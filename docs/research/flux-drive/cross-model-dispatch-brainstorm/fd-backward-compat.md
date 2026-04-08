### Findings Index
- P1 | BC-1 | "Constraints" | No feature gate specified — cross-model dispatch has no off switch
- P2 | BC-2 | "Scope" | flux-review shares code paths with flux-drive but is declared out of scope without verifying isolation
- P2 | BC-3 | "Implementation Sketch" | New log format may break existing interstat log parsers
- P3 | BC-4 | "Implementation Sketch" | No rollback plan if cross-model dispatch degrades finding quality
Verdict: needs-changes

## Summary

The brainstorm follows interflux's progressive enhancement pattern (lib-routing.sh availability is optional), but omits the feature gate that would let operators disable cross-model dispatch without reverting code. Every other interflux feature (AgentDropout, incremental expansion, budget enforcement) has a config toggle in budget.yaml. Cross-model dispatch should too.

## Issues Found

### 1. [P1] BC-1: No feature gate for cross-model dispatch

**File:** brainstorm "Constraints" section, lines 174-179; "Scope" lines 183-196
**Codebase ref:** `interverse/interflux/config/flux-drive/budget.yaml`, lines 40-54

budget.yaml has toggles for:
- `dropout.enabled: true` (line 43)
- `incremental_expansion.enabled: true` (line 52)

Cross-model dispatch has no equivalent toggle. The brainstorm's implementation adds `routing_adjust_expansion_tier()` to the dispatch path with no conditional gate.

**Failure scenario:** Cross-model dispatch is deployed and causes finding quality regression (haiku agents miss P1 issues). The only way to disable it is to revert the code change or manually edit lib-routing.sh — neither is a clean rollback.

**Smallest fix:** Add to budget.yaml:
```yaml
cross_model_dispatch:
  enabled: true
  # Set false to disable tier adjustment — all Stage 2 agents use Step 2.0.5 models
```

In the dispatch path, check `cross_model_dispatch.enabled` before calling `routing_adjust_expansion_tier`. When disabled, fall through to existing behavior (all agents use the Step 2.0.5 model map). Zero behavioral change when off.

### 2. [P2] BC-2: flux-review code path isolation not verified

**File:** brainstorm "Out of Scope" line 196: "flux-review changes (no expansion pool in review mode)"
**Codebase ref:** `interverse/interflux/skills/flux-drive/SKILL-compact.md`, Phase 2

The brainstorm correctly states flux-review has no expansion pool, so cross-model dispatch doesn't apply. But flux-review and flux-drive share:
- `lib-routing.sh` (model resolution)
- `routing_resolve_agents()` (the Step 2.0.5 call)
- Agent prompt templates

If `routing_adjust_expansion_tier()` is added to lib-routing.sh as a new public function, it doesn't affect flux-review (which never calls it). But if a future refactor of `routing_resolve_agents` incorporates tier adjustment logic internally (e.g., an `--expansion-tier` flag as mentioned in Option A, line 61), flux-review would inherit the behavior.

**Question:** Will `routing_adjust_expansion_tier` be a standalone function (safe), or will it be integrated into `routing_resolve_agents` via a flag (risky for flux-review)?

The brainstorm's Option A mentions "A second `routing_resolve_agents` call with an `--expansion-tier` flag" — this would be the risky approach. The implementation sketch uses a standalone function, which is the safer choice. The brainstorm should explicitly state: "Cross-model dispatch is a standalone function, NOT a flag on routing_resolve_agents."

### 3. [P2] BC-3: New log format compatibility

**File:** brainstorm lines 163-169 (logging example)

The brainstorm introduces a new log block:
```
Cross-model dispatch (Stage 2):
  fd-performance: sonnet -> sonnet (score=3, P0 adjacent)
  ...
Budget pressure: low (82% remaining)
Estimated savings: ~35K tokens
```

interstat parses flux-drive logs to extract cost data. The existing log format includes:
- AgentDropout block (from expansion.md line 59)
- Budget triage table (from SKILL-compact.md)
- Per-agent dispatch lines

A new "Cross-model dispatch" block could confuse parsers that expect a fixed log structure. This is P2 because interstat is tolerant of unrecognized lines (it pattern-matches known fields), but the "Estimated savings" line could be double-counted with AgentDropout's "Estimated savings" line if both use the same prefix.

**Smallest fix:** Use a distinct prefix: "Tier adjustment savings: ~35K tokens" instead of "Estimated savings: ~35K tokens" (which AgentDropout already uses).

### 4. [P3] BC-4: No rollback plan

**File:** brainstorm "Risk Assessment" and "Success Criteria"

The brainstorm defines success criteria (line 213-218) but no failure criteria or rollback triggers. What happens if:
- P0/P1 recall drops by >5%? (Turn off via feature gate)
- Token savings < 5K consistently? (Feature is pointless, remove complexity)
- Budget accounting mismatch causes sprint budget overruns? (Turn off, investigate)

A rollback plan would be: "If intertrust shows recall regression >5% over 10 runs, disable cross-model dispatch via `cross_model_dispatch.enabled: false` in budget.yaml."

## Improvements

1. Add a "Rollout Plan" section: shadow mode first (log adjustments but don't apply them), then enforce mode. This mirrors the B2 complexity routing pattern already in lib-routing.sh (`_ROUTING_CX_MODE: off|shadow|enforce`).
2. Add `cross_model_dispatch.mode: off|shadow|enforce` to budget.yaml for consistency with the B2 pattern.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 1, P2: 2, P3: 1)
SUMMARY: No feature gate exists for cross-model dispatch — every other comparable feature has a budget.yaml toggle. Adding an enabled flag and shadow mode would follow existing patterns (AgentDropout, B2 complexity routing) and provide clean rollback.
---
<!-- flux-drive:complete -->
