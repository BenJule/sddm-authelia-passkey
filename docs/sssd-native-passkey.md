# Native SSSD passkey integration (v2.5.0 - investigation, not implemented)

**Status: investigation only. No code shipped in this milestone.** Per
the roadmap's own standing rule against fabricating hardware testing,
and the explicit constraint that no physical FIDO2/U2F device is
available in this environment, this document records a real,
VM124-verified investigation into what SSSD's native passkey support
would actually require - and a concrete, harder blocker found along the
way that goes beyond "no hardware to test with."

## Target architecture (unchanged direction)

```
SDDM -> PAM -> SSSD -> libfido2 -> hardware security key
```

Kept architecturally separate from this project's OIDC broker
(`docs/architecture.md`'s "Central architecture rule": SSSD/NSS is the
authoritative Unix identity, never duplicated). `docs/fido2.md`'s
existing `pam_u2f.so` stack addition is the current, shipped,
real-tested hardware-key path - this document is about a longer-term,
*different* mechanism (SSSD's own native passkey support), not a
replacement for it.

## What was actually verified on VM124 (lab, real Samba AD backend)

- **SSSD version**: `2.10.1-2+b1` (Debian 13/trixie). `sssd.conf`'s own
  man page (shipped by this exact package) documents real passkey
  config directives: `pam_passkey_auth`, `passkey_verification`,
  `passkey_debug_libfido2`, `passkey_child_timeout`, and
  `local_auth_policy` (with `match`/`only`/`enable:passkey` modes).
- **`local_auth_policy`'s own documented default-enablement table**:
  with the default `match` policy, Passkey is `disabled` for the `AD`
  backend by default (`enabled` only for `IPA`), while Smartcard is
  `enabled` for `AD`. VM124's actual domain config uses
  `id_provider = ldap` (schema=ad) against the real Samba AD DC, not
  SSSD's native `ad` provider - a nuance worth noting, since the
  documented table is written in terms of `id_provider` names.
- **Real test performed**: added `local_auth_policy = enable:passkey`
  to VM124's `/etc/sssd/sssd.conf` (backed up first), validated with
  `sssctl config-check` (0 issues both before and after), restarted
  `sssd`, and confirmed the existing real AD account resolution
  (`benlue`/`julia`/`sam` via `getent -s sss passwd`) was completely
  unaffected - a clean, reversible experiment with no regression.
  Reverted to the exact pre-change baseline afterward (diffed byte-
  identical) once the config-level finding below made further live
  testing pointless without upstream packaging changes.

## The actual blocker found (harder than "no hardware")

Beyond the well-known absence of a physical FIDO2 key in this
environment, real investigation on VM124 found that **Debian 13's SSSD
package build does not appear to include compiled passkey/FIDO2
support at all**, independent of hardware availability:

- `libfido2-1` (`1.15.0-1+b1`) *is* installed as a library, but
- `ldd /usr/lib/x86_64-linux-gnu/security/pam_sss.so` shows **no
  libfido2 linkage whatsoever** (only `libpam`, `libc`, `libaudit`,
  `libcap-ng`).
- No `passkey_child` helper binary exists anywhere on the system (the
  architecture SSSD uses for other privileged child-process work, and
  what `passkey_child_timeout`'s own documentation implies should
  exist).
- `sssd-tools` (`2.10.1-2+b1`, installed on VM124 for this
  investigation) ships no `sss_passkey_register` or any other
  passkey-enrollment tool.

This strongly suggests Debian's SSSD build disables the optional
libfido2 build-time dependency, even though the bundled man page
documents the full upstream config surface regardless of what a given
distribution actually compiled in - a common packaging situation, not
a bug in this project's own code or configuration.

## What this means for v2.5.0

Native SSSD passkey integration in this environment is blocked by two
independent factors, not one:

1. No physical FIDO2/U2F hardware available (the already-known,
   explicit constraint).
2. Debian 13's own SSSD package appears to lack compiled passkey
   support, so even a hypothetical hardware key could not be tested
   against this distribution's SSSD build without first either
   building SSSD from source with libfido2 support enabled, or waiting
   for an upstream Debian package change - neither of which is this
   project's own code to fix.

Closure status, honestly:

```
SSSD_PASSKEY_CONFIG_UNDERSTOOD=GREEN  (real investigation complete)
SSSD_PASSKEY_HARDWARE_TESTED=BLOCKED  (no device)
SSSD_PASSKEY_BUILD_AVAILABLE=NOT_AVAILABLE  (Debian 13 SSSD lacks libfido2 linkage)
SSSD_PASSKEY_IMPLEMENTED=NOT_IMPLEMENTED
```

## Recommendation

Continue recommending this project's existing, real, shipped
`pam_u2f.so` hardware-key path (`docs/fido2.md`) as the supported
mechanism for hardware security keys on Debian. Revisit native SSSD
passkey integration if/when either real FIDO2 hardware becomes
available *and* a passkey-capable SSSD build becomes available on the
target distribution - re-run the same `ldd`/`passkey_child` check
above first, since that fact could change with a future Debian point
release.
