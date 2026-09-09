# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
