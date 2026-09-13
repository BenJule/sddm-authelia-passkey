# Generic mechanism data model (v2.11.0)

**Status: a real, narrow second increment toward v3.0.0's "generic
authentication mechanism framework". Not the full framework.** This
document is the "stabile dokumentierte Mechanism-Schnittstelle"
deliverable named by the private roadmap's v3.0.0 gate. It describes
what is genuinely real after this increment, and is explicit about
what is not.

See also `docs/mechanism-selection.md` (the v2.9.0 increment this
model now backs) and `docs/capability-negotiation.md` (the underlying
`/capabilities` signals).

## What this is

`theme/native/components/MechanismModel.qml` is a single, shared QML
data model listing every authentication mechanism this project knows
about: `password`, `eidp`, `passkey`, `smartcard`. It replaces two
separate, ad-hoc property bindings (`smartphoneFlow.oidcReady`,
`smartphoneFlow.fido2Wired`) that `theme/native/Main.qml` read directly
in v2.9.0, with a single named lookup (`mechanismModel.mechanism(id)`)
that both `Main.qml`'s smartphone button/hint-label bindings and any
future mechanism-aware UI code can consume uniformly.

This was implemented as a **pure, byte-identical refactor**: it
changes no rendered pixel of the existing theme. This was proven for
real, not assumed - see "How this was verified" below.

## The `Mechanism` interface

Each entry in `MechanismModel.mechanisms` (and the return value of
`mechanism(id)`) is a plain object with these fields:

| field         | type    | meaning                                                              |
|---------------|---------|-----------------------------------------------------------------------|
| `id`          | string  | stable identifier: `"password"` \| `"eidp"` \| `"passkey"` \| `"smartcard"` |
| `displayName` | string  | translated (`qsTr`) human-readable name                              |
| `kind`        | string  | `"actionable"` or `"ambient"` (see below)                             |
| `available`   | bool    | could this mechanism ever work on this system at all                 |
| `ready`       | bool    | is it usable right now (live, capability-derived)                    |
| `statusHint`  | string  | translated hint to show the user when not ready; `""` when ready     |

`mechanism(mechanismId)` looks up one entry by `id` and returns `null`
for an unrecognized id, so a caller can always safely check the result
before use rather than risk a crash on a typo.

### `kind`: `"actionable"` vs `"ambient"`

- **`actionable`**: the user explicitly starts this mechanism (a
  button/click). `password` and `eidp` are actionable today.
