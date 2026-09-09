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
	// See pollAndDecide for why 15s, not RFC 8628's more typical 5s.
	minPollInterval = 15 * time.Second
)

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

// checkAndReserve enforces per-user cooldown, the post-failure lockout,
// and the global concurrency cap, atomically with reserving a slot. The
// caller must call release() exactly once when the flow ends (success,
// denial, or error).
func checkAndReserve(user string) (release func(success bool), err error) {
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

	return func(success bool) {
		globalMu.Lock()
		globalInFlight--
		globalMu.Unlock()

		l.mu.Lock()
		if success {
			l.consecutiveFails = 0
		} else {
			l.consecutiveFails++
			if l.consecutiveFails >= cfg.FailureLockoutThreshold {
				l.lockedUntil = time.Now().Add(lockDur)
				l.consecutiveFails = 0
			}
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
			done := fs.Status != "pending"
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
	startedAt       time.Time
	cancelled       bool
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
	prior.mu.Lock()
	if prior.Status == "pending" {
		prior.cancelled = true
	}
	prior.mu.Unlock()
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
	log.Printf("sddm-authelia-passkey broker listening on %s (allowed users: %v)", listenAddr, allowedUsersList())
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

// userLookup is a var so tests can stub it without needing real system accounts.
var userLookup = func(name string) (*user.User, error) { return user.Lookup(name) }

func allowedUsersList() []string {
	out := make([]string, 0, len(cfg.AllowedUsers))
	for u := range cfg.AllowedUsers {
		out = append(out, u)
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
	if !cfg.AllowedUsers[username] {
		// Deliberately do not distinguish "wrong user" from any other
		// failure in the response body - avoid username enumeration.
		http.Error(w, "not permitted", http.StatusForbidden)
		return
	}

	// Re-resolve the account fresh via NSS for every flow, not just once
	// at broker startup: if the account was deleted and recreated (e.g.
	// UID reuse/rename) between startup and this request, the UID we
	// bind into the marker below must reflect the *current* account, not
	// a stale one - this is what lets PAM detect and reject a marker
	// minted for an account that no longer exists in its original form.
	localUser, err := userLookup(username)
	if err != nil {
		log.Printf("session start: NSS lookup failed for allowed user %q: %v", username, err)
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
	fs := &flowState{Status: "pending", Username: username, UID: localUser.Uid, startedAt: time.Now()}
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
		release(false)
		writeJSON(w, map[string]string{"session_id": sessionID})
		return
	}

	verURI, err := validateVerificationURI(dev.VerificationURIComplete, cfg.AllowedVerificationHost, cfg.DevInsecureHTTP)
	if err != nil {
		fs.mu.Lock()
		fs.Status, fs.Error = "error", "server returned an unexpected verification URL"
		fs.mu.Unlock()
		log.Printf("session %s: REJECTED verification_uri_complete: %v", sessionID, err)
		release(false)
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
	fs.mu.Lock()
	if fs.Status == "pending" {
		fs.cancelled = true
	}
	fs.mu.Unlock()
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

func pollAndDecide(sessionID string, fs *flowState, dev *deviceAuthResponse, username string, release func(bool)) {
	defer func() {
		fs.mu.Lock()
		success := fs.Status == "approved"
		fs.mu.Unlock()
		release(success)
	}()
	interval := time.Duration(dev.Interval) * time.Second
	if interval < minPollInterval {
		// Authelia's default server.endpoints.rate_limits.openid_connect_token
		// allows at most 50 requests per 10 minutes (the tightest of its
		// stacked buckets); polling faster than that average rate over a
		// full wait can exceed it purely through normal RFC 8628 polling,
		// with nobody ever retrying anything. 15s keeps every bucket
		// (1min/30, 2min/40, 10min/50, 1h/100) comfortably unreachable by
		// polling alone, without touching Authelia's own rate-limit config.
		interval = minPollInterval
	}
	deadline := time.Now().Add(time.Duration(dev.ExpiresIn) * time.Second)
	if time.Until(deadline) > maxFlowAge {
		deadline = time.Now().Add(maxFlowAge)
	}

	// Bounded retry for genuinely ambiguous/malformed responses only -
	// authorization_pending and slow_down (spec-defined or rate-limit)
	// never increment this and may legitimately repeat for the whole
	// flow lifetime. This prevents a real, persistent backend problem
	// (a 5xx, a broken proxy) from silently showing "waiting" to the
	// user for the full maxFlowAge instead of surfacing as an error.
	const maxConsecutiveAmbiguous = 8
	consecutiveAmbiguous := 0

	for time.Now().Before(deadline) {
		time.Sleep(interval)

		fs.mu.Lock()
		cancelled := fs.cancelled
		fs.mu.Unlock()
		if cancelled {
			log.Printf("session %s: superseded by a newer flow for %s, stopping", sessionID, username)
			return
		}

		tok, status, outcome, err := pollToken(dev.DeviceCode)
		if err != nil {
			log.Printf("session %s: token poll error: %v", sessionID, err)
			consecutiveAmbiguous++
			if consecutiveAmbiguous >= maxConsecutiveAmbiguous {
				fail(fs, "temporarily_unavailable")
				log.Printf("session %s: giving up after %d consecutive poll errors", sessionID, consecutiveAmbiguous)
				return
			}
			continue
		}

		switch outcome {
		case outcomeRateLimit:
			// See pollToken: does not count toward consecutiveAmbiguous.
			interval += 5 * time.Second
			continue
		case outcomeAmbiguous:
			consecutiveAmbiguous++
			log.Printf("session %s: ambiguous poll response (%d/%d)", sessionID, consecutiveAmbiguous, maxConsecutiveAmbiguous)
			if consecutiveAmbiguous >= maxConsecutiveAmbiguous {
				fail(fs, "temporarily_unavailable")
				log.Printf("session %s: giving up after %d consecutive ambiguous responses", sessionID, consecutiveAmbiguous)
				return
			}
			continue
		case outcomeOAuth:
			consecutiveAmbiguous = 0
			switch status {
			case "authorization_pending":
				continue
			case "slow_down":
				// RFC 8628 6.1.
				interval += 5 * time.Second
				continue
			default:
				fail(fs, "device flow failed: "+status)
				return
			}
		case outcomeOK:
			gotUser, err := verifyUserinfo(tok)
			if err != nil {
				fail(fs, "userinfo verification failed")
				log.Printf("session %s: userinfo error: %v", sessionID, err)
				return
			}
			if gotUser != username {
				fail(fs, "username mismatch")
				log.Printf("session %s: SECURITY: token username %q != requested %q", sessionID, gotUser, username)
				return
			}
			writeApprovalMarker(username, fs.UID)
			fs.mu.Lock()
			fs.Status = "approved"
			fs.mu.Unlock()
			log.Printf("session %s: approved for user %s", sessionID, username)
			return
		}
	}
	fail(fs, "expired")
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

func pollToken(deviceCode string) (accessToken string, oauthErr string, outcome pollOutcome, err error) {
	form := url.Values{
		"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		"device_code": {deviceCode},
		"client_id":   {cfg.OIDCClientID},
	}
	resp, err := http.PostForm(cfg.AutheliaBaseURL+"/api/oidc/token", form)
	if err != nil {
		return "", "", outcomeAmbiguous, err
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
		io.Copy(io.Discard, resp.Body)
		return "", "slow_down", outcomeRateLimit, nil
	}
	var t tokenResponse
	if decodeErr := json.NewDecoder(resp.Body).Decode(&t); decodeErr != nil {
		// Non-JSON body on a non-rate-limit response: a genuinely
		// unexpected intermediary/server error (e.g. a proxy's HTML error
		// page, a 5xx), not a spec-defined device-flow outcome. Bounded
		// retry only - see pollAndDecide.
		return "", "", outcomeAmbiguous, nil
	}
	if resp.StatusCode != http.StatusOK {
		if t.Error == "" {
			// Well-formed JSON, non-200, but no recognizable OAuth error
			// code: same reasoning as above, bounded retry only.
			return "", "", outcomeAmbiguous, nil
		}
		return "", t.Error, outcomeOAuth, nil
	}
	return t.AccessToken, "", outcomeOK, nil
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

func fail(fs *flowState, reason string) {
	fs.mu.Lock()
	fs.Status, fs.Error = "denied", reason
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
