---
artifact_type: plan
bead: Demarch-dxzr
stage: design
requirements:
  - F1: masaq METRIC wrappers
  - F2: intermap + interlens METRIC wrappers
  - F3: tldr-swinton eval harness
  - F4: Clavain satisfaction/scenario benchmarks
  - F5: Core pillar Go benchmarks
  - F6: Generic Python benchmark harness
  - F7: Interlab meta-observability
---
# Interlab Observability Audit — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-dxzr (epic) with children Demarch-fjvb, Demarch-2s7p, Demarch-xuvh, Demarch-ngwf, Demarch-6ap0, Demarch-j2p9, Demarch-79iq, Demarch-l3dr
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Goal:** Bring Demarch ecosystem from 7% to >50% interlab observability by adding METRIC-emitting benchmark scripts to all optimizable components.

**Architecture:** Each component gets an `interlab.sh` script that wraps existing benchmarks (Go via `go-bench-harness.sh`, Python via new `py-bench-harness.sh`) to emit `METRIC name=value` lines. For components lacking benchmarks, we add `func Benchmark*` functions to existing test files. interlab's `run_experiment` tool parses these METRIC lines — no changes to interlab core needed.

**Tech Stack:** Go benchmarks (`testing.B`), bash harness scripts, Python pytest with timing capture, interlab MCP tools.

---

## Must-Haves

**Truths** (observable behaviors):
- `run_experiment` can parse METRIC output from masaq, intermap, interlens, tldr-swinton, Clavain, and all 4 core pillars
- `init_experiment` + `run_experiment` loop works end-to-end for at least one new component (masaq)
- `scan-plugin-quality.sh` reports METRIC-readiness as a new dimension
- interlab can measure its own campaign efficiency

**Artifacts** (files with specific exports):
- `masaq/interlab.sh` emits `METRIC priompt_render_ns=<value>`
- `interverse/intermap/interlab.sh` emits `METRIC pattern_detect_ns=<value>`
- `interverse/interlens/interlab.sh` emits `METRIC quality_score=<value>`
- `interverse/tldr-swinton/interlab.sh` emits `METRIC token_savings_pct=<value>`
- `os/Clavain/interlab-satisfaction.sh` emits `METRIC satisfaction_score=<value>`
- `os/Skaffen/internal/router/bench_test.go` exports `BenchmarkRouterDecision`
- `core/intercore/internal/dispatch/bench_test.go` exports `BenchmarkDispatch`
- `interverse/interlab/scripts/py-bench-harness.sh` wraps Python benchmarks to METRIC
- `interverse/interlab/interlab-meta.sh` emits campaign efficiency metrics

**Key Links:**
- All `interlab.sh` scripts → `go-bench-harness.sh` or `py-bench-harness.sh` → interlab `run_experiment`
- Core pillar `bench_test.go` → pillar `interlab.sh` → `go-bench-harness.sh`

---

## Task 1: masaq interlab.sh — Priompt Benchmark Wrapper

**Bead:** Demarch-6ap0
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `masaq/interlab.sh`

**Step 1: Write the interlab.sh harness**
```bash
#!/usr/bin/env bash
set -euo pipefail
# masaq/interlab.sh — wraps masaq Go benchmarks for interlab consumption.
# Primary metric: priompt_render_ns (BenchmarkRender100)
# Secondary: diff_lcs_ns, compact_format_ns, allocs, bytes

HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "--- priompt ---" >&2
bash "$HARNESS" --pkg ./priompt/ --bench 'BenchmarkRender100$' --metric priompt_render_ns --dir "$DIR"

echo "--- diff ---" >&2
bash "$HARNESS" --pkg ./diff/ --bench 'BenchmarkLCS500Lines5Pct$' --metric diff_lcs_ns --dir "$DIR"

echo "--- compact ---" >&2
bash "$HARNESS" --pkg ./compact/ --bench 'BenchmarkFormatToolCallCompact$' --metric compact_format_ns --dir "$DIR"
```

