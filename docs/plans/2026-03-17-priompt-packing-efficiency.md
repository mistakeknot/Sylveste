# Plan: Priompt Packing Efficiency Campaign

**Bead:** Sylveste-1x9l.1
**Brainstorm:** docs/brainstorms/2026-03-17-priompt-packing-efficiency.md
**PRD:** docs/prd/2026-03-17-priompt-packing-efficiency-prd.md

## Task Breakdown

### Task 1: Add packing observability fields to RenderResult [F1]
**Files:** `masaq/priompt/priompt.go`, `masaq/priompt/priompt_test.go`
**Steps:**
1. Add three fields to `RenderResult`: `PackingEfficiency float64`, `WastedTokens int`, `ExcludedPrioritySum int`
2. Compute `PackingEfficiency = float64(totalTokens) / float64(budget)` (0 if budget <= 0)
3. Compute `WastedTokens = budget - totalTokens` (0 if totalTokens >= budget)
4. Accumulate `ExcludedPrioritySum` in the `pack()` closure when an element is excluded
5. Add tests: verify efficiency ~1.0 on generous budget, <1.0 on tight budget, ExcludedPrioritySum correct
**Acceptance:** `go test ./...` passes, new fields populated in benchmarks

### Task 2: Running token accumulation [F2]
**Files:** `masaq/priompt/priompt.go`
**Steps:**
1. Add `runningTokens int` variable before `pack()` closure
2. In `pack()`, when including: `runningTokens += tokenCost + thisSepCost`
3. Replace `TotalTokens: cfg.tokenizer.Count(prompt)` with `TotalTokens: runningTokens`
4. Verify: existing tests must produce identical `TotalTokens` values
5. Run benchmarks: expect measurable latency improvement on Render100 (saves one full Count() call on joined string)
**Risk:** Accumulated count may differ from Count(joined) due to tokenizer non-linearity. If CharHeuristic is used (linear), they're equivalent. If custom tokenizer has context-dependent counting, they may differ. Mitigation: document that TotalTokens is the sum of individual counts.
**Acceptance:** All tests pass, TotalTokens values unchanged with CharHeuristic

### Task 3: Fill pass for remaining budget [F3]
**Files:** `masaq/priompt/priompt.go`, `masaq/priompt/priompt_test.go`, `masaq/priompt/bench_test.go`
**Steps:**
1. After `pack(stable, true)` and `pack(dynamic, false)`, collect all excluded items with their token costs
2. Sort excluded by token cost ascending (smallest first)
3. Try each: if `tokenCost + sepCost <= remaining`, include it (append to included lists, deduct from remaining)
4. Update excluded/excludedStable slices to remove any newly-included elements
5. Add test: 3 elements where greedy skips large middle element but fill pass recovers small tail element
6. Add benchmark variant: `BenchmarkRender100TightBudgetWithFill` (same elements, measure packing efficiency)
**Acceptance:** PackingEfficiency improves on TightBudget; no regression >10% on Render100 latency

### Task 4: Packing efficiency benchmark harness [campaign setup]
**Files:** `masaq/priompt/bench_test.go`
**Steps:**
1. Add `BenchmarkPackingEfficiency` that reports `PackingEfficiency` as a custom metric via `b.ReportMetric()`
2. Use tight budget (2000 tokens, 100 elements) to maximize exclusion pressure
3. Report: `packing_efficiency`, `wasted_tokens`, `excluded_priority_sum`
**Acceptance:** `go test -bench=BenchmarkPackingEfficiency -v` shows custom metrics

### Task 5: Stable section budget cap [F4, stretch]
**Files:** `masaq/priompt/priompt.go`, `masaq/priompt/priompt_test.go`
**Steps:**
1. Add `WithStableCap(pct float64)` option; stored as `stableCap` in renderConfig (default 1.0 = no cap)
2. In stable packing: track `stableBudget = int(float64(budget) * stableCap)`, `stableSpent`
3. When stable element would exceed stableBudget, demote to dynamic queue (insert by priority)
4. Add tests: cap=0.5 with heavy stable content forces demotion; default behavior unchanged
**Acceptance:** Tests pass, default behavior identical, capped behavior improves ExcludedPrioritySum

## Dependencies

- Task 1 (observability) is prerequisite for Tasks 3, 4, 5
- Task 2 (running accumulation) is independent, can parallel with Task 1
- Task 3 (fill pass) depends on Task 1 for metrics
- Task 4 (benchmark harness) depends on Tasks 1 and 3
- Task 5 (stable cap) depends on Task 1, independent of 3

## Verification

After all tasks:
```bash
cd masaq/priompt && go test ./... -count=1 -v
cd masaq/priompt && go test -bench=. -benchmem -count=3
```

Compare benchmarks against baseline recorded in brainstorm doc.
