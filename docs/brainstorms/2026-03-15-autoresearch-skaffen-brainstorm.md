# Autoresearch: Autonomous Experiment Loop for Skaffen

**Bead:** projects-z6k
**Date:** 2026-03-15
**Status:** Brainstorm

## Problem

Skaffen lacks a systematic way to optimize itself. When we want to improve routing efficiency, TUI performance, or token usage, we manually iterate: tweak code, run a session, eyeball metrics, decide keep/revert. This is slow (human-in-the-loop) and lossy (no structured record of what was tried).

pi-autoresearch (assessed at `docs/research/assess-pi-autoresearch.md`, verdict: INSPIRE-ONLY) proved that an LLM can autonomously run 50+ experiments without human intervention if given:
1. Domain-agnostic infra tools (init/run/log)
2. A living document that survives context resets
3. Git-as-undo (auto-commit on keep, checkout on discard)
4. An ideas backlog that prevents knowledge loss

We want this for Skaffen — domain-agnostic experiment infrastructure that any optimization campaign can plug into.

## Design Space

### What's an "experiment" in Skaffen?

An experiment is: **modify code/config → run a benchmark → compare metric → keep or revert**.

Examples:
- Change model routing weights → run 5 sessions → compare token cost per turn
- Refactor a phase gate → run test suite → compare test pass rate + execution time
- Tune TUI render batching → run interactive session → compare FPS / flicker count
- Adjust context truncation threshold → run long session → compare quality signal scores

### Two-layer architecture (from pi-autoresearch)

**Layer 1: Infra (domain-agnostic)** — Lives in Skaffen as built-in tools:
- `init_experiment`: Create experiment session with name, hypothesis, metric, baseline
- `run_experiment`: Execute a command/script and capture stdout/stderr/timing/metrics
- `log_experiment`: Record result, decision (keep/discard/investigate), notes

**Layer 2: Campaign (domain-specific)** — Lives as a Clavain skill:
- `/autoresearch` skill creates session docs and starts the loop
- Campaign definition: what to optimize, metric name, baseline value, ideas list
- Domain knowledge injected via system prompt or skill SKILL.md

### Key design decisions

**D1: Where do the tools live?**
- Option A: Skaffen `internal/tool/` as native Go tools (like ReadTool, WriteTool)
- Option B: MCP server (separate process, reusable outside Skaffen)
- Option C: Shell scripts called by BashTool

**Recommendation: Option A.** These tools need tight integration with Skaffen's session, evidence, and phase systems. Native Go tools get:
- Phase gating (experiment tools only available in Act phase)
- Evidence emission (each experiment logged to evidence JSONL)
- Session context (experiment history available in Orient phase)
- Direct git operations (no subprocess overhead for keep/revert)

**D2: Persistence format?**

JSONL with segment headers, matching pi-autoresearch and Skaffen's existing patterns:

```jsonl
{"type":"segment","id":"seg-001","campaign":"routing-opt","metric":"cost_per_turn","baseline":0.42,"started_at":"2026-03-15T10:00:00Z"}
{"type":"experiment","segment":"seg-001","id":"exp-001","hypothesis":"Lower Haiku threshold from C3 to C2","status":"completed","metric_before":0.42,"metric_after":0.38,"delta":-0.04,"decision":"keep","git_sha":"abc123"}
{"type":"experiment","segment":"seg-001","id":"exp-002","hypothesis":"Remove Orient phase for trivial tasks","status":"completed","metric_before":0.38,"metric_after":0.41,"delta":+0.03,"decision":"discard","git_sha":"abc123"}
```

File location: `~/.skaffen/experiments/{campaign-id}.jsonl`

**D3: Git integration strategy?**

- **Branch isolation:** Each experiment session creates a branch `autoresearch/{campaign-id}`
- **Keep:** Auto-commit with message `experiment({campaign}): {hypothesis} [+{delta}%]`
- **Discard:** `git checkout -- .` (revert working tree to last commit)
- **Session end:** If on experiment branch and improvements accumulated, prompt user to merge to main
- **Safety:** Never auto-merge to main. Never force-push.

**D4: How does the loop run?**

The agent (Skaffen or Claude Code via Clavain skill) drives the loop:

```
while ideas remain AND budget allows:
  1. Pick next idea from backlog (or generate one)
  2. init_experiment(hypothesis, metric)
  3. Make code changes (using regular edit/write tools)
  4. run_experiment(benchmark_command)
  5. Compare metric to baseline
  6. log_experiment(result, decision)
  7. If keep: update baseline, commit
  8. If discard: revert changes
  9. Update living document (autoresearch.md)
  10. Append new ideas discovered during experiment
```

