# Failure, offline and recovery policy (v2.7.0)

An explicit, per-case decision for every failure scenario
`docs/roadmap.md`'s v2.7.0 milestone enumerates, tracing each decision
to the actual code that implements it (or explaining why a case
cannot occur, or does not affect the real login decision, in the
current architecture) rather than asserting it in the abstract. Per
the roadmap's own rule: no automatic *unsafe* fallback - every case is
either `FAIL_CLOSED` or an explicitly justified `SAFE_LOCAL_FALLBACK`.

## Device-flow protocol outcomes (`src/broker/main.go`'s `pollAndDecide`)

| Case | Decision | Where |
|---|---|---|
| `authorization_pending` | `SAFE_LOCAL_FALLBACK` (keep polling) - RFC 8628's own defined "not yet" signal, not a failure | `pollAndDecide`, `case "authorization_pending": continue` |
| `slow_down` | `SAFE_LOCAL_FALLBACK` (increase poll interval, keep polling) - RFC 8628's own defined backpressure signal | `pollAndDecide`, `case "slow_down"` |
| `access_denied` | `FAIL_CLOSED` (deny) | `pollAndDecide`, `case "access_denied"` |
| `expired_token` | `FAIL_CLOSED` (expired) | `pollAndDecide`, `case "expired_token"` |
| any other/unrecognized OAuth error code | `FAIL_CLOSED` (deny, logs the exact code) | `pollAndDecide`, `default:` |
| device flow timeout (deadline reached) | `FAIL_CLOSED` (expired) | `pollAndDecide`'s `deadline`/`remaining` checks |
| user cancellation | Not a failure - an explicit, safe, user-initiated stop | `pollAndDecide`'s `cancelled`/`cancelCh` checks, `handleCancel` |
| rate limiting (HTTP 429 from an intermediary) | `SAFE_LOCAL_FALLBACK` while it still fits the flow's remaining lifetime, else `FAIL_CLOSED` | `pollAndDecide`'s `outcomeRateLimit` branch, `rateLimitDecision` |
| ambiguous/malformed poll response | `SAFE_LOCAL_FALLBACK` for up to `maxConsecutiveAmbiguous` (8) consecutive occurrences, then `FAIL_CLOSED` (`temporarily_unavailable`) | `pollAndDecide`'s `outcomeAmbiguous` branch |
| successful token, but username mismatch | `FAIL_CLOSED` (deny) - the exact-match identity-binding invariant | `pollAndDecide`'s `outcomeOK` branch |

## Network-level failures (IdP offline, DNS failure, network timeout)

A genuinely unreachable/hung provider (DNS failure, connection refused,
or a connection accepted but never answered) surfaces as a Go `error`
from `providerDeviceAuthorize`/`providerPollToken` - indistinguishable
from each other at this layer, all `FAIL_CLOSED` the same way:

- At `/start` time: `deviceAuthorize`/`providerDeviceAuthorize` returns
  an error, and `handleStart` reports the flow as `"error"` immediately
  - `FAIL_CLOSED`, no retry loop is even entered.
- During an active flow: `pollToken`/`providerPollToken` returning an
  error is treated identically to `outcomeAmbiguous` (bounded retry,
  then `FAIL_CLOSED` as `temporarily_unavailable`).

**Real gap found and fixed in this milestone**: every one of these
calls previously used `http.DefaultClient`/the bare `http.Get`/
`http.PostForm` package functions, none of which have *any* timeout. A
provider that accepted a TCP connection but never wrote a response
would have hung the calling goroutine **forever** - meaning
`pollAndDecide`'s bounded-retry-then-fail-closed logic above could
never actually run, since `providerPollToken` would simply never
return. Fixed by routing every broker->provider HTTP call through a
single `providerHTTPClient` (`src/broker/provider.go`) with a 15-second
timeout - proven by `TestProviderHTTPClient_BoundsHungResponse`
(`src/broker/http_timeout_test.go`), which sets up a handler that never
responds and confirms the call still returns (with an error) well
within 2 seconds instead of hanging indefinitely.

## NSS/directory failures (SSSD offline, AD unavailable)

`authorizeAccount` (nss mode) calls `userLookup`/`groupIDsForUser`,
which resolve via the C library's ordinary NSS dispatch - if SSSD is
down, or the AD backend it depends on is unreachable, these calls
simply fail (glibc's NSS returns "no such user"/an error), and
`authorizeAccount` returns an error - `FAIL_CLOSED` by construction,
per the project's standing invariant ("Fails closed: any NSS lookup
error is treated as not authorized", `main.go`'s `authorizeAccount` doc
comment). `checkIdentityProvenance` (v2.2.0) is equally fail-closed on
an NSS-service-scoped lookup error.

