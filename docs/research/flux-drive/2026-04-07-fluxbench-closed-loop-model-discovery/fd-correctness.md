---
artifact_type: correctness-review
reviewer: fd-correctness (Julik)
prd: docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md
bead: sylveste-s3z6
date: 2026-04-07
---

# Correctness Review: FluxBench Closed-Loop Model Discovery

## Invariants Established Before Analysis

These must hold at all times, derived from the PRD and existing interflux/interrank contracts:

1. **JSONL append-only integrity**: `data/fluxbench-results.jsonl` must never contain partial or interleaved JSON lines. A corrupt line silently poisons all downstream consumers (drift detection, sync).
2. **model-registry.yaml single-writer**: At any moment, at most one process may be writing `model-registry.yaml`. Reads during a write must see either the complete old state or the complete new state — never a partial update.
3. **Drift detection monotonicity**: A model's status may only move forward on the state machine (`qualifying → qualified → active`) or backward via an explicit demotion event (`active → qualifying`). It must never skip states, move backward silently, or oscillate between two states on repeated evaluation of the same sample.
4. **Challenger safety floor**: The challenger slot must never be assigned to `fd-safety` or `fd-correctness`, regardless of registry state, config, or code path. This is a non-negotiable invariant from the PRD and existing agent-roles.yaml.
5. **Idempotent sync**: Running `fluxbench-sync.sh` N times against the same JSONL must produce the same AgMoDB commit state as running it once. Duplicate `qualification_run_id` entries must be detected and rejected.
6. **Drift hysteresis stability**: Once a model is demoted (>15% drop), it must not be re-promoted until it clears the 5% recovery band. The evaluation path that sets "demoted" and the path that clears it must read the same baseline figure.
7. **Zero-cost session start**: The F5 SessionStart hook must not trigger qualification work. The PRD states this explicitly: "single MCP query, no qualification work in session startup."
8. **Challenger accumulation consistency**: The challenger's accumulated real-review FluxBench metrics must be append-only. The counter used for the "10+ runs" promotion gate must not be reset except by an explicit promotion or rejection event.

---

## Findings Index

| ID | Severity | Feature | Title |
|----|----------|---------|-------|
| FB-01 | P0 | F1/F3/F4 | JSONL append without lock — concurrent qualification runs corrupt `fluxbench-results.jsonl` |
| FB-02 | P0 | F4 | Drift detection TOCTOU — `model-registry.yaml` read-modify-write without atomic swap |
| FB-03 | P0 | F4 | Hysteresis baseline drift — demote and clear thresholds computed from different snapshots |
| FB-04 | P1 | F7 | Challenger promotion gate raceable — 10-run counter and promotion decision are separate reads |
| FB-05 | P1 | F5/F4 | SessionStart version-trigger requalification is not zero-cost if multiple models have stale dates |
| FB-06 | P1 | F3 | Store-and-forward sync idempotency relies on `qualification_run_id` uniqueness with no generation contract |
| FB-07 | P1 | F7 | Challenger safety-floor bypass via registry state: a model in `qualifying` can be promoted to challenger before the safety role exclusion is enforced at dispatch |
| FB-08 | P2 | F4 | Drift sample counter shared across sessions — `2*N` gap guarantee unenforceable without persistent atomic counter |
| FB-09 | P2 | F1 | Auto-fail on missing P0 and weighted scoring are computed independently — a model can pass gates with stale P0 results if scoring and gate check read different baselines |
| FB-10 | P2 | F3/F6 | AgMoDB commit path has no integrity check — partial fluxbench-sync.sh runs leave registry in indeterminate sync state |
| FB-11 | P3 | F5 | Weekly scheduled auto-qualification re-runs candidates that are already `qualified` if registry not updated before next cycle |
| FB-12 | P3 | F4 | `releaseDate` version comparison on SessionStart reads interrank snapshot which may lag — false-positive requalifications |

---

## Detailed Analysis

### FB-01 (P0): JSONL append without lock — concurrent qualification runs corrupt `fluxbench-results.jsonl`

**Affected features**: F1 (fluxbench-score.sh), F3 (fluxbench-sync.sh), F4 (drift detection)

The PRD specifies that FluxBench results are written to `data/fluxbench-results.jsonl` as append-only. The existing `findings-helper.sh` correctly wraps its writes in `flock`:

