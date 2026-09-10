package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// --- parseRetryAfter ------------------------------------------------------

func TestParseRetryAfter_SecondsForm(t *testing.T) {
	s, ok := parseRetryAfter("120", time.Now())
	if !ok || s != 120 {
		t.Fatalf("got (%d, %v), want (120, true)", s, ok)
	}
}

func TestParseRetryAfter_HTTPDateForm(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	future := now.Add(90 * time.Second)
	s, ok := parseRetryAfter(future.Format(http.TimeFormat), now)
	if !ok || s < 89 || s > 90 {
		t.Fatalf("got (%d, %v), want (~90, true)", s, ok)
	}
}

func TestParseRetryAfter_EmptyRejected(t *testing.T) {
	if _, ok := parseRetryAfter("", time.Now()); ok {
		t.Fatal("empty header must be rejected")
	}
}

func TestParseRetryAfter_GarbageRejected(t *testing.T) {
	if _, ok := parseRetryAfter("not-a-value", time.Now()); ok {
		t.Fatal("garbage header must be rejected")
	}
}

func TestParseRetryAfter_ZeroAndNegativeRejected(t *testing.T) {
	if _, ok := parseRetryAfter("0", time.Now()); ok {
		t.Fatal("zero must be rejected")
	}
	if _, ok := parseRetryAfter("-5", time.Now()); ok {
		t.Fatal("negative must be rejected")
	}
}

func TestParseRetryAfter_PastDateRejected(t *testing.T) {
	now := time.Date(2026, 1, 1, 12, 0, 0, 0, time.UTC)
	past := now.Add(-90 * time.Second)
	if _, ok := parseRetryAfter(past.Format(http.TimeFormat), now); ok {
		t.Fatal("a Retry-After date in the past must be rejected")
	}
}

func TestParseRetryAfter_AbsurdlyLargeRejected(t *testing.T) {
	if _, ok := parseRetryAfter("999999999", time.Now()); ok {
		t.Fatal("a value past maxParsableRetryAfter must be rejected")
	}
}

// --- rateLimitDecision (pure, no I/O) --------------------------------------

func TestRateLimitDecision_MissingRetryAfterUsesIntervalFallback(t *testing.T) {
	effective, newInterval, giveUp := rateLimitDecision(0, 20*time.Second, 5*time.Minute)
	if giveUp {
		t.Fatal("must not give up when remaining time is plentiful")
	}
	if effective != 25 {
		t.Fatalf("got effectiveRetry=%d, want 25 (actual fallback backoff)", effective)
	}
	if newInterval != 25*time.Second {
		t.Fatalf("got newInterval=%v, want interval+5s backoff when no Retry-After given", newInterval)
	}
}

func TestRateLimitDecision_RetryAfterHonoredWhenPresent(t *testing.T) {
	effective, newInterval, giveUp := rateLimitDecision(45, 15*time.Second, 5*time.Minute)
	if giveUp {
		t.Fatal("must not give up when remaining time is plentiful")
	}
	if effective != 45 {
		t.Fatalf("got effectiveRetry=%d, want 45 (server-provided value wins)", effective)
	}
	if newInterval != 45*time.Second {
		t.Fatalf("got newInterval=%v, want exactly the server's Retry-After, not the old +5s creep", newInterval)
	}
}

func TestRateLimitDecision_RetryAfterNeverShortensCurrentInterval(t *testing.T) {
	effective, newInterval, giveUp := rateLimitDecision(1, 15*time.Second, 5*time.Minute)
	if giveUp {
		t.Fatal("must not give up")
	}
	if effective != 15 || newInterval != 15*time.Second {
		t.Fatalf("got effective=%d interval=%v, want current 15s interval preserved", effective, newInterval)
	}
}

func TestRateLimitDecision_GivesUpWhenRetryExceedsRemainingFlowLifetime(t *testing.T) {
	_, _, giveUp := rateLimitDecision(600, 15*time.Second, 30*time.Second)
	if !giveUp {
		t.Fatal("must give up: a 600s wait cannot fit in a 30s remaining flow lifetime")
	}
}

func TestRateLimitDecision_DoesNotGiveUpWhenRetryFitsRemainingLifetime(t *testing.T) {
	_, _, giveUp := rateLimitDecision(10, 15*time.Second, 30*time.Second)
	if giveUp {
		t.Fatal("must not give up: a 10s wait fits comfortably in a 30s remaining flow lifetime")
	}
}

// --- flowState JSON shape ---------------------------------------------------

