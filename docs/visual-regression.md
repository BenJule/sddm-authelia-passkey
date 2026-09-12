# Native Theme Visual Regression

v1.15 provides deterministic visual regression testing for the independent
Native SDDM Theme.

## Renderer

The suite uses `sddm-greeter-qt6 --test-mode` under Xvfb with:

- `QT_QPA_PLATFORM=xcb`
- Qt Quick software rendering
- isolated `Noto Sans` from `fonts-noto-core`
- fixed X11/Qt font DPI of 96
- desktop/KDE platform-theme variables removed
- deterministic test fixtures

## Coverage

All 18 required visual states are baseline-tested at `1280x720 @ 1.00`:

- idle
- password
- Smartphone panel idle
- starting
- waiting
- alternate code
- approved
- logging in
- rate limited
- offline
- denied
- expired
- invalid branding asset
- long branding
- no avatar
- directory account
- smartphone unreachable (v2.9.0 - `oidc_ready=false`, button disabled with visible reason)
- FIDO2 available (v2.9.0 - `fido2_wired=true`, hint shown on the main screen)

Representative matrix states `idle`, `waiting`, `offline` and
`long_branding` are additionally tested at:

- `1920x1080 @ 1.00`
- `1920x1080 @ 1.25`

Total automated visual cases: 26.

## Determinism

The harness uses fixed users, sessions, display time, date, device code and
presentation state. It does not authenticate users and never calls
`sddm.login()`.

## Comparison tolerance

ImageMagick absolute-error comparison uses:

- colour fuzz: 6%
- maximum changed-pixel ratio: 1%
- exact image dimensions

Baseline SHA-256 values are stored in `baselines/manifest.json`.

CI never updates baseline images automatically. Baselines may only be regenerated explicitly with `--update-baselines` and must then pass the normal comparison mode again.

## Failure diagnostics

A failed visual CI run retains actual screenshots, diff images, metrics and
greeter logs in the `native-visual-regression-diagnostics` artifact.

## Security boundary

The harness lives only under `tests/native/visual/` and must not be installed
by the Debian package.

PAM remains the authentication authority. Broker, KWallet, FIDO2,
approval-marker and exact username/session-binding semantics remain unchanged.
