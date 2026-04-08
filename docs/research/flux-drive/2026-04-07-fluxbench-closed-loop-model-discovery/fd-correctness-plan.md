---
artifact_type: plan-correctness-review
reviewer: fd-correctness (Julik)
plan: docs/plans/2026-04-07-fluxbench-closed-loop-model-discovery.md
prior_prd_review: docs/research/flux-drive/2026-04-07-fluxbench-closed-loop-model-discovery/fd-correctness.md
bead: sylveste-s3z6
date: 2026-04-07
---

# Plan Correctness Review: FluxBench Implementation Plan

This review targets implementation-level correctness: whether the plan as written is sufficient to produce a correct, race-free system. The PRD design has already been reviewed (see prior review above). The reference invariants from that review are assumed and not re-derived here; only their implementation adequacy is evaluated.

---

## Invariants Carried Forward (from PRD review)

1. `fluxbench-results.jsonl` is append-only and never contains partial or interleaved lines.
2. `model-registry.yaml` has at most one writer at a time; readers see complete old-or-new state.
3. Model status transitions are monotone except for explicit demotion events.
4. Challenger never fills `fd-safety` or `fd-correctness` roles.
5. `fluxbench-sync.sh` is idempotent keyed on `qualification_run_id`.
6. The hysteresis band uses a frozen baseline, not a running average.
7. SessionStart triggers no qualification work.
8. The challenger run counter is append-only between explicit lifecycle events.

---

## Findings Index

| ID | Severity | Task(s) | Title |
|----|----------|---------|-------|
| IP-01 | P0 | Task 3 | `fluxbench-score.sh` flock pattern copied in prose but not enforced in tests — concurrent-write test is vacuous |
| IP-02 | P0 | Tasks 3, 7 | Registry write pattern spec contradicts itself: plan says "flock + atomic swap" but also "yq merge" — yq in-place merge is not atomic |
| IP-03 | P0 | Task 3 | FB-03 (hysteresis baseline ratchet) not addressed — `qualified_baseline: null` remains a copy-alias, not a frozen snapshot |
| IP-04 | P1 | Task 3 | Finding-matching algorithm underspecified: location match semantics, jaro-winkler directionality, and tie-breaking on multi-match are all undefined |
| IP-05 | P1 | Task 3 | Division-by-zero in weighted recall when baseline is empty (`sum(all_weights) == 0`) |
| IP-06 | P1 | Task 3 | `qualification-output.json` schema is consumer-incomplete: `qualification_run_id` field absent, making FB-06 fix impossible |
| IP-07 | P1 | Task 6 | `fluxbench-sync.sh` spec omits dirty-working-directory recovery (FB-10) and partial-commit re-entry path |
| IP-08 | P2 | Task 3 | All-P0 baseline edge case: weighted recall formula returns 1.0 when all found, but P0 auto-fail gate is evaluated in parallel — gate/score output ordering unspecified |
| IP-09 | P2 | Tasks 3, 8 | Empty-findings model output: `false_positive_rate` formula `len(model_only) / len(model_findings)` divides by zero when model produces zero findings |
| IP-10 | P2 | Task 8 | Aggregation rule across fixtures underspecified: "pass all 5 core gates across all fixtures" does not define what score is stored when a model passes some fixtures and fails others |
| IP-11 | P2 | Task 7 | Drift detection `--fleet-check` correlated-drift path writes no JSONL or state audit record — silent suppression of individual demotions is unauditable |
| IP-12 | P3 | Task 3 | Concurrent-write bats test (`score.sh uses flock for JSONL writes`) only checks that a single invocation writes one line — does not test concurrent writers |
| IP-13 | P3 | Task 4 | Calibration `--mock` mode bootstraps thresholds from the same data used to compute them — produces trivially perfect recall scores, not meaningful thresholds |
| IP-14 | P3 | Task 9 | Session-start awareness hook spec still wires `requalification_needed` flag check to session-start.sh — violates Invariant 7 if that flag triggers requalification inline |

---

## Detailed Analysis

### IP-01 (P0): Concurrent-write test is vacuous — flock usage not actually tested

