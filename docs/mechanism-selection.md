# Generic mechanism-selection framework (v2.9.0 - first real increment)

**Status: a real, narrow first increment toward v3.0.0's "generic
authentication mechanism framework" vision. Not the full framework.**
`docs/roadmap.md`'s longer-term direction is a standardized
`password`/`passkey`/`eidp`/`smartcard` mechanism model with dynamic
capability-driven negotiation and a dedicated UI per mechanism. This
document records what actually exists after v2.9.0, and is explicit
about the real constraints that keep the fuller vision from being
honestly closeable yet.

## What shipped

The native theme's two real, selectable login mechanisms - password
(SDDM's own built-in field) and EIdP/smartphone (this project's device-
authorization flow) - are now offered based on a real capability
signal rather than unconditionally:

- The "Mit Smartphone anmelden" button is disabled, with a visible
  reason label, whenever `smartphoneFlow.oidcReady` is `false` (the
  v2.4.0 `/capabilities` endpoint's `oidc_ready` field, polled every
  20 seconds). This directly closes v2.4.0's own explicitly-deferred
  "Noch offen" item: capability-driven mechanism *offering*, not just
  an informational hint.
- A `FIDO2_CAPABLE` badge ("Hardware-Sicherheitsschlüssel verfügbar -
  einfach berühren") is now shown on the **main login screen** (moved
  up from being only visible inside the smartphone panel, which a user
  touching their hardware key would likely never open).

## Why there is no selectable "Passkey" mechanism

The roadmap's own long-term UI mockup shows three separately selectable
options (`Passkey` / `Smartphone` / `Passwort`). That does not map onto
how hardware-key login actually works in this project today:
`pam_u2f.so` (see `docs/fido2.md`) is stacked **ahead of** both the
password and smartphone paths in PAM and tries silently and
automatically - touching an enrolled key logs the user in without ever
opening any panel or clicking any button. There is no "start passkey
login" action to bind a button to; inventing one would either be
purely decorative (misleading - suggesting an action is needed when it
isn't) or would require actually restructuring the PAM stack's trust
model, which is out of scope for a UI-layer change. The `FIDO2_CAPABLE`
badge above is therefore informational, not a third selectable
mechanism - an honest reflection of the real architecture, not a
missing feature.

## Why `SMARTCARD` still does not exist

Unchanged from `docs/capability-negotiation.md`: no smartcard/PKCS#11
implementation exists anywhere in this project, and `smartcard_ready`
remains a constant `false` in `/capabilities`. Nothing in the UI offers
or implies smartcard support.

## Explicitly out of scope for v2.9.0

- A generic, standardized `mechanism` data type/interface consumed
  uniformly across password/passkey/eidp/smartcard (today's change is
  two targeted property bindings on the existing buttons, not a new
  abstraction layer).
- Any smartcard implementation.
- A dedicated Passkey PIN/Touch/Key-connected UI (still not applicable
  - see above).
- Hotplug-driven mechanism re-evaluation beyond the existing 20-second
  poll.
- ~~A visual regression suite for a mechanism/capability matrix~~ -
  **closed as a follow-up**: two new deterministic baseline states
  (`smartphone_unreachable`, `fido2_available`) were added to the
  existing v1.15.0 visual regression framework, bringing it to 18
  states / 26 cases. See `docs/visual-regression.md`.

These, along with the three external blockers the private roadmap
tracks (no real Keycloak instance, no physical FIDO2 key, and Debian
13's SSSD package lacking compiled passkey support), are why v3.0.0
itself remains a gate rather than something this increment closes.
