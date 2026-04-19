---
artifact_type: plan
bead: sylveste-s3z6
stage: design
requirements:
  - F1: FluxBench metric definitions + local scoring engine
  - F2: Qualification test fixtures with ground-truth findings
  - F3: AgMoDB write-back via store-and-forward
  - F4: Drift detection — sample-based + version-triggered
  - F5: Proactive model surfacing — SessionStart + weekly schedule
  - F6: interrank TASK_DOMAIN_MAP FluxBench integration
  - F7: Challenger slot mechanism for unqualified candidates
---
# FluxBench Closed-Loop Model Discovery — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-s3z6
**Goal:** Build FluxBench scoring engine, test fixtures, and feedback pipeline so interflux can measure, qualify, and continuously monitor model performance for multi-agent reviews.

**Architecture:** Local scoring engine (`fluxbench-score.sh`) reads structured `qualification-output.json`, compares against ground-truth/baseline findings, outputs per-metric JSON results to `fluxbench-results.jsonl`. `model-registry.yaml` is the local authority; AgMoDB is the external store via periodic git commit. All concurrent writes use flock + atomic swap.

**Tech Stack:** Bash (scoring scripts), YAML (config/metrics), JSON/JSONL (results), bats (tests), TypeScript (interrank TASK_DOMAIN_MAP)

---

## Must-Haves

**Truths** (observable behaviors):
- Running `fluxbench-score.sh <qualification-output.json> <baseline.json>` produces a FluxBench result JSON with all 9 metric scores
- Running `fluxbench-calibrate.sh` against test fixtures produces `fluxbench-thresholds.yaml` with empirically derived thresholds
- `fluxbench-drift.sh` compares a model's current scores against its frozen `qualified_baseline` and outputs a drift verdict
- Concurrent runs of `fluxbench-score.sh` do not corrupt `fluxbench-results.jsonl` or `model-registry.yaml`
- `fluxbench-sync.sh` writes FluxBench data to AgMoDB format without duplicating entries

**Artifacts** (files with specific exports):
- [`config/flux-drive/fluxbench-metrics.yaml`] defines 9 metrics with keys, types, thresholds, weights
- [`config/flux-drive/fluxbench-thresholds.yaml`] overrides defaults with calibrated values
- [`scripts/fluxbench-score.sh`] exports `score` subcommand, reads qualification-output.json
- [`scripts/fluxbench-calibrate.sh`] runs fixtures, writes thresholds
- [`scripts/fluxbench-drift.sh`] reads model baseline from registry, outputs drift verdict
- [`scripts/fluxbench-qualify.sh`] runs model against fixtures, normalizes output, invokes scorer
- [`scripts/fluxbench-sync.sh`] reads JSONL, writes to AgMoDB format, idempotent
- [`tests/fixtures/qualification/`] contains 5+ test docs with ground-truth.json

**Key Links** (connections where breakage cascades):
- `fluxbench-qualify.sh` produces `qualification-output.json` → `fluxbench-score.sh` consumes it
- `fluxbench-score.sh` writes to `fluxbench-results.jsonl` → `fluxbench-sync.sh` reads it
- `fluxbench-calibrate.sh` writes `fluxbench-thresholds.yaml` → `fluxbench-score.sh` reads it for gate decisions
- `fluxbench-drift.sh` reads `qualified_baseline` from `model-registry.yaml` → demotes model on threshold breach

---

## Phase 1: MVP (F2 + F1)

### Task 1: FluxBench Metric Definitions Config [F1]

**Files:**
- Create: `interverse/interflux/config/flux-drive/fluxbench-metrics.yaml`
- Create: `interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml`

**Step 1: Write metric definitions**

Create `fluxbench-metrics.yaml` with all 9 metrics:

