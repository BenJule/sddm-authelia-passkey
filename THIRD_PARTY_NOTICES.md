# Third-party notices

`sddm-authelia-passkey` integrates with upstream software but does not relicense it.

- **SDDM**: runtime integration through documented greeter and PAM interfaces. Upstream licence applies.
- **KDE Plasma / Debian Breeze**: optional compatibility-patch target. Applicable upstream file licences remain in force for patched combined files.
- **Authelia**: external OIDC Device Authorization provider. No Authelia source is vendored.
- **Linux PAM**: runtime and build dependency. System package licence applies.
- **pam_u2f / libfido2**: optional local hardware-key path. Upstream licences apply.
- **systemd**: runtime integration, including optional credential handling. Upstream licence applies.
- **Go modules and GitHub Actions**: each dependency retains its own licence.

## Theme provenance

The Native Theme under `theme/native/` is original project-owned QML and is not copied from Debian Breeze or KDE Breeze. Files in that subtree carry `SPDX-License-Identifier: GPL-3.0-or-later`. See [`theme/native/PROVENANCE.md`](theme/native/PROVENANCE.md).

The compatibility integration under `theme/debian-breeze-authelia-passkey-patch/` contains project-authored patch files rather than a vendored theme tree.

Project-owned files without a more specific file-level notice use the root [MIT License](LICENSE). See [`docs/licensing.md`](docs/licensing.md) for details.
