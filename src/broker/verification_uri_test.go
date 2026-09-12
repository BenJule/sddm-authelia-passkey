package main

import "testing"

// --- canonicalOrigin: syntax, normalization, and origin equality -------

func TestCanonicalOrigin_DefaultHTTPSPortNormalization(t *testing.T) {
	a, err := canonicalOriginFromRawURL("https://id.example.com")
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalOriginFromRawURL("https://id.example.com:443")
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("expected https://id.example.com and :443 to be the same origin, got %q vs %q", a, b)
	}
}

func TestCanonicalOrigin_DefaultHTTPPortNormalization(t *testing.T) {
	a, err := canonicalOriginFromRawURL("http://id.example.com")
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalOriginFromRawURL("http://id.example.com:80")
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("expected http://id.example.com and :80 to be the same origin, got %q vs %q", a, b)
	}
}

func TestCanonicalOrigin_DifferentPortIsDifferentOrigin(t *testing.T) {
	a, err := canonicalOriginFromRawURL("https://id.example.com")
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalOriginFromRawURL("https://id.example.com:8443")
	if err != nil {
		t.Fatal(err)
	}
	if a == b {
		t.Fatalf("expected :8443 to be a different origin than the default port, got equal %q", a)
	}
}

func TestCanonicalOrigin_HostnameCaseNormalized(t *testing.T) {
	a, err := canonicalOriginFromRawURL("https://ID.Example.COM")
	if err != nil {
		t.Fatal(err)
	}
	b, err := canonicalOriginFromRawURL("https://id.example.com")
	if err != nil {
		t.Fatal(err)
	}
	if a != b {
		t.Fatalf("expected case-insensitive hostname match, got %q vs %q", a, b)
	}
}

func TestCanonicalOrigin_DifferentHostIsDifferentOrigin(t *testing.T) {
	a, _ := canonicalOriginFromRawURL("https://login.example.com")
	b, _ := canonicalOriginFromRawURL("https://id.example.com")
	if a == b {
		t.Fatal("different hosts under the same parent domain must not be the same origin")
	}
}

// --- trustedOriginsForOIDC: only issuer/device_auth/authorization -----

func exampleDiscoveryDoc() *oidcDiscoveryDoc {
	return &oidcDiscoveryDoc{
		Issuer:                      "https://issuer.example",
		AuthorizationEndpoint:       "https://login.example/authorize",
		DeviceAuthorizationEndpoint: "https://device.example/oauth/device",
		TokenEndpoint:               "https://token.example/token",
		UserinfoEndpoint:            "https://issuer.example/userinfo",
	}
}

func TestTrustedOriginsForOIDC_IncludesIssuerDeviceAuthAndAuthorization(t *testing.T) {
	origins, err := trustedOriginsForOIDC(exampleDiscoveryDoc())
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"https://issuer.example", "https://device.example", "https://login.example"} {
		o, _ := canonicalOriginFromRawURL(want)
		if !origins[o] {
			t.Fatalf("expected %q to be a trusted origin, set = %v", want, origins)
		}
	}
}

func TestTrustedOriginsForOIDC_ExcludesTokenEndpointAndJWKS(t *testing.T) {
	origins, err := trustedOriginsForOIDC(exampleDiscoveryDoc())
	if err != nil {
		t.Fatal(err)
	}
	tokenOrigin, _ := canonicalOriginFromRawURL("https://token.example")
	keysOrigin, _ := canonicalOriginFromRawURL("https://keys.example")
	if origins[tokenOrigin] {
		t.Fatal("token_endpoint's origin must not be trusted for verification_uri merely because it's the token endpoint")
	}
	if origins[keysOrigin] {
		t.Fatal("jwks_uri's origin must not be trusted for verification_uri")
	}
}

func TestTrustedOriginsForOIDC_MissingAuthorizationEndpointIsNotFatal(t *testing.T) {
	d := exampleDiscoveryDoc()
	d.AuthorizationEndpoint = ""
	origins, err := trustedOriginsForOIDC(d)
	if err != nil {
		t.Fatalf("unexpected error with no authorization_endpoint: %v", err)
	}
	if len(origins) != 2 {
		t.Fatalf("expected exactly 2 origins (issuer, device_authorization), got %v", origins)
	}
}

// --- trustedOriginsForAuthelia: unchanged single-origin trust model ---

func TestTrustedOriginsForAuthelia_SingleConfiguredOrigin(t *testing.T) {
	origins, err := trustedOriginsForAuthelia("idp.example.com", false)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := canonicalOriginFromRawURL("https://idp.example.com")
	if len(origins) != 1 || !origins[want] {
		t.Fatalf("expected exactly one origin %q, got %v", want, origins)
	}
}

