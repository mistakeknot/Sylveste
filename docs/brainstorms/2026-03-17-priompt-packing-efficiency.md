# Priompt Packing Efficiency — Autoresearch Campaign Brainstorm

**Bead:** Sylveste-1x9l.1
**Date:** 2026-03-17
**Goal:** Maximize budget utilization in priompt's greedy packing algorithm

## Current State

Priompt (`masaq/priompt/priompt.go`) is a 265-line greedy packer:
- Elements sorted by effective priority (base + phase boost), stable-first
- Greedy descent: try each element in order, include if fits, skip if not
- Default separator: `\n\n` (1 token per join with CharHeuristic{Ratio:4})
- Tokenizer: CharHeuristic (chars/ratio, ~85% accuracy vs real tokenizers)

### Baseline Benchmarks (Ryzen 9 5950X)

| Benchmark | ns/op | allocs | B/op |
|-----------|-------|--------|------|
| Render20 | ~7,700 | 40 | 27,792 |
| Render50 | ~17,000 | 49 | 65,344 |
| Render100 | ~33,300 | 56 | 132,224 |
| Render100TightBudget | ~24,200 | 58 | 55,936 |
| RenderDynamic50 | ~26,500 | 59 | 73,472 |

### Production Context

- Priompt is used for system-prompt assembly (~10-20 elements, not per-message)
- Only called in tests currently — not yet integrated into Skaffen's prompt pipeline
- The `Render()` hot path includes: content resolution, priority scoring, sorting, greedy packing, string joining
- `RenderResult` exposes `TotalTokens` and `StableTokens` but no efficiency metrics

## Waste Sources Analysis

### 1. Separator Overhead (~2-5% of budget)
- Default `\n\n` costs 1 token per element boundary
- With 20 elements: 19 separators = 19 tokens wasted on whitespace
- On a 5,000 token budget, that's 0.4%; on 200 tokens, it's 9.5%
- **Lever:** `\n` instead of `\n\n` halves separator char count, but CharHeuristic rounds both to 1 token
- **Real win:** Use empty separator ("") for cache-stable prefix, `\n` for dynamic section

### 2. Greedy Skip Waste (knapsack gap)
- Current algo skips elements that don't fit, never backtracks
- Element ordering: stable→dynamic, each sorted by priority desc
- If element N is too large, smaller element N+1 might fit but gets tested after N
- **Lever:** After initial greedy pass, do a "fill pass" trying excluded elements smallest-first
- **Expected gain:** 1-8% depending on element size variance

### 3. TokenCount Double-Counting
- `TotalTokens` is computed by re-counting the final joined string: `cfg.tokenizer.Count(prompt)`
- This recounts all content + separators, but the individual token counts were already computed during packing
- Not a packing efficiency issue, but a latency issue — could accumulate tokens during packing
- **Lever:** Track running token sum during pack, avoid re-scan

### 4. Stable Prefix Inflexibility
- All stable elements pack first, regardless of size
- A large stable element could consume 60% of budget, excluding more valuable dynamic content
- **Lever:** Budget cap for stable section (e.g., 40% max), overflow stable elements demoted to dynamic queue
- **Risk:** Changes cache-hit behavior

### 5. CharHeuristic Quantization Error
- ratio=4 means any string <=3 chars → 1 token (min 1 guard)
- Separator `\n\n` (2 chars) always costs 1 token, but real tokenizers count it as 1 token too — so this is actually accurate
- Larger elements: error ~15% vs tiktoken/claude tokenizer
- **Lever:** Replace with lookup table or cached tiktoken (heavy dependency)
- **Risk:** Adding tiktoken dependency for <15% accuracy gain may not be worth it for a heuristic system

## Candidate Experiments

### E1: Fill Pass (knapsack improvement)
**Hypothesis:** After greedy descent, a second pass trying excluded elements by ascending size will recover 1-5% of wasted budget.
**Metric:** `budget_utilization = TotalTokens / budget` (higher is better)
**Implementation:** After main `pack()`, iterate excluded elements sorted by token cost ascending, try to fit each.
**Risk:** Low — additive, doesn't change primary ordering. O(excluded) extra work.
**Expected cost:** ~10-20 extra lines of code.

