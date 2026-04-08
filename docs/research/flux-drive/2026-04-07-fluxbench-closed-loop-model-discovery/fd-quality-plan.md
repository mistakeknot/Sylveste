---
artifact_type: review
reviewer: fd-quality
plan: docs/plans/2026-04-07-fluxbench-closed-loop-model-discovery.md
reviewed_at: 2026-04-07
---
# FluxBench Closed-Loop Model Discovery — Plan Quality Review

## Findings Index

| # | Severity | Area | Title |
|---|----------|------|-------|
| Q-01 | P1 | Test file naming | bats files use underscore (`test_`) while plan proposes hyphen (`test-`) |
| Q-02 | P1 | Shell safety | `setup()` in proposed bats uses `$()` subshell expansion without `BATS_TEST_DIRNAME` guard, diverging from existing pattern |
| Q-03 | P1 | Shell safety | `eval` in `discover-models.sh` (existing) pattern used as implicit template; plan's calibrate tests use unquoted variable expansion inside `python3 -c` heredoc |
| Q-04 | P1 | Complexity | `fluxbench-score.sh` delegates finding-match fuzzy similarity to a Python jaro-winkler helper with no existence check — adds a hidden dependency path with no fallback |
| Q-05 | P2 | Test structure | Calibration tests use `export TMPDIR_CAL` inside `@test` blocks rather than `setup()`/`teardown()` — inconsistent with `test_estimate_costs.bats` pattern and leaks temp dirs on failure |
| Q-06 | P2 | Config structure | `fluxbench` root key proposed in `model-registry.yaml` duplicates config that already lives (or belongs) in `budget.yaml` — two config files for the same operational knobs |
| Q-07 | P2 | Commit granularity | Task 3 combines scorer implementation and its bats test in a single commit; project pattern (test-budget.sh, test-findings-flow.sh) separates test scripts from implementation scripts when they grow large |
| Q-08 | P2 | `session-start.sh` modification | Proposed change adds `set -e`-style logic to a file that deliberately uses `set -uo pipefail` + `trap 'exit 0' ERR` — adding new failure modes inside a hook that must never hard-fail |
| Q-09 | P3 | Naming | Script `fluxbench-challenger.sh` — "challenger" is a lifecycle concept, not an action; existing scripts use verb-noun (`discover-models`, `estimate-costs`, `validate-roster`). Suggest `fluxbench-promote-challenger.sh` or absorbing into `fluxbench-qualify.sh` |
| Q-10 | P3 | Verify blocks | Several `<verify>` blocks use `cd interverse/interflux &&` which relies on relative CWD — inconsistent with existing scripts that compute `SCRIPT_DIR` and use absolute paths |

---

## Detail

### Q-01 — P1: bats file naming convention mismatch

The single existing bats file in `interverse/interflux/tests/` is named `test_estimate_costs.bats` (underscore separator). The plan proposes `test-fluxbench-score.bats`, `test-fluxbench-calibrate.bats`, `test-fluxbench-sync.bats`, `test-fluxbench-drift.bats`, and `test-fluxbench-qualify.bats` (hyphen separator).

The `.sh` tests use hyphens (`test-budget.sh`, `test-findings-flow.sh`), which is a different category. Within bats specifically, one data point is not enough to establish a convention — but introducing a second pattern makes discovery harder and `ls tests/*.bats` more confusing if mixed.

Recommendation: pick one separator for all new bats files and document it in `agents/testing.md`. If the project intends bats for unit/integration and `.sh` for flow tests, name new bats files `test_fluxbench_score.bats` to stay consistent with the only existing bats precedent.

---

### Q-02 — P1: `setup()` uses `$()` subshell without standard guard

The proposed `setup()` block in `test-fluxbench-score.bats`:

```bash
export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
```

`BATS_TEST_FILENAME` is the correct variable (available in bats >= 1.3). The existing `test_estimate_costs.bats` uses `$BATS_TEST_DIRNAME` directly without the cd-dance. These resolve to different things: `BATS_TEST_DIRNAME` is the directory, `BATS_TEST_FILENAME` is the full path. Using `dirname "$BATS_TEST_FILENAME"` and `BATS_TEST_DIRNAME` should be equivalent — but the plan mixes both styles across different test files. Standardize on `$BATS_TEST_DIRNAME` (what the existing test uses) and drop the redundant `$(dirname ...)` computation.