```yaml
# FluxBench Metric Definitions
# 5 core gates (qualification requirement) + 4 extended (routing/informational)
version: 1

core_gates:
  fluxbench-format-compliance:
    type: binary_gate
    description: "% of runs producing valid Findings Index (header, pipe-delimited, verdict)"
    threshold_default: 0.95
    gate: true
    higher_is_better: true

  fluxbench-finding-recall:
    type: weighted_score
    description: "Severity-weighted recall vs baseline/ground-truth"
    threshold_default: 0.60
    gate: true
    higher_is_better: true
    severity_weights:
      P0: 4
      P1: 2
      P2: 1
      P3: 0.5
    p0_auto_fail: true  # Missing any P0 fails regardless of aggregate

  fluxbench-false-positive-rate:
    type: rate
    description: "% of findings not in baseline AND not independently validated"
    threshold_default: 0.20
    gate: true
    higher_is_better: false  # Lower is better

  fluxbench-severity-accuracy:
    type: score
    description: "% of severity ratings matching baseline ±1 level"
    threshold_default: 0.70
    gate: true
    higher_is_better: true

  fluxbench-persona-adherence:
    type: llm_judge
    description: "Domain persona adherence vs generic analysis (0-1, LLM-judged)"
    threshold_default: 0.60
    gate: true
    higher_is_better: true
    judge_model: haiku

extended:
  fluxbench-instruction-compliance:
    type: score
    description: "Follows multi-step prompt structure (sections, peer protocol, focus area)"
    higher_is_better: true

  fluxbench-disagreement-rate:
    type: rate
    description: "% of findings unique to this model (not in baseline)"
    higher_is_better: true  # Diversity value

  fluxbench-latency-p50:
    type: latency_ms
    description: "p50 response latency in milliseconds"
    higher_is_better: false

  fluxbench-token-efficiency:
    type: ratio
    description: "Findings per 1K output tokens"
    higher_is_better: true
```

**Step 2: Write default thresholds file**

Create `fluxbench-thresholds.yaml` (overridden by calibration):

```yaml
# FluxBench Thresholds — calibrated values override these defaults
# Generated by: fluxbench-calibrate.sh
# Source: defaults (no calibration run yet)
version: 1
source: defaults
calibrated_at: null

thresholds:
  fluxbench-format-compliance: 0.95
  fluxbench-finding-recall: 0.60
  fluxbench-false-positive-rate: 0.20
  fluxbench-severity-accuracy: 0.70
  fluxbench-persona-adherence: 0.60
```

**Step 3: Commit**
```bash
cd interverse/interflux
git add config/flux-drive/fluxbench-metrics.yaml config/flux-drive/fluxbench-thresholds.yaml
git commit -m "feat(fluxbench): add metric definitions and default thresholds"
```

<verify>
- run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interflux/config/flux-drive/fluxbench-metrics.yaml')); print(len(d['core_gates']) + len(d['extended']))"`
  expect: contains "9"
- run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interflux/config/flux-drive/fluxbench-thresholds.yaml')); print(len(d['thresholds']))"`
  expect: contains "5"
</verify>

---

### Task 2: Qualification Test Fixtures [F2]

**Files:**
- Create: `interverse/interflux/tests/fixtures/qualification/README.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-01-null-check/document.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-01-null-check/ground-truth.json`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-02-sql-injection/document.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-02-sql-injection/ground-truth.json`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-03-naming-conventions/document.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-03-naming-conventions/ground-truth.json`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-04-race-condition/document.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-04-race-condition/ground-truth.json`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-05-api-design/document.md`
- Create: `interverse/interflux/tests/fixtures/qualification/fixture-05-api-design/ground-truth.json`

**Step 1: Write README with fixture format spec**

```markdown
# Qualification Test Fixtures

Each fixture is a directory containing:
- `document.md` — source code or document to review
- `ground-truth.json` — expected findings with severity, location, description

## ground-truth.json Schema

{
  "fixture_id": "fixture-01-null-check",
  "agent_type": "checker|analytical|judgment",
  "findings": [
    {
      "severity": "P0|P1|P2|P3",
      "location": "file:line or section reference",
      "description": "What the finding is",
      "category": "correctness|security|style|architecture|performance"
    }
  ],
  "annotator": "human|hybrid",
  "annotation_date": "YYYY-MM-DD",
  "notes": "Context about annotation decisions"
}

## Agent Type Coverage
- checker: style, naming, test coverage (fixtures 03, 05)
- analytical: architecture, design, dependencies (fixtures 05)
- judgment: security, data integrity, race conditions (fixtures 01, 02, 04)

## Adding Fixtures
1. Create directory `fixture-NN-<slug>/`
2. Add `document.md` with realistic code/doc
3. Add `ground-truth.json` following schema above
4. Annotate severity carefully — P0 auto-fails FluxBench qualification
5. For core gate calibration: require kappa >= 0.7 or dual-annotator agreement on severity
```

**Step 2: Write 5 fixtures**

Each fixture contains a realistic code document with known issues and a ground-truth file. Fixtures span checker/analytical/judgment agent types.

- **fixture-01-null-check** (judgment, P0): Python function with unchecked null dereference + missing error handling
- **fixture-02-sql-injection** (judgment, P0): Express.js endpoint with SQL injection + missing auth
- **fixture-03-naming-conventions** (checker, P2-P3): Go code with mixed naming conventions and missing docstrings
- **fixture-04-race-condition** (judgment, P1): Python threading with shared mutable state and no lock
- **fixture-05-api-design** (analytical, P1-P2): REST API with inconsistent error format and missing pagination

