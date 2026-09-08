// pixel-broker performs the Authelia OAuth2 Device Authorization flow
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
	mu              sync.Mutex
	Status          string `json:"status"` // pending|approved|denied|expired|error
	UserCode        string `json:"user_code,omitempty"`
	VerificationURI string `json:"verification_uri_complete,omitempty"`
	QRPath          string `json:"qr_path,omitempty"`
	Error           string `json:"error,omitempty"`
	startedAt       time.Time
}

var (
	flowsMu sync.Mutex
	flows   = map[string]*flowState{}
)

func main() {
	if os.Geteuid() != 0 {
		log.Fatal("pixel-broker must run as root (writes root-owned approval markers)")
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
	log.Printf("pixel-broker listening on %s (allowed users: %v)", listenAddr, allowedUsersList())
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
	if !cfg.AllowedUsers[username] {
		// Deliberately do not distinguish "wrong user" from any other
		// failure in the response body - avoid username enumeration.
		http.Error(w, "not permitted", http.StatusForbidden)
		return
	}

	release, err := checkAndReserve(username)
	if err != nil {
		log.Printf("rate limit: %s: %v", username, err)
		http.Error(w, "try again later", http.StatusTooManyRequests)
		return
	}

	sessionID := randomHex(16)
	fs := &flowState{Status: "pending", startedAt: time.Now()}
	flowsMu.Lock()
	flows[sessionID] = fs
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
	if interval < 2*time.Second {
		interval = 2 * time.Second
	}
	deadline := time.Now().Add(time.Duration(dev.ExpiresIn) * time.Second)
	if time.Until(deadline) > maxFlowAge {
		deadline = time.Now().Add(maxFlowAge)
	}

	for time.Now().Before(deadline) {
		time.Sleep(interval)
		tok, status, err := pollToken(dev.DeviceCode)
		if err != nil {
			log.Printf("session %s: token poll error: %v", sessionID, err)
			continue
		}
		switch status {
		case "authorization_pending":
			continue
		case "slow_down":
			// RFC 8628 6.1: back off, distinct from a generic HTTP 429 from
			// an intermediate rate limiter, which pollToken also maps to
			// this same branch since the practical remedy is identical.
			interval += 5 * time.Second
			continue
		case "":
			// success
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
			writeApprovalMarker(username)
			fs.mu.Lock()
			fs.Status = "approved"
			fs.mu.Unlock()
			log.Printf("session %s: approved for user %s", sessionID, username)
			return
		default:
			fail(fs, "device flow failed: "+status)
			return
		}
	}
	fail(fs, "expired")
}

func pollToken(deviceCode string) (accessToken string, oauthErr string, err error) {
	form := url.Values{
		"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		"device_code": {deviceCode},
		"client_id":   {cfg.OIDCClientID},
	}
	resp, err := http.PostForm(cfg.AutheliaBaseURL+"/api/oidc/token", form)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	var t tokenResponse
	if decodeErr := json.NewDecoder(resp.Body).Decode(&t); decodeErr != nil {
		if resp.StatusCode == http.StatusTooManyRequests {
			// An intermediary/IdP-side rate limiter without a device-flow-
			// aware JSON body: treat like slow_down rather than an error.
			return "", "slow_down", nil
		}
		return "", "", decodeErr
	}
	if resp.StatusCode != http.StatusOK {
		if t.Error == "" {
			t.Error = "temporarily_unavailable"
		}
		return "", t.Error, nil
	}
	return t.AccessToken, "", nil
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
// succeed on the Pixel path. Written root:root 0600, short TTL enforced
// by the PAM module, which also deletes it on read - so a marker can
// grant at most one login, within a short window, no matter how this
// HTTP API is otherwise reached from localhost.
func writeApprovalMarker(username string) {
	path := fmt.Sprintf("%s/approved-%s", markerDir, sanitizeUsername(username))
	token := randomHex(32) + "\n" + time.Now().UTC().Format(time.RFC3339) + "\n"
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
