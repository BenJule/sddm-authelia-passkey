# Native SDDM Theme

The package ships two SDDM themes side by side:

- the existing compatibility theme
- the original Qt6 Native Theme at
  `/usr/share/sddm/themes/sddm-authelia-passkey-native`

The Native Theme remains opt-in in v1.10.0. Package installation and upgrade
do not select it automatically and do not restart SDDM.

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

v1.10.0 is feature parity.

Later releases separately address:

- v1.11 responsive UX
- v1.12 accessibility hardening
- v1.13 native branding
- later recovery, visual regression and cutover work

The compatibility theme remains supported throughout.
