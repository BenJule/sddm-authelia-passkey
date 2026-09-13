# Licensing

This repository intentionally contains code under more than one licence. The
licence of a file is determined by its own SPDX identifier where present; the
root `LICENSE` is the default for project-owned files that do not carry a more
specific notice.

## Default licence: MIT

Unless a file says otherwise, project-owned source code, scripts,
documentation and configuration in this repository are licensed under the
[MIT License](../LICENSE).

## Native Theme: GPL-3.0-or-later

Files under `theme/native/` that carry:

```text
SPDX-License-Identifier: GPL-3.0-or-later
```

are licensed under the GNU General Public License version 3 or, at your
option, any later version. The Native Theme is original project-owned work;
its provenance is documented in [`theme/native/PROVENANCE.md`](../theme/native/PROVENANCE.md).

The canonical GPL text is published by the Free Software Foundation at
<https://www.gnu.org/licenses/gpl-3.0.html> and identified by SPDX as
`GPL-3.0-or-later`.

## Debian Breeze compatibility patches

`theme/debian-breeze-authelia-passkey-patch/` contains project-authored patch
files rather than a vendored copy of Debian/KDE Breeze. The patch files are
covered by the repository default MIT licence. Once those patches are applied
to an installed Breeze theme, the resulting combined files remain subject to
the applicable upstream KDE/Debian licences.

## Dependencies and upstream projects

The repository depends on or interoperates with software including SDDM,
KDE/Plasma, Linux PAM, Authelia, systemd, Go modules and `pam_u2f`. Those
projects are not relicensed by this repository and remain subject to their own
licence terms.

See [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) for the practical
provenance summary.

## Contributions

By contributing a change, you agree that your contribution may be distributed
under the licence already applicable to the files you modify. New files should
use the repository default MIT licence unless they are part of a subtree that
already uses another explicit SPDX licence.
