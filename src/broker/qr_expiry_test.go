package main

import (
	"encoding/json"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

// --- v1.2.0 Smart QR UX: flowState.ExpiresAt lets the theme render a
// live local countdown/progress ring instead of polling just to learn
// how much time is left. -------------------------------------------------

func TestHandleStart_SetsExpiresAtFromProviderResponse(t *testing.T) {
	resetFlowState(t)
	resetLimiterState(t)
	withStubUserLookup(t, map[string]string{"alice": "1001"})
	cfg.AccountSource = "local"
	cfg.AllowedUsers = map[string]bool{"alice": true}
	// Other tests in this package leave cfg.ProviderKind set to "oidc"
	// without always resetting it - pin it explicitly so this test
	// exercises the plain Authelia deviceAuthorize() path its mock
	// server actually implements, regardless of run order.
	prevProviderKind := cfg.ProviderKind
	cfg.ProviderKind = "authelia"
	t.Cleanup(func() { cfg.ProviderKind = prevProviderKind })

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/oidc/device-authorization" {
			json.NewEncoder(w).Encode(deviceAuthResponse{
				DeviceCode: "dc-1", UserCode: "ABCD-EFGH",
				VerificationURIComplete: "https://idp.example.invalid/consent/openid/device-authorization?user_code=ABCD-EFGH",
				ExpiresIn:               600, Interval: 5,
			})
			return
		}
		w.WriteHeader(http.StatusBadGateway) // token endpoint: never reached synchronously by this test
	}))
	t.Cleanup(srv.Close)
	prevBase := cfg.AutheliaBaseURL
	prevHost := cfg.AllowedVerificationHost
	cfg.AutheliaBaseURL = srv.URL
	cfg.AllowedVerificationHost = "idp.example.invalid"
	t.Cleanup(func() { cfg.AutheliaBaseURL = prevBase; cfg.AllowedVerificationHost = prevHost })

	before := time.Now()
	req := httptest.NewRequest(http.MethodPost, "/start?username=alice", nil)
	w := httptest.NewRecorder()
	handleStart(w, req)
	after := time.Now()

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var resp map[string]string
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	flowsMu.Lock()
	fs, ok := flows[resp["session_id"]]
	flowsMu.Unlock()
	if !ok {
		t.Fatal("flow not found")
	}
	fs.mu.Lock()
	expiresAt := fs.ExpiresAt
	fs.mu.Unlock()

	wantMin := before.Add(600 * time.Second).Unix()
	wantMax := after.Add(600 * time.Second).Unix()
	if expiresAt < wantMin || expiresAt > wantMax {
		t.Fatalf("expires_at = %d, want between %d and %d (now + 600s)", expiresAt, wantMin, wantMax)
	}
}

func TestHandleStatus_ExposesExpiresAtAsJSON(t *testing.T) {
	resetFlowState(t)
	fs := &flowState{Status: "pending", ExpiresAt: 1234567890, cancelCh: make(chan struct{})}
	flowsMu.Lock()
	flows["expiry-test-session"] = fs
	flowsMu.Unlock()

	req := httptest.NewRequest(http.MethodGet, "/status?session_id=expiry-test-session", nil)
	w := httptest.NewRecorder()
	handleStatus(w, req)

	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	got, ok := resp["expires_at"].(float64)
	if !ok || int64(got) != 1234567890 {
		t.Fatalf("expires_at in /status response = %v, want 1234567890", resp["expires_at"])
	}
}

// TestWriteQR_RendersAtExplicitSize is a regression guard against
// silently reverting to size=0 (library default, much smaller than
// qrPixelSize and visibly blurry once scaled up to the panel's QR
// card) - decodes the actual PNG dimensions rather than trusting file
// size, since a QR code's large flat black/white regions compress
// extremely well regardless of pixel dimensions.
func TestWriteQR_RendersAtExplicitSize(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/test.png"
	if err := writeQR("https://idp.example.invalid/device?code=ABCD-EFGH", path); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	imgCfg, err := png.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	// The qrcode library snaps to a multiple of the code's module count,
	// so an exact match to qrPixelSize isn't guaranteed - only that it's
	// unmistakably in that range, not the tiny library default (~256 or
	// smaller for a typical device-authorization URL's module count).
	if imgCfg.Width < qrPixelSize-64 || imgCfg.Height < qrPixelSize-64 {
		t.Fatalf("qr PNG dimensions = %dx%d, want close to %dpx - did qrPixelSize regress to the small library default?", imgCfg.Width, imgCfg.Height, qrPixelSize)
	}
}
