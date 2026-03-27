---
artifact_type: review
reviewer: fd-quality-style
plan: docs/plans/2026-03-15-autoresearch-skaffen.md
bead: projects-z6k
date: 2026-03-15
languages: [go]
verdict: conditional-approve
---

# Quality & Style Review — Autoresearch Plan (projects-z6k)

## Scope

Reviewed against:
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tool/` — all existing tool files
- `/home/mk/projects/Sylveste/os/Skaffen/internal/git/git.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/evidence/emitter.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/mutations/store.go`
- `/home/mk/projects/Sylveste/os/Skaffen/internal/tui/status.go` and `app.go`
- `/home/mk/projects/Sylveste/os/Skaffen/AGENTS.md` and `CLAUDE.md`

Languages in scope: Go only. TypeScript, Python, Shell checks not applied.

---

## Findings

### 1. Package location — `internal/tool/experiment/` creates a nested tool sub-package (MODERATE)

**The plan places all experiment types under `internal/tool/experiment/`.** The existing `internal/tool/` package is a flat package (`package tool`) containing all seven built-in tools, their registry, and phase types. There are no sub-packages under `tool/` today. Nesting `experiment` under `tool/` introduces an asymmetry: every other built-in tool lives directly in `package tool`, but experiment tools would live in a child package that must import from the parent for `tool.Tool`, `tool.Phase`, `tool.ToolResult`, and `tool.Registry`.

The closest parallel in the codebase is `internal/mutations/` — a separate top-level internal package for a self-contained subsystem. `internal/evidence/` follows the same pattern. This suggests `internal/experiment/` (not `internal/tool/experiment/`) is the correct location, matching how `mutations` and `evidence` are organized.

The circular dependency risk is real: if `internal/tool/experiment/` imports `internal/tool` for the `Tool` interface, and `internal/tool/builtin.go` imports `internal/tool/experiment` for `RegisterExperimentTools`, you get a cycle within the same module path prefix. Go's import cycle detection would reject this. The plan's `builtin.go` snippet already illustrates this: `RegisterExperimentTools` sits in `package tool` and would need to import a child path `internal/tool/experiment`.

**Recommended fix:** Place the package at `internal/experiment/` as `package experiment`. The `RegisterExperimentTools` function either stays in `internal/tool/builtin.go` (importing `internal/experiment`) or moves to `internal/experiment/register.go` as a standalone function that receives a `*tool.Registry`. The latter keeps the tool package free of experiment imports. Either direction works — the key constraint is no cycle.

**Concrete structure:**
```
os/Skaffen/internal/experiment/
  campaign.go       package experiment
  store.go
  gitops.go
  init.go
  run.go
  log.go