Ground-truth files include 3-8 findings each with exact severity, location, and description.

**Step 3: Commit**
```bash
cd interverse/interflux
git add tests/fixtures/qualification/
git commit -m "feat(fluxbench): add 5 qualification test fixtures with ground-truth"
```

<verify>
- run: `ls interverse/interflux/tests/fixtures/qualification/fixture-*/ground-truth.json | wc -l`
  expect: contains "5"
- run: `python3 -c "import json; [json.load(open(f)) for f in __import__('glob').glob('interverse/interflux/tests/fixtures/qualification/fixture-*/ground-truth.json')]; print('valid')"` 
  expect: contains "valid"
</verify>

---

### Task 3: FluxBench Scoring Engine [F1]

**Files:**
- Create: `interverse/interflux/scripts/fluxbench-score.sh`
- Test: `interverse/interflux/tests/test_fluxbench_score.bats`

**Step 1: Write the failing test**

Create `tests/test_fluxbench_score.bats` (underscore naming per project convention):

```bash
#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="${BATS_TEST_DIRNAME}/../scripts"
    FIXTURES_DIR="${BATS_TEST_DIRNAME}/fixtures/qualification"
    TMPDIR_SCORE="$(mktemp -d)"
    export FLUXBENCH_RESULTS_JSONL="${TMPDIR_SCORE}/results.jsonl"
}

teardown() {
    rm -rf "$TMPDIR_SCORE"
}

# Helper: create qualification output with required qualification_run_id
_make_qual_output() {
    local model="${1:-test-model}" findings="${2:-[]}" fcr="${3:-1.0}"
    jq -n --arg m "$model" --argjson f "$findings" --arg fcr "$fcr" \
      '{model_slug:$m, findings:$f, format_compliance_rate:($fcr|tonumber),
        metadata:{agent_type:"checker",baseline_model:"claude-sonnet-4-6",
        timestamp:"2026-04-07T00:00:00Z",qualification_run_id:("qr-"+($m))}}'
}

@test "score.sh exits 0 with valid qualification output" {
    _make_qual_output "test-model" \
      '[{"severity":"P1","location":"file.py:10","description":"Missing null check","category":"correctness"}]' \
      > "${TMPDIR_SCORE}/qual-output.json"
    cat > "${TMPDIR_SCORE}/baseline.json" <<'JSON'
    {"findings":[{"severity":"P1","location":"file.py:10","description":"Missing null check","category":"correctness"},{"severity":"P2","location":"file.py:20","description":"Missing docstring","category":"style"}]}
JSON
    run bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-output.json" "${TMPDIR_SCORE}/baseline.json" "${TMPDIR_SCORE}/result.json"
    [ "$status" -eq 0 ]
    [ -f "${TMPDIR_SCORE}/result.json" ]
    # Verify qualification_run_id present in result
    run jq -r '.qualification_run_id' "${TMPDIR_SCORE}/result.json"
    [ "$output" = "qr-test-model" ]
}

@test "score.sh computes finding-recall correctly" {
    _make_qual_output "test-model" \
      '[{"severity":"P1","location":"file.py:10","description":"Missing null check","category":"correctness"}]' \
      > "${TMPDIR_SCORE}/qual-output.json"
    cat > "${TMPDIR_SCORE}/baseline.json" <<'JSON'
    {"findings":[{"severity":"P1","location":"file.py:10","description":"Missing null check","category":"correctness"},{"severity":"P2","location":"file.py:20","description":"Missing docstring","category":"style"}]}
JSON
    run bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-output.json" "${TMPDIR_SCORE}/baseline.json" "${TMPDIR_SCORE}/result.json"
    [ "$status" -eq 0 ]
    # Weighted recall: found P1 (weight 2), missed P2 (weight 1). = 2/3 = 0.667
    recall=$(jq -r '.metrics["fluxbench-finding-recall"]' "${TMPDIR_SCORE}/result.json")
    python3 -c "assert abs(float('${recall}') - 0.667) < 0.01, f'Expected ~0.667, got ${recall}'"
}

@test "score.sh auto-fails when P0 finding missed" {
    _make_qual_output "test-model" \
      '[{"severity":"P2","location":"file.py:20","description":"Style issue","category":"style"}]' \
      > "${TMPDIR_SCORE}/qual-output.json"
    cat > "${TMPDIR_SCORE}/baseline.json" <<'JSON'
    {"findings":[{"severity":"P0","location":"file.py:5","description":"SQL injection","category":"security"},{"severity":"P2","location":"file.py:20","description":"Style issue","category":"style"}]}
JSON
    run bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-output.json" "${TMPDIR_SCORE}/baseline.json" "${TMPDIR_SCORE}/result.json"
    [ "$status" -eq 0 ]
    p0_fail=$(jq -r '.gate_results["fluxbench-finding-recall"].p0_auto_fail' "${TMPDIR_SCORE}/result.json")
    [ "$p0_fail" = "true" ]
}

@test "score.sh handles empty baseline without division by zero" {
    _make_qual_output "test-model" '[]' > "${TMPDIR_SCORE}/qual-output.json"
    cat > "${TMPDIR_SCORE}/baseline.json" <<'JSON'
    {"findings":[]}
JSON
    run bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-output.json" "${TMPDIR_SCORE}/baseline.json" "${TMPDIR_SCORE}/result.json"
    [ "$status" -eq 0 ]
    # Empty baseline → recall=1.0 (vacuously true), FP rate=0.0
    recall=$(jq -r '.metrics["fluxbench-finding-recall"]' "${TMPDIR_SCORE}/result.json")
    [ "$recall" = "1" ]
}

@test "score.sh concurrent writes produce valid JSONL" {
    # Launch 10 parallel scoring invocations
    for i in $(seq 1 10); do
        _make_qual_output "model-${i}" '[]' > "${TMPDIR_SCORE}/qual-${i}.json"
        cp "${TMPDIR_SCORE}/qual-${i}.json" "${TMPDIR_SCORE}/baseline-${i}.json"
        bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-${i}.json" \
          "${TMPDIR_SCORE}/baseline-${i}.json" "${TMPDIR_SCORE}/result-${i}.json" &
    done
    wait
    # Verify: exactly 10 lines, each valid JSON
    lines=$(wc -l < "${FLUXBENCH_RESULTS_JSONL}")
    [ "$lines" -eq 10 ]
    run jq -e '.' "${FLUXBENCH_RESULTS_JSONL}"
    # jq exits 0 only if every line is valid JSON (in slurp mode)
    [ "$status" -eq 0 ]
}

@test "score.sh format-compliance is binary gate" {
    _make_qual_output "test-model" '[]' '0.94' > "${TMPDIR_SCORE}/qual-output.json"
    cat > "${TMPDIR_SCORE}/baseline.json" <<'JSON'
    {"findings":[]}
JSON
    run bash "${SCRIPT_DIR}/fluxbench-score.sh" "${TMPDIR_SCORE}/qual-output.json" "${TMPDIR_SCORE}/baseline.json" "${TMPDIR_SCORE}/result.json"
    [ "$status" -eq 0 ]
    gate=$(jq -r '.gate_results["fluxbench-format-compliance"].passed' "${TMPDIR_SCORE}/result.json")
    [ "$gate" = "false" ]
}
```