**Step 2: Make executable and test**
Run: `chmod +x masaq/interlab.sh && bash masaq/interlab.sh`
Expected: Output contains `METRIC priompt_render_ns=`, `METRIC diff_lcs_ns=`, `METRIC compact_format_ns=` with numeric values

**Step 3: Verify interlab can parse it**
Run: `cd masaq && bash interlab.sh 2>/dev/null | grep '^METRIC'`
Expected: 9+ METRIC lines (3 primary + run_count + bytes_per_op + allocs_per_op per benchmark)

**Step 4: Commit**
```bash
git add masaq/interlab.sh
git commit -m "feat(masaq): add interlab.sh benchmark harness for priompt, diff, compact"
```

<verify>
- run: `bash masaq/interlab.sh 2>/dev/null | grep -c '^METRIC'`
  expect: exit 0
- run: `bash masaq/interlab.sh 2>/dev/null | grep 'METRIC priompt_render_ns='`
  expect: contains "METRIC priompt_render_ns="
</verify>

---

## Task 2: intermap interlab.sh — Pattern Detection Benchmark Wrapper

**Bead:** Demarch-j2p9
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/intermap/interlab.sh`

**Step 1: Write the interlab.sh harness**
```bash
#!/usr/bin/env bash
set -euo pipefail
# intermap/interlab.sh — wraps Go benchmarks for interlab.
# Primary: pattern_detect_ns (BenchmarkDetectPatterns_Warm)

HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$HARNESS" --pkg ./internal/tools/ --bench 'BenchmarkDetectPatterns_Warm$' --metric pattern_detect_ns --dir "$DIR"
```

**Step 2: Test**
Run: `bash interverse/intermap/interlab.sh`
Expected: `METRIC pattern_detect_ns=<value>` with numeric value

**Step 3: Commit**
```bash
git add interverse/intermap/interlab.sh
git commit -m "feat(intermap): add interlab.sh benchmark harness"
```

<verify>
- run: `bash interverse/intermap/interlab.sh 2>/dev/null | grep 'METRIC pattern_detect_ns='`
  expect: contains "METRIC pattern_detect_ns="
</verify>

---

## Task 3: interlens interlab.sh — Python Quality Score Wrapper

**Bead:** Demarch-j2p9
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/interlens/interlab.sh`

**Step 1: Write the interlab.sh harness**

interlens has a Python `run_benchmark.py` that writes JSON to a file (not stdout) and prints human-readable text to stdout. We use `--output` to capture JSON results.

```bash
#!/usr/bin/env bash
set -euo pipefail
# interlens/interlab.sh — wraps Python benchmark runner for interlab.
# Primary: quality_score (from quality_scorer.py)
# NOTE: run_benchmark.py flag is --no-llm-judge (not --no-llm)
# NOTE: output is written to file via --output, not stdout

DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$DIR/packages/mcp/benchmark"
RESULTS="/tmp/interlens-bench-$$.json"

if [[ ! -f "$BENCH_DIR/run_benchmark.py" ]]; then
    echo "METRIC quality_score=-1"
    echo "METRIC error=1"
    exit 0
fi

# Run benchmark, write JSON to file (stdout is human-readable text)
(cd "$BENCH_DIR" && python3 run_benchmark.py --sample 3 --no-llm-judge --output "$RESULTS") >/dev/null 2>&1 || {
    echo "METRIC quality_score=-1"
    echo "METRIC error=1"
    rm -f "$RESULTS"
    exit 0
}

# Parse scores from JSON file
# Structure: { "evaluations": [...] } with per-file overall_score fields
QUALITY=$(python3 -c "
import json, sys
try:
    data = json.load(open('$RESULTS'))
    scores = [e.get('overall_score', 0) for e in data.get('evaluations', [])]
    avg = sum(scores) / len(scores) if scores else 0
    print(f'{avg:.4f}')
except (json.JSONDecodeError, KeyError, ZeroDivisionError, FileNotFoundError):
    print('-1')
" 2>/dev/null) || QUALITY="-1"
rm -f "$RESULTS"

if [[ "$QUALITY" == "-1" ]]; then
    echo "METRIC quality_score=-1"
    echo "METRIC error=1"
else
    echo "METRIC quality_score=$QUALITY"
    echo "METRIC benchmark_exit_code=0"
fi
```

