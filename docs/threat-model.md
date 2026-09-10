# Threat model

## Assets

- Desktop login (the ability to reach an authenticated Plasma session).
- Authelia OIDC tokens exchanged during the device flow.
- The optional KWallet password, once systemd-creds encrypted at rest.
- The approval marker files (login-decision and KWallet hand-off).
- The identity of the local user account being logged into (local or,
  since v0.5.0, NSS/LDAP-resolved).
- FIDO2 credential public-key material in `fido2_mappings` (not a
  secret by itself - see `docs/fido2.md` - but its integrity matters:
  it determines which physical key can authenticate which user).

## Threats and mitigations

| Threat | Mitigation |
|---|---|
| Marker replay (reuse an already-consumed approval) | Atomic rename-then-check consumption in both PAM and `kwallet-secretd`; marker is gone the instant it is read, valid or not. |
| Marker for the wrong user grants a different user's login | Marker filename is derived from the requested username and re-checked; a marker for user A is never even attempted to be consumed when authenticating user B. Broker also independently verifies the `authelia.pam.username` claim matches the username the flow was started for. |
| Path traversal / injection via username | Both broker (`sanitizeUsername`) and PAM module (`getpwnam_r` + charset checks) reject anything outside `[A-Za-z0-9_-]`, and never build a shell command from a username - no `system()`/`popen()`/`eval` anywhere in this codebase. |
| Symlink race on marker files | Markers are created directly in a root-owned, non-world-writable directory (`/run/sddm-authelia-passkey`, mode 0755 but individual marker files 0600, written by root only); consumption uses `rename()` (atomic, fails if the source is not a regular file the caller expects) rather than open-then-trust. |
| Local unprivileged attacker connecting to the KWallet secret socket | Socket is `0600` root-owned (filesystem permission alone blocks any non-root connect attempt, verified in `tests/`) and additionally checks `SO_PEERCRED` for uid 0 as defense in depth. |
| Malicious local service impersonating the broker/secretd | Both bind fixed, root-owned paths (`127.0.0.1:7899` for the broker's own localhost-only HTTP API, and a root-owned `AF_UNIX` socket for `kwallet-secretd`); an unprivileged process cannot bind to an already-listening port, and cannot replace a root-owned socket path without root anyway. |
| Secret leakage via logs/env/argv/core dumps | See `docs/security.md` - `PR_SET_DUMPABLE=0`, explicit zeroing, never logged, never in argv/env. |
| Stolen KWallet credential blob | Verified `0600` root:root; still only as strong as the systemd-creds key mode chosen (`host` vs `host+tpm2` - see `docs/kwallet.md`). Documented, not hidden. |
| Compromised root on the local host | Out of scope for the smartphone-login/marker mechanism itself - a compromised root can always impersonate any local service. For KWallet auto-unlock specifically, `host+tpm2` binding at least requires the correct TPM2 PCR state, not just filesystem read access; `host`-only binding does not add protection against this specific threat (documented, not overstated). |
| Authelia outage / unreachable | Broker fails the specific `/start` request; password login is completely unaffected (different PAM branch, no marker ever gets written). |
| Rate limit abuse (hammering the device-authorization endpoint) | Broker's own per-user cooldown, global concurrency cap, and failure lockout (see `config/examples/config.conf.example`); Authelia's own rate limiter is a second, independent layer this project does not attempt to bypass or loosen. |
| Broker compromise (RCE in the broker process) | Broker runs as root today (needed to write root-owned markers) under a hardened systemd unit (`NoNewPrivileges`, `ProtectSystem=strict`, capability bounding set emptied, syscall filtering, etc. - see `systemd/*.service`); this is a real, accepted risk surface for a service that must produce root-owned files, documented rather than hidden. |
| Fake QR / phishing (attacker shows their own QR to a victim) | The QR encodes `verification_uri_complete` returned by Authelia itself for a flow *this broker* started for the specific username entered on this machine; an attacker would need to inject a flow into the broker's own `/start` response to substitute their own QR, which requires already controlling the local broker process (see "broker compromise" above) - this is not a remotely exploitable phishing vector by itself. |
| Stale/abandoned approval never consumed | Broker's `cleanupStaleFlows()` drops finished/aged flow state; the marker file itself also naturally becomes TTL-expired and is rejected even if somehow left on disk. |
| Concurrent login attempts for the same/different users | Per-user cooldown plus a global concurrency cap bound the number of simultaneously in-flight device flows; each flow has its own session ID and marker. |
| `account_source=nss`: LDAP/AD account with a stale or forged group membership | This project never talks to LDAP/AD directly and never caches membership itself - it calls the same NSS `getgrouplist()`/`getpwnam()` any other PAM-aware program on the host would, at authorization time. Trusting that result to the same degree the rest of the system already does is the accepted boundary; a compromised NSS/SSSD backend is out of scope, same as a compromised Authelia instance. |
| `account_source=nss`: NSS or group-lookup backend unavailable (SSSD/LDAP down) | Fails closed - treated as "not authorized", never as an implicit grant (`TestAuthorizeAccount_NSSMode_UserLookupErrorFailsClosed`/`...GroupLookupErrorFailsClosed`). |
| Stolen/cloned FIDO2 hardware key | Out of scope for this project (a FIDO2 private key never leaving genuine hardware is `pam_u2f`/the authenticator's own guarantee); `fido2_require_user_verification=true` (the default) at least requires the correct PIN/biometric on top of physical possession. |
| FIDO2 credential enrolled for one user used to authenticate another | Structurally impossible - `pam_u2f` looks the authfile line up strictly by the username PAM itself is authenticating; enrollment/revocation scripts only ever touch the named user's own line (`tests/integration/fido2-authfile-test.sh`'s cross-user-isolation case). |
| `fido2_required_group` misconfigured to a group that doesn't exist | `enable-fido2.sh` refuses to proceed (`getent group` check) rather than silently accepting a typo that could either lock everyone out or accidentally match nobody. |
| `provider_kind=oidc` pointed at an unreachable or non-compliant provider | Fails closed at every dispatch point - device-authorization, token poll, and identity verification all return a hard error, never a fabricated success (`TestProviderDispatch_UnreachableProviderNeverApproves`, `TestOIDCDiscover_MissingDeviceAuthorizationEndpointRefused`). |
| `break-glass.sh`/`disable-pam.sh` misuse | Both require root (same trust level as everything else that edits `/etc/pam.d/sddm`), are idempotent, re-verify `common-auth`/sudo/sshd hashes unchanged after editing and roll back on any unexpected difference, and only ever neutralize/remove lines they can positively identify as this project's own. Neither is reachable from the broker's HTTP API or by an unprivileged local user. |
| `sddm-authelia-passkey-admin` CLI misuse | `test-config` needs no root but only ever reads `config.conf` (which holds no secrets - see `docs/security.md`) through the same `LoadConfig`/`Validate` path the broker itself uses; every other subcommand requires root and only reads state (systemd/PAM/journal), never writes. |

## Explicitly out of scope

- Compromise of the Authelia instance itself, or of the phone/authenticator.
- Compromise of an NSS/LDAP/AD/SSSD backend an `account_source=nss`
  deployment relies on, or of a `provider_kind=oidc` identity provider.
- Physical theft/cloning of a FIDO2 hardware key, or compromise of the
  authenticator's own CTAP2/U2F implementation.
- Physical access to an already-unlocked session.
- `sudo`, `sshd`, or `common-auth` - this project never touches them, and
  its installer refuses to run if it cannot verify that.
