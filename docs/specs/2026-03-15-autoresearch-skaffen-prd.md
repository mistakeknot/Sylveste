# PRD: Autoresearch — Autonomous Experiment Loop for Skaffen

**Bead:** projects-z6k
**Date:** 2026-03-15
**Status:** Draft
**Brainstorm:** `docs/brainstorms/2026-03-15-autoresearch-skaffen-brainstorm.md`

## Problem Statement

Skaffen has no systematic way to optimize itself. Manual iteration (tweak → run → eyeball → decide) is slow, lossy, and doesn't produce structured records of what was tried. We need an autonomous experiment loop where an agent can run 50+ experiments without human intervention, keeping improvements and reverting failures.

## Goals

1. **Domain-agnostic experiment infrastructure** — Three built-in Skaffen tools (init/run/log) that any optimization campaign can use
2. **Structured persistence** — JSONL experiment logs with segment headers for crash recovery, bridged to interlab for cross-campaign analysis
3. **Git-as-undo** — Branch/worktree isolation per campaign, auto-commit on keep, auto-revert on discard
4. **Context recovery** — Living document + ideas backlog that let a fresh agent continue where the last one left off
5. **TUI visibility** — Status bar slot and overlay showing experiment progress in real-time

## Non-Goals

- Multi-agent parallel experimentation (v2)
- A/B statistical testing framework
- Custom benchmark infrastructure (uses existing test suites)
- Web dashboard or experiment management UI

## User Stories

**U1: Skaffen developer optimizing routing.**
"I want to run `/autoresearch` with a campaign YAML that targets `cost_per_turn`, have the agent iterate through ideas, and wake up to a summary of what worked."

**U2: Agent continuing after context limit.**
"When the agent hits context limits during a 50-experiment campaign, I want it to checkpoint, restart, read the living document, and resume from where it left off."

**U3: Parallel campaigns on independent subsystems.**
"I want to run a routing optimization campaign and a TUI performance campaign simultaneously without git conflicts."

## Architecture

### Two-Layer Design

**Layer 1: Infra** (Skaffen `internal/tool/experiment/`)
- `InitExperimentTool` — Create experiment with hypothesis, expected metric direction
- `RunExperimentTool` — Execute benchmark, capture output, extract metrics via regex
- `LogExperimentTool` — Record result + decision (keep/discard/investigate), manage git state

**Layer 2: Campaign** (Clavain skill `/autoresearch`)
- Creates session documents (autoresearch.md, autoresearch.ideas.md)
- Loads campaign YAML, generates initial ideas from code analysis
- Drives the experiment loop using Layer 1 tools
- Handles context recovery and auto-resume

### Campaign YAML Schema

```yaml
name: string                      # Campaign identifier (kebab-case)
metric:
  name: string                    # Primary metric name
  unit: string                    # Display unit (usd, ms, %, count)
  direction: minimize | maximize  # Optimization direction
  baseline: number                # Starting value
secondary_metrics:                # Up to 3 secondary metrics
  - name: string
    direction: minimize | maximize
    baseline: number
    regression_threshold: number  # Max allowed regression
benchmark:
  command: string                 # Shell command to run
  metric_pattern: string          # Regex with capture group for metric value
  secondary_patterns:             # Regexes for secondary metrics
    metric_name: string
  timeout: duration               # Max benchmark runtime (default: 120s)
  working_dir: string             # Optional: override CWD for benchmark
git:
  worktree: bool                  # Use git worktree isolation (default: true)
  auto_commit: bool               # Auto-commit on keep (default: true)
budget:
  max_experiments: int            # Max experiments per session (default: 50)
  max_consecutive_failures: int   # Stop after N failures (default: 5)
  token_budget: int               # Optional: override session token budget
ideas:                            # Initial experiment ideas
  - string
```

Location: `~/.skaffen/campaigns/{name}.yaml` or project-local `.skaffen/campaigns/{name}.yaml`

### Persistence

**Experiment JSONL** (`~/.skaffen/experiments/{campaign}.jsonl`):

```jsonl
{"type":"segment","id":"seg-001","campaign":"routing-opt","metric":"cost_per_turn","baseline":0.42,"started_at":"...","session_id":"..."}
{"type":"experiment","segment":"seg-001","id":"exp-001","hypothesis":"...","status":"completed","metric_before":0.42,"metric_after":0.38,"delta":-0.04,"secondary":{"test_pass_rate":{"before":0.98,"after":0.98}},"decision":"keep","git_sha":"abc123","duration_ms":15000}
```

