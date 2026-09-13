# Native SSSD passkey integration (v2.5.0 investigation, corrected 2026-09-13)

**Status: package capability verified; end-to-end native SSSD passkey authentication not yet validated.** No broker-owned FIDO2 implementation is introduced here. The architectural direction remains:

```
SDDM -> PAM -> SSSD -> libfido2 -> hardware security key
```

This path is deliberately separate from the OIDC broker. `docs/fido2.md` documents the project's currently shipped `pam_u2f.so` hardware-key path; native SSSD passkey support is a different, longer-term mechanism.

## Original investigation

The first VM124 investigation correctly identified SSSD's passkey configuration surface (`pam_passkey_auth`, `passkey_verification`, `passkey_debug_libfido2`, `passkey_child_timeout`, and `local_auth_policy`) and proved that temporarily adding `local_auth_policy = enable:passkey` did not break the existing Samba AD / SSSD identity resolution. That configuration experiment was reverted to the pre-test baseline.

However, the original packaging conclusion was wrong. The investigation checked `pam_sss.so` for direct `libfido2` linkage and searched for `passkey_child`, then concluded that Debian 13's SSSD build lacked passkey support. Debian actually ships native passkey support as a **split package**, `sssd-passkey`. `pam_sss.so` is therefore not expected to link to `libfido2` directly; the FIDO2 work is delegated to the helper from that split package.

## Corrected package validation on VM124

A follow-up validation on the real Debian 13 (Trixie) lab VM established:

- Debian repository candidate: `sssd-passkey 2.10.1-2+b1`.
- `sssd-passkey 2.10.1-2+b1` was **already installed** on VM124.
- `/usr/libexec/sssd/passkey_child` exists and is executable.
- `/usr/lib/x86_64-linux-gnu/sssd/modules/sssd_krb5_passkey_plugin.so` exists.
- `dpkg -L sssd-passkey` confirms that the package owns `passkey_child`.
- `ldd /usr/libexec/sssd/passkey_child` shows real linkage to `libfido2.so.1` as well as the expected crypto/JSON runtime libraries.
- `libfido2-1` is installed.
- `dpkg -V sssd-passkey` returned cleanly.
- the SSSD service remained active throughout the read-only package verification.
- `/etc/pam.d/sddm` was SHA-256 identical before and after the run.

The attempted SHA-256 comparison of `/etc/sssd/sssd.conf` in that specific follow-up run was **inconclusive**, because the unprivileged hash operation was denied both before and after. It must therefore not be cited as byte-for-byte evidence. The run did not edit `sssd.conf`, and because `sssd-passkey` was already installed it also performed no package installation or SSSD configuration migration.

## What is now resolved

The earlier package-level blocker is resolved:

```
DEBIAN_SSSD_PASSKEY_PACKAGE=GREEN
PASSKEY_CHILD=GREEN
PASSKEY_CHILD_LIBFIDO2=GREEN
SSSD_SERVICE_ACTIVE=GREEN
PACKAGE_INTEGRITY=GREEN
SSDM_PAM_UNCHANGED=GREEN
```

The previous statement that Debian 13 lacked compiled SSSD passkey/libfido2 support is superseded by this correction.

## What remains unvalidated

This correction does **not** claim an end-to-end native SSSD passkey login. That requires real passkey/FIDO2 hardware and a real enrollment/authentication exercise through the target SSSD identity path. The separate physical-hardware closure gate is tracked by GitHub issue #87.

There is also an identity-provider nuance: the validated Samba AD lab configuration historically used `id_provider = ldap` with AD schema rather than SSSD's native `ad` provider. SSSD's documented `local_auth_policy` defaults differ by provider, so any future native-passkey production design must validate the exact provider/domain configuration instead of assuming IPA/AD defaults apply unchanged.

## Recommendation

Continue to treat the shipped `pam_u2f.so` integration as the project's currently supported hardware-key mechanism until issue #87 is completed with physical hardware. Native SSSD passkey support on Debian 13 is no longer blocked by package availability, but it remains a separate path that needs real enrollment and login evidence before it can be called end-to-end validated.
