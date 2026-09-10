# Native theme (experimental, v1.9.0 Foundation)

This project now ships two SDDM theme options side by side:

- **Debian Breeze compatibility theme**
  (`/usr/share/sddm/themes/debian-breeze-authelia-passkey`) - the
  existing additive patch against the system's Debian Breeze theme.
  Fully supported, feature-complete, unaffected by anything below.
- **Native theme** (`/usr/share/sddm/themes/sddm-authelia-passkey-native`)
  - an original, from-scratch Qt6 theme. **Experimental and opt-in**
    as of v1.9.0 - not selected by package install/upgrade, not the
    default anywhere.

See `theme/native/README.md` and `theme/native/PROVENANCE.md` in the
repository for the theme's own scope statement and explicit provenance
(what was, and explicitly was not, used to build it).

## What v1.9.0 is

A **foundation** release: password login wired to the real
`sddm.login()`, real session selection, real user display with a safe
avatar fallback, real power actions gated by SDDM's own
`canSuspend`/`canReboot`/`canPowerOff`, a keyboard-layout affordance,
and a `Smartphone-Login` action.

## What v1.9.0 is not

The `Smartphone-Login` action opens a clearly-labelled **preview**
panel only - it does not talk to the broker, does not render a QR
code, and does not claim a login occurred. The full QR/device-code/
approval flow, matching the compatibility theme's existing behaviour,
is deferred to v1.10.0 (Native Theme Feature Parity). A switchable
multi-user list is also v1.10.0 scope - v1.9.0 shows only the
SDDM-selected/last user.

Responsive layout, accessibility hardening, and native branding
configuration (equivalent to the v1.8.0 compatibility-theme
`ui_brand_*` keys) are later releases in the same track - see the
private roadmap repository's `NATIVE-THEME-ROADMAP.md` (authoritative)
for the full v1.9.0 -> v2.0.0 plan.

## Trying it

The native theme is installed but not selected. To try it in a lab
environment (never on a production host with an active session):

```
sudo sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sddm-authelia-passkey-native
```

To make it SDDM's active theme (lab only), set
`Current=sddm-authelia-passkey-native` in `/etc/sddm.conf.d/10-theme.conf`
and restart `sddm.service`. This project does not do this
automatically at any point in the v1.9.0 -> v2.0.0 track; see
`NATIVE-THEME-ROADMAP.md`'s v2.0.0 section for the explicit,
user-approved cutover this eventually requires.

## Security

The native theme implements no authentication logic. It calls
`sddm.login(username, password, sessionIndex)` exactly as the
compatibility theme does; PAM remains the sole authentication
authority. See `docs/architecture.md` and `docs/security.md` for the
full model, unchanged by this theme.
