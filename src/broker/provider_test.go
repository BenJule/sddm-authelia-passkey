package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func resetOIDCDiscoveryCache(t *testing.T) {
	t.Helper()
	oidcDiscoveryMu.Lock()
	oidcDiscoveryCache = nil
	oidcDiscoveryMu.Unlock()
	t.Cleanup(func() {
		oidcDiscoveryMu.Lock()
		oidcDiscoveryCache = nil
		oidcDiscoveryMu.Unlock()
	})
}

// --- dispatch: provider_kind=authelia (default) must never touch the
// generic OIDC path at all -------------------------------------------------

func TestProviderDispatch_DefaultIsAuthelia(t *testing.T) {
	resetLimiterState(t)
	cfg.ProviderKind = ""
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-authelia"})
	})
	tok, _, outcome, _, err := providerPollToken("dev-code")
	if err != nil || outcome != outcomeOK || tok != "tok-authelia" {
		t.Fatalf("got tok=%q outcome=%v err=%v, want the unchanged Authelia path used by default", tok, outcome, err)
	}
}

func TestProviderDispatch_ExplicitAuthelia(t *testing.T) {
	resetLimiterState(t)
	cfg.ProviderKind = "authelia"
	withTokenEndpoint(t, func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-authelia"})
	})
	tok, _, _, _, err := providerPollToken("dev-code")
	if err != nil || tok != "tok-authelia" {
		t.Fatalf("got tok=%q err=%v, want the Authelia path", tok, err)
	}
}

// --- generic OIDC: discovery / capability detection -----------------------

func TestOIDCDiscover_MissingDeviceAuthorizationEndpointRefused(t *testing.T) {
	resetOIDCDiscoveryCache(t)
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = "https://idp.example.invalid/.well-known/openid-configuration"
	prev := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		return &oidcDiscoveryDoc{TokenEndpoint: "https://idp.example.invalid/token", UserinfoEndpoint: "https://idp.example.invalid/userinfo"}, nil
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prev })

	if _, err := oidcDiscover(); err == nil {
		t.Fatal("a provider that does not advertise device_authorization_endpoint must be refused (capability detection), not assumed to support RFC 8628")
	}
}

// TestProviderDispatch_UnreachableProviderNeverApproves is the explicit
// "failover never silently grants access" proof for the OIDC provider
// path: a provider that is completely unreachable (not merely
// misconfigured) must produce a hard error at every one of the three
// dispatch points, never a fabricated success value - the same
// invariant the existing marker-absence PAM tests
// (tests/integration/pam-flow-test.sh's "no marker" case) already prove
// for the Authelia path.
func TestProviderDispatch_UnreachableProviderNeverApproves(t *testing.T) {
	resetLimiterState(t)
	resetOIDCDiscoveryCache(t)
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = "http://127.0.0.1:1/.well-known/openid-configuration"

	if dev, err := providerDeviceAuthorize(); err == nil {
		t.Fatalf("got dev=%+v err=nil, want an error - an unreachable provider must never yield a usable device-authorization response", dev)
	}
	if tok, _, outcome, _, err := providerPollToken("irrelevant"); err == nil || tok != "" {
		t.Fatalf("got tok=%q outcome=%v err=%v, want tok=\"\" and a non-nil error - an unreachable provider must never yield a usable access token", tok, outcome, err)
	}
	if user, err := providerVerifyIdentity("irrelevant"); err == nil || user != "" {
		t.Fatalf("got user=%q err=%v, want user=\"\" and a non-nil error - an unreachable provider must never yield a verified identity", user, err)
	}
}

func TestOIDCDiscover_MissingDiscoveryURLRefused(t *testing.T) {
	resetOIDCDiscoveryCache(t)
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = ""
	if _, err := oidcDiscover(); err == nil {
		t.Fatal("provider_kind=oidc with no oidc_discovery_url must be refused")
	}
}

func TestOIDCDiscover_CachedAfterFirstFetch(t *testing.T) {
	resetOIDCDiscoveryCache(t)
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = "https://idp.example.invalid/.well-known/openid-configuration"
	calls := 0
	prev := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		calls++
		return &oidcDiscoveryDoc{
			DeviceAuthorizationEndpoint: "https://idp.example.invalid/device",
			TokenEndpoint:               "https://idp.example.invalid/token",
			UserinfoEndpoint:            "https://idp.example.invalid/userinfo",
		}, nil
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prev })

	if _, err := oidcDiscover(); err != nil {
		t.Fatal(err)
	}
	if _, err := oidcDiscover(); err != nil {
		t.Fatal(err)
	}
	if calls != 1 {
		t.Fatalf("got %d discovery fetches, want exactly 1 (cached after first)", calls)
	}
}

// --- generic OIDC: end-to-end against a mock Keycloak/Authentik-shaped
// discovery document + endpoints -------------------------------------------

func withMockOIDCProvider(t *testing.T, deviceAuthHandler, tokenHandler, userinfoHandler http.HandlerFunc) {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/protocol/openid-connect/auth/device", deviceAuthHandler)
	mux.HandleFunc("/protocol/openid-connect/token", tokenHandler)
	mux.HandleFunc("/protocol/openid-connect/userinfo", userinfoHandler)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)

	resetOIDCDiscoveryCache(t)
	prevKind, prevURL, prevClaim := cfg.ProviderKind, cfg.OIDCDiscoveryURL, cfg.OIDCIdentityClaim
	cfg.ProviderKind = "oidc"
	cfg.OIDCDiscoveryURL = srv.URL + "/.well-known/openid-configuration"
	t.Cleanup(func() {
		cfg.ProviderKind, cfg.OIDCDiscoveryURL, cfg.OIDCIdentityClaim = prevKind, prevURL, prevClaim
	})

	prevFetch := fetchOIDCDiscovery
	fetchOIDCDiscovery = func(string) (*oidcDiscoveryDoc, error) {
		return &oidcDiscoveryDoc{
			DeviceAuthorizationEndpoint: srv.URL + "/protocol/openid-connect/auth/device",
			TokenEndpoint:               srv.URL + "/protocol/openid-connect/token",
			UserinfoEndpoint:            srv.URL + "/protocol/openid-connect/userinfo",
		}, nil
	}
	t.Cleanup(func() { fetchOIDCDiscovery = prevFetch })
}

