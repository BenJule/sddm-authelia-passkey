// broker performs the Authelia OAuth2 Device Authorization flow
// (RFC 8628) out of band from SDDM/PAM, so SDDM never needs to understand
// a multi-step PAM conversation (SDDM's PAM service name is hardcoded per
// login type - see docs/architecture.md - ruling out a per-login-type PAM
// service; sddm/sddm#2098 tracks native multi-step PAM support and remains
// open).
//
// Responsibility split (SDDM stays the ONLY display manager, PAM stays the
// ONLY authentication authority):
//   - This daemon talks to Authelia, renders the QR to a PNG file, decides
//     pass/fail based on Authelia's own response. It NEVER talks to PAM
//     and never runs SDDM's login itself.
//   - src/pam (pam_authelia_passkey.so) is the ONLY thing that turns this
//     daemon's result into a PAM auth decision, and it does so by
//     consuming a root-owned, single-use, short-TTL approval marker file -
//     never by trusting this daemon's HTTP API directly.
//   - The HTTP API is bound to 127.0.0.1 only and is NOT the trust
//     boundary for authentication; the root-owned marker file is.
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/user"
	"strconv"
	"strings"
	"sync"
	"time"

	qrcode "github.com/skip2/go-qrcode"
)

const (
	configPath = "/etc/sddm-authelia-passkey/config.conf"
	markerDir  = "/run/sddm-authelia-passkey"
	qrDir      = "/run/sddm-authelia-passkey/qr"
	listenAddr = "127.0.0.1:7899"
	maxFlowAge = 10 * time.Minute
)

// minPollInterval is a var (not const) solely so tests can shrink it to
// exercise pollAndDecide's real multi-iteration loop in milliseconds
// instead of tens of seconds - production code never assigns it.
//
// See pollAndDecide for why 15s, not RFC 8628's more typical 5s.
var minPollInterval = 15 * time.Second

var cfg Config

type userLimiter struct {
	mu               sync.Mutex
	lastStart        time.Time
	consecutiveFails int
	lockedUntil      time.Time
}

var (
	limitersMu     sync.Mutex
	limiters       = map[string]*userLimiter{}
	globalMu       sync.Mutex
	globalInFlight int
)

func limiterFor(user string) *userLimiter {
	limitersMu.Lock()
	defer limitersMu.Unlock()
	l, ok := limiters[user]
	if !ok {
		l = &userLimiter{}
		limiters[user] = l
	}
	return l
}

type releaseOutcome uint8

const (
	releaseNeutral releaseOutcome = iota
	releaseSuccess
	releaseAuthFailure
)

// checkAndReserve enforces per-user cooldown, the post-failure lockout,
// and the global concurrency cap, atomically with reserving a slot. The
// caller must call release() exactly once. Only a genuine authentication
// denial increments the failure-lockout counter. Cancellation, expiry,
// upstream throttling and infrastructure errors are neutral.
func checkAndReserve(user string) (release func(releaseOutcome), err error) {
	l := limiterFor(user)
	cooldown := time.Duration(cfg.UserCooldownSeconds) * time.Second
	lockDur := time.Duration(cfg.FailureLockoutSeconds) * time.Second

	l.mu.Lock()
	now := time.Now()
	if now.Before(l.lockedUntil) {
		l.mu.Unlock()
		return nil, fmt.Errorf("locked out until %s after repeated failures", l.lockedUntil.Format(time.RFC3339))
	}
	if now.Sub(l.lastStart) < cooldown {
		l.mu.Unlock()
		return nil, fmt.Errorf("cooldown active, retry after %s", l.lastStart.Add(cooldown).Format(time.RFC3339))
	}
	l.lastStart = now
	l.mu.Unlock()

	globalMu.Lock()
	if globalInFlight >= cfg.MaxParallelFlows {
		globalMu.Unlock()
		return nil, fmt.Errorf("too many concurrent device flows (%d)", cfg.MaxParallelFlows)
	}
	globalInFlight++
	globalMu.Unlock()

	return func(outcome releaseOutcome) {
		globalMu.Lock()
		globalInFlight--
		globalMu.Unlock()

		l.mu.Lock()
		switch outcome {
		case releaseSuccess:
			l.consecutiveFails = 0
		case releaseAuthFailure:
			l.consecutiveFails++
			if l.consecutiveFails >= cfg.FailureLockoutThreshold {
				l.lockedUntil = time.Now().Add(lockDur)
				l.consecutiveFails = 0
			}
		case releaseNeutral:
			// Preserve earlier genuine auth failures, but do not manufacture
			// a new failure from cancellation/expiry/infrastructure.
		}
		l.mu.Unlock()
	}, nil
}