**Step 2: Test**
Run: `bash interverse/interlens/interlab.sh`
Expected: `METRIC quality_score=` line (may be 0 if no sample data, but should not error)

**Step 3: Commit**
```bash
git add interverse/interlens/interlab.sh
git commit -m "feat(interlens): add interlab.sh benchmark harness for quality score"
```

<verify>
- run: `bash interverse/interlens/interlab.sh 2>/dev/null | grep '^METRIC'`
  expect: contains "METRIC quality_score="
</verify>

---

## Task 4: tldr-swinton interlab.sh — Token Efficiency Eval Wrapper

**Bead:** Demarch-79iq
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/tldr-swinton/interlab.sh`

**Step 1: Write the interlab.sh harness**

tldr-swinton has evals at `evals/` and a pytest test suite. The `token_efficiency_eval.py` has no `--quick` flag and requires the `tldrs` binary in PATH. Instead, we benchmark the pytest suite (which is self-contained) and measure test pass rate + duration as the primary metrics.

```bash
#!/usr/bin/env bash
set -euo pipefail
# tldr-swinton/interlab.sh — wraps pytest suite for interlab.
# Primary: test_pass_rate (pytest results)
# Secondary: test_duration_ms (wall-clock timing)
# NOTE: token_efficiency_eval.py requires `tldrs` binary — skip for now.
#       When tldrs is available, add a second benchmark target.

DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/py-bench-harness.sh}"

if [[ ! -f "$HARNESS" ]]; then
    echo "METRIC test_pass_rate=-1"
    echo "METRIC error=1"
    exit 0
fi

# Use the Python benchmark harness in pytest mode
bash "$HARNESS" --cmd "uv run pytest tests/ -q --tb=no" --metric test_pass_rate --dir "$DIR" --mode pytest
```

**Step 2: Test**
Run: `bash interverse/tldr-swinton/interlab.sh`
Expected: `METRIC token_savings_pct=` line

**Step 3: Commit**
```bash
git add interverse/tldr-swinton/interlab.sh
git commit -m "feat(tldr-swinton): add interlab.sh eval harness for token efficiency"
```

<verify>
- run: `bash interverse/tldr-swinton/interlab.sh 2>/dev/null | grep '^METRIC'`
  expect: contains "METRIC token_savings_pct="
</verify>

---

## Task 5: Clavain Satisfaction Benchmark Script

**Bead:** Demarch-l3dr
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `os/Clavain/interlab-satisfaction.sh`

**Step 1: Write the benchmark script**
```bash
#!/usr/bin/env bash
set -euo pipefail
# Clavain/interlab-satisfaction.sh — benchmark satisfaction scoring for interlab.
# Primary: scenario_score_ns (time to compute scenario score)

HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
CLI="$DIR/cmd/clavain-cli"

# First check if Go benchmarks exist, if not use CLI timing
if grep -q 'func Benchmark.*Scenario' "$CLI/scenario_test.go" 2>/dev/null; then
    bash "$HARNESS" --pkg ./cmd/clavain-cli/ --bench 'BenchmarkScenarioScore$' --metric scenario_score_ns --dir "$DIR"
else
    # Fallback: time the CLI directly
    START_NS=$(date +%s%N)
    "$DIR/bin/clavain-cli" scenario-score "test-bead" 2>/dev/null || true
    END_NS=$(date +%s%N)
    DURATION=$(( (END_NS - START_NS) ))
    echo "METRIC scenario_score_ns=$DURATION"
    echo "METRIC benchmark_exit_code=0"
    echo "METRIC run_count=1"
