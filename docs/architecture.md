# Architecture

## Components

- **broker** (`src/broker`) - talks to Authelia's OIDC Device Authorization
  endpoints (RFC 8628), renders the QR code, and writes a root-owned,
  single-use, short-TTL approval marker file on success. Never talks to
  PAM. Its local HTTP API (127.0.0.1 only) is not the trust boundary -
  the marker file is.
- **pam_authelia_passkey.so** (`src/pam`) - a native PAM auth module and
  the sole consumer of that marker. On a valid marker it commits to
  `PAM_SUCCESS` unconditionally; optionally (if `kwallet_auto_unlock` is
  configured) it then makes a best-effort attempt to also unlock KWallet,
  which can never turn the already-decided login into a failure.
- **kwallet-secretd** (`src/kwallet-secretd`) - optional. Releases a
  KWallet-unlock secret to the PAM module over a root-only AF_UNIX
  socket, gated by a second, separate, even-shorter-TTL hand-off marker
  that only the PAM module can mint (see below for why).
- **theme patch** (`theme/`) - a diff for `sddm-theme-debian-breeze` adding
  a "Smartphone-Login" action button (alongside Sleep/Restart/Shut Down/
  Other) that opens a right-anchored sidebar with the QR code, matching the
  existing action row's style rather than a floating overlay.

## Why a separate broker process at all?

SDDM's PAM service name is hardcoded in its source
(`src/helper/backend/PamBackend.cpp`): `"sddm"` for a normal login,
`"sddm-greeter"` only for the greeter's own bootstrap session, or
`"sddm-autologin"` for OS-level autologin. It is never configurable from
a theme, `sddm.conf`, or environment variable, which rules out the
"separate PAM service per login method" pattern some other display
managers support. SDDM also only ever asks PAM for a single conversation
step (username + one secret) - see the open upstream issue
[sddm/sddm#2098](https://github.com/sddm/sddm/issues/2098) tracking
native multi-step/async PAM support, which as of this writing has no
linked PR.

Given that, the device-authorization flow (which involves polling over
tens of seconds while a human approves on their phone) cannot happen
inside SDDM's own PAM conversation at all. It has to happen out of band,
in a companion process, with PAM only ever asked a single yes/no question
at the end: "has a marker already been approved for this user?".

## PAM control flow

```mermaid
flowchart TD
    A[SDDM: user attempts login] --> B{pam_authelia_passkey.so}
    B -- "no/invalid/expired marker" --> C["falls through: normal common-auth (password)"]
    B -- "valid marker (consumed, single-use)" --> D["auth = SUCCESS<br/>(skip common-auth via success=N jump)"]
    D --> E{kwallet_auto_unlock enabled?}
    E -- no --> F[pam_kwallet5: no authtok, manual prompt later]
    E -- yes --> G[mint short-lived hand-off marker]
    G --> H["ask kwallet-secretd for secret<br/>(AF_UNIX, SO_PEERCRED)"]
    H -- "ok" --> I[PAM_AUTHTOK = secret]
    H -- "fail/timeout" --> F
    I --> J[pam_kwallet5: auto-unlocks]
    C --> K[pam_kwallet5: unlocks with typed password]
```

The `[success=N default=ignore]` extended PAM control syntax is what
makes this safe: `N` is the exact number of lines the local
`@include common-auth` expands to, computed fresh at install time (see
`scripts/enable-pam.sh`), never hardcoded. On success it skips exactly
those `N` lines - never past the following `pam_kwallet5` line - so a
a smartphone/passkey login still reaches `pam_kwallet5` just like a password login
does; on any non-success it changes nothing and password login proceeds
exactly as if this project were not installed.

## Full login flow

```mermaid
sequenceDiagram
    participant User
    participant Theme as SDDM Theme
    participant Broker
    participant Authelia
    participant PAM as pam_authelia_passkey.so
    participant KWallet as kwallet-secretd (optional)

    User->>Theme: click "Smartphone-Login"
    Note over Theme,Broker: username omitted; broker auto-resolves it<br/>when exactly one allowed_user is configured
    Theme->>Broker: POST /start
    Broker->>Authelia: POST /api/oidc/device-authorization
    Authelia-->>Broker: user_code, verification_uri_complete
    Broker-->>Theme: session_id
    Theme->>Theme: render QR from verification_uri_complete
    User->>Authelia: scan QR, WebAuthn/Passkey user verification
    Broker->>Authelia: poll POST /api/oidc/token
    Authelia-->>Broker: access_token (on approval)
    Broker->>Authelia: GET /api/oidc/userinfo (verify username claim)
    Broker->>Broker: write approval marker (root:root, 0600, TTL)
    Theme->>Theme: poll /status, sees "approved" + resolved username
    Note over Theme: idempotent: a stale/duplicate response for a<br/>session that's no longer current is ignored
    Theme->>PAM: sddm.login(resolvedUsername, "", sessionButton.currentIndex)
    PAM->>PAM: consume approval marker, verify TTL
    PAM-->>User: login succeeds
    opt kwallet_auto_unlock=true
        PAM->>KWallet: mint hand-off marker, GET secret (AF_UNIX)
        KWallet-->>PAM: secret (best-effort)
        PAM->>PAM: PAM_AUTHTOK = secret
    end
```

## Duplicate/overlapping flows

Only one flow per user is meant to be "live" at a time. If a new `/start`
arrives for a user who already has an unfinished flow (e.g. the panel was
reopened before the previous attempt finished), the broker marks the prior
flow `cancelled` so its poll loop exits and frees its concurrency slot on
its next iteration - without this, a few overlapping attempts could each
hold one of `max_parallel_flows`' limited slots until their natural 10-
minute deadline, eventually blocking every further login attempt. The
theme's explicit "Abbrechen"/panel-close path calls a dedicated `/cancel`
endpoint for the same reason, rather than relying only on this supersede-
on-next-start behavior. `pixelFlow.open()` in the theme is itself
idempotent - calling it while a flow is already in progress does not start
a second one.

## Identity Awareness (v1.1.0)

`GET /identity?username=X` is a read-only, pre-flow lookup: the theme
calls it as soon as a flow's `targetUsername` is captured (same moment
`/start` is called), so the panel can show *whose* account a flow is
(or would be) for without waiting on the device-authorization round
trip. It runs through the exact same `authorizeAccount()` check
`/start` uses - an unauthorized or unknown username gets the identical
403 with no distinguishing reason, so this endpoint reveals nothing
`/start` doesn't already. It never touches flow/session/rate-limit
state.

