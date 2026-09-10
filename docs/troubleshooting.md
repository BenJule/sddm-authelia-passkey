# Troubleshooting

**`PAM_INSTALL=REFUSED` during install** - your `/etc/pam.d/common-auth`
doesn't end in the standard pam-auth-update `requisite pam_deny.so` /
`required pam_permit.so` failsafe pair, or the expected
`pam_succeed_if.so user != root quiet_success` insertion point wasn't
found in `/etc/pam.d/sddm`. Don't hand-patch blindly; open an issue with
your (sanitized) `/etc/pam.d/sddm` and `/etc/pam.d/common-auth`.

**Smartphone/passkey login shows "device flow failed: temporarily_unavailable" or
similar after several quick attempts** - almost always Authelia's own
rate limiter on `/api/oidc/token`, not a bug in this project. Wait a
minute and try once; avoid rapid repeated attempts, which can make the
backoff grow further.

**KWallet doesn't auto-unlock even with `kwallet_auto_unlock=true`** -
check `systemctl status sddm-authelia-passkey-kwallet-secretd`; if it
shows `243/CREDENTIALS` it means the encrypted credential file is
missing/corrupt - see `docs/kwallet.md` to (re)create it. This is a
fail-safe, not a crash: smartphone/passkey login itself is unaffected.

**Password login stopped auto-unlocking KWallet after installing this
project** - should not happen; this project never modifies
`pam_kwallet5`'s position or `common-auth`. If you see this, please open
an issue with your `/etc/pam.d/sddm` - the `success=N` line is the only
thing this project ever changes there, and it structurally cannot affect
the password branch (it falls through unchanged on `default=ignore`).

**QR code looks blurry but still scans** - cosmetic; the QML `Image`
element must have `smooth: false` (already set in the shipped patch) to
avoid bilinear upscaling of the small PNG.

**Broker refuses to start after editing config.conf** - run
`sudo /usr/sbin/sddm-authelia-passkey-admin test-config` first; it runs
the exact same `LoadConfig`/`Validate` logic the real broker uses,
without starting anything. `CONFIG_INVALID: unknown config key "..."`
almost always means a typo in a key name - compare against
`config/examples/config.conf.example`.

**A specific user isn't offered the smartphone/passkey path** - run
`sudo /usr/sbin/sddm-authelia-passkey-admin list-users` to see exactly
who is currently eligible under your `account_source`/`allowed_users`/
`minimum_uid`/`deny_users`/`allowed_groups` settings, and which accounts
have a FIDO2 credential enrolled.

**FIDO2 key doesn't work / isn't tried** - confirm `pam_u2f.so` is
actually integrated (`grep pam_u2f /etc/pam.d/sddm`), that the user has
an enrolled credential (`list-fido2-credentials.sh`), and - if you set
`fido2_required_group` - that the user is actually a member of that
group. A missing device, unenrolled user, or non-membership all fall
through to the smartphone/passkey path silently by design, not an
error - see `docs/fido2.md`.

**Something is broken and you need password-only login back
immediately** - `sudo /usr/share/sddm-authelia-passkey/break-glass.sh`
neutralizes this project's PAM lines without needing to locate any
backup; `... --restore` undoes it once you've fixed the underlying
issue. See `docs/rollback.md`.
