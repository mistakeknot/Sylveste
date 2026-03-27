---
category: pattern
tags: [skaffen, security, ssrf, web-tools]
bead: Sylveste-6i0.20
date: 2026-03-12
---

# Pattern: SSRF Defense for Agent Web Tools

## Context

When adding web fetch capabilities to an AI agent, the LLM controls the URL. This creates a Server-Side Request Forgery (SSRF) risk — prompt injection could direct the agent to fetch internal network resources (cloud metadata at 169.254.169.254, localhost services, private IPs).

## Three-Layer Defense

### Layer 1: URL Pre-validation
Parse the URL and reject before any network activity:
- Scheme whitelist: `https` only
- Hostname blocklist: `localhost`, trailing-dot variants
- IP blocklist: loopback, private (RFC-1918), link-local, unspecified, cloud metadata, IPv4-mapped IPv6

### Layer 2: DNS Resolution Validation (DialContext)
URLs pass Layer 1 as hostnames, but DNS can resolve to blocked IPs (DNS rebinding):
```go
func ssrfSafeDialer() func(ctx, network, addr string) (net.Conn, error) {
    return func(...) {
        ips, _ := net.DefaultResolver.LookupIPAddr(ctx, host)
        for _, ip := range ips {
            if isBlockedIP(ip.IP) { return nil, err }
        }
        return dialer.DialContext(ctx, network, resolvedIP+":"+port)
    }
}
```
Key: dial the *resolved* IP string, not the hostname, so there's no second resolution.

### Layer 3: Trust Gate (Human in the Loop)
`web_fetch` requires `Prompt` (user approval) — this is the final defense against prompt injection directing fetches to URLs the pre-validation allows but the user wouldn't.

## Lessons

1. **Integer skip counters break on mismatched HTML nesting.** A `<nav><script>...</nav>...</script>` sequence drives a counter negative-equivalent, suppressing all remaining text. Use a tag stack that pops by name.

2. **Error-path body drains must be bounded.** `io.Copy(io.Discard, resp.Body)` on a 500 response from a malicious server can hold a goroutine for the full client timeout with an infinite body. Always `io.LimitReader`.

3. **`Register()` vs `RegisterForPhases()` is a silent failure.** `Register()` only gates to build phase. If you want a tool in brainstorm/plan phases, you MUST use `RegisterForPhases`. No error, no warning — the tool just doesn't appear in the phase's tool list.

4. **Don't auto-allow external API tools.** Even read-only tools like web search cost money and leak queries to third parties. Keep them at `Prompt` so the user sees what's being searched.
