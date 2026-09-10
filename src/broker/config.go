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

	// ProviderKind selects the OIDC Device Authorization Grant provider:
	//   "authelia" (default, and the implicit value for any config
	//     written before this key existed) - exactly the v0.1-v0.6
	//     behavior, hardcoded Authelia endpoint paths and identity claim.
	//   "oidc" - a generic standards-based provider (Keycloak, Authentik,
	//     or any other OIDC Provider that publishes a discovery document
	//     advertising device_authorization_endpoint), using
	//     OIDCDiscoveryURL/OIDCIdentityClaim below.
	ProviderKind string
	// OIDCDiscoveryURL: the provider's OIDC discovery document (its
	// .well-known/openid-configuration URL). Required when
	// ProviderKind is "oidc". Never consulted for "authelia".
	OIDCDiscoveryURL string
	// OIDCIdentityClaim: which userinfo claim carries the local
	// username to bind to (see the identity-binding model in
	// docs/architecture.md) - defaults to the standard OIDC
	// "preferred_username" claim when unset. Never consulted for
	// "authelia" (which always uses its own "authelia.pam.username").
	OIDCIdentityClaim string

	AllowedUsers map[string]bool

	// AccountSource selects how a requested username is authorized:
	//   "local" (default) - exactly the v0.1-v0.4 behavior: the account
	//     must be a literal entry in AllowedUsers, nothing else checked.
	//   "nss" - any account NSS can resolve (local /etc/passwd, or via
	//     SSSD/nss-ldap against Samba AD/OpenLDAP/FreeIPA - whatever the
	//     host's own nsswitch.conf is configured for; this broker never
	//     talks to LDAP/AD directly) is eligible, subject to MinimumUID,
	//     DenyUsers, and AllowedGroups/RequireGroupMatch below. AllowedUsers
	//     becomes an *optional additional* allowlist in this mode - if
	//     non-empty, it still further restricts which resolved accounts
	//     are accepted, on top of the other checks.
	AccountSource string

	// MinimumUID rejects any account whose NSS-resolved UID is below it -
	// UID 0 (root) is always rejected regardless of this value. Only
	// enforced when AccountSource is "nss".
	MinimumUID int

	// DenyUsers is a fixed denylist checked before any other "nss" mode
	// authorization logic - "root" is always implicitly a member of this
	// set, whether or not the config lists it.
	DenyUsers map[string]bool

	// AllowedGroups, if non-empty, requires the resolved account to be a
	// member (via NSS getgrouplist - real group membership, not a stored
	// cache this project maintains itself) of at least one named group.
	// Only consulted when AccountSource is "nss".
	AllowedGroups map[string]bool
	// RequireGroupMatch existing only as an explicit, readable on/off
	// switch: true (the only supported value once AllowedGroups is
	// non-empty) means group membership is mandatory. Having
	// AllowedGroups set with this false would silently disable the group
	// check, which is exactly the kind of ambiguous half-configuration
	// this project refuses to start with - see Validate().
	RequireGroupMatch bool

	ApprovalTTLSeconds      int
	UserCooldownSeconds     int
	MaxParallelFlows        int
	FailureLockoutThreshold int
	FailureLockoutSeconds   int

	KWalletAutoUnlock     bool
	KWalletCredentialName string
}

