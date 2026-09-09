# Theme integration

`sddm-theme-debian-breeze` is part of KDE's `plasma-desktop`, licensed
GPL-2.0-or-later / LGPL (mixed, per-file - see
`/usr/share/doc/sddm-theme-debian-breeze/copyright` on a Debian system).
This project does **not** vendor a copy of that theme. Instead, this
directory ships two small unified diffs against the theme files as
installed by the `sddm-theme-debian-breeze` Debian package:

- `Main.qml.patch` - adds a "Smartphone-Login" action button (alongside
  Sleep/Restart/Shut Down/Other) that opens a right-anchored sidebar panel
  with the QR code, mostly as new sibling QML elements after the theme's
  existing root `Item`'s last child. Two small, deliberate exceptions touch
  existing lines: the main login block's horizontal centering (clock and
  the `StackView` holding the password form) is adjusted so it recenters
  within the visible area when the sidebar is open, instead of staying
  centered on the full screen width behind it.
- `metadata.desktop.patch` - renames the theme copy so it appears
  alongside (not instead of) the original in SDDM's theme picker.

`scripts/install.sh` copies the user's own installed
`/usr/share/sddm/themes/debian-breeze/` to a new
`debian-breeze-authelia-passkey` theme directory and applies these
patches to that copy - the original theme is never modified in place, and
this repository never redistributes GPL-licensed KDE source itself.

If your distribution ships a different SDDM theme, these patches will
not apply cleanly; see docs/troubleshooting.md.
