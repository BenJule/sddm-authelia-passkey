# Validated environment

This documents what has actually been exercised end-to-end, as opposed
to what is merely expected to work. No private hostnames, IP addresses,
usernames, or infrastructure topology are included below - see
`docs/threat-model.md` and `docs/security.md` for the design rationale
instead of specific deployment details.

## Platform

Debian 13 (Trixie), SDDM 0.21.x, KDE Plasma 6, Authelia 4.39+ (OIDC
Device Authorization Grant), systemd 257+.

## What has been validated on a real production host

- Clean package cutover from a prior, unpackaged prototype implementation
  to this project's packaged `pam_authelia_passkey.so` / broker /
  `kwallet-secretd`, via a scoped, temporary, fixed-dispatch sudo helper
  (no interactive password re-entry per step, no free-form remote shell)
  with an explicit confirmation gate before the `/etc/pam.d/sddm` write.
- Password login, unchanged and unaffected throughout.
- Smartphone/passkey login: QR scan, WebAuthn/Passkey user verification,
  approval, PAM handoff, successful Plasma session start.
- KWallet auto-unlock (optional component) verified working, with no
  manual password prompt, on **both** the password login path (normal
  KDE wallet/login-password sync) and the smartphone/passkey login path
  (via the `kwallet-secretd` hand-off marker mechanism).
- A real host reboot, followed by re-verification that `sddm.service`
  starts correctly and automatically (`systemctl is-enabled` = enabled,
  `display-manager.service` correctly aliased), and a repeat of both the
  password and smartphone/passkey login tests after that reboot.
- `common-auth`, the `sudo` PAM stack, and the `sshd` PAM stack verified
  byte-for-byte unchanged (SHA-256) before, during, and after the entire
  cutover and reboot sequence.
- Removal of the prior prototype implementation's components (PAM
  module, broker, KWallet secret daemon, theme) and an unrelated,
  already-abandoned `greetd`-based prototype, without regressing any of
  the above.

## What has been validated on the lab VM (since v0.5.0)

Every release from v0.5.0 onward added real, dynamic lab-VM verification
on top of the unit/integration test suite, in addition to (not instead
of) the production cutover above:

- **Multi-user / NSS (v0.5.0)**: real local group membership (`getgrouplist`),
  multiple concurrent local test accounts, `account_source=nss` exercised
  against a real NSS group, including live group-membership pickup with
  no caching.
- **FIDO2 (v0.6.0, extended v0.8.0)**: real `libpam-u2f` installed, real
  `enable-fido2.sh`/`disable-fido2.sh` round-trips against the real
  `/etc/pam.d/sddm` (byte-identical restoration verified both with and
  without `fido2_required_group` set), the full existing
  `pam-flow-test.sh` suite re-run unchanged on top with no credential
  enrolled.
- **Provider abstraction (v0.7.0)**: unit-tested against a mock server
  shaped like Keycloak/Authentik's real endpoint layout; a real live
  Keycloak/Authentik instance has not been stood up in this environment.
- **Policy/recovery/admin CLI (v0.8.0)**: `disable-pam.sh`,
  `break-glass.sh` (disable, idempotency, `--restore`), and the admin
  CLI's subcommands all exercised against the real live PAM stack and
  broker on a clean VM snapshot; the full `pam-flow-test.sh` and
  `pam-multiuser-test.sh` suites re-run unchanged afterward.
- **Upgrade/config migration (v0.9.0)**: an in-place package upgrade
  from the previously-published release, with a deliberately
  pre-v0.5.0-shaped `config.conf`, verified to preserve
  `/etc/pam.d/sddm` and `config.conf` byte-for-byte and to keep
  functioning under the new broker - both as a unit test
  (`TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults`) and as a
  dedicated CI job (`upgrade` in `.github/workflows/package.yml`) that
  performs the real `apt install --only-upgrade` against a real prior
  release artifact.

Multi-user configurations (`allowed_users` with more than one account,
and `account_source=nss` group-based authorization) have therefore been
exercised on the lab VM, even though production has only ever run a
single-allowed-user configuration (see above).

