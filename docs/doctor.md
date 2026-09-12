# Doctor: production-readiness diagnostics

`sddm-authelia-passkey-admin doctor` (alias: `diagnose`) is a read-only
diagnostic that answers one question: **is it currently safe to enable
the passwordless login path?** It never writes anything, never
restarts/enables/disables any service, and never touches PAM - it only
observes and reports.

It complements, rather than replaces, the two existing checks:

- `preflight.sh` runs **before** installation (is this host even a
  supported target).
- `postflight.sh` (`admin status`/`health`) checks the **currently
  installed stack** is up.
- `doctor` checks whether the **configured, running stack is actually
  safe to rely on in production** - reachability of the identity
  provider, NSS/SSSD state, and a systematic scan for the exact class
  of local/directory identity collision documented in
  `docs/identity-binding.md`.

## Usage

```
sudo sddm-authelia-passkey-admin doctor
sudo sddm-authelia-passkey-admin doctor --explain
sudo sddm-authelia-passkey-admin doctor --json
sudo sddm-authelia-passkey-admin diagnose   # alias for doctor
```

Plain output is `KEY=STATUS` lines; `--explain` adds a one-line reason
under any check that isn't `GREEN`; `--json` emits a single
machine-readable `{"KEY":"STATUS",...}` object. Exit code reflects only
the aggregate `LOGIN_ENABLEMENT` check (0 = GREEN, 1 = RED) - the
per-check lines let you see exactly which one is responsible.

## Checks

| Key | Meaning | `SKIP` condition |
|---|---|---|
| `SDDM` | `sddm.service` active and `display-manager.service` points at it | never |
| `PAM_CONFIG` | `/etc/pam.d/sddm` carries `pam_authelia_passkey.so` | PAM not yet integrated (not itself an error - password-only login still works) |
| `BROKER_CONFIG` | `config.conf` passes the broker's own `--check-config` validation | never |
| `BROKER` | broker service active and actually rejects a non-allowlisted user (403) | never |
| `OIDC_DISCOVERY` | Authelia `/api/health` returns 200, or (provider_kind=oidc) the discovery document advertises `device_authorization_endpoint` | no `config.conf` yet |
| `JWKS` | (provider_kind=oidc only) the discovery document's `jwks_uri` is reachable and returns a `keys` array | provider_kind=authelia |
| `NSS` | basic NSS `passwd` lookup works | account_source=local |
| `SSSD` | `sssd.service` active | account_source=local, or account_source=nss but neither `reject_local_shadowing` nor `required_identity_source` is set and sssd isn't running (a soft warning, not a hard requirement, unless one of those settings depends on it) |
| `IDENTITY_PROVENANCE` | config-level consistency for the v2.2.0 identity-provenance settings | account_source=local |
| `USER_COLLISIONS` | systematic scan of every local (`files`) account with UID ≥ 1000 against the `sss` NSS service, flagging any that resolve to a **different** UID from each source - the real-world class of gap `docs/identity-binding.md` documents, found proactively rather than by accident | account_source=local, or SSSD isn't active |
| `BREAK_GLASS` | the break-glass panic-button script is present and `/etc/pam.d/sddm` exists for it to act on | never |
| `LOGIN_ENABLEMENT` | aggregate: `GREEN` only if every check above that isn't `SKIP` is `GREEN` | - |

`USER_COLLISIONS` is deliberately proactive: it does not require you to
already suspect a specific username. Any local/directory pair with
disagreeing UIDs for the same name is reported, so a real
`reject_local_shadowing` gap can be caught before it is ever noticed by
a failed or (worse) wrongly-succeeding login.

No secrets are ever printed: only hostnames/URLs already present in
`config.conf` (which itself never contains secrets - see
`config/examples/config.conf.example`), NSS-visible usernames/UIDs, and
the broker's own already-secret-free `--check-config` error text.
