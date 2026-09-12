# Transaction-bound remote approval (v2.8.0)

A smartphone/eIdP approval must be bound to the exact local
authentication transaction that requested it - never "any login for
this username", and never usable by, or attributable to, a different
transaction. This document verifies each of the roadmap's 12 named
security requirements against the actual code, closes one real gap
found while doing so, and extends the approval marker's schema with
the explicit bound-context fields the roadmap names.

Per the roadmap's own explicit framing: **no cryptographic device
attestation is claimed or implied anywhere in this project.** Binding
is to locally-provable request/session context only - `flow_id`,
resolved identity, provider, and target - never a device identity
claim. That remains true after this milestone; TPM/device attestation
is out of scope until a later phase.

## A real gap found and fixed

`pollAndDecide` checked `fs.cancelled` before waiting for the next poll
interval, and again immediately after that wait completed - but **not**
after `providerPollToken` itself returned. `providerPollToken` is a
real network call (now bounded to 15 seconds by v2.7.0's
`providerHTTPClient`, but a genuine window regardless). If a supersede
(a new flow starting for the same username, e.g. `supersedePriorFlow`)
landed while a poll request was in flight, and that in-flight request
happened to return a genuine approval, the code would still call
`writeApprovalMarker` - **a superseded flow succeeding after all**,
violating the exact invariant this milestone exists to guarantee.

Reproduced with `TestPollAndDecide_SupersededDuringInFlightPoll_MustNotApprove`
(`src/broker/transaction_binding_test.go`): a token endpoint that holds
its response open, releases it only after `supersedePriorFlow` has
already run, and asserts the flow never reaches `"approved"`. This
failed before the fix (a marker-write was attempted and the `SECURITY:
... approved` line was logged) and passes after it. Fixed by
re-checking `fs.cancelled` immediately after `providerPollToken`
returns, before any other handling of that specific poll result -
deliberately including the `outcomeOK` case.

## Bound context: marker schema extension

The approval marker (`writeApprovalMarker`/`buildApprovalMarkerToken`
in `src/broker/main.go`) now includes, in addition to the existing
`VERSION`/`USERNAME`/`UID`/`NONCE`/`APPROVED_AT` fields:

- `SESSION_ID` - the broker's own flow/session identifier (the
  roadmap's `flow_id`/"single-use approval identifier").
- `IDENTITY_SOURCE` - `cfg.AccountSource` (`local`/`nss`).
- `PROVIDER` - `cfg.ProviderKind` (`authelia`/`oidc`).
- `HOSTNAME` - `os.Hostname()` (the roadmap's "local target label").
- `REQUESTED_ACTION` - always `desktop_login` (the only action this
  project performs; an explicit, named field rather than an implicit
  assumption).

**None of these new fields are validated by the PAM consumer** - the
security-critical invariants (single-use, TTL, UID re-binding, and now
the in-flight-supersede fix above) are already fully enforced without
them. They exist for audit/traceability completeness, matching the
roadmap's explicit bound-context list. `consume_login_approval`'s C
parser (`src/pam/pam_authelia_passkey.c`) reads only the named keys it
recognizes line-by-line, so this is unconditionally backward
compatible in both directions - verified directly: a marker written in
the old 5-line format is still accepted (this is the format
`tests/integration/pam-flow-test.sh`'s own fixture still uses), and a
marker written in the new, richer format parses identically for the
two keys PAM actually reads.

## The 12 security requirements, verified

| Requirement | Status | Evidence |
|---|---|---|
| User A can never approve User B | Already true | Marker path is per-username (`approved-<user>`); PAM only ever opens the marker for the username it is currently authenticating, reinforced by a fresh UID re-check. Proven by `tests/integration/pam-flow-test.sh`'s "marker for a different user does not grant this user" case. |
| Approval is single-use | Already true | `consume_login_approval` atomically `rename()`s the marker away before reading it; a second attempt's `rename()` fails (`ENOENT`). Proven by `pam-flow-test.sh`'s "marker single-use (replay)" case. |
| Approval is TTL-bound | Already true | `age = now - st.st_mtime`, rejected if `age > ttl_seconds`. Proven by `pam-flow-test.sh`'s "expired marker" case. |
| Approval is flow-bound | Now explicit | `SESSION_ID` embedded (see above); the actual security property (only one flow per username can ever reach `writeApprovalMarker`) was already enforced via `supersedePriorFlow` + the newly-fixed in-flight race. |
| Approval is session-/request-bound | Now explicit | Same `SESSION_ID` field; same underlying enforcement. |
| A superseded flow can never later succeed | **Fixed this milestone** | See "A real gap found and fixed" above. |
| A stale approval is rejected | Already true | Same TTL mechanism. |
| Replay is rejected | Already true | Same single-use mechanism. |
| Cancel isolates old responses | Already true | `handleCancel`/`markPendingFlowCancelled` set `fs.cancelled`, now checked at every point that matters including immediately after an in-flight poll. |
| Parallel flows are isolated from each other | Already true | Per-username flow/marker paths; proven by `multiuser_test.go`'s `TestSupersedePriorFlow_NewAliceFlowDoesNotSupersedeBobFlow`/`TestHandleCancel_CancellingAliceSessionLeavesBobActive`. |
| Visible target context never implies false device attestation | Already true | Checked: no UI copy or documentation anywhere in this project claims or implies device/hardware attestation (`docs/supply-chain.md`'s "attestation" reference is unrelated build-provenance terminology). |
| Audit contains IDs/outcome, never secrets | Already true | `SECURITY: session %s: approved for user %s` logs the session ID and username only - never a token, UID re-check result, or marker content. |

## Real validation

`tests/integration/pam-flow-test.sh` (no-marker/valid-marker/replay/
expiry/cross-user/kwallet-down/wrong-ownership cases) re-run on lab
VM124 against the unchanged `pam_authelia_passkey.so` - this milestone
only changed the broker (Go) side, so the compiled PAM module itself
did not need rebuilding. New Go tests
(`TestPollAndDecide_SupersededDuringInFlightPoll_MustNotApprove`,
`TestBuildApprovalMarkerToken_ContainsBoundContext`,
`TestBuildApprovalMarkerToken_DefaultsProviderToAuthelia`) added to
`src/broker/transaction_binding_test.go`.
