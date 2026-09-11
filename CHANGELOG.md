# Changelog

All notable changes to this project are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [1.13.0] - 2026-09-11

### Added
- Optional vendor-neutral Native Theme branding through SDDM
  `theme.conf.user`.
- Native branding supports brand name, absolute local logo, local hostname,
  administrator-supplied domain/realm, avatar visibility and validated
  custom accent colour.
- Deterministic static, QML, runtime and package regression coverage for
  Native Branding.

### Security
- Native branding remains presentation-only and cannot change PAM, broker,
  KWallet, approval-marker, provider or username/session-binding decisions.
- Remote logo URLs are rejected and custom accents accept only opaque
  `#RRGGBB` values.

## [1.12.0] - 2026-09-11

### Added
- Native Theme accessibility hardening with explicit semantic roles,
  accessible names/descriptions, account-selection state, QR/device-code
  alternatives and deterministic accessibility-contract tests.
- Layout-aware Smartphone-Login semantics: Dialog in modal overlay mode
  and Pane in non-modal sidebar mode.

### Changed
- Native keyboard-focus transitions are explicit for Smartphone-Login,
  manual username entry and password fallback.
- Decorative avatars and status indicators are excluded from the
  accessibility tree where adjacent semantic text already conveys the
  same information.
- Stable-status documentation no longer hard-codes the latest release.

## [1.11.1] - 2026-09-11

### Changed
- Reworked the Native Theme visual presentation with project-owned dark
  translucent controls instead of raw Qt Basic widget surfaces.
- Improved login-card hierarchy, username-first account presentation,
  session controls, power actions and Smartphone-Login presentation.
- Added explicit German date formatting.
- Preserved v1.11 responsive geometry and authentication semantics.

## [1.11.0] - 2026-09-10

### Added
- Native Theme responsive UX with a geometry-derived sidebar/overlay
  breakpoint, compact short-screen spacing, adaptive QR sizing and
  deterministic coverage across 1024x600 through ultrawide 2560x1080.
- Dedicated `ResponsiveMetrics.qml` keeps presentation geometry
  independent of Smartphone authentication state.

### Changed
- Native Theme runtime CI explicitly installs `xauth` alongside Xvfb,
  removing reliance on an implicit/transitive test-runner dependency.
- Documentation now reflects the v1.10.0 stable release, the internal
  Debian 13 APT mirror, and Native Theme feature-parity status.

## [1.10.0]

### Added
- Native Theme Feature Parity: switchable SDDM user list, manual username
  entry, complete broker-backed Smartphone Login, QR and alternate device
  code, trusted local/NSS identity presentation, countdown, connection
  state, approval transition, cancellation, retry/recovery states and
  password fallback.
- Deterministic Native Theme QML state-machine and localhost broker-contract
  tests, including stale-generation/session isolation, exact username
  binding, start throttling, expiry, cancellation, offline behavior and
  identity mismatch fail-closed handling.
- Release-engineering validation for a real Debian 13 APT client so
  repository signature failures are not hidden by successful HTTP fetches.

### Security
- Native QML communicates only with the localhost project broker.
- PAM remains the authentication authority.
- No changes to broker, PAM or KWallet authentication implementation.

## [1.9.0]

### Added
- Native Theme Foundation (experimental, opt-in): a new, original,
  from-scratch Qt6 SDDM theme at `theme/native/`, installed alongside
  the existing Debian Breeze compatibility theme (never replacing it,
  never selected automatically). Password login wired to
  `sddm.login()`, real session selection, real user display with a
  safe avatar fallback, power actions gated by SDDM's own
  `canSuspend`/`canReboot`/`canPowerOff`, a keyboard-layout affordance,
  and a `Smartphone-Login` action that opens a clearly-labelled
  preview/placeholder panel - it does not talk to the broker and does
  not claim a login occurred. Full QR/device-code parity is v1.10.0.
  See `docs/native-theme.md` and `theme/native/PROVENANCE.md`.
- New `native-theme` CI workflow validating source-file presence,
  provenance (no dependency on the installed Debian Breeze theme, no
  copied artwork, no remote resources), `qmllint`, a real
  `sddm-greeter-qt6 --test-mode` runtime check, and that
  `src/broker`/`src/pam`/`src/kwallet-secretd` are unchanged versus the
  PR base.

