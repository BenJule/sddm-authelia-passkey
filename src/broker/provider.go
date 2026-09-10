// provider.go abstracts the three OIDC/RFC 8628 interactions the broker
// needs (device-authorization, token polling, identity verification)
// behind cfg.ProviderKind, so this project can talk to any standards-
// compliant OIDC Device Authorization Grant provider - Authelia (the
// original, default, hardcoded-path behavior - completely unchanged from
// every prior release), Keycloak, Authentik, or any other provider that
// publishes an OIDC discovery document - without any provider-specific
// logic ever reaching the QML theme, which only ever talks to this
// broker's own localhost API exactly as before.
//
// Deliberately NOT a Go interface with multiple concrete types wired
// through every call site: the existing deviceAuthorize/pollToken/
// verifyUserinfo functions (and every test exercising them directly)
// stay completely untouched for provider_kind=authelia (the default) -
// providerDeviceAuthorize/providerPollToken/providerVerifyIdentity below
// are the only new call sites, and they simply dispatch to the unchanged
// Authelia-specific functions unless a generic OIDC provider is
// explicitly configured. This keeps the already-proven Authelia code
// path's risk at zero while still giving other providers a real,
// standards-based integration.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// oidcDiscoveryDoc holds only the fields this broker actually needs from
// an OIDC discovery document (RFC 8414 / OpenID Connect Discovery 1.0).
type oidcDiscoveryDoc struct {
	DeviceAuthorizationEndpoint string `json:"device_authorization_endpoint"`
	TokenEndpoint               string `json:"token_endpoint"`
	UserinfoEndpoint            string `json:"userinfo_endpoint"`
}

var (
	oidcDiscoveryMu    sync.Mutex
	oidcDiscoveryCache *oidcDiscoveryDoc
)

// fetchOIDCDiscovery is a var so tests can stub it without a real HTTP
// round-trip.
var fetchOIDCDiscovery = func(discoveryURL string) (*oidcDiscoveryDoc, error) {
	resp, err := http.Get(discoveryURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("oidc discovery: HTTP %d: %s", resp.StatusCode, body)
	}
	var d oidcDiscoveryDoc
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		return nil, err
	}
	return &d, nil
}

// oidcDiscover fetches and caches the discovery document (once per
// broker run - a restart re-fetches). Fails closed: capability
// detection is simply "does the document advertise
// device_authorization_endpoint" - if not, this provider does not
// support RFC 8628 and every call refuses rather than guessing at a
// conventional path.
func oidcDiscover() (*oidcDiscoveryDoc, error) {
	oidcDiscoveryMu.Lock()
	defer oidcDiscoveryMu.Unlock()
	if oidcDiscoveryCache != nil {
		return oidcDiscoveryCache, nil
	}
	if cfg.OIDCDiscoveryURL == "" {
		return nil, fmt.Errorf("provider_kind=oidc requires oidc_discovery_url")
	}
	d, err := fetchOIDCDiscovery(cfg.OIDCDiscoveryURL)
	if err != nil {
		return nil, fmt.Errorf("oidc discovery fetch failed: %w", err)
	}
	if d.DeviceAuthorizationEndpoint == "" {
		return nil, fmt.Errorf("provider at %s does not advertise device_authorization_endpoint - RFC 8628 device authorization is not supported", cfg.OIDCDiscoveryURL)
	}
	if d.TokenEndpoint == "" {
		return nil, fmt.Errorf("provider at %s does not advertise token_endpoint", cfg.OIDCDiscoveryURL)
	}
	if d.UserinfoEndpoint == "" {
		return nil, fmt.Errorf("provider at %s does not advertise userinfo_endpoint", cfg.OIDCDiscoveryURL)
	}
	oidcDiscoveryCache = d
	return d, nil
}

func genericOIDCDeviceAuthorize() (*deviceAuthResponse, error) {
	d, err := oidcDiscover()
	if err != nil {
		return nil, err
	}
	form := url.Values{
		"client_id": {cfg.OIDCClientID},
		"scope":     {cfg.OIDCScopes},
	}
	resp, err := http.PostForm(d.DeviceAuthorizationEndpoint, form)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return nil, fmt.Errorf("device-authorization: HTTP %d: %s", resp.StatusCode, body)
	}
	var dr deviceAuthResponse
	if err := json.NewDecoder(resp.Body).Decode(&dr); err != nil {
		return nil, err
	}
	return &dr, nil
}

