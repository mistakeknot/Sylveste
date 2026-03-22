# Esoteric Cross-Cutting Analysis — Synthesis Report

**Date:** 2026-03-22
**Agents:** 7 esoteric reviewers (information theory, Conway's Law, economics, adversarial, physics, ecology, evolutionary)
**Target:** Full Demarch monorepo architecture
**Epic:** Demarch-og7m

## Severity Distribution

| Severity | Count | Agents |
|----------|-------|--------|
| **P0** | 2 | Conway's Law (Skaffen code duplication) |
| **P1** | 18 | All 7 agents contributed |
| **P2** | 16 | All 7 agents contributed |
| **P3** | 8 | Entropy, Conway, Economics, Temporal |

## Top 10 Findings (Cross-Agent, Deduplicated)

### 1. [P0] Skaffen Duplicates Alwe/Zaka Code (Conway's Law)
Skaffen's `internal/observer/cass.go` and `internal/provider/tmuxagent/` are copy-forks of Alwe and Zaka with active drift (`parseJSONLEvent` vs `ParseJSONLEvent`). Bug fixes in one copy won't propagate to the other.
**Fix:** Skaffen imports from Alwe/Zaka as Go module dependencies.

### 2. [P1] Agent Impersonation via X-Agent-ID Header (Adversarial)
Intermute's auth middleware reads agent identity from an unauthenticated `X-Agent-ID` header. On localhost (default), any process can steal file reservations by impersonating another agent.
**Fix:** Bind agent identity to registration-time session token, not per-request header.

### 3. [P1] Phase FSM Divergence — Clavain (9 phases) vs Skaffen (6 OODARC) (Economics + Ecology)
Two independent phase systems with deprecated compatibility aliases. When aliases are removed (as code comments instruct), MCP tool gating breaks silently. The kernel hardcodes `"executing"` in `handler_spawn.go:30`, breaking non-Clavain phase vocabularies.
**Fix:** Shared phases contract in `sdk/interbase/phases/phases.go`. Make spawn trigger configurable per run.

### 4. [P1] Routing Superstar Effect — No Per-Agent Cap (Phase Transitions)
`selectQuality()` in scoring.go assigns by highest score with no per-agent limit. Context penalty (0.3 max) is outweighed by stacked bonuses (0.60 max). One agent absorbs all tasks at 5+ concurrent agents.
**Fix:** Add `maxPerAgent` cap to `selectQuality()` matching `selectBalanced()`.

### 5. [P1] Work Context Extinction Debt (Ecology)
The `(bead_id, run_id, session_id)` trinity is reconstructed independently in 8+ locations with no named type. `session-end-release.sh` and `heartbeat.sh` have identical bead-ID reconstruction logic that can drift.
**Fix:** Define `WorkContext` struct, pass through hook chain.

### 6. [P1] Event Pipeline Nucleation (Phase Transitions + Entropy)
`ListEvents` uses a shared LIMIT across 4 tables via UNION ALL. High-volume coordination events (lock acquire/release) crowd out phase and review events. EventEnvelope carries 6/10 dead fields.
**Fix:** Per-source sub-limits in ListEvents. Lazy envelope serialization.

### 7. [P1] Bead Content Poisoning (Adversarial)
`bd set-state` writes are unauthenticated. Poisoning `ic_run_id` hijacks sprint operations. Poisoning `dispatch_count` bypasses the dispatch cap. No writer verification on any critical state field.
**Fix:** Writer identity field on critical state keys. Verify run ownership before use.

### 8. [P1] Safety Floor Ratchets Outrank Calibration (Temporal + Economics)
Routing overrides (fd-safety: sonnet) sit above calibration system in resolution chain. B3 calibration has been in shadow mode since creation. No downward path exists — `_routing_apply_safety_floor()` only clamps upward.
**Fix:** Promote B3 to enforce. Add expiry dates to overrides. Safety floors derived from calibration, not hardcoded.

### 9. [P1] Autonomy Hysteresis — No System-Wide Downward Transition (Phase Transitions)
Gaining autonomy requires explicit human action. Losing it is per-agent circuit breaker only. If 7/10 agents trip breakers, system is still nominally "autonomous." No automatic recovery from tripped breaker (30-day clock only).
**Fix:** System-level circuit breaker at >50% agents tripped. Explicit reset function requiring N clean sessions.

### 10. [P1] Ockham/Clavain Dispatch Shadow Module (Conway's Law)
Clavain has 2,500+ lines of working dispatch/intent/authority logic. Ockham has empty packages for the same concepts. No reference to "Ockham" anywhere in Clavain. Migration will be strangler-fig, not incremental.
**Fix:** Define `DispatchAdvice` interface contract before writing Ockham code. Clavain consumes it.

## Cross-Agent Pattern Recognition

### Pattern A: "Static Constants Masquerading as Intelligence" (3 agents)
Phase transitions, temporal, and ecology all independently found that static thresholds (interspect confidence, routing safety floors, complexity tiers, trust decay) lack calibration loops. PHILOSOPHY.md's own 4-stage closed-loop pattern is incomplete for 4/6 documented domains.

### Pattern B: "Silent Degradation Under Concurrent Load" (4 agents)
Adversarial, phase transitions, temporal, and economics all found systems that silently degrade: interspect.db drops writes at 5+ agents (silent `2>/dev/null || true`), event pipeline crowds out low-volume sources, reservation contention grows O(N*M) with no cap, trust evidence is lost without logging.

### Pattern C: "Architectural Intent vs. Code Reality" (3 agents)
Conway, ecology, and temporal found the same gap: Ockham (empty), Alwe (copy of Skaffen), the Work Context type (unnamed), Authority Scope (prose only). The architecture documentation describes a target state that the code hasn't reached, and the gap is widening as Clavain and Skaffen evolve independently.

## Agent-by-Agent Finding Count

| Agent | P0 | P1 | P2 | P3 |
|-------|----|----|----|----|
| fd-adversarial-architecture-exploitation | 0 | 3 | 3 | 1 |
| fd-conways-law-topology | 2 | 1 | 3 | 2 |
| fd-coupling-cost-economics | 0 | 3 | 3 | 2 |
| fd-phase-transition-dynamics | 0 | 3 | 3 | 0 |
| fd-abstraction-species-diversity | 0 | 2 | 4 | 0 |
| fd-interface-entropy-budget | 0 | 0 | 3 | 3 |
| fd-temporal-architecture-pressure | 0 | 6 | 3 | 1 |
| **Total** | **2** | **18** | **22** | **9** |

## Recommended Priority Sequence

1. **Immediate (security):** Agent impersonation fix + reservation starvation cap (adversarial P1s)
2. **This sprint:** Skaffen→Alwe/Zaka import (P0 dedup), phase contract, superstar cap
3. **Next sprint:** Work Context type, event pipeline sub-limits, bead state writer verification
4. **Backlog:** Safety floor reform (requires B3 promotion), autonomy hysteresis, Ockham contract
