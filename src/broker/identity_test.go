package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// --- OIDC identity determination (verifyUserinfo) and the exact-match
// binding rule pollAndDecide enforces against it
// (REQUESTED_LOCAL_USER == AUTHENTICATED_AUTHELIA_USER, see
// docs/architecture.md's "Multi-user readiness" section). ---------------

func withUserinfoEndpoint(t *testing.T, handler http.HandlerFunc) {
	t.Helper()
	srv := httptest.NewServer(handler)
	prev := cfg.AutheliaBaseURL
	cfg.AutheliaBaseURL = srv.URL
	t.Cleanup(func() {
		srv.Close()
		cfg.AutheliaBaseURL = prev
	})
}

func TestVerifyUserinfo_ExtractsUsernameClaim(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"authelia.pam.username":"alice","sub":"abc"}`))
	})
	got, err := verifyUserinfo("tok")
	if err != nil || got != "alice" {
		t.Fatalf("got %q err=%v", got, err)
	}
}

func TestVerifyUserinfo_MissingClaimRejected(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"sub":"abc"}`))
	})
	if _, err := verifyUserinfo("tok"); err == nil {
		t.Fatal("expected error when authelia.pam.username claim is absent")
	}
}

func TestVerifyUserinfo_EmptyClaimRejected(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"authelia.pam.username":""}`))
	})
	if _, err := verifyUserinfo("tok"); err == nil {
		t.Fatal("expected error for an empty username claim")
	}
}

func TestVerifyUserinfo_WrongClaimTypeRejected(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"authelia.pam.username":12345}`))
	})
	if _, err := verifyUserinfo("tok"); err == nil {
		t.Fatal("expected error when the claim is not a string")
	}
}

func TestVerifyUserinfo_MalformedJSONRejected(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{not json`))
	})
	if _, err := verifyUserinfo("tok"); err == nil {
		t.Fatal("expected error for malformed JSON")
	}
}

func TestVerifyUserinfo_HTTPErrorRejected(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	})
	if _, err := verifyUserinfo("tok"); err == nil {
		t.Fatal("expected error for a non-200 userinfo response")
	}
}

func TestVerifyUserinfo_UsesBearerToken(t *testing.T) {
	var gotAuth string
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		w.Write([]byte(`{"authelia.pam.username":"alice"}`))
	})
	if _, err := verifyUserinfo("my-access-token"); err != nil {
		t.Fatal(err)
	}
	if gotAuth != "Bearer my-access-token" {
		t.Fatalf("Authorization header = %q", gotAuth)
	}
}

// --- Identity binding rule: this replicates pollAndDecide's own
// comparison (see outcomeOK handling in main.go) against
// verifyUserinfo's real output, without needing to drive the full
// 15s-interval poll loop - REQUESTED_LOCAL_USER must exactly equal
// AUTHENTICATED_AUTHELIA_USER, no fuzzy/partial/case-insensitive match.

func TestIdentityBinding_ExactMatchAllowed(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"authelia.pam.username":"alice"}`))
	})
	requested := "alice"
	authenticated, err := verifyUserinfo("tok")
	if err != nil {
		t.Fatal(err)
	}
	if authenticated != requested {
		t.Fatalf("expected identity binding to ALLOW: requested=%q authenticated=%q", requested, authenticated)
	}
}

func TestIdentityBinding_MismatchDenied(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		// Authelia authenticated bob, but this flow was started for alice.
		w.Write([]byte(`{"authelia.pam.username":"bob"}`))
	})
	requested := "alice"
	authenticated, err := verifyUserinfo("tok")
	if err != nil {
		t.Fatal(err)
	}
	if authenticated == requested {
		t.Fatal("bob's identity must never be treated as a match for a flow requested for alice")
	}
}

func TestIdentityBinding_CaseSensitive(t *testing.T) {
	withUserinfoEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"authelia.pam.username":"Alice"}`))
	})
	requested := "alice"
	authenticated, err := verifyUserinfo("tok")
	if err != nil {
		t.Fatal(err)
	}
	if authenticated == requested {
		t.Fatal("identity binding must be exact-match, not case-insensitive")
	}
}
