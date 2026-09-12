# Theme migration & rollback

Since v1.17.0, `sddm-authelia-passkey-admin` provides guided migration
between the three theme installation modes (see
[theme-installation-modes.md](theme-installation-modes.md)), on top of
the existing `apply-mode` command. It never replaces `apply-mode` -
`migrate` delegates to it - it only adds preflight checks, an undo
command, and recovery from an interrupted attempt.

## Commands

Check before switching, without changing anything:

    sudo sddm-authelia-passkey-admin migrate-preflight native

Migrate to a mode:

    sudo sddm-authelia-passkey-admin migrate native
    sudo sddm-authelia-passkey-admin migrate compatibility
    sudo sddm-authelia-passkey-admin migrate backend-only

Undo the most recent migration:

    sudo sddm-authelia-passkey-admin rollback-migration

Show migration history and whether anything is currently interrupted:

    sudo sddm-authelia-passkey-admin migrate-status

Resume an interrupted migration instead of undoing it:

    sudo sddm-authelia-passkey-admin migrate-resume

## `rollback-migration` is single-level undo

`rollback-migration` restores whichever mode was active immediately
before the last successful `migrate`. It is not a history stack:
calling it twice in a row toggles back and forth between the two modes
of the last transition, it does not walk further back through earlier
migrations.

This is separate from `apply-mode backend-only`'s own baseline
restore, which recovers the SDDM theme selection that existed before
this project ever managed it (see
[theme-installation-modes.md](theme-installation-modes.md)). Use
`rollback-migration` to undo a recent mode change; use
`apply-mode backend-only` to fully step back out of managed theme
selection.

## If a migration is interrupted

If `migrate` is interrupted (for example, the machine loses power
mid-operation), the next command run reports it:

    sudo sddm-authelia-passkey-admin migrate-status
    MIGRATE_INTERRUPTED=YES
    MIGRATE_INTERRUPTED_FROM=compatibility
    MIGRATE_INTERRUPTED_TO=native
    ...

A plain `migrate` refuses to run again while this is pending. Resolve
it first, either by finishing the switch:

    sudo sddm-authelia-passkey-admin migrate-resume

or by undoing it and returning to the mode that was active before the
interrupted attempt:

    sudo sddm-authelia-passkey-admin rollback-migration

`migrate-preflight` and `migrate-status` stay available at any time and
never change state.

## Safety

- Every step delegates to the same `apply-mode`/`theme-mode.sh` logic
  already used by direct mode switches - migration does not reimplement
  theme validation, symlink safety, or atomic config writes.
- Migrating never restarts SDDM and never terminates active sessions.
- Migration never touches PAM, the broker, FIDO2, or OIDC
  configuration.
- No package is ever downgraded or reinstalled to change mode.
- A no-op migration (already at the requested mode) does not record a
  migration entry, so it cannot be undone via `rollback-migration`.

State is stored below and should not be edited manually:

    /var/lib/sddm-authelia-passkey/migrate/
