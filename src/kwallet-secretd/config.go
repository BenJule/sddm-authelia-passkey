package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

// config is intentionally a minimal, independent subset of the shared
// config/examples/config.conf.example format - this daemon only ever
// needs to know who is allowed to receive a secret and which named
// systemd credential to read. Duplicated rather than sharing a package
// with the broker so this single-purpose daemon's trust surface (what
// it parses, what it can be influenced by) stays as small as possible.
type config struct {
	AllowedUsers          map[string]bool
	KWalletCredentialName string
}

func loadConfig(path string) (config, error) {
	cfg := config{
		AllowedUsers:          map[string]bool{},
		KWalletCredentialName: "kwallet.secret",
	}

	f, err := os.Open(path)
	if err != nil {
		return cfg, fmt.Errorf("open config %s: %w", path, err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		kv := strings.SplitN(line, "=", 2)
		if len(kv) != 2 {
			return cfg, fmt.Errorf("malformed config line: %q", line)
		}
		key, val := strings.TrimSpace(kv[0]), strings.TrimSpace(kv[1])
		switch key {
		case "allowed_users":
			for _, u := range strings.Split(val, ",") {
				u = strings.TrimSpace(u)
				if u != "" {
					cfg.AllowedUsers[u] = true
				}
			}
		case "kwallet_credential_name":
			cfg.KWalletCredentialName = val
		}
	}
	if err := sc.Err(); err != nil {
		return cfg, err
	}
	if len(cfg.AllowedUsers) == 0 {
		return cfg, fmt.Errorf("allowed_users must list at least one local account")
	}
	return cfg, nil
}
