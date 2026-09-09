# sddm-authelia-passkey

[![build](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/build.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/build.yml)
[![test](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/test.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/test.yml)
[![security](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/security.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/security.yml)
[![package](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/package.yml/badge.svg)](https://github.com/BenJule/sddm-authelia-passkey/actions/workflows/package.yml)
[![release](https://img.shields.io/github/v/release/BenJule/sddm-authelia-passkey?include_prereleases)](https://github.com/BenJule/sddm-authelia-passkey/releases)
[![license](https://img.shields.io/github/license/BenJule/sddm-authelia-passkey)](LICENSE)

**Status: pre-1.0, experimental.** Proven end-to-end on one production
host and one lab VM, including a real host reboot and a full password +
smartphone/passkey login regression on both; not yet tested across
multiple independent installs or hardware configurations. Read
`docs/threat-model.md` and `docs/security.md` before deploying.

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
- Multi-user identity binding, cross-user isolation (flows, approval
  markers, KWallet credentials), and per-user KWallet credentials are
  implemented and tested (unit tests + real PAM integration tests
  against local test accounts - see `docs/architecture.md`'s
  "Multi-user readiness" section). What is **not** yet implemented is
  an SDDM account-picker UX - `allowed_users` with more than one entry
  currently requires the theme/greeter's existing username field to be
  used explicitly (no automatic single-user convenience resolution).
  A full account-picker UI is planned for a future release. Only one
  real human/production Authelia identity has been used in end-to-end
  testing so far; multi-user testing beyond that has used synthetic
  local accounts and unit-level identity mocks, not two real people.

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

## Rollback

See `docs/rollback.md`.

## Development

See `docs/development.md` and `docs/testing.md`.

## License

MIT for this project's own code (see `LICENSE`). The optional theme
integration ships as small patches against `sddm-theme-debian-breeze`
(KDE, GPL/LGPL) rather than a vendored copy - see
`theme/debian-breeze-authelia-passkey-patch/README.md`.
