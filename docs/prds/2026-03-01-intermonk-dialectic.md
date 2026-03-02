# PRD: intermonk — Hegelian dialectic reasoning plugin

**Bead:** iv-x7rlv
**Date:** 2026-03-01
**Status:** Draft
**Source:** [hegelian-dialectic-skill](https://github.com/KyleAMathews/hegelian-dialectic-skill) (MIT, Kyle Mathews)

## Problem

Hard problems have genuine contradictions that can't be resolved by "looking at both sides." The bottleneck isn't intelligence — it's *belief.* Once you commit to a position, you can't simultaneously hold its negation at full strength. You hedge, steelman weakly, and unconsciously bias comparisons. This applies to architectural decisions, product strategy, personal decisions, and any domain where the tradeoffs are unclear.

Existing tools (brainstorm, flux-drive review) analyze objectively. None provide the subjective commitment needed to expose deep structural contradictions.

## Solution

A new Interverse plugin (`intermonk`) providing a single skill (`dialectic`) that orchestrates structured dialectical reasoning through "Electric Monks" — subagents that fully believe opposing positions. The orchestrator performs structural contradiction analysis (determinate negation, Boydian decomposition) and produces synthesis (Aufhebung) that transforms the question itself.

Adopted from Kyle Mathews' 1100-line SKILL.md with mechanical adaptations for Claude Code's Agent tool.

## Features

### F1: Orchestrator skill (`dialectic`)

The core skill that drives the 7-phase process:

1. **Elenctic interview** — Socratic probing to surface hidden assumptions, identify the deepest contradiction, calibrate monk roles to user's belief burden
2. **Prompt calibration** — generate monk prompts with framing corrections to prevent degenerate framings, anti-hedging instructions, targeted research directives
3. **Spawn monks** — two Agent tool subagents in parallel, each fully committed to one position. Decorrelation check after both complete.
4. **Determinate negation** — orchestrator analyzes internal tensions (self-sublation), surface contradiction, shared assumptions, hidden question, Boydian decomposition (shatter → scatter → cross-domain connect)
5. **Sublation** — synthesis that cancels, preserves, and elevates. Abduction test: does it make the original contradiction *predictable*?
6. **Validation** — monks evaluate (elevated or defeated?), hostile auditor attacks from fresh eyes
7. **Recursion** — synthesis generates new contradictions; propose 2-4 directions, user chooses; repeat

**Output:** All artifacts saved to `dialectics/[topic-name]/` — context_briefing.md, monk_a_output.md, monk_b_output.md, determinate_negation.md, sublation.md, dialectic_queue.md.

### F2: Reference material (companion files)

Supporting documentation extracted from the source to keep the main skill focused:

- `references/belief-burdens.md` — belief-burden typology for calibrating monks to user's cognitive style
- `references/theory.md` — full theoretical foundations (Rao, Hegel, Boyd, Peirce, Pollock, Galinsky, etc.)
- `references/worked-examples.md` — example dialectics showing prompt craft, recursive depth
- `references/auditor-prompt.md` — hostile auditor prompt template

### F3: Plugin scaffolding

Standard Interverse plugin structure:
- README.md, CLAUDE.md, AGENTS.md, PHILOSOPHY.md, LICENSE (MIT)
- Structural test suite (pytest)
- bump-version.sh

## Non-goals (v1)

- MCP server (no state to serve)
- Hooks (no events to intercept)
- Multiple skills (one skill is the entire plugin)
- Auto-recursion (always user-driven)
- Heterogeneous model auto-detection (document as option, don't force)
- Integration with interflux review (suggest, don't auto-invoke)

## Adaptation from Source

| Source pattern | Interverse adaptation |
|---|---|
| `claude -p \| > file.md` | Agent tool → orchestrator writes returned text to file |
| `--model` flag | `model` parameter on Agent tool |
| Shell background jobs | Multiple Agent calls with `run_in_background: true` |
| Session resume for validation | Agent `resume` parameter + fallback summary |
| `dialectics/` at working dir | Same — project-root convention |
| 1100-line monolithic SKILL.md | ~650 line SKILL.md + ~300 lines in `references/` companion files |

## Success Criteria

- [ ] Plugin passes structural tests (`cd tests && uv run pytest -q`)
- [ ] Skill invocable via `/intermonk:dialectic "topic"`
- [ ] Monks spawn as parallel Agent subagents with full anti-hedging
- [ ] All 7 phases produce file artifacts in `dialectics/[topic]/`
- [ ] Decorrelation check catches shallow divergence
- [ ] Hostile auditor spawns with correct isolation (no orchestrator analysis)
- [ ] Recursion queue persists across rounds
- [ ] Original MIT license attributed

## Estimated Scope

- 1 new plugin directory with ~15 files
- ~950 lines of skill + reference content (adapted from 1100-line source)
- ~200 lines of scaffolding (plugin.json, CLAUDE.md, AGENTS.md, tests, etc.)
- No external dependencies
