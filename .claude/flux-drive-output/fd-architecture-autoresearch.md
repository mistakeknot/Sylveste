---
artifact_type: architecture-review
reviewer: fd-architecture
plan: docs/plans/2026-03-15-autoresearch-skaffen.md
target: os/Skaffen/internal/tool/experiment/ (proposed)
date: 2026-03-15
---

# Architecture Review: Autoresearch Experiment Loop

## Grounding

Read before reviewing: `os/Skaffen/CLAUDE.md`, `os/Skaffen/AGENTS.md`, `internal/tool/builtin.go`, `internal/tool/registry.go`, `internal/tool/quality_history.go`, `internal/mutations/store.go`, `internal/evidence/emitter.go`, `internal/git/git.go`, `internal/agent/deps.go`, `internal/tui/status.go`, `cmd/skaffen/main.go`.

The existing precedent for a "tool needing its own store" is `quality_history.go` + `mutations/` package. The existing precedent for a "tool needing git access" is `internal/git/git.go`. Both precedents inform the verdict below.

---

## 1. Module Boundary: `internal/tool/experiment/` vs `internal/experiment/`

**Verdict: move to `internal/experiment/`.**

The plan places Campaign, Store, GitOps, and three Tool implementations inside `internal/tool/experiment/`. That nests domain logic (JSONL persistence, worktree lifecycle, campaign parsing) under the tool delivery layer. The existing codebase does the opposite: `internal/mutations/` owns the store, and `internal/tool/quality_history.go` holds only the tool adapter that wraps it. The store never lives inside `tool/`.

The proposed package would have at least 14 files (7 source + 7 test), its own JSONL format distinct from evidence JSONL, its own git subprocess layer, and its own campaign config search path. That is a self-contained subsystem, not a tool helper. Embedding it under `tool/` creates a false impression that these types are tool-layer concerns. It also violates the single-direction import the codebase enforces: `tool/` is imported by `agent/`, `mcp/`, and `tui/`; a large store package inside `tool/` makes `tool/` heavier and harder to reason about in isolation.

The correct split mirrors the `mutations/` precedent exactly:

```
internal/experiment/       -- domain: Campaign, Store, Segment, GitOps, record types
internal/tool/             -- delivery: InitExperimentTool, RunExperimentTool, LogExperimentTool
```

The three Tool structs stay in `internal/tool/` as flat files (`experiment_init.go`, `experiment_run.go`, `experiment_log.go`), each importing `internal/experiment` for the types they need. Registration stays in `builtin.go` or a `RegisterExperimentTools` companion in the same `tool` package. This matches exactly how `quality_history.go` wraps `mutations.Store` without pulling `mutations/` inside `tool/`.

The minimum viable move: rename the proposed package path and adjust `import` paths. No API changes required.

---

## 2. Coupling: Registration in `builtin.go` and Dependency Threading

**The plan's `RegisterExperimentTools(r *Registry, store *experiment.Store, gitOps *experiment.GitOps)` pattern is correct and already established.** `RegisterQualityHistory(r *Registry, store SignalReader)` in `builtin.go` (line 21) is the exact same shape. The coupling is intentional and contained: `builtin.go` acts as a composition root for the `tool` package, not a god module.

One issue to flag: the plan hands a concrete `*experiment.GitOps` to the registration function. `quality_history.go` uses a `SignalReader` interface (defined locally in `tool/` to break the cycle with `agent/`). The experiment tools should do the same — define narrow interfaces in `tool/` for the store and git operations they call, rather than taking concrete types from `internal/experiment`. This keeps `tool/` from importing `internal/experiment` directly and eliminates any future import cycle risk if `experiment` ever needs to import `tool` types.

Concretely:

```go
// In internal/tool/experiment_tools.go (not experiment/store.go)
type ExperimentStore interface {
    OpenSegment(name, sessionID string) (*ExperimentSegment, error)
    LoadSegment(name string) (*ExperimentSegment, error)
}

type ExperimentGitOps interface {
    CreateWorktree(name string) error
    KeepChanges(hypothesis string, delta float64) (string, error)
    DiscardChanges() error
    HasWorktree(name string) bool
}
```

