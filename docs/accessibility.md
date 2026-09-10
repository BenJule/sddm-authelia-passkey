# Accessibility

## The password path is always available and unaffected

Nothing in this project ever requires using the QR/smartphone,
FIDO2/U2F, or alternative-code path. Password login is the stock
Breeze/SDDM password field, completely unmodified and always present -
anyone who can use the unmodified `debian-breeze` theme today can
continue to log in exactly the same way after installing this project.
This is the primary accessibility guarantee: no user is ever forced
through a QR-scanning or hardware-key flow to reach their session.

## Keyboard operability of the added UI

- The alternative-code entry path (`i18nd(..., "Alternativ Code
  eingeben")` in the patched `Main.qml`) lets a user complete the
  device-authorization flow by typing the code shown on screen instead
  of scanning a QR code with a phone camera - useful for anyone who
  cannot hold/aim a phone camera, not just a fallback for a missing
  phone.
- `Keys.onEscapePressed` cancels an in-progress smartphone/passkey flow
  and returns focus to the password field without a mouse.
- The custom-styled buttons this project added (which bypass Breeze's
  default `background`/`contentItem` styling, and therefore would
  otherwise lose the platform's default focus indication) have explicit
  hover/pressed/focus/disabled visual states added specifically so
  keyboard focus remains visible on them (see `CHANGELOG.md`'s v0.4.2
  entry).

## Screen reader support (v1.5.0)

The custom QML elements this project adds now set explicit
`Accessible.role`/`Accessible.name`/`Accessible.description`:

- The smartphone-login panel itself (`Accessible.Dialog` in the
  narrow-display overlay layout, since it's modal there -
  `Accessible.Pane` in the sidebar layout, since the rest of the
  greeter stays reachable). See `docs/architecture.md`'s "Responsive
  Greeter" section for the layouts themselves.
- The icon-only back/cancel button, which previously had no
  screen-reader-visible label at all.
- The QR card: named and described, explicitly pointing an AT user at
  the "Alternativ Code eingeben" button as the actual accessible
  equivalent, rather than leaving them to discover it exists.
- The countdown progress bar, the connection-status chip, and the
  status-text label (flagged `Accessible.AlertMessage` for
  error/expired/approved, since those are exactly the states where a
  user needs to react).
- Purely decorative elements that duplicate adjacent visible text (the
  identity avatar image, the status-chip's color dot) are marked
  `Accessible.ignored` instead of given a redundant name, so they
  don't get double-announced.

Framework-provided components this project reuses unmodified
(Kirigami/Plasma buttons, labels) inherit whatever accessibility
support those frameworks already provide.

## Native Theme accessibility hardening (v1.12.0)

The independent Qt6 Native Theme now carries the same accessibility
principles explicitly instead of inheriting assumptions from the
compatibility theme.

Its custom Smartphone-Login panel reports `Accessible.Dialog` when it
is a modal overlay and `Accessible.Pane` when it is the non-modal
sidebar. The QR representation is exposed as a graphic with a textual
description and the visible device code remains available as the
non-camera alternative.

Connection state, critical authentication state and remaining-flow
time expose explicit accessible semantics. Account selection exposes
List/ListItem roles and selected state. Decorative account avatars and
status-color dots are ignored to avoid duplicate announcements.

The Native Theme also makes the password, session and keyboard-layout
controls explicitly named for assistive technology. Opening the
Smartphone panel transfers keyboard focus into it; closing it or
returning to password login restores focus to the password field.
Manual account entry similarly moves focus to the username field.

These properties are checked structurally in
`tests/native/test_accessibility_contract.py`, exercised through Qt's
QML test runner, and parsed by `qmllint`.

**What has not been specifically verified**: neither the compatibility
theme nor the Native Theme is claimed to have been exercised end to end
with a real screen reader such as Orca via AT-SPI inside an actual SDDM
login session. That requires interactive accessibility tooling outside
the current CI pipeline. If you depend on a screen reader, perform a
lab/VM test before making this your only login path and report any
assistive-technology-specific issue you find.

## What else has not been specifically verified

- **High-contrast/large-text SDDM themes**: this project's patch
  targets `debian-breeze` specifically (see `docs/installation.md`
  "Supported platforms") - it has not been adapted for or tested
  against other themes, including accessibility-focused ones.
- **WebAuthn UV method accessibility on the authenticator side**
  (fingerprint vs. PIN vs. face, whether the phone/OS itself offers
  accessible alternatives) is entirely up to the user's own
  authenticator and outside this project's control or visibility - see
  `docs/security.md`.
