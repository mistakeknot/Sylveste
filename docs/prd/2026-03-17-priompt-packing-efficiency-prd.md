# PRD: Priompt Packing Efficiency Campaign

**Bead:** Sylveste-1x9l.1
**Type:** Autoresearch campaign
**Priority:** P2
**Owner:** mk

## Problem

Priompt's greedy packer leaves budget on the table. With tight budgets (common in real agent systems), wasted tokens mean excluded high-priority content. No observability exists to measure how much waste occurs or where.

## Goal

Maximize `PackingEfficiency` (tokens_used / budget) to ≥ 0.95 on the tight-budget benchmark, while maintaining or improving render latency.

## Non-Goals

- Replacing CharHeuristic with a real tokenizer (separate work)
- Changing the public API contract
- Optimizing for >100 elements (not a real-world scenario)

## Features

### F1: Packing Observability (prerequisite)
Add `PackingEfficiency`, `WastedTokens`, `ExcludedPrioritySum` to `RenderResult`.
**Acceptance:** Fields populated correctly in all benchmarks and tests.

### F2: Running Token Accumulation
Track token sum during packing instead of re-counting joined string.
**Acceptance:** Latency improvement measurable on Render100; exact same TotalTokens values.

### F3: Fill Pass
After greedy descent, try excluded elements smallest-first to fill remaining budget.
**Acceptance:** PackingEfficiency improves on TightBudget benchmark; no regression on other benchmarks.

### F4: Stable Section Budget Cap (optional)
Cap stable elements at configurable % of budget, demote overflow to dynamic queue.
**Acceptance:** New `WithStableCap` option; default behavior unchanged.

## Metrics

| Metric | Baseline | Target | Direction |
|--------|----------|--------|-----------|
| packing_efficiency (tight) | ~0.92 (est) | ≥ 0.95 | higher |
| render_100_ns | ~33,000 | ≤ 36,300 (+10%) | lower guard |
| allocs_100 | 56 | ≤ 60 | lower guard |

## Risks

- Fill pass adds O(excluded) work per render — mitigated by small element counts (<20 in practice)
- Stable cap changes cache behavior — mitigated by opt-in design and default=1.0

## Experiment Order

F1 → F2 → F3 → F4 (each builds on prior; F4 is stretch goal)
