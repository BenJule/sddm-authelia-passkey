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
// Issuer and AuthorizationEndpoint are not otherwise used by this
// provider's device-flow calls, but both are trust anchors: Issuer is
// verified against the configured discovery URL, and both feed
// trustedOriginsForOIDC() - the only two other origins (besides
// DeviceAuthorizationEndpoint) a returned verification_uri is ever
// allowed to point at. See verification_uri.go.
type oidcDiscoveryDoc struct {
	Issuer                      string `json:"issuer"`
	AuthorizationEndpoint       string `json:"authorization_endpoint"`
	DeviceAuthorizationEndpoint string `json:"device_authorization_endpoint"`
	TokenEndpoint               string `json:"token_endpoint"`
	UserinfoEndpoint            string `json:"userinfo_endpoint"`
	// JWKSURI is only used by the v2.6.0 --provider-test conformance
	// check (reachability/shape only, see conformance.go) - this broker
	// does not itself validate ID token signatures against it (identity
	// is established via the userinfo endpoint, see verifyUserinfo/
	// genericOIDCVerifyIdentity), so it plays no role in the trust
	// chain verification_uri.go implements.
	JWKSURI string `json:"jwks_uri"`
}

var (
	oidcDiscoveryMu    sync.Mutex
	oidcDiscoveryCache *oidcDiscoveryDoc
)

// providerHTTPClient bounds every outbound broker->identity-provider HTTP
// call (discovery, device-authorization, token, userinfo/JWKS). Unlike
// the QML side (armRequestTimeout, v1.18.0), none of these calls
// previously had any timeout at all - a provider that accepts a TCP
// connection but never responds would hang the calling goroutine
// forever. For pollAndDecide's polling loop specifically, that would
// leak the flow's background goroutine indefinitely rather than
// reaching any terminal state - the exact "network timeout" failure
// case docs/failure-policy.md documents. 15s comfortably exceeds any
// real provider's normal response time (device-authorization/token/
// userinfo calls are all single, synchronous round trips) while still
// bounding the worst case to a fixed, small delay.
var providerHTTPClient = &http.Client{Timeout: 15 * time.Second}

// fetchOIDCDiscovery is a var so tests can stub it without a real HTTP
// round-trip.
var fetchOIDCDiscovery = func(discoveryURL string) (*oidcDiscoveryDoc, error) {
	resp, err := providerHTTPClient.Get(discoveryURL)
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
	if d.Issuer == "" {
		return nil, fmt.Errorf("provider at %s does not advertise an issuer", cfg.OIDCDiscoveryURL)
	}
	wantIssuer, err := expectedIssuerFromDiscoveryURL(cfg.OIDCDiscoveryURL)
	if err != nil {
		return nil, fmt.Errorf("cannot derive expected issuer from oidc_discovery_url: %w", err)
	}
	// Some real providers (Authentik among them) report a path-based
	// issuer with a trailing slash even though the well-known URL
	// construction in OpenID Connect Discovery 1.0 SS4.1 requires that
	// slash to be removed before appending the well-known suffix - so a
	// single optional trailing slash is tolerated on either side, but
	// nothing else about the comparison is relaxed.
	if strings.TrimSuffix(d.Issuer, "/") != strings.TrimSuffix(wantIssuer, "/") {
		return nil, fmt.Errorf("discovery document issuer %q does not match the configured discovery URL (expected %q) - refusing untrusted provider metadata", d.Issuer, wantIssuer)
	}
	oidcDiscoveryCache = d
	return d, nil
}

// expectedIssuerFromDiscoveryURL derives the issuer identifier OpenID
// Connect Discovery 1.0 requires a well-known discovery URL to be built
// from (issuer + "/.well-known/openid-configuration", or the RFC 8414
// "/.well-known/oauth-authorization-server" variant), so the discovery
// document's own "issuer" claim can be checked against it rather than
// trusted merely because it arrived over the network.
func expectedIssuerFromDiscoveryURL(discoveryURL string) (string, error) {
	for _, suffix := range []string{
		"/.well-known/openid-configuration",
		"/.well-known/oauth-authorization-server",
	} {
		if strings.HasSuffix(discoveryURL, suffix) {
			return strings.TrimSuffix(discoveryURL, suffix), nil
		}
	}
	return "", fmt.Errorf("oidc_discovery_url %q does not end in a recognized well-known discovery suffix", discoveryURL)
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
	resp, err := providerHTTPClient.PostForm(d.DeviceAuthorizationEndpoint, form)
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
	resp, err := providerHTTPClient.PostForm(d.TokenEndpoint, form)
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
	resp, err := providerHTTPClient.Do(req)
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
