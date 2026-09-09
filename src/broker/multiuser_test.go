package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

// --- Multi-user readiness: every flow/marker/cancel/supersede operation
// is scoped to exactly one local user, and one user's session can never
// be affected by another user's requests. See docs/architecture.md's
// "Multi-user readiness" section for the identity-binding model this
// exercises (REQUESTED_LOCAL_USER / AUTHENTICATED_AUTHELIA_USER /
// BOUND_LOCAL_USER). v0.3.0 does not add a full multi-user SDDM UX -
// these tests only prove the existing per-user isolation actually holds
// once more than one allowed_users entry is configured. ---------------

func TestHandleStart_MultipleAllowedUsers_ExplicitAliceAccepted(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true, "bob": true}

	req := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"alice"}}.Encode(), nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 for an explicitly named, allowed user", w.Code)
	}
}

func TestHandleStart_MultipleAllowedUsers_ExplicitBobAccepted(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true, "bob": true}

	req := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"bob"}}.Encode(), nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 for an explicitly named, allowed user", w.Code)
	}
}

func TestHandleStart_MultipleAllowedUsers_ExplicitMalloryRejected(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true, "bob": true}

	req := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"mallory"}}.Encode(), nil)
	w := httptest.NewRecorder()
	handleStart(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 for a non-allowed user", w.Code)
	}
}

func TestHandleStart_AliceAndBobFlowsAreIndependent(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withFailingDeviceAuthEndpoint(t)
	cfg.AllowedUsers = map[string]bool{"alice": true, "bob": true}

	reqA := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"alice"}}.Encode(), nil)
	wA := httptest.NewRecorder()
	handleStart(wA, reqA)
	if wA.Code != http.StatusOK {
		t.Fatalf("alice start status = %d", wA.Code)
	}

	reqB := httptest.NewRequest(http.MethodPost, "/start?"+url.Values{"username": {"bob"}}.Encode(), nil)
	wB := httptest.NewRecorder()
	handleStart(wB, reqB)
	if wB.Code != http.StatusOK {
		t.Fatalf("bob start status = %d (must not be blocked by alice's independent per-user cooldown)", wB.Code)
	}

	var respA, respB map[string]string
	json.Unmarshal(wA.Body.Bytes(), &respA)
	json.Unmarshal(wB.Body.Bytes(), &respB)
	if respA["session_id"] == respB["session_id"] {
		t.Fatal("alice and bob must never share a session_id")
	}

	flowsMu.Lock()
	fsA, okA := flows[respA["session_id"]]
	fsB, okB := flows[respB["session_id"]]
	flowsMu.Unlock()
	if !okA || !okB {
		t.Fatal("expected both flows to exist independently")
	}
	fsA.mu.Lock()
	userA := fsA.Username
	fsA.mu.Unlock()
	fsB.mu.Lock()
	userB := fsB.Username
	fsB.mu.Unlock()
	if userA != "alice" || userB != "bob" {
		t.Fatalf("got Username alice-flow=%q bob-flow=%q", userA, userB)
	}
}

func TestSupersedePriorFlow_NewAliceFlowDoesNotSupersedeBobFlow(t *testing.T) {
	resetFlowState(t)

	bobFlow := &flowState{Status: "pending", Username: "bob"}
	flowsMu.Lock()
	flows["bob-session"] = bobFlow
	lastSessionForUser["bob"] = "bob-session"
	flowsMu.Unlock()

	// A brand new flow for alice must only ever look at
	// lastSessionForUser["alice"] - bob's entry must be untouched.
	supersedePriorFlow("alice")

	bobFlow.mu.Lock()
	cancelled := bobFlow.cancelled
	bobFlow.mu.Unlock()
	if cancelled {
		t.Fatal("a new alice flow must never supersede bob's flow")
	}
}

func TestHandleCancel_CancellingAliceSessionLeavesBobActive(t *testing.T) {
	resetFlowState(t)
	aliceFlow := &flowState{Status: "pending", Username: "alice"}
	bobFlow := &flowState{Status: "pending", Username: "bob"}
	flowsMu.Lock()
	flows["alice-session"] = aliceFlow
	flows["bob-session"] = bobFlow
	flowsMu.Unlock()

	req := httptest.NewRequest(http.MethodPost, "/cancel?session_id=alice-session", nil)
	handleCancel(httptest.NewRecorder(), req)

	aliceFlow.mu.Lock()
	aliceCancelled := aliceFlow.cancelled
	aliceFlow.mu.Unlock()
	bobFlow.mu.Lock()
	bobCancelled := bobFlow.cancelled
	bobFlow.mu.Unlock()

	if !aliceCancelled {
		t.Fatal("expected alice's session to be cancelled")
	}
	if bobCancelled {
		t.Fatal("cancelling alice's session must never touch bob's session")
	}
}

func TestLoadConfig_MultipleAllowedUsersParsedCorrectly(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice,bob,carol
`)
	cfg, err := LoadConfig(p)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, u := range []string{"alice", "bob", "carol"} {
		if !cfg.AllowedUsers[u] {
			t.Fatalf("expected %q in allowed_users, got %v", u, cfg.AllowedUsers)
		}
	}
	if len(cfg.AllowedUsers) != 3 {
		t.Fatalf("len(AllowedUsers) = %d, want 3", len(cfg.AllowedUsers))
	}
}

func TestLoadConfig_RejectsKWalletAutoUnlockWithMultipleUsers(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice,bob
kwallet_auto_unlock=true
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("expected rejection: kwallet-secretd has no per-user credential binding yet")
	}
}

func TestLoadConfig_AllowsKWalletAutoUnlockWithSingleUser(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice
kwallet_auto_unlock=true
`)
	if _, err := LoadConfig(p); err != nil {
		t.Fatalf("unexpected error with a single allowed user: %v", err)
	}
}
