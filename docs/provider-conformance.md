# Provider conformance testing (v2.6.0)

`sddm-authelia-passkey-admin provider-test` (optional `--json`) runs a
real, live conformance check against the **currently configured**
identity provider - not a mocked one, and not an arbitrary issuer URL
argument (see "Scope" below). It reuses the exact same production
dispatch functions every real login flow uses
(`providerDeviceAuthorize`/`providerPollToken`,
`trustedVerificationOrigins`/`validateVerificationURI`) rather than
reimplementing any protocol logic - "standards-conformant behavior
stays in the generic code path" (`docs/roadmap.md`'s security
invariant #7).

## What it checks

| Key | Meaning | Applies to |
|---|---|---|
| `DISCOVERY` | the OIDC discovery document was fetched successfully | `provider_kind=oidc` only |
| `ISSUER_BINDING` | the discovery document's `issuer` matches what OpenID Connect Discovery 1.0 requires it to be, given the configured discovery URL | `provider_kind=oidc` only |
| `DEVICE_ENDPOINT` | a `device_authorization_endpoint` is advertised (oidc) / the hardcoded Authelia path is used (authelia) | both |
| `JWKS` | the discovery document's `jwks_uri` is reachable and returns a `keys` array (reachability/shape only - this broker does not itself validate ID token signatures, see `provider.go`) | `provider_kind=oidc` only |
| `TRUSTED_ORIGIN` | the trusted origin set for `verification_uri` validation could be derived | both |
| `VERIFICATION_URI` | a **real** device-authorization response's `verification_uri_complete` passes the exact same origin-based validation a real login flow would apply | both |
| `RFC8628_PENDING` | immediately polling the token endpoint - before any human could plausibly have approved the code - returns `authorization_pending`, per RFC 8628 | both |

## What this does on the real provider

Running this command creates one real, short-lived, unapproved
device-authorization session against the configured provider. It
**never requires human interaction**: `RFC8628_PENDING` polls
immediately, and a conformant provider is expected to answer
`authorization_pending` at that point - this is the very thing being
verified, not something worked around. The device code simply expires
on its own afterward; no account is touched and no login is ever
granted by running this command.

## Scope

This is deliberately **not** the full "Provider Conformance Lab" the
private roadmap's long-term vision describes (a reproducible
multi-provider test matrix with negative/malformed-response fixtures,
`slow_down`/`access_denied`/`expired_token` coverage, and a
machine-derived public support matrix). Those require either
driving a live provider through a genuinely denied/expired flow
(which needs a human to actually deny/ignore a real device code - out
of scope for an unattended command) or synthetic fixtures against a
mock provider (already covered by this project's existing Go test
suite, e.g. `src/broker/conformance_test.go`,
`src/broker/provider_test.go`). This command's job is narrower and
real: prove that *this specific, currently-configured* provider
behaves conformantly right now, using production code.

## Real validation

Validated on lab VM124 against the real, already-provisioned
infrastructure from v2.1.0: real Authelia (`authelia.s3-dev.ovh`) and
real Authentik (`auth.s3-lan.ovh`, dedicated
`sddm-authelia-passkey-lab` application). Keycloak remains
`NOT_TESTED` - no real instance is available in this environment,
matching this project's standing rule against fabricating provider
validation.
