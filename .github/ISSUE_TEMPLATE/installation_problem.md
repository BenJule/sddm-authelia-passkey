---
name: Installation problem
about: preflight/install/enable-pam/postflight refused or behaved unexpectedly
labels: installation
---

**Which step failed**
`scripts/preflight.sh`, package install, `scripts/enable-pam.sh`,
`scripts/postflight.sh`, theme integration, or KWallet setup.

**Exact output**
Paste the full output of the failing step. If it refused
(`PAM_INSTALL=REFUSED` etc.), include that message verbatim.

**System**
- Distribution/version:
- SDDM version and `sddm --version` output:
- Output of: `grep -c '^auth' /etc/pam.d/common-auth` and
  `grep '^auth' /etc/pam.d/common-auth | tail -2`

**Sanitized `/etc/pam.d/sddm` and `/etc/pam.d/common-auth`**
Remove nothing except genuinely private content - the exact PAM stack
shape is what usually explains a refusal.