### Fixed
- Preserve already-running project systemd services across package upgrades.
  Fresh installs still do not enable or start the services automatically.

## [1.8.0]

### Added
- Vendor-neutral optional branding through SDDM's native
  `theme.conf.user`: local logo, brand name, hostname, administrator-set
  domain/realm, avatar visibility and optional custom accent.
- Safe upgrade preservation for an existing root-owned regular
  `theme.conf.user`; symlink/non-root-owned overrides are refused.
- Default configuration remains visually identical to v1.7.0 and no
  authentication/PAM/OIDC/FIDO2 behaviour changes.

## [1.7.0]

### Added
- Login Transition: the rest of the greeter now dims and stops
  accepting input during the brief window between a confirmed
  smartphone approval and the actual session hand-off (previously
  this only happened while the narrow-display overlay card was open).
  The QR panel's busy indicator now also spins through this window
  instead of only while starting a flow, so there's continuous
  progress feedback right up to the switch.

## [1.6.0]

### Added
- Error/Recovery UX: the retry/new-code button now has a short
  client-side cooldown (2-10s depending on cause) after a failure, so
  a stray double-click or repeated mashing can't hammer the broker's
  `/start` endpoint - purely a UI courtesy debounce, never touching
  Authelia's own real rate limiting. The button's label shows the
  countdown while it's disabled.
- When a specific account isn't eligible for Smartphone-Login (403),
  the panel now also points at the always-available password field
  instead of just repeating a failure sentence retrying can't fix.
- See `docs/architecture.md`'s new "Error/Recovery UX" section for the
  full per-cause cooldown table.

## [1.5.0]

