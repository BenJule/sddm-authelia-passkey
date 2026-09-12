// capabilities.go exposes a small, read-only, unauthenticated GET
// /capabilities endpoint the greeter can query before any username is
// even selected, purely to drive informational UX (see
// docs/capability-negotiation.md) - never a security decision. No
// secrets are involved: every field here is either already public
// configuration shape (account_source) or a simple reachability/
// presence fact an unauthenticated local process could observe anyway.
package main

import (
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// pamFilePath is a var so tests can point fido2Wired() at a fixture
// instead of the real /etc/pam.d/sddm.
var pamFilePath = "/etc/pam.d/sddm"

// fido2Wired reports whether pam_u2f.so has actually been wired into
// the PAM stack by enable-fido2.sh - the only source of truth for
// whether the hardware-key fast path is live, since this broker never
// manages PAM itself (see docs/fido2.md). Read-only; fails closed to
// false on any read error rather than claiming a capability that
// couldn't be confirmed.
func fido2Wired() bool {
	data, err := os.ReadFile(pamFilePath)
	if err != nil {
		return false
	}
	return strings.Contains(string(data), "pam_u2f.so")
}

const capabilitiesCacheTTL = 10 * time.Second

var (
	capabilitiesCacheMu   sync.Mutex
	capabilitiesCacheAt   time.Time
	capabilitiesCacheOIDC bool
)

// checkOIDCReady is a var so tests can stub it without a real network
// round-trip. Deliberately independent of oidcDiscover()'s permanent
// per-process cache (correct for "the endpoints don't change", wrong
// for "is the provider reachable right now") - this always performs a
// fresh check, only throttled by oidcReadyCached()'s short TTL below.
var checkOIDCReady = func() bool {
	if cfg.ProviderKind == "oidc" {
		_, err := fetchOIDCDiscovery(cfg.OIDCDiscoveryURL)
		return err == nil
	}
	resp, err := http.Get(cfg.AutheliaBaseURL + "/api/health")
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

// oidcReadyCached bounds how often /capabilities actually hits the
// identity provider - informational only, so a answer up to
// capabilitiesCacheTTL stale cannot itself grant or deny any login.
func oidcReadyCached() bool {
	capabilitiesCacheMu.Lock()
	defer capabilitiesCacheMu.Unlock()

	if time.Since(capabilitiesCacheAt) < capabilitiesCacheTTL {
		return capabilitiesCacheOIDC
	}

	capabilitiesCacheOIDC = checkOIDCReady()
	capabilitiesCacheAt = time.Now()
	return capabilitiesCacheOIDC
}

type capabilitiesResponse struct {
	AccountSource string `json:"account_source"`
	OIDCReady     bool   `json:"oidc_ready"`
	FIDO2Wired    bool   `json:"fido2_wired"`
	// SmartcardReady is always false: this project does not implement
	// smartcard/PKCS#11 authentication (see docs/capability-negotiation.md).
	// A constant, explicit field rather than an absent one, so a client
	// never has to guess whether "unset" means "false" or "not yet known".
	SmartcardReady bool `json:"smartcard_ready"`
}

func handleCapabilities(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "GET only", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, capabilitiesResponse{
		AccountSource:  cfg.AccountSource,
		OIDCReady:      oidcReadyCached(),
		FIDO2Wired:     fido2Wired(),
		SmartcardReady: false,
	})
}
