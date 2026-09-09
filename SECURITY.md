# Security policy

## Supported versions

This project is currently pre-1.0 and experimental. Only the latest
tagged release receives security fixes until a stable release line is
established.

## Reporting a vulnerability

Please do **not** open a public GitHub issue for a suspected security
vulnerability. Instead use GitHub's private vulnerability reporting
(Security tab -> "Report a vulnerability") on this repository, or open a
draft security advisory. Include:

- The affected component (`src/pam`, `src/broker`, `src/kwallet-secretd`,
  the theme integration, or an installer script).
- Steps to reproduce, and the impact you believe it has.
- Whether you believe it affects the password-login fallback path (that
  path structurally never depending on this project's own code is a
  core design invariant - see `docs/architecture.md` - so a report that
  it does is treated as maximum severity).

We aim to acknowledge reports within a reasonable time and will credit
reporters (unless you ask not to be) once a fix ships.

## Scope

In scope: this repository's own code and scripts. Out of scope: Authelia
itself, WebAuthn authenticators, KDE/SDDM/systemd upstream code this
project patches or depends on but does not author - please report those
upstream instead.
