---
artifact_type: prd
bead: Demarch-ttf
stage: design
---
# PRD: Plans-as-Prompts — Structured Verification for Clavain Plans

## Problem

Clavain plans have prose-embedded verification ("Expected: PASS") that agents can't distinguish from implementation steps, no structured way to confirm a plan achieved its goal, and no link from plan tasks back to PRD features.

## Solution

Add three optional, backward-compatible extensions to the plan format: per-task `<verify>` blocks with machine-parseable run/expect pairs, plan-level `## Must-Haves` for goal-backward validation, and `requirements` frontmatter linking tasks to PRD feature IDs.

## Features

### F1: Structured Verify Blocks
**What:** Add `<verify>` XML blocks at the end of each plan task with run/expect pairs that the executor can parse and run automatically after implementation.
**Acceptance criteria:**
- [ ] writing-plans SKILL.md task template includes `<verify>` block with run/expect syntax
- [ ] executing-plans SKILL.md parses `<verify>` blocks after each task completes
- [ ] Verify failure triggers deviation Rule 1 (auto-fix, retry task)
- [ ] Missing `<verify>` block is gracefully skipped (backward compatible)
- [ ] Verify supports two matchers: `exit 0` (exit code) and `contains "string"` (output substring)

### F2: Plan-Level Must-Haves
**What:** Add a `## Must-Haves` section to plans with three categories (truths, artifacts, key_links) validated after all tasks complete.
**Acceptance criteria:**
- [ ] writing-plans SKILL.md includes Must-Haves section template with guidance for goal-backward derivation
- [ ] executing-plans SKILL.md validates must-haves after final task: checks artifacts exist, key_links are present in source
- [ ] Must-have validation results appear in the batch completion report
- [ ] Missing Must-Haves section is gracefully skipped (backward compatible)

### F3: Requirement Traceability
**What:** Add `requirements` field to plan YAML frontmatter linking to PRD feature IDs (F1, F2, etc.).
**Acceptance criteria:**
- [ ] writing-plans SKILL.md frontmatter template includes `requirements` field
- [ ] writing-plans guidance explains using PRD feature IDs (not a separate namespace)
- [ ] Field is optional — omitting it doesn't break anything

## Non-goals

- Waves in plan markdown (already handled by `.exec.yaml` manifests)
- XML task wrapping (`<task>` elements — markdown headers are sufficient)
- Per-task must_haves (plan-level + per-task verify covers this)
- Changes to `.exec.yaml` format
- Automated requirement coverage analysis (future iteration)

## Dependencies

- `os/clavain/skills/writing-plans/SKILL.md` — plan generation skill
- `os/clavain/skills/executing-plans/SKILL.md` — plan execution skill
- No external dependencies — purely skill file changes

## Open Questions

None — all three open questions from brainstorm resolved:
1. Verify format: YAML-in-markdown (`- run: ... expect: ...`) — parseable and readable enough
2. Must-have validation timing: after all tasks complete (simpler, per-task verify catches immediate failures)
3. Backward compatibility: yes, all three features are opt-in with graceful skip
