---
artifact_type: correctness-review
reviewer: Julik (fd-correctness)
plan: docs/plans/2026-03-15-autoresearch-skaffen.md
prd: docs/specs/2026-03-15-autoresearch-skaffen-prd.md
date: 2026-03-15
bead: projects-z6k
---

# Correctness Review: Autoresearch Implementation Plan

## Invariants That Must Hold

Before enumerating findings, I am stating the invariants the design claims to uphold. Correctness review is guesswork without these.

**I1: Git state is always clean after a keep or discard decision.**
No uncommitted changes in the worktree between experiments. Violated git state is undetectable by subsequent experiments, which would then measure a compound of two experiments.

**I2: JSONL on-disk state is always consistent with in-memory Segment state.**
The durable log is the ground truth. A crash at any point must leave the log in a state from which `LoadSegment` can reconstruct exactly the experiments that were fully committed (written + fsynced).

**I3: The baseline used for delta computation is unambiguous and monotonically defined.**
The plan allows the baseline to shift on keep. The delta shown in the TUI and stored in the log must always reference the same anchor that was in effect when that experiment was logged.

**I4: The agent's keep/discard decision is final before git operations are performed.**
The LogExperimentTool may override the agent's decision to "discard" due to secondary metric regression. The override must be applied before any git write, not after.

**I5: A single campaign has at most one live Segment at a time.**
Multiple concurrent agents calling init_experiment for the same campaign must not both open new segments against the same JSONL file.

**I6: Worktrees are always cleaned up on crash, not just on graceful shutdown.**
The PRD states "JSONL survives crashes, git state is always clean after keep/discard." An orphaned worktree violates I1 on all subsequent runs that try to create it.

---

## Finding 1: Torn Write on Resume — JSONL Last-Line Validation Missing

**Severity: Data integrity. Will corrupt baseline on crash.**

The plan specifies `Segment.LogExperiment` writes with fsync and `LoadSegment` reconstructs the last segment's state. However, the recovery procedure does not account for a torn write on the final line.

**How this happens in practice.** A Linux fsync on a file with `O_APPEND` guarantees that the kernel write buffer is flushed to the storage device, but if the process is killed with SIGKILL between the `Write` syscall and `Sync`, the write may have reached the file partially. A 500-byte JSON line can arrive on disk as 200 bytes of a valid prefix followed by nothing — valid UTF-8, but not a closed JSON object. `bufio.Scanner` with the default split function (ScanLines) will return that partial line as a non-empty byte slice. `json.Unmarshal` will return an error and the existing session JSONL code's convention (see `session.go` line 222) is to `continue` — silently skipping the line.

For session replay that is acceptable. For experiment resumption it is not, because a skipped ExperimentRecord means the experiment count, consecutive-failure count, and cumulative-delta are all understated. The agent resumes and runs what it believes is experiment N+1 when it is actually N+2, or it does not stop when it should because the failure counter is short by one.

**Concrete interleaving:**

1. Agent calls `log_experiment` with decision="keep", metric_after=0.38.
2. `LogExperiment` marshals the record to JSON (412 bytes), calls `f.Write`.
3. The OS writes 200 bytes to the page cache. Process is killed (OOM, SIGKILL, power loss).
4. fsync never completes. The file ends with 200 bytes of a partial JSON object: `{"type":"experiment","segment":"seg-001","id":"exp-007","hypothesis":"cache warmup","status":"compl`.
5. On resume, `LoadSegment` calls `bufio.Scanner.Scan()`, gets the partial line, `json.Unmarshal` fails, the line is skipped.
6. Segment reconstructs exp_count=6 instead of 7, best_metric=0.42 (original baseline) instead of 0.38.
7. The next experiment computes delta relative to 0.42, reports +10% when the real improvement from the true best is only 5%.

**Minimal fix.** After the scanner loop in `LoadSegment`, check whether the last non-empty raw line (before `json.Unmarshal`) is a valid closed JSON object by verifying it ends with `}`. If it does not, truncate the file to the byte offset of the previous newline before returning. This is one `os.Truncate` call. Because the segment header is a separate record type, a torn segment header is a separate and simpler case: no experiments have been logged, recovery is a fresh start.

Alternatively, use a checksum or record-length prefix before each line. The existing `appendJSONL` in `evidence/emitter.go` does not do this, and the proposed `store.go` is modelled after it — so the same deficiency would be copied in.

The existing `session.go` Reader uses the same skip-on-error pattern (line 222). This is acceptable for session history, where a skipped turn merely shortens context. It is not acceptable for the experiment store, where each record is a financial and git-state commitment.

