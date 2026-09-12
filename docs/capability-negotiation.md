# Capability negotiation (v2.4.0)

**Status: a real, narrow subset implemented. The full generic
mechanism-selection framework the private roadmap envisions
(`PASSWORD`/`PASSKEY`/`EIDP`/`SMARTCARD` as standardized, negotiated
mechanisms with dedicated PIN/Touch/Key-connected and Smartcard UI) is
NOT implemented - see "Explicitly out of scope" below.**

## What shipped

A read-only, unauthenticated `GET /capabilities` broker endpoint,
queryable before any username is even selected:

```json
{
  "account_source": "local",
  "oidc_ready": true,
  "fido2_wired": false,
  "smartcard_ready": false
}
```

- `oidc_ready` - a fresh (throttled to at most once per 10 seconds)
  reachability check against the configured identity provider:
  Authelia's `/api/health`, or a live discovery-document fetch for
  `provider_kind=oidc`. Deliberately independent of `oidcDiscover()`'s
  own permanent per-process cache (correct for "the endpoints don't
  change", wrong for "is the provider reachable right now").
- `fido2_wired` - whether `pam_u2f.so` is actually present in
  `/etc/pam.d/sddm`, i.e. whether `enable-fido2.sh` has been run. The
  broker never manages PAM itself (see `docs/fido2.md`); this is a
  read-only observation of the same fact an administrator could grep
  for themselves.
- `smartcard_ready` - always `false`. This project does not implement
  smartcard/PKCS#11 authentication. A constant, explicit field rather
  than an absent one, so a client never has to guess whether "unset"
  means "false" or "not yet known".

The native theme's `SmartphoneFlowController` polls this endpoint every
20 seconds (via `fetchCapabilities()`), independent of any specific
login flow or session, and exposes `fido2Wired`/`oidcReady`
properties. `SmartphoneLoginPanel` uses `fido2Wired` to show a small,
non-blocking informational hint ("Hardware-Sicherheitsschlüssel
verfügbar") - nothing more. A failed or slow `/capabilities` request
never surfaces as a flow error; it just leaves the last-known (or
default-optimistic) values in place.

## Why this is safe

Per the roadmap's own explicit constraint: **capability data must never
replace an authentication decision, only drive an offer/UX or a safe
preflight decision.** Concretely here:

- `/capabilities` carries no per-user authorization check at all (no
  username parameter, no allowlist consultation) - it cannot leak
  anything an unauthenticated local process couldn't already observe.
- The hardware-key fast path (`pam_u2f.so`) already works completely
  independently of whether the greeter shows any hint about it - PAM's
  own stacking order tries it first regardless (see
  `docs/fido2.md`'s "PAM stacking" section). The hint is purely
  informational; hiding or showing it changes nothing about whether a
  touch on the key actually logs someone in.
- `oidc_ready` only feeds a UI hint property (`oidcReady`); no existing
  flow-control logic (start/poll/retry/timeout state machine in
  `SmartphoneFlowController`) was touched, so the carefully-hardened
  v1.18.0 timeout behavior is unaffected.

## Explicitly out of scope for v2.4.0

- A generic `PASSWORD`/`PASSKEY`/`EIDP`/`SMARTCARD` mechanism
  abstraction layer.
- ~~Capability-driven *offering* of mechanisms~~ - **closed in v2.9.0**:
  the smartphone/EIdP button is now disabled (with a visible reason)
  when `oidc_ready` is false, rather than only showing a text hint. See
  `docs/mechanism-selection.md`.
- Dedicated Passkey PIN/Touch/Key-connected UI states - still not
  applicable; see `docs/mechanism-selection.md`'s explanation of why
  hardware-key login has no selectable UI action at all.
- Any smartcard/PKCS#11 implementation whatsoever.
- Hotplug/dynamic capability re-negotiation beyond the existing 20s
  poll.
- ~~A visual regression suite for a mechanism/capability matrix~~ -
  closed as a follow-up; see `docs/mechanism-selection.md`.

These remain open items for a later iteration, tracked in the private
roadmap.
