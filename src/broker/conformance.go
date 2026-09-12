// conformance.go implements --provider-test: a real (not mocked), live
// conformance check against the currently configured identity
// provider, using the exact same production dispatch functions
// (providerDeviceAuthorize/providerPollToken, trustedVerificationOrigins/
// validateVerificationURI) every real login flow uses - never a
// reimplementation. See docs/provider-conformance.md.
//
// This creates one real, short-lived, unapproved device-authorization
// session against the configured provider (it simply expires - no
// account is touched, no login is granted). It never requires human
// interaction: the RFC8628_PENDING check polls immediately, before any
// human could plausibly have approved the code, and a conformant
// provider is expected to answer "authorization_pending" at that
// point - this is itself the thing being verified, not worked around.
package main

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
)

type conformanceCheck struct {
	Name   string
	Status string // GREEN, RED, SKIP
	Detail string
}

func runProviderConformanceTest() []conformanceCheck {
	var checks []conformanceCheck
	add := func(name, status, detail string) {
		checks = append(checks, conformanceCheck{name, status, detail})
	}

	if cfg.ProviderKind == "oidc" {
		d, err := fetchOIDCDiscovery(cfg.OIDCDiscoveryURL)
		if err != nil {
			add("DISCOVERY", "RED", err.Error())
			add("ISSUER_BINDING", "RED", "skipped: discovery fetch failed")
			add("DEVICE_ENDPOINT", "RED", "skipped: discovery fetch failed")
			add("JWKS", "RED", "skipped: discovery fetch failed")
		} else {
			add("DISCOVERY", "GREEN", "")

			wantIssuer, ierr := expectedIssuerFromDiscoveryURL(cfg.OIDCDiscoveryURL)
			if ierr != nil {
				add("ISSUER_BINDING", "RED", ierr.Error())
			} else if strings.TrimSuffix(d.Issuer, "/") != strings.TrimSuffix(wantIssuer, "/") {
				add("ISSUER_BINDING", "RED", fmt.Sprintf("discovery issuer %q does not match expected %q", d.Issuer, wantIssuer))
			} else {
				add("ISSUER_BINDING", "GREEN", "")
			}

			if d.DeviceAuthorizationEndpoint == "" {
				add("DEVICE_ENDPOINT", "RED", "no device_authorization_endpoint advertised - RFC 8628 not supported")
			} else {
				add("DEVICE_ENDPOINT", "GREEN", "")
			}

			if d.JWKSURI == "" {
				add("JWKS", "RED", "no jwks_uri advertised")
			} else {
				resp, jerr := http.Get(d.JWKSURI)
				if jerr != nil {
					add("JWKS", "RED", jerr.Error())
				} else {
					defer resp.Body.Close()
					body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
					if resp.StatusCode == http.StatusOK && bytes.Contains(body, []byte(`"keys"`)) {
						add("JWKS", "GREEN", "")
					} else {
						add("JWKS", "RED", fmt.Sprintf("jwks_uri returned HTTP %d or no keys array", resp.StatusCode))
					}
				}
			}
		}
	} else {
		add("DISCOVERY", "SKIP", "provider_kind=authelia has no discovery document")
		add("ISSUER_BINDING", "SKIP", "provider_kind=authelia has no discovery document")
		add("DEVICE_ENDPOINT", "GREEN", "hardcoded Authelia path, unchanged since v0.1.0")
		add("JWKS", "SKIP", "provider_kind=authelia has no discovery document")
	}

	dev, err := providerDeviceAuthorize()
	if err != nil {
		add("VERIFICATION_URI", "RED", fmt.Sprintf("device-authorization request failed: %v", err))
		add("TRUSTED_ORIGIN", "RED", "skipped: device-authorization failed")
		add("RFC8628_PENDING", "RED", "skipped: device-authorization failed")
		return checks
	}

	trustedOrigins, oerr := trustedVerificationOrigins()
	if oerr != nil {
		add("TRUSTED_ORIGIN", "RED", oerr.Error())
		add("VERIFICATION_URI", "RED", "skipped: trusted origin set unavailable")
	} else {
		add("TRUSTED_ORIGIN", "GREEN", "")
		if _, verr := validateVerificationURI(dev.VerificationURIComplete, trustedOrigins, cfg.DevInsecureHTTP); verr != nil {
			add("VERIFICATION_URI", "RED", verr.Error())
		} else {
			add("VERIFICATION_URI", "GREEN", "")
		}
	}

	// Poll immediately - before any human could plausibly have opened
	// the verification URI - a conformant provider must answer
	// authorization_pending here, never a stale/cached success.
	_, oauthErr, outcome, _, perr := providerPollToken(dev.DeviceCode)
	switch {
	case perr != nil:
		add("RFC8628_PENDING", "RED", perr.Error())
	case outcome == outcomeOAuth && oauthErr == "authorization_pending":
		add("RFC8628_PENDING", "GREEN", "")
	default:
		add("RFC8628_PENDING", "RED", fmt.Sprintf("expected authorization_pending immediately after device-authorization, got oauthErr=%q", oauthErr))
	}

	return checks
}
