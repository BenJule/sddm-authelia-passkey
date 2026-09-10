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
- [ ] A marker's embedded `UID=` must match a *fresh* NSS lookup of the
      account at consumption time - an account deleted and recreated
      (same username, different UID) between approval and consumption
      is rejected, not silently trusted (verified:
      `pam-multiuser-test.sh`'s "wrong UID embedded" case).
- [ ] `kwallet-secretd` never releases one user's credential for a
      request naming a different user, and never releases a credential
      when the hand-off marker's `UID=` doesn't match the requested UID
      (verified: `TestConsumeHandoff_WrongUIDRejected`, and manually via
      the real protocol in lab testing - see docs/validated-environment.md).
- [ ] `allowed_users` may safely contain more than one entry with
      `kwallet_auto_unlock=true` - each user's credential is a separate
      file (`kwallet.secret.<user>`), never one shared secret.
- [ ] Parallel flows for two different users (alice, bob) never
      interfere: alice's `/cancel`, supersede, rate limit, or failure
      lockout never affects bob's independent flow (verified:
      `TestHandleStart_AliceAndBobFlowsAreIndependent`,
      `TestSupersedePriorFlow_NewAliceFlowDoesNotSupersedeBobFlow`,
      `TestHandleCancel_CancellingAliceSessionLeavesBobActive`).
- [ ] `account_source=nss`: root is rejected by both UID `0` and literal
      name `root`, independent of `deny_users` config (verified:
      `TestAuthorizeAccount_NSSMode_RootByNameRejected`,
      `TestAuthorizeAccount_NSSMode_UIDZeroAliasRejectedEvenIfNotNamedRoot`).
- [ ] `account_source=nss`: an NSS lookup error or a group-membership
      lookup error (SSSD/LDAP unavailable) fails closed, never treated
      as authorized or as a group match (verified:
      `TestAuthorizeAccount_NSSMode_UserLookupErrorFailsClosed`,
      `TestAuthorizeAccount_NSSMode_GroupLookupErrorFailsClosed`).
- [ ] `account_source=nss`: an account below `minimum_uid`, in
      `deny_users`, or in none of `allowed_groups` is rejected even with
      an otherwise valid NSS resolution (verified:
      `TestAuthorizeAccount_NSSMode_BelowMinimumUIDRejected`,
      `TestAuthorizeAccount_NSSMode_DenyUsersRejected`,
      `TestAuthorizeAccount_NSSMode_MissingGroupRejected`).
- [ ] Identity binding, UID re-check at PAM consumption, and per-user
      isolation are all unaware of `account_source` - an NSS/LDAP
      account gets exactly the same cross-user/UID-reuse protections a
      local account does, since `authorizeAccount` is the only thing
      that changes; everything downstream is untouched.
- [ ] FIDO2/U2F (`pam_u2f.so`) is looked up strictly by the username PAM
      itself is authenticating - a credential enrolled for one user can
      never authenticate a different one, and the enrollment/revocation
      scripts only ever touch the named user's own authfile line
      (verified: `tests/integration/fido2-authfile-test.sh`'s
      cross-user-isolation case).
- [ ] `setup-fido2-credential.sh` refuses to register root.
- [ ] `enable-fido2.sh`/`disable-fido2.sh` re-verify
      `common-auth`/sudo/sshd PAM hashes unchanged after editing,
      rolling back on any unexpected difference, and round-trip to a
      byte-identical `/etc/pam.d/sddm` (verified live on VM124).
- [ ] A missing FIDO2 device, unenrolled user, or failed touch/PIN/UV
      falls through to the smartphone/passkey path and then the
      password fallback - never a hard denial, never a silent
      authentication grant (verified: the full existing
      `tests/integration/pam-flow-test.sh` suite still passes unchanged
      with the FIDO2 line present but no credential enrolled, on VM124).
- [ ] `provider_kind=oidc` refuses to start/operate against a discovery
      document missing `device_authorization_endpoint`/`token_endpoint`/
      `userinfo_endpoint` rather than guessing a conventional path
      (verified: `TestOIDCDiscover_MissingDeviceAuthorizationEndpointRefused`).
