# SDDM Authelia Passkey Native

Original, from-scratch Qt6 SDDM theme for this project.

Status in v1.10.0: functional feature parity, still opt-in.

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

The Native Theme remains opt-in in v1.10.0. Responsive UX refinement,
accessibility hardening and native branding remain separate roadmap releases.
