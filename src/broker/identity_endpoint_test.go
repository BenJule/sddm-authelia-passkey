package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os/user"
	"testing"
)

// --- v1.1.0 "Identity Awareness": /identity is a read-only, pre-flow
// lookup so the greeter can show who a flow would be for before
// actually starting one. Must use the exact same authorization check as
// /start (no separate, weaker path), and must never leak anything an
// unauthorized /start attempt wouldn't already. ------------------------

func TestHandleIdentity_AuthorizedUser_ReturnsDisplayName(t *testing.T) {
	prev := userLookup
	userLookup = func(name string) (*user.User, error) {
		if name == "alice" {
			return &user.User{Username: "alice", Uid: "1001", Name: "Alice Example"}, nil
		}
		return nil, user.UnknownUserError(name)
	}
	t.Cleanup(func() { userLookup = prev })
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true}

	req := httptest.NewRequest(http.MethodGet, "/identity?username=alice", nil)
	w := httptest.NewRecorder()
	handleIdentity(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["display_name"] != "Alice Example" {
		t.Fatalf("display_name = %q, want the GECOS full name", resp["display_name"])
	}
	if resp["account_source"] != "local" {
		t.Fatalf("account_source = %q, want %q", resp["account_source"], "local")
	}
}

func TestHandleIdentity_EmptyGECOS_FallsBackToUsername(t *testing.T) {
	withStubUserLookup(t, map[string]string{"bob": "1002"}) // Name left empty by the helper
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"bob": true}

	req := httptest.NewRequest(http.MethodGet, "/identity?username=bob", nil)
	w := httptest.NewRecorder()
	handleIdentity(w, req)

	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["display_name"] != "bob" {
		t.Fatalf("display_name = %q, want a fallback to the plain username when GECOS is empty", resp["display_name"])
	}
}

func TestHandleIdentity_UnauthorizedUser_Rejected(t *testing.T) {
	withStubUserLookup(t, map[string]string{"mallory": "1003"})
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true} // mallory not listed

	req := httptest.NewRequest(http.MethodGet, "/identity?username=mallory", nil)
	w := httptest.NewRecorder()
	handleIdentity(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403 for a not-allowlisted user - identical to /start's behavior", w.Code)
	}
}

func TestHandleIdentity_UnknownUser_RejectedWithoutEnumeration(t *testing.T) {
	withStubUserLookup(t, map[string]string{})
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true}

	req := httptest.NewRequest(http.MethodGet, "/identity?username=nobody", nil)
	w := httptest.NewRecorder()
	handleIdentity(w, req)

	if w.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403", w.Code)
	}
	if w.Body.String() != "not permitted\n" {
		t.Fatalf("body = %q, must not distinguish unknown-user from not-allowlisted (avoid enumeration)", w.Body.String())
	}
}

func TestHandleIdentity_NSSMode_ReportsAccountSource(t *testing.T) {
	withStubUserLookup(t, map[string]string{"carol": "2001"})
	prevGroupIDs := groupIDsForUser
	groupIDsForUser = func(u *user.User) ([]string, error) { return []string{"3001"}, nil }
	prevGroupName := lookupGroupName
	lookupGroupName = func(gid string) (string, error) { return "linux-login", nil }
	t.Cleanup(func() { groupIDsForUser = prevGroupIDs; lookupGroupName = prevGroupName })

	cfg.AccountSource = "nss"
	cfg.MinimumUID = 1000
	cfg.DenyUsers = map[string]bool{"root": true}
	cfg.AllowedGroups = map[string]bool{"linux-login": true}
	cfg.AllowedUsers = map[string]bool{}

	req := httptest.NewRequest(http.MethodGet, "/identity?username=carol", nil)
	w := httptest.NewRecorder()
	handleIdentity(w, req)

	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["account_source"] != "nss" {
		t.Fatalf("account_source = %q, want %q so the UI can label this a directory account", resp["account_source"], "nss")
	}
}