// cleanupStaleFlows periodically drops finished/aged-out flow state so
// the in-memory map doesn't grow unbounded over the daemon's lifetime.
func cleanupStaleFlows() {
	for {
		time.Sleep(time.Minute)
		cutoff := time.Now().Add(-maxFlowAge - time.Minute)
		flowsMu.Lock()
		for id, fs := range flows {
			fs.mu.Lock()
			done := fs.Status != "pending" || fs.cancelled
			fs.mu.Unlock()
			if done && fs.startedAt.Before(cutoff) {
				delete(flows, id)
			}
		}
		flowsMu.Unlock()
	}
}

type flowState struct {
	mu       sync.Mutex
	Status   string `json:"status"` // pending|approved|denied|expired|error
	Username string `json:"username,omitempty"`
	// UID is resolved via NSS once, at flow start, and never re-derived
	// from the username string again for the rest of this flow's
	// lifetime - it is the immutable target-account binding a matching
	// OIDC identity gets checked against, and what's embedded in the
	// approval marker for PAM to cross-check at consumption time.
	UID             string `json:"-"`
	UserCode        string `json:"user_code,omitempty"`
	VerificationURI string `json:"verification_uri_complete,omitempty"`
	QRPath          string `json:"qr_path,omitempty"`
	Error           string `json:"error,omitempty"`
	// RateLimited/RetryAfterSeconds are pure UX/diagnostic hints, never
	// an authentication decision: Authelia's own token-endpoint rate
	// limiter (independent of the device flow's own RFC 8628 state) can
	// reject a poll while the flow is still genuinely pending. Without
	// these, the theme has no way to tell "waiting on the user" apart
	// from "waiting on Authelia's rate limiter" and would show a
	// misleading spinner for the flow's whole remaining lifetime.
	RateLimited       bool `json:"rate_limited,omitempty"`
	RetryAfterSeconds int  `json:"retry_after_seconds,omitempty"`
	startedAt         time.Time
	cancelled         bool
	cancelCh          chan struct{}
	cancelOnce        sync.Once
}

var (
	flowsMu sync.Mutex
	flows   = map[string]*flowState{}
	// lastSessionForUser lets a new /start for a user that already has an
	// unfinished flow supersede it immediately, instead of leaving the old
	// flow's pollAndDecide goroutine to hold a global concurrency slot
	// for up to maxFlowAge before it naturally expires and releases it.
	lastSessionForUser = map[string]string{}
)

// supersedePriorFlow marks any still-pending flow this user previously
// started as cancelled, so its poll loop exits (and releases its
// concurrency slot) on its next iteration instead of waiting out
// maxFlowAge. Safe to call even if there is no prior flow.
func supersedePriorFlow(username string) {
	flowsMu.Lock()
	priorID, ok := lastSessionForUser[username]
	flowsMu.Unlock()
	if !ok {
		return
	}
	flowsMu.Lock()
	prior, ok := flows[priorID]
	flowsMu.Unlock()
	if !ok {
		return
	}
	markPendingFlowCancelled(prior)
}

func markPendingFlowCancelled(fs *flowState) bool {
	fs.mu.Lock()
	if fs.Status != "pending" || fs.cancelled {
		fs.mu.Unlock()
		return false
	}
	fs.cancelled = true
	cancelCh := fs.cancelCh
	fs.mu.Unlock()

	if cancelCh != nil {
		fs.cancelOnce.Do(func() { close(cancelCh) })
	}
	return true
}