**Step 2: Run tests to verify they fail**
```bash
cd interverse/interflux && bats tests/test_fluxbench_score.bats
```
Expected: FAIL (script doesn't exist yet)

**Step 3: Write fluxbench-score.sh**

The scoring engine:
1. Reads `qualification-output.json` and `baseline.json`
2. Loads thresholds from `fluxbench-thresholds.yaml` (falls back to `fluxbench-metrics.yaml` defaults)
3. Computes all 9 metrics via finding matching (location + description similarity)
4. Evaluates 5 core gate pass/fail decisions
5. Writes result JSON to output path
6. Appends result to `fluxbench-results.jsonl` under flock

Key implementation details:
- **Results path:** `FLUXBENCH_RESULTS_JSONL` env var, defaulting to `${SCRIPT_DIR}/../data/fluxbench-results.jsonl`. Script runs `mkdir -p "$(dirname "$results_jsonl")"` before first write.
- **qualification_run_id:** Passed through from input `metadata.qualification_run_id` to result JSON. Used by sync.sh for idempotency. Score.sh fails if field missing.
- **Finding matching:** Normalize location strings (strip `./` prefix, lowercase). Match on exact location + Levenshtein distance on description (threshold: distance <= 30% of string length). Use Python's `difflib.SequenceMatcher` (stdlib, no external deps). **Bipartite constraint:** each baseline finding matches at most one model finding (greedy best-match, prevents credit-stacking).
- **Severity-weighted recall:** `sum(found_weights) / sum(all_weights)` where weights come from `fluxbench-metrics.yaml`. **Edge case:** empty baseline → recall = 1.0 (vacuously true), not division by zero.
- P0 auto-fail: if any P0 in baseline is not in model findings, `p0_auto_fail: true`
- **Format compliance:** Read from `format_compliance_rate` field in qualification output. **Callers must compute this:** `fluxbench-qualify.sh` counts valid Findings Index outputs / total runs.
- False positive rate: `len(model_only) / len(model_findings)` where `model_only` is findings not in baseline. Edge case: 0 model findings → FP rate = 0.0.
- **JSONL write (fd 200):** `(flock -x 200; echo "$json_line" >> "$results_jsonl") 200>"${results_jsonl}.lock"`
- **Registry write (fd 201, separate from JSONL):**
  ```bash
  registry="${SCRIPT_DIR}/../config/flux-drive/model-registry.yaml"
  (
    flock -x 201
    cp "$registry" "${registry}.tmp"
    yq -i ".models[...] = ..." "${registry}.tmp"
    python3 -c "import yaml; yaml.safe_load(open('${registry}.tmp'))"  # validate
    mv "${registry}.tmp" "$registry"
  ) 201>"${registry}.lock"
  ```

**Step 4: Run tests to verify they pass**
```bash
cd interverse/interflux && bats tests/test_fluxbench_score.bats
```
Expected: all 5 tests PASS

**Step 5: Commit**
```bash
cd interverse/interflux
git add scripts/fluxbench-score.sh tests/test_fluxbench_score.bats
git commit -m "feat(fluxbench): implement scoring engine with 9 metrics and flock-safe writes"
```

<verify>
- run: `cd interverse/interflux && bats tests/test_fluxbench_score.bats`
  expect: exit 0
- run: `bash interverse/interflux/scripts/fluxbench-score.sh --help 2>&1`
  expect: contains "qualification-output.json"
</verify>

---

### Task 4: Calibration Script [F2]

**Files:**
- Create: `interverse/interflux/scripts/fluxbench-calibrate.sh`
- Test: `interverse/interflux/tests/test_fluxbench_calibrate.bats`

**Step 1: Write the failing test**

```bash
@test "calibrate.sh runs all fixtures and writes thresholds" {
    export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/fixtures/qualification" && pwd)"
    export TMPDIR_CAL="$(mktemp -d)"
    # Mock Claude baseline output (in real usage, calibrate.sh calls Claude)
    export FLUXBENCH_MOCK_BASELINE=true
    export FLUXBENCH_THRESHOLDS_OUT="$TMPDIR_CAL/thresholds.yaml"
    
    run bash "$SCRIPT_DIR/fluxbench-calibrate.sh" --fixtures-dir "$FIXTURES_DIR" --output "$TMPDIR_CAL/thresholds.yaml" --mock
    [ "$status" -eq 0 ]
    [ -f "$TMPDIR_CAL/thresholds.yaml" ]
    # Verify all 5 core thresholds present
    count=$(python3 -c "import yaml; d=yaml.safe_load(open('$TMPDIR_CAL/thresholds.yaml')); print(len(d['thresholds']))")
    [ "$count" -eq 5 ]
}

@test "calibrate.sh source field says calibrated not defaults" {
    export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/fixtures/qualification" && pwd)"
    export TMPDIR_CAL="$(mktemp -d)"
    
    run bash "$SCRIPT_DIR/fluxbench-calibrate.sh" --fixtures-dir "$FIXTURES_DIR" --output "$TMPDIR_CAL/thresholds.yaml" --mock
    [ "$status" -eq 0 ]
    source_val=$(python3 -c "import yaml; d=yaml.safe_load(open('$TMPDIR_CAL/thresholds.yaml')); print(d['source'])")
    [ "$source_val" = "calibrated" ]
}
```

**Step 2: Run tests to verify they fail**

**Step 3: Write fluxbench-calibrate.sh**

The calibration script:
1. Scans `tests/fixtures/qualification/fixture-*/` for ground-truth files
2. For each fixture: runs `fluxbench-score.sh` with ground-truth as both baseline and "ideal model output" (bootstrapping mode)
3. Computes threshold recommendations: p25 of Claude's scores across all fixtures (conservative)
4. Writes `fluxbench-thresholds.yaml` with `source: calibrated` and `calibrated_at` timestamp
5. `--mock` flag uses pre-computed ground-truth as model output (for testing without Claude API)

**Step 4: Run tests to verify they pass**

**Step 5: Commit**
```bash
cd interverse/interflux
git add scripts/fluxbench-calibrate.sh tests/test_fluxbench_calibrate.bats
git commit -m "feat(fluxbench): add calibration script for empirical threshold derivation"
```

<verify>
- run: `cd interverse/interflux && bats tests/test_fluxbench_calibrate.bats`
  expect: exit 0
</verify>

---

### Task 5: Model Registry Schema Extension [F1]

**Files:**
- Modify: `interverse/interflux/config/flux-drive/model-registry.yaml`

**Step 1: Extend registry schema**

Add FluxBench fields to the model entry template and add `qualified_baseline` concept:

```yaml
# Add to model entry template (under qualification:):
    # FluxBench scores (written by fluxbench-score.sh)
    fluxbench:
      format_compliance: null
      finding_recall: null
      false_positive_rate: null
      severity_accuracy: null
      persona_adherence: null
      instruction_compliance: null
      disagreement_rate: null
      latency_p50: null
      token_efficiency: null
    # Frozen baseline — IMMUTABLE snapshot at qualification time.
    # Written once by fluxbench-qualify.sh on first qualification.
    # Drift is always measured against this, never running averages.
    # Write-once contract: all registry writers MUST check if qualified_baseline
    # is non-null before writing. Only fluxbench-qualify.sh may set it, and only
    # when transitioning status to qualified/auto-qualified.
    # To reset: operator must manually null it and re-qualify.
    qualified_baseline: null

# Add to root level:
# FluxBench configuration
fluxbench:
  sample_rate: 10              # 1-in-N reviews for drift sampling
  max_sample_gap: 20           # Force shadow if unsampled for this many reviews
  drift_threshold: 0.15        # Flag drift if any core metric drops >15%
  hysteresis_band: 0.05        # Clear drift only when within 5% of baseline
  correlated_drift_threshold: 0.50  # >=50% simultaneous drift = baseline shift
  challenger_slots: 1          # Integer, 0 to disable
  weekly_budget_ceiling: 5     # Max candidates per weekly qualification cycle
```

**Step 2: Commit**
```bash
cd interverse/interflux
git add config/flux-drive/model-registry.yaml
git commit -m "feat(fluxbench): extend model registry with FluxBench scores and drift config"
```

<verify>
- run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interflux/config/flux-drive/model-registry.yaml')); print('fluxbench' in d)"`
  expect: contains "True"
</verify>

---

## Phase 2: Feedback (F3 + F4)

### Task 6: AgMoDB Store-and-Forward Sync [F3]

**Files:**
- Create: `interverse/interflux/scripts/fluxbench-sync.sh`
- Test: `interverse/interflux/tests/test_fluxbench_sync.bats`

**Step 1: Write the failing test**

Tests verify: JSONL → AgMoDB format conversion, idempotency (re-run doesn't duplicate), missing JSONL handled gracefully.

**Step 2: Write fluxbench-sync.sh**

The sync script:
1. Reads `data/fluxbench-results.jsonl` (path via `FLUXBENCH_RESULTS_JSONL` env var)
2. For each result, checks `.sync-state` file (keyed on `qualification_run_id` — this field is required in every result, written by score.sh from the input metadata)
3. Converts to AgMoDB `externalBenchmarkScores` format
4. **Writes `.sync-state` FIRST** (marks entries as pending-sync)
5. Writes converted entries to AgMoDB repo directory (configurable via `AGMODB_REPO_PATH`)
6. Does NOT git commit — writes local files only. Git operations belong to the orchestrator (operator runs `git add && git commit` or a separate push script). This keeps sync.sh side-effect-free.
7. **Updates `.sync-state` entries to committed** after successful write
8. Crash recovery: entries marked pending-sync but not committed are re-written on next run (idempotent via `qualification_run_id` keying)

**Step 3: Run tests, commit**

<verify>
- run: `cd interverse/interflux && bats tests/test_fluxbench_sync.bats`
  expect: exit 0
</verify>

---

### Task 7: Drift Detection Script [F4]

**Files:**
- Create: `interverse/interflux/scripts/fluxbench-drift.sh`
- Test: `interverse/interflux/tests/test_fluxbench_drift.bats`

**Step 1: Write the failing test**

Tests verify: drift detected when score drops >15%, no drift flagged within normal variance, hysteresis prevents oscillation, correlated drift (>=50% models) triggers baseline-shift alert instead of mass-demotion.

**Step 2: Write fluxbench-drift.sh**

The drift script:
1. Reads a model's `qualified_baseline` from `model-registry.yaml`
2. Compares against latest FluxBench scores (from a shadow run)
3. If any core metric drops >15% from `qualified_baseline`: output `drift_detected`, demote model to `qualifying`
4. If recovery (all core metrics within 5% of `qualified_baseline`): output `drift_cleared`
5. Correlated drift check: if called with `--fleet-check`, counts models with drift flags. If >=50%, outputs `baseline_shift_suspected` instead of demoting
6. Registry writes use atomic swap + flock (same pattern as score.sh)

**Step 3: Run tests, commit**

<verify>
- run: `cd interverse/interflux && bats tests/test_fluxbench_drift.bats`
  expect: exit 0
</verify>

---

## Phase 3: Automation (F5 + F6)

### Task 8: Qualification Runner [F5]

**Files:**
- Create: `interverse/interflux/scripts/fluxbench-qualify.sh`
- Test: `interverse/interflux/tests/test_fluxbench_qualify.bats`

**Step 1: Write fluxbench-qualify.sh**

The qualification runner:
1. Takes a model slug and provider as input
2. Runs the model against all fixtures in `tests/fixtures/qualification/`
3. For each fixture: dispatches the model via appropriate provider, captures output
4. Normalizes output to `qualification-output.json` format (F1 input contract)
5. Invokes `fluxbench-score.sh` for each fixture
6. Aggregates results: pass all 5 core gates across all fixtures → promote to `auto-qualified`
7. Updates `model-registry.yaml` with status change and scores

**Step 2: Run tests, commit**

<verify>
- run: `cd interverse/interflux && bats tests/test_fluxbench_qualify.bats`
  expect: exit 0
</verify>

---

### Task 9: SessionStart Awareness Hook [F5]

**Files:**
- Modify: `interverse/interflux/hooks/session-start.sh`

**Step 1: Add awareness query**

After existing budget signal code, add:
1. Read `model-registry.yaml` to get list of known model slugs
2. Query interrank `recommend_model` for "code review agent" (single MCP call, zero-cost)
3. Compare results against registry — surface models not in registry
4. If new models found: print one-line awareness message
5. Check active models for `requalification_needed` flag — if set, print advisory

**Step 2: Commit**

<verify>
- run: `grep -c 'requalification_needed\|recommend_model' interverse/interflux/hooks/session-start.sh`
  expect: contains "2"
</verify>

---

### Task 10: Weekly Discovery Agent Spec [F5]

**Files:**
- Create: `interverse/interflux/agents/fluxbench-discover.md`

**Step 1: Write agent spec**

```markdown
---
name: fluxbench-discover
description: Weekly model discovery and auto-qualification agent
schedule: weekly
autonomy: auto-qualified (requires operator confirmation for full promotion)
---

# FluxBench Discovery Agent

## Purpose
Discover new model candidates via interrank and auto-qualify them against FluxBench test fixtures.

## Workflow
1. Run `scripts/discover-models.sh` to generate interrank queries
2. Execute MCP calls: `recommend_model` for each tier query, `cost_leaderboard` for coding+agentic
3. For each new candidate not in model-registry.yaml:
   a. Add as `status: candidate`
   b. Run `scripts/fluxbench-qualify.sh <model_slug>`
   c. If passes: promote to `auto-qualified`, create bead
   d. If fails: mark failure reason, leave as `candidate`
4. Budget ceiling: max 5 candidates per run (configurable in model-registry.yaml)
5. Write summary to stdout for operator awareness

## Tools Required
- interrank MCP: recommend_model, cost_leaderboard
- File read/write: model-registry.yaml, fluxbench-results.jsonl
- Beads: bd create (for qualified candidates)
```

**Step 2: Commit**

---

### Task 11: interrank TASK_DOMAIN_MAP Update [F6]

**Files:**
- Modify: `interverse/interrank/src/recommend.ts`
- Test: `interverse/interrank/src/recommend.test.ts` (if exists, else create)

**Step 1: Add fluxbench to domain map**

In `recommend.ts`, add `"fluxbench"` to the affinity lists for code-review-related archetypes:

```typescript
// In TASK_DOMAIN_MAP:
"code review": ["coding", "agents", "fluxbench"],
"agent": ["agents", "coding", "fluxbench"],
"automation": ["agents", "coding", "fluxbench"],
```

**Step 2: Verify backwards compatibility**

Queries without FluxBench data should continue to work — the affinity boost only applies when benchmarks with `category: "fluxbench"` exist in the snapshot.

**Step 3: Commit**
```bash
cd interverse/interrank
git add src/recommend.ts
git commit -m "feat(interrank): add fluxbench category affinity for code-review queries"
```

<verify>
- run: `grep -c 'fluxbench' interverse/interrank/src/recommend.ts`
  expect: contains "3"
</verify>

---

## Phase 4: Optimization (F7)

### Task 12: Challenger Slot Triage Integration [F7]

**Files:**
- Modify: `interverse/interflux/config/flux-drive/budget.yaml` (add challenger config)
- Modify: `interverse/interflux/config/flux-drive/agent-roles.yaml` (add challenger tier)
- Create: `interverse/interflux/scripts/fluxbench-challenger.sh` (challenger lifecycle management)

**Step 1: Add challenger config to budget.yaml**

```yaml
# Challenger slot configuration
challenger:
  enabled: true
  slots: 1                    # Integer, 0 to disable
  pre_inclusion_runs: 2       # Synthetic fixture runs before real dispatch
  promotion_threshold: 10     # Minimum real runs before evaluation
  early_exit_margin: 0.20     # Fast-track at run 5 if passing by this margin
  stale_threshold: 20         # Reject after this many runs without passing
  safety_exclusions:           # Roles challenger can never fill
    - fd-safety
    - fd-correctness
```

**Step 2: Add challenger tier to agent-roles.yaml**

**Step 3: Write challenger lifecycle script**

`fluxbench-challenger.sh` handles:
1. Select highest-scoring `qualifying`/`auto-qualified` model from registry
2. Pre-inclusion filter: run 2 synthetic fixtures, verify format-compliance gate
3. Track challenger run count in registry
4. After promotion_threshold runs: evaluate all 5 core gates
5. Early exit: if passing by >20% margin after 5 runs, fast-track promote
6. Stale cleanup: reject after 20 runs without passing

**Step 4: Commit**

<verify>
- run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interflux/config/flux-drive/budget.yaml')); print('challenger' in d)"`
  expect: contains "True"
</verify>

---

## Task Dependencies

```
Task 1 (metrics config) ────┐
                             ├──▶ Task 3 (scoring engine)
Task 2 (fixtures) ──────────┘          │
                                       ├──▶ Task 4 (calibration)
                                       ├──▶ Task 5 (registry extension)
                                       ├──▶ Task 6 (sync) ──▶ Task 11 (interrank)
                                       ├──▶ Task 7 (drift)
                                       ├──▶ Task 8 (qualify runner)
                                       │         │
                                       │         ├──▶ Task 9 (SessionStart hook)
                                       │         └──▶ Task 10 (agent spec)
                                       └──▶ Task 12 (challenger)
```

**Wave 1 (independent):** Tasks 1, 2 (no dependencies)
**Wave 2 (after Wave 1):** Tasks 3, 5 (depend on Task 1)
**Wave 3 (after Wave 2):** Tasks 4, 6, 7, 8 (depend on Task 3)
**Wave 4 (after Wave 3):** Tasks 9, 10, 11 (depend on Tasks 6, 8)
**Wave 5 (after Wave 3):** Task 12 (depends on Tasks 3, 7)

## Plan Review-Incorporated Changes (2026-04-07)

### P0 resolutions
1. **IP-06/P0-01 (qualification_run_id):** Added to qualification-output.json schema, test helper `_make_qual_output`, and result pass-through contract. Score.sh fails if missing.
2. **P0-02 (data path):** Canonicalized on `FLUXBENCH_RESULTS_JSONL` env var with `mkdir -p` guard. Default: `${SCRIPT_DIR}/../data/fluxbench-results.jsonl`.
3. **IP-01 (vacuous concurrent test):** Added parallel-invocation test (10 background writes + jq validation of every line).
4. **IP-02 (registry atomic swap):** Explicit code block for YAML path using fd 201 (separate from JSONL fd 200). Pattern: cp → yq → validate → mv.
5. **IP-03 (hysteresis ratchet):** Added write-once contract for `qualified_baseline` in registry schema comments. Only qualify.sh may set it.

### Key P1 resolutions
- **Finding matching:** Replaced Jaro-Winkler with `difflib.SequenceMatcher` (stdlib). Added location normalization and bipartite constraint.
- **Empty baseline:** Added edge case handling (recall=1.0 vacuously, FP=0.0) with dedicated test.
- **Bats conventions:** Renamed all test files to underscore format. Used `BATS_TEST_DIRNAME` not `BATS_TEST_FILENAME` dance. Added teardown() to calibration tests.
- **Sync state ordering:** Write `.sync-state` before AgMoDB files (not after). Removed git commit from sync.sh (operator responsibility).
- **format_compliance_rate:** Noted that callers (qualify.sh) must compute this field.
