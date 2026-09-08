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

## Setup (interactive, never automated)

This project's installer **never** accepts your KWallet password as an
argument, environment variable, or piped-without-your-own-terminal input.
You run this yourself:

```
read -s -p "KWallet password: " SECRET && \
  printf '%s' "$SECRET" | sudo systemd-creds encrypt --with-key=host \
    --name=kwallet.secret - /etc/credstore.encrypted/kwallet.secret && \
  unset SECRET
```

The value you enter must be **the same password your KWallet is already
using** (or that you set it to, via KWalletManager) - `pam_kwallet5`
unlocks by receiving this value as `PAM_AUTHTOK`, exactly as it would
receive your typed login password on the normal path.

Then in `/etc/sddm-authelia-passkey/config.conf`:

```
kwallet_auto_unlock=true
```

## Recovery

If the credential is lost, corrupted, deleted, or the TPM is reset/the
motherboard replaced:

- Pixel login continues to work exactly as before - nothing about the
  login decision depends on this credential.
- KWallet auto-unlock silently fails; the manual password prompt appears
  the first time an application accesses the wallet.
- Your actual KWallet password (which you still know) continues to work
  manually, unaffected.
- No desktop lockout in any scenario.

To re-run setup after a failure, just repeat the interactive step above -
it overwrites the existing encrypted credential file.