**Task 3**, test `"score.sh uses flock for JSONL writes"`

The test creates one `qual-output.json` and one `baseline.json`, runs one invocation of `fluxbench-score.sh`, and checks that `results.jsonl` has exactly one line. This confirms that a single run writes a line. It does not confirm that concurrent runs do not produce corrupt output.

The PRD review (FB-01) identified the core risk: kernel scheduling between two concurrent writes of the same JSONL produces an interleaved partial line that `jq` cannot parse. The test as specified would pass even if `fluxbench-score.sh` used a bare `echo >> file` with no flock at all.

A valid concurrent-write test requires at minimum:

```bash
@test "score.sh does not corrupt JSONL under concurrent writes" {
    # Launch N parallel invocations against the same results.jsonl
    for i in $(seq 1 10); do
        bash "$SCRIPT_DIR/fluxbench-score.sh" \
            "$TMPDIR_SCORE/qual-output.json" \
            "$TMPDIR_SCORE/baseline.json" \
            "$TMPDIR_SCORE/result-${i}.json" &
    done
    wait
    # Every line must be valid JSON
    invalid=$(jq -c '.' < "$TMPDIR_SCORE/results.jsonl" 2>&1 | grep -c 'parse error' || true)
    [ "$invalid" -eq 0 ]
    # Line count must equal number of successful invocations
    lines=$(wc -l < "$TMPDIR_SCORE/results.jsonl")
    [ "$lines" -eq 10 ]
}
```

Without this test, FB-01 is not covered by the test suite. An implementer writing `echo >> file` passes all five specified tests.

**Corrective fix**: Replace the single-invocation flock test with a parallel-invocation test. Ten concurrent writers is sufficient to expose the race on any reasonably loaded CI machine. Mark this test as requiring `bats --jobs 1` (sequential evaluation) so the 10 subshells actually run in parallel, not serialized by bats itself.

---

### IP-02 (P0): Registry write spec contradicts itself — "yq merge" is not atomic

**Task 3, Task 7** (and implicitly Tasks 5, 8, 12)

The plan's implementation notes say:

> Registry write: `(flock -x 200; ... write .tmp, yq merge, mv .tmp to registry) 200>"${registry}.lock"`

This pattern has a critical error. `yq merge` writes its output to stdout or in-place (with `yq -i`). Neither is compatible with the atomic temp+mv pattern described:

- `yq merge file1 file2 > tmp_file` followed by `mv tmp_file registry` is atomic on POSIX if both are on the same filesystem. This is correct.
- `yq -i 'merge ...' registry` modifies the registry file in-place without atomicity guarantees. This is not safe even under the lock, because `yq -i` writes to a temp file and renames internally, but on some systems and some yq versions the rename is within yq's own temp path — which may be on a different filesystem, causing `mv` to fail or break the lock file's target.

More importantly, the plan does not specify which `yq` variant is meant. The existing codebase uses `yq -r` (Go-based mikefarah/yq) for reading, but the merge syntax for that tool differs from kislyuk/yq (Python). If an implementer uses `yq eval-all 'select(fi==0) * select(fi==1)' file1 file2 > tmp` (mikefarah merge idiom), the output is correct. If they use `yq merge file1 file2` (kislyuk idiom), the behavior differs. The plan's single-line spec `yq merge` is ambiguous between the two tools.

The plan also says flock is used for both the JSONL write and the registry write, but uses two different fd numbers (both `200`). If a script calls both write paths in the same execution context, the second `flock` call on fd 200 will fail or silently succeed (depending on shell), because the same fd is already open. The pattern must use distinct fd numbers: e.g., `201` for the registry lock.

**Corrective fix**: The spec for `fluxbench-score.sh` must state explicitly:
1. Which yq variant is required (mikefarah v4+).
2. The exact merge idiom: `yq eval-all 'select(fi==0) * select(fi==1)' "$registry" "$tmp_update" > "$tmp_registry" && mv "$tmp_registry" "$registry"`.
3. Distinct fd numbers for JSONL lock (`200`) and registry lock (`201`).