```bash
(
  flock -x 200
  echo "$line" >> "$findings_file"
) 200>"${findings_file}.lock"
```

However, `fluxbench-score.sh` and `fluxbench-qualify.sh` are described as shell scripts that "write results to JSONL." There is no specification or design note requiring these new scripts to use `flock` or any equivalent serialization mechanism. The PRD's acceptance criteria for F1 say only "Results written to `data/fluxbench-results.jsonl` (append-only)." The word "append-only" is a data-shape constraint, not a concurrency constraint — it would be easy for an implementer to use a bare `echo >> file` and satisfy the acceptance criterion while still being unsafe.

**Concrete failure interleaving:**

1. `fluxbench-score.sh` (run A, deepseek) opens the JSONL file and is mid-write of a 600-byte JSON line.
2. The kernel schedules out run A after writing 300 bytes.
3. `fluxbench-qualify.sh` (weekly agent, qwen-3.1) opens the same file and appends a complete 580-byte line.
4. Run A resumes and appends the remaining 300 bytes.

Result: line 2 in the JSONL is valid JSON. Line 3 is the second half of run A's result, which is not valid JSON. `fluxbench-sync.sh` reads the file with `jq`, hits a parse error on line 3, and either silently drops the record or aborts. If it aborts, the idempotent key `qualification_run_id` for run A is never committed to AgMoDB. Run A's result is lost.

There is a second variant: the F7 challenger accumulation path (each real review updates challenger metrics in the JSONL). If this happens during a scheduled weekly qualification run, the corruption window is open throughout the entire qualification run, which may span many minutes.

**Corrective fix**: The `write` subcommand of `findings-helper.sh` already has the correct pattern. The acceptance criteria for F1 should explicitly require that `fluxbench-score.sh` and `fluxbench-qualify.sh` call `findings-helper.sh write` (or its equivalent flock-protected path) rather than appending directly. Alternatively, add a `fluxbench-append` wrapper function that enforces the lock. The lock file convention (`${jsonl_file}.lock`) is already established — reuse it consistently.

---

### FB-02 (P0): Drift detection TOCTOU — `model-registry.yaml` read-modify-write without atomic swap

**Affected features**: F4 (drift detection), F5 (proactive surfacing), F7 (challenger promotion)

`model-registry.yaml` is described as "updated with FluxBench scores on qualification" (F1), compared against interrank snapshot on SessionStart (F5), and mutated by drift events (F4) and challenger promotion (F7). All of these are read-modify-write operations. There is no locking or atomic-swap mechanism mentioned in the PRD for this file.

YAML files cannot be atomically appended. A safe write requires: read → modify in memory → write to temp file → `mv` temp → original (atomic on POSIX for files in the same directory). The PRD does not specify this pattern anywhere. The existing `discover-models.sh` reads the registry with `yq` and the PRD describes fluxbench-score.sh updating the registry after each run — both without any mention of a lock.

**Concrete failure interleaving:**

1. Weekly `fluxbench-qualify.sh` reads `model-registry.yaml` to write `format_compliance: 0.97` for deepseek.
2. Simultaneously, a session's drift detection reads `model-registry.yaml` to compare `finding_recall: 0.71` against the baseline.
3. `fluxbench-qualify.sh` writes its temp file and `mv`s it into place, atomically replacing the registry.
4. Drift detection's read was from the old file — it computes a drift ratio against stale baseline values.
5. Drift detection writes its own demotion update back to the same file, using the stale baseline.

The demotion in step 5 is based on a stale comparison. The model may be incorrectly demoted (or failure to demote when it should). Because the drift detection uses the qualified baseline as its reference point, and that baseline was just updated in step 3, the demoted model now has a new baseline that the hysteresis check in the next cycle will read — leading to asymmetric state.

**Corrective fix**: Serialize all writes to `model-registry.yaml` through a lock file (e.g., `model-registry.yaml.lock`) with `flock`. Each writer: acquire lock → read current state → modify → write atomically via temp+mv → release lock. The SessionStart hook's read-only path does not need the lock for correctness (reads see a consistent file after mv), but the write paths in `fluxbench-score.sh`, `fluxbench-drift.sh`, and `fluxbench-qualify.sh` all must.

