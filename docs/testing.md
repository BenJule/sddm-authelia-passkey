# Testing

## Unit tests (no root, no network, run in CI)

```
cd src/broker && go test ./... -v
cd src/kwallet-secretd && go test ./... -v
```

Covers: config validation, verification-URI/username sanitization,
per-user cooldown/global concurrency cap/failure lockout, marker
consumption (no-marker/valid/replay/expired/wrong-user), secret
wiping/trimming.

## Integration tests (root, local machine, no live Authelia needed)

```
sudo tests/integration/pam-flow-test.sh <existing-local-test-username>
```

Exercises the real compiled `pam_authelia_passkey.so` via `pamtester`
against an isolated PAM service (never touches `/etc/pam.d/sddm`):
no-marker, valid-marker, replay, expired, wrong-user, and
`kwallet-secretd` down (login must still succeed).

## What is intentionally not automated in CI

Anything requiring a live Authelia instance, a real WebAuthn
authenticator, or a real SDDM/Plasma session - these are exercised
manually against a lab VM before any release; see `docs/release-signing.md`
for the release process notes.

## Theme/QML validation (CI, best-effort)

`.github/workflows/theme.yml` applies the theme patch against the real
`sddm-theme-debian-breeze` package inside a Debian 13 container (a hard
gate - the patch must apply cleanly) and additionally runs `qmllint` on
the result. `qmllint` is run best-effort/non-blocking: the theme imports
several KDE-specific QML modules (`org.kde.plasma.components`,
`org.kde.kirigami`, `org.kde.breeze.components`, the private
`../breeze` relative import) that are not resolvable outside a full
Plasma install, so `qmllint` alone cannot fully type-check this file in
CI. Full headless SDDM/Plasma rendering is not attempted in CI for the
same reason; that level of validation only happens in the lab VM
acceptance run before a release (see `docs/release-signing.md`).

## Security-focused tests (`tests/security/`)

Filesystem-permission and race-condition checks: marker files must be
`0600`, the KWallet socket must reject non-root peers, and a marker for
one user must never be consumable by a request for a different user
(also covered by the broker/secretd unit tests above, restated here as
explicit security-review checklist items rather than duplicated as
separate test code).