Also, the existing test declares `SCRIPT_DIR` without `export` — the plan exports it. Prefer consistency with the existing pattern.

---

### Q-03 — P1: Unquoted variable expansion inside `python3 -c` in test assertions

In the calibration test:

```bash
count=$(python3 -c "import yaml; d=yaml.safe_load(open('$TMPDIR_CAL/thresholds.yaml')); print(len(d['thresholds']))")
[ "$count" -eq 5 ]
```

`$TMPDIR_CAL` is interpolated into a Python string. If `mktemp -d` produces a path with spaces or special characters (unlikely but possible in CI), this silently corrupts the Python expression. The existing `test_estimate_costs.bats` avoids this by passing paths via `HOME=` env overrides and never interpolating paths into `-c` strings.

Use a file-level variable set outside the string, or pass the path via an env var read inside the Python snippet:

```bash
count=$(THRESHOLDS_FILE="$TMPDIR_CAL/thresholds.yaml" python3 -c \
  "import yaml,os; d=yaml.safe_load(open(os.environ['THRESHOLDS_FILE'])); print(len(d['thresholds']))")
```

---

### Q-04 — P1: Hidden Python jaro-winkler dependency with no fallback

The scoring engine design specifies:

> Finding matching: exact location match + jaro-winkler on description (threshold 0.7) using Python helper

No Python library ships jaro-winkler in stdlib (`difflib` has `SequenceMatcher`, not jaro-winkler). This means the implementation will silently require `pip install jellyfish` or similar — a new transitive dependency that is not declared in `pyproject.toml` or mentioned in prerequisites.

The existing shell scripts call `python3 -c` only for YAML parsing (stdlib `yaml`) and basic math. Introducing a non-stdlib Python dependency in a bash script via an undeclared helper is a maintenance trap.

Options (in order of preference):
1. Use `difflib.SequenceMatcher` ratio (stdlib, adequate for description similarity)
2. Add `jellyfish` to `pyproject.toml` and note the dependency explicitly in Task 3
3. Implement a shell-only fallback: exact match on the first 60 characters of the description

---

### Q-05 — P2: Temp dir lifecycle in calibration tests

The calibration bats tests create `TMPDIR_CAL` inside `@test` blocks with no `teardown()`:

```bash
@test "calibrate.sh runs all fixtures and writes thresholds" {
    export TMPDIR_CAL="$(mktemp -d)"
    ...
}
```

On test failure, the temp dir is never cleaned up. The existing `test_estimate_costs.bats` uses `TEST_DIR` in `setup()` and cleans it in `teardown()`:

```bash
setup() {
    TEST_DIR="$(mktemp -d)"
}
teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}
```

Move `TMPDIR_CAL` creation into `setup()` and cleanup into `teardown()`. This matches the project's established pattern and prevents temp dir accumulation under `/tmp` on failure runs.

---

### Q-06 — P2: Operational knobs split across two config files

Task 5 proposes adding a `fluxbench:` root key to `model-registry.yaml`:

```yaml
fluxbench:
  sample_rate: 10
  max_sample_gap: 20
  drift_threshold: 0.15
  ...
  challenger_slots: 1
  weekly_budget_ceiling: 5
```

These are operational scheduling and thresholding knobs — the same kind of config that already lives in `budget.yaml` (which has `model_discovery`, `enforcement`, `slicing_multiplier`, etc.). `model-registry.yaml` is a data file (model entries with scores and status); embedding policy config there means two files must be read for any runtime decision.

Move the `fluxbench:` operational block to `budget.yaml` alongside `model_discovery`. Keep `model-registry.yaml` as a pure data store. The scoring scripts already read `budget.yaml` for `BUDGET_FILTER` and `MIN_CONFIDENCE` — they can read `fluxbench:` from there too.

---

### Q-07 — P2: Commit granularity for Task 3

Task 3 Step 5 commits `fluxbench-score.sh` and `test-fluxbench-score.bats` together:

```bash
git add scripts/fluxbench-score.sh tests/test-fluxbench-score.bats
git commit -m "feat(fluxbench): implement scoring engine with 9 metrics and flock-safe writes"
```

This is acceptable for small scripts, but `fluxbench-score.sh` is described as the most complex script in the plan (jaro-winkler matching, weighted recall, P0 auto-fail, JSONL writes, registry writes). Existing practice in this repo is to commit fixtures and tests first (the TDD flow the plan itself describes) so that the "failing test" state is captured in git history before the implementation lands. The commit message also mixes the test and the implementation. Suggest two commits: `test(fluxbench): add scoring engine test suite` then `feat(fluxbench): implement scoring engine`. This is minor but matters for bisect and code review.

---

### Q-08 — P2: `session-start.sh` modification risks adding hard-failure paths to a safety hook

`session-start.sh` deliberately opens with:

```bash
set -uo pipefail
trap 'exit 0' ERR
```

Note the absence of `-e` and the `trap 'exit 0' ERR` — the hook swallows all errors because a failing hook blocks the session. Task 9 proposes adding:

```bash
# Read model-registry.yaml to get list of known model slugs
# Query interrank recommend_model for "code review agent" (single MCP call, zero-cost)
```

Any logic that reads `model-registry.yaml` or calls interrank inside this hook can fail if the file is missing, malformed, or the MCP server is down. Under `trap 'exit 0' ERR`, failures are silently swallowed, which is correct — but if the implementation uses subshells or pipelines that bypass the trap (e.g., `$(yq ...)` inside `[[ ... ]]`), it can propagate non-zero exits.

The plan should explicitly state that the new code block must follow the hook's existing defensive pattern: wrap in a conditional that checks file existence first, use `|| true` on every command, and never rely on the MCP call succeeding. A verify block checking for `|| true` or equivalent guards would make this intention testable.

---

### Q-09 — P3: `fluxbench-challenger.sh` naming does not follow verb-noun pattern

Existing scripts: `discover-models.sh`, `estimate-costs.sh`, `validate-roster.sh`, `validate-manifest.sh`, `validate-gitleaks-waivers.sh`, `findings-helper.sh`. All use verb-noun or verb-noun-noun naming.

`fluxbench-challenger.sh` names a concept rather than an action. If the script manages the full lifecycle (select, pre-include, track, promote, reject), `fluxbench-manage-challenger.sh` is more consistent. If it only promotes, `fluxbench-promote.sh`. This is low-stakes but naming consistency in scripts/ matters for discoverability.

Alternatively, absorb challenger lifecycle into `fluxbench-qualify.sh` behind a `--challenger` flag, reducing the total script count.

---

### Q-10 — P3: `<verify>` blocks use relative CWD

Multiple verify blocks use:

```bash
cd interverse/interflux && bats tests/test-fluxbench-score.bats
```

This requires the agent executing the plan to be at the monorepo root. Scripts in this project compute `SCRIPT_DIR` and `PLUGIN_DIR` as absolute paths from `${BASH_SOURCE[0]}`. Verify blocks should match: use absolute paths or `BATS_TEST_DIRNAME`-equivalent resolution. The verify for Task 1 is particularly fragile — it opens YAML files at a relative path that will break if run from inside the interflux directory.

Suggest standardizing all verify `run:` lines to be runnable from any CWD, either by specifying the full path or by prefixing with `cd "$(git rev-parse --show-toplevel)/interverse/interflux" &&`.

---

## Summary Assessment

The plan is architecturally sound and the TDD flow is well-structured. The most actionable fixes before implementation starts:

- Resolve the jaro-winkler dependency gap (Q-04) — it will block Task 3 mid-implementation
- Move operational config out of `model-registry.yaml` into `budget.yaml` (Q-06) — easier to fix in the plan than to refactor after two tasks are implemented
- Standardize bats naming and `setup()`/`teardown()` patterns (Q-01, Q-05) — low effort, prevents drift from the one existing bats precedent

The remaining findings (Q-07 through Q-10) are style and convention nits that can be addressed during implementation without replanning.

<!-- flux-drive:complete -->