fi
```

**Step 2: Add Go benchmark to scenario_test.go**

**CRITICAL: Read `satisfaction.go` and `scenario.go` first.** The types below are illustrative — the real types are `Scenario` with `Rubric []RubricItem`, and scoring is done by `scoreScenarioResult`. You MUST adapt to the actual API found in these files. The pseudocode below shows the pattern, not compilable code.

```go
// ADAPT THIS to real types found in satisfaction.go/scenario.go:
// - Real type is Scenario with Rubric []RubricItem (not ScenarioConfig/Criterion)
// - Real scoring function is scoreScenarioResult (not ComputeScore)
// - Read the file to find the pure computation hot path
func BenchmarkScenarioScore(b *testing.B) {
	// Setup: construct a minimal Scenario + ScenarioResult from real types
	// Read satisfaction.go to find the correct struct fields
	scenario := /* construct from real types */
	result := /* construct from real types */
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = scoreScenarioResult(scenario, result) // adapt to real function name
	}
}
```

**Step 3: Test both paths**
Run: `cd os/Clavain && go test -bench BenchmarkScenarioScore -benchmem -count=1 -run='^$' ./cmd/clavain-cli/`
Expected: Benchmark output with ns/op

Run: `bash os/Clavain/interlab-satisfaction.sh`
Expected: `METRIC scenario_score_ns=` line

**Step 4: Commit**
```bash
git add os/Clavain/interlab-satisfaction.sh os/Clavain/cmd/clavain-cli/scenario_test.go
git commit -m "feat(clavain): add satisfaction/scenario Go benchmarks and interlab harness"
```

<verify>
- run: `bash os/Clavain/interlab-satisfaction.sh 2>/dev/null | grep 'METRIC scenario_score_ns='`
  expect: contains "METRIC scenario_score_ns="
</verify>

---

## Task 6: Skaffen Go Benchmarks + Harness

**Bead:** Demarch-2s7p
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `os/Skaffen/internal/router/bench_test.go`
- Create: `os/Skaffen/interlab.sh`

**Step 1: Write router benchmark**

Read `os/Skaffen/internal/router/router_test.go` first to understand existing test setup, then add `bench_test.go` in the same package.

**CRITICAL: Read `router.go` and `router_test.go` first.** The real API is `r.SelectModel(phase)`, NOT `r.Route(req)`. Tests construct routers with inline `&Config{}` literals — there is no `setupTestRouter` helper. Adapt:

```go
package router

import "testing"

// ADAPT THIS to real API found in router.go:
// - Constructor: New(&Config{DefaultModel: "claude-sonnet-4-5"})
// - Method: r.SelectModel(tool.Phase("main")) returns (string, string)
// - No setupTestRouter or testRequest helpers exist — construct inline
func BenchmarkRouterDecision(b *testing.B) {
	r := New(&Config{DefaultModel: "claude-sonnet-4-5"}) // adapt to real constructor
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = r.SelectModel(tool.Phase("main")) // adapt to real method
	}
}
```

**Step 2: Write interlab.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$HARNESS" --pkg ./internal/router/ --bench 'BenchmarkRouterDecision$' --metric router_decision_ns --dir "$DIR"
```

**Step 3: Test**
Run: `cd os/Skaffen && go test -bench BenchmarkRouterDecision -benchmem -count=1 -run='^$' ./internal/router/`
Expected: Benchmark output

Run: `bash os/Skaffen/interlab.sh`
Expected: `METRIC router_decision_ns=` line

**Step 4: Commit**
```bash
git add os/Skaffen/internal/router/bench_test.go os/Skaffen/interlab.sh
git commit -m "feat(skaffen): add router decision benchmark and interlab harness"
```

<verify>
- run: `bash os/Skaffen/interlab.sh 2>/dev/null | grep 'METRIC router_decision_ns='`
  expect: contains "METRIC router_decision_ns="
</verify>

---

## Task 7: Autarch Go Benchmarks + Harness

**Bead:** Demarch-2s7p
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `apps/Autarch/internal/gurgeh/spec/bench_test.go`
- Create: `apps/Autarch/interlab.sh`

**Step 1: Write spec analyzer benchmark**

