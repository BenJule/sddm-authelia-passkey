# Rollback / uninstall

## If you installed the `.deb` package

`sudo apt purge sddm-authelia-passkey` (or `apt remove`) is the normal
path - the package's own `prerm` maintainer script automatically calls
`rollback.sh` (shipped at `/usr/share/sddm-authelia-passkey/rollback.sh`)
before the package's files are removed, restoring `/etc/pam.d/sddm`
first. `apt purge` additionally removes
`/etc/sddm-authelia-passkey/config.conf`; `apt remove` leaves it in
place. You can also run `/usr/share/sddm-authelia-passkey/rollback.sh`
manually at any time without removing the package.

## If you installed from source

Two related scripts, for two different situations:

- **`scripts/rollback.sh`** - emergency restore. Finds the most recent
  `/root/sddm-authelia-passkey-backup-*` (or accepts one as `$1`),
  restores `/etc/pam.d/sddm` from it, stops and removes every installed
  component (binaries, systemd units, KWallet credential, theme copy).
  Leaves `/etc/sddm-authelia-passkey/config.conf` in place.
- **`scripts/uninstall.sh`** - calls `rollback.sh`, then additionally
  offers to remove the config directory too.

Neither script touches `common-auth`, `sudo`'s PAM config, `sshd`'s PAM
config, LUKS, or initramfs - by design, this project's installer never
writes to any of those in the first place, so there is nothing there to
undo.

After either script: verify `/etc/pam.d/sddm`'s hash matches
`sddm.pam.orig.sha256` inside the backup directory it used, then test a
normal password login before considering the rollback complete.

## Removing just the PAM integration (keeping everything else installed)

`scripts/disable-pam.sh` (`/usr/share/sddm-authelia-passkey/disable-pam.sh`
in a package install) is the symmetric counterpart to `enable-pam.sh`:
it removes only the `pam_authelia_passkey.so` line (and the 3 lines
`enable-pam.sh` added alongside it) from `/etc/pam.d/sddm`, leaving the
broker, config, theme, and any FIDO2/KWallet setup untouched and
reversible by simply running `enable-pam.sh` again. It refuses if
`pam_u2f.so` (FIDO2) is still layered on top - run
`disable-fido2.sh` first in that case, since it was inserted directly
above the line `disable-pam.sh` removes.

## Break-glass: forcing password-only login immediately

`scripts/break-glass.sh` (`/usr/share/sddm-authelia-passkey/break-glass.sh`
in a package install) is the zero-dependency emergency path for when you
need password-only login back *right now* and don't want to hunt for
(or can't trust) a specific `rollback.sh` backup directory. Unlike every
other script here, it doesn't require locating any prior state:

```
sudo /usr/share/sddm-authelia-passkey/break-glass.sh            # neutralize
sudo systemctl restart sddm                                     # or reboot
# ... investigate, fix, whatever's needed ...
sudo /usr/share/sddm-authelia-passkey/break-glass.sh --restore  # undo
sudo systemctl restart sddm
```

It comments out (never deletes) every `pam_authelia_passkey.so` and
`pam_u2f.so` line it finds, prefixing each with a distinct
`# BREAK-GLASS-DISABLED: ` marker so `--restore` can find and undo
exactly those lines later - nothing else (services, theme, config,
credentials) is touched. Idempotent in both directions; re-verifies
`common-auth`/sudo/sshd PAM hashes unchanged after editing, rolling back
on any unexpected difference, like every other PAM-editing script here.

## Admin CLI

`sddm-authelia-passkey-admin` (installed to `/usr/sbin`) is a small,
fixed-dispatch, read-only helper for the questions an admin actually
asks day to day - it does not edit anything itself, only delegates to
already-existing, already-tested tooling:

```
sddm-authelia-passkey-admin status       # is the stack up right now (= postflight.sh)
sddm-authelia-passkey-admin test-config  # validate config.conf without starting anything
sddm-authelia-passkey-admin list-users   # who is eligible, who has a FIDO2 credential
sddm-authelia-passkey-admin audit-log    # "SECURITY:"-tagged broker log lines via journalctl
```

`test-config` needs no root (it just runs the broker binary's own
`--check-config` flag against the same `LoadConfig`/`Validate` logic the
real broker uses at startup); the other subcommands read
service/PAM/journal state and require root.