func TestFlowStateJSON_RateLimitFieldsOmittedWhenFalseZero(t *testing.T) {
	fs := &flowState{Status: "pending", Username: "benlue"}
	b, err := json.Marshal(fs)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	json.Unmarshal(b, &m)
	if _, present := m["rate_limited"]; present {
		t.Fatal("rate_limited must be omitted (omitempty) when false")
	}
	if _, present := m["retry_after_seconds"]; present {
		t.Fatal("retry_after_seconds must be omitted (omitempty) when zero")
	}
}

func TestFlowStateJSON_RateLimitFieldsPresentWhenSet(t *testing.T) {
	fs := &flowState{Status: "pending", Username: "benlue", RateLimited: true, RetryAfterSeconds: 42}
	b, err := json.Marshal(fs)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	json.Unmarshal(b, &m)
	if rl, _ := m["rate_limited"].(bool); !rl {
		t.Fatal("rate_limited must be true in the JSON")
	}
	if ra, _ := m["retry_after_seconds"].(float64); ra != 42 {
		t.Fatalf("got retry_after_seconds=%v, want 42", m["retry_after_seconds"])
	}
}

// --- pollAndDecide end-to-end (real loop, shrunk minPollInterval) ---------

// withFastPolling shrinks minPollInterval for the duration of one test so
// pollAndDecide's real loop runs in milliseconds instead of tens of
// seconds - production code never assigns this var.
func withFastPolling(t *testing.T) {
	t.Helper()
	prev := minPollInterval
	minPollInterval = 10 * time.Millisecond
	t.Cleanup(func() { minPollInterval = prev })
}

func newTestFlow(username string) (*flowState, *deviceAuthResponse) {
	fs := &flowState{Status: "pending", Username: username, UID: "1000", startedAt: time.Now(), cancelCh: make(chan struct{})}
	dev := &deviceAuthResponse{DeviceCode: "dev-" + username, Interval: 0, ExpiresIn: 3600}
	return fs, dev
}

func noopRelease(releaseOutcome) {}

func TestPollAndDecide_RateLimit_PropagatesThenRecoversThenApproves(t *testing.T) {
	withFastPolling(t)
	var calls int32
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		n := atomic.AddInt32(&calls, 1)
		if n <= 2 {
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-ok"})
	})
	mux.HandleFunc("/api/oidc/userinfo", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]string{"authelia.pam.username": "benlue"})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	fs, dev := newTestFlow("benlue")
	done := make(chan struct{})
	go func() { pollAndDecide("sess-1", fs, dev, "benlue", noopRelease); close(done) }()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("pollAndDecide did not finish in time")
	}

	fs.mu.Lock()
	defer fs.mu.Unlock()
	if fs.Status != "approved" {
		t.Fatalf("got status=%q error=%q, want approved after recovering from rate limit", fs.Status, fs.Error)
	}
	if fs.RateLimited {
		t.Fatal("RateLimited must be cleared once the flow recovers and gets approved")
	}
	if fs.RetryAfterSeconds != 0 {
		t.Fatalf("got RetryAfterSeconds=%d, want 0 after recovery", fs.RetryAfterSeconds)
	}
}

func TestPollAndDecide_RateLimit_NeverApprovesWhileStillLimited(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "1")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	fs, dev := newTestFlow("benlue")
	dev.ExpiresIn = 1 // whole flow lifetime is ~1s, always-429 must exhaust it fast
	done := make(chan struct{})
	go func() { pollAndDecide("sess-2", fs, dev, "benlue", noopRelease); close(done) }()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("pollAndDecide did not finish in time")
	}

	fs.mu.Lock()
	defer fs.mu.Unlock()
	// Status can only ever become "approved" via the outcomeOK branch,
	// which calls writeApprovalMarker - a mock that only ever returns 429
	// structurally never reaches that branch, so this also proves no
	// approval marker was ever written for this flow.
	if fs.Status == "approved" {
		t.Fatal("a flow that only ever saw 429s must never be approved")
	}
	if fs.Status != "error" || fs.Error != "rate_limited" {
		t.Fatalf("got status=%q error=%q, want error/rate_limited", fs.Status, fs.Error)
	}
}