Record types:
- `segment` — Campaign session start, records baseline and config
- `experiment` — Individual experiment with metrics, decision, git state
- `summary` — Written at segment end with aggregate statistics

**Interlab bridge:** On `keep` decisions, emit `ic events record --source=autoresearch --type=mutation_kept` for cross-campaign analysis.

### Git Integration

- **Worktree isolation** (default): `git worktree add /tmp/autoresearch-{campaign} -b autoresearch/{campaign}`
- **Keep:** `git add -A && git commit -m "experiment({campaign}): {hypothesis} [{delta}]"` in worktree
- **Discard:** `git checkout -- .` in worktree (revert to last commit)
- **Session end:** Prompt user to merge worktree branch to main if improvements accumulated
- **Cleanup:** `git worktree remove` on campaign completion or explicit stop
- **Safety:** Never auto-merge to main. Never force-push. Never `git add -A` outside worktree.

### Context Recovery

1. **Living document** (`autoresearch.md` in project root):
   - Updated after each experiment
   - Contains: campaign goal, current best, last 10 experiments, active hypothesis, ideas remaining
   - Fresh agent reads this to continue

2. **Ideas backlog** (`autoresearch.ideas.md`):
   - Append-only
   - New ideas discovered during experiments
   - Survives context resets

3. **JSONL log:** Machine-readable complete history. Agent reads segment header + recent experiments on resume.

4. **Clavain checkpoint:** `checkpoint-write` after each experiment for sprint-level resume.

### TUI Integration

**Status bar slot:**
```
[exp: 8/50 +9.2%]
```
Format: `exp: {completed}/{max} {cumulative_delta}{unit}`

**Phase gating:**
| Tool | Allowed Phases | Rationale |
|------|---------------|-----------|
| `init_experiment` | Act | Creates experiment state |
| `run_experiment` | Act | Executes benchmarks |
| `log_experiment` | Act, Reflect | Record during Act, summarize during Reflect |

### Loop Termination Conditions

1. Ideas exhausted (all ideas tried, no new ones generated)
2. Token budget exceeded (router budget check)
3. Context window > 80% (graceful checkpoint + resume)
4. `max_experiments` reached
5. `max_consecutive_failures` reached
6. User interrupt (Ctrl+C → graceful shutdown, preserve state)

## Deliverables

### D1: Experiment Tools (Go)
- `os/Skaffen/internal/tool/experiment/init.go` — InitExperimentTool
- `os/Skaffen/internal/tool/experiment/run.go` — RunExperimentTool
- `os/Skaffen/internal/tool/experiment/log.go` — LogExperimentTool
- `os/Skaffen/internal/tool/experiment/store.go` — JSONL store with segment model
- `os/Skaffen/internal/tool/experiment/git.go` — Worktree + commit/revert operations
- `os/Skaffen/internal/tool/experiment/campaign.go` — Campaign YAML parser
- Tests for all of the above

### D2: Tool Registration
- Register experiment tools in `internal/tool/builtin.go` with Act phase gating
- `log_experiment` additionally gated to Reflect phase

### D3: TUI Integration
- Status bar experiment slot in `internal/tui/status.go`
- Experiment state tracking in `internal/tui/app.go`

### D4: Clavain Skill
- `os/Clavain/skills/autoresearch/SKILL.md` — Loop driver with context recovery
- `os/Clavain/skills/autoresearch/templates/autoresearch.md` — Living document template
- `os/Clavain/skills/autoresearch/templates/autoresearch.ideas.md` — Ideas backlog template

### D5: Evidence Bridge
- Experiment events emitted to Skaffen evidence JSONL
- Interlab mutation bridge on keep decisions

## Success Criteria

1. An agent can run 20+ experiments in a single campaign without human intervention
2. Context recovery works: after context limit, new session resumes from living document
3. Git state is always clean: no orphaned worktrees, no uncommitted changes on crash
4. Secondary metrics prevent tunnel-vision: improving primary at cost of secondary is rejected
5. Campaign YAML is sufficient to define any optimization target in the Skaffen codebase

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Experiment breaks build | Test suite gate in `run_experiment` before keep decision |
| Runaway cost | Budget limits (token + experiment count + consecutive failures) |
| JSONL corruption | fsync after each write, segment-based recovery |
| Worktree accumulation | Cleanup on campaign end + periodic sweep |
| Context limit mid-experiment | Checkpoint after log_experiment, never mid-experiment |
