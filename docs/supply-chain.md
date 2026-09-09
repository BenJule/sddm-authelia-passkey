# Supply chain

## SBOM

`release-build.yml` (manual `workflow_dispatch`) generates a CycloneDX
SBOM per Go module (`broker.cdx.json`, `kwallet-secretd.cdx.json`) using
[`cyclonedx-gomod`](https://github.com/CycloneDX/cyclonedx-gomod),
uploaded as a build artifact alongside the `.deb`. Not yet attached to
GitHub releases as a signed asset - see `docs/release-signing.md` for
the current manual release process; adding SBOM signing to that process
is a reasonable next step, not yet done.

## Reproducible builds

**Not currently verified.** `dpkg-buildpackage` is run with `-trimpath`
for the Go binaries (removes the local build path from embedded stack
traces) and `SOURCE_DATE_EPOCH` is not currently pinned. No bit-for-bit
reproducibility check (building twice and diffing the `.deb`) has been
performed. This is an honest gap, not a claim - do not assume
reproducibility until this has actually been tested and documented.

## Provenance

Release artifacts are built manually by the maintainer (see
`docs/release-signing.md`) from a signed, tagged commit, then GPG-signed
directly - not via GitHub Actions, deliberately, to avoid putting a
long-lived private signing key into CI. There is currently no SLSA
provenance attestation; the trust chain is: signed git tag -> commit
that verifiably matches -> locally-built `.deb` -> detached GPG
signature over the `.deb` and over `SHA256SUMS`.

## Dependencies

- Go module dependencies: see `src/broker/go.sum` and
  `src/kwallet-secretd/go.sum`. Dependabot (`.github/dependabot.yml`)
  keeps these and GitHub Actions dependencies current on a weekly
  cadence. `govulncheck` runs in CI (`security.yml`) against both
  modules.
- No vendored third-party C/C++ code in `src/pam` - only the system
  `libpam` (via `-lpam`), linked, not vendored.
- The theme integration ships as patches against the Debian-packaged
  `sddm-theme-debian-breeze` (KDE, GPL/LGPL) - no KDE source is vendored
  or built from this repository.