func main() {
	if os.Geteuid() != 0 {
		log.Fatal("sddm-authelia-passkey broker must run as root (writes root-owned approval markers)")
	}
	var err error
	cfg, err = LoadConfig(configPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	for user := range cfg.AllowedUsers {
		if _, lookupErr := userLookup(user); lookupErr != nil {
			log.Fatalf("allowed_users: local account %q does not exist (NSS lookup failed): %v", user, lookupErr)
		}
	}

	for _, d := range []string{markerDir, qrDir} {
		if err := os.MkdirAll(d, 0700); err != nil {
			log.Fatalf("mkdir %s: %v", d, err)
		}
	}
	os.Chmod(qrDir, 0755) // QR PNGs are public data, greeter must be able to read them

	go cleanupStaleFlows()

	mux := http.NewServeMux()
	mux.HandleFunc("/start", handleStart)
	mux.HandleFunc("/status", handleStatus)
	mux.HandleFunc("/cancel", handleCancel)
	if cfg.AccountSource == "nss" {
		log.Printf("sddm-authelia-passkey broker listening on %s (account_source=nss, minimum_uid=%d, allowed_groups=%v, extra allowed_users=%v)",
			listenAddr, cfg.MinimumUID, allowedGroupsList(), allowedUsersList())
	} else {
		log.Printf("sddm-authelia-passkey broker listening on %s (allowed users: %v)", listenAddr, allowedUsersList())
	}
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

// userLookup is a var so tests can stub it without needing real system accounts.
var userLookup = func(name string) (*user.User, error) { return user.Lookup(name) }

// groupIDsForUser is a var so tests can stub it without needing real
// system groups. In production this is *user.User.GroupIds(), which (this
// binary is cgo-enabled, see debian/rules) resolves via the same NSS path
// as getpwnam/getgrouplist - local /etc/group or, on a host with SSSD/
// nss-ldap configured in nsswitch.conf, Samba AD/OpenLDAP/FreeIPA group
// membership. This broker never speaks LDAP itself.
var groupIDsForUser = func(u *user.User) ([]string, error) { return u.GroupIds() }

// lookupGroupName is a var so tests can stub it the same way.
var lookupGroupName = func(gid string) (string, error) {
	g, err := user.LookupGroupId(gid)
	if err != nil {
		return "", err
	}
	return g.Name, nil
}

// authorizeAccount is the single place that decides whether a requested
// username may start a flow at all, independent of the later
// AUTHENTICATED_AUTHELIA_USER == REQUESTED_LOCAL_USER identity-match check
// in pollAndDecide (see docs/architecture.md) - this only answers "is this
// local/NSS-resolved account even eligible", never anything about who
// approves it later.
//
//   - AccountSource "local": unchanged from v0.1-v0.4 - username must be a
//     literal entry in AllowedUsers, nothing else is checked.
//   - AccountSource "nss": any account NSS can resolve is eligible,
//     provided it isn't root (always rejected, UID or name), isn't in
//     DenyUsers, has UID >= MinimumUID, and - if AllowedGroups is
//     non-empty - is a member of at least one of them. AllowedUsers, if
//     also non-empty, is then an *additional* allowlist on top of that,
//     not a replacement for it.
//
// Fails closed: any NSS lookup error (lookup itself, or group resolution)
// is treated as "not authorized", never as "assume yes"/"assume no
// restriction".
func authorizeAccount(username string) (*user.User, error) {
	if cfg.AccountSource == "local" {
		if !cfg.AllowedUsers[username] {
			return nil, fmt.Errorf("not in allowed_users")
		}
		return userLookup(username)
	}

	u, err := userLookup(username)
	if err != nil {
		return nil, fmt.Errorf("NSS lookup failed: %w", err)
	}

	uid, err := strconv.Atoi(u.Uid)
	if err != nil {
		return nil, fmt.Errorf("account has a non-numeric UID: %q", u.Uid)
	}
	if uid == 0 || username == "root" {
		return nil, fmt.Errorf("root is never permitted")
	}
	if cfg.DenyUsers[username] {
		return nil, fmt.Errorf("user is explicitly denied")
	}
	if uid < cfg.MinimumUID {
		return nil, fmt.Errorf("uid %d is below minimum_uid %d", uid, cfg.MinimumUID)
	}

	if len(cfg.AllowedGroups) > 0 {
		gids, err := groupIDsForUser(u)
		if err != nil {
			return nil, fmt.Errorf("group membership lookup failed: %w", err)
		}
		matched := false
		for _, gid := range gids {
			name, err := lookupGroupName(gid)
			if err != nil {
				// A single unresolvable GID (stale/orphaned group) is not
				// itself fatal - other GIDs may still resolve and match -
				// but it is never silently treated as a match.
				continue
			}
			if cfg.AllowedGroups[name] {
				matched = true
				break
			}
		}
		if !matched {
			return nil, fmt.Errorf("account is not a member of any allowed_groups")
		}
	}

	if len(cfg.AllowedUsers) > 0 && !cfg.AllowedUsers[username] {
		return nil, fmt.Errorf("not in allowed_users")
	}

	return u, nil
}

func allowedUsersList() []string {
	out := make([]string, 0, len(cfg.AllowedUsers))
	for u := range cfg.AllowedUsers {
		out = append(out, u)
	}
	return out
}

func allowedGroupsList() []string {
	out := make([]string, 0, len(cfg.AllowedGroups))
	for g := range cfg.AllowedGroups {
		out = append(out, g)
	}
	return out
}

func handleStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	username := r.URL.Query().Get("username")
	if username == "" && len(cfg.AllowedUsers) == 1 {
		// UX convenience: when there is exactly one allowed account, the
		// greeter can start a flow without first asking for a username.
		// Never guesses when there is more than one candidate.
		for u := range cfg.AllowedUsers {
			username = u
		}
	}
	// authorizeAccount re-resolves the account fresh via NSS for every
	// flow, not just once at broker startup (or not at all, in "nss"
	// mode): if the account was deleted and recreated (e.g. UID reuse/
	// rename) between startup and this request, the UID we bind into the
	// marker below must reflect the *current* account, not a stale one -
	// this is what lets PAM detect and reject a marker minted for an
	// account that no longer exists in its original form.
	localUser, err := authorizeAccount(username)
	if err != nil {
		// Deliberately do not distinguish the many possible reasons (not
		// allowlisted, unknown to NSS, root, denied, below minimum_uid,
		// wrong/no group) in the response body - avoid both username
		// enumeration and leaking which specific policy rule fired.
		log.Printf("session start: %q not authorized: %v", username, err)
		http.Error(w, "not permitted", http.StatusForbidden)
		return
	}

	release, err := checkAndReserve(username)
	if err != nil {
		log.Printf("rate limit: %s: %v", username, err)
		http.Error(w, "try again later", http.StatusTooManyRequests)
		return
	}

	supersedePriorFlow(username)

	sessionID := randomHex(16)
	fs := &flowState{Status: "pending", Username: username, UID: localUser.Uid, startedAt: time.Now(), cancelCh: make(chan struct{})}
	flowsMu.Lock()
	flows[sessionID] = fs
	lastSessionForUser[username] = sessionID
	flowsMu.Unlock()

	dev, err := deviceAuthorize()
	if err != nil {
		fs.mu.Lock()
		fs.Status, fs.Error = "error", "device authorization request failed"
		fs.mu.Unlock()
		log.Printf("session %s: device authorize failed: %v", sessionID, err)
		release(releaseNeutral)
		writeJSON(w, map[string]string{"session_id": sessionID})
		return
	}

	verURI, err := validateVerificationURI(dev.VerificationURIComplete, cfg.AllowedVerificationHost, cfg.DevInsecureHTTP)
	if err != nil {
		fs.mu.Lock()
		fs.Status, fs.Error = "error", "server returned an unexpected verification URL"
		fs.mu.Unlock()
		log.Printf("session %s: REJECTED verification_uri_complete: %v", sessionID, err)
		release(releaseNeutral)
		writeJSON(w, map[string]string{"session_id": sessionID})
		return
	}

	qrPath := fmt.Sprintf("%s/%s.png", qrDir, sessionID)
	if err := writeQR(verURI, qrPath); err != nil {
		log.Printf("session %s: QR render failed: %v", sessionID, err)
		// Non-fatal: verification_uri_complete/user_code text fallback
		// still lets the user complete the flow by typing the URL.
	}

	fs.mu.Lock()
	fs.UserCode = dev.UserCode
	fs.VerificationURI = verURI
	fs.QRPath = qrPath
	fs.mu.Unlock()

	go pollAndDecide(sessionID, fs, dev, username, release)

	writeJSON(w, map[string]string{"session_id": sessionID})
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("session_id")
	flowsMu.Lock()
	fs, ok := flows[id]
	flowsMu.Unlock()
	if !ok {
		http.NotFound(w, r)
		return
	}
	fs.mu.Lock()
	defer fs.mu.Unlock()
	writeJSON(w, fs)
}

// handleCancel is the UI's explicit "Abbrechen"/panel-close path. Unlike
// supersedePriorFlow (defense-in-depth for a new /start superseding an
// old, possibly-abandoned one), this is the normal, intentional way a
// flow ends without ever reaching a terminal status - it stops the poll
// loop on its next iteration and frees the flow's concurrency slot
// immediately rather than waiting out its natural deadline.
func handleCancel(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	id := r.URL.Query().Get("session_id")
	flowsMu.Lock()
	fs, ok := flows[id]
	flowsMu.Unlock()
	if !ok {
		http.NotFound(w, r)
		return
	}
	markPendingFlowCancelled(fs)
	w.WriteHeader(http.StatusOK)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		log.Fatalf("rand.Read: %v", err)
	}
	return hex.EncodeToString(b)
}

