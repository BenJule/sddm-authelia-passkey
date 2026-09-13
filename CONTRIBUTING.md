# Contributing

Contributions are welcome. The project deliberately treats PAM, identity binding and recovery paths as security-sensitive, so changes should be small, testable and explicit about trust-boundary impact.

## Before opening code

- Use [GitHub Discussions](https://github.com/BenJule/sddm-authelia-passkey/discussions) for early design ideas and support questions.
- Search existing issues and the public [development project](https://github.com/users/BenJule/projects/2) before opening duplicate work.
- Confirm the target behaviour is inside the documented validated scope.
- Security vulnerabilities must follow [`SECURITY.md`](SECURITY.md), not a public issue or PR.

## Workflow

1. Open or reference an issue for the bug, feature or design change.
2. Create a focused branch from current `main`, for example `fix/short-description`, `feat/short-description` or `docs/short-description`.
3. Make one logical change and add or update tests where behaviour changes.
4. Open a pull request against `main` and complete the repository PR template.
5. Resolve CI failures and review comments.
6. Merge only after the required **CI Gate** is green. The repository uses squash-only merges and deletes merged branches automatically.

`main` is protected. Do not force-push it or rewrite repository history as part of ordinary development.

## Build

```bash
cd src/broker && go build ./...
cd src/kwallet-secretd && go build ./...
make -C src/pam
```

## Test

```bash
cd src/broker && go test ./...
cd src/kwallet-secretd && go test ./...
sudo tests/integration/pam-flow-test.sh <existing-local-test-username>
```

Theme changes should also run the Native Theme and visual-regression tests documented in `docs/testing.md` and `docs/visual-regression.md`.

## Style

- Go: `gofmt`, `go vet` clean.
- Shell: `shellcheck -S warning` clean. See `docs/development.md` for the accepted exception class.
- C: builds clean with `-Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2`, links with `-Wl,-z,relro,-z,now`.
- Documentation: keep operational commands copy-paste safe and distinguish validated behaviour from expected or experimental behaviour.

## Pull requests

1. Keep one logical change per PR.
2. New behaviour needs a test.
3. Anything touching the PAM control-flow design (`src/pam`, `scripts/enable-pam.sh`) should reference `docs/architecture.md`'s **PAM control flow** section and explain why the change preserves the invariant that a failed or absent approval always falls through to the normal password path.
4. Security-relevant changes should update `docs/threat-model.md` if they add, remove or change a trust boundary.
5. Provider or identity changes should keep authentication proof separate from authoritative Unix identity and update `docs/architecture.md` or `docs/identity-binding.md` when that model changes.
6. Packaging or release changes should preserve signed-artifact and verification guarantees described in `docs/release-signing.md`, `docs/supply-chain.md` and `docs/apt-repository.md`.
7. Do not include generated credentials, private keys, personal tokens or unrelated environment data in commits, logs or screenshots.

Repository automation applies area/risk labels, assigns the maintainer, attaches the active milestone and adds new issues/PRs to the public development project.

## Licensing of contributions

Contributions follow the licence of the files being modified. New project-owned files use the repository default MIT licence unless they belong to a subtree with an explicit file-level SPDX licence. See [`docs/licensing.md`](docs/licensing.md) and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Community standards

Participation is covered by [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## More detail

See `docs/development.md`, `docs/testing.md`, `docs/security.md` and `docs/validated-environment.md`.
