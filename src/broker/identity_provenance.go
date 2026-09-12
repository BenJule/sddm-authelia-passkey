// identity_provenance.go closes a real gap found during v2.1.0's
// real-infrastructure validation (see docs/identity-binding.md): an
// ordinary NSS lookup (getpwnam, what userLookup already uses) silently
// prefers whichever source nsswitch.conf lists first when a username
// exists in more than one - there is no signal available from that
// single lookup about which source actually answered. A local
// /etc/passwd account can therefore silently shadow a same-named real
// directory (SSSD/AD) account, or vice versa.
//
// The reliable, non-heuristic way to tell them apart is to ask each NSS
// service directly, bypassing nsswitch.conf's merge order entirely -
// exactly what glibc's own `getent -s <service>` flag is for. This is
// not a new identity store and not a UID-range guess: it is the same
// authoritative signal nsswitch.conf's own dispatch logic is built on,
// just queried per-service instead of merged.
package main

import (
	"fmt"
	"os/exec"
	"strings"
)

// nssServiceEntry is the subset of a passwd(5) entry this broker needs
// from a single, service-restricted NSS query.
type nssServiceEntry struct {
	uid string
}

// nssServiceLookup asks exactly one NSS service for a passwd entry,
// never falling back to nsswitch.conf's configured merge order. A var
// so tests can stub it without needing real system accounts/SSSD.
//
// getent exits 2 both when the name is not found by that service and
// when the service itself is not registered on this system (e.g. no
// SSSD installed at all) - both cases are treated identically here as
// "no entry from this source", which is the safe interpretation either
// way: reject_local_shadowing has nothing to compare without an sss
// entry, and required_identity_source=sssd correctly still refuses
// when SSSD isn't even present.
var nssServiceLookup = func(service, username string) (*nssServiceEntry, error) {
	out, err := exec.Command("getent", "-s", service, "passwd", username).Output()
	if err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 2 {
			return nil, nil
		}
		return nil, err
	}

	fields := strings.SplitN(strings.TrimSpace(string(out)), ":", 4)
	if len(fields) < 3 {
		return nil, fmt.Errorf("unexpected getent -s %s passwd output shape", service)
	}
	return &nssServiceEntry{uid: fields[2]}, nil
}

// checkIdentityProvenance applies RejectLocalShadowing/
// RequiredIdentitySource. Only ever consulted when AccountSource is
// "nss" (config.go's Validate() refuses both settings otherwise), and
// is a no-op - no subprocess calls at all - when neither is configured,
// so a config that doesn't opt in sees zero behavior change.
func checkIdentityProvenance(username string) error {
	if !cfg.RejectLocalShadowing && cfg.RequiredIdentitySource == "" {
		return nil
	}

	filesEntry, err := nssServiceLookup("files", username)
	if err != nil {
		return fmt.Errorf("files identity-source lookup failed: %w", err)
	}
	sssEntry, err := nssServiceLookup("sss", username)
	if err != nil {
		return fmt.Errorf("sss identity-source lookup failed: %w", err)
	}

	if cfg.RequiredIdentitySource == "sssd" && sssEntry == nil {
		return fmt.Errorf("required_identity_source=sssd but %q does not resolve via the sss NSS service", username)
	}

	if cfg.RejectLocalShadowing && filesEntry != nil && sssEntry != nil && filesEntry.uid != sssEntry.uid {
		return fmt.Errorf("SECURITY: local/directory identity collision for %q (files uid=%s, sss uid=%s) - refusing per reject_local_shadowing", username, filesEntry.uid, sssEntry.uid)
	}

	return nil
}
