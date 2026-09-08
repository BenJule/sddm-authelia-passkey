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

## Steps

1. `scripts/preflight.sh` (read-only, safe to re-run)
2. Build: `cd src/broker && go build -o broker .`, likewise for
   `src/kwallet-secretd`, and `make -C src/pam`.
3. `sudo scripts/install.sh` - installs binaries/units, writes an example
   config if none exists, then calls `scripts/enable-pam.sh`.
4. Edit `/etc/sddm-authelia-passkey/config.conf` - at minimum
   `authelia_base_url`, `allowed_verification_host`, `allowed_users`.
5. `sudo scripts/postflight.sh`
6. `sudo systemctl enable --now sddm-authelia-passkey-broker.service`
7. (Optional) theme integration - see `theme/debian-breeze-authelia-passkey-patch/README.md`.
8. (Optional) KWallet auto-unlock - see `docs/kwallet.md`.
9. Log out, test a normal password login FIRST, then test Pixel login.
   If anything is wrong: `sudo scripts/rollback.sh`.

Nothing above restarts SDDM automatically - do that yourself when ready.
