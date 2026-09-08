Go convention keeps unit tests next to the code they test, not in a
separate directory:

- `src/broker/*_test.go`
- `src/kwallet-secretd/*_test.go`

Run via `go test ./...` in each of those directories, or see
`.github/workflows/test.yml` / `docs/testing.md`.
