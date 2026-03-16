---
artifact_type: plan
bead: projects-z6k
stage: reviewed
requirements:
  - D1: Experiment domain package (campaign, store, gitops)
  - D2: Experiment tool adapters + registration with phase gating
  - D3: TUI status bar experiment slot
  - D4: Clavain /autoresearch skill
  - D5: Evidence bridge via existing pipeline
review_fixes:
  - "M1: Package → internal/experiment/ (not tool/experiment/)"
  - "M2: Evidence via agent.Evidence ExperimentEvent field (no second pipeline)"
  - "M3: Recovery reads JSONL via init_experiment (not autoresearch.md)"
  - "S1: Sandbox WrapArgs + RequirePrompt on run_experiment"
  - "S2: DiscardChanges = git clean -fd + git checkout -- ."
  - "S3: Worktree crash recovery: reset+clean+checkout on reuse"
  - "S4: Torn JSONL detection + truncation in LoadSegment"
  - "S5: Two baselines: originalBaseline + currentBest"
  - "S6: Segment mutex for concurrent TUI/agent access"
  - "S7: experimentStatusMsg Bubble Tea message (not direct fields)"
  - "S8: Worktree path ~/.skaffen/worktrees/ (not /tmp)"
  - "S9: File permissions 0600/0700"
  - "S10: exec.CommandContext for benchmark subprocess"
  - "S11: Secret file check before git commit"
  - "S12: Narrow interfaces (Worktree, ExperimentStore) in tool/"
  - "S13: Explicit resumed/campaign_complete fields in tool returns"
  - "S14: agent_decision vs decision in ExperimentRecord"
---
# Autoresearch Implementation Plan (v2 — post-review)

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans

**Bead:** projects-z6k
**Goal:** Domain-agnostic experiment loop for Skaffen — three built-in tools, JSONL persistence, git worktree isolation, TUI integration, and Clavain skill for orchestration.
**Architecture:** Two-layer: domain package at `internal/experiment/` + tool adapters in `internal/tool/`. Evidence through existing `agent.Evidence` pipeline. Git worktrees at `~/.skaffen/worktrees/`.
**Tech Stack:** Go (Skaffen tools), YAML (campaign config), JSONL (persistence), Bubble Tea (TUI), Clavain skills (orchestration)
**PRD:** `docs/specs/2026-03-15-autoresearch-skaffen-prd.md`
**Reviews:** `fd-architecture-autoresearch.md`, `fd-correctness-autoresearch.md`, `fd-quality-autoresearch.md`, `fd-safety-autoresearch.md`

## Must-Haves
- **Truths**: Agent can init/run/log experiments autonomously. JSONL survives crashes (including torn writes). Git state is always clean after keep/discard (including untracked files). Secondary metrics prevent tunnel-vision. Benchmark commands run inside sandbox.
- **Artifacts**: `internal/experiment/` package exports `Campaign`, `Store`, `Segment`, `GitOps`. `internal/tool/` has `experiment_init.go`, `experiment_run.go`, `experiment_log.go` adapters.
- **Key Links**: Domain in `internal/experiment/` → tool adapters in `internal/tool/` accept narrow interfaces → Registry gates to Act phase → Evidence via `agent.Evidence.ExperimentEvent` field

## Invariants (from correctness review)

- **I1:** Git state is always clean between experiments (no uncommitted changes in worktree)
- **I2:** JSONL on-disk state is always consistent with in-memory Segment (crash-safe)
- **I3:** Two baselines: `originalBaseline` (from YAML, immutable) and `currentBest` (shifts on keep). Never conflated.
- **I4:** Agent's keep/discard decision is final before git operations — secondary override applied first
- **I5:** Single campaign = single live Segment. No concurrent writes to same JSONL.
- **I6:** Worktrees are cleaned to known state on reuse (crash recovery contract)

### Task 1: Campaign YAML Parser
**Files:**
- Create: `os/Skaffen/internal/experiment/campaign.go`
- Create: `os/Skaffen/internal/experiment/campaign_test.go`
- Create: `os/Skaffen/internal/experiment/testdata/routing-opt.yaml`

**Step 1:** Define `Campaign` struct matching the YAML schema (name, metric with direction/baseline, secondary_metrics with regression_threshold, benchmark with command/metric_pattern/secondary_patterns/timeout, git config, budget limits, ideas list).

