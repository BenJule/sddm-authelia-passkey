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

## v1.13 native branding

v1.13 adds optional vendor-neutral branding to the independent Native Theme.

Branding uses SDDM's native `theme.conf.user` mechanism and remains strictly
presentation-only.

Supported presentation controls include:

- brand name
- absolute local logo path
- optional SDDM local hostname
- administrator-supplied domain/realm
- avatar visibility
- validated custom accent colour

Remote logo URLs are rejected. Custom accents accept only opaque
`#RRGGBB` values. Invalid values fall back to the v1.12 Native Theme accent.

With no override, the v1.12 presentation remains the default.

No broker, PAM, KWallet, approval-marker, provider or authentication
decision changes are part of Native Branding.

## v1.14 failure and recovery UX

v1.14 makes failure states explicit without moving authentication authority
into QML.

The Native Theme distinguishes:

- broker offline from an authentication denial
- temporary provider/service unavailability from real flow expiry
- provider throttling from denial
- account ineligibility from infrastructure failure
- malformed status data from a valid authentication result
- QR rendering failure from loss of the device-code fallback
- SDDM/PAM login failure after approval from a reusable approval

The password path remains visible in every recoverable state.

A missing or failed QR image does not terminate an otherwise usable device
flow when the device code and verification address are available. The panel
switches to explicit alternate-path wording.

The broker remains responsible for upstream polling cadence and
`Retry-After`. The Native Theme only displays the broker's state. Its short
retry delay after a local `/start` 429 is a client-side anti-double-click
guard and is not described as server-side security or as the provider's
actual Retry-After value.

If SDDM reports `loginFailed` after Smartphone approval, the Native Theme
invalidates the old presentation generation and removes the old QR/session
presentation before offering password login or an explicit new flow. It
never replays the previous approval automatically.

No broker, PAM, approval-marker, KWallet, FIDO2 or authentication-decision
change is part of v1.14.

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

v1.12 added Native Theme accessibility hardening while keeping the
authentication model unchanged.

v1.13 added optional vendor-neutral Native Theme branding while preserving
the v1.12 default appearance and authentication model.

v1.14 hardens Native Theme failure and recovery UX while preserving the
same authentication authority and security boundaries.

Later releases separately address:

- deterministic visual-regression automation
- explicit installation modes
- migration and rollback
- Native Theme hardening and release-candidate work

The compatibility theme remains supported throughout.