### E2: Separator Reduction
**Hypothesis:** Reducing separator from `\n\n` to `\n` saves 0 tokens with CharHeuristic (both round to 1) but saves tokens with a real tokenizer. With CharHeuristic, the win is only in the output string size.
**Metric:** `separator_tokens_pct = separator_tokens / TotalTokens`
**Implementation:** Test `WithSeparator("\n")` and `WithSeparator("")` on existing benchmarks.
**Risk:** Zero — separator is already configurable.
**Note:** This is more of a caller-side optimization than an algorithm change.

### E3: Stable Section Budget Cap
**Hypothesis:** Capping stable elements at X% of budget and demoting overflow to dynamic queue prevents one large stable element from crowding out higher-value dynamic content.
**Metric:** `excluded_priority_sum` (lower is better — less valuable content dropped)
**Implementation:** New option `WithStableCap(float64)`, default 1.0 (no cap). Cap check in stable packing loop.
**Risk:** Medium — changes stable prefix, affects cache-hit patterns. Need A/B data.

### E4: Running Token Accumulation
**Hypothesis:** Tracking token sum during packing instead of re-counting the final string saves one full tokenizer pass.
**Metric:** `render_latency_ns` (lower is better)
**Implementation:** Add `totalTokens` accumulator in `pack()`, skip final `Count(prompt)`.
**Risk:** Low — purely a performance optimization, no behavior change.
**Caveat:** Accumulated count may differ from Count(joined_string) due to separator accounting. Need to verify equivalence.

### E5: Priority-Weighted Density Sorting
**Hypothesis:** Sorting by `priority / token_cost` (value density) instead of raw priority packs more value per token.
**Metric:** `included_priority_sum / TotalTokens` (higher is better — more priority value per token)
**Implementation:** Change sort key from `effPri` to `effPri / tokenCost` in sort function.
**Risk:** High — changes inclusion decisions fundamentally. May produce worse results when all elements are similar size. Need both metrics (utilization AND priority sum).

### E6: PackingEfficiency + WastedTokens Observability
**Hypothesis:** Adding efficiency fields to RenderResult enables autoresearch to directly optimize packing.
**Metric:** Not an optimization itself — this IS the metric infrastructure.
**Implementation:** Add to RenderResult:
- `PackingEfficiency float64` — `TotalTokens / budget`
- `WastedTokens int` — `budget - TotalTokens`
- `ExcludedPrioritySum int` — sum of effective priorities of excluded elements
**Risk:** Zero — additive fields, no behavior change.
**Prerequisite for:** All other experiments that need efficiency signals.

## Experiment Ordering

1. **E6 (observability)** — Must come first. Gives us the metric fields to optimize against.
2. **E4 (running accumulation)** — Low risk latency win, validates token accounting.
3. **E1 (fill pass)** — The highest expected utilization gain.
4. **E3 (stable cap)** — Medium risk, high potential for constrained budgets.
5. **E5 (density sorting)** — High risk, run with both metrics to detect regressions.
6. **E2 (separator)** — Caller-side, test last as it's more of a recommendation than a code change.

## Success Criteria

- **Primary:** PackingEfficiency ≥ 0.95 on Render100TightBudget (currently unmeasured, estimated ~0.92)
- **Secondary:** No latency regression >10% on any benchmark
- **Guard:** All existing tests pass, no API contract changes

## Campaign Configuration (interlab)

```yaml
metric: packing_efficiency
direction: higher_is_better
benchmark_cmd: "go test -bench=BenchmarkRender100TightBudget -benchmem -count=5"
guard_metric: render_100_ns
guard_direction: lower_is_better
guard_threshold_pct: 10
files_in_scope:
  - masaq/priompt/priompt.go
  - masaq/priompt/bench_test.go
  - masaq/priompt/priompt_test.go
```

## Open Questions

1. Should we add a real tokenizer option (tiktoken/claude) or keep CharHeuristic as the reference?
2. Is stable prefix caching actually used by any caller yet? If not, stable cap (E3) is risk-free.
3. What's the real-world element count? If always <20, tight-budget scenarios may be rare.
