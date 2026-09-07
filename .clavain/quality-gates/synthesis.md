# Quality Gates — sylveste-nfqo

**Date:** 2026-04-19
**Diff:** /tmp/qg-diff-nfqo-1776626890.txt (4755 lines, 31 files under core/intermute/)
**Reviewers:** fd-correctness, fd-safety, fd-architecture, fd-quality (parallel)

## Verdict: NO-GO

3 P0 ship-blockers + 7 P1 must-fix issues.

## P0 Ship-Blockers

1. **arch-plan-drift-1:** internal/http imports internal/livetransport concretely — the LiveDelivery interface was meant to prevent exactly this. Fix: move Target to internal/core, move WrapEnvelope behind the interface or to internal/core.
2. **arch-plan-drift-2:** handleSendMessage is 180 lines after extraction — plan specified ~30-50. Fix: pull inline policy-override block into resolveRecipientPlans.
3. **corr-orphan-event:** transport=live inject-fail commits orphan PokeResultFailed audit event; also partial-inject for multi-recipient live (one recipient receives poke before caller gets 503). Fix: skip AppendEvents in live+failure branch.

## P1 Must-Fix

- safety: InMemory.UpsertWindowIdentityWithToken accepts any non-empty token (test stub gap)
- safety: no http.MaxBytesReader on new decoders (DoS exposure if non-loopback binding added)
- arch: recipientPlan.Target is *livetransport.Target (root cause of P0-1)
- arch: broadcastLimiter + liveRateLimiter duplicate implementations
- arch: noopLiveDelivery.Deliver returns error; should return nil for transport=async tests
- quality: inboxPoke struct duplicated between cmd + internal/http
- quality: URL query params not escaped via url.QueryEscape in CLI

## Plan Commitments Verified (no drift)

- Atomic durable + poke staging via AppendEvents
- INSERT OR IGNORE on pending_pokes (no surfaced_at clearing)
- Staleness inside GetAgentFocusState (2s threshold)
- WrapEnvelope body sanitization (--- escape + C0 strip)
- Registration token ownership check
- Feature flag gate (config.live_transport_enabled)
- Rate limiter (10/min per sender-recipient)
- Single EventPeerWindowPoke with result field
- Named TransportMode type
- Migrations follow tableHasColumn pattern; schema.sql has no ALTER TABLE
- TransportOrDefault normalization at every write site

## Test State

- go build ./... — PASS
- go vet ./... — PASS  
- go test ./... — PASS
- go test -tags tmux_integration ./... — PASS (after test fix: session-only target)