**Step 2:** Implement `LoadCampaign(path string) (*Campaign, error)` that reads and validates YAML. Validation: name non-empty, metric.direction is minimize/maximize, baseline > 0, at most 3 secondary metrics, timeout parses as duration. Wrap errors with `fmt.Errorf("load campaign: %w", err)`.

**Step 3:** Implement `FindCampaign(name string) (*Campaign, error)` that searches: project-local `.skaffen/campaigns/{name}.yaml`, then `~/.skaffen/campaigns/{name}.yaml`. **Use `os.UserHomeDir()` + `filepath.Join` for tilde expansion** — `os.Open("~/.skaffen/...")` silently fails in Go.

**Step 4:** Write tests: valid campaign loads, missing fields error, invalid direction errors, secondary metric limit enforced, FindCampaign searches both paths.

<verify>
- run: cd os/Skaffen && go test ./internal/experiment/ -run TestCampaign -count=1
  expect: exit 0
- run: cd os/Skaffen && go vet ./internal/experiment/
  expect: exit 0
</verify>

### Task 2: JSONL Experiment Store
**Files:**
- Create: `os/Skaffen/internal/experiment/store.go`
- Create: `os/Skaffen/internal/experiment/store_test.go`

**Step 1:** Define record types:
- `SegmentRecord` (type:"segment", id, campaign, metric name, **original_baseline**, started_at, session_id)
- `ExperimentRecord` (type:"experiment", segment, id, hypothesis, status, metric_before, metric_after, delta, secondary map, **agent_decision**, **decision** (effective), **override_reason** (empty if no override), git_sha, duration_ms)
- `SummaryRecord` (type:"summary", segment, total, kept, discarded, cumulative_delta)

`metric_before` is always `currentBest` at the time of logging. `delta` is `metric_after - metric_before`. Cumulative delta references `originalBaseline`.

**Step 2:** Implement `Store` struct with `dir string` (defaults to `~/.skaffen/experiments/`). **Create directories with `0700`, open files with `0600`** (not 0755/0644). Methods:
- `OpenSegment(campaign *Campaign, sessionID string) (*Segment, error)` — creates segment record, appends to JSONL. Returns `(*Segment, bool, error)` where `bool` = resumed.
- `Segment.LogExperiment(exp ExperimentRecord) error` — appends experiment record with fsync. **Truncate benchmark output to 2000 chars BEFORE writing** to prevent scanner buffer overflow on resume.
- `Segment.Close() error` — writes summary record
- `LoadSegment(campaignName string) (*Segment, error)` — reads JSONL, reconstructs last segment state

**Step 3:** Implement `Segment` state tracking with **`mu sync.Mutex`**. Fields: `experimentCount`, `consecutiveFailures`, **`originalBaseline`** (immutable), **`currentBest`** (updated on keep), `cumulativeDelta` (always relative to `originalBaseline`). All field reads/writes go through the mutex. Methods:
- `ShouldStop(budget Budget) (bool, string)` — checks max_experiments, max_consecutive_failures. Uses `currentBest` for failure detection.
- `Snapshot() ExperimentStatus` — returns a value-copy of current state under the mutex (for TUI messages).

**Step 4: Torn write recovery in `LoadSegment`:**
After the scanner loop, check whether the last non-empty raw line ends with `}`. If not, truncate the file to the byte offset of the previous newline via `os.Truncate`. Skip malformed lines during scan (like `session.go`) but log a warning to stderr.

**Step 5:** Write tests: segment lifecycle, crash recovery (partial last line), resume from last segment, ShouldStop conditions, `originalBaseline` vs `currentBest` delta computation. **Include `-race` flag.**

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestStore -count=1
  expect: exit 0
</verify>

### Task 3: Git Worktree Operations
**Files:**
- Create: `os/Skaffen/internal/experiment/gitops.go`
- Create: `os/Skaffen/internal/experiment/gitops_test.go`

**Step 1:** Define `GitOps` struct **composing** the existing `git.Git` (embed or accept `*git.Git` — do not duplicate the `run()` helper). Fields: `repoDir string`, `worktreeDir string`, `branchName string`, `git *git.Git` (for the worktree dir).