---

### FB-03 (P0): Hysteresis baseline drift — demote and clear thresholds computed from different snapshots

**Affected feature**: F4 (drift detection)

The PRD specifies:
- Drift flag: "any core metric drops >15% from qualified baseline → model demoted to `qualifying`"
- Drift clear: "clear only when recovered to within 5% of baseline (prevents oscillation)"

This design requires that both the demote check and the clear check use the **same** baseline figure — the value stored in `model-registry.yaml` at the time of initial qualification (`qualified_date`). However, the PRD's acceptance criteria do not specify:

1. Whether the baseline is frozen at qualification time and stored separately, or whether it is read from the current `qualification` block on each check.
2. What happens to the baseline when a previously-demoted model runs new shadow runs that improve its scores.

**Concrete oscillation scenario:**

1. Model qualifies at `finding_recall: 0.82`. Baseline = 0.82.
2. Drift detection fires: current sample = 0.69. Drop = 16%. Model demoted.
3. Model runs new shadow samples. Running average rises to 0.78. Drift check: 0.78 vs 0.82. Drop = 4.9%. Within 5% band. Model cleared. ← Correct so far.
4. But: if `fluxbench-qualify.sh` updated `finding_recall` to the running average (0.78) when it wrote results, the baseline used for the next demotion check is now 0.78, not the original 0.82. The model effectively moved its own goalposts.
5. Next drift sample: 0.68. Drop from 0.78 = 12.8%. Below the 15% threshold. **Model is NOT demoted** even though it is at 0.68 vs the original qualification of 0.82.

This is a silent integrity failure: the baseline shifts downward with each recovery cycle, making demotion progressively harder to trigger. The model can ratchet down from 0.82 to 0.68 in small steps, never crossing the 15% threshold from its current baseline.

The PRD says "clear only when recovered to within 5% of baseline (prevents oscillation)" but does not prevent baseline drift. The two are different failure modes.

**Corrective fix**: Store the qualification baseline as a **frozen** field in `model-registry.yaml` separate from the running averages — e.g., `qualification.baseline_finding_recall`, `qualification.baseline_format_compliance`, etc. Both the demote check and the clear check must read only from the frozen baseline fields, never from the running fields that `fluxbench-score.sh` updates. The frozen baseline is written exactly once: when `status` transitions from `qualifying` to `qualified`.

---

### FB-04 (P1): Challenger promotion gate raceable — counter and promotion decision are separate reads

**Affected feature**: F7 (challenger slot)

The PRD states: "After 10+ challenger runs: auto-evaluate qualification gate — promote or reject." The counter accumulates from real reviews, which run concurrently (parallel agent dispatch, multiple sessions). The counter lives in `model-registry.yaml` under the challenger entry.

The read-modify-write problem from FB-02 applies here acutely: the promotion decision sequence is:

1. Read challenger's `shadow_runs` counter from registry.
2. Check if >= 10.
3. Run qualification evaluation.
4. Write promotion/rejection result to registry.

Between steps 1 and 4, another session may also read `shadow_runs == 10`, also decide to promote, and also write a promotion result. Result: the qualification evaluation runs twice for the same model, and if the two evaluations race on different (but overlapping) sets of real-review samples, they may produce different promote/reject decisions. One session promotes, one rejects — last writer wins, or both promote (duplicate `qualified` entry).

**Concrete failure**: Session A and Session B both complete their 10th challenger review within the same minute. Both read `shadow_runs: 10`, both trigger the qualification evaluation. Session A scores the model at 0.63 on finding_recall (borderline fail). Session B scores it at 0.64 (borderline pass, uses slightly different sample set). Session B writes `status: qualified`. Session A writes `status: candidate` (rejected). Last write wins. The model's fate depends on which write arrives last, not on the aggregate evidence.

**Corrective fix**: The promotion evaluation must be protected by the same lock as registry writes (from FB-02). Additionally, the promotion decision should be atomic: read counter, check threshold, and write promotion in a single locked transaction. A sentinel field like `challenger_evaluation_in_progress: true` written under the lock can prevent double-evaluation.

---

### FB-05 (P1): SessionStart version-trigger is not zero-cost when multiple models have stale `qualified_date`

