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

- `sddm-authelia-passkey-admin`'s five subcommands
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
