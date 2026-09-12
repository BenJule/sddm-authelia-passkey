# Native Theme hardening (v1.18.0)

A threat-model review of the Native Theme greeter and its broker
client, covering file handling, network behavior, and presentation
edge cases. Nothing here changes the authentication model: PAM stays
the sole authentication authority, and the greeter still speaks only
to the local project broker over HTTP - never LDAP/AD/FIDO2/OIDC
directly, and never a login-method bypass.

## What changed

- **Branding override safety.** `theme.conf.user` (the optional admin
  branding override, for both the Native Theme and the compatibility
  theme) is read directly by SDDM's own config object, with no
  ownership check of its own. `scripts/validate-branding-overrides.sh`
  closes that gap: it runs automatically on every install/upgrade
  (and on demand via `sddm-authelia-passkey-admin branding-status`),
  and neutralizes (moves aside, never deletes) an override that is a
  symlink, not owned `root:root`, or group/world-writable. A
  neutralized override simply falls back to zero-config branding -
  login itself is never affected.
- **Broker request timeouts.** Every XHR the Native Theme's
  `SmartphoneFlowController` makes now has a bounded timeout
  (`requestTimeoutMs`, 8s in production). A broker that accepts a
  connection but never responds previously left that request pending
  indefinitely; each subsequent poll would leak another one. A timed-
  out request is aborted and treated exactly like a refused connection
  (existing `offline` handling), and a defensive `aborted` flag
  guards against a late response from the same request being applied
  after the fact.
- **Bounded image decoding.** The QR code, user avatar, and brand logo
  `Image` elements now set `sourceSize` to their actual displayed
  size, so an oversized file on disk can't force a full-resolution
  decode.
- **Bounded branding text.** `ui_brand_name`/`ui_brand_domain` are
  truncated (with an ellipsis) past a generous defensive length cap;
  normal values are never affected.

## Reviewed, no code change needed

- **QML imports / dynamic code.** No `Qt.createComponent`,
  `createQmlObject`, or `eval`-equivalent exists anywhere in
  `theme/native/` - all imports are static.
- **Path traversal via the broker.** The broker never builds a
  filesystem path from client-controlled input without sanitization
  (`sanitizeUsername()`), and QR paths are broker-generated into a
  non-world-writable directory, not client-influenced.
- **Malformed broker responses.** Every XHR handler already used
  `safeParse()` (try/catch `JSON.parse`) with explicit shape checks
  before v1.18.0; this was already solid and is unchanged.
- **Stale flow responses.** Every response handler already re-checks
  the request's flow generation and target identity before applying
  anything, and cancels a broker session created by an invalidated
  request; this was already solid and is unchanged.
- **Oversized/malformed images.** Both the avatar and QR `Image`
  elements already gate on `Image.Error`/`status !== Image.Ready` and
  fall back to non-image UI; unchanged.
- **Overlay click-through.** The smartphone-panel scrim already has an
  `anchors.fill` `MouseArea` that absorbs input to whatever is behind
  it while the panel is open.
- **Resource exhaustion via timers.** All flow timers are singleton,
  generation-guarded, and explicitly stopped on every state
  transition; no unbounded retry loop exists.

## Verified on VM124, not purely from source review

Screen hotplug, multi-monitor layout, and focus behavior depend on
runtime rendering, not just static QML. These were exercised as part
of the v1.18.0 VM124 pre-merge gate (see the release notes for that
gate's results) rather than through new static analysis.
