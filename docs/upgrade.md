# Upgrading

## In-place package upgrade

```
sudo apt update
sudo apt install --only-upgrade sddm-authelia-passkey
```

(or `apt install ./sddm-authelia-passkey_X.Y.Z-1_amd64.deb` against a
downloaded release asset). This is the only supported upgrade path.

`/etc/sddm-authelia-passkey/config.conf` is a dpkg conffile: an upgrade
never overwrites it, regardless of how old it is or how many releases
have shipped since it was written. Every configuration key introduced
after your config.conf was written (`account_source`, `provider_kind`,
`minimum_uid`/`deny_users`/`allowed_groups`/`require_group_match`,
`fido2_*`, ...) takes its documented backward-compatible default when
absent - see each key's default in
`config/examples/config.conf.example` and `docs/configuration.md`. This
is verified two ways:

- `TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults`
  (`src/broker/config_test.go`) loads a config.conf containing only the
  handful of keys that existed before v0.5.0 and asserts every
  since-added key resolves to its default and the config still
  validates.
- The `upgrade` CI job (`.github/workflows/package.yml`) installs the
  actual previously-published release, writes that same pre-v0.5.0-shaped
  config.conf, integrates PAM, then upgrades in place to the
  newly-built package and asserts `/etc/pam.d/sddm` and config.conf are
  byte-identical to before the upgrade, and that the new admin CLI
  accepts the untouched old config.

An upgrade **never** touches `/etc/pam.d/sddm`, enables/disables FIDO2,
or changes which PAM lines are integrated - it only replaces installed
files under `/usr/lib/sddm-authelia-passkey/`,
`/usr/lib/x86_64-linux-gnu/security/pam_authelia_passkey.so`,
`/usr/share/sddm-authelia-passkey/`, and (if you enabled it)
`/usr/lib/sddm-authelia-passkey/kwallet-secretd`. New optional features
shipped in a given release (a new `fido2_*` key, `provider_kind=oidc`,
`account_source=nss`, ...) are opt-in: an untouched config.conf keeps
you on exactly the behavior you had before, nothing is silently
upgraded to a new default that could change who is authorized.

## Theme installation mode across upgrades

Since v1.16.0, SDDM theme selection uses an explicit persistent mode:

- `native`
- `compatibility`
- `backend-only`

Package upgrades never apply a mode automatically and never silently
switch the selected mode.

An upgrade may refresh the installed Native Theme or regenerate the
compatibility-theme payload, but the managed SDDM theme selection and
its rollback baseline remain unchanged.

Check the current state with:

    sudo sddm-authelia-passkey-admin mode-status

See `docs/theme-installation-modes.md` for the full mode and rollback
contract.

## If something goes wrong after an upgrade

`sudo /usr/sbin/sddm-authelia-passkey-admin test-config` validates the
running config.conf against the newly-installed broker without
starting anything - run this first. `sudo /usr/sbin/sddm-authelia-passkey-admin
status` shows whether the broker/sddm/kwallet-secretd stack is actually
up. If the new version's broker refuses to start on a config that
worked before, that is treated as a packaging bug in this project, not
something you're expected to work around - please open an issue.

See `docs/rollback.md` for `break-glass.sh` (immediate password-only
recovery) if a login regression needs to be worked around before a fix
is available, and `scripts/rollback.sh`/`apt remove` for a full
uninstall back to a state with no trace of this project's PAM
integration.

## What is not a supported upgrade path

- Downgrading (installing an older `.deb` over a newer one) is not
  tested and not supported - `dpkg`/`apt` will generally refuse this
  anyway unless forced.
- Skipping this project entirely and hand-editing
  `/etc/sddm-authelia-passkey/config.conf` into a shape that never
  existed in any released version is outside the scope of what
  `TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults` or the
  `upgrade` CI job can prove.
