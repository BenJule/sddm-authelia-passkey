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
