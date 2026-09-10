# sddm-authelia-passkey

[![build](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/build.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/build.yml)
[![test](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/test.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/test.yml)
[![security](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/security.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/security.yml)
[![package](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/package.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/package.yml)
[![release](https://img.shields.io/github/v/release/BenJule/sddm-authelia-passkey?include_prereleases)](https://github.com/BenJule/sddm-authelia-passkey/releases)
[![license](https://img.shields.io/github/license/BenJule/sddm-authelia-passkey)](LICENSE)

**Status: v1.0.0, stable.** No known P0/P1 bugs within the documented
validated scope (see `docs/validated-environment.md`); `config.conf`,
the admin CLI, and the shipped scripts' exit codes/status lines are
covered by a stability commitment going forward (`docs/stability.md`).
Proven end-to-end on one production host and one lab VM, including a
real host reboot and a full password + smartphone/passkey login
regression on both, plus extensive lab-VM verification of every
optional feature (NSS/LDAP, FIDO2, generic OIDC providers, policy/
recovery tooling) added since. Still a single-maintainer project not
yet tested across multiple independent installs, hardware
configurations, or a real distro/display-manager matrix - read
`docs/threat-model.md`, `docs/security.md`, and
`docs/validated-environment.md` before deploying.

Passwordless SDDM login via Authelia's OIDC Device Authorization Grant
and WebAuthn/Passkey user verification - approve a login on your phone
instead of typing a password, with the existing password login always
kept as a fallback.

## Features

- Login via QR code + Passkey (fingerprint/PIN/whatever your
  authenticator uses) instead of a typed password.
- Password login is never removed, weakened, or made conditional - the
  PAM integration is purely additive and falls through unchanged when no
  approval is present.
- Optional KWallet auto-unlock on a successful smartphone/passkey login
  (`kwallet_auto_unlock`, off by default), using `systemd-creds` so the
  wallet password is never stored in plaintext.
- Rate limiting, single-use/short-TTL approval markers, and a
  server-side allowlist independent of any group membership.
- Optional native FIDO2/U2F hardware security keys (`docs/fido2.md`),
  optionally restricted to a group.
- A read-only admin CLI (`sddm-authelia-passkey-admin`) and an
  emergency `break-glass.sh` recovery path independent of any backup
  lookup - see `docs/rollback.md`.

## Architecture

See `docs/architecture.md` for the full diagram and design rationale
(including why a separate broker process is unavoidable given SDDM's PAM
architecture).

## Tested configuration

| Component | Version |
| --- | --- |
| OS | Debian 13 (Trixie) |
| Display manager | SDDM 0.21.x |
| Desktop | KDE Plasma 6 |
| Identity provider | Authelia 4.39+ (OIDC, Device Authorization Grant) |
| Init system | systemd 257+ |

Other distributions/versions are unsupported/experimental - the
installer will refuse to touch PAM rather than guess on an unrecognized
stack. See `docs/installation.md`.

## Limitations

- Only proven on the configuration above; not yet validated on other
  distributions, display managers, or desktop environments.
- Requires an Authelia instance you control and can configure an OIDC
  client on - it does not work against arbitrary/unmodified identity
  providers.
- KWallet auto-unlock is KDE-specific and optional; it is off by default
  and a failure there can never turn a successful login into a failed
  one (see `docs/architecture.md`).
- No packages are published to a Debian/APT repository yet - install
  from a signed GitHub release `.deb`, see `docs/installation.md`.
- Multi-user support: `allowed_users` may list more than one account,
  each with independent flows, approval markers, and KWallet
  credentials, bound to whichever account SDDM's own existing user
  selector (avatar list or manual username entry) currently has
  selected - see `docs/architecture.md`'s "Multi-user readiness"
  section. Tested via unit tests, real PAM integration tests against
  local test accounts, and manual verification of the theme change on
  the lab VM. Only one real human/production Authelia identity has been
  used in end-to-end testing so far; multi-user proof beyond that uses
  synthetic local accounts and unit-level identity mocks, not two real
  people.
- LDAP/Active Directory accounts: `account_source=nss` (opt-in,
  `local` remains the default) authorizes any account this host's own
  NSS/SSSD setup can resolve, instead of requiring a static
  `allowed_users` entry - see `docs/architecture.md`'s "LDAP/Active
  Directory accounts (NSS)" section. This project never talks to
  LDAP/AD/SSSD directly and implements no directory-credential caching
  of its own.
- Native FIDO2/U2F hardware security keys (YubiKey, Nitrokey, SoloKey,
  etc.): optional, off by default, via the upstream `pam_u2f.so`
  (`libpam-u2f`) - never reimplemented by this project - see
  `docs/fido2.md`. Verified: PAM stacking arithmetic, idempotent enable/
  disable round-trip, and the full existing smartphone/passkey
  regression suite still passing with it present but unenrolled, all on
  VM124. Not verified: an actual live authentication against physical
  FIDO2 hardware - none was available in this environment; the
  CTAP2/USB-HID protocol handling is `pam_u2f`/`libfido2`'s own,
  separately-maintained implementation.
- Provider abstraction: `provider_kind=oidc` (default remains
  `authelia`, unchanged) supports any standards-compliant OIDC Device
  Authorization Grant provider - Keycloak, Authentik, generic OIDC - via
  discovery-based capability detection, with no provider-specific logic
  in the QML theme. See `docs/architecture.md`'s "Provider abstraction"
  section. Verified against a mock server shaped like Keycloak's real
  endpoint layout; not verified against a real, live Keycloak or
  Authentik deployment.

## Requirements

- An Authelia instance (or compatible OIDC provider) with Device
  Authorization Grant support and WebAuthn/Passkey configured.
- Go 1.24+ and a C toolchain with `libpam0g-dev`, to build.

## Installation

Signed `.deb` releases are published on
[GitHub Releases](https://github.com/BenJule/sddm-authelia-passkey/releases)
(verify before installing - see `docs/release-signing.md`). Building
from source is also supported. See `docs/installation.md` for both
paths.

## Configuration

See `docs/configuration.md` and `config/examples/config.conf.example`.

## Password fallback

Always available, always unchanged - see `docs/architecture.md`'s "PAM
control flow" section for exactly why the password path is structurally
unaffected by this project's PAM integration.

## KWallet (optional)

See `docs/kwallet.md`.

## Security

See `docs/security.md`, `docs/threat-model.md`, and `SECURITY.md`. For
what has actually been exercised end-to-end vs. merely expected to work,
see `docs/validated-environment.md`. For SBOM/dependency/provenance
status, see `docs/supply-chain.md`.

## Accessibility

See `docs/accessibility.md`.

## Upgrading

See `docs/upgrade.md`.

## Rollback

See `docs/rollback.md`.

## Development

See `docs/development.md` and `docs/testing.md`.

## License

MIT for this project's own code (see `LICENSE`). The optional theme
integration ships as small patches against `sddm-theme-debian-breeze`
(KDE, GPL/LGPL) rather than a vendored copy - see
`theme/debian-breeze-authelia-passkey-patch/README.md`.