**Affected feature**: F5 (proactive surfacing), F4 (drift detection — version trigger)

The PRD states F5's SessionStart hook is "zero-cost: single MCP query, no qualification work in session startup." However, the F4 version-trigger behavior says: "on SessionStart, compare active models' `qualified_date` against interrank snapshot `releaseDate` — version bump → trigger full requalification."

These two features share the same hook entry point (`hooks/session-start.sh`). The PRD does not make clear whether the version comparison is part of the "zero-cost" F5 path or is a separate F4 trigger. If it is the F4 trigger, and if three active models all have stale `qualified_date` values (e.g., after a major interrank snapshot refresh), then three full requalifications are triggered simultaneously at session start.

A full requalification runs against all F2 fixtures (5+ documents), invokes `fluxbench-score.sh` for each, writes JSONL, and updates the registry. Even if dispatched as background processes, they saturate the JSONL write path and registry write path simultaneously. The "zero-cost" guarantee is violated.

More critically: if requalification is triggered in the background without blocking session start, the session proceeds with models that may be concurrently mid-requalification — their registry entries are being written under the processes spawned by the hook. If the session dispatches one of those models (as active), it may be using a model whose status is flipping from `qualified` to `qualifying` in the background.

**Corrective fix**: Separate the "awareness" signal (zero-cost, F5) from the "trigger requalification" action (costly, F4). The version trigger should create a bead (or set a flag file) and exit, never triggering actual requalification inline during session start. A subsequent explicit `/interflux:requalify` command or the weekly scheduled agent handles the actual work. This matches the PRD's own separation of "awareness" vs "action" modes.

---

### FB-06 (P1): Idempotency relies on `qualification_run_id` uniqueness with no generation contract

**Affected feature**: F3 (store-and-forward sync)

The PRD states the sync script is idempotent "keyed on `qualification_run_id`." The idempotency guarantee is only as strong as the uniqueness guarantee on `qualification_run_id`. The PRD does not specify how this ID is generated.

If `fluxbench-score.sh` generates the ID as a timestamp (`date +%s`), two concurrent qualification runs within the same second share an ID. The sync script's dedup logic then silently drops one of them — the wrong record survives (whichever arrived in the JSONL first), but both runs believed their results were committed.

If the ID is generated as a hash of (model_id, fixture_file, timestamp), two runs of the same model against the same fixture in rapid succession (e.g., the weekly agent and a manual re-run) produce the same ID. One result is silently dropped.

There is also a recovery scenario: if `fluxbench-sync.sh` crashes mid-commit, on retry it re-processes the same JSONL entries. The idempotency check must account for the fact that AgMoDB may have received a partial commit — some entries from the same JSONL batch may be present, others absent. The PRD's acceptance criterion only says "re-running doesn't duplicate entries" — it does not address the partial-commit recovery path.

**Corrective fix**: Generate `qualification_run_id` as a UUID v4 at the start of each `fluxbench-score.sh` invocation, written as the first field before any results. Make the generation method explicit in the acceptance criteria. For partial-commit recovery, `fluxbench-sync.sh` should read the AgMoDB committed-IDs manifest before determining which JSONL records are unsent.

---

### FB-07 (P1): Challenger safety-floor bypass via registry state

**Affected feature**: F7 (challenger slot), agent-roles.yaml safety constraint

The PRD states: "Safety: challenger never assigned to `fd-safety` or `fd-correctness` roles (safety floor constraint)." This constraint must be enforced at dispatch time, not just at registry write time.

The challenger slot logic selects the "highest-FluxBench-scoring `qualifying` model." The safety-role exclusion is stated as a property of the challenger slot allocation. However, there are two enforcement points that could diverge:

1. **At allocation time** (triage picks the challenger): The triage logic must know which agent slots are safety-critical. If it checks only the challenger model's `eligible_tiers` field in the registry (e.g., `eligible_tiers: [checker, analytical]`), a model whose `eligible_tiers` does not include `reviewer` would not normally be dispatched to `fd-safety`. But the PRD does not explicitly require that `eligible_tiers` be consulted when picking the challenger's **target role** — it says the challenger "runs alongside qualified agents in actual reviews."