Read `apps/Autarch/internal/gurgeh/spec/specflow_analyzer_test.go` first. Add benchmark for the specflow analysis hot path.

```go
package spec

import "testing"

func BenchmarkSpecflowAnalyze(b *testing.B) {
	analyzer := setupTestAnalyzer(b) // adapt from test helpers
	input := testSpecInput()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = analyzer.Analyze(input)
	}
}
```

**Step 2: Write interlab.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$HARNESS" --pkg ./internal/gurgeh/spec/ --bench 'BenchmarkSpecflowAnalyze$' --metric specflow_analyze_ns --dir "$DIR"
```

**Step 3: Test and commit**
Run: `bash apps/Autarch/interlab.sh`
Expected: `METRIC specflow_analyze_ns=` line

```bash
git add apps/Autarch/internal/gurgeh/spec/bench_test.go apps/Autarch/interlab.sh
git commit -m "feat(autarch): add specflow analyzer benchmark and interlab harness"
```

<verify>
- run: `bash apps/Autarch/interlab.sh 2>/dev/null | grep 'METRIC specflow_analyze_ns='`
  expect: contains "METRIC specflow_analyze_ns="
</verify>

---

## Task 8: Intercore Go Benchmarks + Harness

**Bead:** Demarch-2s7p
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `core/intercore/internal/dispatch/bench_test.go`
- Create: `core/intercore/interlab.sh`

**Step 1: Write dispatch benchmark**

Read `core/intercore/internal/dispatch/dispatch_test.go` first. Add benchmark for the dispatch hot path.

**CRITICAL: Read `dispatch.go` and `dispatch_test.go` first.** The real API is `Store.Create(ctx, *Dispatch)`, NOT `d.Dispatch(req)`. The store requires a SQLite DB — `testStore(t)` creates `t.TempDir()` + `db.Open()` + `d.Migrate()`. Adapt:

```go
package dispatch

import (
	"context"
	"testing"
)

// ADAPT THIS to real API found in dispatch.go:
// - Store created via testStore() helper (takes *testing.T, adapt for *testing.B)
// - Method: s.Create(ctx, &Dispatch{...}) returns (string, error)
func BenchmarkDispatch(b *testing.B) {
	s := setupBenchStore(b) // adapt from testStore — use b.TempDir()
	ctx := context.Background()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = s.Create(ctx, &Dispatch{ /* fill from real type */ })
	}
}
```

**Step 2: Write interlab.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$HARNESS" --pkg ./internal/dispatch/ --bench 'BenchmarkDispatch$' --metric dispatch_ns --dir "$DIR"
```

**Step 3: Test and commit**
Run: `bash core/intercore/interlab.sh`
Expected: `METRIC dispatch_ns=` line

```bash
git add core/intercore/internal/dispatch/bench_test.go core/intercore/interlab.sh
git commit -m "feat(intercore): add dispatch benchmark and interlab harness"
```

<verify>
- run: `bash core/intercore/interlab.sh 2>/dev/null | grep 'METRIC dispatch_ns='`
  expect: contains "METRIC dispatch_ns="
</verify>

---

## Task 9: Intermute Go Benchmarks + Harness

**Bead:** Demarch-2s7p
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `core/intermute/internal/storage/bench_test.go` (or appropriate storage package)
- Create: `core/intermute/interlab.sh`

**Step 1: Write storage benchmark**

Read `core/intermute/internal/http/handlers_reservations_test.go` to understand the storage layer. Add benchmark for SQLite write/read hot path.

```go
package storage // or appropriate package

import "testing"

func BenchmarkReservationWrite(b *testing.B) {
	store := setupTestStore(b) // adapt from test helpers
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = store.Reserve(testReservation(i))
	}
}
```

