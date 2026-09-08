package main

import (
	"bufio"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// Config is parsed from a simple KEY=VALUE file (see
// config/examples/config.conf.example). Kept deliberately dependency-free
// (no TOML/YAML library) so both this Go broker and the C PAM module can
// parse the exact same on-disk format without divergence.
type Config struct {
	AutheliaBaseURL         string
	AllowedVerificationHost string
	OIDCClientID            string
	OIDCScopes              string
	DevInsecureHTTP         bool

	AllowedUsers map[string]bool

	ApprovalTTLSeconds       int
	UserCooldownSeconds      int
	MaxParallelFlows         int
	FailureLockoutThreshold  int
	FailureLockoutSeconds    int

	KWalletAutoUnlock     bool
	KWalletCredentialName string
}

func defaultConfig() Config {
	return Config{
		OIDCScopes:              "openid authelia.pam",
		AllowedUsers:            map[string]bool{},
		ApprovalTTLSeconds:      30,
		UserCooldownSeconds:     10,
		MaxParallelFlows:        3,
		FailureLockoutThreshold: 3,
		FailureLockoutSeconds:   60,
		KWalletCredentialName:   "kwallet.secret",
	}
}

func LoadConfig(path string) (Config, error) {
	cfg := defaultConfig()

	f, err := os.Open(path)
	if err != nil {
		return cfg, fmt.Errorf("open config %s: %w", path, err)
	}
	defer f.Close()

	raw := map[string]string{}
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
		raw[strings.TrimSpace(kv[0])] = strings.TrimSpace(kv[1])
	}
	if err := sc.Err(); err != nil {
		return cfg, err
	}

	getInt := func(key string, cur int) (int, error) {
		v, ok := raw[key]
		if !ok {
			return cur, nil
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			return 0, fmt.Errorf("%s: not an integer: %q", key, v)
		}
		return n, nil
	}
	getBool := func(key string, cur bool) (bool, error) {
		v, ok := raw[key]
		if !ok {
			return cur, nil
		}
		switch strings.ToLower(v) {
		case "true", "1", "yes":
			return true, nil
		case "false", "0", "no":
			return false, nil
		default:
			return false, fmt.Errorf("%s: not a bool: %q", key, v)
		}
	}

	if v, ok := raw["authelia_base_url"]; ok {
		cfg.AutheliaBaseURL = v
	}
	if v, ok := raw["allowed_verification_host"]; ok {
		cfg.AllowedVerificationHost = v
	}
	if v, ok := raw["oidc_client_id"]; ok {
		cfg.OIDCClientID = v
	}
	if v, ok := raw["oidc_scopes"]; ok {
		cfg.OIDCScopes = v
	}
	if v, ok := raw["allowed_users"]; ok {
		cfg.AllowedUsers = map[string]bool{}
		for _, u := range strings.Split(v, ",") {
			u = strings.TrimSpace(u)
			if u != "" {
				cfg.AllowedUsers[u] = true
			}
		}
	}

	var err2 error
	if cfg.DevInsecureHTTP, err2 = getBool("authelia_dev_insecure_http", cfg.DevInsecureHTTP); err2 != nil {
		return cfg, err2
	}
	if cfg.ApprovalTTLSeconds, err2 = getInt("approval_ttl_seconds", cfg.ApprovalTTLSeconds); err2 != nil {
		return cfg, err2
	}
	if cfg.UserCooldownSeconds, err2 = getInt("user_cooldown_seconds", cfg.UserCooldownSeconds); err2 != nil {
		return cfg, err2
	}
	if cfg.MaxParallelFlows, err2 = getInt("max_parallel_flows", cfg.MaxParallelFlows); err2 != nil {
		return cfg, err2
	}
	if cfg.FailureLockoutThreshold, err2 = getInt("failure_lockout_threshold", cfg.FailureLockoutThreshold); err2 != nil {
		return cfg, err2
	}
	if cfg.FailureLockoutSeconds, err2 = getInt("failure_lockout_seconds", cfg.FailureLockoutSeconds); err2 != nil {
		return cfg, err2
	}
	if cfg.KWalletAutoUnlock, err2 = getBool("kwallet_auto_unlock", cfg.KWalletAutoUnlock); err2 != nil {
		return cfg, err2
	}
	if v, ok := raw["kwallet_credential_name"]; ok {
		cfg.KWalletCredentialName = v
	}

	return cfg, cfg.Validate()
}

// Validate enforces fail-closed policy for anything Pixel-auth-relevant.
// A validation failure must never be silently ignored - refuse to start
// rather than run with an insecure or ambiguous configuration.
func (c Config) Validate() error {
	if c.AutheliaBaseURL == "" {
		return fmt.Errorf("authelia_base_url is required")
	}
	u, err := url.Parse(c.AutheliaBaseURL)
	if err != nil {
		return fmt.Errorf("authelia_base_url: %w", err)
	}
	if u.Scheme != "https" && !c.DevInsecureHTTP {
		return fmt.Errorf("authelia_base_url must be https:// (set authelia_dev_insecure_http=true only for local development)")
	}
	if c.AllowedVerificationHost == "" {
		return fmt.Errorf("allowed_verification_host is required")
	}
	if c.OIDCClientID == "" {
		return fmt.Errorf("oidc_client_id is required")
	}
	if len(c.AllowedUsers) == 0 {
		return fmt.Errorf("allowed_users must list at least one local account")
	}
	if c.ApprovalTTLSeconds <= 0 || c.UserCooldownSeconds < 0 || c.MaxParallelFlows <= 0 ||
		c.FailureLockoutThreshold <= 0 || c.FailureLockoutSeconds <= 0 {
		return fmt.Errorf("timing/limit values must be positive")
	}
	return nil
}
