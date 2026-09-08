# Theme integration

`sddm-theme-debian-breeze` is part of KDE's `plasma-desktop`, licensed
GPL-2.0-or-later / LGPL (mixed, per-file - see
`/usr/share/doc/sddm-theme-debian-breeze/copyright` on a Debian system).
This project does **not** vendor a copy of that theme. Instead, this
directory ships two small additive unified diffs against the theme files
as installed by the `sddm-theme-debian-breeze` Debian package:

- `Main.qml.patch` - adds a "Login with Passkey" button and its popup as
  new sibling QML elements after the theme's existing root `Item`'s last
  child. Touches zero existing lines.
- `metadata.desktop.patch` - renames the theme copy so it appears
  alongside (not instead of) the original in SDDM's theme picker.

`scripts/install.sh` copies the user's own installed
`/usr/share/sddm/themes/debian-breeze/` to a new
`debian-breeze-authelia-passkey` theme directory and applies these
patches to that copy - the original theme is never modified in place, and
this repository never redistributes GPL-licensed KDE source itself.

If your distribution ships a different SDDM theme, these patches will
not apply cleanly; see docs/troubleshooting.md.
