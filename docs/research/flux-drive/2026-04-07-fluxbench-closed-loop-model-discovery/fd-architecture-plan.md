# FluxBench Closed-Loop Model Discovery — Architecture Plan Review

**Source plan:** `/home/mk/projects/Sylveste/docs/plans/2026-04-07-fluxbench-closed-loop-model-discovery.md`
**Reviewer:** fd-architecture (flux-drive)
**Date:** 2026-04-07
**Scope:** Implementation plan review — file paths, task dependencies, integration contracts, flock consistency, test realism

---

## Findings Index

| ID | Severity | Area | Title |
|----|----------|------|-------|
| P0-01 | P0 | Integration contract | `qualification_run_id` field missing from `qualification-output.json` schema but required by sync |
| P0-02 | P0 | File paths | `data/fluxbench-results.jsonl` path does not exist and is never created |
| P1-01 | P1 | Flock consistency | Registry writes in `fluxbench-score.sh` described as atomic but the pattern diverges from `findings-helper.sh` precedent |
| P1-02 | P1 | Task dependency | Task 12 (challenger) depends on Task 5 (registry extension) not just Task 3 — wave assignment is wrong |
| P1-03 | P1 | Test realism | `BATS_TEST_FILENAME` used in plan test code; existing codebase uses `BATS_TEST_DIRNAME` |
| P1-04 | P1 | Integration gap | `fluxbench-qualify.sh` output schema omits `format_compliance_rate` field that `fluxbench-score.sh` reads |
| P2-01 | P2 | Speculative complexity | Jaro-Winkler described as the matching algorithm but no library is available in the test environment |
| P2-02 | P2 | Integration gap | `fluxbench-sync.sh` performs a `git commit` inside a plugin directory, breaking the interflux-as-library model |
| P2-03 | P2 | Task dependency | Task 11 (interrank TASK_DOMAIN_MAP) is waved after Task 6 (sync), but the dependency is on Task 8 (qualify runner), not sync |
| P2-04 | P2 | Scope creep | Task 9 (SessionStart hook) calls `recommend_model` MCP at session start — violates the hook's zero-cost contract |
| P3-01 | P3 | YAGNI | `fluxbench-thresholds.yaml` is a separate file from `fluxbench-metrics.yaml` with only 5 fields; merge or use a `calibrated_overrides` block |
| P3-02 | P3 | Test realism | Verify commands in Task 1 use relative paths from a `cd interverse/interflux` context; the `python3 -c` commands open paths without a path prefix |

---

## P0 Findings

### P0-01 — `qualification_run_id` field missing from qualification-output.json schema

**Location:** Task 3 Step 3 (score.sh) and Task 6 (sync.sh), plan lines 282–295 and 528–529

`fluxbench-sync.sh` (Task 6, step 2) keys its idempotency `.sync-state` file on `qualification_run_id`. That field is not present in the `qualification-output.json` schema defined in Task 3's test fixtures:

```json
{"model_slug":"test-model","findings":[...],"metadata":{"agent_type":"checker","baseline_model":"claude-sonnet-4-6","timestamp":"2026-04-07T00:00:00Z"}}
```

Neither the test fixture JSON nor the scorer's output result JSON include a `qualification_run_id`. If the sync script reads a field that the scorer never writes, every sync run either silently skips all results or crashes on a null key lookup.

**Smallest fix:** Add `qualification_run_id` to the `metadata` block of `qualification-output.json`. The scorer derives it as `"${model_slug}:${timestamp}"` or a uuid, and copies it into the result JSON. Update the Task 3 test fixtures to include it. Sync uses it as written.

---

### P0-02 — `data/fluxbench-results.jsonl` path does not exist and is never created

**Location:** Task 3 Step 3 (score.sh writes to `fluxbench-results.jsonl`), Task 6 Step 2 (sync reads `data/fluxbench-results.jsonl`), plan lines 366 and 528

The architecture summary says the scorer appends to `fluxbench-results.jsonl`. The test for score.sh uses the env variable `FLUXBENCH_RESULTS_JSONL` to override the path (Task 3 test, line 328), confirming the default path is baked into the script. Task 6 hard-codes the read path as `data/fluxbench-results.jsonl`. But `interverse/interflux/data/` does not exist anywhere in the codebase — verified by inspection. No task in the plan creates it.

