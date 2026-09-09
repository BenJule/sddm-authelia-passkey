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
	if effective != 20 {
		t.Fatalf("got effectiveRetry=%d, want 20 (fallback to current interval)", effective)
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
	fs := &flowState{Status: "pending", Username: username, UID: "1000", startedAt: time.Now()}
	dev := &deviceAuthResponse{DeviceCode: "dev-" + username, Interval: 0, ExpiresIn: 3600}
	return fs, dev
}

func noopRelease(bool) {}

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
	if fs.RateLimited && fs.Status != "denied" {
		// Once terminal (denied), RateLimited/RetryAfterSeconds are
		// left as last-known values - fine, Status/Error are authoritative.
		t.Fatalf("got status=%q while still marked RateLimited with no terminal decision", fs.Status)
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
	if fs.Status != "denied" || fs.Error != "rate_limited" {
		t.Fatalf("got status=%q error=%q, want denied/rate_limited", fs.Status, fs.Error)
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
	fs.mu.Lock()
	fs.cancelled = true
	fs.mu.Unlock()
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
