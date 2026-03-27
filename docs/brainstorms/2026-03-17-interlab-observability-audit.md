# Brainstorm: Interlab Observability Audit

> **Epic bead:** Sylveste-dxzr
> **Date:** 2026-03-17
> **Goal:** Ensure all Sylveste components have measurable metrics for interlab optimization

## Executive Summary

**Audited:** 54 interverse plugins + 137 Clavain components + 6 core pillars + interlab itself
**Finding:** ~90% of the ecosystem is "dark" to interlab — no METRIC emission, no benchmarks.

| Layer | Total | Observable | Dark | % Observable |
|-------|-------|-----------|------|-------------|
| Interverse plugins | 54 | 1 (interlab) | 53 | 2% |
| Clavain (skills/cmds/agents/hooks/Go/scripts) | 137 | 12.5 | 124.5 | 9% |
| Core pillars (Skaffen/Autarch/Intercore/Intermute/Interbase) | 5 | 0 | 5 | 0% |
| masaq | 1 | 0.5 (PARTIAL) | 0.5 | 50% |
| **Total** | **197** | **14** | **183** | **7%** |

Only **interlab itself** emits `METRIC name=value` lines. Zero other components do.

## How interlab Works (for context)

interlab optimizes via an experiment loop: edit code → run benchmark → parse `METRIC name=value` from stdout → keep/discard → repeat. Requirements per component:
1. **Benchmark script** that outputs `METRIC name=value` lines
2. **Clear primary metric** (timing, score, size, count — any float64)
3. Optionally: Go `func Benchmark*` functions wrapped by `go-bench-harness.sh`

Existing reusable harnesses:
- `go-bench-harness.sh` — wraps any `go test -bench` into METRIC lines
- `plugin-benchmark.sh` — 19-point plugin quality audit → PQS score
- `agent-quality-benchmark.sh` — 13-check agent .md quality → score

## Audit Results by Layer

### Tier 1: Already Have Benchmarks (just need METRIC wrapper)

