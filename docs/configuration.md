# Configuration

File: `/etc/sddm-authelia-passkey/config.conf` (root:root, `0644` - no
secrets live here). See `config/examples/config.conf.example` for the
full, commented reference; every key is documented there.

Deliberately a simple `KEY=VALUE` format, not TOML/YAML: both the Go
broker/secretd and the C PAM module parse the exact same file without
either needing a third-party parsing library, and without risking the
two parsers disagreeing on some YAML/TOML edge case.

## Validation

`LoadConfig` (`src/broker/config.go`) fails closed - a missing or invalid
required field refuses to start the broker rather than run with an
ambiguous or insecure configuration:

- `authelia_base_url` must be `https://` unless
  `authelia_dev_insecure_http=true` (development only).
- `account_source=local` (default): `allowed_users` must list at least
  one account, must not include `root` (refused outright, redundant with
  the PAM stack's own `user != root` line - see `docs/architecture.md`),
  and every listed account is verified to exist via a real NSS lookup
  (`os/user.Lookup`) at broker startup - not just trusted from the
  config file text.
- `account_source=nss`: `minimum_uid` must be positive, and
  `require_group_match=true` requires at least one `allowed_groups`
  entry - an empty `allowed_groups` with the switch left on is refused
  rather than silently treated as "no group check".
- Any other `account_source` value is refused outright.
- All timing/limit values must be positive.

## `account_source=nss`: LDAP/Active Directory accounts

See `docs/architecture.md`'s "LDAP/Active Directory accounts (NSS)"
section for the full design. In short: set `account_source=nss`,
`minimum_uid`, optionally `allowed_groups`/`require_group_match`, and
optionally `deny_users`; `allowed_users` becomes optional (an additional
restriction if set, no restriction beyond the other checks if left
empty). This project never talks to LDAP/AD/SSSD directly and never
implements its own directory credential cache - it only calls the same
NSS APIs (`getpwnam`, `getgrouplist`) any other PAM-integrated program
would, so whatever your host's `/etc/nsswitch.conf`+SSSD/nss-ldap already
resolves (Samba AD, OpenLDAP, FreeIPA, or plain local accounts) is what
this broker sees - nothing more, nothing less, and it fails closed if
that lookup errors or SSSD is unavailable.

## Migrating an existing `local`-mode install to `nss`

No forced migration - `account_source` defaults to `local`, and an
existing config with no `account_source` line behaves exactly as before
after upgrading. To opt in:

1. Confirm the accounts you want are actually NSS-resolvable on this
   host: `getent passwd someuser` and `getent group somegroup` (if using
   `allowed_groups`) must succeed *before* touching this config - this
   project cannot fix a broken/missing SSSD setup, it only consumes NSS.
2. Set `account_source=nss`, `minimum_uid` (1000 is the common Debian
   convention for "real" accounts), and optionally `allowed_groups`/
   `require_group_match`/`deny_users`.
3. `allowed_users` can be left empty (any account passing the above
   checks is eligible) or kept as a further restriction.
4. Restart the broker and check its log line for
   `account_source=nss, minimum_uid=..., allowed_groups=...` confirming
   the new mode is active.

## Changing `allowed_users`/`account_source`/etc.

Restart the broker after editing (`systemctl restart
sddm-authelia-passkey-broker.service`) - it re-validates on every start,
so a typo'd username or invalid config is caught immediately rather than
silently ignored.
