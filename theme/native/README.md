# SDDM Authelia Passkey Native (v1.9.0 - Foundation)

An original, from-scratch Qt6 SDDM greeter theme for this project.
Installed alongside (not replacing) the existing Debian Breeze
compatibility theme at
`/usr/share/sddm/themes/sddm-authelia-passkey-native`.

**Status: experimental, opt-in, foundation-level.** It is not selected
automatically by package installation or upgrade, and is not the
default anywhere.

## What this release is

- password login, wired to the real `sddm.login()` call
- real session selection (`sessionModel`)
- real user display (`userModel`) with a safe avatar fallback
- real power actions, gated by `sddm.canSuspend`/`canReboot`/`canPowerOff`
- a keyboard-layout affordance when more than one layout is configured
- a `Smartphone-Login` action that opens a clearly-labelled
  **preview/placeholder** panel

## What this release deliberately is not

- **not** feature parity with the compatibility theme (see
  `NATIVE-THEME-ROADMAP.md` in the private roadmap repo, or
  `docs/native-theme.md` in this repo, for the full track)
- **not** a working QR/device-code/passkey flow - the Smartphone-Login
  action here never talks to the broker and never claims a login
  occurred. That full flow is v1.10.0 (Native Theme Feature Parity).
- **not** a switchable multi-user list yet (shows the SDDM-selected/
  last user only) - a full user list is also v1.10.0 scope.
- **not** responsive/accessibility-hardened yet - see v1.11.0/v1.12.0.
- **not** branded/configurable yet - native branding parity with the
  v1.8.0 compatibility-theme branding contract is v1.13.0.

## Why from scratch

See `PROVENANCE.md` for the explicit statement of what was and was not
used to build this theme. In short: no Debian Breeze or KDE Breeze
source was copied, no Debian/KDE artwork is bundled, and only
documented SDDM greeter context APIs (`sddm`, `userModel`,
`sessionModel`, `keyboard`) plus standard Qt Quick Controls/Layouts
were used.

## Security

This theme does not implement any authentication logic itself. It
only calls `sddm.login(username, password, sessionIndex)` - PAM
remains the sole authentication authority, exactly as with the
compatibility theme. See the project's `docs/architecture.md` and
`docs/security.md` for the full security model, which this theme does
not change in any way.