// genericOIDCPollToken mirrors pollToken's exact outcome classification
// (see that function's doc comment for why rate-limit/ambiguous/OAuth
// outcomes are distinguished) against a discovered token_endpoint
// instead of Authelia's hardcoded path.
func genericOIDCPollToken(deviceCode string) (accessToken string, oauthErr string, outcome pollOutcome, retryAfterSeconds int, err error) {
	d, derr := oidcDiscover()
	if derr != nil {
		return "", "", outcomeAmbiguous, 0, derr
	}
	form := url.Values{
		"grant_type":  {"urn:ietf:params:oauth:grant-type:device_code"},
		"device_code": {deviceCode},
		"client_id":   {cfg.OIDCClientID},
	}
	resp, err := http.PostForm(d.TokenEndpoint, form)
	if err != nil {
		return "", "", outcomeAmbiguous, 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests {
		ra, _ := parseRetryAfter(resp.Header.Get("Retry-After"), time.Now())
		io.Copy(io.Discard, resp.Body)
		return "", "slow_down", outcomeRateLimit, ra, nil
	}
	var t tokenResponse
	if decodeErr := json.NewDecoder(resp.Body).Decode(&t); decodeErr != nil {
		return "", "", outcomeAmbiguous, 0, nil
	}
	if resp.StatusCode != http.StatusOK {
		if t.Error == "" {
			return "", "", outcomeAmbiguous, 0, nil
		}
		return "", t.Error, outcomeOAuth, 0, nil
	}
	return t.AccessToken, "", outcomeOK, 0, nil
}

// genericOIDCVerifyIdentity extracts cfg.OIDCIdentityClaim (default
// "preferred_username" - the standard OIDC claim most providers,
// including Keycloak and Authentik, populate with the local account
// name) from the userinfo response, exactly analogous to verifyUserinfo
// reading Authelia's "authelia.pam.username" claim. The exact-match
// AUTHENTICATED_..._USER == REQUESTED_LOCAL_USER identity-binding check
// in pollAndDecide is completely unaware of which provider or claim name
// produced this value.
func genericOIDCVerifyIdentity(accessToken string) (string, error) {
	d, err := oidcDiscover()
	if err != nil {
		return "", err
	}
	claimName := cfg.OIDCIdentityClaim
	if claimName == "" {
		claimName = "preferred_username"
	}
	req, _ := http.NewRequest(http.MethodGet, d.UserinfoEndpoint, nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return "", fmt.Errorf("userinfo: HTTP %d: %s", resp.StatusCode, body)
	}
	var claims map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&claims); err != nil {
		return "", err
	}
	u, _ := claims[claimName].(string)
	if u == "" {
		return "", fmt.Errorf("%s claim missing from userinfo response", claimName)
	}
	return u, nil
}

// The three dispatch points every call site in main.go uses instead of
// calling deviceAuthorize/pollToken/verifyUserinfo directly - the ONLY
// new call sites this abstraction introduces. provider_kind=authelia
// (the default, and the value an upgraded pre-v0.7.0 config implicitly
// has since the key didn't exist before) always dispatches to the
// original, completely unmodified functions.

func providerDeviceAuthorize() (*deviceAuthResponse, error) {
	if cfg.ProviderKind == "oidc" {
		return genericOIDCDeviceAuthorize()
	}
	return deviceAuthorize()
}

func providerPollToken(deviceCode string) (accessToken string, oauthErr string, outcome pollOutcome, retryAfterSeconds int, err error) {
	if cfg.ProviderKind == "oidc" {
		return genericOIDCPollToken(deviceCode)
	}
	return pollToken(deviceCode)
}

func providerVerifyIdentity(accessToken string) (string, error) {
	if cfg.ProviderKind == "oidc" {
		return genericOIDCVerifyIdentity(accessToken)
	}
	return verifyUserinfo(accessToken)
}

// isKnownProviderKind guards config validation - never silently accept
// an unrecognized value.
func isKnownProviderKind(k string) bool {
	switch strings.ToLower(k) {
	case "", "authelia", "oidc":
		return true
	default:
		return false
	}
}
