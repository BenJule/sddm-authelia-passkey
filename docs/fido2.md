# Optional: native FIDO2/U2F hardware security keys

Off by default (no `pam.d` change, nothing to install, until you opt in).
A YubiKey, Nitrokey, SoloKey, or any other CTAP2/U2F-compliant
authenticator can be registered as a fast, fully local login path -
touch the key instead of typing a password or waiting for the
smartphone/passkey device-authorization flow.

## What this project does and does not do

**This project never implements FIDO2/CTAP2/U2F itself.**
[`pam_u2f.so`](https://github.com/Yubico/pam-u2f) (Debian package
`libpam-u2f`) is the actual protocol implementation - mature, maintained
by Yubico, and already the standard way Linux systems do hardware-key PAM
authentication. This project only:

- wires `pam_u2f.so` additively into `/etc/pam.d/sddm`, using the exact
  same dynamic `[success=N default=ignore]` jump-skip pattern already
  used for `pam_authelia_passkey.so` (`scripts/enable-fido2.sh` /
  `scripts/disable-fido2.sh`), computed fresh from the live
  `common-auth`, never assumed;
- provides per-user enrollment/revocation/listing tooling
  (`scripts/setup-fido2-credential.sh`,
  `scripts/revoke-fido2-credential.sh`,
  `scripts/list-fido2-credentials.sh`) around `pam_u2f`'s own
  `pamu2fcfg` registration tool and its authfile.

## Install and enable

```
sudo apt install libpam-u2f
sudo /usr/share/sddm-authelia-passkey/enable-fido2.sh   # requires enable-pam.sh already done
sudo /usr/share/sddm-authelia-passkey/setup-fido2-credential.sh <username>
```

`setup-fido2-credential.sh` prompts you to touch the key, then appends
the new credential to `/etc/sddm-authelia-passkey/fido2_mappings`
(root:root, `0600`). Re-running it for the same user adds a *further*
credential - multiple keys per user are supported natively (e.g. a
primary key and a backup one), never overwriting existing ones.

## Revocation

```
sudo /usr/share/sddm-authelia-passkey/revoke-fido2-credential.sh <username>
```

Removes **all** of that user's credentials at once (the authfile format
does not support surgically removing a single credential among several
without risking corrupting another's data on a parsing mistake) - the
safe path is revoke-all, then re-enroll the ones still wanted.
`list-fido2-credentials.sh` shows which users have credentials and how
many, without printing key material.

## PAM stacking / where it fits

```
auth    requisite       pam_nologin.so
auth    required        pam_succeed_if.so user != root quiet_success
auth    [success=N+1 default=ignore]   pam_u2f.so authfile=... cue userverification=1
auth    [success=N default=ignore]     pam_authelia_passkey.so
@include common-auth
```

Tried first (fastest, fully local, no phone/network needed); on any
non-success (no key present, no credential enrolled for this user,
touch not confirmed) it falls through exactly as if this project's FIDO2
support were not installed - smartphone/passkey and password remain
unaffected fallbacks, in that order, exactly as before. `enable-fido2.sh`
refuses to run before `pam_authelia_passkey.so` is integrated, and both
scripts re-verify `common-auth`/sudo/sshd PAM hashes unchanged after
editing, rolling back on any unexpected difference - the same fail-closed
safety net every other PAM-editing script in this project uses.

## Config

```
fido2_authfile=/etc/sddm-authelia-passkey/fido2_mappings
fido2_require_user_verification=true
fido2_require_pin_verification=false
```

There is no separate `fido2_enabled` switch - whether FIDO2 is active is
solely determined by whether `enable-fido2.sh` has wired `pam_u2f.so`
into `/etc/pam.d/sddm` (`disable-fido2.sh` to turn it back off). The
three config values above are read by `enable-fido2.sh` at the moment it
writes that PAM line, and by the enrollment scripts to find the
authfile.

`fido2_require_user_verification=true` (the default) requires the
authenticator support FIDO2 user verification (PIN or biometric) at
authentication time - set to `false` if your device only supports plain
U2F presence ("touch") verification.

## Security model

- **Per-user, per-credential isolation**: `pam_u2f` looks up the
  authfile strictly by the username PAM itself is authenticating
  (`pam_get_user()`) - the same structural guarantee every other
  identity source in this project relies on. A credential registered for
  `alice` can never authenticate `bob`; the enrollment/revocation
  scripts only ever touch the named user's own line (see
  `tests/integration/fido2-authfile-test.sh`).
- **root is never eligible**: `setup-fido2-credential.sh` refuses to
  register a credential for `root`.
- **No credential caching by this project**: the authfile holds public
  key material only (a FIDO2 credential's public key and key handle are
  not secrets - the private key never leaves the hardware token). This
  project stores nothing more sensitive than that, and never touches the
  authenticator's PIN/biometric data, which stays entirely on-device.
- **Fail closed**: a missing/unreadable authfile, an unenrolled user, an
  absent device, or a failed touch/PIN/UV all result in `pam_u2f`
  returning non-success, which `[default=ignore]` correctly treats as
  "try the next path" - never as an implicit allow.

## Validated environment / limitations

Proven in this session: the PAM-stacking arithmetic, idempotent
enable/disable round-trip (byte-identical `/etc/pam.d/sddm` restoration),
and the full existing smartphone/passkey regression suite
(`tests/integration/pam-flow-test.sh`) still passing unchanged with the
FIDO2 line present but no credential enrolled - all on VM124, the real
compiled PAM stack. The authfile append/revoke/list logic
(`scripts/lib/fido2-authfile.sh`) is covered by a dedicated unit test
(`tests/integration/fido2-authfile-test.sh`) proving cross-user
isolation and multi-credential support.

**Not proven in this session**: an actual live authentication against a
physical FIDO2/U2F device (no hardware key was available in this
environment). The CTAP2/USB-HID protocol handling itself is
`pam_u2f`/`libfido2`'s own, separately-maintained and widely-deployed
implementation - this project's own testing scope is the additive
integration around it (stacking, enrollment tooling, isolation), not a
re-verification of Yubico's own protocol implementation.
