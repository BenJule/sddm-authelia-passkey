# Theme installation modes

Since v1.16.0 there are three explicit modes:

- `native`
- `compatibility`
- `backend-only`

Show status:

    sudo sddm-authelia-passkey-admin mode-status

Select Native Theme:

    sudo sddm-authelia-passkey-admin apply-mode native

Select compatibility theme:

    sudo sddm-authelia-passkey-admin apply-mode compatibility

Restore the previous SDDM theme selection:

    sudo sddm-authelia-passkey-admin apply-mode backend-only

The Native Theme remains opt-in.

## Safety

The previous SDDM theme selection is preserved before the first managed switch.

`backend-only` restores that previous selection.

External drift, invalid targets, and symlinked config/theme files fail closed.

Unrelated themes are not overwritten or deleted.

Mode changes never restart SDDM and never terminate active sessions.

## Package upgrades

Package upgrades may refresh theme payloads, but they never apply or change
an installation mode.

State is stored below:

    /var/lib/sddm-authelia-passkey/theme-mode/

Do not edit this state manually.
