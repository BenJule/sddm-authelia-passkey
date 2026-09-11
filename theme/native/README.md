# SDDM Authelia Passkey Native

Original, from-scratch Qt6 SDDM theme for this project.

Current stable baseline: v1.11.1 visual quality on top of the
v1.11 responsive presentation. v1.12.0 targets accessibility hardening;
the Native Theme remains opt-in.

The native theme is installed alongside the existing compatibility theme
and is never selected automatically.

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
polish. v1.12 adds accessibility hardening; native branding remains a
separate v1.13 roadmap release.


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