The response's `display_name` comes from a fresh NSS/local lookup's
GECOS field (falling back to the plain username if empty) and
`account_source` echoes the server's own `local`/`nss` policy setting -
both already-trusted, server-side-resolved values. This is deliberately
**not** where `resolvedUsername` (the OIDC-claim-derived identity
`pollAndDecide` binds against for the actual login decision) comes from
- an unauthenticated claim is never presented as a trustworthy "whose
account is this" answer, only ever checked against the already-bound
`targetUsername` after a real approval.

The theme resolves an avatar for the identity header the same way: by
matching `targetUsername` against SDDM's own `userModel` (the exact
model backing the main account list), never a second/independent
avatar source. An NSS-only account SDDM's own list doesn't enumerate
simply gets no avatar match - the panel falls back to a generic
identity icon rather than guessing.

## Smart QR UX (v1.2.0)

`flowState.ExpiresAt` (exposed as `expires_at` in `/status`) is the
provider's own RFC 8628 `expires_in` deadline, captured once at
`/start` time - a pure UX value the theme uses to render a live local
countdown and progress bar, recomputed client-side every second rather
than polling the broker just to animate one. It is never itself an
expiry *authority*: `pollAndDecide`'s own independently-computed
deadline (see "Upstream rate limiting" below) remains the only thing
that actually transitions a flow to `expired` - the two happen to track
the same underlying `expires_in` value, but the client-side countdown
reaching zero triggers nothing by itself, it just stops looking
accurate for the second or two until the next real `/status` poll
catches up.

QR codes are rendered at a fixed `qrPixelSize` (512px) with
`qrcode.High` error correction (25% redundancy budget) rather than the
library's small default size and `Medium` (15%) correction - a
higher-resolution source lets the QML `Image` (already `smooth: false`)
downscale to the panel's ~220-260px display size instead of upscaling a
small PNG, and the extra error-correction budget trades a slightly
denser code for materially better real-world scan success against a
phone camera's glare/angle/partial obstruction.

