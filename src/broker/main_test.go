package main

import (
	"testing"
	"time"
)

const testHost = "idp.example.com"

// --- URI validation ----------------------------------------------------

func TestValidateVerificationURI_Valid(t *testing.T) {
	got, err := validateVerificationURI(
		"https://idp.example.com/consent/openid/device-authorization?user_code=ABCDEFGH",
		testHost, false)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got == "" {
		t.Fatal("expected non-empty result")
	}
}

func TestValidateVerificationURI_WrongScheme(t *testing.T) {
	if _, err := validateVerificationURI("http://idp.example.com/consent/openid/device-authorization?user_code=ABCDEFGH", testHost, false); err == nil {
		t.Fatal("expected rejection of http scheme")
	}
}

func TestValidateVerificationURI_DevInsecureHTTPAllowsHTTP(t *testing.T) {
	if _, err := validateVerificationURI("http://idp.example.com/consent/openid/device-authorization?user_code=ABCDEFGH", testHost, true); err != nil {
		t.Fatalf("dev mode should accept http: %v", err)
	}
	if _, err := validateVerificationURI("https://idp.example.com/consent/openid/device-authorization?user_code=ABCDEFGH", testHost, true); err == nil {
		t.Fatal("dev mode should reject https (scheme must match configured mode exactly)")
	}
}

func TestValidateVerificationURI_WrongHost(t *testing.T) {
	if _, err := validateVerificationURI("https://evil.example.com/consent/openid/device-authorization?user_code=ABCDEFGH", testHost, false); err == nil {
		t.Fatal("expected rejection of unexpected host")
	}
}

func TestValidateVerificationURI_WrongPath(t *testing.T) {
	if _, err := validateVerificationURI("https://idp.example.com/api/oidc/token?user_code=ABCDEFGH", testHost, false); err == nil {
		t.Fatal("expected rejection of unexpected path")
	}
}

func TestValidateVerificationURI_ExtraParam(t *testing.T) {
	if _, err := validateVerificationURI("https://idp.example.com/consent/openid/device-authorization?user_code=ABCDEFGH&evil=1", testHost, false); err == nil {
		t.Fatal("expected rejection of unexpected extra query parameter")
	}
}

func TestValidateVerificationURI_Newline(t *testing.T) {
	if _, err := validateVerificationURI("https://idp.example.com/consent/openid/device-authorization?user_code=AB\nCD", testHost, false); err == nil {
		t.Fatal("expected rejection of embedded newline")
	}
}

func TestValidateVerificationURI_Oversized(t *testing.T) {
	long := "https://idp.example.com/consent/openid/device-authorization?user_code="
	for len(long) < 600 {
		long += "A"
	}
	if _, err := validateVerificationURI(long, testHost, false); err == nil {
		t.Fatal("expected rejection of oversized URI")
	}
}

func TestValidateVerificationURI_MissingUserCode(t *testing.T) {
	if _, err := validateVerificationURI("https://idp.example.com/consent/openid/device-authorization", testHost, false); err == nil {
		t.Fatal("expected rejection of missing user_code")
	}
}

// --- username sanitization (path traversal / injection defense) --------

func TestSanitizeUsername(t *testing.T) {
	cases := map[string]string{
		"alice":              "alice",
		"../../etc/passwd":   "etcpasswd",
		"alice; rm -rf /":    "alicerm-rf",
		"alice\x00root":      "aliceroot",
		"UPPER":              "", // uppercase intentionally not allowed through
		"under_score-dash1":  "under_score-dash1",
	}
	for in, want := range cases {
		got := sanitizeUsername(in)
		if got != want {
			t.Errorf("sanitizeUsername(%q) = %q, want %q", in, got, want)
		}
	}
}

// --- rate limiting -------------------------------------------------------