```

---

### 2. `RegisterExperimentTools` signature — `*experiment.GitOps` not an interface (MODERATE)

The plan defines `GitOps` as a concrete struct wrapping `git.Git`. `RegisterExperimentTools` takes `*experiment.GitOps` directly. The existing codebase consistently uses interface injection — `SignalReader` in `quality_history.go` is defined in the `tool` package to avoid the import cycle with `mutations`. `JSONLEmitter` in `evidence/` accepts `agent.Evidence`, an interface type.

If `GitOps` is a struct with git operations, its methods should be behind an interface for the same reasons the rest of the codebase uses interfaces: testability (gitops tests currently spin up real `git init` repos, which is fine for the gitops unit, but the tool-level tests shouldn't require real git), and substitutability.

**Recommended fix:** Define a `Worktree` interface in `internal/experiment/` covering the operations the tools actually need (`CreateWorktree`, `KeepChanges`, `DiscardChanges`, `CurrentSHA`, `RemoveWorktree`, `HasWorktree`). `GitOps` implements it. Tool constructors accept `Worktree`. This follows the "accept interfaces, return structs" pattern documented in AGENTS.md.

---

### 3. Schema as `json.RawMessage` string literal — matches existing convention (PASS)

The plan defines schemas as inline string literals. This exactly matches `ReadTool.Schema()`, `QualityHistoryTool.Schema()`, and `WebSearchTool.Schema()` — all return `json.RawMessage(` `` ` `` `{...}` `` ` `` `)`. No deviation. The plan is consistent here.

The `LogExperimentTool` schema is the most complex (nested enum, optional fields). Recommend validating it parses cleanly in a test — the existing `TestRegisterBuiltins` in `tools_test.go` checks `json.Unmarshal(tool.Schema(), &schema)` for all registered tools, and experiment tools will get the same treatment once registered.

---

### 4. Type naming — `InitExperimentTool`, `RunExperimentTool`, `LogExperimentTool` (MINOR)

Existing names are `ReadTool`, `WriteTool`, `EditTool`, `BashTool`, `GrepTool`, `GlobTool`, `LsTool`, `WebSearchTool`, `WebFetchTool`, `QualityHistoryTool`. The pattern is `<Verb|Domain>Tool`. The proposed `InitExperimentTool` is verbose but unambiguous — it follows the `QualityHistoryTool` / `WebSearchTool` two-word pattern. The names are acceptable, though `ExperimentInitTool`, `ExperimentRunTool`, `ExperimentLogTool` would group-sort adjacent in IDEs. Either is fine since the names are confined to `internal/experiment/`.

Constructor names `NewInitExperimentTool` / `NewRunExperimentTool` / `NewLogExperimentTool` are correct Go for types that require injected dependencies (mirroring `NewWebSearchTool`, `NewWebFetchTool`, `NewQualityHistoryTool`).

---

### 5. Error handling — `%w` wrapping required; interlab bridge omits error logging (MODERATE)

AGENTS.md states: "Use `fmt.Errorf("context: %w", err)` for wrapping." The plan mentions this for validation errors and benchmark timeouts. The existing `git.go` uses this correctly: `fmt.Errorf("git add: %w", err)`. The mutations store uses it: `fmt.Errorf("create mutations dir: %w", err)`.

**Gap in the plan — Task 6 interlab bridge:** The plan says "shell out to `ic events record` — best-effort." The existing `evidence/emitter.go` does this correctly: it calls `cmd.Run()` and ignores the error explicitly (with a comment "ignore errors — intercore bridge is best-effort"). The plan should follow exactly the same pattern rather than inventing a new shell-out pattern inside `LogExperimentTool`. This means:
- Detect `ic` once via `exec.LookPath("ic")` at construction time (not per-call)
- Store the path (empty = unavailable), same as `JSONLEmitter.icPath`
- On keep, call the bridge outside the JSONL write lock
- Swallow the `cmd.Run()` error silently

Using a bare `exec.Command` in the tool body without the stored-path pattern will cause repeated `LookPath` calls on every `log_experiment` invocation. That's both slower and diverges from established convention.

**Gap in Task 9 (evidence bridge):** The plan proposes `EmitExperiment(ev ExperimentEvidence) error` as a new method on `JSONLEmitter`. However `JSONLEmitter` currently imports `internal/agent` (for `agent.Evidence`). Adding `ExperimentEvidence` to `evidence/experiment.go` would be a separate struct. If `EmitExperiment` is added to `JSONLEmitter`, the evidence package must not import `internal/experiment` — that would create a cycle (experiment tools import evidence, evidence imports experiment types). The `ExperimentEvidence` struct should be defined in `internal/evidence/` (not in `internal/experiment/`), and experiment tools should convert their state to `evidence.ExperimentEvidence` before calling `emitter.EmitExperiment`. Alternatively, `ExperimentEvidence` could be defined in `internal/experiment/` and the emitter method defined on a new `ExperimentEmitter` wrapper that experiment tools receive — keeping the dependency direction clean.

---

### 6. `Store` resumption — `LoadSegment` must handle scanner buffer overflow for large JSONL files (MINOR)

The existing `mutations.Store.ReadRecent` uses `bufio.NewScanner` with default 64KB buffer. JSONL lines with large benchmark outputs or many secondary metrics could exceed this. The plan says benchmark output is "truncated to 2000 chars" before logging — if this truncation happens consistently before `LogExperiment`, the default scanner buffer is fine. If not, lines could be silently skipped. The plan should explicitly note the truncation must occur before the JSONL write, not just before the tool response.

The `mutations` store silently skips malformed lines (`continue` on unmarshal error). The plan's `LoadSegment` should do the same for crash recovery correctness — a partial write at crash time will produce a truncated JSON line that must be skipped rather than failing resume.

---

### 7. `GitOps` — worktree path `/tmp/autoresearch-{name}` is not deterministic across reboots (MINOR)

The plan hardcodes `/tmp/autoresearch-{name}`. This is fine for Linux since `/tmp` is session-scoped on reboots. However, `HasWorktree` needs to check `git worktree list` output, not just whether the directory exists — the directory may exist as a leftover but the worktree may be detached or the branch may have been deleted. The existing `git.Git.run` helper is the right model: it returns `(string, error)` from `exec.Command`, and errors wrap stderr with `%w`. The plan should use the same helper pattern rather than constructing `exec.Command` directly in each method.

---

### 8. TUI state injection — experiment state should be a message type, not fields on `appModel` (MODERATE)

The plan adds five fields directly to `appModel`:
```go
experimentActive   bool
experimentCount    int
experimentMax      int
experimentDelta    float64
experimentUnit     string
```

The existing `app.go` already passes subagent state via the `subagentStatusMsg` message type (a cast of `subagent.StatusUpdate`) sent via `p.Send(subagentStatusMsg(u))`. The tools inject state updates through the Bubble Tea message loop, not through direct struct mutation. Direct field access on `appModel` from experiment tools would require `appModel` to be passed to the tools (violating the tool interface) or a shared pointer (creating a data race since tools execute in goroutines).

**Required fix:** Define an `experimentStatusMsg` type in `tui/` analogous to `subagentStatusMsg`. The `LogExperimentTool` sends this via a channel or callback that the TUI registered at construction — same pattern as `SubagentInit.AgentTool` carries the Bubble Tea callback. The five fields stay on `appModel` but are only written in the Bubble Tea `Update` method that handles `experimentStatusMsg`, keeping the model mutation thread-safe.

---

### 9. `updateStatusSlots` signature change will break existing tests (MODERATE)

The plan adds experiment state to `updateStatusSlots`. The existing function signature is:
```go
func updateStatusSlots(sb *statusbar.Model, phase, model string, cost, contextPct float64, turns int, planMode bool, sandboxLabel string)
```
`status_test.go` calls this function directly. Adding parameters to this signature will cause compilation failures in all existing call sites. The pattern used for `sandboxLabel` (added as a trailing parameter) is the established way to extend — but adding multiple fields for a single feature is better handled by extracting an `experimentStatus` struct and passing it as one parameter, keeping the call-site diff minimal.

**Recommended fix:** Define:
```go
type ExperimentStatus struct {
    Active bool
    Count  int
    Max    int
    Delta  float64
    Unit   string
}
```
And add a single `exp ExperimentStatus` parameter to `updateStatusSlots`. Call sites pass `ExperimentStatus{}` (zero value = inactive) when not in experiment mode.

---

### 10. Test strategy — task tests are correctly unit-scoped with temp repos (PASS)

The plan uses `git init` temp repos for gitops tests. This matches the Go testing pattern used elsewhere (e.g., `TestReadTool` uses `t.TempDir()`). The gitops tests are integration-level only for the filesystem/git layer, which is appropriate since there's no meaningful mock for git subprocess calls. All tool-level tests should use a stub `Worktree` (if the interface is introduced per finding #2) to remain hermetic.

The plan does not mention `go test -race`. The `Store` uses a mutex (`sync.Mutex`) following `mutations.Store`. The TUI state injection (finding #8) requires careful race analysis. Recommend adding `// go test -race ./internal/experiment/` to the verify blocks for `store.go` and `log.go` tests.

