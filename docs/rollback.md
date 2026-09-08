# Rollback / uninstall

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
