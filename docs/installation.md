# Installation

## Supported platform

Officially supported and tested:

- Debian 13 (Trixie)
- SDDM 0.21.x
- KDE Plasma 6
- Authelia 4.39+ (OIDC provider with Device Authorization Grant support)
- systemd 257+

Anything else (other distributions, other display managers, older
Authelia/systemd) is **unsupported/experimental**. `scripts/preflight.sh`
and `scripts/enable-pam.sh` will tell you plainly if your system's PAM
stack doesn't match a shape this project can safely patch, and refuse
rather than guess (`PAM_INSTALL=REFUSED`).

## Authelia configuration

Add an OIDC client for the Device Authorization Grant, e.g. (Authelia
`configuration.yml`):

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: pam-authelia
        client_name: "PAM Device Login"
        public: true
        authorization_policy: two_factor
        scopes: [openid]
        grant_types: [urn:ietf:params:oauth:grant-type:device_code]
        response_types: []
```

`authorization_policy: two_factor` combined with
`experimental_enable_passkey_uv_two_factors: true` (Authelia global
config) is what makes a Passkey/WebAuthn user-verification tap alone
satisfy this policy - check Authelia's own docs for the exact option
name in your version, this changes between releases.

## Package install (recommended)

Download the `.deb`, `SHA256SUMS`, and `SHA256SUMS.asc` for the release
you want from
[GitHub Releases](https://github.com/BenJule/sddm-authelia-passkey/releases),
then verify before installing - see `docs/release-signing.md` for the
full verification commands (import the signing key, `gpg --verify
SHA256SUMS.asc SHA256SUMS`, `sha256sum -c SHA256SUMS`).

1. `sudo apt install ./sddm-authelia-passkey_X.Y.Z-1_amd64.deb` -
   installs the broker, `kwallet-secretd`, PAM module, and systemd units,
   and generates `debian-breeze-authelia-passkey` from Debian's installed
   pristine Breeze theme plus this project's additive patches.
   Writes `/etc/sddm-authelia-passkey/config.conf.example` but does
   **not** create `config.conf`, and does **not** touch
   `/etc/pam.d/sddm` - see the package's own `postinst` message for the
   exact next-step commands, repeated below.
2. Create and edit `/etc/sddm-authelia-passkey/config.conf` (copy from
   `config.conf.example`) - at minimum `authelia_base_url`,
   `allowed_verification_host`, `allowed_users`.
3. `sudo /usr/share/sddm-authelia-passkey/preflight.sh` (read-only, safe
   to re-run)
4. `sudo /usr/share/sddm-authelia-passkey/enable-pam.sh` - the only step
   that writes `/etc/pam.d/sddm`; refuses rather than guesses if your
   `common-auth` doesn't match the expected pam-auth-update shape.
5. `sudo systemctl enable --now sddm-authelia-passkey-broker.service`
   (and `sddm-authelia-passkey-kwallet-secretd.service` too, if you plan
   to use KWallet auto-unlock).
6. `sudo /usr/share/sddm-authelia-passkey/postflight.sh`
7. Select `debian-breeze-authelia-passkey` as the SDDM theme if not already selected.
   The package never restarts SDDM automatically.
8. (Optional) KWallet auto-unlock - see `docs/kwallet.md`.
9. Log out, test a normal password login FIRST, then test smartphone/passkey login.
   If anything is wrong: `sudo /usr/share/sddm-authelia-passkey/rollback.sh`.

Nothing above restarts SDDM automatically - do that yourself when ready.

## Optional features (all off by default)

- **NSS/LDAP/Active Directory accounts** (`account_source=nss`) instead
  of a fixed local `allowed_users` list - see `docs/configuration.md`'s
  "account_source=nss" section.
- **Native FIDO2/U2F hardware security keys** (YubiKey, Nitrokey,
  SoloKey, ...), optionally restricted to a group - see `docs/fido2.md`.
- **A generic OIDC provider** (`provider_kind=oidc`) instead of Authelia
  - Keycloak, Authentik, or any other provider publishing an OIDC
  discovery document - see `docs/architecture.md`'s "Provider
  abstraction" section.

`sudo /usr/sbin/sddm-authelia-passkey-admin test-config` validates
`config.conf` at any point without starting anything, and
`... status` reports whether the broker/sddm/kwallet-secretd stack is
currently up - see `docs/rollback.md` for the full admin CLI reference.

Already have this project installed and want to move to a newer
release instead of a fresh install? See `docs/upgrade.md`. Have
accessibility needs (screen reader, keyboard-only)? See
`docs/accessibility.md`.

- **Native SDDM theme** (experimental, opt-in, not selected by
  install/upgrade) - an original from-scratch Qt6 theme installed
  alongside the compatibility theme. Foundation-level as of v1.9.0 -
  see `docs/native-theme.md`.

## Build from source (alternative)

1. `scripts/preflight.sh` (read-only, safe to re-run)
2. Build: `cd src/broker && go build -trimpath -o broker .`, likewise for
   `src/kwallet-secretd`, and `make -C src/pam`.
3. `sudo scripts/install.sh` - installs binaries/units, writes an example
   config if none exists, then calls `scripts/enable-pam.sh`.
4. Edit `/etc/sddm-authelia-passkey/config.conf` - at minimum
   `authelia_base_url`, `allowed_verification_host`, `allowed_users`.
5. `sudo scripts/postflight.sh`
6. `sudo systemctl enable --now sddm-authelia-passkey-broker.service`
7. (Optional) theme integration - see `theme/debian-breeze-authelia-passkey-patch/README.md`.
8. (Optional) KWallet auto-unlock - see `docs/kwallet.md`.
9. Log out, test a normal password login FIRST, then test smartphone/passkey login.
   If anything is wrong: `sudo scripts/rollback.sh`.

Nothing above restarts SDDM automatically - do that yourself when ready.