2. **At dispatch time** (lib-routing.sh safety floor): The existing `min_model: sonnet` floor for `fd-correctness` and `fd-safety` is enforced in `lib-routing.sh`. But this is a model-tier floor, not a model-identity exclusion. A challenger model on an eligible tier (sonnet or higher) could still be dispatched to a safety role if the allocation step does not check the role exclusion.

The gap: if the challenger is allocated to fill a role vacancy in a review and the triage code does not explicitly check "is this role in the safety-excluded list before assigning the challenger," the safety floor from agent-roles.yaml does not save you — that floor governs model tier, not which model is dispatched.

**Corrective fix**: The acceptance criterion for F7 should specify that the safety exclusion is enforced at **allocation**, not just at dispatch. The triage code must maintain a hardcoded exclusion list `CHALLENGER_EXCLUDED_ROLES = [fd-safety, fd-correctness]` checked before any challenger assignment. This list should match `budget.yaml → exempt_agents`.

---

### FB-08 (P2): Drift sample counter is session-local without persistent atomic state

**Affected feature**: F4 (drift detection — sample-based trigger)

The PRD specifies: "every Nth review, shadow-run 1 active non-Claude agent against Claude baseline" with "force shadow if model unsampled in 2*N reviews." This requires a persistent counter of how many reviews have occurred since the last shadow run for each active model.

The PRD does not specify where this counter lives. If it lives in a session-local variable or a temp file, it resets every session. A model could remain unsampled indefinitely: each new session starts its counter at 0, and if each session runs fewer than N reviews, the counter never reaches N.

The `2*N` gap guarantee ("force shadow if model unsampled in 2*N reviews") is also unenforceable without a persistent, process-safe counter. The most natural place for this counter is `model-registry.yaml` (as `last_sampled_review_index` or similar), but writing it on every review incurs the same TOCTOU risk as FB-02, and the write would happen inside a live review session (performance concern).

**Corrective fix**: Store the drift sample counter in a small separate state file (e.g., `data/drift-state.yaml`) keyed by model_id. Protect it with the same flock pattern. The counter records: `last_sampled_at` (timestamp), `reviews_since_last_sample` (counter incremented per review, reset on shadow run). This separates the high-write drift state from the less-frequently-written registry.

---

### FB-09 (P2): P0 auto-fail and weighted scoring operate on potentially inconsistent data

**Affected feature**: F1 (FluxBench scoring engine)

The PRD specifies two scoring rules:
- "Missing any P0 auto-fails regardless of aggregate"
- "Weighted recall uses P0=4x, P1=2x, P2=1x, P3=0.5x"

These two rules must be computed from the same set of ground-truth P0 findings. If `fluxbench-score.sh` reads the ground-truth baseline at two different points (e.g., once to check for P0 presence, once to compute the weighted recall), and the fixture directory is modified between those reads (e.g., a human is updating a ground-truth.json during a calibration run), the two computations use different data.

More concretely: the auto-fail check is a binary gate that should be evaluated before the weighted score is finalized. If the logic evaluates weighted score first and then applies the P0 gate as a post-hoc override, a model could appear to "nearly pass" (high weighted score) in logs while actually having auto-failed — misleading calibration data in the JSONL.

**Corrective fix**: The acceptance criteria should specify execution order: (1) load ground-truth once into a single data structure, (2) evaluate P0 gate (binary, can short-circuit immediately), (3) if P0 gate fails, write result with `auto_fail: true` and skip weighted scoring entirely. This ensures log entries are unambiguous and the gate and score are always consistent.

---

### FB-10 (P2): Partial fluxbench-sync.sh run leaves registry in indeterminate sync state

**Affected feature**: F3 (AgMoDB write-back), F6 (interrank integration)

`fluxbench-sync.sh` reads the JSONL, writes to AgMoDB repo format, and commits. If the script crashes between "wrote files" and "committed," the AgMoDB working directory has uncommitted changes. The next run of `fluxbench-sync.sh` will find:
- Uncommitted changes in the AgMoDB repo
- The JSONL still has all entries marked as "unsent" (since no commit was made)
- Re-processing will regenerate the same files, which may or may not be identical to the partial write

If the crash left a partially-written file in the AgMoDB working directory, `git status` will show it as modified. The sync script must handle this state explicitly — either stash, reset, or verify the working directory is clean before generating new files.