**Loop termination:**
- Ideas exhausted
- Token budget exceeded (checked via router budget)
- Context limit approaching (detected by context meter > 80%)
- User interrupt (Ctrl+C → graceful: log current state, don't revert)
- N consecutive failures (configurable, default 5)

**D5: Context recovery (the hard problem)**

When context is compacted or session ends:
1. **Living document** (`autoresearch.md`): Updated after each experiment. Contains: campaign goal, current baseline, experiment history (last 10), active hypothesis, ideas backlog. A fresh agent can read this and continue.
2. **Ideas backlog** (`autoresearch.ideas.md`): Append-only. New ideas discovered during experiments. Prevents losing insights when context resets.
3. **JSONL log**: Complete machine-readable history. Agent reads segment header + last N experiments on resume.
4. **Auto-resume hook**: On context limit detection, write checkpoint → end session → session hook creates new session with `autoresearch.md` as initial context.

**D6: TUI integration?**

Status bar slot showing experiment progress:
```
[Act] [opus] [$1.23] [42%] [5 turns] [exp: 8/12 +9.2%]
```

The `exp:` slot shows: experiments completed / total planned, cumulative improvement.

Breadcrumb trail shows current experiment phase:
```
observe → orient → [decide] → act → reflect → compound
                    ↑ hypothesis: "reduce context reserve from 8192 to 4096"
```

Expandable overlay (Ctrl+X or similar) shows experiment dashboard:
- Current segment, baseline, best result
- Last 5 experiments with hypothesis/delta/decision
- Ideas remaining

**D7: Phase gating for experiment tools?**

| Tool | Phases | Rationale |
|------|--------|-----------|
| `init_experiment` | Act | Creates experiment state, needs write access |
| `run_experiment` | Act | Executes benchmarks, may modify files |
| `log_experiment` | Act, Reflect | Log during Act, summarize during Reflect |

No experiment tools in Observe/Orient/Decide — those phases should analyze results, not create new experiments.

### What we're NOT building

- **Multi-agent experiment coordination** — Single-agent loop is enough for v1. Multi-agent (parallel experiments on different branches) is a v2 concern.
- **A/B testing framework** — This is optimization, not statistical testing. We're looking for improvements, not significance.
- **Custom benchmark infrastructure** — We use existing test suites, existing Skaffen sessions. The experiment runner just times and captures output.
- **UI for experiment management** — The TUI overlay is sufficient. No web dashboard needed.

## Architecture Summary

```
┌─────────────────────────────────────────────────┐
│ Clavain Skill: /autoresearch                    │
│ - Creates campaign docs (autoresearch.md)       │
│ - Generates initial ideas from analysis         │
│ - Sets up git branch                            │
│ - Starts the experiment loop                    │
│ - Handles context recovery / auto-resume        │
└──────────────────┬──────────────────────────────┘
                   │ drives
┌──────────────────▼──────────────────────────────┐
│ Skaffen Tools (internal/tool/)                  │
│ ┌──────────────┐ ┌──────────────┐ ┌───────────┐ │
│ │init_experiment│ │run_experiment│ │log_experiment│
│ └──────────────┘ └──────────────┘ └───────────┘ │
│                                                  │
│ JSONL: ~/.skaffen/experiments/{campaign}.jsonl    │
│ Git:   autoresearch/{campaign} branch            │
│ TUI:   status bar slot + overlay                 │
└──────────────────┬──────────────────────────────┘
                   │ feeds
┌──────────────────▼──────────────────────────────┐
│ Evidence Pipeline                                │
│ - Experiment events → evidence JSONL             │
│ - Aggregate in Compound phase                    │
│ - Orient injection: "last campaign improved X%"  │
└─────────────────────────────────────────────────┘
```

## Open Questions

1. **Campaign definition format:** Should campaigns be YAML files (structured, versionable) or SKILL.md sections (readable, inline)? Leaning YAML for machine readability.

2. **Metric extraction:** How does `run_experiment` extract the metric value from benchmark output? Options: regex pattern in campaign config, structured JSON output convention, or exit code + stdout parsing.

3. **Concurrent experiments:** If someone runs `/autoresearch` on routing while another session runs `/autoresearch` on TUI perf, they'd conflict on the same codebase. Do we need workspace isolation (worktrees)?

4. **Secondary metrics:** pi-autoresearch tracks secondary metrics (e.g., compile time alongside primary metric). Do we want this in v1?

5. **Interlab integration:** The existing `interverse/interlab/` module has mutation tracking infrastructure. Should autoresearch feed into interlab's mutation store, or maintain its own JSONL?

## Deliverables (Draft)

1. **Go tools** (`os/Skaffen/internal/tool/experiment/`):
   - `init_experiment.go` — InitExperimentTool
   - `run_experiment.go` — RunExperimentTool
   - `log_experiment.go` — LogExperimentTool
   - `store.go` — JSONL persistence with segment headers

2. **JSONL persistence** (`~/.skaffen/experiments/`):
   - Append-only JSONL with segment model
   - Crash recovery: read last segment header + experiments to reconstruct state

3. **Git integration** (`os/Skaffen/internal/tool/experiment/git.go`):
   - Branch creation/management
   - Auto-commit (keep) / auto-revert (discard)
   - Merge prompt on session end

4. **Clavain skill** (`os/Clavain/skills/autoresearch/`):
   - `SKILL.md` — Campaign setup, loop driver, context recovery
   - Template: `autoresearch.md` (living document)
   - Template: `autoresearch.ideas.md` (ideas backlog)

5. **TUI integration** (`os/Skaffen/internal/tui/`):
   - Status bar experiment slot
   - Experiment overlay (keyboard shortcut)

6. **Auto-resume** (`os/Clavain/hooks/`):
   - Context limit detection → checkpoint write → session restart
   - Session start hook: detect `autoresearch.md` → inject as context → resume loop

7. **Evidence bridge**:
   - Experiment events emitted to evidence JSONL
   - Compound phase aggregation includes experiment metrics

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Experiment modifies critical code, breaks build | Medium | High | Branch isolation + test suite gate before keep |
| Context limit hit mid-experiment | High | Medium | Checkpoint + living document + auto-resume |
| JSONL corruption on crash | Low | Medium | fsync after each write, segment recovery |
| Runaway loop (100+ experiments, high cost) | Medium | Medium | Budget limit in router + consecutive failure cap |
| Git conflicts when merging experiment branch | Low | Low | Single-file changes per experiment preferred |
