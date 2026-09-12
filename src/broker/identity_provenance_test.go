package main

import (
	"fmt"
	"testing"
)

// withStubNSSServiceLookup replaces nssServiceLookup with fixed,
// in-memory per-service data - entries[service][username] = uid (empty
// string entries are not supported; omit the username entirely to mean
// "not found by that service", matching real getent -s exit-2
// semantics). calls records every (service, username) pair actually
// queried, so a test can assert checkIdentityProvenance's short-circuit
// (neither setting configured) makes zero calls.
func withStubNSSServiceLookup(t *testing.T, entries map[string]map[string]string) *[]string {
	t.Helper()
	prev := nssServiceLookup
	calls := []string{}
	nssServiceLookup = func(service, username string) (*nssServiceEntry, error) {
		calls = append(calls, service+":"+username)
		uid, ok := entries[service][username]
		if !ok {
			return nil, nil
		}
		return &nssServiceEntry{uid: uid}, nil
	}
	t.Cleanup(func() { nssServiceLookup = prev })
	return &calls
}

func provenanceBaseConfig() {
	cfg.AccountSource = "nss"
	cfg.MinimumUID = 1000
	cfg.DenyUsers = map[string]bool{"root": true}
	cfg.AllowedGroups = map[string]bool{}
	cfg.RequireGroupMatch = false
	cfg.AllowedUsers = map[string]bool{}
	cfg.RejectLocalShadowing = false
	cfg.RequiredIdentitySource = ""
}

// --- checkIdentityProvenance: short-circuit when neither setting is
// configured (zero behavior/performance change for existing users) ---

func TestCheckIdentityProvenance_NeitherSettingConfigured_NoLookupsPerformed(t *testing.T) {
	provenanceBaseConfig()
	calls := withStubNSSServiceLookup(t, map[string]map[string]string{})

	if err := checkIdentityProvenance("anyone"); err != nil {
		t.Fatalf("unexpected error with neither setting configured: %v", err)
	}
	if len(*calls) != 0 {
		t.Fatalf("expected zero NSS service lookups when neither setting is configured, got %v", *calls)
	}
}

// --- reject_local_shadowing ---------------------------------------------

func TestCheckIdentityProvenance_RejectShadowing_RealCollisionDenied(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"benlue": "1000"},
		"sss":   {"benlue": "10000"},
	})

	if err := checkIdentityProvenance("benlue"); err == nil {
		t.Fatal("expected rejection of a real local/directory UID collision")
	}
}

func TestCheckIdentityProvenance_RejectShadowing_SameUIDBothSourcesAllowed(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"alice": "1001"},
		"sss":   {"alice": "1001"},
	})

	if err := checkIdentityProvenance("alice"); err != nil {
		t.Fatalf("same UID from both sources is not a collision: %v", err)
	}
}

func TestCheckIdentityProvenance_RejectShadowing_DirectoryOnlyAllowed(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"sss": {"julia": "10002"},
	})

	if err := checkIdentityProvenance("julia"); err != nil {
		t.Fatalf("a directory-only account (no local shadow) must be allowed: %v", err)
	}
}

func TestCheckIdentityProvenance_RejectShadowing_LocalOnlyAllowed(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"localonly": "2000"},
	})

	if err := checkIdentityProvenance("localonly"); err != nil {
		t.Fatalf("a local-only account (no directory entry to collide with) must be allowed: %v", err)
	}
}

func TestCheckIdentityProvenance_RejectShadowing_NeitherSourceHasEntry(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{})

	if err := checkIdentityProvenance("nobody"); err != nil {
		t.Fatalf("no entry from either source is not itself a collision: %v", err)
	}
}

// --- required_identity_source=sssd --------------------------------------

func TestCheckIdentityProvenance_RequiredSourceSSSD_DirectoryAccountAllowed(t *testing.T) {
	provenanceBaseConfig()
	cfg.RequiredIdentitySource = "sssd"
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"sss": {"julia": "10002"},
	})

	if err := checkIdentityProvenance("julia"); err != nil {
		t.Fatalf("an sss-resolved account must be allowed: %v", err)
	}
}

func TestCheckIdentityProvenance_RequiredSourceSSSD_LocalOnlyDenied(t *testing.T) {
	provenanceBaseConfig()
	cfg.RequiredIdentitySource = "sssd"
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"localonly": "2000"},
	})

	if err := checkIdentityProvenance("localonly"); err == nil {
		t.Fatal("a files-only account must be denied when required_identity_source=sssd")
	}
}

