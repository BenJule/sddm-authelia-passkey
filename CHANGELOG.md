# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Broker: config validation now refuses `allowed_users` containing
  `root` outright at startup, redundant with (and independent of) the
  PAM stack's own `user != root` protection.
- PAM module: approval-marker consumption now also verifies the marker
  file is owned by `root:root`, mode `0600`, and a regular file before
  trusting its age - defense in depth against a future regression that
  loosens `markerDir`'s own permissions (the real boundary today).
- CI: package-level verification (Debian package build, `lintian`,
  install/verify/remove/reinstall lifecycle test in an isolated Debian
  13 container), CodeQL (Go + C/C++), `govulncheck`, `gitleaks`,
  dependency review, and theme-patch validation against the real
  `sddm-theme-debian-breeze` package.
- Broker: test coverage for `pollToken`'s outcome classification (429
  rate-limit vs. RFC 8628 `authorization_pending`/`slow_down` vs.
  genuinely ambiguous/malformed responses), `handleStart`'s
  username-resolution/rejection logic, and `handleCancel`.
- `docs/validated-environment.md` and `docs/supply-chain.md`.

### Fixed
- Debian packaging: `debian/rules`, `debian/postinst`, and
  `debian/prerm` are now correctly tracked as executable in git (were
  silently auto-corrected by `dpkg-buildpackage` on every build).
- Debian packaging: `debian/control`/`debian/copyright` `Homepage`/
  `Source` no longer point at a placeholder `github.com/example/...`
  URL.
- `docs/installation.md` now documents the actual packaged-`.deb`
  install path (previously only documented building from source, even
  though that is not how the project's own releases are distributed).
- `docs/rollback.md` now documents the packaged-install rollback path
  (`apt purge`, which the package's own `prerm` already wires to
  `rollback.sh` automatically).
- `tests/integration/pam-flow-test.sh` now stops/starts the correctly-
  named `sddm-authelia-passkey-kwallet-secretd.service` (was a stale
  `kwallet-secretd.service` reference that silently no-op'd).

### Changed
- Public-facing wording ("Pixel login" etc.) replaced with vendor-
  neutral "smartphone/passkey login" throughout docs, config comments,
  and source comments/log strings - the feature works with any
  Passkey-capable phone, not just Google Pixel devices. Internal QML
  identifiers (`pixelFlow`) are unchanged.

## [0.2.0]

### Fixed
- Smartphone-login now uses `sessionButton.currentIndex` (the same
  session selection the password login uses) instead of a hardcoded
  session index of `0`.
- Broker: overlapping/duplicate device-authorization flows for the same
  user no longer exhaust `max_parallel_flows`' concurrency slots waiting
  out their full lifetime - a new `/start` now actively cancels a still-
  pending prior flow, and the theme's "Abbrechen" path calls a new
  `/cancel` endpoint explicitly instead of relying only on that.
- Broker: a rate-limited or genuinely ambiguous/malformed response from
  the token endpoint is no longer conflated with legitimate RFC 8628
  waiting states; only truly ambiguous responses count toward a bounded
  retry limit.
- Theme: `pixelFlow.open()`/`poll()` are now idempotent and ignore stale
  responses for a session that is no longer current.

### Changed
- Theme: replaced the floating "Login with Passkey" button/popup with a
  "Smartphone-Login" entry in the existing action row (alongside Sleep/
  Restart/Shut Down/Other) and a right-anchored sidebar panel, matching
  the host theme's own visual language instead of a separate overlay.
  The main login block now recenters within the visible area when the
  sidebar is open.

## [0.1.0]

### Added
- Initial public release candidate: broker (RFC 8628 device
  authorization + rate limiting + single-use approval markers), native
  PAM module, optional KWallet auto-unlock via systemd-creds, additive
  SDDM theme integration, installer/rollback/uninstall scripts, unit and
  integration tests, CI workflows, Debian packaging skeleton, and
  documentation (architecture, threat model, security boundaries,
  installation, configuration, KWallet setup, rollback,
  troubleshooting, development, testing).
