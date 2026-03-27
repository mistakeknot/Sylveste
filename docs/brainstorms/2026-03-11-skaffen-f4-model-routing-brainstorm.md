---
artifact_type: brainstorm
bead: Sylveste-4xp
stage: discover
---
# Brainstorm: Skaffen F4 — Model Routing

## What We're Building

Phase-aware model routing for Skaffen's OODARC loop. Each phase selects the optimal model based on: hardcoded defaults → routing.yaml overrides → env var overrides → budget constraints → complexity classification. Budget degradation downgrades models gracefully rather than hard-stopping.

## Why This Approach

Clavain's `config/routing.yaml` has been battle-tested across 334K+ messages with economy/quality mode toggle. The data shows:
- **brainstorm is the only phase that benefits from opus** — creative exploration needs heavy reasoning
- **Research/synthesis tasks work fine on haiku** — grep, read, summarize don't need reasoning
- **fd-safety on haiku scored 47%, fd-correctness 26%** — some tasks have hard model floors
- **Complexity tiers (C1-C5)** in shadow mode show promise for dynamic promotion/demotion

Skaffen should mirror this proven routing table rather than inventing a new one. Since Skaffen is a single-agent runtime (not an orchestrator with subagents), routing is simpler: phase → model, with budget and complexity layers.

## Key Decisions

1. **Phase defaults match Clavain economy mode**: brainstorm=opus, all other phases=sonnet. This is the control baseline with known-good cost/quality tradeoffs.

2. **Three-layer config resolution** (highest priority first):
   - Env vars: `SKAFFEN_MODEL_BUILD=haiku` overrides just that phase
   - routing.yaml: `~/.skaffen/routing.json` (JSON, not YAML — Go stdlib has no YAML) with phase map + budget config
   - Hardcoded defaults: the economy table above

3. **Budget enforcement is configurable with graceful degradation as default**:
   - Three modes: `graceful` (default), `hard-stop`, `advisory`
   - Graceful: 0-80% use configured model, 80-100% downgrade to cheapest in chain, 100%+ warn + continue on haiku
   - Users set budget mode in routing.json or via env `SKAFFEN_BUDGET_MODE`

4. **Complexity layer in shadow mode**: C4-C5 tasks promote to opus, C1-C2 demote to haiku. Shadow mode logs what would change without applying. Enforce mode applies overrides.

5. **Read Clavain's routing.yaml when available**: If `config/routing.yaml` exists (Clavain project context), parse the `subagents.phases` section and use it. Fall back to hardcoded defaults otherwise. This gives maximum compatibility with the existing ecosystem.

6. **Shadow experiment bead**: Create a separate bead to run controlled experiments comparing haiku/sonnet/opus across phases and subagents, using the current economy defaults as control.

## Router Interface Extension

Current:
```go
type Router interface {
    SelectModel(phase tool.Phase) (model string, reason string)
}
```

Extended:
```go
type Router interface {
    SelectModel(phase tool.Phase) (model string, reason string)
    RecordUsage(tokens provider.Usage) // feed budget tracker
}
```

Keep `SelectModel` signature unchanged — budget state lives inside the router, not as a parameter. `RecordUsage` is called by the loop after each turn to update the budget tracker. The router uses internal state to degrade when budget thresholds are hit.

## Open Questions

- Should the fallback chain be configurable? (e.g., opus → sonnet → haiku) or hardcoded?
  - **Tentative**: hardcoded opus→sonnet→haiku is sufficient for v0.2. Configurable in v0.3.
- Should we expose a `--budget` CLI flag for per-run token limits?
  - **Tentative**: Yes, `--budget 500000` sets max input tokens for the session.
- How to detect rate limiting from the provider to trigger fallback?
  - **Tentative**: Provider returns a typed error; router catches it and retries with next model in chain. Deferred to v0.2.1 if complex.
