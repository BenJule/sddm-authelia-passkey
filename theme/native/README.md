# SDDM Authelia Passkey Native

Original, from-scratch Qt6 SDDM theme for this project.

As of v2.0.0, this is the **recommended** deployment mode for new
installations (see `docs/stability.md` and the theme deployment mode
matrix in `docs/validated-environment.md`). See `CHANGELOG.md` for the
full v1.14.0-v2.0.0 history (failure/recovery UX, the visual regression
framework, theme installation modes, migration/rollback tooling, and
the v1.18.0 security hardening review).

The native theme is installed alongside the existing compatibility
theme and is never selected automatically - "recommended" is a
statement about which mode to choose, not a change to that: choosing
any mode (native, compatibility, or staying backend-only) is always an
explicit administrator action via `sddm-authelia-passkey-admin
apply-mode`/`migrate`.

## v1.10.0

The Native Theme provides:

- switchable SDDM user list
- manual username entry
- password login
- session selection
- keyboard-layout selection
- avatar handling
- power actions
- broker-backed Smartphone-Login
- QR display
- alternate device code
- local/NSS identity display
- countdown
- service/connection state
- approval transition
- cancellation
- stale-response isolation
- retry and recovery states
- explicit password fallback

The Smartphone flow communicates only with the project broker on
`127.0.0.1:7899`.

It never communicates directly with a directory server, FIDO device, or
identity provider.

PAM remains the authentication authority. An HTTP response from the broker
does not authenticate a user. The SDDM login is only attempted after the
broker reports an approval for the exact account bound to the current flow,
and PAM still has to consume the corresponding protected approval marker.

The Native Theme remains opt-in. v1.11 added responsive presentation
without changing authentication semantics. v1.11.1 added visual-quality
polish. v1.12 added accessibility hardening. v1.13 adds optional Native
Theme branding without changing authentication semantics.


## v1.11.1 visual-quality hotfix

v1.11.1 retains v1.11 responsive and authentication behaviour while
replacing raw Qt Basic presentation with project-owned styled controls and
a visually integrated Smartphone Login panel.


## v1.12 accessibility hardening

v1.12 keeps the v1.11.1 visual presentation and adds explicit
accessibility roles, names, descriptions, selection state and focus
transitions for the Native Theme.

The Smartphone panel reports Dialog semantics in overlay mode and Pane
semantics in sidebar mode. Account selection exposes List/ListItem
semantics. QR/device-code, status, countdown, password, session and
keyboard controls expose explicit assistive-technology metadata.

Authentication authority remains exclusively with SDDM/PAM and the local
broker flow remains unchanged.


## v1.13 native branding

v1.13 adds optional vendor-neutral branding through SDDM
`theme.conf.user`.

Supported presentation controls include a brand name, absolute local logo,
local hostname, administrator-supplied domain/realm, avatar visibility and
a validated custom accent colour.

Remote logo URLs are rejected. Invalid custom accents fall back to the
normal Native Theme accent. With no override, the v1.12 appearance is
preserved.

Branding cannot change PAM, broker, KWallet, approval-marker or
SmartphoneFlowController authentication decisions.
