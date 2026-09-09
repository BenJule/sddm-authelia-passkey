# Security test checklist

Most of these are already exercised as assertions inside the unit tests
in `src/broker/*_test.go` and `src/kwallet-secretd/*_test.go` (marker
single-use/replay/expired/wrong-user, username sanitization) and the
integration test in `tests/integration/pam-flow-test.sh` (socket
permission enforcement, login/wallet-unlock decoupling). This file is
the explicit checklist a security reviewer should walk through
independently of trusting that the tests above are correct:

- [ ] `/run/sddm-authelia-passkey/approved-*` and `kwallet-ready-*`
      marker files are created `0600`, never group/world-readable.
- [ ] `/run/sddm-authelia-passkey/kwallet-secret.sock` is `0600`
      root:root; connecting as a non-root user fails at the filesystem
      permission layer (`PermissionError` / `EACCES`), before any
      application-level check even runs.
- [ ] A marker for user A is never consumed while authenticating user B
      (verified: `TestConsumeApproval_WrongUserMarkerNotConsumed` /
      `TestConsumeHandoff_WrongUserMarkerNotConsumed`, and the file is
      confirmed still present afterward, not just "denied").
- [ ] `pam_authelia_passkey.so` never calls `system()`, `popen()`, or any
      shell (`grep -n 'system(\|popen(' src/pam/*.c` should return
      nothing).
- [ ] No secret value ever appears in `journalctl` output for
      `sddm-authelia-passkey-broker` or
      `sddm-authelia-passkey-kwallet-secretd`, in `/proc/<pid>/environ`
      for either service, or in `ps` output for any process this project
      starts.
- [ ] `scripts/enable-pam.sh` refuses (does not guess) when
      `common-auth` does not end in the standard pam-auth-update
      failsafe pair.
- [ ] A `kwallet-secretd` outage or missing credential never prevents a
      valid smartphone/passkey login from succeeding (verified in
      `tests/integration/pam-flow-test.sh`'s last case).
