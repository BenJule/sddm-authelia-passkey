# Support

Thanks for using `sddm-authelia-passkey`.

## Start with documentation

Please check the relevant documentation first:

- [Installation](../docs/installation.md)
- [Configuration](../docs/configuration.md)
- [Validated environment](../docs/validated-environment.md)
- [Rollback and recovery](../docs/rollback.md)
- [Architecture](../docs/architecture.md)
- [Security](../docs/security.md)

The project is intentionally conservative around PAM. Unsupported or unrecognised login-stack layouts are refused rather than modified speculatively.

## Questions and installation help

Use the repository's **Discussions → Q&A** category for configuration questions, installation guidance and design discussions that are not confirmed bugs. Include relevant versions and deployment mode, but remove credentials and private infrastructure details.

## Bugs

Use the bug report template and include:

- exact OS, SDDM, KDE/desktop and provider versions;
- whether the issue affects password login, passkey login, theme UX or packaging;
- output from the read-only preflight/admin status commands where relevant;
- the smallest reproducible configuration with sensitive values removed.

Do not post access tokens, client secrets, private keys, KWallet credentials or other sensitive material.

## Feature ideas

Early ideas belong in **Discussions → Ideas**. Once the scope is concrete, use the feature-request issue form and explain the user problem, expected behaviour and any authentication or identity-boundary impact.

## Security vulnerabilities

Do **not** open a public issue. Report vulnerabilities through the private process described in [SECURITY.md](../SECURITY.md).

## Community standards

Repository participation is covered by [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md).

## Scope

The current validated reference environment is Debian 13 (Trixie), SDDM 0.21.x, KDE Plasma 6, Authelia 4.39+ and systemd 257+. Other environments may be unsupported or experimental unless explicitly documented.
