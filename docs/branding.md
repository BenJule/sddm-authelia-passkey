# Optional branding

v1.8.0 keeps the default Debian Breeze appearance when no branding is
configured.

Branding uses SDDM's native `theme.conf.user` override mechanism. It is
presentation-only and deliberately separate from
`/etc/sddm-authelia-passkey/config.conf`, which remains authentication and
policy configuration.

Create:

`/usr/share/sddm/themes/debian-breeze-authelia-passkey/theme.conf.user`

as a regular `root:root` file with mode `0644`.

Example settings are shipped as
`/usr/share/sddm-authelia-passkey/theme/theme.conf.user.example`.

Supported keys:

- `ui_brand_name`
- `ui_brand_logo`
- `ui_show_hostname`
- `ui_show_domain`
- `ui_brand_domain`
- `ui_show_avatar`
- `ui_accent`
- `ui_accent_color`

`ui_brand_logo` accepts only an absolute local path. Remote URLs are never
loaded.

`ui_accent=custom` accepts only an opaque `#RRGGBB` value. Invalid values
fall back to the current system/Kirigami accent.

The domain/realm is administrator supplied. It is never guessed from OIDC
claims or NSS data.

Package/theme regeneration preserves an existing safe `theme.conf.user`.
Symlinks and files not owned by root are refused rather than followed.

The default with no override remains the normal vendor-neutral Debian Breeze
look. Authentication, PAM, OIDC, FIDO2 and broker behaviour are unchanged.