func writeQR(content, path string) error {
	q, err := qrcode.New(content, qrcode.Medium)
	if err != nil {
		return err
	}
	png, err := q.PNG(0) // 0 = library default size
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, png, 0644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// --- Authelia OAuth2 Device Authorization client -----------------------
//
// Independently implemented from the publicly documented RFC 8628 flow,
// rather than importing authelia/pam's Go client, to keep this project's
// own licensing/dependency footprint minimal and auditable (authelia/pam
// is itself Apache-2.0, so this is a design choice, not a compatibility
// requirement).

type deviceAuthResponse struct {
	DeviceCode              string `json:"device_code"`
	UserCode                string `json:"user_code"`
	VerificationURI         string `json:"verification_uri"`
	VerificationURIComplete string `json:"verification_uri_complete"`
	ExpiresIn               int    `json:"expires_in"`
	Interval                int    `json:"interval"`
}

func deviceAuthorize() (*deviceAuthResponse, error) {
	form := url.Values{
		"client_id": {cfg.OIDCClientID},
		"scope":     {cfg.OIDCScopes},
	}
	resp, err := http.PostForm(cfg.AutheliaBaseURL+"/api/oidc/device-authorization", form)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("device-authorization: HTTP %d: %s", resp.StatusCode, body)
	}
	var d deviceAuthResponse
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		return nil, err
	}
	return &d, nil
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	Error       string `json:"error"`
}

