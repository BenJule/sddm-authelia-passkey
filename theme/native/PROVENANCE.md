# Native Theme provenance

This statement covers everything under `theme/native/`.

## Original implementation

All Native Theme QML is original project-owned work.

The implementation was written from scratch using documented Qt Quick and
SDDM greeter APIs plus the project's already-defined local broker protocol.

The existing compatibility theme was studied only for externally visible
behaviour, state semantics and security requirements. Its QML source was not
copied or mechanically translated into this Native Theme.

## Not copied or bundled

The Native Theme contains no:

- copied Debian Breeze QML
- copied KDE Breeze QML
- Debian artwork or logos
- KDE artwork or logos
- provider artwork or logos
- third-party SDDM theme source
- remote fonts
- remote images
- vendored JavaScript libraries

## APIs used

The theme uses documented SDDM context interfaces including:

- `sddm.login()`
- `sddm.loginFailed`
- `sddm.loginSucceeded`
- `sddm.canPowerOff` / `powerOff()`
- `sddm.canReboot` / `reboot()`
- `sddm.canSuspend` / `suspend()`
- `userModel`
- `sessionModel`
- `keyboard`

The Smartphone flow uses only the project broker's localhost HTTP interface.

## Authentication boundary

The Native Theme does not implement authentication decisions.

It does not validate approval-marker files, passwords, passkeys or identity
provider tokens.

PAM remains the authentication authority.
