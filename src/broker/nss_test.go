package main

import (
	"fmt"
	"os/user"
	"testing"
)

// withStubGroups replaces groupIDsForUser/lookupGroupName with fixed,
// in-memory data - gidsByUser maps username to its list of numeric GIDs
// (as strings, matching user.User.Gid's own type), and groupNameByGID
// maps a numeric GID string to the group name NSS would resolve it to.
func withStubGroups(t *testing.T, gidsByUser map[string][]string, groupNameByGID map[string]string) {
	t.Helper()
	prevGids := groupIDsForUser
	prevNames := lookupGroupName
	groupIDsForUser = func(u *user.User) ([]string, error) {
		gids, ok := gidsByUser[u.Username]
		if !ok {
			return nil, fmt.Errorf("no stub group data for %q", u.Username)
		}
		return gids, nil
	}
	lookupGroupName = func(gid string) (string, error) {
		name, ok := groupNameByGID[gid]
		if !ok {
			return "", fmt.Errorf("no stub group name for gid %q", gid)
		}
		return name, nil
	}
	t.Cleanup(func() {
		groupIDsForUser = prevGids
		lookupGroupName = prevNames
	})
}

func nssBaseConfig() {
	cfg.AccountSource = "nss"
	cfg.MinimumUID = 1000
	cfg.DenyUsers = map[string]bool{"root": true}
	cfg.AllowedGroups = map[string]bool{}
	cfg.RequireGroupMatch = true
	cfg.AllowedUsers = map[string]bool{}
}

// --- local mode: unchanged v0.1-v0.4 behavior --------------------------

func TestAuthorizeAccount_LocalMode_AllowedUserPositive(t *testing.T) {
	resetLimiterState(t)
	withStubUserLookup(t, map[string]string{"alice": "1001"})
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true}

	u, err := authorizeAccount("alice")
	if err != nil || u == nil {
		t.Fatalf("got err=%v, want a local allowed user to be authorized", err)
	}
}

func TestAuthorizeAccount_LocalMode_NotInAllowedUsersRejected(t *testing.T) {
	resetLimiterState(t)
	withStubUserLookup(t, map[string]string{"alice": "1001", "mallory": "1003"})
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true}

	if _, err := authorizeAccount("mallory"); err == nil {
		t.Fatal("mallory is not in allowed_users, must be rejected even though NSS resolves her fine")
	}
}

// --- nss mode: positive cases --------------------------------------------

func TestAuthorizeAccount_NSSMode_LDAPLikeUserPositive(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	// Simulates an SSSD/LDAP-resolved account: nothing distinguishes it
	// from a local one at this layer, which is the point - the broker
	// never talks to LDAP itself, NSS already did the work.
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})

	u, err := authorizeAccount("jsmith")
	if err != nil || u == nil {
		t.Fatalf("got err=%v, want an NSS-resolved account above minimum_uid to be authorized", err)
	}
}

func TestAuthorizeAccount_NSSMode_AllowedGroupPositive(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.AllowedGroups = map[string]bool{"linux-login": true}
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})
	withStubGroups(t,
		map[string][]string{"jsmith": {"10042", "5000"}},
		map[string]string{"10042": "jsmith", "5000": "linux-login"},
	)

	if _, err := authorizeAccount("jsmith"); err != nil {
		t.Fatalf("got err=%v, want a member of an allowed_groups entry to be authorized", err)
	}
}

func TestAuthorizeAccount_NSSMode_MultipleGroupsOnlyOneMustMatch(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.AllowedGroups = map[string]bool{"linux-login": true, "vpn-users": true}
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})
	withStubGroups(t,
		map[string][]string{"jsmith": {"10042", "6001", "6002", "6003"}},
		map[string]string{"10042": "jsmith", "6001": "printer-admins", "6002": "linux-login", "6003": "wifi-guests"},
	)

	if _, err := authorizeAccount("jsmith"); err != nil {
		t.Fatalf("got err=%v, want a match on any one of several allowed_groups (found among several unrelated groups) to authorize", err)
	}
}

// --- nss mode: negative cases ---------------------------------------------

func TestAuthorizeAccount_NSSMode_UnknownUserRejected(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})

	if _, err := authorizeAccount("ghost"); err == nil {
		t.Fatal("an account NSS cannot resolve at all must be rejected")
	}
}

func TestAuthorizeAccount_NSSMode_RootByNameRejected(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	withStubUserLookup(t, map[string]string{"root": "0"})

	if _, err := authorizeAccount("root"); err == nil {
		t.Fatal("root must always be rejected in nss mode, regardless of deny_users/minimum_uid config")
	}
}

func TestAuthorizeAccount_NSSMode_UIDZeroAliasRejectedEvenIfNotNamedRoot(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	// A second account sharing UID 0 (a classic misconfiguration/attack
	// vector) must be rejected on UID alone, not just by name match.
	withStubUserLookup(t, map[string]string{"toor": "0"})

	if _, err := authorizeAccount("toor"); err == nil {
		t.Fatal("any account resolving to UID 0 must be rejected, not just the literal name \"root\"")
	}
}