func pollAndDecide(sessionID string, fs *flowState, dev *deviceAuthResponse, username string, release func(releaseOutcome)) {
	releaseResult := releaseNeutral
	defer func() { release(releaseResult) }()

	normalInterval := time.Duration(dev.Interval) * time.Second
	if normalInterval < minPollInterval {
		normalInterval = minPollInterval
	}
	interval := normalInterval

	deadline := time.Now().Add(time.Duration(dev.ExpiresIn) * time.Second)
	if time.Until(deadline) > maxFlowAge {
		deadline = time.Now().Add(maxFlowAge)
	}

	const maxConsecutiveAmbiguous = 8
	consecutiveAmbiguous := 0
	loggedRateLimit := false
	loggedRetryAfter := 0

	for {
		fs.mu.Lock()
		cancelled := fs.cancelled
		cancelCh := fs.cancelCh
		fs.mu.Unlock()
		if cancelled {
			log.Printf("session %s: cancelled/superseded for %s, stopping", sessionID, username)
			return
		}

		remaining := time.Until(deadline)
		if remaining <= 0 {
			errorFlow(fs, "expired")
			return
		}

		waitFor := interval
		if waitFor > remaining {
			waitFor = remaining
		}

		timer := time.NewTimer(waitFor)
		if cancelCh != nil {
			select {
			case <-timer.C:
			case <-cancelCh:
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				log.Printf("session %s: cancelled/superseded for %s during poll wait, stopping", sessionID, username)
				return
			}
		} else {
			<-timer.C
		}

		fs.mu.Lock()
		cancelled = fs.cancelled
		fs.mu.Unlock()
		if cancelled {
			return
		}
		if !time.Now().Before(deadline) {
			errorFlow(fs, "expired")
			return
		}

		tok, status, outcome, retryAfter, err := pollToken(dev.DeviceCode)
		if err != nil {
			log.Printf("session %s: token poll error: %v", sessionID, err)
			consecutiveAmbiguous++
			if consecutiveAmbiguous >= maxConsecutiveAmbiguous {
				errorFlow(fs, "temporarily_unavailable")
				return
			}
			continue
		}

		if outcome != outcomeRateLimit {
			fs.mu.Lock()
			wasRateLimited := fs.RateLimited
			fs.RateLimited = false
			fs.RetryAfterSeconds = 0
			fs.mu.Unlock()
			if wasRateLimited {
				interval = normalInterval
				loggedRateLimit, loggedRetryAfter = false, 0
				log.Printf("session %s: upstream token endpoint recovered from rate limit", sessionID)
			}
		}

		switch outcome {
		case outcomeRateLimit:
			effectiveRetry, newInterval, giveUp := rateLimitDecision(retryAfter, interval, time.Until(deadline))
			if giveUp {
				errorFlow(fs, "rate_limited")
				log.Printf("session %s: giving up, rate-limit backoff (%ds) does not fit remaining flow lifetime",
					sessionID, effectiveRetry)
				return
			}
			fs.mu.Lock()
			fs.RateLimited = true
			fs.RetryAfterSeconds = effectiveRetry
			fs.mu.Unlock()
			if !loggedRateLimit || absInt(effectiveRetry-loggedRetryAfter) > loggedRetryAfter/2+5 {
				log.Printf("session %s: upstream token endpoint rate limited, retry_after=%ds", sessionID, effectiveRetry)
				loggedRateLimit, loggedRetryAfter = true, effectiveRetry
			}
			interval = newInterval
			continue

		case outcomeAmbiguous:
			consecutiveAmbiguous++
			if consecutiveAmbiguous >= maxConsecutiveAmbiguous {
				errorFlow(fs, "temporarily_unavailable")
				return
			}
			continue

		case outcomeOAuth:
			consecutiveAmbiguous = 0
			switch status {
			case "authorization_pending":
				continue
			case "slow_down":
				normalInterval += 5 * time.Second
				interval = normalInterval
				continue
			case "access_denied":
				denyFlow(fs, "device flow failed: access_denied")
				releaseResult = releaseAuthFailure
				return
			case "expired_token":
				errorFlow(fs, "expired")
				return
			default:
				errorFlow(fs, "device flow failed: "+status)
				return
			}

		case outcomeOK:
			gotUser, err := verifyUserinfo(tok)
			if err != nil {
				errorFlow(fs, "userinfo verification failed")
				log.Printf("session %s: userinfo error: %v", sessionID, err)
				return
			}
			if gotUser != username {
				denyFlow(fs, "username mismatch")
				releaseResult = releaseAuthFailure
				log.Printf("session %s: SECURITY: token username %q != requested %q", sessionID, gotUser, username)
				return
			}
			writeApprovalMarker(username, fs.UID)
			fs.mu.Lock()
			fs.Status = "approved"
			fs.mu.Unlock()
			releaseResult = releaseSuccess
			log.Printf("session %s: approved for user %s", sessionID, username)
			return
		}
	}
}

