# PRD: Measure Accuracy Gap With and Without Composition Layer

**Bead:** iv-u74sq
**Date:** 2026-03-05
**Brainstorm:** docs/brainstorms/2026-03-05-accuracy-gap-measurement-brainstorm.md
**Approach:** Hybrid — fix instrumentation deployment bug + synthetic benchmark for directional signal

---

## Goal

Determine how much of the 18-point tool selection accuracy gap (74% with 49 plugins vs 92% with 5-7 native tools) the shallow composition layer closes, decomposed by gap category (discovery, sequencing, scale). This measurement gates `iv-mtf12` — "Let data determine plugin boundary decisions."

## Non-Goals

- Definitive statistical proof (follow-up bead with real instrumentation data)
- Testing moderate/deep composition approaches (this measures the shallow layer only)
- Benchmarking across multiple model families (Opus 4.6 only for now)

## Deliverables

### D1: Fix Interstat Hook Deployment Bug
Deploy the `PostToolUse:*` and `PostToolUseFailure` hooks that were written for iv-rttr5 but never published. This unblocks real data collection for all future sessions.

**Acceptance:** `SELECT COUNT(*) FROM tool_selection_events` returns >0 after a test session.

### D2: Synthetic Accuracy Benchmark
A repeatable benchmark of 15 tool selection tasks (5 per gap category) run with and without composition context. Produces a per-category accuracy delta.

**Acceptance:** A results table showing with/without accuracy per category and an overall delta, written to `docs/research/accuracy-gap-measurement-results.md`.

### D3: Gap Decomposition Analysis
Interpret the benchmark results against the R3 dialectic's three-band model. Determine: (a) what the composition layer closes, (b) what remains, (c) recommended next action for iv-mtf12.

**Acceptance:** Analysis section in the results doc with a clear recommendation: invest in moderate composition, wait for model improvements, or declare the gap acceptable.

## Architecture

### Hook Fix (D1)

The interstat plugin at `interverse/interstat/` has the hooks in source:
- `hooks/post-tool-all.sh` — records ALL tool calls (PostToolUse:*)
- `hooks/post-tool-failure.sh` — records failures with classification (PostToolUseFailure)
- `hooks/hooks.json` — source version includes these entries

The **installed** version at `~/.claude/plugins/cache/.../interstat/0.2.14/` is missing:
- The two hook script files
- The hooks.json entries for `PostToolUse:*` and `PostToolUseFailure`

Fix: republish interstat so the cache gets the complete hooks.json and script files.

### Benchmark (D2)

15 tasks across 3 categories, each run as a subagent with controlled context:

| Category | Tests | Composition Layer Feature Tested |
|---|---|---|
| Discovery (5) | Agent picks the right plugin for a clear need | Domain groups, curation groups |
| Sequencing (5) | Agent calls plugins in the right order | Sequencing hints (first/then) |
| Scale (5) | Agent picks correctly despite ambiguous prompts | Control — should show no improvement |

Two runs per task:
- **With:** `clavain-cli tool-surface` output injected in prompt
- **Without:** No composition context, only default tool descriptions

Scoring: binary (correct tool / correct order / both).

### Analysis (D3)

Expected outcomes and what they mean:

| Discovery Delta | Sequencing Delta | Scale Delta | Interpretation |
|---|---|---|---|
| High (>50%) | High (>50%) | Low (<20%) | Composition layer is working. Ship and monitor. |
| High | Low | Low | Discovery metadata works, sequencing hints don't. Invest in better hints or moderate composition. |
| Low | Low | Low | Composition layer doesn't help. Gap is mostly scale. Wait for model improvements. |
| High | High | High | Benchmark is poorly designed — scale tasks aren't truly ambiguous. Redesign. |

## Risks

1. **Synthetic bias:** Tasks designed around known plugin relationships may inflate discovery/sequencing scores. Mitigation: include tasks for plugins NOT in the composition YAML.
2. **Small sample:** 5 tasks per category is directional, not statistically significant. Mitigation: follow-up bead with real instrumentation data.
3. **Hook performance:** PostToolUse:* fires on EVERY tool call. Timeout is 5s but slow SQLite writes could add latency. Mitigation: the existing hook uses `|| true` on the INSERT — failures are silent.

## Success Criteria

- [ ] Interstat hooks deployed and collecting data
- [ ] Benchmark run with results documented
- [ ] iv-mtf12 has enough data to make a boundary decision (even if directional)
