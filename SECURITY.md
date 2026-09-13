# Security policy

Security is a release gate for `sddm-authelia-passkey`, not an optional add-on. The project touches SDDM, PAM, identity resolution and local secret handling, so reports that could weaken the password fallback or authentication boundary are treated with the highest priority.

## Supported versions

Only the **latest stable tagged release** receives security fixes. Older release lines are not maintained in parallel. Before reporting a problem found on an older build, please confirm whether it is still reproducible on the latest release when that can be done safely.

| Version | Security support |
|---|---|
| Latest stable release | ✅ Supported |
| Older releases | ❌ Upgrade required |
| Unreleased development branches | Best effort; report against the affected commit |

## Reporting a vulnerability

Do **not** open a public GitHub issue for a suspected vulnerability.

Use GitHub's private vulnerability-reporting / Security Advisory flow for this repository. A useful report includes:

- affected component (`src/pam`, `src/broker`, `src/kwallet-secretd`, Native Theme, packaging or installer tooling);
- affected release or commit;
- reproduction steps and expected impact;
- whether the issue could affect the normal password-login fallback;
- sanitized logs or a minimal reproducer where appropriate.

Never include production credentials, access tokens, private keys or unrelated personal data.

## Priority areas

Reports are especially important when they involve:

- bypassing or confusing PAM authentication decisions;
- approval-marker replay, cross-user use or incorrect identity binding;
- provider-origin or OIDC trust validation;
- local privilege boundaries, file ownership or permissions;
- KWallet secret exposure;
- rollback or break-glass failure;
- a change that could make password fallback unavailable;
- release or dependency supply-chain integrity.

## Disclosure and fixes

The maintainer will validate the report, develop a fix on a private or otherwise controlled path when needed, run the normal regression/security gates, publish a patched release and coordinate public disclosure appropriate to the severity. Reporter credit is welcome unless anonymity is requested.

## Scope

In scope: this repository's own source, scripts, packaging and release automation.

Out of scope: vulnerabilities in Authelia, SDDM, KDE/Plasma, systemd, `pam_u2f`, authenticators or other upstream dependencies that are not caused by this repository. Those should be reported to the relevant upstream project, although integration bugs in how this project uses those components are in scope.

See [docs/security.md](docs/security.md), [docs/threat-model.md](docs/threat-model.md) and [docs/supply-chain.md](docs/supply-chain.md) for the implemented security model.