---

## Finding 2: Orphaned Worktrees on Crash — No Cleanup Mechanism

**Severity: Invariant I6 violated. Will block all future campaigns with the same name.**

The plan specifies `CreateWorktree` with "if worktree already exists, reuse it." This is mentioned as a positive feature. It is not: reuse without verifying the worktree's git state can resume the loop with uncommitted leftover changes from the prior crashed experiment.

**The structural problem.** The plan defines `RemoveWorktree` (called on campaign completion or explicit stop) but there is no automatic cleanup path for crashes. The PRD risk table mentions "Worktree accumulation → Cleanup on campaign end + periodic sweep" but neither the plan nor the PRD defines what that sweep is, who runs it, or when.

**Crash interleaving that creates a corrupt state:**

1. Experiment 7: agent calls `log_experiment` with decision="keep".
2. `KeepChanges` calls `git add -A && git commit`. Commit succeeds.
3. The experiment record is written to JSONL. fsync begins. Process crashes.
4. JSONL log has experiment 7 (decision=keep, git_sha=abc123).
5. On resume, `CreateWorktree` sees the worktree at `/tmp/autoresearch-routing-opt` already exists, reuses it. The worktree is at commit abc123.
6. The next experiment makes changes, calls `run_experiment`. The benchmark runs against both the experiment-8 changes AND any pre-crash debris from experiment 7 that was staged but not committed.

Wait — actually in the clean success case the worktree is at abc123 and is clean. The problem is subtler: what if the crash happened during `git add -A` (step 2), before the commit? Then:

1. Experiment 7: `log_experiment` decision=keep.
2. `git add -A` starts, stages some files. Process crashes before `git commit` runs.
3. JSONL log does NOT have experiment 7 (the write happens after `KeepChanges` returns, so the record was not written yet, or was written but partially — see Finding 1).
4. On resume, `CreateWorktree` reuses worktree. The worktree now has staged changes that belong to experiment 7.
5. Agent begins experiment 8. Makes new changes. Calls `run_experiment`. The benchmark runs against experiment-7 staged changes plus experiment-8 unstaged changes combined.
6. Agent calls `log_experiment` with decision="keep". `KeepChanges` does `git add -A && git commit`, committing a blend of experiments 7 and 8.

The commit message says "experiment(routing-opt): [experiment 8 hypothesis]" but the commit contains changes from two hypotheses. The experiment log and the git history diverge.

**Minimal fix.** On `CreateWorktree` reuse (when the worktree already exists), always call `git reset HEAD` + `git checkout -- .` to reset staged and unstaged changes before returning to the caller. This is equivalent to a clean discard of any in-flight experiment, which is the only safe assumption on reuse. Document this clearly as the crash-recovery contract. The JSONL log is the ground truth; any git state not recorded in the log is discarded.

A secondary fix: implement a startup sweep function that calls `git worktree list --porcelain` and removes any autoresearch worktrees whose campaign is not in an active segment in the store. This prevents accumulation but does not address the per-resume state problem.

---

## Finding 3: Baseline Ambiguity in Delta Computation

**Severity: Logical correctness. Produces misleading cumulative statistics.**

Plan Task 6, Step 2: "Compute delta from baseline (or best, if keep decisions have shifted baseline)."

This is ambiguous in two ways.

**Ambiguity A: When does baseline shift?** The PRD says "Keep: update segment baseline to new value." If "baseline" in the segment means the current-best after each keep decision, then "delta from baseline" always means "delta from current best." If "baseline" means the original campaign YAML baseline that never changes, then "delta from baseline" means "total improvement from start." The plan uses both meanings in different places.

In the JSONL ExperimentRecord schema (PRD persistence section), the fields are `metric_before` and `metric_after`, which strongly implies delta = `metric_after - metric_before`. But what is `metric_before`? Is it the original baseline, the segment-start value, or the value after the last kept experiment?

The TUI status slot shows "cumulative_delta" — which must reference the original campaign baseline (otherwise you cannot tell whether the campaign is progressing overall). But the per-experiment delta for the ShouldStop `max_consecutive_failures` counter needs to compare against the current best, not the original baseline, because otherwise a campaign that keeps improving at smaller increments will appear to "fail" if each improvement is smaller than the original baseline gap.

**The concrete failure.** Suppose the optimization direction is "minimize" and original baseline is 100. After 5 experiments: kept at 90, kept at 85, kept at 82. Now an experiment produces 83 (worse than current best of 82, but better than original 82 + acceptable regression?). Is this a failure for the consecutive-failure counter? The answer depends on which baseline is used, and the plan does not specify.

