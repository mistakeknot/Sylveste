# Flux Drive Review — 2026-04-06-interop-brainstorm

**Reviewed**: 2026-04-06 | **Agents**: 9 launched, 9 completed | **Verdict**: risky

**Tracks**: 5 domain-expert project agents (primary focus) + 4 orthogonal-domain agents (prior run)

---

## Verdict Summary

| Agent | Category | Status | Summary |
|-------|----------|--------|---------|
| fd-go-goroutine-isolation | Project | NEEDS_ATTENTION | 3 P1: no panic recovery contract, unbounded channels, unbounded worker pools |
| fd-webhook-delivery-semantics | Project | RISKY | 1 P0 (missing signature verification), 3 P1: no async processing, no dedup, no Notion fallback |
| fd-bidirectional-sync-conflicts | Project | RISKY | 1 P0 (ancestor store not persisted), 3 P1: untrusted clocks, global policy, silent tiebreaking |
| fd-adapter-interface-contracts | Project | NEEDS_ATTENTION | 3 P1: no behavioral contracts, identity mapping deferred, no error taxonomy |
| fd-daemon-operational-reliability | Project | RISKY | 1 P0 (SIGTERM event loss), 3 P1: no health/ready split, no checkpoint, no lifecycle coupling |
| fd-atc-flow-management | Orthogonal | RISKY | 2 P0: no per-entity serialization, conflict detection after emission |
| fd-laboratory-middleware | Orthogonal | RISKY | 1 P0: Event lacks routing context |
| fd-scada-energy-management | Orthogonal | RISKY | 1 P0: panic recovery loses in-flight events |
| fd-supply-chain-control-tower | Orthogonal | RISKY | 1 P0: three-way merge overwrites on convergent state transitions |

---

## Critical Findings (P0)

Five P0 findings across 7 agents. Three have multi-agent convergence (strongest signal).

1. **[P0-3] No graceful shutdown — SIGTERM loses in-flight events permanently** (3/9 agents: fd-daemon-operational-reliability, fd-scada-energy-management, fd-atc-flow-management)
   Docker SIGTERM kills goroutines immediately. Events already ACKed by the webhook handler but not yet processed by adapters are lost permanently. Invisible sync divergence on every deploy.

2. **[P0-2] Common ancestor store persistence unspecified** (2/9 agents: fd-bidirectional-sync-conflicts, fd-scada-energy-management)
   Three-way merge requires a persisted common ancestor. If in-memory only, daemon restart causes either silent data loss (wrong merge base) or hundreds of false conflicts.

3. **[P0-1] Webhook signature verification absent** (1/9 agents: fd-webhook-delivery-semantics)
   The internet-facing webhook endpoint has no HMAC verification. An attacker can forge payloads that close beads, create issues, or inject content into Notion. Beads is the "single source of truth for work tracking."

4. **[P0-4] No per-entity serialization** (1/9 agents: fd-atc-flow-management)
   Two adapters updating the same entity without locking — goroutine scheduling determines the winner.

5. **[P0-5] Event lacks routing context** (1/9 agents: fd-laboratory-middleware)
   Canonical Event has no cross-system ID hints. FS adapter silently drops events it cannot route.

---

## Important Findings (P1)

Fifteen P1 findings. Key themes with convergence:

**Concurrency contracts** (convergence: 2-3 agents each):
- No panic recovery contract for adapter goroutine pools (fd-go-goroutine-isolation, fd-scada-energy-management)
- Event bus backpressure unspecified — slow adapter blocks webhook handler (fd-go-goroutine-isolation, fd-atc-flow-management)
- Health vs readiness distinction missing — crashed adapters invisible to Docker (fd-daemon-operational-reliability, fd-scada-energy-management)

**Sync correctness** (convergence: 2 agents each):
- Conflict resolution policy is global, not per-adapter-pair (fd-bidirectional-sync-conflicts, fd-supply-chain-control-tower)
- No HandleEvent error taxonomy — hub cannot distinguish retry from fatal (fd-adapter-interface-contracts, fd-laboratory-middleware)
- Notion webhook no polling fallback (fd-webhook-delivery-semantics, fd-supply-chain-control-tower)

**Single-agent P1s** (no convergence but high impact):
- No async webhook processing contract (fd-webhook-delivery-semantics)
- No delivery ID deduplication (fd-webhook-delivery-semantics)
- LWW clock source unspecified (fd-bidirectional-sync-conflicts)
- Silent tiebreaking for unresolvable conflicts (fd-bidirectional-sync-conflicts)
- Adapter interface lacks behavioral contracts (fd-adapter-interface-contracts)
- Identity mapping deferred as open question (fd-adapter-interface-contracts)
- No recovery checkpoint on crash (fd-daemon-operational-reliability)
- MCP and webhook server lifecycle not coupled (fd-daemon-operational-reliability)
- Goroutine pool worker count unbounded (fd-go-goroutine-isolation)

---

## Section Heat Map