func TestAuthorizeAccount_NSSMode_BelowMinimumUIDRejected(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.MinimumUID = 1000
	withStubUserLookup(t, map[string]string{"daemonish": "999"})

	if _, err := authorizeAccount("daemonish"); err == nil {
		t.Fatal("a system/service-range UID below minimum_uid must be rejected")
	}
}

func TestAuthorizeAccount_NSSMode_DenyUsersRejected(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.DenyUsers = map[string]bool{"root": true, "mallory": true}
	withStubUserLookup(t, map[string]string{"mallory": "1003"})

	if _, err := authorizeAccount("mallory"); err == nil {
		t.Fatal("an explicitly deny_users-listed account must be rejected even with a valid UID")
	}
}

func TestAuthorizeAccount_NSSMode_MissingGroupRejected(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.AllowedGroups = map[string]bool{"linux-login": true}
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})
	withStubGroups(t,
		map[string][]string{"jsmith": {"10042", "7000"}},
		map[string]string{"10042": "jsmith", "7000": "some-other-group"},
	)

	if _, err := authorizeAccount("jsmith"); err == nil {
		t.Fatal("an account in none of the allowed_groups must be rejected")
	}
}

func TestAuthorizeAccount_NSSMode_GroupLookupErrorFailsClosed(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	cfg.AllowedGroups = map[string]bool{"linux-login": true}
	withStubUserLookup(t, map[string]string{"jsmith": "10042"})
	prevGids := groupIDsForUser
	groupIDsForUser = func(u *user.User) ([]string, error) {
		return nil, fmt.Errorf("simulated SSSD/NSS backend unavailable")
	}
	t.Cleanup(func() { groupIDsForUser = prevGids })

	if _, err := authorizeAccount("jsmith"); err == nil {
		t.Fatal("a group-membership lookup failure (SSSD/NSS unavailable) must fail closed, never be treated as a match")
	}
}

func TestAuthorizeAccount_NSSMode_UserLookupErrorFailsClosed(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	prevLookup := userLookup
	userLookup = func(name string) (*user.User, error) {
		return nil, fmt.Errorf("simulated SSSD/NSS backend unavailable")
	}
	t.Cleanup(func() { userLookup = prevLookup })

	if _, err := authorizeAccount("jsmith"); err == nil {
		t.Fatal("an NSS lookup failure (SSSD down, LDAP unreachable) must fail closed, never be treated as authorized")
	}
}

func TestAuthorizeAccount_NSSMode_ExtraAllowedUsersRestrictsFurther(t *testing.T) {
	resetLimiterState(t)
	nssBaseConfig()
	// An optional additional allowlist on top of nss-mode's own checks -
	// jsmith passes UID/group but is not on this extra list.
	cfg.AllowedUsers = map[string]bool{"jdoe": true}
	withStubUserLookup(t, map[string]string{"jsmith": "10042", "jdoe": "10043"})

	if _, err := authorizeAccount("jsmith"); err == nil {
		t.Fatal("with a non-empty allowed_users, nss mode must still further restrict to only those names")
	}
	if _, err := authorizeAccount("jdoe"); err != nil {
		t.Fatalf("got err=%v, want jdoe (on the extra allowlist, valid UID) to be authorized", err)
	}
}

// --- config validation ----------------------------------------------------

func TestLoadConfig_NSSMode_RequiresPositiveMinimumUID(t *testing.T) {
	c := defaultConfig()
	c.AutheliaBaseURL = "https://authelia.example.invalid"
	c.AllowedVerificationHost = "authelia.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AccountSource = "nss"
	c.MinimumUID = 0
	c.RequireGroupMatch = false
	if err := c.Validate(); err == nil {
		t.Fatal("minimum_uid=0 in nss mode must be refused (UID 0 is root)")
	}
}

func TestLoadConfig_NSSMode_RequireGroupMatchNeedsGroups(t *testing.T) {
	c := defaultConfig()
	c.AutheliaBaseURL = "https://authelia.example.invalid"
	c.AllowedVerificationHost = "authelia.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AccountSource = "nss"
	c.MinimumUID = 1000
	c.RequireGroupMatch = true
	c.AllowedGroups = map[string]bool{}
	if err := c.Validate(); err == nil {
		t.Fatal("require_group_match=true with no allowed_groups is an ambiguous config and must be refused")
	}
}

func TestLoadConfig_NSSMode_ValidConfigAccepted(t *testing.T) {
	c := defaultConfig()
	c.AutheliaBaseURL = "https://authelia.example.invalid"
	c.AllowedVerificationHost = "authelia.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AccountSource = "nss"
	c.MinimumUID = 1000
	c.RequireGroupMatch = true
	c.AllowedGroups = map[string]bool{"linux-login": true}
	if err := c.Validate(); err != nil {
		t.Fatalf("got err=%v, want a well-formed nss-mode config to validate", err)
	}
}

func TestLoadConfig_UnknownAccountSourceRejected(t *testing.T) {
	c := defaultConfig()
	c.AutheliaBaseURL = "https://authelia.example.invalid"
	c.AllowedVerificationHost = "authelia.example.invalid"
	c.OIDCClientID = "pam-authelia"
	c.AccountSource = "ldap-direct" // never a supported value - NSS is the only path
	if err := c.Validate(); err == nil {
		t.Fatal("an unrecognized account_source must be refused, not silently ignored")
	}
}
