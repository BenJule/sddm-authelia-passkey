# Native SDDM Theme

The package ships two SDDM themes side by side:

- the existing compatibility theme
- the original Qt6 Native Theme at
  `/usr/share/sddm/themes/sddm-authelia-passkey-native`

The Native Theme remains opt-in. Package installation and upgrade do
not select it automatically and do not restart SDDM.

## v1.10.0 feature parity

v1.10.0 moves the Native Theme from foundation status to functional parity
with the existing compatibility theme.

It includes:

- SDDM user list and manual username prompt
- password login and generic failure feedback
- session and keyboard-layout selection
- avatar handling
- supported power actions
- complete broker-backed Smartphone-Login
- QR code and alternate device code
- local/NSS identity information
- device-flow countdown
- connection/service state
- provider-throttle presentation
- approval-to-SDDM transition
- explicit cancellation
- stale response isolation
- retry/recovery states
- password fallback

## v1.11 responsive UX

v1.11 keeps the same Native Theme authentication and Smartphone-flow
state machine while adapting only presentation geometry.

On sufficiently wide displays the Smartphone-Login panel becomes a
right-side panel and leaves a usable login area beside it. When the
sidebar plus the minimum login width no longer fit, the same panel
becomes a centred modal overlay with a dimming/input-blocking scrim.

The breakpoint is derived from available logical-pixel space rather
than a hard-coded display resolution. Short displays additionally use
reduced margins, a shorter user list and a smaller QR presentation.

The responsive contract is exercised at 1024x600, 1280x720,
1366x768, 1920x1080 and 2560x1080.

No broker, PAM, approval-marker or authentication decision changes are
part of responsive UX.

## v1.11.1 visual-quality hotfix

v1.11.1 keeps the v1.11 authentication and responsive behaviour while
replacing visibly raw Qt Basic control surfaces with project-owned visual
components.

The patch improves login-card hierarchy, username-first account
presentation, password/session controls, power actions, German date
formatting and the Smartphone-Login panel.

No PAM, broker, approval-marker, OIDC/provider, KWallet authentication or
username/session-binding behaviour changes are part of this patch.

## v1.12 accessibility hardening

v1.12 applies explicit accessibility semantics to the independent
Native Theme while preserving the v1.11.1 presentation and
authentication model.

The Native Theme accessibility contract includes:

- Dialog semantics for the modal Smartphone-Login layout and Pane
  semantics for the non-modal sidebar layout
- explicit names and descriptions for Smartphone Login, QR code,
  device code, connection status and countdown
- alert semantics for authentication states requiring attention
- List/ListItem semantics and selected-state exposure for account choice
- explicit accessible names for password, session and keyboard layout
- decorative avatars and status indicators excluded from the
  accessibility tree when semantic text already conveys the information
- deterministic focus transfer into Smartphone Login, back to the
  password path and into manual username entry

The password path remains available throughout.

Structural semantics are covered by deterministic tests and qmllint.
Actual AT-SPI/Orca interaction in a real SDDM session remains a manual
lab verification item and is not claimed by CI.

No broker, PAM, approval-marker or authentication decision changes are
part of accessibility hardening.

## Security model

The Native Theme communicates only with the local broker at
`127.0.0.1:7899`.

It does not contact LDAP, AD, FIDO hardware or an OIDC provider directly.

The local broker HTTP interface is not the authentication trust boundary.
PAM remains the authority and must consume the protected, single-use approval
marker before the login succeeds.

Every Smartphone flow captures the selected canonical username and session
index when it starts. Late responses from an old generation or old broker
session are ignored. Switching accounts cancels the current device flow.

The UI never interprets ordinary provider polling throttling as repeated user
login attempts.

## Expiry

The broker's `expires_at` value is used for the visible countdown. The QML
timer is display-only and never decides whether authentication has expired.
The broker remains authoritative.

## Provenance

The Native Theme is from scratch. See `theme/native/PROVENANCE.md`.

No compatibility-theme QML is copied into the Native Theme.

## Current roadmap position

v1.10.0 established feature parity.

v1.11 added responsive Native Theme presentation while keeping the
authentication model unchanged.

v1.11.1 added visual-quality polish while preserving that model.

v1.12 adds Native Theme accessibility hardening while keeping the
authentication model unchanged.

Later releases separately address:

- v1.13 native branding
- later recovery, visual regression and cutover work

The compatibility theme remains supported throughout.