Add a `<verify>` step that runs the registry-write path under concurrent invocations and checks YAML validity after all writes complete.

---

### IP-03 (P0): FB-03 not addressed — `qualified_baseline` is a copy-alias, not a frozen snapshot

**Task 5** (Model Registry Schema Extension)

The PRD review identified FB-03 as P0: the hysteresis ratchet allows a model to drift its baseline downward through recovery cycles by updating `finding_recall` as a running field, causing the 15% demotion threshold to be measured against an increasingly lenient baseline.

Task 5's registry schema extension adds:

```yaml
qualified_baseline: null    # Copy of fluxbench scores at qualification
```

This comment says "copy of fluxbench scores at qualification" — which is correct intent. But the plan does not specify:

1. When exactly `qualified_baseline` is written (what event triggers the freeze).
2. Whether `fluxbench-score.sh` is prohibited from updating `qualified_baseline` after initial write.
3. Whether `fluxbench-drift.sh` is required to read from `qualified_baseline` rather than from the live `fluxbench` block.

Without these three constraints, an implementer will reasonably implement `fluxbench-score.sh` as "write results to `fluxbench` block, copy to `qualified_baseline` on promotion" and then assume that subsequent FluxBench runs update both blocks. The ratchet failure from FB-03 materializes immediately.

The drift detection spec (Task 7, Step 2) says "reads a model's `qualified_baseline` from model-registry.yaml" but does not prohibit `fluxbench-score.sh` from overwriting `qualified_baseline`. The two tasks are implemented independently (Tasks 3 and 7 both depend on Task 3 — the scorer — not on each other). There is no shared contract document specifying the field's immutability.

**Corrective fix**: Add an explicit schema rule to Task 5: `qualified_baseline` is written exactly once, during the `qualifying → qualified` transition, and must never be overwritten. Add a `<verify>` check in Task 3 that running `fluxbench-score.sh` against a model that already has a non-null `qualified_baseline` does not modify `qualified_baseline`. This can be a bats test:

```bash
@test "score.sh does not overwrite existing qualified_baseline" {
    # Pre-populate registry with frozen baseline
    echo "frozen_recall: 0.82" > ...
    run bash "$SCRIPT_DIR/fluxbench-score.sh" ... --update-registry ...
    baseline_after=$(yq '.models[0].qualification.qualified_baseline.finding_recall' "$registry")
    [ "$baseline_after" = "0.82" ]
}
```

---

### IP-04 (P1): Finding-matching algorithm underspecified in three dimensions

**Task 3**, implementation note:

> Finding matching: exact location match + jaro-winkler on description (threshold 0.7) using Python helper

Three decisions are left to the implementer with no guidance:

**4a. Location match semantics.** What constitutes an "exact location match"? The ground-truth format uses `"file:line or section reference"` (quoted from the README). Some agents report `"src/api.py:42"`, others `"api.py:42"`, others `"L42"`, others `"line 42"`. The test fixtures use `"file.py:10"` — a format that may not match what the model under test produces if the model uses a different convention. If location match is truly exact string equality, then `"file.py:10"` and `"./file.py:10"` are different findings, producing artificially low recall scores. The plan does not define normalization.

**4b. Jaro-Winkler directionality.** When comparing a model-finding description against a baseline description, which string is the "source" and which is the "target" in the jaro-winkler computation? Jaro-Winkler has a prefix bonus that is asymmetric. A model that paraphrases the description in a different word order may score 0.68 vs the baseline at 0.69 (just above threshold), depending on direction. The threshold of 0.7 is on the boundary where this asymmetry matters.

**4c. Tie-breaking on multi-match.** A model may produce multiple findings that all match the same baseline finding (e.g., it breaks one issue into three sub-issues). The plan does not specify whether each baseline finding can be matched by at most one model finding (greedy bipartite matching) or whether multiple model findings can all "match" the same baseline finding. If the latter, a model that produces 10 re-statements of the same P1 gets 10 recall credits against one baseline finding, inflating its recall score.

