# Optional: KWallet auto-unlock

Off by default (`kwallet_auto_unlock=false`). A failed or unavailable
KWallet secret **never** blocks login either way - it only means KWallet
falls back to its normal manual password prompt the first time an
application tries to use it.

## Credential protection modes

| Mode | Command | Security notes |
|---|---|---|
| `host` | `systemd-creds encrypt --with-key=host` | Bound to `/var/lib/systemd/credential.secret` (root-only, `0400`). Protects the credential file if copied elsewhere; does **not** protect against an already-compromised root on the same machine. Works on any host, no TPM required. |
| `host+tpm2` | `systemd-creds encrypt --with-key=host+tpm2` | Additionally sealed to your TPM2's PCR state. Stronger, but only usable if `systemd-analyze has-tpm2` on your machine actually reports usable hardware (check first - this project will never claim TPM2 protection you don't actually have). |

Check before choosing:

```
systemd-analyze has-tpm2
ls /dev/tpm0 /dev/tpmrm0
```

If neither device exists, only `host` mode is available to you - this is
normal on most desktops/laptops without a discrete or firmware TPM
exposed to Linux, and on virtual machines without vTPM passthrough.

## Setup (interactive, never automated, per user)

Credentials are **per local user**, not shared - `alice` and `bob` each
get their own encrypted credential file, and `kwallet-secretd` only ever
releases the one matching the account whose login-approval marker (and
its embedded UID) was just consumed by PAM. This project's installer
**never** accepts a KWallet password as an argument, environment
variable, or piped-without-your-own-terminal input.

For each user you want KWallet auto-unlock for:

```
sudo /usr/share/sddm-authelia-passkey/setup-kwallet-credential.sh alice
```

(source checkout: `sudo scripts/setup-kwallet-credential.sh alice`) -
prompts interactively (no echo), resolves the account via NSS, refuses
`root`, and writes
`/etc/credstore.encrypted/kwallet.secret.alice` (`root:root`, `0600`).

The value you enter must be **the same password that user's KWallet is
already using** (or that you set it to, via KWalletManager) -
`pam_kwallet5` unlocks by receiving this value as `PAM_AUTHTOK`, exactly
as it would receive their typed login password on the normal path.

The setup command also creates that user's dedicated systemd
`LoadCredentialEncrypted=` drop-in atomically, runs `systemctl
daemon-reload`, and restarts only
`sddm-authelia-passkey-kwallet-secretd.service`. No manual
`systemctl edit` step is required. Running setup for one user never
rewrites another user's credential/drop-in.

Then enable the feature in `/etc/sddm-authelia-passkey/config.conf`:

```
kwallet_auto_unlock=true
```

## Migrating from a single-user (pre-per-user) setup

Older configurations used one global
`/etc/credstore.encrypted/kwallet.secret` for whichever single user was
configured. This is never migrated automatically. If you have exactly
one allowed user and want to keep using that same password, just run
`setup-kwallet-credential.sh` for them as above (re-entering the
password) - the old file is left in place, unused, and can be removed
manually once you've confirmed the new one works. With more than one
allowed user, there is no "correct" automatic choice of who the old
credential belonged to, so it is never assigned to anyone.

## Recovery

If the credential is lost, corrupted, deleted, or the TPM is reset/the
motherboard replaced:

- Smartphone/passkey login continues to work exactly as before - nothing about the
  login decision depends on this credential.
- KWallet auto-unlock silently fails; the manual password prompt appears
  the first time an application accesses the wallet.
- Your actual KWallet password (which you still know) continues to work
  manually, unaffected.
- No desktop lockout in any scenario.

To re-run setup after a failure, just repeat the interactive step above -
it overwrites the existing encrypted credential file.
