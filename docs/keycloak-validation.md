# Real Keycloak validation

This document records the real-provider validation used to close GitHub issue
[#86](https://github.com/BenJule/sddm-authelia-passkey/issues/86). It is
evidence of what was actually exercised, not a general claim that every
Keycloak release or configuration is supported.

## Tested baseline

- Date: 2026-09-13
- Project source: `main` at
  `7bd4e9a18730a2fd66b54ec67a5a6de662ff9a0e`
- Keycloak: **26.7.3**, official `quay.io/keycloak/keycloak:26.7.3` image
- Keycloak mode: disposable `start-dev` instance bound to loopback only
- Realm: disposable lab realm, deleted with the container after each run
- Client type: public OpenID Connect client
- Device Authorization Grant: enabled
- Standard, implicit, direct-access and service-account grants: disabled
- Requested scopes: `openid profile`
- Identity claim: `preferred_username`
- Broker provider mode: `provider_kind=oidc`
- Unix identity authority: the local/NSS account, never Keycloak

The lab used plain HTTP on `127.0.0.1` with
`authelia_dev_insecure_http=true` solely because the disposable Keycloak
`start-dev` instance was loopback-only. This does **not** relax the production
configuration rule: generic OIDC discovery must use HTTPS unless that explicit
development switch is enabled.

## Production-code conformance result

The broker was built from the source commit above. The only test-local source
change was the listening TCP port, so it could run beside an already-running
broker without touching port 7899. The test verified that this patch changed
only the `listenAddr` constant; provider, identity, marker and authentication
logic were byte-for-byte the project source.

`--provider-test --json` against the real Keycloak instance returned GREEN for
all of its production checks:

| Check | Result |
| --- | --- |
| OIDC discovery | GREEN |
| discovery issuer binding | GREEN |
| advertised device-authorization endpoint | GREEN |
| JWKS reachability/shape | GREEN |
| trusted verification-origin derivation | GREEN |
| `verification_uri_complete` origin validation | GREEN |
| immediate RFC 8628 `authorization_pending` | GREEN |

## Real end-to-end approval

A real RFC 8628 device flow was then started through the broker. A human logged
into the disposable Keycloak realm and granted the requested profile access.
The flow reached `approved` through the real token and userinfo endpoints.

The approved OIDC `preferred_username` matched the requested local username
exactly. Only after that exact match did the broker create its approval marker.
The marker was verified as `root:root`, mode `0600`, and contained both the
expected username and the NSS/local UID. Keycloak therefore remained an
authentication proof source; it did not become a Unix UID/GID authority.

## Real negative and RFC 8628 behaviour

The same disposable Keycloak 26.7.3 environment produced the following real
responses:

- an invalid device code returned HTTP 400 / `invalid_grant`; no access token
  was issued
- a nonexistent client was rejected with HTTP 401; no device code was issued
- a newly-created valid device code returned `authorization_pending`
- polling the same pending code too quickly returned `slow_down`
- a dedicated 15-second device-code lifetime test returned `expired_token`
  after the provider-side expiry deadline

The project's broker unit contract for `expired_token` was re-run immediately
against the same source and passed, confirming that the production broker
classifies that OAuth result as an expired/fail-closed flow.

`access_denied` was not separately forced in the live Keycloak run. Its broker
handling remains covered by the deterministic Go test suite and documented in
`docs/failure-policy.md`; issue #86 required `slow_down`/`access_denied` where
practical, not fabrication of a provider result that was not observed.

## Safety and isolation

The validation did not modify the installed production broker, PAM stack,
SDDM configuration or the provider currently used by the machine. Temporary
Keycloak and broker containers used dynamically-selected loopback ports, while
the existing broker on port 7899 remained untouched.

No lab password, device code, session identifier or other ephemeral credential
is retained in this repository.

## Support statement

Keycloak **26.7.3** is therefore **TESTED** for this project's generic OIDC
Device Authorization path with the configuration described above. Other
Keycloak versions/configurations remain expected-but-unverified unless they are
listed separately as tested. The generic OIDC implementation remains the same
provider-neutral code path used for Authentik; there is no Keycloak-specific
authentication branch.
