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
- `allowed_users` must list at least one account, must not include
  `root` (refused outright, redundant with the PAM stack's own `user !=
  root` line - see `docs/architecture.md`), and every listed account is
  verified to exist via a real NSS lookup (`os/user.Lookup`) at broker
  startup - not just trusted from the config file text.
- All timing/limit values must be positive.

## Changing `allowed_users`

Restart the broker after editing (`systemctl restart
sddm-authelia-passkey-broker.service`) - it re-validates on every start,
so a typo'd username is caught immediately rather than silently ignored.