---

### 11. `FindCampaign` — `~/.skaffen/campaigns/` path expansion (MINOR)

The plan calls `FindCampaign(name string)` which searches `~/.skaffen/campaigns/{name}.yaml`. Tilde expansion is not automatic in Go — `os.Open("~/.skaffen/...")` will fail. Use `os.UserHomeDir()` + `filepath.Join`. The existing `git.go` and `emitter.go` do not deal with tilde paths (they receive absolute paths from `main.go`). This is a correctness issue that must be fixed before implementation.

---

## Summary

| # | Finding | Severity | Action |
|---|---------|----------|--------|
| 1 | Package under `tool/` creates import cycle | Moderate | Move to `internal/experiment/` |
| 2 | `GitOps` is a concrete struct in constructor signature | Moderate | Extract `Worktree` interface |
| 3 | Schema as `json.RawMessage` literals | Pass | No change needed |
| 4 | Type naming verbose but consistent | Minor | Accept as-is |
| 5 | Interlab bridge pattern diverges from `emitter.go`; evidence cycle risk | Moderate | Follow stored-`icPath` pattern; define `ExperimentEvidence` in evidence pkg |
| 6 | JSONL scanner buffer; truncation order | Minor | Clarify truncation happens before `LogExperiment` write; skip malformed lines on resume |
| 7 | Worktree existence check via directory only, not `git worktree list` | Minor | Use `git worktree list` for `HasWorktree` |
| 8 | Experiment state as direct fields on `appModel` races with tool goroutines | Moderate | Use `experimentStatusMsg` Bubble Tea message |
| 9 | `updateStatusSlots` signature change breaks existing call sites | Moderate | Extract `ExperimentStatus` struct parameter |
| 10 | Test strategy with temp repos is correct | Pass | Add `-race` to verify blocks |
| 11 | Tilde expansion in `FindCampaign` fails in Go | Minor | Use `os.UserHomeDir()` |

**Blockers before implementation begins:** Findings 1, 8. Finding 1 is an import cycle that will prevent compilation. Finding 8 is a data race that will produce non-deterministic failures in production but may not surface in tests.

**Required fixes before first task verify:** Findings 2, 5, 9, 11 will produce either compilation errors or silent behavioral failures.