| Section | P0 | P1 | P2 | Agents Reporting |
|---------|----|----|-----|-----------------|
| Key Decisions | 3 | 10 | 5 | All 9 agents |
| Architecture Sketch | 1 | 2 | 2 | fd-go-goroutine-isolation, fd-atc-flow-management, fd-scada-energy-management |
| Day-1 Adapters | 0 | 2 | 1 | fd-webhook-delivery-semantics, fd-supply-chain-control-tower |
| Open Questions | 0 | 1 | 1 | fd-adapter-interface-contracts, fd-bidirectional-sync-conflicts |
| Why This Approach | 0 | 1 | 0 | fd-webhook-delivery-semantics |

---

## Cross-Agent Convergence Themes

Three structural patterns emerged independently across both the domain-expert and orthogonal-domain agent tracks:

### 1. Event lifecycle is underspecified
Every agent — from goroutine isolation to SCADA to webhook semantics — found that the brainstorm treats event dispatch as completion. The hub has no concept of `dispatched -> in-flight -> acknowledged`. This causes data loss on shutdown, crash, and adapter failure. **Fix**: Add an event lifecycle with WAL-backed in-flight tracking.

### 2. Operational contracts are entirely missing
The brainstorm describes functional architecture (adapters, event bus, sync) but says nothing about operational behavior (shutdown, health, recovery, logging, resource limits). Five agents independently flagged this gap. **Fix**: Add Key Decisions 9-14 covering graceful shutdown sequence, health/readiness endpoints, recovery checkpoints, structured logging, Docker resource limits, and crash recovery strategy.

### 3. Conflict resolution assumes ideal conditions
Three-way merge and LWW are correct strategies, but the brainstorm assumes trusted clocks, persisted ancestors, and symmetric policies. All three assumptions are wrong in practice with four external systems. **Fix**: Specify per-adapter-pair directional authority policies, use interop's receive-time clock for LWW, persist the ancestor store as a first-class component.

---

## Recommended Key Decision Additions

Based on convergence across all 9 agents, these additions address the highest-risk gaps:

| # | Decision | Addresses |
|---|----------|-----------|
| 9 | **Webhook signature verification as non-bypassable middleware** | P0-1 |
| 10 | **Graceful shutdown: drain-then-stop sequence with configurable timeout** | P0-3 |
| 11 | **Persisted ancestor store (SQLite or flat JSON), not in-memory** | P0-2 |
| 12 | **Event lifecycle: dispatched/in-flight/acknowledged with WAL** | P0-3, P0-4, P0-5 |
| 13 | **Per-adapter-pair conflict policies with directional authority** | P1-6, P1-7 |
| 14 | **Adapter behavioral contracts (timeout, blocking, lifecycle) in GoDoc** | P1-8, P1-10 |
| 15 | **Identity mapping as first-class config using stable system IDs** | P1-9 |
| 16 | **Health + readiness endpoints; Docker healthcheck calls /ready** | P1-11 |
| 17 | **LWW uses interop receive-time clock, not external timestamps** | P1-5 |
| 18 | **Per-adapter HTTP transport isolation** | From orthogonal agents |

---

## Improvements Suggested

1. Document goroutine lifecycle state machine (Starting -> Running -> Draining -> Stopped) — fd-go-goroutine-isolation, fd-scada-energy-management
2. Add adapter compliance test suite validating behavioral contracts — fd-adapter-interface-contracts
3. Add Prometheus-compatible /metrics endpoint for operational alerting — fd-daemon-operational-reliability
4. Add sync state visualization MCP tool for debugging divergence — fd-bidirectional-sync-conflicts
5. Add dead letter queue for events that pass signature but fail processing — fd-webhook-delivery-semantics
6. Version the Adapter interface explicitly with compatibility checks — fd-adapter-interface-contracts

---

## Conflicts

No agent disagreements detected. All agents converged on the same risk areas from different angles. The orthogonal-domain agents (ATC, Lab, SCADA, Supply Chain) independently discovered the same three structural patterns as the domain-expert agents, providing high-confidence validation.

---

## Files

- Summary: `docs/research/flux-drive/2026-04-06-interop-brainstorm/summary.md` (this file)
- Findings: `docs/research/flux-drive/2026-04-06-interop-brainstorm/findings.json`
- Prior synthesis (orthogonal agents): `docs/research/flux-drive/2026-04-06-interop-brainstorm/synthesis.md`
- Individual reports:
  - `fd-go-goroutine-isolation.md` — goroutine panic recovery, channel backpressure, circuit breakers
  - `fd-webhook-delivery-semantics.md` — signature verification, idempotent processing, deduplication
  - `fd-bidirectional-sync-conflicts.md` — three-way merge, LWW clocks, per-adapter conflict policies
  - `fd-adapter-interface-contracts.md` — Go interface behavioral contracts, identity mapping, beads CLI enforcement
  - `fd-daemon-operational-reliability.md` — SIGTERM drain, health endpoints, crash recovery, Docker resource limits
  - `fd-atc-flow-management.md` — ATC lens: event routing, ordering, backpressure
  - `fd-laboratory-middleware.md` — Lab middleware lens: translation fidelity, schema versioning
  - `fd-scada-energy-management.md` — SCADA lens: fault isolation, circuit breaker, degraded-mode
  - `fd-supply-chain-control-tower.md` — Supply chain lens: authority hierarchy, golden record, reconciliation