func TestPollAndDecide_RateLimit_ExceedsFlowLifetime_TerminalError(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		// A Retry-After far longer than the flow's own remaining
		// lifetime - the flow must fail closed instead of polling
		// forever inside a deadline it can never actually reach.
		w.Header().Set("Retry-After", "3600")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	fs, dev := newTestFlow("benlue")
	dev.ExpiresIn = 3600 // real deadline is clamped to maxFlowAge (10m) anyway
	done := make(chan struct{})
	go func() { pollAndDecide("sess-3", fs, dev, "benlue", noopRelease); close(done) }()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("pollAndDecide did not finish in time")
	}

	fs.mu.Lock()
	defer fs.mu.Unlock()
	if fs.Status != "error" || fs.Error != "rate_limited" {
		t.Fatalf("got status=%q error=%q, want error/rate_limited", fs.Status, fs.Error)
	}
}

func TestPollAndDecide_Cancelled_NeverApprovedEvenIfRateLimitedFirst(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "1")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	fs, dev := newTestFlow("benlue")
	markPendingFlowCancelled(fs)
	done := make(chan struct{})
	go func() { pollAndDecide("sess-4", fs, dev, "benlue", noopRelease); close(done) }()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("pollAndDecide did not finish in time")
	}

	fs.mu.Lock()
	defer fs.mu.Unlock()
	if fs.Status == "approved" {
		t.Fatal("a cancelled flow must never be approved regardless of rate-limit state")
	}
}

// TestPollAndDecide_RateLimit_FlowIsolation proves alice's rate-limited
// flow never touches bob's independent flowState - no shared/global
// rate-limit flag exists, only per-flow fields.
func TestPollAndDecide_RateLimit_FlowIsolation(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		if r.FormValue("device_code") == "dev-alice" {
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		// bob's own device code: authorization_pending, never rate limited.
		json.NewEncoder(w).Encode(tokenResponse{Error: "authorization_pending"})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prevBase }()

	aliceFS, aliceDev := newTestFlow("alice")
	aliceDev.DeviceCode = "dev-alice"
	bobFS, bobDev := newTestFlow("bob")
	bobDev.DeviceCode = "dev-bob"

	go pollAndDecide("sess-alice", aliceFS, aliceDev, "alice", noopRelease)
	go pollAndDecide("sess-bob", bobFS, bobDev, "bob", noopRelease)

	time.Sleep(150 * time.Millisecond)
	aliceFS.mu.Lock()
	bobFS.mu.Lock()
	defer aliceFS.mu.Unlock()
	defer bobFS.mu.Unlock()

	if !aliceFS.RateLimited {
		t.Fatal("alice's flow must observe the rate limit on her own device code")
	}
	if bobFS.RateLimited {
		t.Fatal("bob's independent flow must never be marked rate-limited by alice's")
	}

	aliceFS.cancelled = true
	bobFS.cancelled = true
}

