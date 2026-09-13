# Roadmap: generic OIDC broker toward a general authentication mechanism framework

This documents the direction beyond v2.1.0 and the evidence accumulated while
moving from a single-provider login integration toward a generic authentication
mechanism framework. Milestones v2.1.0 through v2.14.0 are implemented as
described below; v3.0.0 remains gated on the explicit public closure issues.

The native-theme track (v1.8.0-v2.0.0, see `docs/native-theme.md`) began as a
separate line of work and is now one part of the v3 mechanism-framework gate.

Operational planning is tracked in the public [SDDM Authelia Passkey Development](https://github.com/users/BenJule/projects/2) GitHub Project. The active release gate is the **v3.0.0 - Generic authentication mechanism framework** milestone; this document remains the detailed technical source of truth.

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
discovery-document issuer verification. Real validation initially
covered a live Authentik instance and a live Samba AD domain; Keycloak
was deliberately left NOT TESTED at that time. That provider gap has
since been closed by the real Keycloak 26.7.3 validation recorded in
`docs/keycloak-validation.md`.

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
presentation was intentionally deferred and subsequently implemented in
increments through v2.14.0.

### v2.5.0 - Native SSSD passkey integration (investigated; package blocker corrected)

Direction: hardware FIDO2 via `SDDM -> PAM -> SSSD -> libfido2`, kept
architecturally separate from the OIDC broker (`docs/fido2.md`'s
existing `pam_u2f.so` stack is the current, shipped, simpler
alternative). Trust boundary: the OIDC broker is remote/web
authentication; SSSD passkey support is local hardware authentication -
these must not be blurred into one code path.

The original VM124 investigation incorrectly concluded that Debian 13's
SSSD build lacked compiled passkey support because `pam_sss.so` had no
direct `libfido2` linkage and `passkey_child` was not found during that
check. A follow-up on 2026-09-13 resolved this packaging misunderstanding:
Debian ships native passkey support separately as `sssd-passkey`.
VM124 already had `sssd-passkey 2.10.1-2+b1` installed,
`/usr/libexec/sssd/passkey_child` exists and is package-owned, the
Kerberos passkey plugin exists, and `passkey_child` links to
`libfido2.so.1`. See `docs/sssd-native-passkey.md` for the corrected
verification record.

Therefore **package availability is no longer a v3 blocker**. What is
still missing is a real end-to-end native SSSD passkey enrollment/login
with physical FIDO2 hardware and the exact target identity-provider
configuration. That hardware validation remains tracked by #87; no
broker-owned FIDO2 implementation is introduced.

### v2.6.0 - Multi-IdP / provider hardening (conformance test implemented)

Shipped `sddm-authelia-passkey-admin provider-test`: a real, live
conformance check against the currently configured provider (discovery,
issuer binding, device endpoint, `verification_uri` trust origin, JWKS
reachability, RFC 8628 `authorization_pending`), reusing the exact same
production dispatch functions every real login flow uses - never a
reimplementation. See `docs/provider-conformance.md`.

Real provider validation now exists for Authelia, Authentik and
**Keycloak 26.7.3**. The Keycloak closure run used the generic
`provider_kind=oidc` path with no Keycloak-specific authentication
branch and additionally observed real `slow_down`, `expired_token`,
invalid-device-code and invalid-client failures plus a human-approved
end-to-end flow. See `docs/keycloak-validation.md`. A larger automated
multi-provider/version matrix and additional live provider-specific
negative paths remain future quality work, not blockers disguised as
completed validation.

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

### v2.10.0 - Visual regression coverage for mechanism offering (implemented)

Extended the v1.15.0 Native Theme visual regression framework with two
new deterministic baseline states covering v2.9.0's capability-driven
mechanism offering (`smartphone_unreachable`, `fido2_available`) - now
18 states / 26 cases total at that milestone. No functional/shipped
theme code changed; baselines were generated in a real `debian:13`
container matching CI exactly, with all pre-existing baselines confirmed
byte-identical before the new states were accepted.

### v2.11.0 - Generic mechanism data model, first real interface (implemented)

Introduced `theme/native/components/MechanismModel.qml`: a single,
shared, documented `Mechanism` data model (`password`/`eidp`/`passkey`/
`smartcard`, each with `kind`/`available`/`ready`/`statusHint`) backing
the smartphone button/hint-label bindings instead of separate raw
property reads. See `docs/generic-mechanism-model.md`.

### v2.12.0 - Password wired through the mechanism model (implemented)

`password`'s login button and password field are also gated on
`mechanismModel.mechanism("password").ready`, alongside the existing
username-selected check. `smartcard` deliberately received no UI wiring:
it has neither a real capability signal nor a backend action to bind.

### v2.13.0 - First visible mechanism-selection UI (implemented)

The native theme shows an always-visible "Anmeldemethode" selector row
data-driven from `MechanismModel.selectableMechanisms` via a `Repeater`,
letting the user explicitly pick between `password` and `eidp` before
either mechanism's controls are shown. The selection/fallback state
machine lives in separately unit-tested `MechanismSelector.qml`. Passkey
remains ambient and smartcard remains unoffered for structural reasons.

### v2.14.0 - Mechanism selector interaction & responsive UX (implemented)

Hardens the v2.13.0 selector into a fully operable login control (see
[#85](https://github.com/BenJule/sddm-authelia-passkey/issues/85)):
keyboard selection, safe readiness fallback, restored password focus,
responsive stacked layout, accessibility coverage and 30-case visual
regression are implemented. SmartphoneLoginPanel was also made compact
and state-coherent so QR/waiting and confirmed states cannot contradict
each other. No authentication authority moved into QML.

### v3.0.0 - Generic authentication mechanism framework (gated, not yet closeable)

Operational tracking: [#85 mechanism-selection UI](https://github.com/BenJule/sddm-authelia-passkey/issues/85), [#86 real Keycloak validation](https://github.com/BenJule/sddm-authelia-passkey/issues/86), [#87 physical FIDO2/U2F validation](https://github.com/BenJule/sddm-authelia-passkey/issues/87), [#88 SSSD native-passkey package tracking](https://github.com/BenJule/sddm-authelia-passkey/issues/88), and [#89 final closure gate](https://github.com/BenJule/sddm-authelia-passkey/issues/89).

Direction: this project's OIDC integration is one provider within a more
general SDDM/PAM authentication-mechanism model (password / passkey /
eIdP / smartcard / future mechanisms), rather than a single-purpose
"SDDM OIDC" project.

The **real-Keycloak external blocker is resolved**: Keycloak 26.7.3 was
validated on 2026-09-13 through production broker code, including the
real approval path and live RFC 8628 negative/edge responses. See
`docs/keycloak-validation.md` and issue #86.

The **Debian SSSD package blocker is also resolved**: VM124 has the real
`sssd-passkey 2.10.1-2+b1` split package, an executable package-owned
`passkey_child`, the passkey plugin, and real `libfido2` linkage. The
previous contrary conclusion was a packaging-detection error and is
corrected in `docs/sssd-native-passkey.md` and issue #88.

v3.0.0 still cannot honestly close while its remaining explicit gates
are unresolved. In particular, physical FIDO2/U2F hardware validation
(#87) has not occurred, #85 retains its explicit post-v2.14 full-login
regression closure criterion until that evidence is recorded, and #89
is the final release/regression gate. Native SSSD passkey support is no
longer blocked by package availability, but end-to-end native SSSD
passkey authentication still requires the same real-hardware evidence
rather than being silently counted as validated.

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