**Corrective fix**: The implementation notes for Task 3 must specify:
1. Location normalization: strip leading `./`, normalize line number format to integer-only before comparison.
2. JW direction: always compute `jaro_winkler(model_description, baseline_description)` (model as source, baseline as target). Use the same direction in both recall and severity-accuracy computations.
3. Matching is a maximum-weight bipartite matching: each baseline finding matched to at most one model finding, each model finding to at most one baseline finding. First pass: exact location + JW >= 0.7. Second pass: location-fuzzy (same file, within 5 lines) + JW >= 0.85.

---

### IP-05 (P1): Division by zero in weighted recall when baseline is empty

**Task 3**, scoring formula:

> Severity-weighted recall: `sum(found_weights) / sum(all_weights)` where weights come from `fluxbench-metrics.yaml`

If `baseline.json` contains `"findings": []` (an empty baseline — valid per the schema), then `sum(all_weights) == 0`. The formula divides by zero.

This edge case occurs in the test suite itself: the flock test uses `{"findings":[]}` as the baseline. If the script crashes on this input, the flock test fails with a script error rather than a meaningful assertion, masking the flock behavior the test was meant to verify.

The question of what the correct result is when the baseline is empty is a semantic decision:
- Return `recall = 1.0` (vacuously all baseline findings are found)? This would pass the gate automatically, which seems wrong for qualifying a model.
- Return `recall = null` and mark the run as invalid?
- Return `recall = 0.0` (no findings found, denominator undefined)?

No choice is specified. The test `score.sh uses flock for JSONL writes` will exercise this path, but because it only checks status code and line count, the wrong behavior (crash vs. null vs. 1.0 vs. 0.0) is not caught.

**Corrective fix**: Add a `<verify>` test:

```bash
@test "score.sh handles empty baseline gracefully" {
    # Empty baseline: recall should be defined (not crash), gate result should be explicit
    cat > "$TMPDIR_SCORE/qual-output.json" <<'JSON'
    {"model_slug":"test-model","findings":[{"severity":"P1","location":"f.py:1","description":"issue","category":"correctness"}],"metadata":{...}}
JSON
    cat > "$TMPDIR_SCORE/baseline.json" <<'JSON'
    {"findings":[]}
JSON
    run bash "$SCRIPT_DIR/fluxbench-score.sh" ...
    [ "$status" -eq 0 ]
    recall=$(jq -r '.metrics["fluxbench-finding-recall"]' "$TMPDIR_SCORE/result.json")
    # Must be a number, not null, not NaN
    python3 -c "v=float('$recall'); assert 0.0 <= v <= 1.0"
}
```

Specify in the implementation notes: empty baseline → `recall = 1.0`, gate passes (no baseline findings to miss). This is the vacuous truth convention and is consistent with "if there are no P0 findings in the baseline, the P0 auto-fail gate does not fire."

---

### IP-06 (P1): `qualification-output.json` schema missing `qualification_run_id` — FB-06 fix impossible

**Tasks 3, 6** — the producer/consumer contract

The PRD review (FB-06) identified that idempotency in `fluxbench-sync.sh` relies on `qualification_run_id` uniqueness, and that the generation method must be specified. The implementation plan's Task 3 specifies the `qualification-output.json` schema via test fixture examples:

```json
{"model_slug":"test-model","findings":[...],"metadata":{"agent_type":"checker","baseline_model":"claude-sonnet-4-6","timestamp":"2026-04-07T00:00:00Z"}}
```

No `qualification_run_id` field appears in any fixture example in the plan. The README for the qualification fixtures (`ground-truth.json` schema) also does not include it. Task 6's `fluxbench-sync.sh` spec says "checks `sync_marker` in a `.sync-state` file (keyed on `qualification_run_id`)" — but there is no spec for where that field comes from.

Because Task 3 (scorer) and Task 6 (sync) are implemented by potentially different sub-agents in wave ordering, the contract between them must be in the schema. Without it, the sync script will attempt to read a field that the scorer never wrote, silently producing either a `null` key in `.sync-state` (which matches all null-keyed entries on retry) or a jq error.

