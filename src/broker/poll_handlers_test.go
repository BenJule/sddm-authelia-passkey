package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

// --- pollToken outcome classification (RFC 8628 vs. rate-limit vs.
// genuinely ambiguous) - see the pollOutcome doc comment in main.go for
// why this distinction exists; these are the real bugs found during
// v0.2.0 development. ---------------------------------------------------

func withTokenEndpoint(t *testing.T, handler http.HandlerFunc) func() {
	t.Helper()
	srv := httptest.NewServer(handler)
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	t.Cleanup(func() {
		srv.Close()
		cfg.AutheliaBaseURL = prevBase
	})
	return srv.Close
}

func TestPollToken_OutcomeOK(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-123"})
	})
	tok, oauthErr, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeOK || tok != "tok-123" || oauthErr != "" {
		t.Fatalf("got tok=%q oauthErr=%q outcome=%v err=%v", tok, oauthErr, outcome, err)
	}
}

func TestPollToken_OutcomeOAuth_AuthorizationPending(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(tokenResponse{Error: "authorization_pending"})
	})
	_, oauthErr, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeOAuth || oauthErr != "authorization_pending" {
		t.Fatalf("got oauthErr=%q outcome=%v err=%v", oauthErr, outcome, err)
	}
}

func TestPollToken_OutcomeOAuth_SlowDown(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(tokenResponse{Error: "slow_down"})
	})
	_, oauthErr, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeOAuth || oauthErr != "slow_down" {
		t.Fatalf("got oauthErr=%q outcome=%v err=%v", oauthErr, outcome, err)
	}
}

func TestPollToken_OutcomeOAuth_ExpiredToken(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(tokenResponse{Error: "expired_token"})
	})
	_, oauthErr, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeOAuth || oauthErr != "expired_token" {
		t.Fatalf("got oauthErr=%q outcome=%v err=%v", oauthErr, outcome, err)
	}
}

func TestPollToken_OutcomeRateLimit_429MustNotBeTreatedAsOAuthOrAmbiguous(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
		w.Write([]byte("rate limited"))
	})
	_, oauthErr, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeRateLimit {
		t.Fatalf("got outcome=%v err=%v, want outcomeRateLimit", outcome, err)
	}
	if oauthErr != "slow_down" {
		t.Fatalf("got oauthErr=%q, want slow_down (429 is treated like a spec slow_down)", oauthErr)
	}
}

func TestPollToken_OutcomeAmbiguous_NonJSONBody(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte("<html>502 Bad Gateway</html>"))
	})
	_, _, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeAmbiguous {
		t.Fatalf("got outcome=%v err=%v, want outcomeAmbiguous", outcome, err)
	}
}

func TestPollToken_OutcomeAmbiguous_JSONWithoutErrorCode(t *testing.T) {
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(map[string]string{"message": "internal error"})
	})
	_, _, outcome, err := pollToken("dev-code")
	if err != nil || outcome != outcomeAmbiguous {
		t.Fatalf("got outcome=%v err=%v, want outcomeAmbiguous", outcome, err)
	}
}

func TestPollToken_TransportError(t *testing.T) {
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = "http://127.0.0.1:1" // nothing listens here
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	_, _, _, err := pollToken("dev-code")
	if err == nil {
		t.Fatal("expected a transport error when the endpoint is unreachable")
	}
}

// --- handleCancel --------------------------------------------------------

func resetFlowState(t *testing.T) {
	t.Helper()
	flowsMu.Lock()
	flows = map[string]*flowState{}
	lastSessionForUser = map[string]string{}
	flowsMu.Unlock()
}

