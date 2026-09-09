## Summary

## Why

## Testing
- [ ] `go test ./...` (broker + kwallet-secretd)
- [ ] `go vet ./...`
- [ ] `shellcheck -S warning scripts/*.sh tests/integration/*.sh`
- [ ] `make -C src/pam verify-hardening`
- [ ] Package build + lintian (if `debian/` or packaged files changed)
- [ ] Lab VM regression (password login + smartphone/passkey login) if
      `src/`, `theme/`, or PAM integration changed

## Security-relevant?
If this touches `src/pam`, `src/broker`, `src/kwallet-secretd`, or PAM
integration scripts, note which trust boundary (see `docs/security.md`,
`docs/threat-model.md`) it affects, if any.