The PRD's acceptance criterion only states "re-running doesn't duplicate entries." It does not state what happens to a dirty working directory. This is a gap that will surface in production when network failures or process kills occur mid-commit.

**Corrective fix**: At startup, `fluxbench-sync.sh` should check `git status --porcelain` in the AgMoDB repo. If uncommitted changes exist from a previous run, either `git stash` them or verify they match the expected output for the same `qualification_run_id` entries and complete the commit. Document this recovery behavior in the script's header.

---

### FB-11 (P3): Weekly auto-qualification re-runs `qualified` models if registry not updated between cycles

**Affected feature**: F5 (proactive surfacing — weekly scheduled agent)

The weekly agent queries interrank for candidates, runs `fluxbench-qualify.sh` on candidates, and promotes passing models. The filtering logic should skip models already `qualified` in the registry. If the registry write from a previous week's qualification run was dropped (due to FB-02, or a crash), the model remains in `candidate` or `qualifying` state in the registry even though it has already been qualified.

The weekly agent will re-run qualification against it, consuming fixture-run tokens unnecessarily. More importantly, the JSONL will accumulate duplicate qualification results for the same model, and the idempotency logic (FB-06) must handle this correctly.

This is lower severity because the outcome is redundant work rather than data corruption, but it would be noticeable at scale if the registry write reliability is low.

**Corrective fix**: The weekly agent should check the JSONL (not just the registry) for recent successful `qualification_run_id` entries for each candidate before re-running. The JSONL is the source of truth for what has actually been measured; the registry is a derived cache.

---

### FB-12 (P3): `releaseDate` comparison on SessionStart reads a potentially stale interrank snapshot

**Affected feature**: F4 (drift detection — version trigger), F5 (proactive surfacing)

The version trigger compares `qualified_date` against the interrank snapshot's `releaseDate`. The interrank snapshot has a `refresh-ms` parameter (default 5 minutes per `interrank/CLAUDE.md`). If the SessionStart hook fires immediately after a model provider releases a new version but before the snapshot refreshes, the comparison sees the old `releaseDate` and does not trigger requalification.

This is a bounded delay (up to 5 minutes), not a correctness failure — but it creates a window during which the system operates on a stale version signal. If a model has degraded silently in that window and a review is dispatched during it, the review uses a model that should be in requalification.

The more concerning scenario: the snapshot is stale for longer than expected due to network failure. The interrank load code should have a max-staleness policy beyond which it refuses to serve recommendations. If it does not, the system may operate with an arbitrarily old snapshot indefinitely.

**Corrective fix**: Low urgency. Confirm that `interverse/interrank/src/load.ts` has a max-staleness policy (it is not visible in the current code from `load.ts`). If absent, add a `max_snapshot_age_ms` threshold beyond which `recommend_model` returns an error. The version-trigger on SessionStart should log a warning if the snapshot age exceeds 2x the `refresh-ms` setting.

---

## Summary

The two P0 findings (FB-01, FB-02, FB-03) are the operational risks that would cause a 3 AM incident in production:

- **FB-01** (JSONL append race): any concurrent qualification pair corrupts the permanent results store. The fix pattern already exists in `findings-helper.sh`; the requirement to use it must be made explicit in the acceptance criteria for all scripts that write to `fluxbench-results.jsonl`.

- **FB-02** (registry TOCTOU): the registry is the nerve center of the entire system — it controls model status, challenger state, and drift baselines. Without a write lock, concurrent qualification + drift detection + session-start reads produce inconsistent state.

- **FB-03** (hysteresis baseline drift): the "prevents oscillation" comment in the PRD addresses one failure mode (rapid bounce above/below threshold) but misses the slow ratchet mode where the baseline itself drifts downward over recovery cycles.

The P1 findings (FB-04 through FB-07) are correctness failures that would manifest in production within the first month: double-promotion of a challenger, session startup triggering requalification work, ID collision invalidating sync idempotency, and challenger models reaching safety-critical agent roles.

The minimal safe implementation requires: an explicit `fluxbench-append` lock-protected helper (addresses FB-01), a `flock`-protected `model-registry.yaml` write wrapper (addresses FB-02, FB-04, FB-07 write paths), and a frozen baseline field in the qualification block (addresses FB-03).

<!-- flux-drive:complete -->
