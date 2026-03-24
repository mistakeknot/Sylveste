---
artifact_type: brainstorm
bead: projects-z6k
stage: discover
---
# interlab: Autonomous Experiment Loop for Demarch

## What We're Building

A Demarch-native autonomous experiment loop that lets an agent continuously optimize a metric by editing code, running a benchmark, measuring the result, and keeping or reverting the change. Inspired by pi-autoresearch (assessed in docs/research/assess-pi-autoresearch.md, verdict: inspire-only).

**Two components:**
1. **interlab** (`interverse/interlab/`) — Go MCP server providing 3 stateless tools (`init_experiment`, `run_experiment`, `log_experiment`) with JSONL persistence, git operations, and ic events bridge
2. **Clavain `/autoresearch` skill** (`os/Clavain/skills/autoresearch/SKILL.md`) — Loop protocol, living-document pattern, ideas backlog, domain-specific orchestration

**Key property:** The LLM drives the loop (decides what code to change, when to keep/discard, when ideas are exhausted). The plugin provides stateless tools that reconstruct state from JSONL on each call, plus guards that pi-autoresearch lacks (circuit breaker, budget cap, path-scoped git staging).

## Why This Approach

### Architecture: Clavain skill + Interverse MCP plugin

Matches PHILOSOPHY.md's mechanism/policy separation:
- **Mechanism** (interlab plugin): Run benchmarks, record results, manage JSONL, git commit/revert. Domain-agnostic — works for any metric.
- **Policy** (Clavain skill): What to optimize, loop philosophy ("NEVER STOP"), living document template, ideas backlog rules. Domain-specific — different skills for different optimization targets.

This preserves "one extension, unlimited domains" — the same interlab plugin serves TUI perf optimization, token efficiency tuning, model routing calibration, etc.

### Go MCP server (not skills + shell)