**Step 2:** Implement methods:
- `CreateWorktree(campaignName string) error` — **path: `~/.skaffen/worktrees/{name}`** (not `/tmp`), with `0700` parent dir. `git worktree add {path} -b autoresearch/{name}`. **On reuse (worktree already exists): always execute `git reset HEAD && git clean -fd && git checkout -- .`** to restore clean known state (crash-recovery contract). Check via `git worktree list --porcelain`, not just directory existence.
- `KeepChanges(hypothesis string, delta float64) (string, error)` — In worktree: `git add -A`, then **pre-commit secret check**: run `git diff --cached --name-only` and reject if any staged filename matches `.env`, `*.pem`, `*.key`, `*_rsa`, `*.p12`. Then `git commit -m "experiment({campaign}): {hypothesis} [{delta}]"`. Returns commit SHA.
- `DiscardChanges() error` — **`git clean -fd && git checkout -- .`** in worktree dir (not just `git checkout -- .` which misses untracked files).
- `CurrentSHA() (string, error)` — returns HEAD SHA in worktree.
- `RemoveWorktree() error` — `git worktree remove` with cleanup.
- `HasWorktree(campaignName string) bool` — **check `git worktree list` output**, not just directory existence. Verify branch is not stale (branched from recent HEAD).

**Step 3:** Write tests: create/remove worktree lifecycle, keep creates commit, **keep rejects staged .env file**, discard removes untracked files AND reverts tracked changes, reuse cleans up crashed state. Tests use `git init` temp repos.

<verify>
- run: cd os/Skaffen && go test -race ./internal/experiment/ -run TestGitOps -count=1
  expect: exit 0
</verify>

### Task 4: InitExperimentTool
**Files:**
- Create: `os/Skaffen/internal/tool/experiment_init.go`
- Create: `os/Skaffen/internal/tool/experiment_init_test.go`

**Step 1:** Define narrow interface in `internal/tool/` for store dependency (mirrors `SignalReader` pattern in `quality_history.go`):
```go
// ExperimentStore is the subset of experiment.Store used by experiment tools.
type ExperimentStore interface {
    OpenSegment(campaignName, sessionID string) (*ExperimentSegment, bool, error)
    LoadSegment(campaignName string) (*ExperimentSegment, error)
    FindCampaign(name string) (*Campaign, error)
}

// ExperimentSegment is the subset of experiment.Segment used by experiment tools.
type ExperimentSegment interface {
    Snapshot() ExperimentStatus
    ShouldStop() (bool, string)
    LogExperiment(rec ExperimentRecord) error
    Close() error
}
```

**Step 2:** Implement `InitExperimentTool` satisfying `tool.Tool` interface:
- Name: `"init_experiment"`
- Description: "Initialize an experiment with a hypothesis. Creates or resumes a campaign session, sets up git worktree if needed."
- Schema: `{"type":"object","properties":{"campaign":{"type":"string","description":"Campaign name (matches YAML file)"},"hypothesis":{"type":"string","description":"What you expect this change to achieve"}},"required":["campaign","hypothesis"]}`

**Step 3:** Execute logic:
1. Load campaign YAML via store's `FindCampaign(name)`
2. Create or reuse git worktree via `Worktree.CreateWorktree()` (clean on reuse)
3. Open or resume segment via `Store.OpenSegment()` — returns `(segment, resumed, err)`
4. Return confirmation with **explicit `resumed: true/false`**, campaign `originalBaseline`, `currentBest`, experiment ID, worktree path, and experiment count if resumed

**Step 4:** Tests: init new campaign, init existing campaign (resume returns `resumed: true`), campaign not found error. Use stub `Worktree` and `ExperimentStore`.

<verify>
- run: cd os/Skaffen && go test ./internal/tool/ -run TestInitExperiment -count=1
  expect: exit 0
</verify>

### Task 5: RunExperimentTool
**Files:**
- Create: `os/Skaffen/internal/tool/experiment_run.go`
- Create: `os/Skaffen/internal/tool/experiment_run_test.go`

**Step 1:** Define narrow interface for worktree operations:
```go
// Worktree provides git worktree operations for experiment tools.
type Worktree interface {
    CreateWorktree(name string) error
    KeepChanges(hypothesis string, delta float64) (string, error)
    DiscardChanges() error
    HasWorktree(name string) bool
    WorktreeDir() string
}
```

**Step 2:** Implement `RunExperimentTool` satisfying `tool.Tool`. Constructor: `NewRunExperimentTool(store ExperimentStore, wt Worktree, sandbox *sandbox.Sandbox)` — **accepts sandbox for benchmark wrapping**.
- Name: `"run_experiment"`
- Description: "Run the campaign benchmark and extract metrics. Returns primary and secondary metric values."
- Schema: `{"type":"object","properties":{"campaign":{"type":"string","description":"Campaign name"}},"required":["campaign"]}`