**Corrective fix**: Add `qualification_run_id` to the `qualification-output.json` schema in Task 3's spec, with explicit generation instruction: `qualification_run_id` is a UUID v4 generated at the start of each `fluxbench-score.sh` invocation (`uuidgen` or `python3 -c "import uuid; print(uuid.uuid4())"`). Update all test fixture JSON examples to include a `qualification_run_id` field. Add a `<verify>` check that the output JSON has a non-empty `qualification_run_id`.

---

### IP-07 (P1): `fluxbench-sync.sh` spec omits dirty-working-directory recovery

**Task 6**

The Task 6 spec for `fluxbench-sync.sh` describes the happy path: read JSONL, convert, git add, git commit. The PRD review (FB-10) identified the partial-commit recovery path: if the script crashes between "wrote files" and "committed," the AgMoDB working directory has uncommitted changes. On retry, the script will find modified files that match the new output — or may find conflicts if JSONL has new entries since the crash.

The test spec says "missing JSONL handled gracefully" but does not include a test for the dirty-working-directory case. The implementation guidance contains no `git status --porcelain` check and no stash/reset logic.

Furthermore, the `.sync-state` file update (marking entries as synced) is described as happening after the git commit. If the process is killed between commit and `.sync-state` update, the entries are committed to AgMoDB but still appear as "unsent" in `.sync-state`. On next run, the script re-processes them, generating duplicate AgMoDB entries for the same `qualification_run_id`. This violates the idempotency invariant from a different direction than FB-06: the IDs are not duplicated in the JSONL, but the AgMoDB write is duplicated.

**Corrective fix**: Add to Task 6's spec:
1. At startup, check `git -C "$AGMODB_REPO_PATH" status --porcelain`. If output is non-empty, either abort with error (safe) or stash + re-apply with warning (recovery).
2. Update `.sync-state` before the git commit, not after. If the commit fails, remove the `.sync-state` entries added in this run (rollback). This ensures the state file never advances ahead of the actual commit.
3. Add a bats test: create a dirty AgMoDB working directory, verify the script detects it and exits non-zero without corrupting state.

---

### IP-08 (P2): All-P0 baseline edge case — gate/score evaluation order unspecified

**Task 3**

Consider a baseline with 3 findings, all P0 (weights 4, 4, 4 = total 12). The model under test finds all 3. Weighted recall = 12/12 = 1.0. Gate passes. P0 auto-fail does not fire. This is correct behavior.

Now consider: baseline has 2 P0 findings, model finds both but also produces 5 additional findings not in the baseline. False-positive rate = 5/7 = 0.714. The FP gate (threshold 0.20) fails. What does the output JSON look like?

The plan specifies that the scoring engine "writes result JSON to output path" and "evaluates 5 core gate pass/fail decisions" but does not specify the structure when some gates pass and others fail. Specifically:

- Is there a single top-level `qualified: true|false` field that ORs all gate results?
- Or does the consumer read each gate individually and decide?

The `qualification-output.json` schema must include both the per-gate results AND a top-level qualification verdict. If it does not, `fluxbench-qualify.sh` (Task 8) which "aggregates results: pass all 5 core gates → promote to `auto-qualified`" must re-compute the conjunction itself, duplicating the gate logic.

The P0 auto-fail case is a special variant: a model with weighted recall 0.62 (above the 0.60 threshold) but missing one P0 should appear as `gate_passed: false` on the finding-recall gate even though the numeric score cleared the threshold. The test `score.sh auto-fails when P0 finding missed` checks this, but the plan does not specify whether `metrics["fluxbench-finding-recall"]` should return 0.62 (the numeric score) or 0.0 (indicating auto-fail) or the numeric score with a separate `p0_auto_fail: true` flag. The test checks for `p0_auto_fail: true` in `gate_results` — but the test for weighted recall correctness reads `.metrics["fluxbench-finding-recall"]`. These are two different fields. The plan never specifies what happens to `.metrics["fluxbench-finding-recall"]` in the P0 auto-fail case.

