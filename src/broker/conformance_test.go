package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

var errTestDiscoveryUnreachable = errors.New("simulated discovery fetch failure")

func checkStatus(t *testing.T, checks []conformanceCheck, name string) string {
	t.Helper()
	for _, c := range checks {
		if c.Name == name {
			return c.Status
		}
	}
	t.Fatalf("no check named %q in %+v", name, checks)
	return ""
}

// --- provider_kind=oidc, fully conformant real-shaped mock ------------------

func TestProviderConformanceTest_OIDC_AllGreen(t *testing.T) {
	resetOIDCDiscoveryCache(t)

	var srv *httptest.Server
	mux := http.NewServeMux()
	mux.HandleFunc("/device", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"device_code":               "dev-code-1",
			"user_code":                 "ABCD-EFGH",
			"verification_uri":          srv.URL + "/consent",
			"verification_uri_complete": srv.URL + "/consent?user_code=ABCD-EFGH",
			"expires_in":                600,
			"interval":                  5,
		})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "authorization_pending"})
	})
	mux.HandleFunc("/jwks", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"keys": []any{}})
	})
	srv = httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	prevKind, prevURL, prevInsecure := cfg.ProviderKind, cfg.OIDCDiscoveryURL, cfg.DevInsecureHTTP
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = srv.URL + "/.well-known/openid-configuration"
	cfg.DevInsecureHTTP = true
	t.Cleanup(func() { cfg.ProviderKind, cfg.OIDCDiscoveryURL, cfg.DevInsecureHTTP = prevKind, prevURL, prevInsecure })

	prevFetch := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		return &oidcDiscoveryDoc{
			Issuer:                      srv.URL,
			DeviceAuthorizationEndpoint: srv.URL + "/device",
			TokenEndpoint:               srv.URL + "/token",
			UserinfoEndpoint:            srv.URL + "/userinfo",
			JWKSURI:                     srv.URL + "/jwks",
		}, nil
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prevFetch })

	checks := runProviderConformanceTest()

	for _, name := range []string{"DISCOVERY", "ISSUER_BINDING", "DEVICE_ENDPOINT", "JWKS", "TRUSTED_ORIGIN", "VERIFICATION_URI", "RFC8628_PENDING"} {
		if got := checkStatus(t, checks, name); got != "GREEN" {
			t.Errorf("%s = %s, want GREEN (checks: %+v)", name, got, checks)
		}
	}
}

func TestProviderConformanceTest_OIDC_IssuerMismatchIsRed(t *testing.T) {
	resetOIDCDiscoveryCache(t)
	prevKind, prevURL := cfg.ProviderKind, cfg.OIDCDiscoveryURL
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = "https://idp.example.invalid/.well-known/openid-configuration"
	t.Cleanup(func() { cfg.ProviderKind, cfg.OIDCDiscoveryURL = prevKind, prevURL })

	prevFetch := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		return &oidcDiscoveryDoc{Issuer: "https://evil.example.invalid"}, nil
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prevFetch })

	checks := runProviderConformanceTest()
	if got := checkStatus(t, checks, "ISSUER_BINDING"); got != "RED" {
		t.Fatalf("ISSUER_BINDING = %s, want RED for a mismatched issuer", got)
	}
}

func TestProviderConformanceTest_OIDC_DiscoveryFailureCascadesToRed(t *testing.T) {
	resetOIDCDiscoveryCache(t)
	prevKind, prevURL := cfg.ProviderKind, cfg.OIDCDiscoveryURL
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = "https://idp.example.invalid/.well-known/openid-configuration"
	t.Cleanup(func() { cfg.ProviderKind, cfg.OIDCDiscoveryURL = prevKind, prevURL })

	prevFetch := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		return nil, errTestDiscoveryUnreachable
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prevFetch })

	checks := runProviderConformanceTest()
	for _, name := range []string{"DISCOVERY", "ISSUER_BINDING", "DEVICE_ENDPOINT", "JWKS"} {
		if got := checkStatus(t, checks, name); got != "RED" {
			t.Errorf("%s = %s, want RED when discovery itself fails", name, got)
		}
	}
}

// --- provider_kind=authelia --------------------------------------------------

func TestProviderConformanceTest_Authelia_DeviceEndpointGreenDiscoverySkippedPendingGreen(t *testing.T) {
	var srv *httptest.Server
	mux := http.NewServeMux()
	mux.HandleFunc("/api/oidc/device-authorization", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"device_code":               "dev-code-authelia",
			"user_code":                 "WXYZ-1234",
			"verification_uri":          srv.URL + "/consent",
			"verification_uri_complete": srv.URL + "/consent?user_code=WXYZ-1234",
			"expires_in":                600,
			"interval":                  5,
		})
	})
	mux.HandleFunc("/api/oidc/token", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(map[string]string{"error": "authorization_pending"})
	})
	srv = httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	prevKind, prevBase, prevHost, prevInsecure := cfg.ProviderKind, cfg.AutheliaBaseURL, cfg.AllowedVerificationHost, cfg.DevInsecureHTTP
	cfg.ProviderKind = "authelia"
	cfg.AutheliaBaseURL = srv.URL
	cfg.AllowedVerificationHost = srv.Listener.Addr().String()
	cfg.DevInsecureHTTP = true
	t.Cleanup(func() {
		cfg.ProviderKind, cfg.AutheliaBaseURL, cfg.AllowedVerificationHost, cfg.DevInsecureHTTP = prevKind, prevBase, prevHost, prevInsecure
	})

	checks := runProviderConformanceTest()
	if got := checkStatus(t, checks, "DISCOVERY"); got != "SKIP" {
		t.Errorf("DISCOVERY = %s, want SKIP for provider_kind=authelia", got)
	}
	if got := checkStatus(t, checks, "DEVICE_ENDPOINT"); got != "GREEN" {
		t.Errorf("DEVICE_ENDPOINT = %s, want GREEN (hardcoded Authelia path)", got)
	}
	if got := checkStatus(t, checks, "TRUSTED_ORIGIN"); got != "GREEN" {
		t.Errorf("TRUSTED_ORIGIN = %s, want GREEN (checks: %+v)", got, checks)
	}
	if got := checkStatus(t, checks, "VERIFICATION_URI"); got != "GREEN" {
		t.Errorf("VERIFICATION_URI = %s, want GREEN (checks: %+v)", got, checks)
	}
	if got := checkStatus(t, checks, "RFC8628_PENDING"); got != "GREEN" {
		t.Errorf("RFC8628_PENDING = %s, want GREEN (checks: %+v)", got, checks)
	}
}

func TestProviderConformanceTest_DeviceAuthorizeFailureCascadesToRed(t *testing.T) {
	prevKind, prevBase := cfg.ProviderKind, cfg.AutheliaBaseURL
	cfg.ProviderKind = "authelia"
	cfg.AutheliaBaseURL = "http://127.0.0.1:1" // nothing listens here
	t.Cleanup(func() { cfg.ProviderKind, cfg.AutheliaBaseURL = prevKind, prevBase })

	checks := runProviderConformanceTest()
	for _, name := range []string{"VERIFICATION_URI", "TRUSTED_ORIGIN", "RFC8628_PENDING"} {
		if got := checkStatus(t, checks, name); got != "RED" {
			t.Errorf("%s = %s, want RED when device-authorization itself fails", name, got)
		}
	}
}