## Service/Connection UX (v1.3.0)

`pixelFlow.connectionState` is deliberately a separate property from
`pixelFlow.state` (flow *progress*: idle/starting/waiting/approved/...):
it answers "is the broker/upstream actually reachable right now", with
exactly six values - `ready`, `connecting`, `waiting`, `rate_limited`,
`offline`, `error` - each with fixed, generic German wording (a status
chip: colored dot + short label, never color alone) that never names a
hostname, HTTP status code, or OIDC/LDAP term. Those details exist only
in the broker's own log (`journalctl -u sddm-authelia-passkey-broker`,
or `SECURITY:`-tagged lines specifically via the admin CLI's
`audit-log`), never in the greeter.

`offline` is the one genuinely new failure mode this introduces
detection for: `xhr.status === 0` on either the initial `/start` POST
or an in-flight `/status` poll means a real network-level failure (no
HTTP response at all - e.g. the broker process isn't running), distinct
from any 4xx/5xx the broker itself returned. A transient offline poll
never tears the flow down by itself - `pixelPollTimer` just keeps
retrying on its normal interval, and a later successful poll clears the
indicator back to `waiting` automatically.

### A single open QR code is one device flow, not repeated login attempts

Authelia's own token-endpoint rate limiter (`internal/middlewares/rate_limiting.go`
as of 4.39.23) periodically returns HTTP 429 to the broker's normal
RFC 8628 polling - confirmed live against the project's real Authelia
instance, with observed `Retry-After` delays ranging from under a
minute up to roughly 55 minutes under this session's own repeated
testing traffic. This is expected, ordinary behavior for **one** open
device flow, not a consequence of a user attempting to log in multiple
times - `checkAndReserve`'s local per-user start-limiter (a completely
separate mechanism, gating `/start` itself) is the only thing that
actually represents repeated login *attempts*.

The broker's own classification of this was already correct before the
UI wording fix below: `rateLimitDecision` (see its doc comment) honors
`Retry-After`, backs off without busy-looping, and gives up cleanly if
the required wait would exceed the flow's own remaining lifetime -
`pollAndDecide` never counts a rate-limited, expired, or
otherwise-ambiguous/infrastructure outcome as an authentication
failure (`releaseNeutral` in every such case; only a genuine
`access_denied` or username mismatch sets `releaseAuthFailure`). What
was wrong was purely presentational: the QML theme labeled all of
this "Zu viele Anmeldeversuche" ("too many login attempts"), which is
backwards - it describes the *user's* behavior, not the *broker's*
polling being throttled. Fixed by:

- **Still pending, upstream momentarily throttling polls**
  (`resp.rate_limited` while `resp.status === "pending"`): reworded to
  "Der Anmeldedienst wartet derzeit mit weiteren Statusabfragen. Bitte
  kurz warten." - never "Zu viele Anmeldeversuche".
- **The flow can no longer succeed** - RFC 8628 `expired`, the
  rate-limit-give-up case (`errorFlow(fs, "rate_limited")` when the
  required wait exceeds the remaining flow lifetime), and
  `temporarily_unavailable` (too many ambiguous/infrastructure errors
  in a row) - all three now collapse to the exact same user-facing
  treatment as plain expiry: `state = "expired"`, "QR-Code
  abgelaufen." + the existing "Neuen Code anfordern" retry button. The
  broker's log keeps the precise distinct reason for diagnosis; the
  greeter doesn't need to distinguish them for the user, and showing
  three different phrasings for what is, from the user's perspective,
  the identical "this code doesn't work anymore, get a new one"
  outcome would only add confusion.

## Responsive Greeter (v1.4.0)

`root.pixelOverlayLayout` switches the Smartphone-Login panel between
exactly one of two layouts - never both, never a hybrid state - purely
a geometry change; `pixelFlow`'s own state machine is completely
unaware of which one is active:

- **Sidebar** (the default): right-anchored,
  `root.pixelSidebarWidth` (`Math.max(320, Math.min(420, root.width *
  0.24))`) wide, full height, slides in horizontally. `mainStack`'s
  `rightMargin` and the clock's centering both narrow to make room for
  it.
