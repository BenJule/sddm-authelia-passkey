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

`provider-test` remains deliberately narrower than a complete provider
conformance laboratory. It proves that the configured provider's live
discovery/device/JWKS/origin/pending path works through production code;
it does not itself automate human approval/denial or rewrite the
provider's behaviour into synthetic fixtures.

The existing Go suite covers deterministic malformed/error responses.
Real-provider validation may additionally exercise RFC 8628 outcomes
outside `provider-test` when practical. The Keycloak closure run below
therefore included real `authorization_pending`, `slow_down`,
`expired_token`, invalid-device-code and invalid-client responses plus a
human-approved end-to-end flow. `access_denied` was not artificially
manufactured and remains covered by the broker regression suite and
`docs/failure-policy.md`.

## Real validation

### Authelia

Real and continuously exercised in the project's lab/production path.
The `provider_kind=authelia` compatibility path retains its explicit
Authelia endpoint handling and configured verification-host trust model.

### Authentik

Real validation was completed against a dedicated Authentik OIDC lab
application using Device Code grant, a public client and minimal scopes.
That run originally exposed the provider-neutral `verification_uri`
origin-validation gap fixed during the v2.1/v2.6 hardening work.

### Keycloak 26.7.3

**TESTED on 2026-09-13 against a real Keycloak 26.7.3 instance.**

The disposable lab used the official
`quay.io/keycloak/keycloak:26.7.3` image, an isolated realm, a public OIDC
client with Device Authorization Grant enabled, `openid profile`, and
`preferred_username` as the identity claim. Standard/implicit/direct
access/service-account grants were disabled for the test client.

The production broker's `--provider-test --json` returned GREEN for:

- discovery
- exact issuer binding
- advertised device-authorization endpoint
- JWKS reachability/shape
- trusted verification-origin derivation
- real `verification_uri_complete` origin validation
- immediate RFC 8628 `authorization_pending`

A separate real end-to-end device flow was approved interactively and
reached the broker's `approved` state. The returned
`preferred_username` matched the requested local username exactly; only
then was a root-owned `0600` approval marker created with the expected
local/NSS UID.

Real negative/edge observations from the same Keycloak version:

- invalid device code -> HTTP 400 / `invalid_grant`
- nonexistent client -> HTTP 401, no device code
- rapid token polling -> `slow_down`
- deliberately short-lived device code -> `expired_token`

The installed/production broker, PAM and SDDM configuration were not
changed during this validation; disposable Keycloak/broker test
instances used isolated loopback ports. Full reproducibility notes,
transport caveats and evidence are in `docs/keycloak-validation.md`.

The support statement is intentionally version-specific: **Keycloak
26.7.3 is TESTED with the documented configuration**. Other Keycloak
versions/configurations remain expected-but-unverified until separately
validated.
