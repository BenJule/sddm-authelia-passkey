# Contributing

## Build

```
cd src/broker && go build ./...
cd src/kwallet-secretd && go build ./...
make -C src/pam
```

## Test

```
cd src/broker && go test ./...
cd src/kwallet-secretd && go test ./...
sudo tests/integration/pam-flow-test.sh <existing-local-test-username>
```

## Style

- Go: `gofmt`, `go vet` clean.
- Shell: `shellcheck -S warning` clean (see `docs/development.md` for the
  one accepted exception class).
- C: builds clean with `-Wall -Wextra -Werror
  -fstack-protector-strong -D_FORTIFY_SOURCE=2`, links with
  `-Wl,-z,relro,-z,now`.

## Pull requests

1. One logical change per PR.
2. New behavior needs a test.
3. Anything touching the PAM control-flow design
   (`src/pam`, `scripts/enable-pam.sh`) should reference
   `docs/architecture.md`'s "PAM control flow" section in the PR
   description and explain why the change preserves the invariant that a
   failed/absent approval always falls through to the unmodified
   password path.
4. Security-relevant changes should also update `docs/threat-model.md`
   if they add, remove, or change a trust boundary.

See `docs/development.md` for more detail.