- **Overlay** (below the breakpoint): a centered, **size-capped** modal
  card - never full-screen - `Math.min(parent.width - 4*gridUnit,
  420)` wide and `Math.min(parent.height - 6*gridUnit, 620)` tall,
  rounded corners, sliding up from off-screen to vertically centered.
  A dedicated `pixelOverlayScrim` (a separate `Rectangle`, `z: 199`,
  just below the card's own `z: 200`) covers the full screen behind
  the card with a semi-transparent dim, and `loginScreenRoot.enabled`
  (the `MouseArea` wrapping the password field, user list and action
  row) is bound to `!(root.pixelOverlayLayout && pixelPanel.open)` -
  Qt Quick disabling an `Item` disables mouse, keyboard and focus for
  it and every child, so the greeter behind the overlay is dimmed
  *and* genuinely non-interactive/non-focusable, not just visually
  covered. The scrim's own `MouseArea` absorbs any remaining input but
  deliberately does not close the panel on click - only Escape or the
  Cancel button do, so a stray tap can't discard an in-progress flow.
  `mainStack`/clock are **not** narrowed or recentered in this layout,
  since the card floats on top rather than permanently shrinking the
  main area.

**Breakpoint**: derived, not a fixed constant -
`pixelOverlayLayout: width < (pixelSidebarWidth +
pixelMainAreaMinWidth)` (`pixelMainAreaMinWidth = 560`), i.e. the
overlay only activates once the sidebar and a usably-wide main login
column genuinely wouldn't fit side by side, rather than at an
arbitrary screen-size cutoff. `root.width`/`height` are QtQuick
logical units - already DPI-independent, since Qt divides out the
platform's device pixel ratio before these bindings see a number - so
this is correct unchanged across 100/125/150/200/250% scale factors,
with no separate HiDPI branch needed.

Both layouts share the exact same `pixelPanel.open` single-source-of-
truth, the same `Keys.onEscapePressed`/cancel button, and the same
inner `ColumnLayout` content (identity header, QR/countdown, alternate
code, connection-status chip) unchanged - only the outer
position/size/slide-axis/scrim differs.

**Multi-monitor**: SDDM already instantiates one independent QML scene
per screen (the existing `Repeater { model: screenModel }` driving the
wallpaper). Each screen's `Main.qml` instance has its own `root.width`,
so `pixelOverlayLayout` is evaluated independently per screen with no
additional code needed - a narrow secondary display gets the overlay
layout even if the primary display is wide enough for the sidebar, and
vice versa.

**HiDPI**: all of this project's own sizing is expressed in
`Kirigami.Units` (already DPI-aware) or plain numbers interpreted as
QML's own logical-pixel coordinate space, which Qt itself scales to
physical pixels via the platform's normal HiDPI handling - no
project-specific DPI detection was added or is needed.

**Long names/translations**: the identity header's display name and
username labels already `elide: Text.ElideRight` with
`maximumLineCount: 1` (v1.1.0); the "Verzeichniskonto" badge and
connection-status chip size to their own (short, fixed) text via
`implicitWidth`, so longer translated strings simply grow the badge
rather than clipping.

## Accessibility 2.0 (v1.5.0)

Every custom element this project adds to the panel now carries
explicit `Accessible` attached properties (`import QtQuick` already
provides these, no extra import needed) - see `docs/accessibility.md`
for the full list and rationale. Two deliberate patterns worth calling
out:

- **Role follows layout, not a fixed value**: `pixelPanel`'s
  `Accessible.role` is `Accessible.Dialog` in overlay layout (modal -
  the rest of the greeter is dimmed and disabled behind it, see
  "Responsive Greeter" above) and `Accessible.Pane` in sidebar layout
  (not modal - the rest of the greeter stays reachable). A screen
  reader should describe the actual interaction model, not a value
  that's only correct in one of the two layouts.
- **Decorative duplicates are ignored, not named**: the identity
  avatar image and the connection-status chip's color dot each sit
  right next to a text label saying the same thing. Giving them their
  own `Accessible.name` would double-announce the same information;
  `Accessible.ignored: true` is the correct fix, not a redundant name.

This is reviewed against the Qt Quick `Accessible` API and Qt Quick
Controls conventions, not verified against a running screen reader
(AT-SPI/Orca) - see `docs/accessibility.md`'s "What has not been
specifically verified" section.

## Error/Recovery UX (v1.6.0)

Every place `Main.qml` sets `pixelFlow.state` to `"error"` or
`"expired"` also sets `pixelFlow.errorKind` (a machine-readable cause,
never shown directly - `statusText` stays the free-form sentence) and
calls `armRetryCooldown(seconds)`, except the one case where no
request was ever sent (`errorKind: "no_account"` - selecting an
account first is the only thing that helps, so there's nothing to
debounce):

| `errorKind`        | Cause                                          | Cooldown |
|---------------------|------------------------------------------------|----------|
| `offline`            | `/start` unreachable (`xhr.status === 0`)      | 4s |
| `rate_limited`        | broker's own local per-user start-limiter (429) | 10s |
| `not_authorized`      | `/start` 403 - this account isn't eligible      | 3s |
| `start_failed`         | any other non-200 from `/start`                | 4s |
| `expired`               | RFC 8628 deadline / upstream give-up (collapsed, see "Flow outcome versus local failure lockout") | 2s |
| `denied`                 | `access_denied` or an unrecognized broker error | 4s |
| `handoff_failed`          | empty resolved username / invalid session index (should never happen) | 4s |

The cooldown (`pixelFlow.retryAvailableAt`/`retryCooldownRemaining`,
ticked by `pixelRetryCooldownTimer`) is a **UI courtesy debounce only**
- it disables the retry/new-code button for a few seconds so a stray
double-click or repeated mashing can't hammer the broker's `/start`
endpoint, and shows a countdown in the button's own label. It never
touches Authelia's real rate limiting (see "Upstream rate limiting"
below) and is not itself a security control - a modified/replacement
theme skipping it changes nothing about what the broker or Authelia
actually enforce.