| Component | What Exists | Natural Metric | Effort |
|-----------|------------|----------------|--------|
| **masaq/** (priompt, diff, compact) | 17 Go benchmarks across 3 packages | Render ns/op, LCS ns/op, FormatToolCall ns/op | Low — wrap with go-bench-harness.sh |
| **intermap** | 4 Go benchmarks (DetectPatterns, CrossProjectDeps) | pattern_detect_ns_per_op | Low — wrap with go-bench-harness.sh |
| **tldr-swinton** | Full eval suite (tldr-bench, 7 eval scripts, 90+ tests) | resolve_rate, token_savings_pct | Low — shell wrapper around eval |
| **interlens** | Benchmark runner (run_benchmark.py) with 4 metric analyzers | quality_score | Low — pipe Python output to METRIC format |
| **Clavain Go** (sprint, satisfaction, scenario) | 4 interlab benchmark scripts + scoring system | cli_find_active_ms, satisfaction_score | Already exists for sprint; extend for satisfaction |

### Tier 2: Have Tests/Hooks, Need Benchmarks

| Component | Tests | Hooks/Events | Natural Metric | Effort |
|-----------|-------|-------------|----------------|--------|
| Skaffen | 93 test files | N | agent_loop_cycle_ms, router_decision_ns | Med — add Go benchmarks |
| Autarch | 80+ test files | N | tui_render_ms, arbiter_orchestration_ms | Med — add Go benchmarks |
| Intercore | 64 test files | N | dispatch_latency_ns, scheduler_tick_ns | Med — add Go benchmarks |
| Intermute | 29 test files | N | sqlite_write_ms, ws_throughput_msg_s | Med — add Go benchmarks |
| intermix | 12 Go tests | N | eval_accuracy | Med — add Go benchmarks |
| interserve | 4 Go tests | Y | classify_ns_per_op | Med — add Go benchmarks |
| intermem | 10 Py tests | Y | synthesis_accuracy | Med |
| intercache | 6 Py tests | Y | cache_hit_rate | Med |
| interject | 5 Py tests | Y | recommendation_precision | Med |
| interlock | 2 Go tests | Y | lock_contention_rate | Med |

### Tier 3: DARK (no observability beyond structural tests)

22 interverse plugins + ~45 Clavain commands + ~16 Clavain skills with zero measurement:
- interchart, intercheck, intercraft, interdev, interform, interleave, intermonk, internext, interpath, interpeer, interplug, interpub, interrank, interscribe, intersense, intersight, interskill, interslack, intertest, intertree, tuivision, intership

### Clavain Specifics

- **Skills:** 1/17 observable (galiana only). 94% dark.
- **Commands:** 3/48 observable (route, sprint, galiana). 94% dark.
- **Agents:** 0.5/17 (codex-delegate partial). 97% dark.
- **Hooks:** 1/10 partial (session-start). 90% dark.
- **Go modules:** 5/19 (sprint, satisfaction, scenario, stats, cxdb). 74% dark.
- **Zero `func Benchmark*` functions** in all of Clavain despite 17 test files.

## Interlab Self-Observability Gaps

interlab dogfoods 3 campaigns on its own code but has **no meta-observability**:
- No campaign success rate metric
- No experiment efficiency metric (experiments per unit improvement)
- No mutation store utilization tracking
- No circuit breaker trip frequency
- No orchestration overhead benchmarks
- `CreateRun()` exists but has no callers (dead code)
- Single-run benchmarks in dogfood scripts (variance risk)

## Prioritized Remediation Plan

### Phase 1: Quick Wins (5 components, ~2h each)
1. **masaq** — wrap 17 existing Go benchmarks with go-bench-harness.sh → 3 interlab.sh scripts
2. **intermap** — wrap 4 Go benchmarks with go-bench-harness.sh → 1 interlab.sh
3. **tldr-swinton** — shell wrapper around eval suite → 1 interlab.sh
4. **interlens** — Python METRIC wrapper → 1 interlab.sh
5. **Clavain satisfaction/scenario** — extend existing benchmark pattern → 2 interlab scripts

### Phase 2: Go Benchmark Foundation (6 pillars, ~4h each)
6. **Skaffen** — add func Benchmark* for agent loop, router, MCP dispatch
7. **Autarch** — add func Benchmark* for TUI render, arbiter, spec validation
8. **Intercore** — add func Benchmark* for dispatch, scheduler, budget reconciliation
9. **Intermute** — add func Benchmark* for SQLite write, WS throughput, reservation
10. **Clavain CLI** — add func Benchmark* for sprint-find-active, complexity, scenario

### Phase 3: Plugin METRIC Harnesses (batch)
11. **Generic Python benchmark harness** — analogous to go-bench-harness.sh for Python plugins
12. Apply to: intermem, intercache, interject, intersearch, interdeep, interwatch
13. **Plugin quality sweep** — run scan-plugin-quality.sh → generate-campaign-spec.sh → /autoresearch-multi

### Phase 4: Interlab Meta-Observability
14. **Campaign success rate** — track % campaigns that produce improvement
15. **Experiment efficiency** — experiments per unit of improvement
16. **Mutation store analytics** — query hit rate, genealogy depth, seeding effectiveness

## Approach Options

### Option A: Bottom-Up (benchmark scripts first)
Write interlab.sh harnesses for Tier 1 components, run campaigns, prove value, expand.
- Pro: Immediate ROI, validates the pattern
- Con: Doesn't address the 90% dark problem systematically

### Option B: Top-Down (universal METRIC protocol)
Define a standard `interlab.sh` contract for every plugin, add to plugin-benchmark.sh audit.
- Pro: Systematic, measurable compliance
- Con: Many plugins lack meaningful metrics (meta-tooling, cosmetic)

### Option C: Hybrid (recommended)
Phase 1-2 for quick wins + Go foundations, then Phase 3 with a generic harness. Skip components where metrics don't make sense (intership, interform, interdev). Track coverage as a meta-metric.

**Recommended: Option C** — delivers value fast while building toward systematic coverage.