func TestGenericOIDC_FullDeviceFlow_KeycloakShapedEndpoints(t *testing.T) {
	resetLimiterState(t)
	withMockOIDCProvider(t,
		func(w http.ResponseWriter, r *http.Request) {
			json.NewEncoder(w).Encode(deviceAuthResponse{
				DeviceCode: "dc-1", UserCode: "ABCD-EFGH",
				VerificationURIComplete: "https://idp.example.invalid/device?code=ABCD-EFGH",
				ExpiresIn:               600, Interval: 5,
			})
		},
		func(w http.ResponseWriter, r *http.Request) {
			json.NewEncoder(w).Encode(tokenResponse{AccessToken: "tok-keycloak"})
		},
		func(w http.ResponseWriter, r *http.Request) {
			json.NewEncoder(w).Encode(map[string]string{"preferred_username": "jsmith"})
		},
	)

	dev, err := providerDeviceAuthorize()
	if err != nil || dev.DeviceCode != "dc-1" {
		t.Fatalf("got dev=%+v err=%v", dev, err)
	}
	tok, _, outcome, _, err := providerPollToken(dev.DeviceCode)
	if err != nil || outcome != outcomeOK || tok != "tok-keycloak" {
		t.Fatalf("got tok=%q outcome=%v err=%v", tok, outcome, err)
	}
	user, err := providerVerifyIdentity(tok)
	if err != nil || user != "jsmith" {
		t.Fatalf("got user=%q err=%v, want preferred_username claim extracted", user, err)
	}
}

func TestGenericOIDC_CustomIdentityClaim(t *testing.T) {
	resetLimiterState(t)
	withMockOIDCProvider(t,
		func(w http.ResponseWriter, r *http.Request) {},
		func(w http.ResponseWriter, r *http.Request) {},
		func(w http.ResponseWriter, r *http.Request) {
			json.NewEncoder(w).Encode(map[string]string{"upn": "jsmith@corp.example"})
		},
	)
	cfg.OIDCIdentityClaim = "upn"

	user, err := providerVerifyIdentity("irrelevant-token")
	if err != nil || user != "jsmith@corp.example" {
		t.Fatalf("got user=%q err=%v, want the configured custom claim (upn) extracted", user, err)
	}
}

func TestGenericOIDC_MissingIdentityClaimRejected(t *testing.T) {
	resetLimiterState(t)
	withMockOIDCProvider(t,
		func(w http.ResponseWriter, r *http.Request) {},
		func(w http.ResponseWriter, r *http.Request) {},
		func(w http.ResponseWriter, r *http.Request) {
			json.NewEncoder(w).Encode(map[string]string{"sub": "1234"})
		},
	)
	if _, err := providerVerifyIdentity("irrelevant-token"); err == nil {
		t.Fatal("missing preferred_username (or configured claim) must be rejected, never silently accepted as an empty identity")
	}
}

func TestGenericOIDC_RateLimitPassthrough(t *testing.T) {
	resetLimiterState(t)
	withMockOIDCProvider(t,
		func(w http.ResponseWriter, r *http.Request) {},
		func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Retry-After", "42")
			w.WriteHeader(http.StatusTooManyRequests)
		},
		func(w http.ResponseWriter, r *http.Request) {},
	)
	_, oauthErr, outcome, retryAfter, err := providerPollToken("dc-1")
	if err != nil || outcome != outcomeRateLimit || oauthErr != "slow_down" || retryAfter != 42 {
		t.Fatalf("got outcome=%v oauthErr=%q retryAfter=%d err=%v, want rate-limit classification identical to the Authelia path", outcome, oauthErr, retryAfter, err)
	}
}

// --- config validation -----------------------------------------------------

func TestLoadConfig_ProviderKindOIDC_RequiresDiscoveryURL(t *testing.T) {
	c := defaultConfig()
	c.AllowedVerificationHost = "idp.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AllowedUsers = map[string]bool{"alice": true}
	c.ProviderKind = "oidc"
	c.OIDCDiscoveryURL = ""
	if err := c.Validate(); err == nil {
		t.Fatal("provider_kind=oidc with no oidc_discovery_url must be refused")
	}
}

func TestLoadConfig_ProviderKindOIDC_ValidAccepted(t *testing.T) {
	c := defaultConfig()
	c.AllowedVerificationHost = "idp.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AllowedUsers = map[string]bool{"alice": true}
	c.ProviderKind = "oidc"
	c.OIDCDiscoveryURL = "https://idp.example.invalid/.well-known/openid-configuration"
	if err := c.Validate(); err != nil {
		t.Fatalf("got err=%v, want a well-formed oidc-provider config to validate (authelia_base_url not required in this mode)", err)
	}
}

func TestLoadConfig_UnknownProviderKindRejected(t *testing.T) {
	c := defaultConfig()
	c.AutheliaBaseURL = "https://authelia.example.invalid"
	c.AllowedVerificationHost = "authelia.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AllowedUsers = map[string]bool{"alice": true}
	c.ProviderKind = "okta-direct"
	if err := c.Validate(); err == nil {
		t.Fatal("an unrecognized provider_kind must be refused, not silently ignored")
	}
}