func TestHandleCancel_MarksPendingFlowCancelled(t *testing.T) {
	resetFlowState(t)
	fs := &flowState{Status: "pending", Username: "alice"}
	flowsMu.Lock()
	flows["sess-1"] = fs
	flowsMu.Unlock()

	req := httptest.NewRequest(http.MethodPost, "/cancel?session_id=sess-1", nil)
	w := httptest.NewRecorder()
	handleCancel(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	fs.mu.Lock()
	cancelled := fs.cancelled
	fs.mu.Unlock()
	if !cancelled {
		t.Fatal("expected the pending flow to be marked cancelled")
	}
}

func TestHandleCancel_DoesNotTouchFinishedFlow(t *testing.T) {
	resetFlowState(t)
	fs := &flowState{Status: "approved", Username: "alice"}
	flowsMu.Lock()
	flows["sess-2"] = fs
	flowsMu.Unlock()

	req := httptest.NewRequest(http.MethodPost, "/cancel?session_id=sess-2", nil)
	w := httptest.NewRecorder()
	handleCancel(w, req)

	fs.mu.Lock()
	cancelled := fs.cancelled
	fs.mu.Unlock()
	if cancelled {
		t.Fatal("must not cancel a flow that already reached a terminal state")
	}
}

func TestHandleCancel_UnknownSessionIs404(t *testing.T) {
	resetFlowState(t)
	req := httptest.NewRequest(http.MethodPost, "/cancel?session_id=does-not-exist", nil)
	w := httptest.NewRecorder()
	handleCancel(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", w.Code)
	}
}

func TestHandleCancel_RejectsNonPOST(t *testing.T) {
	resetFlowState(t)
	req := httptest.NewRequest(http.MethodGet, "/cancel?session_id=sess-1", nil)
	w := httptest.NewRecorder()
	handleCancel(w, req)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

// --- handleStart: username auto-resolution / rejection -------------------
//
// deviceAuthorize() is deliberately pointed at a server that fails (502)
// for these tests, so handleStart takes its early error-return path
// before ever spawning the pollAndDecide goroutine - the username
// resolution/rejection decision happens before that call either way, and
// this keeps the test synchronous with no lingering background poller.

func withFailingDeviceAuthEndpoint(t *testing.T) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	t.Cleanup(func() {
		srv.Close()
		cfg.AutheliaBaseURL = prevBase
	})
}

func TestHandleStart_SingleAllowedUser_ResolvesWithoutUsernameParam(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true}

	req := httptest.NewRequest(http.MethodPost, "/start", nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}
	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	flowsMu.Lock()
	fs, ok := flows[resp["session_id"]]
	flowsMu.Unlock()
	if !ok {
		t.Fatal("expected a flow to have been created")
	}
	fs.mu.Lock()
	gotUser := fs.Username
	fs.mu.Unlock()
	if gotUser != "alice" {
		t.Fatalf("resolved username = %q, want %q (the sole allowed user)", gotUser, "alice")
	}
}

func TestHandleStart_MultipleAllowedUsers_RejectsWithoutExplicitUsername(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true, "bob": true}

	req := httptest.NewRequest(http.MethodPost, "/start", nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 (must never guess between multiple allowed users)", w.Code)
	}
}

func TestHandleStart_ExplicitWrongUserIsRejected(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true}

	req := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"mallory"}}.Encode(), nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", w.Code)
	}
}

func TestHandleStart_RejectsNonPOST(t *testing.T) {
	resetFlowState(t)
	req := httptest.NewRequest(http.MethodGet, "/start", nil)
	w := httptest.NewRecorder()
	handleStart(w, req)
	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", w.Code)
	}
}

func TestHandleStart_RateLimitedUserGets429(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true}

	req1 := httptest.NewRequest(http.MethodPost, "/start", nil)
	handleStart(httptest.NewRecorder(), req1)

	req2 := httptest.NewRequest(http.MethodPost, "/start", nil)
	w2 := httptest.NewRecorder()
	handleStart(w2, req2)

	if w2.Code != http.StatusTooManyRequests {
		t.Fatalf("status = %d, want 429 (per-user cooldown)", w2.Code)
	}
	if !strings.Contains(w2.Body.String(), "try again") {
		t.Fatalf("body = %q", w2.Body.String())
	}
}
