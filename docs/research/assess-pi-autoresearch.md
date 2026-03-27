# Assessment: pi-autoresearch

**Repo:** https://github.com/davebcn87/pi-autoresearch
**Date:** 2026-03-12
**Author:** davebcn87
**License:** MIT
**Language:** TypeScript (single-file extension + SKILL.md)
**LOC:** ~1,450 (extension index.ts) + 83 lines (SKILL.md)
**Platform:** [pi](https://github.com/mariozechner/pi-ai) (Mario Zechner's coding agent)

## What It Is

An autonomous experiment loop for pi — the Karpathy-inspired "autoresearch" pattern where an AI agent continuously:

1. Makes a code change targeting a metric (test speed, bundle size, LLM val_bpb, etc.)
2. Runs a benchmark command
3. Measures the result
4. Keeps the change if improved, reverts if not
5. Repeats forever until interrupted

Think: hill-climbing optimization driven by an LLM that reads code, proposes changes, measures outcomes, and accumulates institutional knowledge about what has been tried.

## Architecture (Excellent)

### Two-layer separation

| Layer | Role | How |
|-------|------|-----|
| **Extension** (infra) | Domain-agnostic experiment loop machinery | 3 tools + TUI widget + dashboard + JSONL persistence |
| **Skill** (domain) | What to optimize, how to measure it | SKILL.md prompt that creates autoresearch.md + autoresearch.sh |

This is the cleanest architecture in the repo. The extension knows nothing about what you are optimizing — it just runs commands, times them, and records results. The skill encodes domain knowledge (which files to edit, what metric to extract, what "better" means). One extension serves unlimited domains.

### Three tools

| Tool | Purpose |
|------|---------|
| init_experiment | One-time config: name, metric, unit, direction (lower/higher) |
| run_experiment | Shell execution with wall-clock timing, exit code detection, output capture |
| log_experiment | Record result (keep/discard/crash), auto-commit on keep, auto-revert on discard |

### Persistence: append-only JSONL

```
autoresearch.jsonl — one JSON line per experiment (config headers + result entries)
autoresearch.md   — living document: objective, what has been tried, dead ends, key wins
autoresearch.sh   — benchmark script that outputs METRIC name=number lines
```

**Segment model:** Each init_experiment call inserts a config header in the JSONL and increments a segment counter. All stats (baseline, best metric, delta %) are scoped to the current segment. This allows re-targeting the same session to a different metric/workload without losing history.

**Crash recovery:** A fresh agent with no memory can read autoresearch.jsonl + autoresearch.md and continue exactly where the last session left off. The SKILL.md explicitly instructs: "A fresh agent with no context should be able to read this file and run the loop effectively."

### TUI integration

- **Status widget:** Always-visible one-liner above the editor: 🔬 autoresearch 12 runs 8 kept | best: 42.3s (-15.2%)
- **Expanded dashboard (Ctrl+X):** Inline table with all runs, deltas, secondary metrics
- **Fullscreen overlay (Ctrl+Shift+X):** Scrollable, vim-keybindings (j/k/g/G), spinner for running experiments

### Auto-resume on context limit

The agent_end hook detects when the agent stops (likely context limit hit), checks that experiments actually ran this session (not a manual stop), and auto-sends a resume message. Rate-limited to once per 5 minutes. Also checks for autoresearch.ideas.md backlog.

### Secondary metrics

Tracks additional metrics alongside the primary optimization target. Enforces consistency: once you start tracking compile_us and render_us, every subsequent log_experiment must provide them (or use force: true to add new ones). Auto-infers units from metric names (_us -> "us", _ms -> "ms").

## Key Design Decisions

### 1. "NEVER STOP" loop philosophy

The SKILL.md is emphatic: "LOOP FOREVER. Never ask 'should I continue?' — the user expects autonomous work." This is the core UX bet — the user walks away and comes back to find 50 experiments completed. The agent is explicitly instructed to handle user interrupts gracefully (finish current experiment first, then incorporate feedback).

### 2. Git-integrated experiment tracking

- keep -> auto-commits with Result: {status, metric, ...} trailer
- discard/crash -> git checkout -- . to revert
- Each experiment session runs on autoresearch/<goal>-<date> branch

This is clever: git becomes the undo mechanism, and the commit history is a readable log of successful optimizations.

### 3. Ideas backlog

When the agent discovers promising but complex optimizations it won't pursue immediately, it appends them to autoresearch.ideas.md. On resume, it checks this file, prunes stale entries, and experiments with the rest. This prevents good ideas from being lost across context resets.

### 4. User interrupts during experiments

"If the user sends a message while an experiment is running, finish the current run_experiment + log_experiment cycle first, then incorporate their feedback in the next iteration." Prevents partial experiment state.

## Code Quality

**Strengths:**
- Well-structured single file with clear section boundaries
- TypeScript types for all state (ExperimentState, ExperimentResult, RunDetails)
- State reconstruction from JSONL handles config headers, segments, and malformed lines gracefully
- Dashboard rendering is a pure function (renderDashboardLines) separated from UI wiring
- Proper truncation of output (80 tail lines, 40KB cap) to avoid context bloat
- Secondary metric consistency validation prevents data drift

**Weaknesses/risks:**
- No tests — single-file extension with ~1,450 lines and no test suite
- reconstructState has a fallback path that reads session history (backward compat) — could be slow with large session trees
- Auto-resume via sendUserMessage could create infinite loops if the agent keeps hitting context limits immediately
- git add -A in log_experiment is aggressive — could commit unintended files
- No rate limiting on run_experiment — a buggy benchmark that exits instantly could create a tight loop

## Relevance to Sylveste

### Direct applicability: **Medium-High**

The autoresearch pattern maps well to several Sylveste scenarios:

| Sylveste Use Case | Autoresearch Analog |
|-----------------|---------------------|
| Skaffen model routing optimization | Metric: latency/cost per phase, command: benchmark suite |
| TUI render performance | Metric: frame time, command: masaq benchmarks |
| Token efficiency optimization | Metric: tokens/task, command: controlled coding tasks |
| Plugin load time optimization | Metric: startup ms, command: time skaffen --dry-run |

### What we could port

1. **The loop pattern itself** — init/run/log/decide/repeat with JSONL persistence. This is ~100 lines of core logic independent of the pi platform.
2. **The SKILL.md template** — the "autoresearch.md as living document" pattern is excellent for any optimization campaign.
3. **Git-as-undo** — branch-based experiment isolation with auto-commit/revert.
4. **Ideas backlog** — preventing idea loss across context resets.

### What does not transfer

- The pi-specific TUI integration (widget, overlay, ctx.ui.custom)
- The pi.exec() process execution model
- The extension/skill separation (pi-specific abstraction)

### Implementation path

For Skaffen/Interverse, this would be:
- A **Clavain skill** (/autoresearch) that creates the session documents and starts the loop
- A **Skaffen built-in tool** or **MCP tool** for run_experiment/log_experiment
- JSONL persistence in the project directory (already our pattern with beads)
- No TUI widget needed initially — the Skaffen status bar could show experiment progress

## Verdict: **inspire-only**

The architecture and UX patterns are excellent and worth studying. The actual code is pi-platform-specific (TypeScript, pi extension API, pi TUI primitives) and cannot be adopted directly. The transferable value is in the **design patterns**:

1. Domain-agnostic infra + domain-specific skill separation
2. Append-only JSONL with segment headers for crash recovery
3. "Never stop" autonomous loop philosophy with graceful interrupt handling
4. Git-integrated keep/revert decision flow
5. Ideas backlog to prevent knowledge loss across context resets
6. Living document (autoresearch.md) as the primary context for fresh agents

These patterns could inspire a Sylveste-native autoresearch implementation if we need one. Not a near-term priority — most relevant when we start doing systematic optimization campaigns (model routing, token efficiency, TUI performance).