- **Real infrastructure (v2.1.0)**: this milestone specifically requires
  never marking an integration TESTED without a real, live instance
  behind it - not a mock, and not a simulation.
  - **Authelia**: real - this project's own lab (VM124) and production
    deployments both run continuously against a real, live Authelia
    instance; this predates v2.1.0 and is exercised throughout this
    entire document.
  - **Samba AD / SSSD**: real - VM124 configured with SSSD against a
    real Samba AD domain controller over LDAPS (no StartTLS mixing,
    certificate validation proven both to succeed with the correct CA
    and fail with an untrusted one), using a dedicated low-privilege
    bind account and the directory's real RFC2307 POSIX attributes
    (not a synthetic SID-based mapping). `account_source=nss` proven
    end-to-end against a real AD-only identity (fake user still 403,
    the real identity correctly authorized). This is a validation
    exercise, not a permanent VM124 configuration - the lab VM's
    `config.conf` and SSSD setup were restored/left in a documented
    state rather than being a new standing baseline (see the
    private roadmap tracking issue for the exact end state).
  - **Authentik**: real - an isolated lab OAuth2/OIDC application
    (Device Code grant, public client, explicit RS256 signing key,
    minimal scopes) on a real, live Authentik instance, discovered and
    validated read-only before any mutation. This is what surfaced the
    `verification_uri` origin-validation gap fixed in this release (see
    `docs/architecture.md`'s "Provider abstraction" section) - real
    infrastructure validation catching what mock-based tests could not.
  - **Keycloak**: not tested - no real Keycloak instance exists in this
    environment. Not simulated, not counted as validated.
  - **FIDO2 hardware**: not tested - no physical FIDO2/U2F security key
    is available in this environment. PAM-stacking behavior (v0.6.0/
    v0.8.0 above) is real; a live authentication with actual hardware is
    not.

## Theme deployment modes (as of v2.0.0)

Three modes are supported (`sddm-authelia-passkey-admin
mode-status`/`apply-mode`/`migrate`, see
`docs/theme-installation-modes.md`). Only the platform documented
above (Debian 13 / SDDM 0.21.x / KDE Plasma 6) has actually been
exercised - no other distribution, display manager, or desktop
environment is claimed as TESTED anywhere below.

| Mode | Status | Verified |
| --- | --- | --- |
| Native Theme | **TESTED, RECOMMENDED** | Full feature parity, responsive layout, accessibility roles, vendor-neutral optional branding, visual regression baselines (v1.10.0-v1.18.0); no dependency on Debian Breeze source (`theme/native/PROVENANCE.md`); v1.18.0 threat-model hardening; real install/upgrade/migrate/rollback on VM124 across every release since v1.16.0. |
| Compatibility Theme (patched Debian Breeze) | TESTED | Patch-based install/upgrade idempotency, branding parity with Native (v1.8.0), migrate/rollback round-trip on VM124 alongside Native. |
| Backend/PAM only (no theme) | TESTED | The original, longest-validated mode - see "What has been validated on a real production host" above; unaffected by any Native/compat theme work. |
| Other distributions (Ubuntu, Fedora, openSUSE, ...) | UNSUPPORTED | Not exercised in any form. |
| Other display managers (GDM, LightDM, ...) | UNSUPPORTED | This project is SDDM-specific by design (PAM stack, theme mechanism). |
| Wayland-only / X11-only session restrictions | UNSUPPORTED | Not exercised as a distinct configuration; sessions are whatever SDDM's own session list offers on the tested platform. |

"Recommended" reflects which mode this project suggests choosing for a
*new* deployment (see `docs/native-theme.md`); it is not a claim that
compatibility or backend-only are less correct or less maintained, and
no installation or upgrade selects any mode automatically regardless of
this recommendation.

## What is not yet validated

- Only one production host and one lab VM have been exercised - not
  multiple independent installs, hardware configurations, or Authelia
  versions within the supported range.
- No multi-user (`allowed_users` with more than one account)
  configuration has been exercised **in production** - only on the lab
  VM (see above). Production remains a single-allowed-user deployment.
- A real "VM matrix" (multiple distributions, display managers, or
  desktop environments run in parallel/automated) does not exist - every
  lab-VM test above ran sequentially, by hand or via CI, against the one
  supported combination (Debian 13 / SDDM / KDE Plasma 6). Claims of
  cross-platform compatibility beyond that combination would be
  guessing, not verification.
- Real physical FIDO2/U2F hardware, a real live Keycloak/Authentik/generic
  OIDC provider, and a real Samba AD/SSSD directory beyond local NSS
  calls remain unverified - see `docs/fido2.md` and
  `docs/architecture.md`'s "Provider abstraction" section for the exact
  scope of what was and wasn't tested for each.
- Fresh, from-scratch installation by someone without prior knowledge of
  this project's development history has not been independently
  observed - `docs/installation.md` is audited for completeness (see
  `docs/testing.md`), but that is not a substitute for a truly
  independent first-time install.