func TestCheckIdentityProvenance_RequiredSourceSSSD_LocalShadowOfDirectoryAccountStillAllowed(t *testing.T) {
	// required_identity_source=sssd only asks "does sss resolve this
	// name at all" - it does not by itself detect a UID mismatch
	// against a co-existing local entry. That is reject_local_shadowing's
	// job; the two settings are independent and can be combined.
	provenanceBaseConfig()
	cfg.RequiredIdentitySource = "sssd"
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"benlue": "1000"},
		"sss":   {"benlue": "10000"},
	})

	if err := checkIdentityProvenance("benlue"); err != nil {
		t.Fatalf("required_identity_source=sssd alone must not itself flag the UID mismatch: %v", err)
	}
}

func TestCheckIdentityProvenance_BothSettingsCombined_CollisionDenied(t *testing.T) {
	provenanceBaseConfig()
	cfg.RequiredIdentitySource = "sssd"
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"benlue": "1000"},
		"sss":   {"benlue": "10000"},
	})

	if err := checkIdentityProvenance("benlue"); err == nil {
		t.Fatal("combining both settings must still deny a real collision")
	}
}

// --- lookup failure propagation (fail closed, never "assume no
// restriction") ----------------------------------------------------------

func TestCheckIdentityProvenance_LookupErrorPropagates(t *testing.T) {
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	prev := nssServiceLookup
	nssServiceLookup = func(service, username string) (*nssServiceEntry, error) {
		return nil, fmt.Errorf("simulated NSS backend failure")
	}
	t.Cleanup(func() { nssServiceLookup = prev })

	if err := checkIdentityProvenance("anyone"); err == nil {
		t.Fatal("an NSS service lookup failure must fail closed, not be treated as no collision")
	}
}

// --- end-to-end through authorizeAccount --------------------------------

func TestAuthorizeAccount_NSSMode_RejectShadowing_DeniesRealCollision(t *testing.T) {
	resetLimiterState(t)
	withStubUserLookup(t, map[string]string{"benlue": "1000"})
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"files": {"benlue": "1000"},
		"sss":   {"benlue": "10000"},
	})

	if _, err := authorizeAccount("benlue"); err == nil {
		t.Fatal("authorizeAccount must deny a username with a real local/directory UID collision when reject_local_shadowing=true")
	}
}

func TestAuthorizeAccount_NSSMode_RejectShadowing_AllowsCleanDirectoryAccount(t *testing.T) {
	resetLimiterState(t)
	withStubUserLookup(t, map[string]string{"julia": "10002"})
	provenanceBaseConfig()
	cfg.RejectLocalShadowing = true
	withStubNSSServiceLookup(t, map[string]map[string]string{
		"sss": {"julia": "10002"},
	})

	if _, err := authorizeAccount("julia"); err != nil {
		t.Fatalf("authorizeAccount must allow a clean directory-only account: %v", err)
	}
}

// --- config validation ---------------------------------------------------

func TestLoadConfig_RejectLocalShadowing_RequiresNSSMode(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
account_source=local
allowed_users=alice
reject_local_shadowing=true
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("reject_local_shadowing=true with account_source=local must be rejected at load time")
	}
}

func TestLoadConfig_RequiredIdentitySource_RequiresNSSMode(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
account_source=local
allowed_users=alice
required_identity_source=sssd
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("required_identity_source with account_source=local must be rejected at load time")
	}
}

func TestLoadConfig_RequiredIdentitySource_RejectsUnknownValue(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
account_source=nss
minimum_uid=1000
require_group_match=false
required_identity_source=ldap
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("required_identity_source must only accept \"\" or \"sssd\"")
	}
}

func TestLoadConfig_RejectLocalShadowing_ValidNSSConfigAccepted(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
account_source=nss
minimum_uid=1000
require_group_match=false
reject_local_shadowing=true
required_identity_source=sssd
`)
	c, err := LoadConfig(p)
	if err != nil {
		t.Fatalf("valid nss config with both settings must be accepted: %v", err)
	}
	if !c.RejectLocalShadowing || c.RequiredIdentitySource != "sssd" {
		t.Fatalf("parsed config does not reflect the configured values: %+v", c)
	}
}