**Minimal fix.** Define two distinct fields in Segment state: `originalBaseline float64` (from campaign YAML, never mutated) and `currentBest float64` (updated on each keep). Use `currentBest` for per-experiment delta computation and the consecutive-failure guard. Use `originalBaseline` for cumulative delta in the TUI and summary record. Store both in the segment header record so they survive crashes. The plan conflates these under the single word "baseline."

---

## Finding 4: Secondary Metric Override After Agent Decision

**Severity: Agent-tool contract violation. Creates tool call ambiguity.**

Plan Task 6, Step 3: "Check secondary metric regressions: if any secondary regresses beyond threshold, force decision to 'discard' with reason."

The problem is the sequence of operations in the plan's Step 4: the git operation is executed based on the original decision, and separately the secondary check happens "before." But the plan actually writes it in this order:

1. Load active segment
2. Compute delta from baseline
3. Check secondary metric regressions → force decision to "discard" with reason
4. Based on decision: keep → GitOps.KeepChanges(), discard → GitOps.DiscardChanges()
5. Write experiment record to JSONL

If the override in step 3 is applied before step 4, this is safe. But the plan's language "force decision to discard with reason" after the tool has already received `decision="keep"` from the agent is architecturally concerning for a different reason: the tool is silently changing the agent's declared intent.

The agent sees the result of `log_experiment` — "discarded due to secondary regression" — and must interpret this correctly. The returned `ToolResult.Content` will say "discard" but the agent submitted "keep." This creates a situation where:

- The agent may retry with a new hypothesis, not understanding why its keep was rejected.
- The agent may proceed normally, having "learned" that this type of change is bad.
- If the agent is not reading the tool result carefully, it may update its internal state as if the keep succeeded (because it submitted keep).

**The pattern mismatch.** The plan uses a tool to enforce a business constraint (secondary regression) that should be enforced before the agent makes its decision. The more correct architecture is to surface secondary metric values in `run_experiment`'s return, let the agent see them, and make the keep/discard decision with full information. If the tool must override anyway (as a safety net), the override should be flagged unambiguously in the result schema, not buried in a string reason.

**Minimal fix.** The tool override is acceptable as a safety net, but the `ToolResult.Content` must include a structured field like `"decision_override": "discard"` and `"override_reason": "secondary metric test_pass_rate regressed by 3.2% (threshold 2.0%)"`. The JSONL ExperimentRecord should store the agent's original decision alongside the effective decision so audits can distinguish agent-chosen discards from system-forced discards. Add a field `agent_decision` distinct from `decision`.

Also: git operations must not be invoked until the override check is complete. The plan says "Based on decision:" in step 4, which is after the override in step 3. Verify the implementation does not split the check and the git call across a code boundary where an error between them could leave git in a committed state when the effective decision is "discard."

---

## Finding 5: Store Has No Mutex — Concurrent TUI Message Write Race

**Severity: Data race. Will corrupt JSONL on concurrent writes.**

The plan's Task 8, Step 3: "Add message types for experiment state updates (sent by experiment tools via TUI message channel)."

The `Store` struct defined in Task 2 has no mutex. The `Segment` it manages holds state (exp_count, best_metric, cumulative_delta) and writes to a JSONL file.

Looking at the existing `JSONLEmitter` in `evidence/emitter.go`: it correctly uses `sync.Mutex` in `Emit()` around `appendJSONL`. The plan's Store must do the same.

**The concurrent access paths.**

Path A: The agent calls `log_experiment` → `Segment.LogExperiment` → file write + fsync. This runs in the agent goroutine (the Bubble Tea `tea.Cmd` closure, which runs in a goroutine — see `app.go` line 818-831, where `agentCmd` is a closure returned as a `tea.Cmd`).

Path B: The TUI plan calls experiment tools to send state update messages to `p.Send(experimentStateMsg{...})`. The `p.Send` call itself is goroutine-safe in Bubble Tea. However, if the plan implements this as a direct call from within the tool's Execute method (which runs in the agent goroutine) to update shared state, and the TUI Update handler (which runs in the Bubble Tea event loop goroutine) simultaneously reads or writes the same Store to display state, there is a race.

More critically: `Segment` has in-memory fields like `experimentCount int` and `bestMetric float64`. If the TUI message handler reads `experimentCount` to render the status slot while `LogExperiment` is incrementing it, this is an unsynchronized read/write on a non-atomic integer. Go's race detector will flag this.