- [ ] `provider_kind=authelia` (the default) dispatches to the exact
      same, completely unmodified `deviceAuthorize`/`pollToken`/
      `verifyUserinfo` functions as every prior release - the generic
      OIDC path is additive, never a modification of the existing
      Authelia call path (verified:
      `TestProviderDispatch_DefaultIsAuthelia`, and all pre-existing
      Authelia-path tests continuing to pass unchanged).
- [ ] The QML theme contains no provider-specific logic - it only ever
      talks to the broker's own `127.0.0.1:7899` API, unaware of
      `provider_kind` by construction (no QML change was made or needed
      for this feature).
- [ ] An unreachable `provider_kind=oidc` provider (not merely a
      misconfigured one) produces a hard error at every dispatch point
      (device-authorization, token poll, identity verification), never a
      fabricated success (verified:
      `TestProviderDispatch_UnreachableProviderNeverApproves`) - the
      failover-never-silently-grants invariant for the provider layer,
      complementing the existing marker-absence proof at the PAM layer
      (`tests/integration/pam-flow-test.sh`'s "no marker" case).
- [ ] `fido2_required_group`: a user not in the configured group never
      reaches `pam_u2f.so` at all (the `pam_succeed_if.so
      user notingroup` guard skips it via `[success=1]`); a user in the
      group is unaffected. `enable-fido2.sh` refuses to configure a group
      that doesn't exist rather than silently accepting a typo.
      `disable-fido2.sh` removes the guard line along with the rest of
      the block in both the gated and ungated shape, round-tripping to a
      byte-identical `/etc/pam.d/sddm` either way.
- [ ] `disable-pam.sh` refuses to run while `pam_u2f.so` is still
      integrated above `pam_authelia_passkey.so`, rather than removing
      the wrong line or leaving `pam_u2f.so` pointing at a shifted
      target.
- [ ] `break-glass.sh` only ever neutralizes lines it can positively
      identify (`pam_authelia_passkey.so`/`pam_u2f.so`), only ever
      comments them out (never deletes), and only ever restores lines
      carrying its own `# BREAK-GLASS-DISABLED: ` marker - a line an
      admin commented out for an unrelated reason is never touched by
      `--restore`.
- [ ] `sddm-authelia-passkey-admin test-config` never requires root and
      never starts the broker's listener - it only calls `LoadConfig`/
      `Validate` and exits.
- [ ] The broker's `SECURITY:`-tagged log lines (authorization denials,
      identity mismatches, successful approvals) never include a secret
      value (token, credential, marker content) - only usernames,
      session IDs, and policy-decision outcomes.
- [ ] `LoadConfig` refuses a `config.conf` containing any key not in
      `knownConfigKeys` (`src/broker/config.go`) - a typo'd key name
      (e.g. `alowed_groups=`) is refused at startup, never silently
      left at its default while the admin believes it took effect
      (verified: `TestLoadConfig_RejectsUnknownKey`). The four
      shell-only `fido2_*` keys the broker itself never reads are
      explicitly included in the allowlist so they are never
      mistakenly rejected (verified:
      `TestLoadConfig_AcceptsShellOnlyFido2Keys`).
- [ ] The shipped `config/examples/config.conf.example` itself always
      loads and validates cleanly (verified:
      `TestLoadConfig_ShippedExampleFileLoadsAndValidates`) - it cannot
      silently drift out of sync with what the broker actually accepts.
- [ ] `GET /identity` uses the exact same `authorizeAccount()` check as
      `/start` and returns an identical, reason-free 403 for both an
      unknown username and a known-but-not-allowlisted one (verified:
      `TestHandleIdentity_UnauthorizedUser_Rejected`,
      `TestHandleIdentity_UnknownUser_RejectedWithoutEnumeration`) -
      no new enumeration surface.
- [ ] `display_name`/`account_source` in the `/identity` response come
      only from a fresh NSS/local lookup, never from an OIDC claim or
      any client-supplied value - the QML theme never derives displayed
      identity from `resolvedUsername` (the post-approval OIDC-claim
      binding used only for the exact-match security check).
