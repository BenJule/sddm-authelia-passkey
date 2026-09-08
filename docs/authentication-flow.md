# Authentication flow details

See `docs/architecture.md` for the full sequence diagram. This document
covers the protocol-level specifics.

## OAuth2 Device Authorization Grant (RFC 8628)

The broker implements the device flow independently (no vendored OIDC
client library), against these Authelia endpoints:

- `POST /api/oidc/device-authorization` - `client_id`, `scope`. Returns
  `device_code`, `user_code`, `verification_uri`,
  `verification_uri_complete`, `expires_in`, `interval`.
- `POST /api/oidc/token` - polls with `grant_type=urn:ietf:params:oauth:
  grant-type:device_code`, `device_code`, `client_id`. Response is either
  a token, or an OAuth error: `authorization_pending` (keep polling at
  `interval`), `slow_down` (increase the polling interval by 5s per RFC
  8628 §6.1 and retry), or a terminal error.
- `GET /api/oidc/userinfo` - `Authorization: Bearer <token>`. The
  broker requires the `authelia.pam.username` claim and rejects the
  approval outright if it does not exactly match the username the flow
  was started for - this is the actual identity check, not the marker
  file (which only proves *some* approved flow exists for that
  filesystem-safe username string).

`slow_down` is handled distinctly from a generic HTTP 429 from an
intermediary rate limiter without a device-flow-aware JSON body - both
back off, but only the former increases the polling interval per-spec;
see `pollToken` in `src/broker/main.go`.

## verification_uri_complete validation

Never trusted blindly - `validateVerificationURI` in `src/broker/main.go`
enforces: `https://` scheme (or `http://` only with
`authelia_dev_insecure_http=true`), an exact configured host match, the
exact expected consent path, only a `user_code` query parameter, bounded
length, and no control characters. This exists because the QR code is
the one thing rendered to an untrusted display (SDDM's greeter, before
login) from data returned by a network response.

## WebAuthn / Passkey user verification

Authelia performs the actual WebAuthn ceremony; this project only
consumes its result. See `docs/security.md` for exactly what that result
does and does not prove.
