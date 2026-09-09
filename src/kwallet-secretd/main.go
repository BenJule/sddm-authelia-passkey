// kwallet-secretd is a single-purpose daemon: it releases a KDE KWallet
// unlock secret to the local PAM module, but only when a valid,
// single-use, short-TTL hand-off marker - minted by the PAM module itself,
// only after it already independently consumed the real smartphone login-
// approval marker - is present for the requesting user.
//
// It never talks to the identity provider itself and never listens on
// any network socket. The secret is read once per successful request
// straight from the systemd-managed $CREDENTIALS_DIRECTORY (decrypted
// in-kernel/tmpfs by systemd from an on-disk systemd-creds encrypted
// file) and zeroed from memory immediately after being written to the
// client.
package main

import (
	"bufio"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	configPath = "/etc/sddm-authelia-passkey/config.conf"
	socketPath = "/run/sddm-authelia-passkey/kwallet-secret.sock"
	// Separate, short-lived hand-off marker ("kwallet-ready-<user>") minted
	// by the PAM module ONLY after it has already independently consumed
	// the real, single-use smartphone login-approval marker ("approved-<user>").
	// This daemon never reads or consumes the login-approval marker
	// itself, so there is no double-consumer race between the login
	// decision and the secret release.
	markerPrefix = "kwallet-ready-"
	markerTTL    = 5 * time.Second
	ioTimeout    = 2 * time.Second
	maxUsername  = 64
)

// markerDir is a var (not const) so tests can point it at a temp dir.
var markerDir = "/run/sddm-authelia-passkey"

var cfg config

// credPath is per-user: cfg.KWalletCredentialName is a prefix (default
// "kwallet.secret"), and each allowed user has their own systemd-creds
// encrypted file "<prefix>.<user>" - never one credential shared across
// every allowed user. See docs/kwallet.md for the setup tool that
// creates these.
func credPath(user string) string {
	dir := os.Getenv("CREDENTIALS_DIRECTORY")
	if dir == "" {
		dir = "/run/credentials/sddm-authelia-passkey-kwallet-secretd.service"
	}
	return filepath.Join(dir, cfg.KWalletCredentialName+"."+user)
}

func sanitizeUID(u string) (string, bool) {
	if u == "" || len(u) > 10 {
		return "", false
	}
	for _, c := range u {
		if c < '0' || c > '9' {
			return "", false
		}
	}
	return u, true
}

func sanitizeUsername(u string) (string, bool) {
	if u == "" || len(u) > maxUsername {
		return "", false
	}
	for _, c := range u {
		if !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') && !(c >= '0' && c <= '9') && c != '_' && c != '-' {
			return "", false
		}
	}
	return u, true
}

// consumeHandoff atomically claims (removes) the hand-off marker for
// user, and reports whether it was present, still within TTL, and (if
// it carries a UID= line - minted by an up to date PAM module) bound to
// exactly the UID the caller claims to be releasing a secret for.
// Single-use: whether valid or expired, the marker is gone afterwards.
func consumeHandoff(user string, wireUID string) bool {
	path := filepath.Join(markerDir, markerPrefix+user)
	tmp := path + ".claimed"
	if err := os.Rename(path, tmp); err != nil {
		return false
	}
	defer os.Remove(tmp)

	info, err := os.Stat(tmp)
	if err != nil {
		return false
	}
	if time.Since(info.ModTime()) > markerTTL {
		return false
	}
	content, err := os.ReadFile(tmp)
	if err != nil {
		return false
	}
	for _, line := range strings.Split(string(content), "\n") {
		if after, ok := strings.CutPrefix(line, "UID="); ok {
			return after == wireUID
		}
	}
	return false
}

func peerIsRoot(c *net.UnixConn) bool {
	raw, err := c.SyscallConn()
	if err != nil {
		return false
	}
	var cred *syscall.Ucred
	var gerr error
	err = raw.Control(func(fd uintptr) {
		cred, gerr = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	})
	if err != nil || gerr != nil || cred == nil {
		return false
	}
	return cred.Uid == 0
}

func handle(c *net.UnixConn) {
	defer c.Close()
	_ = c.SetDeadline(time.Now().Add(ioTimeout))

	if !peerIsRoot(c) {
		fmt.Fprint(c, "DENY\n")
		return
	}

	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil {
		return
	}
	line = strings.TrimSpace(line)
	parts := strings.SplitN(line, " ", 3)
	if len(parts) != 3 || parts[0] != "GET" {
		fmt.Fprint(c, "DENY\n")
		return
	}
	user, ok := sanitizeUsername(parts[1])
	if !ok || !cfg.AllowedUsers[user] {
		fmt.Fprint(c, "DENY\n")
		return
	}
	uid, ok := sanitizeUID(parts[2])
	if !ok {
		fmt.Fprint(c, "DENY\n")
		return
	}

	// The handoff marker's own UID= binding is checked against uid here -
	// a request for "alice" carrying bob's UID (or any UID that doesn't
	// match what PAM's own fresh NSS lookup produced when it minted the
	// marker) is rejected, not just a username string match.
	if !consumeHandoff(user, uid) {
		fmt.Fprint(c, "DENY\n")
		return
	}

	secret, err := os.ReadFile(credPath(user))
	if err != nil {
		log.Printf("credential unavailable: %v", err)
		fmt.Fprint(c, "DENY\n")
		return
	}
	defer wipe(secret)

	secret = trimTrailingNewline(secret)
	if len(secret) == 0 {
		fmt.Fprint(c, "DENY\n")
		return
	}
	fmt.Fprintf(c, "OK %s\n", secret)
	// Never log secret content or length beyond this point.
}

func trimTrailingNewline(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r') {
		b = b[:len(b)-1]
	}
	return b
}

func wipe(b []byte) {
	for i := range b {
		b[i] = 0
	}
}

func main() {
	var err error
	cfg, err = loadConfig(configPath)
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	_ = os.Remove(socketPath)
	if err := os.MkdirAll(markerDir, 0700); err != nil {
		log.Fatalf("mkdir markerDir: %v", err)
	}

	l, err := net.Listen("unix", socketPath)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	if err := os.Chmod(socketPath, 0600); err != nil {
		log.Fatalf("chmod socket: %v", err)
	}

	// Fail fast and loudly at startup if a user's credential is missing/
	// unreadable, rather than only discovering it during a real
	// smartphone login attempt - checked per allowed user, since each
	// has their own credential file.
	for u := range cfg.AllowedUsers {
		if _, err := os.Stat(credPath(u)); err != nil {
			log.Printf("WARNING: kwallet credential for %q not present at startup (%v) - auto-unlock will fail-safe to DENY until fixed", u, err)
		}
	}

	log.Printf("kwallet-secretd listening on %s", socketPath)
	for {
		conn, err := l.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			log.Printf("accept: %v", err)
			continue
		}
		uc, ok := conn.(*net.UnixConn)
		if !ok {
			conn.Close()
			continue
		}
		go handle(uc)
	}
}