This is a silent break: `fluxbench-score.sh` may write to `scripts/fluxbench-results.jsonl` or `config/flux-drive/fluxbench-results.jsonl` depending on where it resolves `$PLUGIN_DIR`, and `fluxbench-sync.sh` reads a different path entirely.

**Smallest fix:** Pick one canonical path (recommended: `config/flux-drive/fluxbench-results.jsonl` to keep all runtime state with the other registry files) and make both scripts use `${PLUGIN_DIR}/config/flux-drive/fluxbench-results.jsonl`. Add a `mkdir -p` guard in score.sh. Remove the discrepancy by either eliminating the `data/` prefix or creating the directory explicitly in Task 2 or Task 3.

---

## P1 Findings

### P1-01 — Registry writes diverge from the established flock pattern

**Location:** Task 3 Step 3, plan line 375

The plan describes the registry write pattern as:

> "write .tmp, yq merge, mv .tmp to registry"

The established pattern in `findings-helper.sh` (the documented precedent) uses:

```bash
(flock -x 200; echo "$line" >> "$findings_file") 200>"${findings_file}.lock"
```

The plan's described pattern performs a `yq` merge inside the flock, then an `mv`. This is structurally different: the `yq` merge reads the registry, modifies it, and writes a temp file — all inside the lock. That is correct and is actually stronger than the append-only JSONL pattern. The risk is that if this pattern is not explicitly spelled out in the implementation step, the implementer may cargo-cult the append pattern from `findings-helper.sh`, which is destructive for a YAML file.

**Smallest fix:** Task 3 Step 3 should spell out the atomic swap pattern explicitly as a named block so the implementer cannot miss it:

```bash
(
  flock -x 200
  tmp=$(mktemp "${registry}.XXXXXX")
  yq eval-all '. as $item ireduce ({}; . * $item)' "$registry" <(echo "$update_yaml") > "$tmp"
  mv "$tmp" "$registry"
) 200>"${registry}.lock"
```

The JSONL append (score.sh) and the YAML atomic-swap (registry update) are two different patterns — the plan conflates them in one sentence and relies on the implementer to separate them correctly.

---

### P1-02 — Task 12 (challenger) is in Wave 5 but also depends on Task 5 (registry extension)

**Location:** Task Dependencies diagram, plan lines 748–766

The dependency graph lists Task 12 as depending only on Task 3 (scoring engine), placing it in Wave 5 "after Wave 3." But Task 12 writes `challenger_slots` config to `budget.yaml` and adds a `challenger` tier to `agent-roles.yaml`. The challenger lifecycle script reads `qualified_baseline` from the registry, which is only added in Task 5. If Task 5 is not complete, `fluxbench-challenger.sh` reads a registry schema that does not have `qualified_baseline` and either silently skips the drift baseline comparison or throws a yq null error.

Task 5 is already in Wave 2 ("after Wave 1"), so it completes before Wave 5. But the dependency diagram and wave table do not make this edge explicit — an implementer working in parallel could start Task 12 before Task 5 lands.

**Smallest fix:** Add Task 5 as a dependency of Task 12 in the diagram. Update the Wave 5 entry: "Task 12 (depends on Tasks 3, 5)."

---

### P1-03 — Test code uses `BATS_TEST_FILENAME` but codebase convention is `BATS_TEST_DIRNAME`

**Location:** Task 3 test code, plan lines 269–271

The plan's test `setup()` resolves paths via:

```bash
export SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
export FIXTURES_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/fixtures/qualification" && pwd)"
```

The existing bats test in the codebase (`tests/test_estimate_costs.bats`) uses `BATS_TEST_DIRNAME` directly:

```bash
SCRIPT_DIR="$BATS_TEST_DIRNAME/../scripts"
```

`BATS_TEST_FILENAME` is valid in bats 1.5+ but `$(dirname "$BATS_TEST_FILENAME")` is redundant when `BATS_TEST_DIRNAME` is available and is the established codebase pattern. Using a different variable creates inconsistency that will confuse future maintainers and may fail in older bats installations.

**Smallest fix:** Replace `$(dirname "$BATS_TEST_FILENAME")` with `$BATS_TEST_DIRNAME` in the Task 3 test and in Task 4's calibration test, matching the convention in `tests/test_estimate_costs.bats`.

---

### P1-04 — `fluxbench-qualify.sh` output schema omits `format_compliance_rate`