**Corrective fix**: The `result.json` schema must specify:
```json
{
  "qualification_run_id": "...",
  "model_slug": "...",
  "metrics": { "fluxbench-finding-recall": 0.62, ... },  // always numeric score
  "gate_results": {
    "fluxbench-finding-recall": {"passed": false, "p0_auto_fail": true, "score": 0.62, "threshold": 0.60}
  },
  "qualified": false,  // conjunction of all gate_results.passed
  "auto_fail_reason": "missing_p0"  // present only when p0_auto_fail fires
}
```
Add a test that verifies the numeric score is preserved even in the P0 auto-fail case.

---

### IP-09 (P2): False-positive rate divides by zero when model produces empty findings

**Task 3**, implementation note:

> False positive rate: `len(model_only) / len(model_findings)` where `model_only` is findings not in baseline

If the model produces zero findings (`"findings": []`), then `len(model_findings) == 0` and the formula divides by zero. The correct semantic is: a model that produces no findings has a false-positive rate of 0.0 (no false positives, since there are no positives at all). However, this is also the degenerate case for gaming the metric — a model that suppresses all output trivially achieves the lowest possible FP rate while achieving zero recall.

The plan does not specify how to handle this. There is no test case for a model that produces zero findings. The empty-findings case should also interact with the P0 auto-fail gate (if baseline has P0 findings, a model producing no findings must auto-fail regardless of FP rate).

**Corrective fix**: Add the following to the implementation notes for `fluxbench-score.sh`:
- Empty model findings: `false_positive_rate = 0.0` (not a division error), gate passes on FP metric.
- But: if baseline has any findings, the finding-recall gate fails (0.0 recall < 0.60 threshold).
- If baseline has any P0, the P0 auto-fail fires.
Add a bats test covering the zero-findings case.

---

### IP-10 (P2): Aggregation rule across fixtures undefined for partial-pass models

**Task 8** (Qualification Runner)

Task 8 states: "Aggregates results: pass all 5 core gates across all fixtures → promote to `auto-qualified`."

"Pass all 5 core gates across all fixtures" is ambiguous. It could mean:
- (A) For each fixture individually, all 5 gates pass. Every fixture must be a clean pass. → Model that passes 4/5 fixtures is rejected.
- (B) The aggregate score across all fixtures (mean of per-fixture scores) must clear each gate threshold. → A model can fail 2 of 5 fixtures if it aces the others.
- (C) Each gate is evaluated per-fixture; the per-gate pass requires passing on >= 80% of fixtures. → Some tolerance for fixture-specific noise.

Interpretation A is the strictest. Interpretation C matches the calibration script's p25 threshold derivation (which implies there is expected variance across fixtures). The plan says "runs model against all fixtures" and then "pass all 5 core gates across all fixtures" — the word "across" suggests aggregation (B or C), not per-fixture AND (A).

The `fluxbench-qualify.sh` script decides whether to promote a model based on this rule. If the rule is ambiguous, two implementations will produce different results for borderline models.

What score is written to `model-registry.yaml`? If interpretation B is used and the model's mean finding-recall is 0.62 (above 0.60), that is what gets stored. But if one fixture had finding-recall of 0.45 (below threshold), should that fixture's result be stored separately or merged? The `qualified_baseline` field would then be an aggregate, not a per-fixture breakdown.

**Corrective fix**: Task 8 must specify explicitly:
- Qualification requires all 5 gates to pass on >= 4 of 5 fixtures (minimum 80% fixture pass rate per gate). One fixture failure is tolerated to account for annotation noise.
- The score stored in the registry is the mean across passing fixtures (not all fixtures). This prevents a single bad fixture from anchoring the stored baseline too low.
- Add a bats test: model passes 4/5 fixtures, fails 1 → should qualify. Model fails 2/5 → should not qualify.

---

### IP-11 (P2): Correlated drift suppression creates unauditable silent demotion suppression

**Task 7** (Drift Detection)

Task 7's Step 2 specifies: "If called with `--fleet-check`, counts models with drift flags. If >=50%, outputs `baseline_shift_suspected` instead of demoting."