The existing `JSONLSession.Save` uses `s.mu.Lock()` before every mutation. The plan does not mention adding a mutex to `Store` or `Segment`, which means it would need to be added explicitly.

**Minimal fix.** Add `mu sync.Mutex` to `Segment`. Acquire it in `LogExperiment`, `Close`, and any method that reads mutable state (`ShouldStop`, `BestMetric`, `ExperimentCount`). The file write is serialized by the mutex. For TUI reads, either snapshot the Segment state into a separate struct and pass that as the message payload (preferred — no shared state between goroutines), or require all reads from the TUI goroutine to go through a mutex-protected accessor.

The plan's current structure of "TUI message channel" for experiment state updates suggests the intent is to copy state into a Bubble Tea message and post it. If the copy happens inside the mutex in `LogExperiment` (before releasing the lock), there is no race. The plan must explicitly state this sequencing.

---

## Finding 6: Worktree Path in /tmp Is World-Readable

**Severity: Security. Moderate risk, campaign-name-predictable path.**

The plan specifies `git worktree add /tmp/autoresearch-{name}` where `{name}` is the campaign name from a user-controlled YAML file. This creates a predictable, world-readable path.

**Practical risks:**

1. **Symlink attack.** An adversary on the same system creates `/tmp/autoresearch-routing-opt` as a symlink to a path they want to corrupt before the agent runs the campaign. `git worktree add` will fail if the target exists but is not a valid worktree, but this produces a confusing error rather than a security-safe failure.

2. **Information disclosure.** The worktree contains the full git repository checkout including any secrets in tracked files (API keys in config files that were accidentally committed, etc.). On a shared build server, other users can read `/tmp/autoresearch-*`.

3. **Experiment content exposure.** The hypothesis commits made in the worktree (containing potentially proprietary optimization code changes) are readable by any user on the system.

**Minimal fix.** Use `os.UserCacheDir()` or `os.UserHomeDir()` to construct a user-specific base path. On Linux, `$XDG_CACHE_HOME/skaffen/worktrees/` or `~/.cache/skaffen/worktrees/` with permissions 0700. The existing Store default path already uses `~/.skaffen/experiments/` — the worktree path should follow the same convention. The plan already uses `~/.skaffen/campaigns/` for campaign YAML and `~/.skaffen/experiments/` for the store, so `/tmp` is inconsistent with the design's own conventions.

---

## Finding 7: `CreateWorktree` Reuse Ignores Stale Branch State

**Severity: Data integrity. Compounds with Finding 2.**

Task 3, Step 2: `CreateWorktree` — "If worktree already exists, reuse it."

The plan does not specify how to determine that the existing worktree is on the correct branch. If a previous campaign run used `autoresearch/routing-opt` and was completed (branch not deleted), a new run would reuse the worktree pointing at a historical commit — not at the current HEAD of the main branch. All experiments in the new run would be based on stale code.

The `HasWorktree` check uses path existence. Path existence does not imply the worktree is valid, healthy, or branched from the right base.

**Minimal fix.** On reuse, verify that the worktree's `git merge-base HEAD autoresearch/{name}` is recent (within N commits of HEAD). If it is not, error out and require the user to explicitly remove the stale worktree. Alternatively, do not reuse and always create a fresh worktree from the current HEAD, naming it with a timestamp suffix to avoid conflicts.

---

## Finding 8: `DiscardChanges` with `git checkout -- .` Misses Untracked Files

**Severity: Data integrity. Experiments can pollute future experiments.**

Task 3, Step 2: `DiscardChanges` — `git checkout -- .` in worktree dir.

`git checkout -- .` reverts modifications to tracked files. It does not remove untracked files created during the experiment. If an experiment creates new source files (which is a common experiment — "add a new cache layer"), a discard will revert existing file changes but leave the new files on disk. The next experiment sees these leftover files. The benchmark runs against a polluted worktree.

**Concrete case.** Experiment 5: "Add a query result cache in `internal/cache/lru.go`." Decision: discard. `git checkout -- .` runs. The modifications to existing files are reverted, but `internal/cache/lru.go` (a new file, untracked) remains on disk. Experiment 6's benchmark runs and imports the leftover `lru.go` if the import was not in a tracked file — or more subtly, the file is present and the build system picks it up without an explicit import, changing benchmark behavior.

**Minimal fix.** Replace `git checkout -- .` with `git clean -fd && git checkout -- .`. The `-f` flag forces removal of untracked files, `-d` extends it to untracked directories. This is the standard idiom for a hard reset to the last committed state. Add a comment explaining why both are needed. Consider whether to also call `git checkout -- .` before `git clean` or after — order does not matter for correctness here, but `clean` first is slightly safer because it cannot disturb tracked files.

