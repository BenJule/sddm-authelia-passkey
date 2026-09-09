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