`errorKind === "not_authorized"` additionally shows a small hint
pointing at the always-available password field (see
`docs/accessibility.md`'s "password path is always available"
guarantee) - retrying doesn't change whether this account is eligible
for Smartphone-Login, so the panel points at the path that's
guaranteed to still work instead of just repeating the same failure
sentence with nothing actionable.

## Upstream rate limiting

Authelia's own token-endpoint abuse limiter (`server.endpoints.rate_limits
.openid_connect_token`, on by default) sits in front of the OAuth2 handler
and can reject a poll with HTTP 429, independently of the device flow's own
`interval`/`slow_down` semantics - a burst of overlapping flows (several
real logins, or heavy manual testing) can trigger it purely through normal
RFC 8628 polling, with nobody actually retrying anything abusively. The
broker never weakens or reconfigures this limit; `pollToken` detects a 429,
reads `Retry-After` if present (bounded, RFC 7231 seconds-or-HTTP-date
form), and `pollAndDecide` treats it like a spec `slow_down` for backoff
purposes - except the resulting wait is also checked against the flow's own
remaining lifetime: if Authelia's `Retry-After` would land at or past the
flow's deadline, the flow fails closed (`rate_limited`) instead of quietly
running out the clock.

Critically, this is a UX/diagnostic concern, not an authentication
decision: `flowState.RateLimited`/`RetryAfterSeconds` are pure hints
surfaced over `/status` so the theme can distinguish "Authelia's limiter is
holding this poll" from "still waiting on the user" instead of showing an
indistinguishable "Warte auf Bestätigung…" for both. A rate-limited flow
can never be approved and never writes an approval marker - `fs.Status`
only ever becomes `"approved"` via the same `outcomeOK` branch as before,
which a rate-limited poll never reaches by construction (see
`rateLimitDecision`, `pollAndDecide` in `src/broker/main.go`).

## Multi-user readiness

`allowed_users` supports more than one entry, and the smartphone/passkey
flow is bound to whichever local account SDDM itself currently has
selected - `pixelFlow.sddmSelectedUsername` in the theme tracks the
avatar list's highlighted user (or the manually typed username when
that prompt is showing instead) via SDDM's own `userList`/`userNameInput`,
so there is no second, independent user database. See
`docs/validated-environment.md` for what has actually been exercised
end-to-end (still one real production/lab identity; multi-user proof
beyond that is via real local PAM test accounts and unit-level identity
mocks, not two real people - see `KNOWN_LIMITATIONS`).

**Identity binding.** Three distinct usernames are involved in a single
flow, and they must agree by the definition below - anything else is a
`DENY`, not a best-effort guess:

- `REQUESTED_LOCAL_USER` - the local account the flow was started for.
  Either the `username` query parameter on `/start` (validated against
  `allowed_users`), or, only when `allowed_users` has exactly one entry,
  that sole entry (a convenience fallback, not the long-term model - see
  below). Stored as `flowState.Username` for the lifetime of the flow,
  and independently re-derived by PAM via `pam_get_user()` (i.e. from
  SDDM's own login prompt) when a marker is consumed.
- `AUTHENTICATED_AUTHELIA_USER` - the `authelia.pam.username` claim from
  Authelia's `/api/oidc/userinfo` response for the access token the
  device flow produced (`verifyUserinfo` in `src/broker/main.go`).
- `BOUND_LOCAL_USER` - the mapping rule is **exact string match**:
  `pollAndDecide` refuses (`fail(fs, "username mismatch")`, logged at
  `SECURITY` level) unless `AUTHENTICATED_AUTHELIA_USER ==
  REQUESTED_LOCAL_USER`. No fuzzy/heuristic mapping exists or is
  planned; a future explicit static mapping table (Authelia username ->
  local username) is conceivable, but exact match is and remains the
  default.

**Per-user isolation, already true today:**

1. Rate limiting (`limiterFor`), the concurrency cap, and failure
   lockout are all keyed by username (`limiters map[string]*userLimiter`).
2. `supersedePriorFlow`/`lastSessionForUser` are keyed by username - a
   new flow for alice can only ever supersede alice's own prior flow,
   never bob's.
3. `/cancel` operates on an unguessable `session_id` (128 bits of
   randomness from `randomHex`), not a username - cancelling one
   session cannot reach another user's session by construction.
4. Approval markers are filed as `approved-<sanitized username>`
   (`writeApprovalMarker`) and consumed by PAM using its own
   independently-obtained username - PAM can structurally never consume
   a marker for a user other than the one it is actually authenticating.
   The marker's content additionally embeds the UID the broker resolved
   via NSS *at flow-start time* (`VERSION=2`/`USERNAME=`/`UID=` fields);
   PAM re-resolves the account fresh via `getpwnam_r` at consumption
   time and requires an exact UID match, so an account deleted and
   recreated (same username, different UID) between approval and
   consumption fails closed instead of being silently trusted.
5. `allowed_users["root"]` is refused outright at config-load time,
   redundant with (not a replacement for) the PAM stack's own
   `pam_succeed_if.so user != root` line.

See `src/broker/multiuser_test.go` for the tests exercising this
isolation directly (parallel alice/bob flows, cross-user
supersede/cancel rejection, multi-entry `allowed_users` parsing).

**Per-user KWallet credentials.** `kwallet-secretd` resolves a distinct
credential per local user (`kwallet_credential_name` is a *prefix*; the
actual file is `<prefix>.<username>`, e.g. `kwallet.secret.alice` - see
`docs/kwallet.md` and `scripts/setup-kwallet-credential.sh`). The
hand-off marker PAM mints after a successful login also carries the
account's UID, and `kwallet-secretd` refuses to release a secret unless
that UID matches what the requesting PAM process claims - a request
naming "alice" cannot be satisfied by a hand-off marker minted for any
other account, even under a race.

**The single-allowed-user auto-resolution is a broker-level convenience
fallback, not what the theme relies on.** The theme itself always sends
an explicit `username` (SDDM's own currently-selected account - see
below), so this API-level fallback (omit `username` when
`allowed_users` has exactly one entry) mainly exists for direct API
callers/testing. With more than one entry and no `username`, `/start`
still refuses (`403`) rather than guessing - never username enumeration,
never an implicit choice.

**Flow-to-account binding in the theme.** `pixelFlow.sddmSelectedUsername`
tracks SDDM's own account selection (`mainStack.currentItem.userList
.selectedUser`, or `.userNameInput.text` when the manual-entry prompt is
showing) - SDDM's existing account picker is the only source of truth,
never a second user list. `pixelFlow.targetUsername` is captured from
that once, when a flow starts, and is immutable for the flow's whole
lifetime; if SDDM's selection changes to a different account while a
flow is active, `onSddmSelectedUsernameChanged` cancels it immediately
rather than silently retargeting - a stale `/status` "approved" response
can then never reach `handleApproved` for the newly-selected account,
because `state` is no longer `"waiting"` by the time it would arrive.

## LDAP/Active Directory accounts (NSS)

`account_source=nss` (config-only; `local` remains the default and is
unchanged from v0.1-v0.4) lifts the "must be a literal `allowed_users`
entry" requirement for accounts NSS can resolve - the same mechanism any
other PAM-integrated login path already relies on, not a new one this
project invents:

```mermaid
flowchart LR
    B[Broker: authorizeAccount] -->|user.Lookup / GroupIds| N[NSS]
    N --> F["files (/etc/passwd, /etc/group)"]
    N --> S["sss (SSSD)"]
    S --> AD[Samba AD / OpenLDAP / FreeIPA]
