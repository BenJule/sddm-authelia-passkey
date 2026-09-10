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

## What has not been specifically verified

- **Screen readers**: the custom QML elements this project adds (the
  QR display panel, its approve/expire states) do not set explicit
  `Accessible.role`/`Accessible.name` properties. Framework-provided
  components this project reuses unmodified (Kirigami/Plasma buttons,
  labels) inherit whatever accessibility support those frameworks
  provide, but this has not been tested with an actual screen reader
  against the patched theme - only visually and via keyboard. If you
  rely on a screen reader, please test in a lab/VM environment before
  relying on this for your only login path, and consider filing an
  issue with what you find.
- **High-contrast/large-text SDDM themes**: this project's patch
  targets `debian-breeze` specifically (see `docs/installation.md`
  "Supported platforms") - it has not been adapted for or tested
  against other themes, including accessibility-focused ones.
- **WebAuthn UV method accessibility on the authenticator side**
  (fingerprint vs. PIN vs. face, whether the phone/OS itself offers
  accessible alternatives) is entirely up to the user's own
  authenticator and outside this project's control or visibility - see
  `docs/security.md`.