**Step 2: Write interlab.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/go-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$HARNESS" --pkg ./internal/storage/ --bench 'BenchmarkReservationWrite$' --metric reservation_write_ns --dir "$DIR"
```

**Step 3: Test and commit**
```bash
git add core/intermute/internal/storage/bench_test.go core/intermute/interlab.sh
git commit -m "feat(intermute): add reservation write benchmark and interlab harness"
```

<verify>
- run: `bash core/intermute/interlab.sh 2>/dev/null | grep 'METRIC reservation_write_ns='`
  expect: contains "METRIC reservation_write_ns="
</verify>

---

## Task 10: Generic Python Benchmark Harness

**Bead:** Demarch-xuvh
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/interlab/scripts/py-bench-harness.sh`

**Step 1: Write the harness**
```bash
#!/usr/bin/env bash
set -euo pipefail
# py-bench-harness.sh — wraps Python test/benchmark output into METRIC format.
#
# Usage:
#   bash py-bench-harness.sh --cmd "pytest tests/ -q" --metric test_duration_ms --dir interverse/intercache
#   bash py-bench-harness.sh --cmd "python3 benchmark.py" --metric quality_score --dir interverse/intermem
#
# Modes:
#   --mode timing  (default) — measures wall-clock duration of command in ms
#   --mode output  — parses stdout for "METRIC name=value" lines (passthrough)
#   --mode pytest  — parses pytest output for pass/fail counts + timing

CMD=""
METRIC_NAME="duration_ms"
DIR="."
MODE="timing"
COUNT=3

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd) CMD="$2"; shift 2 ;;
        --metric) METRIC_NAME="$2"; shift 2 ;;
        --dir) DIR="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --count) COUNT="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$CMD" ]]; then
    echo "Usage: $0 --cmd <command> [--metric name] [--dir path] [--mode timing|output|pytest]" >&2
    exit 1
fi

cd "$DIR"

case "$MODE" in
    timing)
        DURATIONS=()
        ERRORS=0
        for ((i=0; i<COUNT; i++)); do
            START_MS=$(($(date +%s%N) / 1000000))
            bash -c "$CMD" >/dev/null 2>&1 || ERRORS=$((ERRORS + 1))
            END_MS=$(($(date +%s%N) / 1000000))
            DURATIONS+=($((END_MS - START_MS)))
        done
        # Median
        IFS=$'\n' SORTED=($(printf '%s\n' "${DURATIONS[@]}" | sort -n))
        MID=$(( ${#SORTED[@]} / 2 ))
        echo "METRIC ${METRIC_NAME}=${SORTED[$MID]}"
        echo "METRIC run_count=${#SORTED[@]}"
        [[ $ERRORS -gt 0 ]] && echo "METRIC error=$ERRORS"
        echo "METRIC benchmark_exit_code=0"
        ;;
    output)
        bash -c "$CMD" 2>/dev/null | grep '^METRIC ' || {
            echo "METRIC ${METRIC_NAME}=-1"
            echo "METRIC error=1"
        }
        ;;
    pytest)
        OUTPUT=$(eval "$CMD" 2>&1) || true
        PASSED=$(echo "$OUTPUT" | grep -oP '\d+ passed' | grep -oP '\d+' || echo "0")
        FAILED=$(echo "$OUTPUT" | grep -oP '\d+ failed' | grep -oP '\d+' || echo "0")
        TOTAL=$((PASSED + FAILED))
        RATE=$(python3 -c "print(f'{$PASSED / $TOTAL:.4f}' if $TOTAL > 0 else '0')")
        echo "METRIC ${METRIC_NAME}=$RATE"
        echo "METRIC tests_passed=$PASSED"
        echo "METRIC tests_failed=$FAILED"
        echo "METRIC tests_total=$TOTAL"
        echo "METRIC benchmark_exit_code=0"
        ;;
esac
```

**Step 2: Test with a real plugin**
Run: `bash interverse/interlab/scripts/py-bench-harness.sh --cmd "uv run pytest -q" --metric test_pass_rate --dir interverse/intercache --mode pytest`
Expected: `METRIC test_pass_rate=` line with numeric value

**Step 3: Commit**
```bash
git add interverse/interlab/scripts/py-bench-harness.sh
git commit -m "feat(interlab): add py-bench-harness.sh for Python plugin benchmarking"
```