func TestPollAndDecide_RateLimitTerminalIsNeutral(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Retry-After", "3600")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-neutral-429", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	select {
	case got := <-released:
		if got != releaseNeutral {
			t.Fatalf("got release outcome %v, want neutral", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timeout")
	}
}

func TestPollAndDecide_CancelInterruptsLongBackoff(t *testing.T) {
	withFastPolling(t)
	var calls int32
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.Header().Set("Retry-After", "5")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-cancel", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	deadline := time.Now().Add(2 * time.Second)
	for atomic.LoadInt32(&calls) == 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if atomic.LoadInt32(&calls) == 0 {
		t.Fatal("first rate-limited poll never happened")
	}

	start := time.Now()
	if !markPendingFlowCancelled(fs) {
		t.Fatal("cancel was not accepted")
	}
	select {
	case got := <-released:
		if got != releaseNeutral {
			t.Fatalf("got %v, want neutral", got)
		}
		if time.Since(start) > 500*time.Millisecond {
			t.Fatalf("cancel too slow: %v", time.Since(start))
		}
	case <-time.After(time.Second):
		t.Fatal("cancel did not interrupt backoff")
	}
}

func TestPollAndDecide_AccessDeniedCountsAsAuthFailure(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(tokenResponse{Error: "access_denied"})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-denied", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	select {
	case got := <-released:
		if got != releaseAuthFailure {
			t.Fatalf("got %v, want auth failure", got)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timeout")
	}
}

// --- v1.3.0 rate-limit UX fix: a single QR code left open normally is
// one device flow, not a sequence of user login attempts. These prove
// the backend side of that distinction (already correct before this
// fix - see docs/architecture.md) stays correct, complementing the
// theme-side wording fix (rateLimitedWaitingText / the "denied"/"error"
// switch in Main.qml no longer say "Zu viele Anmeldeversuche" for any
// of these). ---------------------------------------------------------

// TestPollAndDecide_LongPendingFlow_NoRateLimit_NeverCountsAsFailure
// proves the plain, expected case - a user who simply hasn't scanned
// yet - never touches the ambiguous-error counter, the rate-limit path,
// or the failure-lockout counter, no matter how many authorization_pending
// polls happen over the flow's lifetime.
func TestPollAndDecide_LongPendingFlow_NoRateLimit_NeverCountsAsFailure(t *testing.T) {
	withFastPolling(t)
	var calls int32
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		// RFC 8628: authorization_pending is returned with a non-200
		// status (Authelia uses 400) - without this, pollToken would
		// treat the 200-default response as outcomeOK with an empty
		// access token instead of outcomeOAuth/authorization_pending.
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(tokenResponse{Error: "authorization_pending"})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	dev.ExpiresIn = 1 // short-lived on purpose: let it run out naturally
	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-long-pending", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	select {
	case got := <-released:
		if got != releaseNeutral {
			t.Fatalf("got release outcome %v, want neutral - repeated authorization_pending must never count as a failure", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timeout")
	}
	if atomic.LoadInt32(&calls) < 2 {
		t.Fatalf("got %d polls, want at least 2 - the flow must keep polling normally, not bail out early", calls)
	}
	fs.mu.Lock()
	defer fs.mu.Unlock()
	if fs.Status != "error" || fs.Error != "expired" {
		t.Fatalf("got status=%q error=%q, want error/expired once the flow's own deadline (not any rate limit) passes", fs.Status, fs.Error)
	}
}

// TestPollAndDecide_AmbiguousExhaustion_IsNeutral_NotFailure proves the
// OTHER terminal give-up path (repeated malformed/connection-level
// responses, maxConsecutiveAmbiguous exceeded - an infrastructure
// problem) is exactly as neutral as the rate-limit terminal path
// (TestPollAndDecide_RateLimitTerminalIsNeutral above) - "Infrastrukturfehler
// != Auth Denial" applies equally to both terminal reasons.
func TestPollAndDecide_AmbiguousExhaustion_IsNeutral_NotFailure(t *testing.T) {
	withFastPolling(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		// Non-JSON body, non-429: outcomeAmbiguous every time (see
		// pollToken's doc comment).
		w.WriteHeader(http.StatusBadGateway)
		w.Write([]byte("<html>bad gateway</html>"))
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-ambiguous", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	select {
	case got := <-released:
		if got != releaseNeutral {
			t.Fatalf("got release outcome %v, want neutral - repeated ambiguous/infrastructure errors must never count as a failure", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("timeout")
	}
	fs.mu.Lock()
	defer fs.mu.Unlock()
	if fs.Status != "error" || fs.Error != "temporarily_unavailable" {
		t.Fatalf("got status=%q error=%q, want error/temporarily_unavailable", fs.Status, fs.Error)
	}
}

// TestSupersedePriorFlow_InterruptsLongBackoff proves supersede (a new
// /start for the same user, superseding this one) interrupts an
// in-progress rate-limit backoff exactly as immediately as an explicit
// cancel does (TestPollAndDecide_CancelInterruptsLongBackoff) - both
// go through the same markPendingFlowCancelled/cancelCh mechanism, but
// supersede is a distinct production entry point (supersedePriorFlow,
// called from handleStart) worth proving directly rather than only by
// implication.
func TestSupersedePriorFlow_InterruptsLongBackoff(t *testing.T) {
	resetFlowState(t)
	withFastPolling(t)
	var calls int32
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&calls, 1)
		w.Header().Set("Retry-After", "5")
		w.WriteHeader(http.StatusTooManyRequests)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	defer func() { cfg.AutheliaBaseURL = prev }()

	fs, dev := newTestFlow("benlue")
	flowsMu.Lock()
	flows["sess-supersede"] = fs
	lastSessionForUser["benlue"] = "sess-supersede"
	flowsMu.Unlock()

	released := make(chan releaseOutcome, 1)
	go pollAndDecide("sess-supersede", fs, dev, "benlue", func(o releaseOutcome) { released <- o })

	deadline := time.Now().Add(2 * time.Second)
	for atomic.LoadInt32(&calls) == 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if atomic.LoadInt32(&calls) == 0 {
		t.Fatal("first rate-limited poll never happened")
	}

	start := time.Now()
	supersedePriorFlow("benlue")
	select {
	case got := <-released:
		if got != releaseNeutral {
			t.Fatalf("got %v, want neutral", got)
		}
		if time.Since(start) > 500*time.Millisecond {
			t.Fatalf("supersede too slow: %v", time.Since(start))
		}
	case <-time.After(time.Second):
		t.Fatal("supersede did not interrupt backoff")
	}
}