// pollTokenResult distinguishes genuinely retryable conditions (rate
// limited by an intermediary, or a single ambiguous/malformed response)
// from real, spec-defined OAuth device-flow outcomes. Only "ambiguous"
// is subject to pollAndDecide's bounded consecutive-failure counter -
// authorization_pending/slow_down can legitimately repeat for the whole
// flow lifetime, per RFC 8628.
type pollOutcome int

const (
	outcomeOK        pollOutcome = iota // AccessToken set
	outcomeOAuth                        // oauthErr set to a real RFC 8628 error code
	outcomeRateLimit                    // HTTP 429 from an intermediary, not a device-flow decision
	outcomeAmbiguous                    // non-200 with no decodable OAuth error - not a spec-defined outcome
)

// maxParsableRetryAfter bounds what pollToken will accept out of a
// Retry-After header as a sanity ceiling against a malformed or
// deliberately huge upstream value - not a functional limit (the flow's
// own remaining lifetime is what actually decides whether a wait is
// worth continuing for, in pollAndDecide).
const maxParsableRetryAfter = 24 * time.Hour

// parseRetryAfter parses an RFC 7231 Retry-After header value (either
// delta-seconds or an HTTP-date) relative to now. Returns ok=false for
// anything empty, malformed, non-positive, or past maxParsableRetryAfter -
// callers must fall back to their own safe default rather than trust a
// zero value here.
func parseRetryAfter(header string, now time.Time) (seconds int, ok bool) {
	header = strings.TrimSpace(header)
	if header == "" {
		return 0, false
	}
	if n, err := strconv.Atoi(header); err == nil {
		if n <= 0 || time.Duration(n)*time.Second > maxParsableRetryAfter {
			return 0, false
		}
		return n, true
	}
	if t, err := http.ParseTime(header); err == nil {
		d := t.Sub(now)
		if d <= 0 || d > maxParsableRetryAfter {
			return 0, false
		}
		return int(d.Seconds()), true
	}
	return 0, false
}