func resetLimiterState(t *testing.T) {
	t.Helper()
	limitersMu.Lock()
	limiters = map[string]*userLimiter{}
	limitersMu.Unlock()
	globalMu.Lock()
	globalInFlight = 0
	globalMu.Unlock()
	cfg = Config{
		UserCooldownSeconds:     10,
		MaxParallelFlows:        3,
		FailureLockoutThreshold: 3,
		FailureLockoutSeconds:   60,
	}
}

func TestCheckAndReserve_Cooldown(t *testing.T) {
	resetLimiterState(t)

	release, err := checkAndReserve("testuser1")
	if err != nil {
		t.Fatalf("first call should succeed: %v", err)
	}
	release(true)

	if _, err := checkAndReserve("testuser1"); err == nil {
		t.Fatal("expected cooldown to reject immediate second call")
	}
}

func TestCheckAndReserve_GlobalConcurrencyCap(t *testing.T) {
	resetLimiterState(t)

	var releases []func(bool)
	for i := 0; i < cfg.MaxParallelFlows; i++ {
		user := string(rune('a' + i))
		r, err := checkAndReserve(user)
		if err != nil {
			t.Fatalf("call %d should succeed: %v", i, err)
		}
		releases = append(releases, r)
	}
	if _, err := checkAndReserve("one-too-many"); err == nil {
		t.Fatal("expected global concurrency cap to reject")
	}
	for _, r := range releases {
		r(true)
	}
}

func TestCheckAndReserve_FailureLockout(t *testing.T) {
	resetLimiterState(t)
	cooldown := time.Duration(cfg.UserCooldownSeconds) * time.Second

	user := "lockouttest"
	for i := 0; i < cfg.FailureLockoutThreshold; i++ {
		l := limiterFor(user)
		l.mu.Lock()
		l.lastStart = time.Now().Add(-cooldown - time.Second) // bypass cooldown for the test
		l.mu.Unlock()
		release, err := checkAndReserve(user)
		if err != nil {
			t.Fatalf("call %d should succeed: %v", i, err)
		}
		release(false) // simulate denial
	}

	l := limiterFor(user)
	l.mu.Lock()
	l.lastStart = time.Now().Add(-cooldown - time.Second)
	l.mu.Unlock()
	if _, err := checkAndReserve(user); err == nil {
		t.Fatal("expected lockout after repeated failures")
	}
}

// --- flow supersession (releases stuck global concurrency slots) -------

func TestSupersedePriorFlow_MarksOldPendingFlowCancelled(t *testing.T) {
	flowsMu.Lock()
	flows = map[string]*flowState{}
	lastSessionForUser = map[string]string{}
	flowsMu.Unlock()

	old := &flowState{Status: "pending", Username: "alice"}
	flowsMu.Lock()
	flows["old-session"] = old
	lastSessionForUser["alice"] = "old-session"
	flowsMu.Unlock()

	supersedePriorFlow("alice")

	old.mu.Lock()
	cancelled := old.cancelled
	old.mu.Unlock()
	if !cancelled {
		t.Fatal("expected the prior pending flow to be marked cancelled")
	}
}

func TestSupersedePriorFlow_DoesNotTouchFinishedFlow(t *testing.T) {
	flowsMu.Lock()
	flows = map[string]*flowState{}
	lastSessionForUser = map[string]string{}
	flowsMu.Unlock()

	done := &flowState{Status: "approved", Username: "alice"}
	flowsMu.Lock()
	flows["done-session"] = done
	lastSessionForUser["alice"] = "done-session"
	flowsMu.Unlock()

	supersedePriorFlow("alice")

	done.mu.Lock()
	cancelled := done.cancelled
	done.mu.Unlock()
	if cancelled {
		t.Fatal("must not cancel a flow that already reached a terminal state")
	}
}

func TestSupersedePriorFlow_NoPriorSessionIsNoop(t *testing.T) {
	flowsMu.Lock()
	flows = map[string]*flowState{}
	lastSessionForUser = map[string]string{}
	flowsMu.Unlock()

	// Must not panic or block when the user has no prior session at all.
	supersedePriorFlow("nobody-yet")
}