**Step 3:** Execute logic:
1. Load active segment state
2. **Wrap benchmark command through sandbox**: `sandbox.WrapArgs("bash", "-c", command)` — same pattern as `BashTool`. This gives bwrap containment when available.
3. **Use `exec.CommandContext(ctx, ...)`** with `context.WithTimeout(ctx, campaign.Benchmark.Timeout)` — ties subprocess lifetime to both campaign timeout and user cancellation (Ctrl+C/Esc).
4. Set `cmd.Dir = wt.WorktreeDir()`
5. Capture stdout/stderr
6. Extract primary metric via regex `metric_pattern` from output
7. Extract secondary metrics via `secondary_patterns`
8. Return: metric values, benchmark output (truncated to 2000 chars), duration

**Step 4:** Error handling: context deadline exceeded → kill subprocess, return error with partial output. Regex no match → return error with full output for debugging. Command failure → return stderr.

**Step 5:** Tests: successful benchmark with metric extraction, timeout handling (context cancellation kills subprocess), regex mismatch, secondary metric extraction. **Test with sandbox mock.** Add injection-safety test: hypothesis string containing `'; rm -rf /tmp/test'` must not execute via shell.

<verify>
- run: cd os/Skaffen && go test ./internal/tool/ -run TestRunExperiment -count=1
  expect: exit 0
</verify>

### Task 6: LogExperimentTool
**Files:**
- Create: `os/Skaffen/internal/tool/experiment_log.go`
- Create: `os/Skaffen/internal/tool/experiment_log_test.go`

**Step 1:** Implement `LogExperimentTool` satisfying `tool.Tool`. Constructor: `NewLogExperimentTool(store ExperimentStore, wt Worktree, icPath string)` — detect `ic` binary once via `exec.LookPath("ic")` at construction, store path (empty = unavailable). Same pattern as `evidence/emitter.go`.
- Name: `"log_experiment"`
- Description: "Log experiment results and decide: keep (commit changes), discard (revert changes), or investigate (keep changes uncommitted for manual review). May override decision to discard if secondary metrics regress."
- Schema: `{"type":"object","properties":{"campaign":{"type":"string"},"decision":{"type":"string","enum":["keep","discard","investigate"]},"metric_value":{"type":"number","description":"Primary metric value from run_experiment"},"secondary_values":{"type":"object","description":"Map of secondary metric name to value"},"notes":{"type":"string","description":"Optional notes about what was learned"}},"required":["campaign","decision","metric_value"]}`

**Step 2:** Execute logic:
1. Load active segment (mutex-protected snapshot for reads)
2. Compute delta: `metric_value - segment.CurrentBest()`. Cumulative delta: `metric_value - segment.OriginalBaseline()`.
3. **Check secondary metric regressions BEFORE git operations.** If any secondary regresses beyond threshold:
   - Set `effectiveDecision = "discard"`, `overrideReason = "secondary metric {name} regressed by {amount} (threshold {threshold})"`
   - Store both `agentDecision` (original) and `decision` (effective) in ExperimentRecord
4. Based on **effective** decision:
   - **keep:** `wt.KeepChanges()`, update segment `currentBest`, emit interlab mutation event via stored `icPath` (best-effort, `cmd.Run()` error swallowed)
   - **discard:** `wt.DiscardChanges()` (cleans untracked files too)
   - **investigate:** no git action, mark experiment as "investigating"
5. Write experiment record to JSONL via `segment.LogExperiment()` (under mutex)
6. Check `segment.ShouldStop()` — returns `(bool, string)`
7. Return: experiment summary with **explicit `campaign_complete: true/false`** field, cumulative stats (using `originalBaseline`), and `decision_override` info if applicable

**Step 3:** Interlab bridge (best-effort): on keep, use `exec.Command(icPath, args...)` with args slice (never shell string interpolation). Same pattern as `evidence/emitter.go:bridgeToIntercore`.

**Step 4:** Tests: keep writes commit + updates `currentBest`, discard reverts + cleans untracked, secondary regression overrides keep→discard with `agent_decision` preserved, ShouldStop triggers `campaign_complete: true`, interlab bridge called on keep with safe args (test injection string). **Include `-race`.**

<verify>
- run: cd os/Skaffen && go test -race ./internal/tool/ -run TestLogExperiment -count=1
  expect: exit 0
</verify>

