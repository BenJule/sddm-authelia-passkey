# Provenance

This statement covers everything under `theme/native/`.

## What was not used

- No Debian Breeze `Main.qml` source was copied, adapted, or used as a
  template. The pristine file was only ever *read* (in the same
  working tree this project's own compatibility-theme patch is
  developed against) to confirm the names of documented, public SDDM
  greeter context APIs actually in use on this platform (for example,
  that `sddm.login()`, `sddm.canPowerOff`/`canReboot`/`canSuspend`,
  and `userModel.lastUser`/`lastIndex` are the real, current property
  and method names) - never to copy its QML structure, layout,
  wording, or visual design.
- No KDE Breeze QML source blocks were copied.
- No Debian artwork, logos, or wallpapers are bundled or referenced.
- No KDE artwork or icon files are bundled.
- No third-party theme source of any kind was copied.
- No existing compatibility-theme QML blocks (from
  `theme/debian-breeze-authelia-passkey-patch/`) were copied - the
  native theme is not a port of that patch.

## What was used

- Documented, public SDDM Qt6 greeter theme APIs: `metadata.desktop`
  with `QtVersion=6`, `MainScript`/`ConfigFile` keys, the `sddm`
  context object (`login()`, `loginFailed`/`loginSucceeded`,
  `canPowerOff`/`powerOff()`, `canReboot`/`reboot()`,
  `canSuspend`/`suspend()`), `userModel`, `sessionModel`, and
  `keyboard` (`currentLayout`, `layouts`).
- Standard Qt Quick, Qt Quick Controls (Basic style), and Qt Quick
  Layouts modules, shipped with Qt6 itself - not a KDE/Plasma
  framework, not a third-party dependency.
- System icon-theme conventions are referenced by name only where
  applicable (none are vendored as image assets in this release).
- Generic, uncopyrightable UI interaction concepts common to every
  desktop login screen (a centered card, a password field, a clock, a
  power-actions row) - not a specific implementation copied from
  anywhere.

## Original work

All QML files under `theme/native/` (`Main.qml`,
`components/UserAvatar.qml`, `components/PowerActionsRow.qml`,
`components/SmartphoneLoginPreview.qml`), `metadata.desktop`, and
`theme.conf` are original work written for this project, licensed
under the same terms as the rest of this repository (see the top-level
`LICENSE`/`debian/copyright`).

## Branding

No Debian, KDE, Breeze, Authelia, AuthentiK, Keycloak, or other
provider/vendor name, logo, or visual identity is used anywhere in
this theme. The theme's own identity is the neutral name
"SDDM Authelia Passkey Native" - see `metadata.desktop`.