<verify>
- run: `bash interverse/interlab/scripts/py-bench-harness.sh --cmd "echo 'METRIC x=42'" --metric x --mode output 2>/dev/null | grep 'METRIC x=42'`
  expect: contains "METRIC x=42"
</verify>

---

## Task 11: Apply Python Harness to 5 Plugins

**Bead:** Demarch-xuvh
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/intercache/interlab.sh`
- Create: `interverse/intermem/interlab.sh`
- Create: `interverse/interject/interlab.sh`
- Create: `interverse/intersearch/interlab.sh`
- Create: `interverse/interwatch/interlab.sh`

**Step 1: Write interlab.sh for each plugin**

Each follows the same pattern — wrap their test suite with py-bench-harness.sh:

```bash
#!/usr/bin/env bash
set -euo pipefail
# <plugin>/interlab.sh — wraps pytest for interlab.
HARNESS="${INTERLAB_HARNESS:-$(git rev-parse --show-toplevel)/interverse/interlab/scripts/py-bench-harness.sh}"
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$HARNESS" --cmd "uv run pytest tests/ -q --tb=no" --metric test_pass_rate --dir "$DIR" --mode pytest
```

Adapt per plugin:
- **intercache**: `--dir "$DIR/tests"` (6 unit tests)
- **intermem**: `--dir "$DIR/tests"` (10 unit tests)
- **interject**: `--dir "$DIR/tests"` (5 unit tests)
- **intersearch**: `--dir "$DIR/tests"` (2 unit tests)
- **interwatch**: `--dir "$DIR/tests"` (1 unit test)

**Step 2: Test each**
Run: `for p in intercache intermem interject intersearch interwatch; do echo "--- $p ---"; bash "interverse/$p/interlab.sh" 2>/dev/null | grep '^METRIC'; done`
Expected: METRIC lines for each plugin

**Step 3: Commit**
```bash
git add interverse/intercache/interlab.sh interverse/intermem/interlab.sh interverse/interject/interlab.sh interverse/intersearch/interlab.sh interverse/interwatch/interlab.sh
git commit -m "feat(interverse): add interlab.sh to intercache, intermem, interject, intersearch, interwatch"
```

<verify>
- run: `bash interverse/intercache/interlab.sh 2>/dev/null | grep 'METRIC test_pass_rate='`
  expect: contains "METRIC test_pass_rate="
</verify>

---

## Task 12: Interlab Meta-Observability

**Bead:** Demarch-ngwf
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Create: `interverse/interlab/interlab-meta.sh`
- Modify: `interverse/interlab/internal/experiment/ic.go` (remove dead CreateRun if confirmed)

**Step 1: Write interlab-meta.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail
# interlab-meta.sh — measures interlab's own optimization effectiveness.
# Primary: campaign_success_rate (fraction of campaigns producing improvement)

DIR="$(cd "$(dirname "$0")" && pwd)"
CAMPAIGNS_DIR="$DIR/campaigns"

# Count campaigns with positive improvement
total=0
improved=0

# Check both interlab.jsonl (standard) and results.jsonl (legacy)
for campaign_dir in "$CAMPAIGNS_DIR"/*/; do
    jsonl=""
    [[ -f "$campaign_dir/interlab.jsonl" ]] && jsonl="$campaign_dir/interlab.jsonl"
    [[ -z "$jsonl" && -f "$campaign_dir/results.jsonl" ]] && jsonl="$campaign_dir/results.jsonl"
    [[ -z "$jsonl" ]] && continue
    total=$((total + 1))
    # Check if any experiment was kept (decision=keep)
    if grep -q '"decision":"keep"' "$jsonl" 2>/dev/null; then
        improved=$((improved + 1))
    fi
done

if [[ $total -gt 0 ]]; then
    RATE=$(python3 -c "print(f'{$improved / $total:.4f}')")
else
    RATE="0"
fi

echo "METRIC campaign_success_rate=$RATE"
echo "METRIC campaigns_total=$total"
echo "METRIC campaigns_improved=$improved"

# Mutation store metrics (if available)
MUTATIONS_DB="$HOME/.local/share/interlab/mutations.db"
if [[ -f "$MUTATIONS_DB" ]]; then
    TOTAL_MUTATIONS=$(sqlite3 "$MUTATIONS_DB" "SELECT COUNT(*) FROM mutations" 2>/dev/null || echo "0")
    BEST_MUTATIONS=$(sqlite3 "$MUTATIONS_DB" "SELECT COUNT(*) FROM mutations WHERE is_new_best=1" 2>/dev/null || echo "0")
    SEEDED=$(sqlite3 "$MUTATIONS_DB" "SELECT COUNT(*) FROM mutations WHERE inspired_by IS NOT NULL AND inspired_by != ''" 2>/dev/null || echo "0")
    echo "METRIC mutation_total=$TOTAL_MUTATIONS"
    echo "METRIC mutation_best_count=$BEST_MUTATIONS"
    echo "METRIC mutation_seeded_count=$SEEDED"
fi

echo "METRIC benchmark_exit_code=0"
```