### Task 7: Tool Registration + Phase Gating
**Files:**
- Modify: `os/Skaffen/internal/tool/builtin.go`
- Modify: `os/Skaffen/cmd/skaffen/main.go`

**Step 1:** Add `RegisterExperimentTools` function accepting narrow interfaces:
```go
func RegisterExperimentTools(r *Registry, store ExperimentStore, wt Worktree, sb *sandbox.Sandbox) {
    icPath, _ := exec.LookPath("ic")
    expPhases := []Phase{PhaseAct}
    r.RegisterForPhases(NewInitExperimentTool(store, wt), expPhases)
    // run_experiment gets RequirePrompt constraint for sandbox safety
    r.RegisterForPhasesWithConstraint(NewRunExperimentTool(store, wt, sb), expPhases,
        &GateConstraint{RequirePrompt: true})
    // log_experiment also available in Reflect
    r.RegisterForPhases(NewLogExperimentTool(store, wt, icPath), []Phase{PhaseAct, PhaseReflect})
}
```

**Step 2:** Add `RegisterForPhasesWithConstraint` method to Registry if it doesn't exist — same as `RegisterForPhases` but stores the constraint instead of `nil`.

**Step 3:** Call `RegisterExperimentTools` from `cmd/skaffen/main.go` where registry is created. Construct `experiment.Store` and `experiment.GitOps` there, passing them as interfaces.

<verify>
- run: cd os/Skaffen && go build ./cmd/skaffen
  expect: exit 0
- run: cd os/Skaffen && go test ./internal/tool/ -run TestRegistry -count=1
  expect: exit 0
</verify>

### Task 8: TUI Experiment Status Slot
**Files:**
- Modify: `os/Skaffen/internal/tui/status.go`
- Modify: `os/Skaffen/internal/tui/app.go`

**Step 1:** Define `ExperimentStatus` struct (value type for thread-safe messaging) and Bubble Tea message type. **Define in `internal/tool/` or a shared location** to avoid `tool` → `tui` import cycle:
```go
// In internal/tool/experiment_status.go
type ExperimentStatus struct {
    Active bool
    Count  int
    Max    int
    Delta  float64  // cumulative, relative to originalBaseline
    Unit   string
}
```

**Step 2:** Define `experimentStatusMsg` in `internal/tui/`:
```go
type experimentStatusMsg tool.ExperimentStatus
```

**Step 3:** Add `expStatus ExperimentStatus` field to `appModel` (single struct, not five loose fields). Update only in `Update()` handler for `experimentStatusMsg` — **never mutate from tool goroutines directly**.

**Step 4:** Update `updateStatusSlots` — add a single `exp ExperimentStatus` parameter:
```go
func updateStatusSlots(sb *statusbar.Model, phase, model string, cost, contextPct float64, turns int, planMode bool, sandboxLabel string, exp ExperimentStatus) {
    // ... existing slots ...
    if exp.Active {
        expValue := fmt.Sprintf("exp: %d/%d %+.1f%s", exp.Count, exp.Max, exp.Delta, exp.Unit)
        slots = append(slots, statusbar.Slot{Label: "", Value: expValue, Color: expColor(exp.Delta)})
    }
}
```

Update all existing call sites to pass `ExperimentStatus{}` (zero value = inactive).

**Step 5:** Add `expColor` function: improvement (delta in right direction for campaign) = Success color, regression = Warning, zero = FgDim.

**Step 6:** Wire: experiment tools send `ExperimentStatus` snapshots via a callback `func(ExperimentStatus)` set at construction — the callback calls `p.Send(experimentStatusMsg(status))`. Same pattern as `SubagentInit` carries a callback.

<verify>
- run: cd os/Skaffen && go build ./cmd/skaffen
  expect: exit 0
- run: cd os/Skaffen && go test ./internal/tui/ -count=1
  expect: exit 0
</verify>

### Task 9: Evidence Bridge
**Files:**
- Modify: `os/Skaffen/internal/agent/deps.go` (add ExperimentEvent field)
- Modify: `os/Skaffen/internal/evidence/emitter.go` (handle experiment event type in BridgeArgs)

**Step 1:** Add optional `ExperimentEvent` field to existing `agent.Evidence` struct in `internal/agent/deps.go`:
```go
type ExperimentEvent struct {
    Type       string  `json:"type"`       // "experiment_init", "experiment_run", "experiment_log"
    Campaign   string  `json:"campaign"`
    Hypothesis string  `json:"hypothesis,omitempty"`
    Decision   string  `json:"decision,omitempty"`
    Delta      float64 `json:"delta,omitempty"`
}

// In Evidence struct:
ExperimentEvent *ExperimentEvent `json:"experiment,omitempty"`
```