func TestTrustedOriginsForAuthelia_DevInsecureHTTPUsesHTTPScheme(t *testing.T) {
	origins, err := trustedOriginsForAuthelia("idp.example.com", true)
	if err != nil {
		t.Fatal(err)
	}
	want, _ := canonicalOriginFromRawURL("http://idp.example.com")
	if !origins[want] {
		t.Fatalf("expected http origin under devInsecureHTTP, got %v", origins)
	}
}

// --- validateVerificationURI: the full origin-bound matrix -------------

func trustedSetFrom(rawURLs ...string) map[string]bool {
	set := map[string]bool{}
	for _, raw := range rawURLs {
		o, err := canonicalOriginFromRawURL(raw)
		if err != nil {
			panic(err)
		}
		set[o] = true
	}
	return set
}

// The exact matrix from the v2.1.0 review: four distinct provider
// endpoint origins, only three of which (issuer, device_authorization,
// authorization) may ever be a verification_uri target.
var reviewMatrixTrustedOrigins = trustedSetFrom(
	"https://issuer.example",
	"https://device.example",
	"https://login.example",
)

func TestValidateVerificationURI_ReviewMatrix_IssuerOriginAllowed(t *testing.T) {
	if _, err := validateVerificationURI("https://issuer.example/whatever?x=1", reviewMatrixTrustedOrigins, false); err != nil {
		t.Fatalf("issuer origin must be allowed: %v", err)
	}
}

func TestValidateVerificationURI_ReviewMatrix_DeviceAuthOriginAllowed(t *testing.T) {
	if _, err := validateVerificationURI("https://device.example/device?code=ABC", reviewMatrixTrustedOrigins, false); err != nil {
		t.Fatalf("device_authorization_endpoint origin must be allowed: %v", err)
	}
}

func TestValidateVerificationURI_ReviewMatrix_AuthorizationOriginAllowed(t *testing.T) {
	if _, err := validateVerificationURI("https://login.example/oauth/device/verify", reviewMatrixTrustedOrigins, false); err != nil {
		t.Fatalf("authorization_endpoint origin must be allowed: %v", err)
	}
}

func TestValidateVerificationURI_ReviewMatrix_TokenOriginDenied(t *testing.T) {
	if _, err := validateVerificationURI("https://token.example/device", reviewMatrixTrustedOrigins, false); err == nil {
		t.Fatal("token_endpoint's origin must be denied")
	}
}

func TestValidateVerificationURI_ReviewMatrix_JWKSOriginDenied(t *testing.T) {
	if _, err := validateVerificationURI("https://keys.example/device", reviewMatrixTrustedOrigins, false); err == nil {
		t.Fatal("jwks_uri's origin must be denied")
	}
}

func TestValidateVerificationURI_ReviewMatrix_UnrelatedOriginDenied(t *testing.T) {
	if _, err := validateVerificationURI("https://evil.example/device", reviewMatrixTrustedOrigins, false); err == nil {
		t.Fatal("a completely unrelated origin must be denied")
	}
}

// --- provider-specific path/query must now be fully accepted ----------

func TestValidateVerificationURI_ProviderSpecificPathsAllowed(t *testing.T) {
	trusted := trustedSetFrom("https://idp.example.com")
	for _, raw := range []string{
		"https://idp.example.com/device?code=ABC",
		"https://idp.example.com/consent/openid/device-authorization?user_code=ABC",
		"https://idp.example.com/oauth/device/verify",
		"https://idp.example.com/custom/path?a=1&b=2",
	} {
		if _, err := validateVerificationURI(raw, trusted, false); err != nil {
			t.Errorf("%q: expected acceptance once origin is trusted, got error: %v", raw, err)
		}
	}
}

func TestValidateVerificationURI_QueryParamOrderIrrelevant(t *testing.T) {
	trusted := trustedSetFrom("https://idp.example.com")
	if _, err := validateVerificationURI("https://idp.example.com/device?b=2&a=1", trusted, false); err != nil {
		t.Fatalf("query parameter order must not matter: %v", err)
	}
}

// --- negative cases: origin confusion attempts -------------------------

func TestValidateVerificationURI_LookalikeSuffixDomainDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	for _, raw := range []string{
		"https://trusted.example.evil.example/device",
		"https://eviltrusted.example/device",
		"https://subdomain.trusted.example/device",
	} {
		if _, err := validateVerificationURI(raw, trusted, false); err == nil {
			t.Errorf("%q: lookalike/subdomain must be denied unless itself explicitly trusted", raw)
		}
	}
}