**Location:** Task 3 Step 3 (score.sh reads `format_compliance_rate`), Task 8 Step 1 (qualify.sh produces the output), plan lines 372 and 582–590

The scorer reads `format_compliance_rate` from the qualification output (plan line 372: "read from `format_compliance_rate` field in qualification output (computed by caller)"). Task 8 describes `fluxbench-qualify.sh` as the caller that "normalizes output to `qualification-output.json` format." But the qualify.sh step does not mention computing or writing `format_compliance_rate` — the word does not appear in Task 8 at all.

`format_compliance_rate` requires evaluating whether each run produced a valid Findings Index header. This computation lives between the raw model output and the scorer — exactly in qualify.sh's normalization step. Without an explicit contract that qualify.sh computes and writes this field, the scorer will read null/missing and either gate-fail every run or silently score format compliance as 0.0.

**Smallest fix:** Task 8 Step 1 must explicitly state that the normalization step evaluates each model output for Findings Index structure (presence of header, pipe-delimited table, verdict line) and writes `format_compliance_rate` as `passed_runs / total_runs` before invoking the scorer.

---

## P2 Findings

### P2-01 — Jaro-Winkler described as the matching algorithm but is not available in the test environment

**Location:** Task 3 Step 3, plan line 369

The plan specifies: "Finding matching: exact location match + jaro-winkler on description (threshold 0.7) using Python helper."

The test environment's `pyproject.toml` lists only `pytest>=8.0` and `pyyaml>=6.0`. Jaro-Winkler requires `jellyfish`, `rapidfuzz`, or `textdistance` — none of which are declared. The existing `flux-drive` spec uses Levenshtein distance < 0.3 for finding deduplication (from `docs/spec/core/synthesis.md` line 60). Choosing a different algorithm for FluxBench scoring than the synthesis spec uses creates two divergent matching strategies for the same concept.

**Smallest fix:** Either (a) use the Levenshtein / keyword-overlap approach already in the synthesis spec (no new dependency, consistent), or (b) add `rapidfuzz` to `pyproject.toml` and justify the algorithm switch in a comment. Option (a) is preferred under the YAGNI principle since Jaro-Winkler offers marginal benefit over keyword overlap for single-sentence finding descriptions.

---

### P2-02 — `fluxbench-sync.sh` performs `git commit` inside a library script

**Location:** Task 6 Step 2, plan lines 531–534

The sync script's described behavior includes:

> "Git adds + commits with message `'chore(fluxbench): sync N FluxBench results'`"

Interflux scripts are designed as library/tool scripts called by an orchestrator (Claude Code session or a schedule hook). Scripts that issue `git add` and `git commit` on the AgMoDB repo assume: (a) the script runs in a context where `AGMODB_REPO_PATH` is set to a valid git working tree, (b) the current git identity is configured for AgMoDB's remote, and (c) no other script is mid-commit. None of these conditions are enforced or tested by the plan.

The existing store-and-forward model in interflux (`findings-helper.sh`, `discover-models.sh`) is deliberately write-to-local-state only; git operations are the orchestrator's responsibility. `fluxbench-sync.sh` breaks this pattern by owning the commit.

**Smallest fix:** Split sync into two responsibilities: (a) write converted AgMoDB-format JSON to `${AGMODB_REPO_PATH}/...` and update `.sync-state` (what the script does), and (b) a separate `git add + commit` step that the orchestrator or a dedicated `fluxbench-push.sh` calls explicitly. This mirrors how `bd sync` is called separately from `git push` in the session protocol.

---

### P2-03 — Task 11 (interrank) is waved after Task 6 (sync) with no actual dependency

**Location:** Task Dependencies diagram, plan lines 756 and 763

The diagram shows Task 11 (interrank TASK_DOMAIN_MAP update) depending on Task 6 (sync). But Task 11 only needs FluxBench benchmark scores to exist in an AgMoDB snapshot — which is an external data dependency, not a code dependency on sync.sh. The actual code dependency for Task 11 is Task 8 (qualify runner) because Task 11 enables interrank to surface FluxBench-qualified models, and those models only enter the registry after qualification runs.

Placing Task 11 in Wave 4 "after Tasks 6, 8" is correct in timing but the diagram edge to Task 6 is misleading. The interrank TypeScript change is purely additive (new entries in `TASK_DOMAIN_MAP`) and can run as soon as the benchmark category string `"fluxbench"` is defined — which happens in Task 1.