**Step 2:** Update `BridgeArgs` in `evidence/emitter.go` to check for non-nil `ExperimentEvent` and emit appropriate intercore event type (`experiment_kept`, `experiment_discarded`, `experiment_init`). Use `--source=autoresearch` for the intercore bridge call when experiment event is present. **No second JSONL file, no second Emit method.**

**Step 3:** Wire experiment tools to populate `agent.Evidence.ExperimentEvent` when emitting. Pass the emitter as a dependency to the tools (via interface or callback).

**Step 4:** Also fix file permissions in existing `emitter.go`: change `os.OpenFile(..., 0644)` to `0600` and `MkdirAll(..., 0755)` to `0700` (latent issue surfaced by safety review).

<verify>
- run: cd os/Skaffen && go test ./internal/evidence/ -count=1
  expect: exit 0
- run: cd os/Skaffen && go test ./internal/agent/ -count=1
  expect: exit 0
</verify>

### Task 10: Clavain /autoresearch Skill
**Files:**
- Create: `os/Clavain/skills/autoresearch/SKILL.md`
- Create: `os/Clavain/skills/autoresearch/templates/autoresearch.md`
- Create: `os/Clavain/skills/autoresearch/templates/autoresearch.ideas.md`

**Step 1:** Write `SKILL.md` with frontmatter:
```yaml
---
name: autoresearch
description: "Use when running autonomous experiment campaigns to optimize metrics. Drives init/run/log experiment loop with context recovery."
---
```

**Step 2:** Skill body — three phases:
1. **Setup:** Load campaign YAML, create session docs from templates, call `init_experiment`
2. **Loop:** Pick next idea → make changes → `run_experiment` → evaluate → `log_experiment` → **check `campaign_complete` field** — if true, stop loop → update living doc → repeat
3. **Recovery:** On context limit, write checkpoint with current state. **On resume: call `init_experiment` first (which reads JSONL store — the authoritative source), then rebuild `autoresearch.md` from the tool's return value.** Never treat `autoresearch.md` as the recovery source — it is a write-through cache for agent context, not ground truth.

**Step 3:** Skill must check `init_experiment` response for `resumed: true` — if resumed, do not regenerate the living document from scratch; patch it with current state from the tool response.

**Step 4:** Living document template (`autoresearch.md`) — same as before but with explicit note:
```markdown
<!-- This document is a context cache. The JSONL store is authoritative.
     On resume, init_experiment reads the store and this document is rebuilt. -->
# Autoresearch: {campaign_name}
## Campaign
- **Metric:** {metric_name} ({direction})
- **Original Baseline:** {original_baseline}
- **Current Best:** {current_best} ({cumulative_delta} from baseline)
- **Experiments:** {completed}/{max}

## Recent Experiments (last 10)
| # | Hypothesis | Delta | Decision | Override? |
|---|-----------|-------|----------|-----------|
...

## Active Hypothesis
{current_hypothesis}

## Ideas Remaining
{count} ideas in autoresearch.ideas.md
```

**Step 5:** Ideas backlog template (`autoresearch.ideas.md`) — unchanged.

**Step 6:** Register skill in Clavain's `plugin.json` skills list.

<verify>
- run: test -f os/Clavain/skills/autoresearch/SKILL.md && echo "exists"
  expect: contains "exists"
- run: grep "autoresearch" os/Clavain/.claude-plugin/plugin.json
  expect: exit 0
</verify>

## Execution Order

Tasks 1-3 are independent foundations (campaign parser, store, git ops) → can be parallelized.
Tasks 4-6 (tool adapters) depend on Tasks 1-3 and the narrow interfaces.
Task 7 (registration) depends on Tasks 4-6.
Task 8 (TUI) depends on the ExperimentStatus type from Task 4.
Task 9 (evidence) can parallel with Task 8.
Task 10 (skill) can start after Tasks 4-6 are done.

```
[1: Campaign] ─┐
[2: Store]    ──┼──→ [4: Init (+ interfaces)] ──┐
[3: GitOps]  ──┘     [5: Run (+ sandbox)]     ──┼──→ [7: Register] ──→ [8: TUI]
                      [6: Log (+ overrides)]   ──┘                      [9: Evidence]
                                                                        [10: Skill]
```