This is the correlated drift / baseline shift detection from the PRD. The correctness concern is: when `baseline_shift_suspected` is emitted, individual model demotions are suppressed. This suppression leaves no trace unless:
1. The `fluxbench-results.jsonl` records the suppression decision, or
2. The model-registry records a `drift_suppressed_at` field, or
3. Some other audit trail exists.

The plan specifies no audit record for this case. The test spec says "correlated drift (>=50% models) triggers baseline-shift alert instead of mass-demotion" — which tests the alert is emitted but not that the suppression is recorded for later reconciliation.

Without an audit trail, a baseline shift event is invisible to the weekly reconciliation cycle. The next week, the fleet check may no longer show correlated drift (because the baseline shifted and models now appear healthy), but none of the suppressed individual demotion events are revisited. Models that individually drifted remain in `active` state indefinitely.

**Corrective fix**: Task 7 must specify that `baseline_shift_suspected` events write a JSONL record to `fluxbench-results.jsonl` with `event_type: "fleet_drift_suppression"`, listing which model IDs had their demotion suppressed and the correlated metric drops. The weekly agent (Task 10) should check for unresolved `fleet_drift_suppression` events and present them to the operator for manual review.

---

### IP-12 (P3): Concurrency bats test structure serializes workers via bats job control

**Task 3**, test `"score.sh uses flock for JSONL writes"`

Even if the concurrent-write test from IP-01 is added, the default bats execution model runs tests sequentially in a single process. Background `&` within a `@test` block does create parallel processes, but if bats is invoked with `--jobs 1` (the default) the test runner itself is single-threaded. The `wait` call in the test will still work correctly, but the test's effectiveness depends on the OS scheduling parallel processes fast enough to produce actual interleaving.

On a loaded CI machine this works. On a lightly loaded developer machine the 10 parallel processes may all write sequentially without interleaving, giving a false-pass. The test should add a `sleep 0.01` inside the loop body before the main write to increase interleaving probability, or use a barrier (all start at the same moment via a tempfile signal).

**Corrective fix**: Low urgency. The fix from IP-01 (adding the concurrent test at all) is the priority. Once the test exists, mark it with `# @concurrent-stress` and run it under stress in CI with `stress-ng` or `fio` to simulate disk contention.

---

### IP-13 (P3): Calibration `--mock` mode produces trivially perfect scores — not meaningful thresholds

**Task 4** (Calibration Script)

Task 4's `--mock` flag "uses pre-computed ground-truth as model output (for testing without Claude API)." This means the scoring engine is given ground-truth as both the model output and the baseline. Weighted recall = 1.0, FP rate = 0.0, severity accuracy = 1.0 for every fixture.

The calibration script then takes p25 of these scores as thresholds. p25 of [1.0, 1.0, 1.0, 1.0, 1.0] = 1.0. This means `--mock` calibration produces thresholds of `finding_recall: 1.0` — a threshold no real model can clear. Running `fluxbench-score.sh` against `fluxbench-thresholds.yaml` written by `--mock` calibration would fail every model on every metric.

The test spec checks that `--mock` writes a file with `source: calibrated` and 5 threshold entries. It does not check that the threshold values are sensible. This means the calibration CI test passes while producing a thresholds file that would break all downstream qualification runs.

**Corrective fix**: The `--mock` mode should not use ground-truth as the model output. Instead, it should use a pre-generated "imperfect model" fixture — a version of the ground-truth with some findings intentionally removed or severity-shifted. This simulates a real model response (less than perfect) and produces meaningful threshold values. Add a `verify` step that checks the calibrated thresholds are below 1.0 for all metrics.

---

### IP-14 (P3): Session-start awareness hook spec still wires inline requalification check

**Task 9** (SessionStart Awareness Hook)

Task 9's Step 1 says: "Check active models for `requalification_needed` flag — if set, print advisory."

This is correct — print an advisory, do not trigger requalification. The `<verify>` step checks that `grep -c 'requalification_needed\|recommend_model' session-start.sh` returns 2 occurrences. This only verifies the string is present, not that it does not trigger work.

