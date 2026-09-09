# Internal APT repository

Signed `.deb` builds of `sddm-authelia-passkey` are additionally
published to an internal APT repository for Debian 13 (Trixie), shared
with (but isolated from) an existing internal BambuStudio APT
repository on the same host.

## Using it

```
curl -fsSL https://apt.s3-dev.ovh/trixie-KEY.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/sddm-authelia-passkey-repo.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/sddm-authelia-passkey-repo.gpg] https://apt.s3-dev.ovh trixie main" | sudo tee /etc/apt/sources.list.d/sddm-authelia-passkey.list
sudo apt update
sudo apt install sddm-authelia-passkey
```

This is a convenience mirror of the same signed `.deb` published on
[GitHub Releases](https://github.com/BenJule/sddm-authelia-passkey/releases) -
see `docs/release-signing.md` for how to verify the artifact directly
instead, if preferred.

## Publishing architecture

```
GitHub Release published (or workflow_dispatch with an explicit tag)
        |
.github/workflows/cd-deploy-apt.yml
  - verifies the release/tag is not a draft and is GitHub-verified
  - downloads exactly one sddm-authelia-passkey_*_amd64.deb + SHA256SUMS(.asc)
  - verifies the maintainer's detached GPG signature and checksum
  - verifies Package/Architecture via dpkg-deb
        |
SSH (forced command only, dedicated restricted key)
        |
apt-deploy@<apt server>: /usr/local/sbin/publish-sddm-authelia-passkey
  - re-validates the uploaded .deb itself (Package/Architecture/Version)
  - adds it to pool/main/s/sddm-authelia-passkey/ (never deletes older versions)
  - regenerates dists/trixie's Packages/Packages.gz/Release/InRelease/Release.gpg
  - signs with the repository's own dedicated GPG key
  - writes are atomic (temp files, renamed into place only once complete)
```

**Trust boundaries:**

- The GitHub Actions workflow only ever has the *public* maintainer key
  (to verify signatures) - never the private release-signing key.
- The repository's own GPG signing key (which signs `dists/trixie`'s
  `Release`/`InRelease`) lives exclusively on the APT server, owned by
  the unprivileged `apt-deploy` account. It is never exported, never
  copied into GitHub, and CI has no way to read it.
- `apt-deploy`'s SSH key is restricted with a forced command
  (`command="/usr/local/sbin/publish-sddm-authelia-passkey",restrict` in
  `authorized_keys`) - it can execute exactly that one script and
  nothing else, with no PTY/agent/X11/port forwarding.
- `apt-deploy` owns only `dists/trixie` and `pool/main/s/`
  (this project's own pool letter) on the shared repository - it has no
  access to the existing BambuStudio `stable`/`nightly` distributions or
  their `pool/main/b/` tree, which remain owned by a different account.
- The publisher script re-validates the package independently of CI
  (never trusts that the uploaded bytes are what CI claims), uses
  `flock` so two concurrent publishes cannot corrupt the metadata, and
  activates new `Packages`/`Release`/`InRelease`/`Release.gpg` files
  atomically (via `mv`, only after everything validated and signed
  successfully) so a failed run never leaves the repository serving a
  half-written index.
- Re-publishing an already-published version is a safe no-op (byte
  comparison against the existing pool file) rather than an error or a
  silent overwrite with different content.