**Smallest fix:** Remove the Task 6 → Task 11 edge from the dependency diagram. Mark Task 11 as dependent on Task 1 (metrics config defines the `"fluxbench"` category string). Move it to Wave 2, parallel with Task 3, since it is a purely additive TypeScript change with no runtime dependency on any new script.

---

### P2-04 — Task 9 SessionStart hook calls `recommend_model` MCP — violates zero-cost hook contract

**Location:** Task 9 Step 1, plan lines 609–617

The plan states: "Query interrank `recommend_model` for 'code review agent' (single MCP call, zero-cost)."

MCP calls are not zero-cost in a SessionStart hook. The existing `session-start.sh` is explicitly minimal — it reads local files, sources interbase, and emits a one-line budget signal. It avoids all network calls because a SessionStart hook runs before the user's first message and any latency directly delays the session. An MCP call to interrank requires: loading the interrank snapshot (network fetch on cold start), scoring all models, and returning results. This is 200–800ms of added latency on every session, including sessions that never touch model dispatch.

The awareness goal (surfacing new models not in registry) is valid. The hook is the wrong place for it.

**Smallest fix:** Move the `recommend_model` query out of `session-start.sh` into `fluxbench-discover.md` (Task 10's agent spec) and/or into a `check-compact-drift.sh`-style hook that only runs when `model-registry.yaml` has not been updated in the past `model_discovery.refresh_interval`. The SessionStart hook should only read the registry file to check `requalification_needed` flags — a local file read, not an MCP call.

---

## P3 Findings

### P3-01 — Separate `fluxbench-thresholds.yaml` with 5 fields is unnecessary

**Location:** Task 1 Step 2, Task 4

`fluxbench-thresholds.yaml` contains exactly 5 threshold values that duplicate the `threshold_default` fields already in `fluxbench-metrics.yaml`. The only thing it adds over the defaults file is `source: calibrated` and `calibrated_at`. This creates two files to maintain in sync: when a metric is added to `fluxbench-metrics.yaml`, it must also be added to `fluxbench-thresholds.yaml`. If they drift, the scorer has undefined behavior depending on which file it reads first.

**Smallest fix:** Add a `calibration` block to `fluxbench-metrics.yaml` itself, e.g., `calibration: {source: defaults, calibrated_at: null, overrides: {}}`. Calibration writes only to `overrides`. Scorer merges `threshold_default` with override if present. One file, one schema, no drift.

---

### P3-02 — Task 1 verify commands assume `cd interverse/interflux` but are written without it

**Location:** Task 1 Step 3 verify block, plan lines 164–168

```
- run: `python3 -c "import yaml; d=yaml.safe_load(open('interverse/interflux/config/flux-drive/fluxbench-metrics.yaml')); ..."`
```

The Task 3 verify block uses `cd interverse/interflux && bats ...`, establishing a `cd`-first convention for multi-task verify commands. But Task 1's verify commands open paths as `interverse/interflux/config/...` without a `cd` prefix, which assumes cwd is the monorepo root. This is inconsistent with the codebase's pattern where scripts discover their own location via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`. A reviewer running Task 1 verify from inside `interverse/interflux/` will get "file not found."

**Smallest fix:** Standardize Task 1 verify to match Task 3: either `cd interverse/interflux && python3 -c "... open('config/flux-drive/...')"` or use absolute paths. Pick one form and apply it to Task 4's verify too.

---

## Integration Contract Summary

The three integration seams with the highest cascading failure risk, in order:

1. **qualify.sh → score.sh:** `format_compliance_rate` and `qualification_run_id` must both appear in `qualification-output.json`. Neither is in the test fixtures as written. Any test that does not include these fields will pass during unit testing and fail in end-to-end runs.

2. **score.sh → sync.sh:** The `data/fluxbench-results.jsonl` path mismatch will cause sync.sh to silently read zero records. This will not surface as an error — it will produce an empty AgMoDB commit and mark everything as synced.

3. **score.sh → drift.sh → registry:** The atomic swap pattern on `model-registry.yaml` must be the same in all three scripts. The plan describes it once in Task 3 and relies on Tasks 7 and 8 to replicate it correctly. An explicit shared helper (e.g., a `registry-write.sh` function sourced by all three) would eliminate the risk of one script using append instead of atomic swap.

<!-- flux-drive:complete -->
