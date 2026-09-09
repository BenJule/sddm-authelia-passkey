---
name: Bug report
about: Something doesn't work as documented
labels: bug
---

**Affected component**
`src/pam`, `src/broker`, `src/kwallet-secretd`, the theme integration, or an installer script.

**System**
- Distribution/version:
- SDDM version:
- KDE Plasma version:
- Authelia version:
- `sddm-authelia-passkey` version (`dpkg -l sddm-authelia-passkey`):

**Steps to reproduce**

**Expected behavior**

**Actual behavior**

**Logs**
Relevant, sanitized `journalctl -u sddm-authelia-passkey-broker` /
`journalctl -u sddm-authelia-passkey-kwallet-secretd` output. Remove any
hostnames, usernames, or tokens before pasting.

**Did this affect the password login fallback path?**
That path structurally never depends on this project's own code (see
`docs/architecture.md`) - if you believe it does, please say so
explicitly, this is treated as maximum severity.
