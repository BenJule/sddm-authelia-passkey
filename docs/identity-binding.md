# Identity binding & local-shadowing protection (v2.2)

**Status: implemented in v2.2.0** (`reject_local_shadowing`,
`required_identity_source` config keys; `checkIdentityProvenance()` in
`src/broker/identity_provenance.go`, wired into `authorizeAccount()` for
`account_source=nss`). This document originally analyzed a real gap
found during v2.1.0's real-infrastructure validation; the "Candidate
config surface" section below is now the shipped surface for the first
two keys. `expected_directory_domain` remains design-only, deferred to
a later milestone (see "Explicitly out of scope" at the end).

## The finding

`account_source=nss` resolves a username via the C library's ordinary
NSS dispatch (`getpwnam`/`os/user.Lookup`), which - per
`/etc/nsswitch.conf`'s `passwd: files sss` order - always prefers a
**local** `/etc/passwd` entry over a directory (SSSD/AD) entry with the
same username, silently. On the real v2.1.0 lab VM (VM124):

```
$ getent passwd benlue          # unqualified - "files" wins silently
benlue:x:1000:1000:Debian:/home/benlue:/bin/bash

$ getent -s files passwd benlue # explicitly local
benlue:x:1000:1000:Debian:/home/benlue:/bin/bash

$ getent -s sss passwd benlue   # explicitly directory (Samba AD)
benlue:*:10000:10001:BenLue:/home/benlue:/bin/bash
```

Same username, two different real accounts (`uid=1000` local vs.
`uid=10000` in Active Directory), and the broker's ordinary NSS lookup
has no way to tell you got the "wrong" one - it just gets whichever
`getpwnam("benlue")` returns, per libc's own configured order. This is
not `sddm-authelia-passkey`-specific; it's inherent to how NSS works
whenever a name exists in more than one configured source. It was found
by testing against a real Samba AD domain in v2.1.0's lab validation
(`sam`/`julia`, which have no local counterpart, were used to prove the
real NSS/SSSD/`account_source=nss` path instead, precisely to sidestep
this collision - see `docs/validated-environment.md`).

**Not changed in this run**: the local `benlue`/AD `benlue` pair on
VM124 itself. No `userdel`/`usermod`/UID renumbering/NSS reordering was
performed - this is a lab-VM fact to design around, not something to
silently "fix" by mutating accounts.

## Why a heuristic is the wrong fix

A tempting shortcut - "if UID >= some threshold, assume it's the
directory account" - is exactly the kind of fragile heuristic this
project's own conventions reject. UID ranges are an operator/domain
convention (`minimum_uid` already exists as one, for a different
purpose: excluding system accounts), not a reliable signal for *which
NSS module* answered. It breaks the moment UID ranges change, differ
between environments, or a local account happens to be provisioned
above the threshold.

## The reliable mechanism: NSS service-scoped queries

glibc's `getent` (and the underlying NSS `nss_*` per-service query
mechanism it wraps) supports **restricting a lookup to one specific NSS
service**, bypassing `nsswitch.conf`'s configured merge order entirely:

```
getent -s files passwd <name>   # ask ONLY the local /etc/passwd source
getent -s sss   passwd <name>   # ask ONLY SSSD (whatever domains it manages)
```

This is not a heuristic - it is asking each real backend directly and
comparing the *actual* answers, the same authoritative signal
`nsswitch.conf`'s merge logic itself is built on. Given a resolved
username, the direction for v2.2 is:

1. When `account_source=nss`, additionally query `files` and `sss`
   independently for the exact requested username.
2. If **both** resolve and their UIDs (or any other identity-relevant
   field) **disagree**, that is a proven collision, not a guess - fail
   closed rather than silently trusting whichever one `getpwnam`
   happened to prefer.
3. If only `sss` resolves, proceed normally (the common, unambiguous
   case - e.g. `julia`/`sam` in the v2.1.0 validation).
4. If only `files` resolves, `account_source=nss`'s existing semantics
   already apply as today (a `files`-only account is still eligible,
   subject to `minimum_uid`/`deny_users`/`allowed_groups` exactly as
   now) - this case does not change.

## Config surface (v2.2.0)

Two knobs shipped in v2.2.0, both only consulted when
`account_source=nss`, both off/empty by default (zero behavior change
unless opted in):

- `reject_local_shadowing=true` - refuse (fail closed) any username
  that resolves in *both* `files` and `sss` with disagreeing UID,
  regardless of which one ordinary `getpwnam` would have preferred.
  This directly closes the finding above. Same UID from both sources,
  directory-only, or local-only are all still allowed - only a genuine
  disagreement is refused.
- `required_identity_source=sssd` - a stricter mode: refuse a username
  at all unless it resolves via `sss` specifically, independent of
  whether a `files` entry also exists. Useful for deployments that want
  the directory to be the *only* source of truth for the passwordless
  path, full stop. The only accepted value; anything else is rejected
  at config-load time.

Both settings are independent and can be combined. Neither is accepted
when `account_source=local` (rejected at config-load time, since
`account_source=local` never consults NSS at all). A lookup failure on
either NSS service fails closed (an error, never treated as "no
collision").

Implementation: `checkIdentityProvenance(username)` in
`src/broker/identity_provenance.go` shells out to `getent -s <service>
passwd <username>` for `files` and `sss` independently (a `var` func,
`nssServiceLookup`, stubbed in tests) - not a new identity store, just
the same authoritative per-service NSS query described above, called
from Go instead of a shell one-liner.

Deferred to a later milestone, not part of v2.2.0:

- `expected_directory_domain=ad.s3-dev.ovh` - for a future multi-domain
  SSSD configuration (v2.6 Multi-IdP direction), pin eligibility to a
  specific SSSD domain rather than "any domain SSSD happens to serve" -
  not required for the single-domain case validated against here.

None of this changes `account_source=local`'s behavior, and none of it
requires a new UID/GID store of this project's own - it only ever
*asks* NSS/SSSD more precisely than a bare `getpwnam` does, per this
project's standing architecture rule that SSSD/NSS stays the
authoritative Unix identity source (see `docs/architecture.md`).

## Explicitly out of scope for v2.2.0

- Renumbering, renaming, or otherwise mutating any existing local or
  directory account (the real `benlue` local/AD collision on VM124 was
  never touched to build or validate this feature).
- A new identity cache/store maintained by the broker itself.
- Implicit fallback: this is about **detecting and refusing** an
  ambiguous match, never about silently picking one of two candidates
  by some new rule.
- Case/domain/realm normalization, `expected_directory_domain`,
  explain-output for identity binding decisions, and a dedicated
  privacy boundary for provenance logging - all remain open items for a
  later milestone.
