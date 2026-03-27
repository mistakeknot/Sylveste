---
name: Ockham
description: "Interverse driver capability: Ockham"
---
# Gemini Skill: Ockham

You have activated the Ockham capability.

## Base Instructions
# Ockham — Agent Reference

## Architecture

Ockham is the factory governor — the Cyberstride in Sylveste's Cybersyn-inspired architecture. It sits between the principal's strategic intent (expressed through Meadowsyn or CLI) and the factory's execution (Clavain self-dispatch, Zaka agent steering, Alwe observation).

```
Principal
  │ intent directives
  ▼
Ockham (governor)
  │ dispatch weights + authority grants
  ├──→ Clavain (self-dispatch scoring)
  ├──→ Zaka (agent spawning)
  ├──→ Alwe (observation queries)
  └──→ Intercore (events, gates)
```

## Package Map

| Package | Purpose | Key Types |
|---------|---------|-----------|
| `intent` | Theme budgets, priority overrides | `Directive`, `ThemeBudget`, `IntentStore` |
| `authority` | Trust tiers, domain grants | `Authority`, `DomainGrant`, `DelegationCeiling` |
| `anomaly` | Algedonic signals, circuit breakers | `Signal`, `Detector`, `CircuitBreaker` |
| `dispatch` | Weight synthesis | `Scorer`, `WeightConfig`, `DispatchAdvice` |

## Core Concepts

### Intent Directives
The principal expresses strategic intent at the theme level, not the bead level:
- "Spend 40% on auth, 30% on performance, 30% on whatever's ready"
- "Freeze all non-critical work until the release"
- "Prioritize anything blocking the API launch"

Ockham translates these to scoring weights that Clavain's dispatch function consumes.

### Authority Tiers
From the AI factory brainstorm (Wave 3):
- `authority = min(fleet_tier, domain_grant)`
- CODEOWNERS-style domain globs
- 5 safety invariants: no self-promotion, delegation ceiling, action-time validation, audit completeness, human halt supremacy

### Algedonic Signals
From Stafford Beer's VSM — pain/pleasure signals that bypass hierarchy:
- **Pain:** quarantined beads, circuit breaker trips, gate failures, stale claims
- **Pleasure:** clean first-attempt completions, improving cycle time, shrinking backlog
- These surface first in Meadowsyn, not buried in logs

### Autonomy Ratchet
Three modes, progressing as the factory earns trust:
1. **Shadow** — Ockham proposes dispatch, principal approves/overrides
2. **Supervised** — Ockham dispatches, principal reviews outcomes
3. **Autonomous** — Ockham dispatches, principal audits periodically

## Build & Test

```bash
go build ./cmd/ockham
go test ./... -count=1
go vet ./...
```

## CLI (planned)

```bash
ockham intent --theme auth --budget 40%
ockham intent --freeze non-critical
ockham authority grant agent-3 --domain "core/*"
ockham authority tier agent-3 --level supervised
ockham anomaly --since 1h
ockham health
ockham dispatch advise   # show what would be dispatched next
```

## Dependencies

- Beads (`bd` CLI) — reads backlog state
- Alwe — queries session history for anomaly detection
- Intercore — reads events, gate verdicts
- Clavain — consumes dispatch weights

## Related Research

- `docs/brainstorms/2026-03-19-ai-factory-orchestration-brainstorm.md`
- `docs/plans/2026-03-20-ai-factory-wave1-foundation.md`
- `docs/research/flux-research/authority-tiers/synthesis.md`
- `docs/research/flux-research/phase1-self-dispatch/synthesis.md`


