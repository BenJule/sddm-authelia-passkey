# Release signing

## Key

Fingerprint: `96D8CF4E27A30719930EC28973F9432144634D95` (a signing-capable
subkey of the primary key registered on the maintainer's GitHub account;
UID `Benjamin Lütker <benjamin.luetker@gmail.com>`).

## Tag signing

Every release tag is an annotated, GPG-signed tag:

```
git tag -s vX.Y.Z <commit> -m "sddm-authelia-passkey vX.Y.Z"
```

Verify locally:

```
git tag -v vX.Y.Z
```

GitHub shows the tag as "Verified" when the signature is valid, the
signing key (or its primary key) is registered on the tagger's GitHub
account, and the tagger email is both a UID on that key and associated
with the account.

## Artifact signing

Release artifacts (`.deb`, `.changes`, `.buildinfo`) are accompanied by:

- `SHA256SUMS` - checksums of every release artifact, by filename only.
- `SHA256SUMS.asc` - detached armored signature over `SHA256SUMS`.
- `<artifact>.asc` - a detached armored signature for the Debian package
  itself (and optionally other artifacts), independent of `SHA256SUMS`.

Produced with:

```
sha256sum <artifacts...> > SHA256SUMS
gpg --local-user 96D8CF4E27A30719930EC28973F9432144634D95 --armor --detach-sign SHA256SUMS
gpg --local-user 96D8CF4E27A30719930EC28973F9432144634D95 --armor --detach-sign sddm-authelia-passkey_X.Y.Z-1_amd64.deb
```

## Verifying a release as a user

```
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
gpg --verify sddm-authelia-passkey_X.Y.Z-1_amd64.deb.asc sddm-authelia-passkey_X.Y.Z-1_amd64.deb
```

Import the signing key first if you don't already have it:

```
gpg --keyserver keys.openpgp.org --recv-keys 96D8CF4E27A30719930EC28973F9432144634D95
```

## Repository defaults

This repository's local git config sets `commit.gpgsign=true` and
`tag.gpgsign=true` - every commit and tag made in this working copy from
here on is signed automatically. This applies going forward only; the
commits that made up the original `v0.1.0` release were not individually
signed (only the tag itself was, after the fact) and are not rewritten
retroactively.