func TestValidateVerificationURI_SameHostDifferentPortDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("https://trusted.example:8443/device", trusted, false); err == nil {
		t.Fatal("same host but different port must be a different origin")
	}
}

func TestValidateVerificationURI_SameRegistrableDomainDifferentHostDenied(t *testing.T) {
	trusted := trustedSetFrom("https://login.trusted.example")
	if _, err := validateVerificationURI("https://cdn.trusted.example/device", trusted, false); err == nil {
		t.Fatal("same registrable domain but different host must be denied")
	}
}

func TestValidateVerificationURI_UserinfoAtTrustedHostDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("https://user@trusted.example/device", trusted, false); err == nil {
		t.Fatal("userinfo component must be rejected outright, even with a trusted host")
	}
}

func TestValidateVerificationURI_TrustedHostAsUserinfoForEvilHostDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("https://trusted.example@evil.example/device", trusted, false); err == nil {
		t.Fatal("trusted-looking userinfo in front of a different actual host must be denied")
	}
}

func TestValidateVerificationURI_SchemeRelativeDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("//trusted.example/device", trusted, false); err == nil {
		t.Fatal("scheme-relative URL must be denied (not absolute)")
	}
}

func TestValidateVerificationURI_RelativeURLDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("/device?code=ABC", trusted, false); err == nil {
		t.Fatal("relative URL must be denied (no host)")
	}
}

func TestValidateVerificationURI_HTTPDowngradeDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("http://trusted.example/device", trusted, false); err == nil {
		t.Fatal("http must be denied when https is required")
	}
}

func TestValidateVerificationURI_FragmentDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("https://trusted.example/device#something", trusted, false); err == nil {
		t.Fatal("fragment must be rejected outright")
	}
}

func TestValidateVerificationURI_JavascriptSchemeDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("javascript:alert(1)", trusted, false); err == nil {
		t.Fatal("javascript: scheme must be denied")
	}
}

func TestValidateVerificationURI_DataSchemeDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("data:text/html,<script>alert(1)</script>", trusted, false); err == nil {
		t.Fatal("data: scheme must be denied")
	}
}

func TestValidateVerificationURI_FileSchemeDenied(t *testing.T) {
	trusted := trustedSetFrom("https://trusted.example")
	if _, err := validateVerificationURI("file:///etc/passwd", trusted, false); err == nil {
		t.Fatal("file: scheme must be denied")
	}
}

func TestValidateVerificationURI_URLEncodedQueryAllowedOnTrustedOrigin(t *testing.T) {
	trusted := trustedSetFrom("https://idp.example.com")
	if _, err := validateVerificationURI("https://idp.example.com/device?code=AB%2DCD%20EF", trusted, false); err != nil {
		t.Fatalf("URL-encoded query values must not themselves be rejected once the origin is trusted: %v", err)
	}
}

// Hostname comparison is an exact, case-insensitive ASCII/lowercased
// string match - deliberately NOT IDNA-normalized. A Unicode lookalike
// hostname therefore fails closed (rejected as a non-matching origin)
// rather than being silently treated as equivalent to a trusted ASCII
// hostname; the reverse (a legitimately IDNA-equivalent hostname
// written differently than the trusted set) would be a availability/
// compatibility gap, never a security one, since trusted origins come
// from admin configuration/discovery metadata that is realistically
// always ASCII already.
func TestValidateVerificationURI_UnicodeLookalikeHostDenied(t *testing.T) {
	trusted := trustedSetFrom("https://xn--exmple-cua.com") // trusted.example's real ASCII/punycode form is irrelevant here; the point is exact string match
	if _, err := validateVerificationURI("https://еxample.com/device", trusted, false); err == nil {
		t.Fatal("a Unicode-lookalike hostname must not be silently treated as equivalent to a trusted ASCII hostname")
	}
}

func TestValidateVerificationURI_ResponseSelectedNewOriginDenied(t *testing.T) {
	// Simulates a device-authorization response trying to introduce an
	// origin that was never part of trustedProviderOrigins - the origin
	// set must come only from already-validated configuration/discovery,
	// never be expanded by the response being validated against it.
	trusted := trustedSetFrom("https://device.example")
	if _, err := validateVerificationURI("https://attacker-controlled.example/device", trusted, false); err == nil {
		t.Fatal("an origin not present in the pre-derived trusted set must be denied")
	}
}
