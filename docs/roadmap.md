# Roadmap: generic OIDC broker toward a general authentication mechanism framework

This documents the direction beyond v2.1.0, following the real-hardware
validation findings in `docs/validated-environment.md`. Only v2.1.0 is
fully implemented as of this writing; v2.2.0 onward are architecture/
design preparation only (see each milestone's linked doc, where one
exists) - not implemented, per this project's own standing rule against
premature large migrations.

The native-theme track (v1.8.0-v2.0.0, see `docs/native-theme.md`) is a
separate, already-completed line of work; this roadmap is specifically
about the broker/authentication side of the project going forward.

## Target architecture

```
                         SDDM
                          |
                          v
                   PAM / mechanism UI
                          |
              +-----------+-----------+
              |                       |
              v                       v
        Generic OIDC                SSSD
           broker                    |
              |               +------+------+
              |               |             |
         RFC 8628          NSS/RFC2307   Passkey/FIDO2
              |               |             |
   +----------+----------+    |             |
   |          |          |    |             |
Authelia   Authentik   Keycloak            |
   |          |          |                  |
   +----------+----+-----+                  |
              |                             |
        AUTHENTICATION                UNIX IDENTITY
              |                             |
              +--------------+--------------+
                             v
                       Linux session
```

**Central architecture rule:**

```
OIDC       = authentication proof
SSSD/NSS   = authoritative Unix identity
```

The OIDC broker must never become a second Unix identity store: no
independent UID/GID database, and no reimplementation of something
SSSD/NSS already does reliably. Hardware FIDO2/passkeys are intended to
run through `PAM -> SSSD -> libfido2`, not a broker-owned FIDO2
implementation - see `docs/fido2.md` for what's actually shipped today
(a straightforward `pam_u2f.so` stack addition) versus this longer-term
direction.

## Milestones

### v2.1.0 - Generic OIDC really provider-neutral (implemented)

Fixed `verification_uri` validation to be genuinely provider-agnostic
in path/query while staying origin-bound via already-validated
discovery metadata, instead of hardcoding Authelia's URL shape. Added
discovery-document issuer verification. Real-validated against a live
Authentik instance and a live Samba AD domain (see
`docs/validated-environment.md`); Keycloak and physical FIDO2 hardware
remain explicitly not tested (no instance/device available), not
silently waived.

### v2.2.0 - Identity binding & local-shadowing protection (implemented)

See `docs/identity-binding.md`. Closes a real finding from v2.1.0's
validation: NSS silently prefers a local `/etc/passwd` entry over a
same-named directory account depending on `nsswitch.conf` order, with
no reliable signal from an ordinary `getpwnam` call about which source
actually answered. Shipped `reject_local_shadowing`/
`required_identity_source` config keys, using NSS service-scoped
queries (`getent -s files`/`getent -s sss`) to detect and refuse a
genuine collision, not a UID-range heuristic.

### v2.3.0 - Debian production packaging & safe deployment (doctor implemented)

Shipped `sddm-authelia-passkey-admin doctor` (alias `diagnose`): a
read-only diagnostic checking `SDDM`, `PAM_CONFIG`, `BROKER_CONFIG`,
`BROKER`, `OIDC_DISCOVERY`, `JWKS` reachability, `NSS`, `SSSD`,
`IDENTITY_PROVENANCE`, `USER_COLLISIONS` (a systematic files-vs-sss
UID-collision scan, not just the one already-known case), and
`BREAK_GLASS` readiness, aggregated into a single `LOGIN_ENABLEMENT`
verdict - with `--explain`/`--json` output modes. Extends the existing
`preflight.sh`/`postflight.sh`/admin-CLI pattern rather than replacing
it; see `docs/doctor.md`. A versioned overall config schema, an
upgrade/downgrade compatibility matrix, and pre-change lockout
simulation remain design-only, deferred to a later iteration.

### v2.4.0 - SDDM rich authentication UI (capability discovery implemented)

Shipped a real, narrow subset: a read-only `GET /capabilities` broker
endpoint (`oidc_ready`, `fido2_wired`, `smartcard_ready` - always
`false`, honestly not implemented) polled independently of any login
flow, driving a small informational hint in the native theme only -
never a flow-control or security decision. See
`docs/capability-negotiation.md`. The full generic mechanism-selection
presentation (password / passkey / eIdP / smartcard as standardized,
negotiated mechanisms, conceptually similar to modern SSSD PAM
mechanism-selection UX, with dedicated PIN/touch/key-connected and
smartcard UI states) remains design-only, deferred to a later
iteration.

### v2.5.0 - Native SSSD passkey integration (investigated, blocked)

Direction: hardware FIDO2 via `SDDM -> PAM -> SSSD -> libfido2`, kept
architecturally separate from the OIDC broker (`docs/fido2.md`'s
existing `pam_u2f.so` stack is the current, shipped, simpler
alternative). Trust boundary: the OIDC broker is remote/web
authentication; SSSD passkey support is local hardware authentication -
these must not be blurred into one code path.

Real investigation on VM124 (see `docs/sssd-native-passkey.md`) found a
harder blocker than the already-known absence of physical FIDO2
hardware: Debian 13's own SSSD package (`2.10.1-2+b1`) does not appear
to include compiled passkey support at all - `pam_sss.so` has no
libfido2 linkage and no `passkey_child` helper binary exists, despite
`libfido2` itself being installed and `sssd.conf`'s man page
documenting the relevant config directives. No code implemented in
this milestone; the existing `pam_u2f.so` path remains the recommended,
real, shipped hardware-key mechanism.

### v2.6.0 - Multi-IdP / provider hardening (design only)

Direction: real (not mocked) validation against Authelia, Authentik,
*and* Keycloak once a real Keycloak instance is available, with
`provider_kind` special-casing kept to only the places a real,
unavoidable provider difference exists - standards-conformant behavior
stays in the generic code path (this is the same principle v2.1.0
applied to `verification_uri`).

### v2.7.0 - Offline & failure policy (design only)

Direction: explicitly documented behavior (not just incidental
behavior) for IdP/DNS/JWKS/SSSD/AD outages, expired discovery caches,
expired signing keys, network timeouts, user cancellation, device-flow
timeout, `slow_down`/`authorization_pending`/`access_denied`/
`expired_token`, distinguishing **fail closed** from a genuinely safe
local fallback. No automatic unsafe fallback.

### v3.0.0 - Generic authentication mechanism framework (design only)

Direction: this project's OIDC integration becomes one provider within
a more general SDDM/PAM authentication-mechanism model (password /
passkey / eIdP / smartcard / future mechanisms), rather than staying a
single-purpose "SDDM OIDC" project.

## Security invariants (apply across every milestone above)

1. No OIDC response may create trust for its own network origin (see
   `docs/architecture.md`'s "`verification_uri` trust model").
2. No successful OIDC authentication automatically implies a valid Unix
   account.
3. No Unix username collision may silently change identity semantics
   (v2.2.0).
4. No hardware FIDO2 implementation inside the OIDC broker (v2.5.0
   direction).
5. No UID/GID ownership model duplicated outside NSS/SSSD.
6. No arbitrary HTTPS verification URLs - origin must be provider-bound.
7. No provider-specific URL-shape assumptions.
8. No secrets in logs.
9. No PAM mutation without preflight + rollback capability.
10. No fake green: an integration is only ever documented as validated
    when it was checked against a real, live instance - see
    `docs/validated-environment.md`'s explicit TESTED/NOT TESTED
    convention.
