# Development

## Build

```
cd src/broker && go build ./... && go vet ./...
cd src/kwallet-secretd && go build ./... && go vet ./...
make -C src/pam
```

## Test

See `docs/testing.md`.

## Style / tooling

- Go: standard `gofmt`/`go vet`; no linter config beyond that yet.
- Shell: `shellcheck -S warning scripts/*.sh tests/**/*.sh` must be clean
  at warning level or above (a few `SC2015` "A && B || C" info-level
  notes are accepted where B can never itself fail - simple `echo`
  wrappers - rather than rewritten into `if/then/else` purely to satisfy
  the linter).
- C: must build clean with `-Wall -Wextra -Werror
  -fstack-protector-strong -D_FORTIFY_SOURCE=2`, and link with
  `-Wl,-z,relro,-z,now` (verified by `make -C src/pam
  verify-hardening`).

## Pull requests

- Explain the *why*, not just the *what*.
- Any change touching `src/pam` or the PAM control-flow design in
  `scripts/enable-pam.sh` needs the reasoning re-checked against
  `docs/architecture.md`'s "PAM control flow" section - this is the part
  of the project where a subtle mistake has the highest blast radius.
- New behavior needs a test (unit, integration, or both) in the matching
  `tests/` subdirectory.
