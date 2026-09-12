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

**Explicitly unchanged / not yet real:**
- `password` and `smartcard` are represented in the model's data (both
  correctly: always ready/never available respectively) but **nothing
  in the UI reads the model for them yet** - the password field/button
  and the (nonexistent) smartcard UI behave exactly as before,
  independent of this model. Wiring them through the model is future
  work, not part of this increment.
- No new capability signal was added; the model is a pure
  restructuring of the two signals that already existed since v2.4.0/
  v2.9.0.
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
   real, reproducible proof this is visually a no-op.

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