```

**The broker never speaks LDAP, Kerberos, or any directory protocol
itself, and never caches a directory credential.** It only calls
`os/user.Lookup`/`(*user.User).GroupIds` - the same libc NSS entry points
(`getpwnam_r`, `getgrouplist`) `login`, `sshd`, or `sudo` would use. This
binary is built cgo-enabled (`debian/rules`, external linking already
required for the PAM hardening flags) specifically so these calls go
through the *system's* NSS/`/etc/nsswitch.conf`, not a pure-Go fallback
that would only ever see `/etc/passwd`. Whatever `passwd:`/`group:` lines
in `nsswitch.conf` resolve to - `files`, `sss`, or both - is exactly what
this project sees, nothing more.

**`authorizeAccount` (`src/broker/main.go`) is the single gate**, called
fresh on every `/start`, never cached:

1. `local` mode: username must be a literal `allowed_users` entry -
   identical to every prior release.
2. `nss` mode: the account must resolve via NSS at all (a lookup error -
   SSSD down, LDAP unreachable, truly unknown user - fails closed, never
   "assume allowed"); must not be `root` (checked by both UID `0` *and*
   name, so a second account sharing UID 0 can't slip through either);
   must not be in `deny_users` (which always implicitly contains `root`
   regardless of config); must have UID `>= minimum_uid`; and, if
   `allowed_groups` is non-empty, must be a member (via a fresh
   `GroupIds()` call, resolved against `allowed_groups` by name, not
   GID number, since GID numbering is directory-specific) of at least
   one of them. A non-empty `allowed_users` in this mode is then an
   *additional*, not alternative, restriction.

**Everything downstream of that gate is unchanged.** The UID resolved
here is embedded in the v2 approval marker exactly as before, and PAM
re-resolves it fresh via `getpwnam_r` at consumption time - an NSS/LDAP
account renamed, deleted, or given a different UID between approval and
login fails exactly the same way a local account would (see "Multi-user
readiness" above). The `AUTHENTICATED_AUTHELIA_USER ==
REQUESTED_LOCAL_USER` exact-match check in `pollAndDecide` is completely
unaware of `account_source` - identity binding does not care where the
account came from. Per-user rate limiting, flow supersession, and
cancellation are keyed by username exactly as before, so an NSS-resolved
account gets the same per-user isolation a local one does.

**What this project deliberately does not do**: implement its own LDAP
client, its own directory credential cache, or its own group-membership
cache. SSSD (or whatever NSS module is configured) already solves
caching, offline behavior, and connection pooling correctly; duplicating
that here would only add a second, likely-inconsistent source of truth.
A host without SSSD configured (or with `account_source=local`, the
default) is entirely unaffected - this is opt-in, not a new requirement.

## Provider abstraction

`provider_kind` (default `authelia`, unchanged from v0.1-v0.6) selects
which OIDC Device Authorization Grant (RFC 8628) provider the broker
talks to. `provider_kind=oidc` supports any standards-compliant provider
that publishes an OIDC discovery document advertising
`device_authorization_endpoint` - Keycloak, Authentik, or any other
generic OIDC Provider - via `oidc_discovery_url`/`oidc_identity_claim`
(`src/broker/provider.go`).

**No provider-specific logic ever exists in the QML theme** - it only
ever talks to this broker's own `127.0.0.1:7899` API exactly as before,
completely unaware of which provider (or even whether Authelia or a
generic OIDC provider) is configured. This is unaffected by
`provider_kind` by construction, not by convention.

**Capability detection** is the discovery document itself: if it doesn't
advertise `device_authorization_endpoint`, `token_endpoint`, and
`userinfo_endpoint`, the broker refuses to start rather than guess at a
conventional path - the same fail-closed philosophy as everywhere else
in this project.

**Identity mapping** stays exactly the model described above
(`REQUESTED_LOCAL_USER`/`AUTHENTICATED_..._USER`/`BOUND_LOCAL_USER`,
exact string match, no fuzzy mapping) - only which userinfo claim
supplies `AUTHENTICATED_..._USER` changes: Authelia's own
`authelia.pam.username`, or `oidc_identity_claim` (default
`preferred_username`) for a generic OIDC provider.

**Deliberately not a Go `interface` threaded through every call site.**
The existing `deviceAuthorize`/`pollToken`/`verifyUserinfo` functions -
and every test exercising them directly - are completely unmodified;
`providerDeviceAuthorize`/`providerPollToken`/`providerVerifyIdentity`
are the only new call sites (used by `handleStart`/`pollAndDecide`
instead of calling the Authelia-specific functions directly), and they
simply dispatch to those unchanged functions unless `provider_kind=oidc`
is explicitly configured. This keeps the already-proven Authelia code
path's risk at zero.

**Validated**: the generic OIDC path end-to-end (device-authorization,
token polling including rate-limit passthrough, and identity extraction
with both the default and a custom claim name) against a mock server
shaped like Keycloak's real endpoint layout
(`/protocol/openid-connect/{auth/device,token,userinfo}`), and discovery
capability detection refusing a provider that doesn't advertise
`device_authorization_endpoint`. **Not validated**: a real, live
Keycloak or Authentik instance - none was stood up in this environment;
the implementation follows the OIDC/RFC 8628 standards both providers
document, but was not independently re-verified against their actual
deployments.

## Native FIDO2/U2F hardware security keys

Optional, opt-in, off by default - see `docs/fido2.md` for the full
design, enrollment/revocation workflow, and PAM stacking detail. In
short: `pam_u2f.so` (Debian package `libpam-u2f`, upstream Yubico
project - never reimplemented by this project) is wired in additively,
ahead of `pam_authelia_passkey.so`, using the same dynamic
`[success=N default=ignore]` skip-count computation already used
throughout this project. A missing device, unenrolled user, or failed
touch/PIN/UV falls through to the smartphone/passkey path and then the
password fallback exactly as if FIDO2 support were not installed -
`pam_u2f` is looked up strictly by the username PAM itself is
authenticating, giving it the same structural cross-user isolation as
every other identity source here.

## Trust boundaries

- The broker's HTTP API is localhost-only and never itself authenticates
  anyone - only the approval marker file does.
- The approval marker is root-owned, 0600, single-use (atomically
  renamed-then-checked before being trusted), and short-TTL.
- `kwallet-secretd`'s socket is root-only (`0600`) at the filesystem
  level and additionally checks `SO_PEERCRED` for uid 0, and only ever
  releases a secret in response to a *second*, separate hand-off marker
  that only the already-successful PAM module can mint - it never reads
  or consumes the login-approval marker itself, so there is no
  double-consumer race between the login decision and the secret
  release.
- See `docs/threat-model.md` and `docs/security.md` for the full
  analysis.


### Flow outcome versus local failure lockout

The per-user failure lockout is an authentication-abuse control, not an
availability-error counter. Only explicit authentication denial, including
OAuth `access_denied` or a verified identity mismatch, increments it.
Cancellation, supersession, expiry, HTTP 429, transport/proxy errors and
userinfo infrastructure failures release the concurrency slot neutrally.

HTTP 429 backoff never becomes shorter than the current poll interval and
grows conservatively while throttling continues. Cancellation wakes a poller
even during a long Retry-After wait so stale flows do not retain global
concurrency slots.