### Added
- Accessibility 2.0: the custom Smartphone-Login panel elements now set
  explicit `Accessible.role`/`Accessible.name`/`Accessible.description`
  (the panel itself as a Dialog/Pane depending on layout, the icon-only
  back button, the QR card - explicitly pointing screen reader users at
  the "Alternativ Code eingeben" button as the accessible equivalent -
  the countdown progress bar, the connection-status chip, and the
  status-text label flagged as an alert for error/expired/approved
  states). Purely decorative elements that duplicate adjacent visible
  text (the identity avatar image, the status-chip's color dot) are
  marked `Accessible.ignored` instead of double-announced. See
  `docs/accessibility.md`.
- CI now checks the theme patch actually contains a minimum number of
  `Accessible.role`/`Accessible.name` occurrences, so a future edit
  can't silently regress this.

## [1.4.0]

### Added
- Responsive Greeter: the Smartphone-Login panel now adapts to screen
  width, with exactly one layout active at a time (never both). Wide
  enough for the sidebar and a usable main login column side by side:
  unchanged right-anchored sidebar. Otherwise: a centered, size-capped
  modal overlay card (never full-screen), with the rest of the greeter
  dimmed and made fully non-interactive/non-focusable behind it.
  Escape or the Cancel button close it; a stray click on the dimmed
  background does not, to avoid discarding an in-progress flow. Purely
  a geometry change; the flow's own state machine, content, and all
  existing interactions are unchanged in both layouts.
- Documented (no new code needed): multi-monitor support, since SDDM
  already instantiates one independent QML scene per screen, so the
  responsive threshold is evaluated per screen automatically; HiDPI
  support, since all sizing already goes through Kirigami's own
  DPI-aware units or Qt's standard logical-pixel scaling.

### Fixed
- The Smartphone-Login panel's "make sure your phone is on the same
  network" hint was factually wrong - the device only needs to reach
  the configured OIDC/Authelia endpoint, not be on the same LAN/WLAN.
  Replaced with neutral, correct wording.

## [1.3.0]

### Added
- Service/Connection UX: a compact status chip (colored dot + short,
  generic German label - never color alone) for `pixelFlow.connectionState`,
  a new property distinct from flow-progress `state` with exactly six
  values: `ready`, `connecting`, `waiting`, `rate_limited`, `offline`,
  `error`. Shown only when it's not the plain happy path, so it adds no
  noise to normal use.
- `offline` detection: `xhr.status === 0` on `/start` or `/status` (a
  real network-level failure, e.g. the broker isn't running) is now
  distinguished from any HTTP error response, with its own clear,
  non-technical message. A transient offline poll never tears the flow
  down - it clears back to `waiting` automatically once the broker
  responds again.

### Fixed
- A normally-left-open QR code no longer risks being misreported as
  "Zu viele Anmeldeversuche" (too many login attempts). That phrasing
  is now reserved exclusively for the broker's own local per-user
  start-limiter (`/start` returning 429 from repeated *start* clicks) -
  every other upstream-throttle-related case was reworded:
  - **Still pending, upstream momentarily throttling status polls**
    (Authelia's own token-endpoint rate limiter, RFC 8628
    `slow_down`/HTTP 429 - normal and expected for a single open device
    flow, not a sign of repeated login attempts): now reads "Der
    Anmeldedienst wartet derzeit mit weiteren Statusabfragen. Bitte
    kurz warten."
  - **Flow can no longer succeed** (RFC 8628 deadline passed, OR the
    upstream throttle's own Retry-After would exceed the flow's
    remaining lifetime, OR too many ambiguous/infrastructure errors in
    a row): all three now collapse to the same "QR-Code abgelaufen." +
    "Neuen Code anfordern" treatment already used for plain expiry -
    the broker's log keeps the precise reason, the greeter doesn't need
    it.
- No broker-side behavior changed - `rateLimitDecision`,
  `outcomeRateLimit`/`outcomeAmbiguous` classification, and
  `releaseNeutral` for every one of these outcomes (never counted as
  an auth failure) were already correct; this was a presentation-layer
  fix only. Confirmed against real Authelia (4.39.23) token-endpoint
  rate-limiter behavior observed live (delays up to ~55 minutes during
  this session's own repeated testing) - read-only, no Authelia config
  or restart involved.

### Unchanged (explicitly preserved)
- No technical backend/OIDC/LDAP detail is ever shown in the greeter -
  all six connection states use fixed, generic wording; hostnames/HTTP
  codes/OIDC terms stay in the broker's own log only.

## [1.2.0]

### Added
- Visible remaining time in the Smartphone-Login panel: a live,
  locally-ticking countdown (`Läuft ab in M:SS`) and a slim progress
  bar, shared between the QR and alternate-code views. Purely a UX
  value derived from the broker's own `expires_in` deadline
  (`flowState.ExpiresAt`, new `expires_at` field on `/status`) - never
  itself an authority on when a flow actually expires, which remains
  `pollAndDecide`'s own server-side deadline.
- Higher-quality QR rendering: explicit 512px size (`qrPixelSize`,
  previously the qrcode library's small default) and `qrcode.High`
  error correction (previously `Medium`) for better real-world phone
  camera scan resilience.

### Unchanged (explicitly preserved)
- No automatic/uncontrolled creation of new device flows - a new flow
  still only ever starts from an explicit user action (`pixelFlow.open()`
  via the Smartphone-Login button or an explicit retry button).
- No login-method selector added.

## [1.1.0]

### Added
- Identity Awareness in the Smartphone-Login panel: avatar, display name
  (from a fresh NSS/local GECOS lookup), username, and a "Verzeichniskonto"
  (directory account) badge for `account_source=nss` accounts. All shown
  values come from the broker's new `/identity` endpoint (same
  authorization check as `/start`, no rate limit/marker/session side
  effects) or from SDDM's own `userModel` (avatar) - never from
  `resolvedUsername`/Authelia OIDC claims, which stay strictly a
  post-approval identity-binding check, not a display source.
- New broker endpoint `GET /identity?username=X`: read-only, pre-flow
  lookup so the panel can show identity before a device flow starts.
  403 without a reason on any unauthorized/unknown username, identical
  to `/start`'s behavior (no enumeration, no policy-rule leakage).

### Unchanged (explicitly preserved)
- The flow-binding model: a device flow is still bound to
  `targetUsername`, captured once at `open()` and immutable for the
  flow's lifetime; switching SDDM's own account selection while a flow
  is active still cancels it (`onSddmSelectedUsernameChanged`).
- No login-method selector was added - password and Smartphone-Login
  remain the only two visible entry points. FIDO2 and the OIDC
  provider choice remain PAM/config-only, invisible to QML.

## [1.0.0]

First stable release. No known P0/P1 bugs within the documented
validated scope (`docs/validated-environment.md`).

### Added
- `docs/stability.md`: a stability commitment for `config.conf` (every
  key added since the first release has a backward-compatible default;
  existing keys' meanings won't silently change), the admin CLI, and
  the shipped scripts' exit codes/status lines. The broker's HTTP API
  and the on-disk approval marker format are explicitly *not* covered -
  private implementation details, never meant to be consumed outside
  this project's own components.
- `LoadConfig` now refuses an unrecognized key in `config.conf` (a typo,
  or a key from a newer version than this build) instead of silently
  ignoring it, closing a real gap the stability commitment above
  depends on. The four `fido2_*` keys the broker never reads itself
  (consumed by `scripts/enable-fido2.sh`) are explicitly allowlisted so
  they are never mistakenly rejected.
- A regression test guarding that the shipped
  `config/examples/config.conf.example` always loads and validates.
- `docs/accessibility.md`: what's actually keyboard-operable today
  (the alternative-code path, Escape-to-cancel, explicit focus styling
  on custom buttons), and what has not been specifically verified
  (screen readers, high-contrast themes).

### Changed
- `docs/threat-model.md` and `docs/security.md` updated with the
  attack surface introduced since v0.5.0 (NSS/LDAP account resolution,
  FIDO2 hardware keys and group-gating, the generic OIDC provider path,
  `break-glass.sh`/`disable-pam.sh`, and the admin CLI).
- `docs/supply-chain.md` corrected: it referenced a workflow file
  (`release-build.yml`) that doesn't exist (the real one is
  `release-candidate.yml`) and understated that SBOMs are already
  attached to GitHub releases and covered by the release signature.
- `docs/installation.md` and `docs/troubleshooting.md` updated to
  reference every optional feature added since v0.5.0 (NSS/LDAP,
  FIDO2, generic OIDC providers, the admin CLI, `break-glass.sh`),
  which they previously didn't mention at all.

## [0.9.0]

### Added
- Explicit config-migration proof:
  `TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults` loads a
  config.conf containing only the handful of keys that existed before
  v0.5.0 and asserts every since-added key resolves to its documented
  backward-compatible default.
- A new CI `upgrade` job installs the previously-published release,
  writes that same pre-v0.5.0-shaped config.conf, integrates PAM, then
  performs a real in-place `apt install --only-upgrade` to the
  newly-built package and asserts `/etc/pam.d/sddm` and `config.conf`
  are byte-for-byte unchanged, and that the new admin CLI accepts the
  untouched old config.
- `docs/upgrade.md`: the supported upgrade path, what an upgrade does
  and does not touch, and how to recover if something looks wrong
  afterward.
- `tests/run-all.sh`: a single entry point that runs the entire test
  corpus (unit + every root-requiring integration test) in one pass on
  a lab VM/CI container - see `docs/testing.md`.
- `docs/validated-environment.md` corrected and expanded: the previous
  "no multi-user configuration has been exercised" claim was stale
  (v0.5.0 onward has exercised multi-user/NSS extensively on the lab
  VM) and is now accurate, alongside an honest note that no real
  distro/display-manager/desktop-environment matrix exists.

## [0.8.0]

### Added
- `scripts/disable-pam.sh`: symmetric counterpart to `enable-pam.sh`,
  removing just the `pam_authelia_passkey.so` PAM integration (refuses
  while FIDO2 is still layered on top - run `disable-fido2.sh` first).
- `fido2_required_group` (optional): restricts the FIDO2 path to members
  of a named group via an additive `pam_succeed_if.so user notingroup`
  guard, computed and verified the same way as every other PAM edit in
  this project. `enable-fido2.sh`/`disable-fido2.sh` round-trip
  byte-identically in both the gated and ungated shape. See
  `docs/fido2.md`'s "Group policy" section.
- `scripts/break-glass.sh`: zero-dependency emergency recovery that
  neutralizes (comments out, never deletes) any
  `pam_authelia_passkey.so`/`pam_u2f.so` line, with a matching
  `--restore`. Does not depend on locating any prior backup - see
  `docs/rollback.md`.
- `sddm-authelia-passkey-admin` (installed to `/usr/sbin`): fixed-dispatch
  read-only admin CLI (`status`/`health`, `test-config`, `list-users`,
  `audit-log`), delegating entirely to existing tooling.
- Broker: `--check-config` flag validates `config.conf` and exits (no
  root required, nothing started) - backs the admin CLI's `test-config`.
- Broker: authorization denials and successful approvals are now also
  `SECURITY:`-tagged in the log (alongside the existing identity-mismatch
  line), enabling `audit-log` to show a real, minimal audit trail.
- An explicit test proving an unreachable `provider_kind=oidc` provider
  never yields a fabricated success at any of the three dispatch points
  (`TestProviderDispatch_UnreachableProviderNeverApproves`), the
  provider-layer counterpart to the existing PAM-layer
  marker-absence proof.

## [0.7.0]

### Added
- Broker: `provider_kind=oidc` supports any standards-compliant OIDC
  Device Authorization Grant provider (Keycloak, Authentik, or any other
  generic OIDC Provider publishing a discovery document) via
  `oidc_discovery_url`/`oidc_identity_claim`, alongside the unchanged
  default `provider_kind=authelia`. Capability detection refuses a
  provider that doesn't advertise `device_authorization_endpoint`
  instead of guessing. No provider-specific logic exists in the QML
  theme (unaffected by construction - it only ever talks to this
  broker's own local API). See `docs/architecture.md`'s "Provider
  abstraction" section. Validated against a mock server shaped like
  Keycloak's real endpoint layout; a real live Keycloak/Authentik
  instance was not stood up in this environment.

## [0.6.0]

### Added
- Optional native FIDO2/U2F hardware security key support (YubiKey,
  Nitrokey, SoloKey, etc.) via the upstream `pam_u2f.so` (package
  `libpam-u2f`) - never reimplemented by this project. Wired in
  additively ahead of the smartphone/passkey path using the same
  dynamic `[success=N default=ignore]` skip-count computation used
  throughout this project (`scripts/enable-fido2.sh`/
  `scripts/disable-fido2.sh`). Per-user enrollment/revocation/listing
  tooling around `pamu2fcfg`'s authfile
  (`scripts/setup-fido2-credential.sh`,
  `scripts/revoke-fido2-credential.sh`,
  `scripts/list-fido2-credentials.sh`; shared logic in
  `scripts/lib/fido2-authfile.sh`, unit-tested for cross-user isolation
  and multi-credential support). Off by default, fully backward
  compatible - see `docs/fido2.md`.

## [0.5.0]

### Added
- Broker: `account_source=nss` config mode authorizes any NSS-resolvable
  account (local, or - with SSSD/nss-ldap configured in
  `/etc/nsswitch.conf` - Samba AD/OpenLDAP/FreeIPA) instead of requiring
  a static `allowed_users` entry, subject to `minimum_uid`, `deny_users`,
  and optional `allowed_groups`/`require_group_match`. The broker never
  talks to LDAP/AD/SSSD directly and implements no directory-credential
  caching of its own - see `docs/architecture.md`'s new "LDAP/Active
  Directory accounts (NSS)" section. `account_source=local` (the
  default) is unchanged from v0.1-v0.4.

### Changed
- Theme: the smartphone/passkey sidebar now animates (slide-in/out, QR
  fade-in, per-state cross-fades for idle/starting/waiting/approved/
  error/expired, a brief "Bestätigt" checkmark beat before login, a
  subtle pulse while waiting on the phone, and explicit hover/pressed/
  focus/disabled styling on the custom-styled "Alternativ Code" button).
  Purely visual - no change to the flow/security state machine, PAM,
  broker, or KWallet logic.

## [0.4.1]

### Fixed
- Local failure lockout now counts only genuine authentication denials.
  Cancellation, expiry, upstream token-endpoint throttling, and infrastructure
  errors are neutral and cannot manufacture a user lockout.
- Rate-limit backoff is monotonic, cancellation interrupts long backoff waits,
  and terminal infrastructure throttling is exposed as an error rather than
  an authentication denial.
- Rollback now preserves unrelated SDDM configuration while changing only the
  custom theme selection back to Debian Breeze, and package removal no longer
  manually deletes dpkg-owned files.

### Changed
- Debian package installs now generate the custom SDDM theme automatically
  from the installed pristine Debian Breeze theme plus this project's
  additive patches; the original Breeze files remain untouched.
- Rollback preserves encrypted KWallet credentials and leaves package-owned
  files to dpkg when the package is installed.

### Fixed
- `scripts/setup-kwallet-credential.sh`: no longer widens an existing
  `/etc/credstore.encrypted` directory's permissions to `0755` on every
  run - only ever creates it at `0700` if missing, and hardens (never
  loosens) an existing directory's mode back down to `0700`. Found on
  production after the v0.4.0 cutover (`P0`, directory-metadata exposure
  only - file contents remained `0600` throughout).
- Broker: HTTP 429 from Authelia's own token-endpoint rate limiter is now
  surfaced to the theme (`rate_limited`/`retry_after_seconds` on
  `/status`) instead of being silently indistinguishable from a normal
  "still waiting on the user" `pending` state. `Retry-After` (seconds or
  HTTP-date form) is parsed when present; if honoring it would run past
  the flow's own remaining lifetime, the flow now fails closed
  (`rate_limited`) instead of quietly waiting out a deadline it can never
  reach. Never weakens or reconfigures Authelia's actual rate limit - see
  `docs/architecture.md`'s new "Upstream rate limiting" section.

## [0.4.0]

### Added
- Broker: resolve the target account's UID via NSS fresh on every flow
  start and embed it in the approval marker (v2 format:
  `VERSION=2`/`USERNAME=`/`UID=`/`NONCE=`/`APPROVED_AT=`).
- PAM module: re-resolve the requesting account's UID via NSS at marker
  consumption time and require an exact match against the marker's
  embedded UID - an account deleted and recreated (same username,
  different UID) between approval and login is now rejected instead of
  silently trusted.
- KWallet: per-user credentials. `kwallet_credential_name` is now a
  prefix (`kwallet.secret.<user>`, one systemd-creds encrypted file per
  allowed user) instead of one credential shared by every allowed user
  - see `scripts/setup-kwallet-credential.sh` and `docs/kwallet.md`.
  The KWallet hand-off marker also now carries the account's UID, and
  `kwallet-secretd` refuses to release a secret unless the requesting
  UID matches it.
- `tests/integration/pam-multiuser-test.sh`: proves the core
  cross-user invariant (alice's approval never authenticates bob and
  vice versa, parallel alice+bob approvals stay independent) against
  real local test accounts and the compiled PAM module.
- Broker unit tests for OIDC identity determination/exact-match binding
  (`identity_test.go`) and a concurrent alice/bob race test.
- Theme: the smartphone/passkey flow is now bound to whichever account
  SDDM's own existing user selector (avatar list or manual username
  entry) currently has selected, captured immutably per flow
  (`pixelFlow.targetUsername`); changing the selection mid-flow cancels
  it instead of silently retargeting.

### Changed
- Removed the v0.3.0-era restriction that refused
  `kwallet_auto_unlock=true` with more than one `allowed_users` entry -
  per-user credentials make this safe now.

## [0.3.0]

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
- Broker: `kwallet_auto_unlock=true` is now refused at config-load time
  when `allowed_users` has more than one entry - `kwallet-secretd` has
  no per-user credential binding yet, so this prevents one user's
  KWallet secret from being handed to another. Documented in
  `docs/architecture.md`'s new "Multi-user readiness" section, along
  with the existing per-user isolation of rate limits, flow
  supersession, cancellation, and approval markers, and the
  `REQUESTED_LOCAL_USER`/`AUTHENTICATED_AUTHELIA_USER`/`BOUND_LOCAL_USER`
  identity-binding model. 8 new regression tests
  (`src/broker/multiuser_test.go`).

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
