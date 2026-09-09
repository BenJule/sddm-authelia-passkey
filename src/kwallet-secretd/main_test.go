package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func withTestConfig(t *testing.T) {
	t.Helper()
	old := cfg
	cfg = config{
		AllowedUsers:          map[string]bool{"alice": true},
		KWalletCredentialName: "kwallet.secret",
	}
	t.Cleanup(func() { cfg = old })
}

func TestSanitizeUsername(t *testing.T) {
	cases := []struct {
		in string
		ok bool
	}{
		{"alice", true},
		{"", false},
		{"root", true}, // sanitize only checks charset; allowlist check is separate
		{"; rm -rf /", false},
		{"user with space", false},
		{"a$(id)", false},
		{"../../etc/passwd", false},
		{string(make([]byte, 100)), false},
	}
	for _, c := range cases {
		_, ok := sanitizeUsername(c.in)
		if ok != c.ok {
			t.Errorf("sanitizeUsername(%q) ok=%v want %v", c.in, ok, c.ok)
		}
	}
}

func TestAllowlistExcludesUnknownAndRoot(t *testing.T) {
	withTestConfig(t)
	if cfg.AllowedUsers["root"] {
		t.Fatal("root must never be in AllowedUsers")
	}
	if cfg.AllowedUsers["someoneelse"] {
		t.Fatal("unknown user must not be allowlisted")
	}
	if !cfg.AllowedUsers["alice"] {
		t.Fatal("alice must be allowlisted per test config")
	}
}

func withMarkerDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	old := markerDir
	markerDir = dir
	t.Cleanup(func() { markerDir = old })
	return dir
}

func TestConsumeHandoff_NoMarker(t *testing.T) {
	withMarkerDir(t)
	if consumeHandoff("alice", "1001") {
		t.Fatal("expected false with no marker present")
	}
}

func TestConsumeHandoff_ValidThenReplayDenied(t *testing.T) {
	dir := withMarkerDir(t)
	p := filepath.Join(dir, markerPrefix+"alice")
	if err := os.WriteFile(p, []byte("UID=1001\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if !consumeHandoff("alice", "1001") {
		t.Fatal("expected true for fresh valid marker")
	}
	if consumeHandoff("alice", "1001") {
		t.Fatal("replay: second consume of the same hand-off must be denied")
	}
}

func TestConsumeHandoff_Expired(t *testing.T) {
	dir := withMarkerDir(t)
	p := filepath.Join(dir, markerPrefix+"alice")
	if err := os.WriteFile(p, []byte("UID=1001\n"), 0600); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-2 * markerTTL)
	if err := os.Chtimes(p, old, old); err != nil {
		t.Fatal(err)
	}
	if consumeHandoff("alice", "1001") {
		t.Fatal("expected false for expired marker")
	}
}

func TestConsumeHandoff_WrongUserMarkerNotConsumed(t *testing.T) {
	dir := withMarkerDir(t)
	p := filepath.Join(dir, markerPrefix+"otheruser")
	if err := os.WriteFile(p, []byte("UID=1002\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if consumeHandoff("alice", "1001") {
		t.Fatal("must not consume a marker belonging to a different user")
	}
	if _, err := os.Stat(p); err != nil {
		t.Fatal("other user's marker must remain untouched")
	}
}

func TestConsumeHandoff_WrongUIDRejected(t *testing.T) {
	dir := withMarkerDir(t)
	p := filepath.Join(dir, markerPrefix+"alice")
	if err := os.WriteFile(p, []byte("UID=1001\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if consumeHandoff("alice", "1002") {
		t.Fatal("a handoff marker minted for UID 1001 must not release a secret for a request claiming UID 1002")
	}
}

func TestConsumeHandoff_MissingUIDFieldRejected(t *testing.T) {
	dir := withMarkerDir(t)
	p := filepath.Join(dir, markerPrefix+"alice")
	if err := os.WriteFile(p, []byte("ok"), 0600); err != nil {
		t.Fatal(err)
	}
	if consumeHandoff("alice", "1001") {
		t.Fatal("a marker with no UID= binding must fail closed, not be trusted")
	}
}

func TestSanitizeUID(t *testing.T) {
	cases := []struct {
		in string
		ok bool
	}{
		{"1001", true},
		{"0", true},
		{"", false},
		{"-1", false},
		{"1001; rm -rf /", false},
		{"0x3e9", false},
		{"99999999999", false}, // too long, not a plausible UID
	}
	for _, c := range cases {
		_, ok := sanitizeUID(c.in)
		if ok != c.ok {
			t.Errorf("sanitizeUID(%q) ok=%v want %v", c.in, ok, c.ok)
		}
	}
}

func TestTrimTrailingNewline(t *testing.T) {
	if got := string(trimTrailingNewline([]byte("secret\n"))); got != "secret" {
		t.Fatalf("got %q", got)
	}
	if got := string(trimTrailingNewline([]byte("secret\r\n"))); got != "secret" {
		t.Fatalf("got %q", got)
	}
	if got := string(trimTrailingNewline([]byte("secret"))); got != "secret" {
		t.Fatalf("got %q", got)
	}
}

func TestWipe(t *testing.T) {
	b := []byte("topsecret")
	wipe(b)
	for i, v := range b {
		if v != 0 {
			t.Fatalf("byte %d not wiped: %v", i, b)
		}
	}
}
