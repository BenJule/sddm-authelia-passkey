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