- **`ambient`**: the mechanism has no start action at all and simply
  runs silently in the background ahead of the other PAM modules.
  `passkey` (`pam_u2f.so`, see `docs/fido2.md`) is the only ambient
  mechanism - it is tried before both other PAM paths, so there is no
  "start passkey login" action to bind a UI button to (see
  `docs/mechanism-selection.md`'s "Why there is no selectable
  'Passkey' mechanism" for the full reasoning). An ambient mechanism
  is never rendered as a button, at most as an informational hint.

### `available` vs `ready`

- `available` is a static-ish capability fact: could this mechanism
  ever work on this system at all.
- `ready` is the live, currently-true readiness: could it work right
  now.

For `password` both are always `true`. For `eidp`/`passkey` they are
derived from the real `/capabilities` signals (`oidcReady`/
`fido2Wired` on the existing `SmartphoneFlowController`, polled every
20 seconds - see `docs/capability-negotiation.md`). For `smartcard`
both are always `false` - this project implements no smartcard/
PKCS#11 support whatsoever.

## What this model never does

**This model never makes or gates an authentication decision - it
only describes what the UI may safely offer.** The broker/PAM stack
remains the sole authentication authority regardless of anything
exposed here. This is the same invariant `docs/capability-negotiation.md`
established for the raw `/capabilities` signals this model is built
from, restated here because it is the single most important property
of this interface.

## What is genuinely new versus what is unchanged

**Real and new in v2.11.0:**
- A single, named, documented `Mechanism` data shape now exists and is
  actually consumed by `Main.qml`'s smartphone button/hint-label
  bindings (previously two separate raw property reads).
- All four mechanisms this project knows about - including
  `password` and `smartcard`, which have no UI wiring yet - are
  represented in the model, so the interface itself is complete even
  though not every mechanism is UI-driven by it yet.

**Real and new in v2.12.0:**
- `password`'s login button and password field are now also gated on
  `mechanismModel.mechanism("password").ready`, alongside the existing
  username-selected check. `password.ready` is always `true` today, so
  this changes no rendered/functional behavior (proven via the same
  26-case visual regression suite, `CHANGED=0` for all cases) - but it
  means all *actionable* mechanisms (`password`, `eidp`) now go through
  the same single source of truth, rather than password being the one
  exception left on an ad-hoc check.
- `smartcard` was deliberately **not** given any UI wiring. Unlike
  `passkey` (an ambient mechanism with a real, if silent, PAM path) or
  `eidp` (a real capability signal with a real backend), `smartcard`
  has neither a capability signal that could ever turn `true` nor any
  backend action a button could trigger - there is no PKCS#11/
  smartcard implementation anywhere in this project. Adding a
  permanently-invisible "Smartcard" button today would only be UI
  scaffolding for a feature that doesn't exist, which conflicts with
  this project's own "no UI offers or implies smartcard support"
  invariant (`docs/capability-negotiation.md`) even if the button
  itself would never render. When smartcard support is ever actually
  implemented, wiring its UI through this model is expected to be a
  small, mechanical change - exactly like `eidp`/`passkey` were - not
  a redesign.

**Explicitly still unchanged / not yet real:**
- No new capability signal was added; the model itself is unchanged
  since v2.11.0 - only which UI elements read from it grew.
- The three external blockers tracked by the private roadmap (no real
  Keycloak instance, no physical FIDO2 key, Debian 13's SSSD package
  lacking compiled passkey support) are unaffected by this change and
  still gate v3.0.0 itself.

## How this was verified

Because this was designed as a byte-identical refactor, the
verification goal was to actually prove zero rendered change, not just
assert it:

1. `qmllint` on the new `MechanismModel.qml` file: 0 warnings.
2. `qmllint` across all of `theme/native/`: identical total warning
   count before (via `git stash`) and after the `Main.qml` edit - no
   new warning categories introduced.
3. The full `qmltestrunner` suite (`tests/native`, including the new
   `tst_MechanismModel.qml` unit tests) against the mock broker: all
   tests pass.
4. The existing 26-case deterministic visual regression suite
   (`tests/native/visual/run_visual_regression.sh`, see
   `docs/visual-regression.md`) was re-run inside a real `debian:13`
   Docker container (matching CI's exact environment) after mirroring
   this same refactor into the test harness's own `Main.qml` (which is
   a hand-maintained visual mirror of the real theme, not an import of
   it). Result: `CHANGED=0` for all 26 cases, `26_OF_26_GREEN` -
   real, reproducible proof this is visually a no-op. Repeated
   identically for v2.12.0's password-wiring change.

## New unit tests

`tests/native/tst_MechanismModel.qml` covers: all four mechanisms are
present and independently addressable; unknown ids return `null`;
`password` is always available/ready with no status hint; `smartcard`
is always unavailable/not-ready with no status hint; `eidp.ready`
tracks `smartphoneFlow.oidcReady` reactively (with a status hint only
when not ready); `passkey` is `kind: "ambient"` and tracks
`smartphoneFlow.fido2Wired` reactively for both `available`/`ready`;
the model degrades safely (no crash, `password` still ready) when no
`smartphoneFlow` is bound at all.

## v2.13.0: the first visible mechanism-selection UI

**Status: not the full v3.0.0 Rich UI. Not smartcard support. Not a
manually-triggered passkey UI.** This is deliberately the smallest real
*visible* step: a selector row ("Anmeldemethode") with one button per
selectable mechanism, letting the user explicitly switch between the
password and smartphone/EIdP content areas that already existed.
Everything before this point (v2.11.0/v2.12.0) was a pixel-identical
refactor; this one is not, and was never intended to be.

### The selectable-mechanisms list

`MechanismModel.selectableMechanisms` is a new computed property:
`mechanisms.filter(m => m.kind === "actionable" && m.available)`. Today
that is exactly `password` and `eidp` - `passkey` is excluded because
it is `kind: "ambient"` (no start action a selector entry could ever
trigger), and `smartcard` is excluded because `available` is always
`false` (nothing real exists to select). This is derived purely from
the existing `kind`/`available` fields - not a second, competing
definition of what those fields mean.

### MechanismSelector.qml: a small, separately unit-tested state machine

The actual "which mechanism's controls are shown, and what happens
when you switch" logic lives in a new
`theme/native/components/MechanismSelector.qml`, not inline in
`Main.qml` - the same reason `SmartphoneFlowController.qml` is its own
component: `Main.qml` cannot be instantiated in `qmltestrunner` at all
(it depends on SDDM's own global context properties - `sddm`, `config`,
`userModel`, `sessionModel`, `keyboard` - which don't exist outside a
real greeter process), so any logic worth unit-testing has to live
somewhere else. `MechanismSelector` never makes or gates an
authentication decision; it exposes:

- `selectedMechanism` (`"password"` by default)
- `selectMechanism(id)` - user-driven selection; refuses an unready
  mechanism (mirrors the selector's own disabled-button state)
- `returnToPassword()` - the one safe path back to password, used both
  automatically and by explicit "leave the smartphone area" actions
  (Escape, closing the panel, a real account change)
- `reconsiderCurrentMechanism()` - call whenever a mechanism's live
  readiness may have changed; fails closed to password if the
  currently selected mechanism is no longer ready

Switching away from a *live* smartphone flow always calls the existing
`SmartphoneFlowController.cancelCurrent(false)` - the exact same
call `attemptPasswordLogin()` already used before this increment
existed. No second/parallel cancellation mechanism was invented.
`Main.qml` wires `MechanismModel.onEidpReadyChanged` to
`reconsiderCurrentMechanism()`, since `eidp` is the only selectable
mechanism whose readiness can ever change while selected (`password`
is always ready).

### What actually changed visibly

- A "Anmeldemethode" label + two-button selector row, always shown.
- The password label/field/failure-label/login-button are now only
  shown while `password` is selected (previously always shown).
- The "Mit Smartphone anmelden" button and its unreachable-hint label
  are now only shown while `eidp` is selected (previously always
  shown). The ambient passkey hint is unaffected by selection - it
  remains visible whenever `passkey.ready`, regardless of which tab is
  active, since it is not something the user selects.
- Selection state is never conveyed by color alone: the selected tab
  also gets a bolder font weight and a distinct border (the existing
  `PolishedButton.primary` styling), plus an explicit
  `Accessible.role: Accessible.RadioButton` and a description stating
  "Ausgewählt" for screen readers.

### What did not change

- `password`/`smartcard` still are not both "backed" the same way -
  `smartcard` still has zero UI, by design (see below).
- No new capability signal, no new backend call, no new PAM/broker
  behavior. Every login still goes through exactly the same
  `sddm.login()`/broker code paths as before.
- The three external blockers (Keycloak instance, FIDO2 hardware,
  SSSD passkey-capable build) are unaffected.

### Why smartcard still gets no selector entry

Unlike `passkey` (a real, if silent, PAM path) or `eidp` (a real
capability signal with a real backend), `smartcard` has neither a
capability signal that could ever turn `true` nor any backend action a
button could trigger - there is no PKCS#11/smartcard implementation
anywhere in this project. `MechanismModel.selectableMechanisms`
structurally excludes it (`available` is a hardcoded `false`), so it is
not merely hidden - there was nothing to wire in the first place. If
smartcard support is ever implemented, giving it a selector entry is
expected to be a small, mechanical addition, exactly like `password`
becoming selectable was.

### How this was verified

This increment is explicitly **not** a pixel-identical change - the
selector row is new, visible UI. The verification goal was therefore
to identify and review every actual diff, not to force `CHANGED=0`:

1. The unmodified visual regression suite was run first (real
   `debian:13` container) to capture a true pre-change baseline:
   `26_OF_26_GREEN`.
2. After implementing the change (mirrored into the test harness, a
   hand-maintained visual mirror, not an import of the real theme),
   the suite was re-run: all 26 pre-existing cases showed a real diff
   (the new selector row + one button/labels hidden), reviewed
   visually case-by-case across every distinct scenario (default
   idle/password states, every "eidp active" flow state, both existing
   capability-variance states, three brand-new dedicated selector
   states) - all matched the intended design, nothing unexpected.
3. Three new dedicated baseline states were added:
   `mechanism_selector_password`, `mechanism_selector_eidp` (tab
   selected, flow not yet started - a state that didn't exist before),
   `mechanism_selector_eidp_unavailable` (disabled tab rendering).
4. All 29 cases (26 existing + 3 new) were regenerated via
   `--update-baselines` and the suite was re-run once more in normal
   comparison mode: `29_OF_29_GREEN`, `CHANGED=0` for every case.

`EXPECTED_VISUAL_CHANGES=29` (all cases - the selector is genuinely new
UI shown everywhere). `UNEXPECTED_VISUAL_CHANGES=0`.

### New unit tests

`theme/native/components/MechanismSelector.qml` is covered by
`tests/native/tst_MechanismSelector.qml`: initial state is `password`;
selecting a ready mechanism works; selecting an unready or unknown
mechanism is refused; reselecting the current mechanism is a no-op;
switching away from a *live* `eidp` flow cancels it
(`cancelCurrent(false)`, exactly once); switching away from an *idle*
`eidp` flow cancels nothing; `reconsiderCurrentMechanism()` falls back
to `password` (cancelling a live flow if needed) when the selected
mechanism becomes unready, and is a no-op while it stays ready;
`returnToPassword()` is a no-op when already on `password` and
otherwise cancels a live flow.

`tests/native/tst_MechanismModel.qml` gained coverage for
`selectableMechanisms`: exactly `password` + `eidp` when both are
ready; `eidp` stays present-but-disabled (not removed) when unready;
`passkey` is never selectable even when ready; `smartcard` is never
selectable.

`tests/native/test_feature_parity.py` gained a static check that
`Main.qml`'s selector actually reads `mechanismModel.selectableMechanisms`
(not a second, hardcoded `["password", "eidp"]` list), and that
`MechanismSelector.qml` never calls `sddm.login` directly (a static
proof that selection stays presentation-only).