---

## Finding 9: `run_experiment` Has No Context Cancellation

**Severity: Resource leak. Will leave benchmark processes running after Ctrl+C.**

Task 5, Step 2: "Run benchmark command in worktree directory with timeout."

The `Tool.Execute` interface signature is `Execute(ctx context.Context, params json.RawMessage) ToolResult`. The existing `git.go` `run()` method creates `exec.Command` without attaching a context. The plan for `RunExperimentTool` specifies "command timeout → return error with partial output" but does not specify using `exec.CommandContext`.

If the Skaffen user presses Esc (which calls `m.cancelRun()` in `app.go` line 341), the agent's context is cancelled. The `RunExperimentTool.Execute` receives the cancelled context in its `ctx` parameter. If the benchmark subprocess was started with `exec.Command` (no context), it will continue running in the background consuming CPU, I/O, and potentially modifying files in the worktree. The agent loop exits, the TUI shows "Stopped," but a 2-minute benchmark is still running and may complete and modify files after the agent has returned control to the user.

**Minimal fix.** Use `exec.CommandContext(ctx, ...)` for the benchmark subprocess. This ties the subprocess lifetime to the context, so cancellation (Esc) or timeout both terminate the child process. This is the pattern used by Go's own test runner and is explicitly recommended in the Go documentation for long-running subprocesses. The timeout in the campaign YAML should be implemented as `context.WithTimeout(ctx, campaign.Benchmark.Timeout)` — this way both the campaign-level timeout and the user's Esc both work.

---

## Summary Table

| # | Finding | Severity | Invariant Violated |
|---|---------|----------|--------------------|
| 1 | Torn JSONL last line not detected on resume; malformed partial record is silently skipped, corrupting exp count and best-metric | High | I2 |
| 2 | No crash-safe worktree cleanup; `CreateWorktree` reuse can carry staged debris from crashed experiment into the next run | High | I1, I6 |
| 3 | "Baseline" is used with two incompatible meanings (original YAML value vs. current best); delta arithmetic and ShouldStop logic will disagree at runtime | High | I3 |
| 4 | Secondary-metric override happens after agent submitted keep; git ops must be strictly sequenced after override; agent_decision vs. effective decision not recorded separately | Medium | I4 |
| 5 | Store and Segment have no mutex; concurrent TUI state-update message and agent-goroutine log write produce a data race on in-memory Segment fields and the JSONL file | High | I5 |
| 6 | `/tmp/autoresearch-{name}` is world-readable and name-predictable; inconsistent with the design's own `~/.skaffen/` conventions | Low-Medium | (security) |
| 7 | Reused worktree branch may be stale (branched from an old HEAD); experiments run on wrong code base | Medium | I1 |
| 8 | `git checkout -- .` does not remove untracked files; created files from discarded experiments persist into the next experiment | High | I1 |
| 9 | Benchmark subprocess not started with `exec.CommandContext`; Ctrl+C/timeout cancels agent context but leaves subprocess running | Medium | (resource) |

## Recommended Implementation Order of Fixes

Address these before any code is written, because several fixes change the struct definitions and method signatures that all tasks depend on:

1. **Finding 3 first:** Settle the baseline definition. It determines Segment's field schema, the ExperimentRecord schema, and the ShouldStop logic. Every other task writes to or reads these fields.

2. **Finding 5 next:** Add `mu sync.Mutex` to Segment and define the mutex boundary. This determines how TUI message payloads are structured.

3. **Findings 1 and 8 together:** Both are write-path invariants. Add torn-write detection to `LoadSegment` and replace `git checkout -- .` with `git clean -fd && git checkout -- .` in `DiscardChanges`. These are small diffs but must be part of the initial implementation, not retrofitted.

4. **Finding 2:** Decide the crash-recovery contract for worktree reuse. Write it as a comment in `CreateWorktree` before implementing it. The safest contract: on reuse, always run `git reset HEAD && git clean -fd && git checkout -- .`.

5. **Finding 9:** Change all subprocess invocations in `RunExperimentTool` to `exec.CommandContext`.

6. **Finding 4:** Add `agent_decision string` field to ExperimentRecord alongside `decision string`. Document the override contract in the tool's description schema so the LLM can reason about it.

7. **Findings 6 and 7:** Change the worktree base path to `~/.cache/skaffen/worktrees/` and add branch-freshness validation to `CreateWorktree`. These are lower urgency but should be done before the first real campaign.