func pollToken(deviceCode string) (accessToken string, oauthErr string, outcome pollOutcome, retryAfterSeconds int, err error) {
	form := url.Values{
		"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		"device_code": {deviceCode},
		"client_id":   {cfg.OIDCClientID},
	}
	resp, err := http.PostForm(cfg.AutheliaBaseURL+"/api/oidc/token", form)
	if err != nil {
		return "", "", outcomeAmbiguous, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests {
		// Authelia's own rate-limiter middleware, sitting in front of the
		// OAuth2 handler, rejects the request before it ever produces a
		// device-flow-aware JSON error body. This is a transient condition
		// the client caused by polling too fast for Authelia's separate
		// abuse-prevention limit (independent of the device flow's own
		// `interval`) - back off and keep polling within the SAME flow,
		// exactly like a spec `slow_down`, rather than treating a normal,
		// recoverable rate limit as a terminal failure. Unlike a genuinely
		// ambiguous response, this does NOT count toward the bounded
		// consecutive-failure limit - Authelia's bucket state is out of
		// this flow's control and can legitimately stay active for a long
		// time without indicating anything is actually broken.
		ra, _ := parseRetryAfter(resp.Header.Get("Retry-After"), time.Now())
		io.Copy(io.Discard, resp.Body)
		return "", "slow_down", outcomeRateLimit, ra, nil
	}
	var t tokenResponse
	if decodeErr := json.NewDecoder(resp.Body).Decode(&t); decodeErr != nil {
		// Non-JSON body on a non-rate-limit response: a genuinely
		// unexpected intermediary/server error (e.g. a proxy's HTML error
		// page, a 5xx), not a spec-defined device-flow outcome. Bounded
		// retry only - see pollAndDecide.
		return "", "", outcomeAmbiguous, 0, nil
	}
	if resp.StatusCode != http.StatusOK {
		if t.Error == "" {
			// Well-formed JSON, non-200, but no recognizable OAuth error
			// code: same reasoning as above, bounded retry only.
			return "", "", outcomeAmbiguous, 0, nil
		}
		return "", t.Error, outcomeOAuth, 0, nil
	}
	return t.AccessToken, "", outcomeOK, 0, nil
}

func verifyUserinfo(accessToken string) (string, error) {
	req, _ := http.NewRequest(http.MethodGet, cfg.AutheliaBaseURL+"/api/oidc/userinfo", nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("userinfo: HTTP %d: %s", resp.StatusCode, body)
	}
	var claims map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&claims); err != nil {
		return "", err
	}
	u, _ := claims["authelia.pam.username"].(string)
	if u == "" {
		return "", fmt.Errorf("authelia.pam.username claim missing from userinfo response")
	}
	return u, nil
}

