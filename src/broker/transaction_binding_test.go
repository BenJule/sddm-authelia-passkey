package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// --- approval marker bound context (v2.8.0) --------------------------------

func TestBuildApprovalMarkerToken_ContainsBoundContext(t *testing.T) {
	prevSource, prevKind := cfg.AccountSource, cfg.ProviderKind
	cfg.AccountSource = "nss"
	cfg.ProviderKind = "oidc"
	t.Cleanup(func() { cfg.AccountSource, cfg.ProviderKind = prevSource, prevKind })

	tok := buildApprovalMarkerToken("sess-abc123", "benlue", "1000")

	for _, want := range []string{
		"VERSION=2\n",
		"USERNAME=benlue\n",
		"UID=1000\n",
		"SESSION_ID=sess-abc123\n",
		"IDENTITY_SOURCE=nss\n",
		"PROVIDER=oidc\n",
		"REQUESTED_ACTION=desktop_login\n",
	} {
		if !strings.Contains(tok, want) {
			t.Errorf("marker token missing %q; got:\n%s", want, tok)
		}
	}
	if !strings.Contains(tok, "HOSTNAME=") {
		t.Error("marker token missing HOSTNAME= line")
	}
	if !strings.Contains(tok, "APPROVED_AT=") {
		t.Error("marker token missing APPROVED_AT= line")
	}
	if !strings.Contains(tok, "NONCE=") {
		t.Error("marker token missing NONCE= line")
	}
}

func TestBuildApprovalMarkerToken_DefaultsProviderToAuthelia(t *testing.T) {
	prevKind := cfg.ProviderKind
	cfg.ProviderKind = ""
	t.Cleanup(func() { cfg.ProviderKind = prevKind })

	tok := buildApprovalMarkerToken("sess-1", "benlue", "1000")
	if !strings.Contains(tok, "PROVIDER=authelia\n") {
		t.Errorf("expected PROVIDER=authelia when cfg.ProviderKind is empty; got:\n%s", tok)
	}
}

// TestPollAndDecide_SupersededDuringInFlightPoll_MustNotApprove reproduces
// a real race found while investigating v2.8.0's "a superseded flow can
// never later succeed" requirement: pollAndDecide checks fs.cancelled
// before waiting for the next poll interval and again right after that
// wait completes, but NOT after providerPollToken itself returns - so a
// supersede landing while a poll request is genuinely in flight (blocked
// on network I/O, now bounded to 15s by v2.7.0's providerHTTPClient
// timeout, but still a real window) was not observed at all, and a
// provider response that happens to be a genuine approval would still be
// accepted despite the flow having been superseded moments earlier.
func TestPollAndDecide_SupersededDuringInFlightPoll_MustNotApprove(t *testing.T) {
	withFastPolling(t)
	requestStarted := make(chan struct{})
	releaseResponse := make(chan struct{})

	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		close(requestStarted)
		<-releaseResponse // held open until the test signals to answer
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-ok"})
	})
	mux.HandleFunc("/api/oidc/userinfo", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]string{"authelia.pam.username": "benlue"})
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	prevBase := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	t.Cleanup(func() { cfg.AutheliaBaseURL = prevBase })

	fs, dev := newTestFlow("benlue")
	flowsMu.Lock()
	flows["sess-race"] = fs
	lastSessionForUser["benlue"] = "sess-race"
	flowsMu.Unlock()
	t.Cleanup(func() {
		flowsMu.Lock()
		delete(flows, "sess-race")
		delete(lastSessionForUser, "benlue")
		flowsMu.Unlock()
	})

	done := make(chan struct{})
	go func() { pollAndDecide("sess-race", fs, dev, "benlue", noopRelease); close(done) }()

	select {
	case <-requestStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("token poll never started")
	}

	// The user (or the greeter) starts a brand new flow for the same
	// username while the old one's poll request is still in flight -
	// exactly the real-world sequence supersedePriorFlow exists for.
	supersedePriorFlow("benlue")

	close(releaseResponse) // now let the in-flight request's real approval land

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("pollAndDecide did not finish after being superseded")
	}

	fs.mu.Lock()
	status := fs.Status
	cancelled := fs.cancelled
	fs.mu.Unlock()

	if !cancelled {
		t.Fatal("expected the flow to be marked cancelled by supersedePriorFlow")
	}
	if status == "approved" {
		t.Fatal("SECURITY: a superseded flow's in-flight poll response was still accepted as an approval")
	}
}
