# Skaffen Quality Signals — Brainstorm

**Bead:** Sylveste-khlh
**Date:** 2026-03-14
**Status:** Brainstorm complete

## Problem

Skaffen's OODARC loop has all 6 phases but the Compound phase is a stub. Evidence is emitted per-turn to `~/.skaffen/evidence/<session_id>.jsonl` but no future session reads it. Every session starts cold — Orient has no memory of past quality patterns.

## Decision Record

### D1: Storage — Mutation history store (new package)

New `internal/mutations/` package with JSONL store at `~/.skaffen/mutations/quality-signals.jsonl`.

**Why:** Clean separation of concerns:
- `evidence/` = raw per-turn operational data (existing)
- `mutations/` = aggregated cross-session quality signals (new)
- `sessions/` = conversation history (existing)

The mutations store is the natural home for future cross-session learning (not just quality signals).

### D2: Dimensions — Three-dimension model (hard/soft/human)

```go
type QualitySignal struct {
    SessionID  string       `json:"session_id"`
    Timestamp  string       `json:"timestamp"`
    Phase      tool.Phase   `json:"phase"`
    Hard       HardSignals  `json:"hard"`
    Soft       SoftSignals  `json:"soft"`
    Human      HumanSignals `json:"human"`
}

type HardSignals struct {
    TestsPassed     *bool   `json:"tests_passed,omitempty"`
    BuildSuccess    *bool   `json:"build_success,omitempty"`
    TokenEfficiency float64 `json:"token_efficiency"`
    TurnCount       int     `json:"turn_count"`
}

type SoftSignals struct {
    ComplexityTier  int     `json:"complexity_tier"`
    ToolErrorRate   float64 `json:"tool_error_rate"`
    ToolDenialRate  float64 `json:"tool_denial_rate"`
}

type HumanSignals struct {
    ApprovalRate float64 `json:"approval_rate"`
    Outcome      string  `json:"outcome"`
}
```

**Why:** Maps cleanly to signal provenance:
- Hard = objective, automated measurements
- Soft = derived from tool/agent behavior
- Human = user interaction patterns

### D3: Orient consumption — System prompt + dedicated tool

Dual-mode read:
1. **System prompt injection:** Compact summary injected when `phase == Orient` (always available, zero cost)
2. **`quality_history` tool:** Gated to Orient phase, allows detailed drill-down on demand

**Why:** The prompt gives the LLM passive awareness ("last 5 sessions averaged 14 turns, 1 had test failures"). The tool gives it active investigation capability when patterns warrant deeper analysis.

## Data Flow

```
Session N:
  Act → Reflect → Compound
                    ↓
              Aggregate per-turn evidence
                    ↓
              Write QualitySignal to
              ~/.skaffen/mutations/quality-signals.jsonl

Session N+1:
  Observe → Orient
              ↓
        Read last 5 QualitySignals
              ↓
        Inject summary into system prompt
        + Register quality_history tool
              ↓
        Decide (informed by history)
```

## Key Files to Modify

| File | Change |
|------|--------|
| `internal/mutations/signal.go` | **NEW** — QualitySignal types |
| `internal/mutations/store.go` | **NEW** — JSONL read/write |
| `internal/mutations/aggregate.go` | **NEW** — Aggregate evidence → signal |
| `internal/agent/agent.go` | Wire mutations.Store into Agent |
| `internal/agent/deps.go` | Add SignalStore interface |
| `internal/agent/compound.go` | **NEW** — Compound phase logic (aggregate + write) |
| `internal/session/session.go` | Inject quality summary in Orient prompt |
| `internal/tool/quality_history.go` | **NEW** — Orient-gated drill-down tool |
| `internal/agent/gated_registry.go` | Gate quality_history to Orient |

## Risks

1. **Evidence file locking** — Compound reads evidence while Reflect may still be writing. Mitigation: Compound runs after Reflect in FSM, so evidence file is complete by then.
2. **Signal bloat** — quality-signals.jsonl grows unbounded. Mitigation: ReadRecent(N) only reads last N entries; add rotation in v0.2.
3. **System prompt budget** — Injected summary competes for context window. Mitigation: Keep summary under 200 tokens; truncate if budget < threshold.