The risk: an implementer reads "check for `requalification_needed` flag" and writes:

```bash
if yq ... requalification_needed; then
    bash scripts/fluxbench-qualify.sh "$model_slug" &  # "background, so zero-cost"
fi
```

The `&` makes it non-blocking but not zero-cost. This violates Invariant 7 (no qualification work at session start) and the FB-05 finding from the PRD review.

The `<verify>` grep check would still pass (the string `requalification_needed` is present). The hook would still print an advisory. But it would also launch background qualification, consuming tokens and triggering JSONL/registry writes from the session-start hook.

**Corrective fix**: Task 9's spec must add a `<verify>` check that session-start.sh does not contain any invocation of `fluxbench-qualify.sh` or `fluxbench-score.sh`:

```bash
- run: `grep -c 'fluxbench-qualify\|fluxbench-score' interverse/interflux/hooks/session-start.sh || echo 0`
  expect: contains "0"
```

---

## Cross-Cutting Assessment

### Are the P0 bugs from the PRD review adequately addressed?

**FB-01 (JSONL concurrent writes):** Partially addressed. The plan says "use flock" in the implementation notes. But as IP-01 shows, the test suite does not enforce this. An implementer can pass all tests without using flock. The flock requirement must be enforced by a concurrent-write test, not just stated in prose.

**FB-02 (registry TOCTOU):** Not adequately addressed. The plan says "flock + atomic swap" in one sentence but does not specify the exact yq idiom, the lock fd to use, or how to test it. IP-02 shows the spec contradicts itself on atomic swap vs. yq merge. No test covers concurrent registry writes.

**FB-03 (hysteresis baseline ratchet):** Not addressed. Task 5 adds `qualified_baseline: null` with a comment but no immutability contract, no enforcement in Task 3's scorer, and no test.

### Is the finding-matching algorithm specified precisely enough to implement?

No. Three decisions are left open (location normalization, JW directionality, bipartite matching vs. many-to-one). Two implementations following the plan could produce recall scores differing by 10-15 percentage points for the same model output against the same baseline. This would make fixture-based qualification non-reproducible.

### Are the JSONL/YAML write patterns correctly specified with flock?

The JSONL pattern is correctly described in prose and the lock file convention is established. The YAML pattern has a contradiction (IP-02) and the fd number collision risk. Neither has concurrent-write test coverage.

### Are there edge cases in the scoring math?

Three division-by-zero cases identified (IP-05: empty baseline; IP-09: empty model output; IP-08: all-P0 baseline interacting with gate/score ordering). The all-P0 baseline case is handled correctly if the P0 auto-fail gate is checked first, but the plan does not specify evaluation order.

### Is the `qualification-output.json` schema complete enough for all consumers?

No. The `qualification_run_id` field is absent (IP-06), making the sync idempotency fix from FB-06 impossible to implement correctly without inventing a convention that the scorer and syncer must independently agree on. A top-level `qualified: bool` field and `auto_fail_reason` are also absent, forcing `fluxbench-qualify.sh` to re-implement gate conjunction logic.

---

## Recommended Minimum Fixes Before Implementation Begins

These are changes to the plan itself (not the code), ordered by severity:

1. **IP-03**: Add immutability contract for `qualified_baseline` to Task 5 and a test in Task 3 that verifies the scorer does not overwrite an existing baseline.

2. **IP-06**: Add `qualification_run_id: <uuidv4>` to all `qualification-output.json` schema examples in Task 3 and the ground-truth README.

3. **IP-04**: Add a three-point matching spec (location normalization, JW direction, bipartite matching) to Task 3's implementation notes.

4. **IP-01/IP-02**: Replace the single-invocation flock test with a concurrent-write test; fix the yq merge idiom spec and fd-number collision.

5. **IP-05/IP-09**: Add two explicit tests for empty-baseline and empty-findings edge cases.

6. **IP-07**: Add dirty-working-directory recovery spec to Task 6.

7. **IP-10**: Clarify the aggregation rule (recommend: pass >= 4 of 5 fixtures per gate).

<!-- flux-drive:complete -->
