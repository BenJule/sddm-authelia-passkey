# Troubleshooting

**`PAM_INSTALL=REFUSED` during install** - your `/etc/pam.d/common-auth`
doesn't end in the standard pam-auth-update `requisite pam_deny.so` /
`required pam_permit.so` failsafe pair, or the expected
`pam_succeed_if.so user != root quiet_success` insertion point wasn't
found in `/etc/pam.d/sddm`. Don't hand-patch blindly; open an issue with
your (sanitized) `/etc/pam.d/sddm` and `/etc/pam.d/common-auth`.

**Pixel login shows "device flow failed: temporarily_unavailable" or
similar after several quick attempts** - almost always Authelia's own
rate limiter on `/api/oidc/token`, not a bug in this project. Wait a
minute and try once; avoid rapid repeated attempts, which can make the
backoff grow further.

**KWallet doesn't auto-unlock even with `kwallet_auto_unlock=true`** -
check `systemctl status sddm-authelia-passkey-kwallet-secretd`; if it
shows `243/CREDENTIALS` it means the encrypted credential file is
missing/corrupt - see `docs/kwallet.md` to (re)create it. This is a
fail-safe, not a crash: Pixel login itself is unaffected.

**Password login stopped auto-unlocking KWallet after installing this
project** - should not happen; this project never modifies
`pam_kwallet5`'s position or `common-auth`. If you see this, please open
an issue with your `/etc/pam.d/sddm` - the `success=N` line is the only
thing this project ever changes there, and it structurally cannot affect
the password branch (it falls through unchanged on `default=ignore`).

**QR code looks blurry but still scans** - cosmetic; the QML `Image`
element must have `smooth: false` (already set in the shipped patch) to
avoid bilinear upscaling of the small PNG.