**Step 2: Check and clean dead code**
Read `internal/experiment/ic.go` and verify `CreateRun()` has no callers. If confirmed dead, remove it.

**Step 3: Test**
Run: `bash interverse/interlab/interlab-meta.sh`
Expected: `METRIC campaign_success_rate=` line

**Step 4: Commit**
```bash
git add interverse/interlab/interlab-meta.sh
git commit -m "feat(interlab): add meta-observability benchmark for campaign effectiveness"
```

<verify>
- run: `bash interverse/interlab/interlab-meta.sh 2>/dev/null | grep 'METRIC campaign_success_rate='`
  expect: contains "METRIC campaign_success_rate="
</verify>

---

## Task 13: Update scan-plugin-quality.sh with METRIC-Readiness

**Bead:** Demarch-xuvh
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:**
- Modify: `interverse/interlab/scripts/scan-plugin-quality.sh`

**Step 1: Add METRIC-readiness check**

After the existing PQS computation, add a check for `interlab.sh` presence:

```bash
# In the per-plugin loop, after existing checks:
has_interlab=0
if [[ -f "$plugin_path/interlab.sh" ]]; then
    has_interlab=1
fi
```

Add `has_interlab` to the JSON output and table display.

**Step 2: Test**
Run: `bash interverse/interlab/scripts/scan-plugin-quality.sh --top=10 2>/dev/null`
Expected: Table shows new "Interlab" column

**Step 3: Commit**
```bash
git add interverse/interlab/scripts/scan-plugin-quality.sh
git commit -m "feat(interlab): add METRIC-readiness column to scan-plugin-quality.sh"
```

<verify>
- run: `bash interverse/interlab/scripts/scan-plugin-quality.sh --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print('has_interlab' in str(d))"`
  expect: contains "True"
</verify>

---

## Task 14: End-to-End Validation — Run a masaq Campaign

**Bead:** Demarch-6ap0
**Phase:** planned (as of 2026-03-17T21:56:50Z)
**Files:** None (validation only)

**Step 1: Initialize a test campaign**
Use interlab MCP tools:
- `init_experiment` with name="masaq-priompt-speed", metric_name="priompt_render_ns", metric_unit="ns", direction="lower_is_better", benchmark_command="bash masaq/interlab.sh"

**Step 2: Run one experiment**
- `run_experiment` — verify it parses METRIC output correctly

**Step 3: Log the result**
- `log_experiment` with decision="keep" (baseline)

**Step 4: Verify JSONL**
Run: `cat masaq/interlab.jsonl | tail -3`
Expected: Config header + at least one result entry with priompt_render_ns value

**Step 5: Clean up**
Revert interlab branch: `git checkout main && git branch -D interlab/masaq-priompt-speed`

<verify>
- run: `test -f masaq/interlab.sh && echo "exists"`
  expect: contains "exists"
</verify>
