package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func resetCapabilitiesCache(t *testing.T) {
	t.Helper()
	capabilitiesCacheMu.Lock()
	capabilitiesCacheAt = time.Time{}
	capabilitiesCacheOIDC = false
	capabilitiesCacheMu.Unlock()
}

func withStubPAMFile(t *testing.T, content string) {
	t.Helper()
	prev := pamFilePath
	if content == "" {
		pamFilePath = filepath.Join(t.TempDir(), "does-not-exist")
	} else {
		p := filepath.Join(t.TempDir(), "sddm")
		if err := os.WriteFile(p, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
		pamFilePath = p
	}
	t.Cleanup(func() { pamFilePath = prev })
}

// --- fido2Wired -----------------------------------------------------------

func TestFido2Wired_PresentInPAMFile(t *testing.T) {
	withStubPAMFile(t, "auth [success=2 default=ignore] pam_u2f.so authfile=/etc/x cue\nauth [success=1 default=ignore] pam_authelia_passkey.so\n")
	if !fido2Wired() {
		t.Fatal("expected fido2Wired() true when pam_u2f.so is present in the PAM file")
	}
}

func TestFido2Wired_AbsentFromPAMFile(t *testing.T) {
	withStubPAMFile(t, "auth [success=1 default=ignore] pam_authelia_passkey.so\n")
	if fido2Wired() {
		t.Fatal("expected fido2Wired() false when pam_u2f.so is not present")
	}
}

func TestFido2Wired_MissingPAMFile_FailsClosedToFalse(t *testing.T) {
	withStubPAMFile(t, "")
	if fido2Wired() {
		t.Fatal("expected fido2Wired() false (fail closed) when the PAM file cannot be read")
	}
}

// --- oidcReadyCached --------------------------------------------------------

func TestOIDCReadyCached_ReflectsUnderlyingCheck(t *testing.T) {
	resetCapabilitiesCache(t)
	prev := checkOIDCReady
	calls := 0
	checkOIDCReady = func() bool { calls++; return true }
	t.Cleanup(func() { checkOIDCReady = prev })

	if !oidcReadyCached() {
		t.Fatal("expected oidcReadyCached() to reflect the stubbed true result")
	}
	if calls != 1 {
		t.Fatalf("expected exactly 1 underlying check on first call, got %d", calls)
	}
}

func TestOIDCReadyCached_ThrottlesRepeatedCalls(t *testing.T) {
	resetCapabilitiesCache(t)
	prev := checkOIDCReady
	calls := 0
	checkOIDCReady = func() bool { calls++; return true }
	t.Cleanup(func() { checkOIDCReady = prev })

	oidcReadyCached()
	oidcReadyCached()
	oidcReadyCached()
	if calls != 1 {
		t.Fatalf("expected the underlying check to run once within the cache TTL, got %d calls", calls)
	}
}

func TestOIDCReadyCached_RefetchesAfterTTLExpires(t *testing.T) {
	resetCapabilitiesCache(t)
	prev := checkOIDCReady
	calls := 0
	checkOIDCReady = func() bool { calls++; return true }
	t.Cleanup(func() { checkOIDCReady = prev })

	oidcReadyCached()
	capabilitiesCacheMu.Lock()
	capabilitiesCacheAt = time.Now().Add(-2 * capabilitiesCacheTTL)
	capabilitiesCacheMu.Unlock()
	oidcReadyCached()

	if calls != 2 {
		t.Fatalf("expected a fresh check once the TTL has expired, got %d calls", calls)
	}
}

// --- handleCapabilities ------------------------------------------------------

func TestHandleCapabilities_ReportsRealFacts(t *testing.T) {
	resetCapabilitiesCache(t)
	withStubPAMFile(t, "auth [success=2 default=ignore] pam_u2f.so authfile=/etc/x cue\n")
	prev := checkOIDCReady
	checkOIDCReady = func() bool { return true }
	t.Cleanup(func() { checkOIDCReady = prev })
	cfg.AccountSource = "nss"

	req := httptest.NewRequest(http.MethodGet, "/capabilities", nil)
	w := httptest.NewRecorder()
	handleCapabilities(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var resp capabilitiesResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.AccountSource != "nss" {
		t.Fatalf("account_source = %q, want %q", resp.AccountSource, "nss")
	}
	if !resp.OIDCReady {
		t.Fatal("oidc_ready = false, want true (stubbed reachable)")
	}
	if !resp.FIDO2Wired {
		t.Fatal("fido2_wired = false, want true (pam_u2f.so present in stub PAM file)")
	}
	if resp.SmartcardReady {
		t.Fatal("smartcard_ready must always be false - not implemented")
	}
}

func TestHandleCapabilities_RejectsNonGET(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "/capabilities", nil)
	w := httptest.NewRecorder()
	handleCapabilities(w, req)

	if w.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405 for a non-GET request", w.Code)
	}
}

func TestHandleCapabilities_NoUsernameRequired_UnauthenticatedByDesign(t *testing.T) {
	resetCapabilitiesCache(t)
	withStubPAMFile(t, "")
	prev := checkOIDCReady
	checkOIDCReady = func() bool { return false }
	t.Cleanup(func() { checkOIDCReady = prev })
	cfg.AccountSource = "local"

	// No username query parameter at all, and no allowlist configured -
	// must still succeed, since this endpoint carries no per-user
	// authorization decision (see the file's doc comment).
	req := httptest.NewRequest(http.MethodGet, "/capabilities", nil)
	w := httptest.NewRecorder()
	handleCapabilities(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200 (no auth required for this endpoint)", w.Code)
	}
}
