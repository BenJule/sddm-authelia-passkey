# sddm-authelia-passkey

**Status: experimental / early release.** Proven end-to-end on one
production host and one lab VM; not yet tested across multiple
independent installs. Read `docs/threat-model.md` and `docs/security.md`
before deploying.

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
- Optional KWallet auto-unlock on a successful Pixel login
  (`kwallet_auto_unlock`, off by default), using `systemd-creds` so the
  wallet password is never stored in plaintext.
- Rate limiting, single-use/short-TTL approval markers, and a
  server-side allowlist independent of any group membership.

## Architecture

See `docs/architecture.md` for the full diagram and design rationale
(including why a separate broker process is unavoidable given SDDM's PAM
architecture).

## Supported platforms

Debian 13 (Trixie) + SDDM 0.21.x + KDE Plasma 6 + Authelia 4.39+ +
systemd 257+. Other distributions/versions are unsupported/experimental
- the installer will refuse to touch PAM rather than guess on an
unrecognized stack. See `docs/installation.md`.

## Requirements

- An Authelia instance (or compatible OIDC provider) with Device
  Authorization Grant support and WebAuthn/Passkey configured.
- Go 1.24+ and a C toolchain with `libpam0g-dev`, to build.

## Installation

See `docs/installation.md`.

## Configuration

See `docs/configuration.md` and `config/examples/config.conf.example`.

## Password fallback

Always available, always unchanged - see `docs/architecture.md`'s "PAM
control flow" section for exactly why the password path is structurally
unaffected by this project's PAM integration.

## KWallet (optional)

See `docs/kwallet.md`.

## Security

See `docs/security.md`, `docs/threat-model.md`, and `SECURITY.md`.

## Rollback

See `docs/rollback.md`.

## Development

See `docs/development.md` and `docs/testing.md`.

## License

MIT for this project's own code (see `LICENSE`). The optional theme
integration ships as small patches against `sddm-theme-debian-breeze`
(KDE, GPL/LGPL) rather than a vendored copy - see
`theme/debian-breeze-authelia-passkey-patch/README.md`.
