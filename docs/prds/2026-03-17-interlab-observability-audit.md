---
artifact_type: prd
bead: Demarch-dxzr
stage: design
---
# PRD: Interlab Observability Audit — Universal METRIC Coverage

## Problem

93% of Demarch's 197 components are invisible to interlab's optimization loop. Only interlab itself emits `METRIC name=value` lines. Components with existing Go benchmarks (masaq, intermap), eval suites (tldr-swinton), and scoring systems (Clavain satisfaction) cannot be optimized because they lack the thin METRIC wrapper interlab requires.

## Solution

Systematically instrument all optimizable components with interlab-compatible benchmark scripts, starting with components that already have benchmarks/tests (wrap existing work), then adding Go benchmarks to core pillars, creating a reusable Python harness for the plugin ecosystem, and finally adding meta-observability to interlab itself.

## Features

### F1: masaq METRIC Wrappers
**What:** Wrap masaq's 17 existing Go benchmarks (priompt, diff, compact) with go-bench-harness.sh to emit METRIC lines.
**Acceptance criteria:**
- [ ] `interlab.sh` in masaq/ wraps `go test -bench` for priompt and emits `METRIC priompt_render_ns=<value>`
- [ ] `interlab.sh` covers diff (LCS benchmarks) and compact (FormatToolCall benchmarks)
- [ ] `init_experiment` + `run_experiment` successfully parse masaq metrics
- [ ] Secondary metrics (allocs_per_op, bytes_per_op) captured

### F2: intermap + interlens METRIC Wrappers
**What:** Wrap intermap's 4 Go benchmarks and interlens' Python benchmark runner with METRIC emission.
**Acceptance criteria:**
- [ ] intermap `interlab.sh` wraps DetectPatterns/CrossProjectDeps benchmarks → `METRIC pattern_detect_ns=<value>`
- [ ] interlens `interlab.sh` wraps run_benchmark.py → `METRIC quality_score=<value>`
- [ ] Both parseable by `run_experiment`

### F3: tldr-swinton Eval Harness
**What:** Shell wrapper around tldr-swinton's eval suite emitting METRIC lines for resolve rate and token savings.
**Acceptance criteria:**
- [ ] `interlab.sh` runs a representative eval and emits `METRIC resolve_rate=<value>` and `METRIC token_savings_pct=<value>`
- [ ] Eval completes in <60s for fast iteration
- [ ] Compatible with existing tldr-bench infrastructure

### F4: Clavain Satisfaction/Scenario Benchmarks
**What:** Extend Clavain's existing interlab benchmark pattern to cover satisfaction scoring and scenario evaluation.
**Acceptance criteria:**
- [ ] `interlab-satisfaction.sh` wraps `clavain-cli scenario-score` → `METRIC satisfaction_score=<value>`
- [ ] Go benchmarks added for `satisfaction.go` and `scenario.go` hot paths
- [ ] Clavain's observable Go modules increase from 5/19 to 8/19

### F5: Core Pillar Go Benchmarks
**What:** Add `func Benchmark*` functions to Skaffen, Autarch, Intercore, Intermute hot paths with go-bench-harness.sh wrappers.
**Acceptance criteria:**
- [ ] Skaffen: benchmarks for agent loop cycle, router decision, MCP dispatch (3+ benchmarks)
- [ ] Autarch: benchmarks for TUI render, arbiter orchestration, spec validation (3+ benchmarks)
- [ ] Intercore: benchmarks for dispatch latency, scheduler tick, budget reconciliation (3+ benchmarks)
- [ ] Intermute: benchmarks for SQLite write, WS message throughput, reservation check (3+ benchmarks)
- [ ] Each pillar has an `interlab.sh` that wraps its benchmarks via go-bench-harness.sh
- [ ] All 4 pillars move from DARK to PARTIAL or READY

### F6: Generic Python Benchmark Harness
**What:** Create a reusable `py-bench-harness.sh` (analogous to go-bench-harness.sh) that wraps Python test/benchmark output into METRIC lines, then apply to top PARTIAL plugins.
**Acceptance criteria:**
- [ ] `py-bench-harness.sh` in interlab/scripts/ converts pytest timing or custom Python metric output to `METRIC` format
- [ ] Applied to at least 5 Python plugins: intermem, intercache, interject, intersearch, interwatch
- [ ] `scan-plugin-quality.sh` updated to detect and report METRIC-readiness
- [ ] Ecosystem-wide observable count increases from 7% to >20%

### F7: Interlab Meta-Observability
**What:** Add self-measurement to interlab: campaign success rate, experiment efficiency, mutation store utilization.
**Acceptance criteria:**
- [ ] New `interlab-meta.sh` benchmark that queries interlab's own JSONL/SQLite and emits meta-metrics
- [ ] `METRIC campaign_success_rate=<value>` (% campaigns producing improvement)
- [ ] `METRIC experiments_per_improvement=<value>` (efficiency ratio)
- [ ] `METRIC mutation_store_utilization=<value>` (query hit rate)
- [ ] Dead code `CreateRun()` either wired up or removed
- [ ] interlab can run `/autoresearch` on itself to optimize its own meta-metrics

## Non-goals

- Instrumenting purely cosmetic/meta-tooling plugins (intership, interform, interdev) where metrics don't make sense
- Production observability (APM, distributed tracing) — interlab is dev-time optimization
- Automated campaign dispatch (running campaigns is still agent-driven)
- Changing the METRIC protocol itself — it works, just needs adoption

## Dependencies

- `go-bench-harness.sh` (exists in interlab/scripts/)
- `plugin-benchmark.sh` (exists in interlab/scripts/)
- Go test infrastructure in each pillar (exists, 270+ test files)
- Beads CLI for tracking (exists)

## Open Questions

1. Should the Python harness support pytest-benchmark's JSON output format, or just timing capture?
2. For Skaffen benchmarks, should we benchmark the full agent loop (expensive, realistic) or isolated functions (cheap, synthetic)?
3. What's the minimum meaningful metric for plugins like interpeer or intermonk that do LLM-mediated reasoning?