The concrete `experiment.Store` and `experiment.GitOps` satisfy these interfaces; the tool structs accept the interfaces. This is one additional file and eliminates the concrete-type coupling the plan currently has.

**The `defaultGates` map in `registry.go` does not need to change.** The plan correctly uses `RegisterForPhases` with `[]Phase{PhaseAct}` (and `{PhaseAct, PhaseReflect}` for log). Tool names `"init_experiment"`, `"run_experiment"`, `"log_experiment"` slot into the existing gating mechanism without any modification to `defaultGates`. This is the right approach — do not add experiment tool names to `defaultGates` statically; let dynamic registration via `RegisterForPhases` handle it.

---

## 3. Two-Layer Design: Skaffen Tools + Clavain Skill

**The separation holds structurally but has a state ownership problem.**

The plan states "the skill drives the loop but the tools own all state." That is correct and appropriate. The Clavain skill is an orchestration script; it should hold no state of its own. The experiment store, campaign config, and git worktree are all owned by the Go tools, and the skill drives them via tool calls. The living document (`autoresearch.md`) is write-through context for the skill, not a second state store — that is fine as long as it is never treated as authoritative over the JSONL.

The risk is in `InitExperimentTool`'s resume logic (Task 4, Step 3): "if segment already exists for this campaign, load it and return current state." The skill has no way to distinguish a fresh start from a resume unless the tool return value makes this explicit. If the tool silently resumes, the skill may regenerate a living document that conflicts with the actual JSONL state. The tool should return a `resumed: true` flag and the last experiment ID so the skill can decide whether to rebuild the living document from scratch or patch it.

The recovery phase (Task 10, Step 2) says "read `autoresearch.md` and continue from last experiment." This is backwards: the JSONL is authoritative, not the markdown. On recovery, the skill should call `init_experiment` (which loads from JSONL) and use the tool's return value to reconstruct context, then update `autoresearch.md` from that data. Treating the markdown as the recovery source will cause drift between what the markdown says and what the JSONL actually records.

The two-layer split has one missing seam: the skill has no way to see whether `log_experiment` triggered a budget stop. The plan says the tool "returns stop reason" in the result. The skill must check this field and halt. If the skill ignores it and calls `init_experiment` again, it will start a new experiment after budget exhaustion. Make the stop signal unambiguous: use a dedicated field (`campaign_complete: true`) rather than embedding the reason in a string the skill must parse.

---

## 4. Evidence Bridge: `ExperimentEvidence` Through the Existing Pipeline

**Do not add `EmitExperiment` to `JSONLEmitter`. Route experiment evidence through the existing `Emit(agent.Evidence)` path instead.**

The plan proposes a second method `EmitExperiment(ev ExperimentEvidence)` on `JSONLEmitter` with a different `--source=autoresearch` flag for intercore. This creates two parallel paths through the emitter: one for turn evidence, one for experiment evidence. They diverge at serialization, at intercore bridging (different `--source` values), and at JSONL file routing.

The existing `agent.Evidence` struct has extensible fields (`ToolCalls`, `FileActivity`, `Outcome`) and the emitter already handles the intercore bridge. The cleanest path is to emit experiment events as structured `agent.Evidence` records with `Outcome` set to the experiment decision and an agreed convention for what goes in the existing fields, or to add one optional field to `agent.Evidence`:

```go
ExperimentEvent *ExperimentEvent `json:"experiment,omitempty"`
```

Where `ExperimentEvent` is defined in `internal/agent/` (next to `Evidence`) and populated only when the emitter is called from an experiment tool context.

This keeps one JSONL file per session, one intercore bridge path, and one consumer of evidence records downstream (interspect, interstat). The `--source` can remain `interspect` with the experiment type carried inside the payload, or the `eventType` selection logic in `BridgeArgs` can check for the non-nil `ExperimentEvent` field and emit `experiment_kept`/`experiment_discarded` as types.

