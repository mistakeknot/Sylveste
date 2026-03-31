---
artifact_type: prd
bead: sylveste-rsj.7
date: 2026-03-31
---

# PRD: Composable Discourse Protocols

## Problem

Interflux's reaction round (rsj.2) lets agents respond to each other, but the discourse is unstructured — any agent can say anything. There's no move validation, no health monitoring, no systematic way to evolve the conversation frame. Five formal discourse protocols from jazz/improv/philosophy research could make multi-agent discourse measurably better, but only if they compose cleanly.

## Solution

Implement 5 composable discourse protocols as a layered stack within interflux's existing reaction round infrastructure. Deploy in 3 phases ordered by effort/impact:

1. **Phase 1 (this bead):** Sawyer Flow Envelope (health monitor) + Lorenzen Dialogue (move validation) — always-on, zero new dispatch cost
2. **Phase 2 (future bead):** Yes-And with Degeneration Guards — enabled when reaction round is active
3. **Phase 3 (future bead):** Conduction Protocol + Pressing Cycle — opt-in, multi-round orchestration

## Scope (Phase 1 Only)

### In Scope

- **Discourse health computation** in synthesis phase: participation Gini, novelty rate, response relevance
- **Health output artifact:** `discourse-health.json` alongside synthesis output
- **Lorenzen move types** in reaction output contract: attack, defense, new-assertion
- **Move legality validation** in synthesis: score reactions by structural validity
- **Configuration:** `config/flux-drive/discourse/` directory with `sawyer.yaml` and `lorenzen.yaml`
- **Convergence gate refinement:** existing overlap-based gate becomes one of Sawyer's health checks

### Out of Scope (Phase 2/3)

- Yes-And premise tracking and guard thresholds
- Conduction signal vocabulary and role assignment
- Pressing Cycle referent-drift and multi-round support
- Domain-specific discourse profiles

## Success Criteria

1. Every flux-drive review produces `discourse-health.json` with 3 metrics
2. Reaction output contract includes Lorenzen move types (attack/defense/new-assertion)
3. Synthesis reports move legality violations (non-sequiturs, circular reasoning)
4. No increase in total token cost (monitoring is computed from existing outputs)
5. No new agent dispatches — all computation happens in orchestrator and synthesis

## Non-Functional Requirements

- **Backward compatible:** Reviews without reaction round still produce health metrics (from Phase 2 output alone)
- **Configuration-driven:** All thresholds in YAML, overridable per domain profile
- **Observable:** Health metrics in synthesis output and sprint summary
