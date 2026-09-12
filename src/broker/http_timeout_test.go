package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// TestProviderHTTPClient_BoundsHungResponse proves the v2.7.0 timeout
// hardening actually works: a provider that accepts the connection but
// never writes a response must not hang the caller forever. Before
// this milestone, every broker->provider call used http.DefaultClient/
// the http package-level Get/PostForm helpers, none of which have any
// timeout - this test would hang until the test binary's own overall
// timeout without providerHTTPClient's bound.
func TestProviderHTTPClient_BoundsHungResponse(t *testing.T) {
	prevTimeout := providerHTTPClient.Timeout
	providerHTTPClient.Timeout = 300 * time.Millisecond
	t.Cleanup(func() { providerHTTPClient.Timeout = prevTimeout })

	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-release // never respond until the test cleans up
	}))
	// Cleanup runs LIFO: release the hung handler FIRST (registered
	// last), only then close the server - otherwise srv.Close() would
	// itself block forever waiting for the still-blocked handler to
	// return.
	t.Cleanup(srv.Close)
	t.Cleanup(func() { close(release) })

	start := time.Now()
	_, err := providerHTTPClient.Get(srv.URL)
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("expected a timeout error from a hung response, got nil")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("providerHTTPClient did not bound the hung request: took %v", elapsed)
	}
}
