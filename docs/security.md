# Security boundaries

## What the server proves, and what it does not

Authelia's WebAuthn ceremony proves **User Verification (UV)** occurred:
the authenticator asserts that *some* local check (PIN, fingerprint, face,
pattern - whatever that specific authenticator implements) gated the
signature. This project therefore reports and documents:

    WEBAUTHN_UV=YES

It never reports, and you should never describe this project as
providing:

    FINGERPRINT_CRYPTOGRAPHICALLY_PROVEN=YES

The server has no visibility into *which* local verification method an
authenticator used, only that its own policy for "user verification
required" was satisfied. If your phone's fingerprint sensor is
compromised or its UV check is otherwise bypassed at the OS/authenticator
level, this project cannot detect that - that trust is inherent to
WebAuthn itself, not something this project adds or removes.

## What is, and is not, a secret

- The smartphone/passkey login path itself has **no persistent secret** at
  rest - the private key never leaves the authenticator, and the
  short-lived approval marker is not a credential, just a "this exact
  device flow was approved, once, recently" fact.
- The optional KWallet auto-unlock path **does** introduce an at-rest
  secret: your KWallet password, systemd-creds encrypted
  (`--with-key=host`, or `--with-key=host+tpm2` if your hardware has a
  TPM2 - see `docs/kwallet.md`). `host` binding protects the credential
  file against being copied elsewhere and decrypted on another machine;
  it does **not** protect against an already-compromised root context on
  the same machine, which could always read `/var/lib/systemd/
  credential.secret` itself. This is a real, documented limitation, not
  an oversight - see `docs/threat-model.md`.

- The optional FIDO2/U2F path (`docs/fido2.md`) similarly has **no
  persistent secret** at rest: `fido2_mappings` holds only public-key
  material (key handle + public key + COSE type) `pamu2fcfg` produces -
  the authenticator's private key never leaves the hardware token, and
  its PIN/biometric data never reaches this project or the host at all.

## Never present, by design

- No secret ever appears in process argv (`ps` output), environment
  variables, log lines (journal or otherwise), or a temporary plaintext
  file.
- `pam_authelia_passkey.so` calls `PR_SET_DUMPABLE=0` and best-effort
  `mlock()`s the small stack buffer holding a fetched secret, explicitly
  zeroing it (`wipe()`) before returning, on every code path including
  errors.
- `kwallet-secretd` reads the credential fresh per request from
  `$CREDENTIALS_DIRECTORY` (systemd-managed tmpfs) rather than caching it
  for the service's lifetime, and zeroes its buffer immediately after
  writing the response.

## Privacy

- No biometric data of any kind is stored, transmitted to, or seen by
  any component of this project. It stays entirely on the authenticator
  and inside Authelia's own WebAuthn ceremony.
- The broker stores no passkeys/credentials itself - Authelia is the
  WebAuthn relying party and credential store.
- The approval marker contains a random token and a timestamp, nothing
  about the authentication method used; it is deleted on first read
  (successful or not) and additionally garbage-collected after
  `approval_ttl_seconds` if never read.
