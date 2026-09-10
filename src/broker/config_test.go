package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeTempConfig(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, "config.conf")
	if err := os.WriteFile(p, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadConfig_ValidMinimal(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice,bob
`)
	c, err := LoadConfig(p)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !c.AllowedUsers["alice"] || !c.AllowedUsers["bob"] {
		t.Fatalf("allowed_users not parsed: %+v", c.AllowedUsers)
	}
	if c.ApprovalTTLSeconds != 30 {
		t.Fatalf("expected default ttl 30, got %d", c.ApprovalTTLSeconds)
	}
}

func TestLoadConfig_RejectsHTTPWithoutDevFlag(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=http://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("expected rejection of http:// base URL without authelia_dev_insecure_http=true")
	}
}

func TestLoadConfig_DevInsecureHTTPAllowed(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=http://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice
authelia_dev_insecure_http=true
`)
	if _, err := LoadConfig(p); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLoadConfig_RejectsEmptyAllowedUsers(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("expected rejection of missing allowed_users")
	}
}

func TestLoadConfig_RejectsRootInAllowedUsers(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice,root
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("expected rejection of root in allowed_users")
	}
}

func TestLoadConfig_RejectsUnknownKey(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice
alowed_groups=admins
`)
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("a typo'd/unrecognized config key must be refused, not silently ignored")
	}
}

func TestLoadConfig_AcceptsShellOnlyFido2Keys(t *testing.T) {
	// The broker itself never reads these (scripts/enable-fido2.sh
	// parses them directly from the file), but they are a documented,
	// legitimate part of config.conf and must not be rejected as
	// "unknown" just because this package has no field for them.
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice
fido2_authfile=/etc/sddm-authelia-passkey/fido2_mappings
fido2_require_user_verification=true
fido2_require_pin_verification=false
fido2_required_group=fido2-users
`)
	if _, err := LoadConfig(p); err != nil {
		t.Fatalf("shell-only fido2_* keys must be accepted: %v", err)
	}
}

// TestLoadConfig_ShippedExampleFileLoadsAndValidates guards against the
// shipped config/examples/config.conf.example drifting out of sync with
// what LoadConfig actually accepts (e.g. a renamed key, or the new
// unknown-key rejection above catching a stale example) - if this test
// ever fails, the example file is broken for every real user who copies
// it verbatim.
func TestLoadConfig_ShippedExampleFileLoadsAndValidates(t *testing.T) {
	// Repo layout: src/broker/config_test.go -> ../../config/examples/
	p := filepath.Join("..", "..", "config", "examples", "config.conf.example")
	c, err := LoadConfig(p)
	if err != nil {
		t.Fatalf("shipped config.conf.example must load cleanly: %v", err)
	}
	if err := c.Validate(); err != nil {
		t.Fatalf("shipped config.conf.example must validate: %v", err)
	}
}

func TestLoadConfig_RejectsMalformedLine(t *testing.T) {
	p := writeTempConfig(t, "not_a_key_value_line\n")
	if _, err := LoadConfig(p); err == nil {
		t.Fatal("expected rejection of malformed line")
	}
}

func TestLoadConfig_MissingFile(t *testing.T) {
	if _, err := LoadConfig("/nonexistent/config.conf"); err == nil {
		t.Fatal("expected error for missing file")
	}
}

// TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults is the explicit
// upgrade/config-migration proof for v0.9.0: a config.conf written
// before account_source/provider_kind/FIDO2/policy keys existed (the
// exact shape shipped up to v0.4.x) must still load correctly after an
// in-place package upgrade, with every key introduced since then taking
// its documented backward-compatible default - dpkg's conffile handling
// preserves the admin's existing config.conf verbatim across an
// upgrade, so this is the only thing standing between "apt upgrade" and
// a broker that refuses to start.
func TestLoadConfig_PreV050ConfigStillLoadsWithNewDefaults(t *testing.T) {
	p := writeTempConfig(t, `
authelia_base_url=https://idp.example.com
allowed_verification_host=idp.example.com
oidc_client_id=pam-authelia
allowed_users=alice,bob
approval_ttl_seconds=45
`)
	c, err := LoadConfig(p)
	if err != nil {
		t.Fatalf("a pre-v0.5.0-shaped config.conf must still load after upgrading: %v", err)
	}
	if c.AccountSource != "local" {
		t.Fatalf("account_source default: got %q, want \"local\"", c.AccountSource)
	}
	if c.ProviderKind != "" && c.ProviderKind != "authelia" {
		t.Fatalf("provider_kind default: got %q, want \"\" or \"authelia\"", c.ProviderKind)
	}
	if !isKnownProviderKind(c.ProviderKind) {
		t.Fatalf("provider_kind default %q must be accepted by isKnownProviderKind", c.ProviderKind)
	}
	if c.ApprovalTTLSeconds != 45 {
		t.Fatalf("an explicitly-set pre-existing value must survive unchanged: got %d, want 45", c.ApprovalTTLSeconds)
	}
	// require_group_match defaults to true, but is only consulted when
	// account_source=nss (see Validate) - account_source=local here must
	// still validate despite that default, since the nss-only check
	// never fires for it.
	if !c.RequireGroupMatch {
		t.Fatalf("require_group_match default: got false, want true (its effect is gated on account_source=nss, not on this default)")
	}
	if err := c.Validate(); err != nil {
		t.Fatalf("a pre-v0.5.0-shaped config.conf must still validate after upgrading: %v", err)
	}
	if !c.DenyUsers["root"] {
		t.Fatalf("deny_users must implicitly cover root after Validate: got %+v", c.DenyUsers)
	}
}
