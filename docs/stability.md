# Stability (as of v1.0.0)

## `config.conf`

Every key documented in `config/examples/config.conf.example` is
considered stable from v1.0.0 onward:

- An existing key's meaning and default (where it has one) will not
  silently change. If a key's behavior must change in a
  backward-incompatible way, that will ship as a new key with the old
  one deprecated (accepted, documented as deprecated, still honored)
  for at least one full release cycle before removal.
- Every key added since the project's first release
  (`account_source`, `provider_kind`, `minimum_uid`/`deny_users`/
  `allowed_groups`/`require_group_match`, `fido2_*`) is opt-in with a
  backward-compatible default - an untouched config.conf from any prior
  release keeps behaving exactly as it did before, forever, unless you
  deliberately set the new key (see `docs/upgrade.md` and
  `TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults`). This
  pattern continues for any future key.
- Unknown keys and malformed lines are rejected at load time (fail
  closed), not silently ignored - a typo in a key name has always
  produced a startup error, not a silently-ignored setting, and this
  will not change.

## The broker's HTTP API (`127.0.0.1:7899`)

**Not a stable public API.** `/start`, `/status`, `/cancel`, and their
exact request/response shapes are a private implementation detail
between this project's own broker, PAM module, and QML theme, which are
always installed and upgraded together as one package. Nothing outside
this project should depend on this API's shape - it is bound to
localhost specifically so it is not reachable from outside the host in
the first place, and it can change between any two releases without a
deprecation cycle.

## The approval marker format (`VERSION=` field)

The on-disk marker format (`/run/sddm-authelia-passkey/approved-*`) is
versioned internally (`VERSION=2` today) precisely so it *can* change
between releases without breaking anything: the broker and PAM module
are always upgraded together from the same package, so there is no
cross-version compatibility requirement for this format - unlike
`config.conf`, which an admin may leave untouched across many releases.

## Command-line tools

- `sddm-authelia-passkey-admin`'s subcommands
  (`status`/`health`/`test-config`/`list-users`/`audit-log`) and their
  general output shape are considered stable; new subcommands may be
  added, existing ones will not be removed or repurposed without a
  deprecation notice in `CHANGELOG.md`.
- The one-shot scripts under `/usr/share/sddm-authelia-passkey/`
  (`enable-pam.sh`, `disable-pam.sh`, `enable-fido2.sh`,
  `disable-fido2.sh`, `break-glass.sh`, `rollback.sh`, ...) are
  considered stable in their exit codes (`0` success, non-zero failure)
  and the `KEY=VALUE`-shaped status lines they print
  (`PAM_INSTALL=GREEN`, `FIDO2_PAM_INSTALL=GREEN`, etc.) - useful if you
  script around them - but their human-readable `[OK]`/`[FAIL]`/`[INFO]`
  detail lines are not guaranteed to stay byte-identical between
  releases.

## Frozen as of v1.19.0: theme installation mode, migration, and branding

The following interfaces, all added since v1.0.0, are frozen from
v1.19.0 onward under the same rule as `config.conf` above: an existing
field's meaning will not silently change, and a backward-incompatible
change ships as a new field with the old one deprecated for at least
one full release cycle, documented in `CHANGELOG.md`. As with
`config.conf`, this covers the field *names and meaning*, not their
exact ordering or the presence of human-readable text alongside them.

**Install-mode interface** (`sddm-authelia-passkey-admin
mode-status`/`apply-mode`, delegating to `theme-mode.sh`): the three
mode names (`native`, `compatibility`, `backend-only`) and every
`KEY=VALUE` field they print - `INSTALL_MODE`, `THEME_SELECTION_MANAGED`,
`EFFECTIVE_THEME`, `MODE_TARGET`, `TARGET_VALID`, `SELECTION_FILE`,
`BASELINE_THEME`, `RESTORED_THEME`, `MODE_APPLY`, `SDDM_RESTART_USED`,
`TARGET` (from `check-target`), and the `THEME_MODE_ERROR=` failure
prefix. See `docs/theme-installation-modes.md`.

**Migration interface** (`sddm-authelia-passkey-admin
migrate-preflight`/`migrate`/`rollback-migration`/`migrate-resume`/
`migrate-status`, delegating to `theme-migrate.sh`): every
`MIGRATE_*`/`MIGRATION_ID=` field these five subcommands print, and the
`THEME_MIGRATE_ERROR=` failure prefix. Single-level-undo semantics for
`rollback-migration` (documented in `docs/theme-migration.md`) are part
of this frozen contract - a future release cannot silently turn this
into multi-level history without a new subcommand.

**Branding schema** (`theme.conf.user`, both the Native Theme and the
compatibility theme): `ui_brand_name`, `ui_brand_logo`,
`ui_show_hostname`, `ui_show_domain`, `ui_brand_domain`,
`ui_show_avatar`, `ui_accent`, `ui_accent_color`, and the safety
behavior around them - a missing/invalid/unsafe value always falls
back to the pre-branding zero-config appearance, never a startup
failure. `sddm-authelia-passkey-admin branding-status`'s
`BRANDING_OVERRIDE_NATIVE=`/`BRANDING_OVERRIDE_COMPAT=`/
`BRANDING_VALIDATION_RESULT=` fields are likewise frozen.

Internal state file formats backing these interfaces
(`/var/lib/sddm-authelia-passkey/theme-mode/`,
`/var/lib/sddm-authelia-passkey/migrate/`) are explicitly **not**
covered by this freeze, for the same reason the approval marker format
above isn't: they are read only by this project's own scripts, which
are always upgraded together as one package.

## What is explicitly *not* covered by any stability guarantee

- Internal Go package structure, function names, or test helpers in
  `src/broker`/`src/kwallet-secretd` - this project ships a compiled
  binary, not a library.
- The exact QML/theme patch content (`theme/*.patch`) - it tracks
  whatever the upstream `debian-breeze` theme looks like on the
  supported Debian release and is expected to need updates as that
  theme changes.
- Anything documented elsewhere as explicitly unvalidated (see
  `docs/validated-environment.md`).
