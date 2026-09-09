# Validated environment

This documents what has actually been exercised end-to-end, as opposed
to what is merely expected to work. No private hostnames, IP addresses,
usernames, or infrastructure topology are included below - see
`docs/threat-model.md` and `docs/security.md` for the design rationale
instead of specific deployment details.

## Platform

Debian 13 (Trixie), SDDM 0.21.x, KDE Plasma 6, Authelia 4.39+ (OIDC
Device Authorization Grant), systemd 257+.

## What has been validated on a real production host

- Clean package cutover from a prior, unpackaged prototype implementation
  to this project's packaged `pam_authelia_passkey.so` / broker /
  `kwallet-secretd`, via a scoped, temporary, fixed-dispatch sudo helper
  (no interactive password re-entry per step, no free-form remote shell)
  with an explicit confirmation gate before the `/etc/pam.d/sddm` write.
- Password login, unchanged and unaffected throughout.
- Smartphone/passkey login: QR scan, WebAuthn/Passkey user verification,
  approval, PAM handoff, successful Plasma session start.
- KWallet auto-unlock (optional component) verified working, with no
  manual password prompt, on **both** the password login path (normal
  KDE wallet/login-password sync) and the smartphone/passkey login path
  (via the `kwallet-secretd` hand-off marker mechanism).
- A real host reboot, followed by re-verification that `sddm.service`
  starts correctly and automatically (`systemctl is-enabled` = enabled,
  `display-manager.service` correctly aliased), and a repeat of both the
  password and smartphone/passkey login tests after that reboot.
- `common-auth`, the `sudo` PAM stack, and the `sshd` PAM stack verified
  byte-for-byte unchanged (SHA-256) before, during, and after the entire
  cutover and reboot sequence.
- Removal of the prior prototype implementation's components (PAM
  module, broker, KWallet secret daemon, theme) and an unrelated,
  already-abandoned `greetd`-based prototype, without regressing any of
  the above.

## What is not yet validated

- Only one production host and one lab VM have been exercised - not
  multiple independent installs, hardware configurations, or Authelia
  versions within the supported range.
- No multi-user (`allowed_users` with more than one account)
  configuration has been exercised in production; the lab VM and
  production deployments documented above both use a single allowed
  user.
- Fresh, from-scratch installation by someone without prior knowledge of
  this project's development history has not been independently
  observed - `docs/installation.md` is audited for completeness (see
  `docs/testing.md`), but that is not a substitute for a truly
  independent first-time install.
