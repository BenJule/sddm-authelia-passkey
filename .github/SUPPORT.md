# Support

Thanks for using `sddm-authelia-passkey`.

## Before opening an issue

Please check the relevant documentation first:

- [Installation](../docs/installation.md)
- [Configuration](../docs/configuration.md)
- [Validated environment](../docs/validated-environment.md)
- [Rollback and recovery](../docs/rollback.md)
- [Architecture](../docs/architecture.md)
- [Security](../docs/security.md)

The project is intentionally conservative around PAM. Unsupported or unrecognised login-stack layouts are refused rather than modified speculatively.

## Bugs

Use the repository's bug report template and include:

- exact OS, SDDM, KDE/desktop and provider versions
- whether the issue affects password login, passkey login, theme UX or packaging
- output from the read-only preflight/admin status commands where relevant
- the smallest reproducible configuration with secrets removed

Do not post access tokens, client secrets, private keys, KWallet credentials or other sensitive material.

## Installation problems

Use the dedicated installation-problem issue template. If PAM was modified and login behaviour is unexpected, use the documented rollback path before further experimentation.

## Feature requests

Use the feature-request template and explain the user problem, expected behaviour and whether the proposal changes an authentication or identity trust boundary.

## Security vulnerabilities

Do **not** open a public issue. Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/BenJule/sddm-authelia-passkey/security/advisories/new) and follow [SECURITY.md](../SECURITY.md).

## Scope

The current validated reference environment is Debian 13 (Trixie), SDDM 0.21.x, KDE Plasma 6, Authelia 4.39+ and systemd 257+. Other environments may be unsupported or experimental unless explicitly documented.
