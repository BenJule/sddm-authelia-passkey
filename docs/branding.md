# Optional branding

Branding is presentation-only and deliberately separate from
`/etc/sddm-authelia-passkey/config.conf`, which remains authentication and
policy configuration.

The compatibility theme has supported vendor-neutral branding since v1.8.0.
v1.13.0 adds the same administrator-facing branding contract to the
independent Qt6 Native Theme.

## Native Theme

SDDM's supported theme override mechanism is used directly.

Create:

`/usr/share/sddm/themes/sddm-authelia-passkey-native/theme.conf.user`

as a regular `root:root` file with mode `0644`.

A Native Theme example is shipped as:

`/usr/share/sddm-authelia-passkey/native-theme/theme.conf.user.example`

The package does not create `theme.conf.user`; it only ships defaults in
`theme.conf` and the example above. Because the administrator override is
not package-owned, an in-place package reinstall or upgrade preserves it.

Supported keys:

- `ui_brand_name`
- `ui_brand_logo`
- `ui_show_hostname`
- `ui_show_domain`
- `ui_brand_domain`
- `ui_show_avatar`
- `ui_accent`
- `ui_accent_color`

`ui_brand_logo` accepts only an absolute local path. HTTP, HTTPS and other
remote URL forms are rejected by the Native Theme.

`ui_accent=custom` accepts only an opaque `#RRGGBB` value. Invalid values
fall back to the v1.12 Native Theme accent.

`ui_show_hostname=true` displays SDDM's own local hostname.

The domain/realm is administrator supplied through `ui_brand_domain`. It is
never inferred from OIDC claims, broker identity data or NSS information.

`ui_show_avatar=false` suppresses account avatars without changing username
selection, account binding or authentication behaviour.

With no `theme.conf.user`, the exact v1.12 presentation remains the Native
Theme default.

## Compatibility theme

The compatibility theme continues to use:

`/usr/share/sddm/themes/debian-breeze-authelia-passkey/theme.conf.user`

Its example remains:

`/usr/share/sddm-authelia-passkey/theme/theme.conf.user.example`

The compatibility-theme installer additionally validates the existing
override before preserving it. Unsafe symlinks and non-root-owned overrides
are refused there.

## Security boundary

Branding cannot alter:

- PAM authentication authority
- broker authentication decisions
- KWallet authentication authority
- approval markers
- OIDC/FIDO2 policy
- SmartphoneFlowController decisions
- exact username/session binding

Branding remains presentation-only.
