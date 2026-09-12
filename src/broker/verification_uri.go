// verification_uri.go validates a provider's returned verification_uri
// (RFC 8628 SS3.3.1) with a provider-agnostic path/query but a
// provider-BOUND network origin:
//
//	TRUSTED_DISCOVERY_METADATA determines TRUSTED_ORIGINS
//	never: DEVICE_AUTHORIZATION_RESPONSE determines TRUSTED_ORIGINS
//
// The trusted origin set is derived only from configuration/discovery
// metadata this broker already fetched and validated *before* the
// device-authorization call that returns verification_uri - never from
// the verification_uri itself or any other part of that same response.
// This is deliberately not "Authelia's exact URL shape" (which broke
// real interoperability with any other real provider - see v2.1.0's
// Authentik lab validation) and not "any HTTPS URL" (which would let a
// compromised/misconfigured device-authorization response redirect a
// user's browser anywhere).
package main

import (
	"fmt"
	"net/url"
	"strings"
)

// canonicalOrigin returns "scheme://lowercased-host:effective-port" for
// an absolute URL, or an error if the URL is missing anything an origin
// requires. u.Hostname()/u.Port() (not the raw u.Host string) are used
// so bracketed IPv6 literals are handled correctly by the stdlib parser
// rather than by ad-hoc bracket-stripping here.
func canonicalOrigin(u *url.URL) (string, error) {
	if u.Scheme == "" || u.Host == "" {
		return "", fmt.Errorf("not an absolute URL with a host")
	}
	host := strings.ToLower(strings.TrimSuffix(u.Hostname(), "."))
	if host == "" {
		return "", fmt.Errorf("empty host")
	}
	port := u.Port()
	if port == "" {
		switch u.Scheme {
		case "https":
			port = "443"
		case "http":
			port = "80"
		default:
			return "", fmt.Errorf("unsupported scheme %q", u.Scheme)
		}
	}
	return u.Scheme + "://" + host + ":" + port, nil
}

// canonicalOriginFromRawURL parses raw (expected to come from
// already-trusted configuration or an already-validated discovery
// document, never from a device-authorization response) and returns its
// canonical origin.
func canonicalOriginFromRawURL(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	return canonicalOrigin(u)
}

// trustedOriginsForAuthelia reproduces this project's original,
// unchanged Authelia trust model: a single explicitly-configured origin
// (allowed_verification_host), independent of authelia_base_url so a
// reverse-proxy/CDN front-end can't silently redirect the QR code
// elsewhere without that also being updated deliberately. Authelia mode
// does no OIDC discovery, so there is no discovery document to derive
// trust from - this is exactly the "explicitly configured provider
// endpoint, itself treated as a trust anchor" case.
func trustedOriginsForAuthelia(allowedVerificationHost string, devInsecureHTTP bool) (map[string]bool, error) {
	scheme := "https"
	if devInsecureHTTP {
		scheme = "http"
	}
	origin, err := canonicalOriginFromRawURL(scheme + "://" + allowedVerificationHost)
	if err != nil {
		return nil, fmt.Errorf("invalid allowed_verification_host %q: %w", allowedVerificationHost, err)
	}
	return map[string]bool{origin: true}, nil
}

// trustedOriginsForOIDC derives the allowed origin set for a generic
// OIDC provider from its already-validated discovery document only:
//
//   - issuer is always included - it is the trust anchor the discovery
//     document's own issuer claim was already checked against.
//   - device_authorization_endpoint is always included - it is the exact
//     endpoint whose response contains the verification_uri being
//     validated.
//   - authorization_endpoint is included when present - a provider's
//     interactive user-facing flows legitimately live at that origin.
//   - token_endpoint and jwks_uri are deliberately NOT included: a
//     provider may run token/key infrastructure on a separate host from
//     its user-facing pages, and that alone must not authorize sending a
//     user's browser there.
func trustedOriginsForOIDC(d *oidcDiscoveryDoc) (map[string]bool, error) {
	origins := map[string]bool{}

	issuerOrigin, err := canonicalOriginFromRawURL(d.Issuer)
	if err != nil {
		return nil, fmt.Errorf("invalid issuer %q in discovery document: %w", d.Issuer, err)
	}
	origins[issuerOrigin] = true

	deviceOrigin, err := canonicalOriginFromRawURL(d.DeviceAuthorizationEndpoint)
	if err != nil {
		return nil, fmt.Errorf("invalid device_authorization_endpoint %q in discovery document: %w", d.DeviceAuthorizationEndpoint, err)
	}
	origins[deviceOrigin] = true

	if d.AuthorizationEndpoint != "" {
		authOrigin, err := canonicalOriginFromRawURL(d.AuthorizationEndpoint)
		if err != nil {
			return nil, fmt.Errorf("invalid authorization_endpoint %q in discovery document: %w", d.AuthorizationEndpoint, err)
		}
		origins[authOrigin] = true
	}

	return origins, nil
}

// trustedVerificationOrigins picks the trust-derivation strategy for the
// currently active provider. For provider_kind=oidc, oidcDiscover() is
// already cached by the providerDeviceAuthorize() call this always
// follows, so this does not trigger a second HTTP fetch.
func trustedVerificationOrigins() (map[string]bool, error) {
	if cfg.ProviderKind == "oidc" {
		d, err := oidcDiscover()
		if err != nil {
			return nil, err
		}
		return trustedOriginsForOIDC(d)
	}
	return trustedOriginsForAuthelia(cfg.AllowedVerificationHost, cfg.DevInsecureHTTP)
}

// validateVerificationURI enforces bounded length, no control
// characters, absolute-URL syntax, no userinfo, no fragment, an
// https scheme (http only if devInsecureHTTP), and that the URL's
// origin is a member of trustedOrigins. Path and query are
// deliberately never pattern-matched: once the origin is trusted, a
// provider's own path/query shape for its verification page is its own
// business (RFC 8628 does not mandate one), and this broker must not
// try to guess which query parameter carries the user code.
func validateVerificationURI(raw string, trustedOrigins map[string]bool, devInsecureHTTP bool) (string, error) {
	if len(raw) == 0 || len(raw) > 512 {
		return "", fmt.Errorf("length %d out of bounds", len(raw))
	}
	if strings.ContainsAny(raw, "\n\r\x00") {
		return "", fmt.Errorf("control characters present")
	}

	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if !u.IsAbs() || u.Host == "" {
		return "", fmt.Errorf("not an absolute URL with a host")
	}
	if u.User != nil {
		return "", fmt.Errorf("userinfo present in URL")
	}
	if u.Fragment != "" {
		return "", fmt.Errorf("fragment present in URL")
	}

	wantScheme := "https"
	if devInsecureHTTP {
		wantScheme = "http"
	}
	if u.Scheme != wantScheme {
		return "", fmt.Errorf("scheme %q", u.Scheme)
	}

	origin, err := canonicalOrigin(u)
	if err != nil {
		return "", err
	}
	if !trustedOrigins[origin] {
		return "", fmt.Errorf("origin %q is not a trusted provider origin", origin)
	}

	return raw, nil
}