- Precise timing of benchmark execution (Go's time.Now vs shell date overhead)
- Structured types for experiment state (ExperimentConfig, ExperimentResult)
- Concurrent-safe JSONL writes (mutex-protected)
- Clean ic events bridge with typed payloads
- Pattern: follows interlock's plugin structure

### LLM-driven loop with plugin guards

Matches pi-autoresearch's proven design. The intelligence is in the SKILL.md and the LLM's reasoning, not in the plugin. The plugin is "dumb tools + smart guards":
- State reconstructed from JSONL on each tool call (crash-recovery for free)
- Guards added where pi-autoresearch has known weaknesses: consecutive-crash circuit breaker, experiment budget cap, path-scoped git staging, secondary metric consistency

## Key Decisions

### 1. All three P0 blockers solved in v1

From the flux-drive synthesis (os/Skaffen/.claude/flux-drive-output/SYNTHESIS.md):

- **Path-scoped git staging:** interlab controls its own git operations. Never `git add -A` — always `git add <specific files>` scoped to the experiment's declared working directory. The Clavain skill declares "Files in Scope" and interlab enforces it.
- **Cross-session circuit breaker:** Built into the plugin. Configurable limits: max experiments (default 50), max consecutive crashes (default 3), max consecutive no-improvement (default 10). `run_experiment` returns an error when any limit is hit.
- **Structured experiment_outcome events:** `log_experiment` emits typed events via `ic events record --source=interlab --type=experiment_outcome` with fields: metric_name, metric_value, baseline_value, delta_pct, direction, decision, secondary_metrics.

### 2. Experiment branches (documented exception to trunk-based development)

interlab creates short-lived `interlab/<goal>-<YYYYMMDD>` branches at campaign start. On `keep`, commits with structured trailers (metric values, bead ID, run ID). On campaign end, squash-merges into main. On abandon, deletes the branch.

This is a documented exception in the Clavain skill — experiment branches are ephemeral working state, not feature branches.

### 3. Self-hosting dogfood as success criteria

interlab's first campaign optimizes itself — e.g., JSONL write throughput, state reconstruction latency, or plugin startup time. This proves the loop works end-to-end and produces a real living document with real experiment history.

### 4. Stateless tools with file-based state

No server-side state machine. Each tool call reads `interlab.jsonl` to reconstruct current state (segment, run count, best metric, crash count). This gives crash recovery for free — a fresh agent can continue exactly where the last one left off by reading the JSONL + living document.

## Three-Tool Interface

### init_experiment

**Input:** name, metric_name, metric_unit, direction (lower_is_better / higher_is_better), benchmark_command, working_directory, files_in_scope[]
**Effect:** Writes config header to interlab.jsonl, creates experiment branch, increments segment counter
**Output:** segment_id, branch_name

### run_experiment

**Input:** (none — reads config from current segment)
**Effect:** Executes benchmark_command, captures stdout/stderr, measures wall-clock duration
**Guards:** Checks circuit breaker (crash count, experiment count, budget). Returns error if tripped.
**Output:** exit_code, stdout (truncated), stderr (truncated), duration_ms, metrics (parsed from METRIC name=value lines in stdout)

### log_experiment

**Input:** decision (keep/discard/crash), description, metrics (secondary), notes
**Effect on keep:** `git add <files_in_scope>` + commit with structured message + trailers. Append result to JSONL. Emit ic event.
**Effect on discard:** `git checkout -- <files_in_scope>`. Append result to JSONL. Emit ic event.
**Effect on crash:** Same as discard + increment crash counter. Append result to JSONL.
**Guards:** Enforces secondary metric consistency (once declared, must be provided). Refuses if no preceding run_experiment.

## Living Document Pattern

The Clavain skill instructs the agent to create and maintain `interlab.md`:

```
# interlab: <goal>

## Objective
<what we're optimizing and why>

## Metrics
- **Primary**: <name> (<unit>, direction)
- **Secondary**: <names>

## How to Run
`./interlab.sh` — outputs METRIC name=value lines

## Files in Scope
<files the agent may modify>

## Constraints
<hard rules: tests must pass, no new deps, etc.>

## What's Been Tried
<updated as experiments accumulate — key wins, dead ends, insights>
```

Split into two artifacts per flux-drive recommendation:
- **interlab.md** — living document for fresh agents (C5 session-context, regenerable)
- **interlab-learnings.md** — validated insights with provenance (C2 curated narrative, durable)

## Ideas Backlog

`interlab.ideas.md` — lightweight holding pen for promising-but-not-yet-pursued optimizations. Pruned on resume. Each entry has provenance (which session proposed it). Treated as C2 sub-type with experiment-validated promotion.

## Resolved Questions

1. **JSONL location:** Project-local (`./interlab.jsonl`). Simple, visible, version-controllable. Cross-project analytics via ic events bridge (structured events emitted on every log_experiment).

2. **Benchmark script convention:** Accept both. init_experiment takes a benchmark_command string. The Clavain skill recommends creating `interlab.sh` for complex benchmarks, but simple commands work inline. The plugin just shells out.

3. **Secondary metrics v1 scope:** Enforce in v1. ~20 lines. Once secondary metrics are declared, every subsequent log_experiment must provide them. Allow `force: true` override for adding new metrics mid-campaign.

4. **Auto-resume v1 scope:** SessionStart hook detects active interlab.jsonl with an active segment. If found, injects system prompt: "Active interlab campaign detected for <goal>. Read interlab.md and resume." Detection + prompt only — no auto-spawning.

5. **Branch naming with run_id:** Create an `ic run` at campaign start via init_experiment. Branch name derived from run ID: `interlab/<run_id>`. Events attributed to run_id. Closes the attribution chain.

## Prior Art

- **pi-autoresearch** (docs/research/assess-pi-autoresearch.md) — inspire-only, TypeScript, pi-platform-specific. Transferable patterns: 3-tool decomposition, JSONL segment model, living document, ideas backlog, git-as-undo.
- **Flux-drive synthesis** (os/Skaffen/.claude/flux-drive-output/SYNTHESIS.md) — 5-agent review with 20 findings covering OODARC mapping, flywheel integration, safety, implementation path, and Orient/Compound gaps.
- **interlock** (interverse/interlock/) — Reference Go MCP plugin for structure, plugin.json, and ic bridge patterns.
- **interstat** (interverse/interstat/) — Reference for JSONL persistence and metrics tracking patterns.
