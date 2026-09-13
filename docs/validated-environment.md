# Validated environment

This documents what has actually been exercised end-to-end, as opposed
to what is merely expected to work. No private credentials, account
secrets, device codes or transient session identifiers are included
below - see `docs/threat-model.md` and `docs/security.md` for the design
rationale instead of deployment secrets.

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
- **Provider abstraction (v0.7.0)**: originally unit-tested against a mock
  server shaped like Keycloak/Authentik's endpoint layout. This historical
  milestone predated the later real-provider validation described below;
  mock coverage is no longer the only evidence for those providers.
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

- **Real infrastructure (v2.1.0 onward)**: this track specifically requires
  never marking an integration TESTED without a real, live instance
  behind it - not a mock, and not a simulation.
  - **Authelia**: real - this project's lab and production deployments
    run continuously against a real, live Authelia instance; this
    predates v2.1.0 and is exercised throughout this document.
  - **Samba AD / SSSD**: real - the lab VM was configured with SSSD
    against a real Samba AD domain controller over LDAPS (no StartTLS
    mixing, certificate validation proven both to succeed with the
    correct CA and fail with an untrusted one), using a dedicated
    low-privilege bind account and the directory's real RFC2307 POSIX
    attributes (not a synthetic SID-based mapping).
    `account_source=nss` was proven end-to-end against a real AD-only
    identity: an invented user remained rejected and the real identity
    was correctly authorized. This was a validation exercise, not a new
    permanent lab baseline.
  - **Debian SSSD native-passkey package**: **PACKAGE CAPABILITY TESTED**
    on 2026-09-13. VM124 already had `sssd-passkey 2.10.1-2+b1`
    installed. `/usr/libexec/sssd/passkey_child` exists, is owned by
    that package and links to `libfido2.so.1`; the packaged Kerberos
    passkey plugin also exists, `libfido2-1` is installed, and
    `dpkg -V sssd-passkey` was clean. SSSD remained active and
    `/etc/pam.d/sddm` was SHA-256 identical before/after. This corrects
    the earlier mistaken conclusion that Debian's SSSD build lacked
    compiled passkey support. It is **not** an end-to-end passkey login
    claim; physical hardware/enrollment remains untested. See
    `docs/sssd-native-passkey.md`.
  - **Authentik**: real - an isolated lab OAuth2/OIDC application
    (Device Code grant, public client, explicit signing key, minimal
    scopes) on a real, live Authentik instance. This surfaced the
    `verification_uri` origin-validation gap fixed in the provider
    abstraction hardening: real infrastructure validation caught a
    problem that mock-only tests had not.
  - **Keycloak 26.7.3**: **TESTED** on 2026-09-13 against a real,
    disposable Keycloak 26.7.3 server using the official container
    image. The public OIDC client had RFC 8628 Device Authorization
    enabled and requested only `openid profile`; `preferred_username`
    carried the authentication identity. The production broker's
    `provider-test` passed discovery, issuer binding, device endpoint,
    JWKS, trusted-origin, verification-URI and `authorization_pending`
    checks. A human-approved real device flow then completed through
    token + userinfo, exact username matching and root-owned `0600`
    approval-marker creation with the expected local/NSS UID. Real
    negative/edge responses also observed: invalid device code
    (`invalid_grant`), nonexistent client rejection, `slow_down`, and
    provider-side `expired_token`. See `docs/keycloak-validation.md`.
  - **FIDO2 hardware**: not tested - no physical FIDO2/U2F security key
    is available in this environment. PAM-stacking behavior (v0.6.0/
    v0.8.0 above) and SSSD package capability are real; a live
    authentication with actual hardware is not.

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

- Only one production host and one principal lab VM have been exercised
  for the full SDDM/PAM integration - not a matrix of independent
  installs and hardware configurations.
- No multi-user (`allowed_users` with more than one account)
  configuration has been exercised **in production** - only on the lab
  VM. Production remains a single-allowed-user deployment.
- A real "VM matrix" (multiple distributions, display managers, or
  desktop environments run in parallel/automated) does not exist. Claims
  of cross-platform compatibility beyond Debian 13 / SDDM / KDE Plasma 6
  would therefore be guessing, not verification.
- Real physical FIDO2/U2F hardware is still unverified. Keycloak 26.7.3,
  Authentik and Authelia now all have real-provider evidence, but other
  generic OIDC providers and other versions/configurations of those
  products remain unverified unless explicitly listed as TESTED.
- Debian 13's `sssd-passkey` package capability is verified, but a real
  native SSSD passkey enrollment/login has not yet been exercised. This
  is distinct from the shipped `pam_u2f.so` hardware-key path and is
  documented in `docs/sssd-native-passkey.md`.
- Fresh, from-scratch installation by someone without prior knowledge of
  this project's development history has not been independently
  observed - `docs/installation.md` is audited for completeness (see
  `docs/testing.md`), but that is not a substitute for a truly
  independent first-time install.