// rateLimitDecision is the pure decision logic for a single HTTP 429 from
// the token endpoint: given what Authelia told us to wait (retryAfter,
// possibly 0 if it sent no Retry-After header) and how much longer this
// flow can still run (remaining), decide whether continuing to wait is
// still worthwhile, and what the next poll interval should be. No I/O,
// no locking - kept separate from pollAndDecide so this decision is
// directly unit-testable without real sleeps.
func rateLimitDecision(retryAfter int, interval, remaining time.Duration) (effectiveRetry int, newInterval time.Duration, giveUp bool) {
	newInterval = interval
	if retryAfter > 0 {
		serverWait := time.Duration(retryAfter) * time.Second
		if serverWait > newInterval {
			newInterval = serverWait
		}
	} else {
		newInterval += 5 * time.Second
	}

	effectiveRetry = int(newInterval / time.Second)
	if newInterval%time.Second != 0 {
		effectiveRetry++
	}
	if effectiveRetry < 1 {
		effectiveRetry = 1
	}

	if newInterval >= remaining {
		return effectiveRetry, newInterval, true
	}
	return effectiveRetry, newInterval, false
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

func denyFlow(fs *flowState, reason string) {
	fs.mu.Lock()
	fs.Status, fs.Error = "denied", reason
	fs.mu.Unlock()
}

func errorFlow(fs *flowState, reason string) {
	fs.mu.Lock()
	fs.Status, fs.Error = "error", reason
	fs.mu.Unlock()
}

// writeApprovalMarker is the ONLY thing that can make the PAM module
// succeed on the smartphone/passkey path. Written root:root 0600, short TTL enforced
// by the PAM module, which also deletes it on read - so a marker can
// grant at most one login, within a short window, no matter how this
// HTTP API is otherwise reached from localhost.
func writeApprovalMarker(username, uid string) {
	path := fmt.Sprintf("%s/approved-%s", markerDir, sanitizeUsername(username))
	// v2: PAM re-resolves the requesting account's UID via NSS at
	// consumption time and compares it against UID= below - this is what
	// makes a marker minted for an account that has since been deleted
	// and recreated (same username, different UID) fail closed instead
	// of silently trusting the username string alone.
	token := "VERSION=2\n" +
		"USERNAME=" + sanitizeUsername(username) + "\n" +
		"UID=" + uid + "\n" +
		"NONCE=" + randomHex(32) + "\n" +
		"APPROVED_AT=" + time.Now().UTC().Format(time.RFC3339) + "\n"
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(token), 0600); err != nil {
		log.Printf("writeApprovalMarker: %v", err)
		return
	}
	os.Chmod(tmp, 0600)
	os.Rename(tmp, path)
}

func sanitizeUsername(u string) string {
	// Defense in depth: never let a username string reach a filesystem
	// path unfiltered, even though it was already checked against
	// cfg.AllowedUsers above.
	var b strings.Builder
	for _, r := range u {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// validateVerificationURI enforces https-only (unless devInsecureHTTP),
// a pinned host, the exact expected Authelia consent path, and only a
// user_code query parameter, with bounded length and no control
// characters.
func validateVerificationURI(raw, wantHost string, devInsecureHTTP bool) (string, error) {
	if len(raw) == 0 || len(raw) > 512 {
		return "", fmt.Errorf("length %d out of bounds", len(raw))
	}
	if strings.ContainsAny(raw, "\n\r\x00") {
		return "", fmt.Errorf("control characters present")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	wantScheme := "https"
	if devInsecureHTTP {
		wantScheme = "http"
	}
	if u.Scheme != wantScheme {
		return "", fmt.Errorf("scheme %q", u.Scheme)
	}
	if u.Host != wantHost {
		return "", fmt.Errorf("host %q", u.Host)
	}
	if u.Path != "/consent/openid/device-authorization" {
		return "", fmt.Errorf("path %q", u.Path)
	}
	q := u.Query()
	if q.Get("user_code") == "" {
		return "", fmt.Errorf("missing user_code")
	}
	for k := range q {
		if k != "user_code" {
			return "", fmt.Errorf("unexpected query param %q", k)
		}
	}
	return raw, nil
}
