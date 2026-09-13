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

### v2.6.0 - Multi-IdP / provider hardening (conformance test implemented)

Shipped `sddm-authelia-passkey-admin provider-test`: a real, live
conformance check against the currently configured provider (discovery,
issuer binding, device endpoint, `verification_uri` trust origin, JWKS
reachability, RFC 8628 `authorization_pending`), reusing the exact same
production dispatch functions every real login flow uses - never a
reimplementation. See `docs/provider-conformance.md`. Real (not mocked)
validation against Authelia and Authentik, `provider_kind`
special-casing kept to only the places a real, unavoidable provider
difference exists - standards-conformant behavior stays in the generic
code path (the same principle v2.1.0 applied to `verification_uri`).
Real validation against Keycloak remains deferred - no real instance is
available in this environment - and a full multi-provider conformance
lab (negative/malformed fixtures, `slow_down`/`access_denied` coverage,
an automatically-derived public support matrix) remains design-only.

### v2.7.0 - Offline & failure policy (implemented)

Explicitly documented, traced-to-code behavior for every enumerated
failure case - IdP/DNS/JWKS/SSSD/AD outages, network timeouts, user
cancellation, device-flow timeout, `slow_down`/`authorization_pending`/
`access_denied`/`expired_token`, broker restart mid-flow, capability
loss mid-flow - distinguishing **fail closed** from a genuinely safe
local fallback, never an automatic unsafe one. See
`docs/failure-policy.md`. Fixed a real gap along the way: every
broker->identity-provider HTTP call previously had no timeout at all
and could hang forever on a non-responding provider; now bounded to 15
seconds. Real-tested on VM124: SSSD's own on-disk cache provides
meaningful resilience during both a stopped daemon and a
network-unreachable AD backend (a previously-undocumented finding); a
broker restart mid-flow recovers safely by construction.

### v2.8.0 - Transaction-bound remote approval (implemented)

An approval must be bound to the exact local transaction that
requested it - never "any login for this username" - and no
cryptographic device attestation is claimed. Found and fixed a real
gap while verifying this: `pollAndDecide` did not re-check cancellation
immediately after a token-poll network call returned, so a superseded
flow's in-flight poll could still succeed if it happened to return a
genuine approval just after being superseded. Reproduced with a real
test against a token endpoint that holds its response open, fixed by
re-checking cancellation right after every poll. The approval marker
now also carries explicit bound context (`SESSION_ID`/
`IDENTITY_SOURCE`/`PROVIDER`/`HOSTNAME`/`REQUESTED_ACTION`), backward
compatible with the unchanged PAM consumer. See
`docs/transaction-binding.md` for verification of all 12 named
security requirements against real code and tests.

### v2.9.0 - Mechanism selection, first increment (implemented)

The smartphone/EIdP login button is now disabled, with a visible
reason, whenever `oidc_ready` is false, rather than only showing an
informational hint - closing v2.4.0's own explicitly-deferred
capability-*offering* gap. The FIDO2-available hint moved to the main
login screen. See `docs/mechanism-selection.md` for the real scope,
including why hardware-key login has no selectable UI action to bind
at all (`pam_u2f.so` tries silently ahead of both other paths in PAM,
so there is no "start passkey login" action a button could trigger).
Not the full generic mechanism-selection framework v3.0.0 envisions -
see that milestone for what remains.

### v2.10.0 - Visual regression coverage for mechanism offering (implemented)

Extended the v1.15.0 Native Theme visual regression framework with two
new deterministic baseline states covering v2.9.0's capability-driven
mechanism offering (`smartphone_unreachable`, `fido2_available`) - now
18 states / 26 cases total. No functional/shipped theme code changed;
baselines were generated in a real `debian:13` container matching CI
exactly, with all 24 pre-existing baselines confirmed byte-identical
against the harness change first, proving zero regression.

### v2.11.0 - Generic mechanism data model, first real interface (implemented)

Introduced `theme/native/components/MechanismModel.qml`: a single,
shared, documented `Mechanism` data model (`password`/`eidp`/`passkey`/
`smartcard`, each with `kind`/`available`/`ready`/`statusHint`) that now
backs the v2.9.0 smartphone button/hint-label bindings, replacing two
separate raw property reads with one named lookup. A pure,
byte-identical refactor: proven with the existing 26-case visual
regression suite (mirrored into the test harness, re-run in a real
`debian:13` container) showing `CHANGED=0` across every case. See
`docs/generic-mechanism-model.md` for the full interface and what
remains genuinely unwired (`password`/`smartcard` are represented in
the model but not yet UI-driven by it).

### v2.12.0 - Password wired through the mechanism model (implemented)

`password`'s login button and password field are now also gated on
`mechanismModel.mechanism("password").ready`, alongside the existing
username-selected check - the same single source of truth already used
for `eidp`/`passkey` since v2.11.0. `password.ready` is always `true`
today, so this is another pure, byte-identical refactor (proven the
same way as v2.11.0: the 26-case visual regression suite, mirrored
onto the test harness, re-run in a real `debian:13` container,
`CHANGED=0` for every case). `smartcard` deliberately received no UI
wiring - see `docs/generic-mechanism-model.md` for why (no capability
signal, no backend action, nothing real to bind a button to).

### v3.0.0 - Generic authentication mechanism framework (gated, not yet closeable)

Direction: this project's OIDC integration becomes one provider within
a more general SDDM/PAM authentication-mechanism model (password /
passkey / eIdP / smartcard / future mechanisms), rather than staying a
single-purpose "SDDM OIDC" project. Defined as the closure gate for
this whole phase of work, requiring every milestone above to be fully
green. As of v2.9.0, two things keep it from honestly closing: a
generic, standardized mechanism data model/UI still needs real design
and implementation work (not itself blocked, just not yet done), and
three external blockers only resolvable outside this project's own
code - no real Keycloak instance for provider-conformance testing, no
physical FIDO2/U2F hardware, and Debian 13's own SSSD package lacking
compiled passkey/libfido2 support. As of v2.11.0, the mechanism data
model itself is real (see above); as of v2.12.0, `password` is also
wired through it (`eidp`/`passkey`/`password` all real; `smartcard`
deliberately not, since nothing real exists to wire). What remains is
the larger generic SDDM Rich UI/mechanism-selection surface and the
three external blockers. See the private roadmap for the full, honest
gap assessment; this milestone will not be marked closed until it
actually is.

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