The alternative — two separate JSONL files, two `ic` invocations per log — doubles the surface area for failures and means downstream consumers must join two streams to correlate experiments with the turns that produced them. That correlation is valuable (which tool calls preceded a kept experiment?) and is lost if they are separate pipelines.

If the interlab mutation emit (Task 6, Step 3) must use a different `--source=autoresearch`, that is an argument for a specific method or helper on the emitter, not a second full pipeline. A `BridgeWithSource(ev agent.Evidence, source string)` method keeps the JSONL write unified and varies only the intercore call.

---

## Summary: Structural Issues by Priority

### Must Fix

**M1 — Wrong package boundary.** `Campaign`, `Store`, `Segment`, and `GitOps` must live in `internal/experiment/`, not `internal/tool/experiment/`. The precedent is `internal/mutations/`. Seven files of domain logic embedded under the tool delivery layer violates the existing import structure. Change the package path; no API changes required.

**M2 — Evidence pipeline duplication.** `EmitExperiment` must not create a second evidence pipeline. Add an optional `ExperimentEvent` field to `agent.Evidence` or use the existing `Emit` path with experiment-specific field values. Two JSONL streams + two intercore invocations breaks downstream correlation.

**M3 — Recovery reads the wrong source.** The skill's recovery phase treats `autoresearch.md` as authoritative. The JSONL store is authoritative. Recovery must call `init_experiment` (which reads JSONL) and rebuild the markdown from the tool response, not the reverse.

### Should Fix

**S1 — Concrete type coupling in registration.** `RegisterExperimentTools` takes `*experiment.Store` and `*experiment.GitOps`. Define narrow interfaces in `tool/` and accept those instead. Matches the `SignalReader` interface precedent in `quality_history.go`.

**S2 — Resume signal ambiguity.** `InitExperimentTool` must return an explicit `resumed: bool` and `last_experiment_id` so the skill can determine whether to rebuild the living document. Silent resume breaks the skill's context management.

**S3 — Budget stop signal.** `LogExperimentTool` should return an unambiguous `campaign_complete: bool` field, not a human-readable stop reason string the skill must parse.

### Optional Cleanup

**O1 — `gitops.go` inside `experiment/`.** Once the package moves to `internal/experiment/`, consider whether `GitOps` wraps `internal/git.Git` or duplicates its subprocess logic. The existing `git.Git` handles `workDir`; worktree operations are additive. `GitOps` should embed or accept a `*git.Git` and add only the worktree methods, rather than duplicating the `run()` helper.

**O2 — TUI message channel.** Task 8 says experiment tools send state updates "via TUI message channel." This channel does not currently exist in the `appModel`; experiment state updates will need to go through the same `tea.Cmd` / message dispatch the agent uses for streaming events. Verify that the message type additions do not require the tools to import `tui`, which would create a cycle (`tui` → `agent` → `tool` → `tui`). The safe path is an `ExperimentStateMsg` defined in a shared location (or in `tool/`) that `tui` subscribes to, not the other way around.

---

## Relevant Files

- `/home/mk/projects/Demarch/os/Skaffen/internal/tool/builtin.go` — registration site; `RegisterQualityHistory` is the pattern to follow
- `/home/mk/projects/Demarch/os/Skaffen/internal/tool/quality_history.go` — precedent for tool wrapping a store via interface
- `/home/mk/projects/Demarch/os/Skaffen/internal/mutations/store.go` — precedent for domain store living outside `tool/`
- `/home/mk/projects/Demarch/os/Skaffen/internal/evidence/emitter.go` — existing pipeline; `EmitExperiment` must not fork this
- `/home/mk/projects/Demarch/os/Skaffen/internal/agent/deps.go` — `Evidence` struct; correct place to add `ExperimentEvent` field
- `/home/mk/projects/Demarch/os/Skaffen/internal/git/git.go` — existing git ops; `GitOps` should compose this, not duplicate it
- `/home/mk/projects/Demarch/os/Skaffen/internal/tui/status.go` — `updateStatusSlots` signature; no `tool` import, keep it that way
- `/home/mk/projects/Demarch/docs/plans/2026-03-15-autoresearch-skaffen.md` — plan under review
