package handlers

import (
	"net"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Brute-force protection for the endpoints that take a password. Only failed
// attempts count, so a person logging in normally never sees a 429 — but an
// attacker walking a password list runs out of budget quickly.
//
// In-memory and per-process, which is the right size for a single-binary
// self-hosted server. Restarting clears the counters; that's acceptable, since
// an attacker can't trigger a restart.
const (
	loginMaxFailures = 10
	loginWindow      = 15 * time.Minute
)

type failureCounter struct {
	mu   sync.Mutex
	hits map[string][]time.Time
}

var loginLimiter = &failureCounter{hits: map[string][]time.Time{}}

// blocked reports whether this key is over budget, pruning expired attempts on
// the way past.
func (c *failureCounter) blocked(key string) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.prune(key)) >= loginMaxFailures
}

// record adds a failed attempt.
func (c *failureCounter) record(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.hits[key] = append(c.prune(key), time.Now())
}

// reset clears a key after a successful login, so one bad typo before a correct
// password doesn't count against you.
func (c *failureCounter) reset(key string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	delete(c.hits, key)
}

// prune drops attempts older than the window. Caller must hold the lock.
func (c *failureCounter) prune(key string) []time.Time {
	cutoff := time.Now().Add(-loginWindow)
	kept := c.hits[key][:0]
	for _, t := range c.hits[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) == 0 {
		delete(c.hits, key)
		return nil
	}
	c.hits[key] = kept
	return kept
}

// clientIP is the address to rate-limit against. X-Forwarded-For and X-Real-IP
// are only honoured when the connection itself came from the loopback reverse
// proxy — otherwise anyone could spoof a header and dodge the limit entirely.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if ip := net.ParseIP(host); ip == nil || !ip.IsLoopback() {
		return host
	}
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// Left-most entry is the original client.
		if first := strings.TrimSpace(strings.Split(xff, ",")[0]); first != "" {
			return first
		}
	}
	if real := strings.TrimSpace(r.Header.Get("X-Real-IP")); real != "" {
		return real
	}
	return host
}