**Real-tested on VM124** (a genuinely more precise finding than "just
stop the daemon"): stopping `sssd.service` alone was **not** sufficient
to observe a real failure - `libnss_sss`'s on-disk cache
(`/var/lib/sss/db/*.ldb`) continued serving previously-resolved
entries even with the daemon down, a deliberate SSSD resilience
feature for exactly this kind of outage. Only after also force-
expiring the cache (`sss_cache -E`) did `getent -s sss passwd julia`
genuinely fail (exit 2), and at that point `/start` for that account
was correctly refused: `NSS lookup failed: user: lookup username
julia: connection refused` - `FAIL_CLOSED`, no silent fallback beyond
the cache SSSD itself already provides. Restarting `sssd.service`
recovered real AD account resolution (`benlue`/`julia`/`sam`) cleanly.
This means real deployments get an *additional*, valuable
`SAFE_LOCAL_FALLBACK` layer for free (SSSD's own cache bridges brief
backend outages) before ever reaching this broker's own fail-closed
NSS-error handling - worth calling out explicitly since it was not
previously documented anywhere in this project.

**A second, separate real test** blocked outbound LDAPS (port 636) to
the actual Samba AD DC's real addresses from VM124 only (local,
reversible `iptables`/`ip6tables` `OUTPUT` rules - the shared DC itself
was never touched), with `sssd.service` left running this time (unlike
the test above). Observed timing was **not fully deterministic from
this project's outside view**: one lookup (`julia`, immediately after
`sss_cache -E`) took a real ~12 seconds (consistent with an LDAP
connection attempt genuinely timing out) before still succeeding from
cache; a subsequent lookup (`sam`) succeeded in ~0.2 seconds. This is
SSSD's own internal caching/refresh behavior, not something this
project controls or fully re-derives - but it surfaces a real,
honestly-documented open item: **`userLookup` (the broker's NSS call)
has no timeout of its own** (unlike the v2.7.0 HTTP-client fix above),
so a request landing during a slow SSSD-internal backend timeout would
block that request's goroutine for the same variable duration. Not
fixed in this milestone (a glibc NSS/cgo call cannot be bounded the
same way an `http.Client.Timeout` can); tracked as an open item rather
than silently left undocumented. Both firewall rules were removed
afterward and real AD account resolution
(`benlue`/`julia`/`sam`) confirmed recovered.

## Broker restart during an active flow

`flows` (the in-memory session-state map) is lost on any broker
restart - `FAIL_CLOSED` by construction, not a special case needing its
own logic: PAM's own approval marker is what actually grants a login
(never the broker's in-memory state directly, see
`docs/architecture.md`'s "PAM control flow"), and a marker is only ever
written on a genuinely completed, verified `outcomeOK` outcome. A
broker restart mid-flow means no marker gets written for that attempt,
so PAM's own `approval_ttl_seconds` window simply expires with nothing
to consume - the same as any other never-approved attempt.

**Real-tested on VM124**: started a real device-authorization flow,
restarted `sddm-authelia-passkey-broker.service` mid-flow (before
approval), and confirmed no approval marker was ever written and the
interrupted session could not be resumed - a fresh `/start` was
required, exactly as an admin would expect, with no silent success and
no hang.

## Capability loss during an active flow

Not applicable by design: v2.4.0's `/capabilities`
(`fido2_wired`/`oidc_ready`) are purely informational UI hints (see
`docs/capability-negotiation.md`) and never gate any flow-control or
security decision. Losing a capability mid-flow has zero effect on
that flow, because nothing in the flow's own logic ever depended on
it.

## Cases that do not apply to this broker's current architecture

- **Expired discovery cache**: `oidcDiscover()` caches a successfully
  fetched discovery document for the lifetime of the broker process,
  with no TTL/expiry concept at all - there is no "expired cache" state
  this architecture can reach. If a provider's endpoints genuinely
  change, the broker requires a restart to pick up the new document -
  an accepted, documented limitation, not a runtime failure mode.
- **Expired signing key**: this broker never validates ID token
  signatures itself - identity is established via the provider's
  userinfo endpoint (`verifyUserinfo`/`genericOIDCVerifyIdentity`), not
  local JWT/JWKS verification (`docs/provider-conformance.md`'s `JWKS`
  check is reachability/shape only). A provider's signing-key rotation
  or expiry therefore has no effect on this broker's actual
  authentication decisions today. This would become a real
  consideration only if a future milestone adds local ID-token
  signature validation (tracked as the still-open `TOKEN_VALIDATION`
  item in the private roadmap's v2.6.0 section).

## Closure

```text
FAILURE_MODEL=GREEN (every enumerated case has an explicit, traced decision)
OFFLINE_POLICY=GREEN (broker->provider HTTP calls now genuinely bounded - see the http-timeout fix; NSS/SSSD calls remain unbounded at the broker level - an honestly-documented open item, not a silent gap, see above)
RECOVERY_POLICY=GREEN (SSSD-offline, AD-network-unreachable, and broker-restart-mid-flow all real-tested on VM124; all recover cleanly once the underlying condition is removed)
```