func defaultConfig() Config {
	return Config{
		OIDCScopes:              "openid authelia.pam",
		AllowedUsers:            map[string]bool{},
		AccountSource:           "local",
		MinimumUID:              1000,
		DenyUsers:               map[string]bool{},
		AllowedGroups:           map[string]bool{},
		RequireGroupMatch:       true,
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
	if v, ok := raw["provider_kind"]; ok {
		cfg.ProviderKind = strings.ToLower(strings.TrimSpace(v))
	}
	if v, ok := raw["oidc_discovery_url"]; ok {
		cfg.OIDCDiscoveryURL = v
	}
	if v, ok := raw["oidc_identity_claim"]; ok {
		cfg.OIDCIdentityClaim = v
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
	if v, ok := raw["account_source"]; ok {
		cfg.AccountSource = strings.ToLower(strings.TrimSpace(v))
	}
	if v, ok := raw["deny_users"]; ok {
		cfg.DenyUsers = map[string]bool{}
		for _, u := range strings.Split(v, ",") {
			u = strings.TrimSpace(u)
			if u != "" {
				cfg.DenyUsers[u] = true
			}
		}
	}
	if v, ok := raw["allowed_groups"]; ok {
		cfg.AllowedGroups = map[string]bool{}
		for _, g := range strings.Split(v, ",") {
			g = strings.TrimSpace(g)
			if g != "" {
				cfg.AllowedGroups[g] = true
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
	if cfg.MinimumUID, err2 = getInt("minimum_uid", cfg.MinimumUID); err2 != nil {
		return cfg, err2
	}
	if cfg.RequireGroupMatch, err2 = getBool("require_group_match", cfg.RequireGroupMatch); err2 != nil {
		return cfg, err2
	}
	if v, ok := raw["kwallet_credential_name"]; ok {
		cfg.KWalletCredentialName = v
	}

	return cfg, cfg.Validate()
}

// Validate enforces fail-closed policy for anything auth-relevant.
// A validation failure must never be silently ignored - refuse to start
// rather than run with an insecure or ambiguous configuration.
func (c Config) Validate() error {
	if !isKnownProviderKind(c.ProviderKind) {
		return fmt.Errorf("provider_kind must be %q or %q, got %q", "authelia", "oidc", c.ProviderKind)
	}
	if c.ProviderKind == "oidc" {
		if c.OIDCDiscoveryURL == "" {
			return fmt.Errorf("oidc_discovery_url is required when provider_kind=oidc")
		}
		du, err := url.Parse(c.OIDCDiscoveryURL)
		if err != nil {
			return fmt.Errorf("oidc_discovery_url: %w", err)
		}
		if du.Scheme != "https" && !c.DevInsecureHTTP {
			return fmt.Errorf("oidc_discovery_url must be https:// (set authelia_dev_insecure_http=true only for local development)")
		}
	} else {
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
	}
	if c.AllowedVerificationHost == "" {
		return fmt.Errorf("allowed_verification_host is required")
	}
	if c.OIDCClientID == "" {
		return fmt.Errorf("oidc_client_id is required")
	}
	switch c.AccountSource {
	case "local":
		if len(c.AllowedUsers) == 0 {
			return fmt.Errorf("allowed_users must list at least one local account (or set account_source=nss)")
		}
	case "nss":
		if c.MinimumUID <= 0 {
			return fmt.Errorf("minimum_uid must be positive when account_source=nss (UID 0/root is always rejected regardless)")
		}
		if c.RequireGroupMatch && len(c.AllowedGroups) == 0 {
			// An explicit true with nothing to match against is not "no
			// restriction" - it is a config mistake that would either
			// reject everyone or (if the code silently ignored an empty
			// list) accidentally stop enforcing group membership. Refuse
			// to start rather than guess which one was meant.
			return fmt.Errorf("require_group_match=true needs at least one allowed_groups entry")
		}
	default:
		return fmt.Errorf("account_source must be %q or %q, got %q", "local", "nss", c.AccountSource)
	}
	if c.AllowedUsers["root"] {
		// The PAM stack's own `pam_succeed_if.so user != root` line
		// already structurally prevents a root marker from ever granting
		// login (see docs/architecture.md) - this is a second, redundant
		// check at config-load time so a misconfiguration is refused
		// immediately and loudly instead of relying solely on PAM
		// control-flow ordering never changing.
		return fmt.Errorf("allowed_users must not include root")
	}
	if !c.DenyUsers["root"] {
		// Belt-and-suspenders: DenyUsers always implicitly contains root,
		// this just makes it explicit/observable in the parsed struct too
		// (authorizeAccount does not rely on this - it independently
		// checks resolved UID/username == root either way).
		c.DenyUsers["root"] = true
	}
	if c.ApprovalTTLSeconds <= 0 || c.UserCooldownSeconds < 0 || c.MaxParallelFlows <= 0 ||
		c.FailureLockoutThreshold <= 0 || c.FailureLockoutSeconds <= 0 {
		return fmt.Errorf("timing/limit values must be positive")
	}
	return nil
}
