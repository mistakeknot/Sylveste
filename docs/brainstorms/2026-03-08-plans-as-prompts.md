---
artifact_type: brainstorm
bead: Demarch-ttf
---
# Plans-as-Prompts — Structured Verification for Clavain Plans

**Bead:** Demarch-ttf
**Date:** 2026-03-08

## Problem Statement

Clavain plans are prose-driven with bite-sized steps, but lack machine-parseable verification criteria. When an executor agent finishes a task, the only signal is "I did it" — there's no structured way to confirm the task actually achieved its goal. This creates three gaps:

1. **No automated verification**: Expected outputs are embedded in prose ("Expected: PASS") but not parseable by the executing-plans skill or orchestrator
2. **No goal-backward validation**: Plans list what to *do* but not what must be *true* when done — no `must_haves` equivalent
3. **No requirement traceability**: No link from plan tasks back to PRD features or roadmap items

## What Already Works (Don't Break)

Before designing additions, inventory what Clavain already does well:

### Prose plan format (KEEP)
- Bite-sized 2-5 minute steps with exact commands and expected output
- TDD workflow: failing test → implementation → passing test → commit
- Exact file paths with line ranges
- Code blocks with complete implementations (not "add validation")

### `.exec.yaml` manifests (KEEP)
- Dependency-driven orchestration with stages and task IDs
- Wave breakdown is already handled here (not in the plan markdown)
- `depends`, `files`, `tier` fields for dispatch routing
- Python orchestrator (`orchestrate.py`) reads these

### Deviation rules (KEEP)
- Rules 1-4 for auto-fix vs. ask-for-permission
- Analysis paralysis guard (5+ reads without writes)
- Fix attempt limit (3 per task)

### Execution handoff (KEEP)
- 4 modes: Subagent-Driven, Parallel Session, Codex Delegation, Orchestrated
- AskUserQuestion-based selection with plan-specific recommendations

## What's Missing (Add)

### M1: Structured verification blocks

Current state: "Run: `pytest tests/path.py -v` / Expected: PASS" is prose inside a step. The executor can't distinguish verification from implementation.

Proposed: Add `<verify>` blocks at the end of each task that are machine-parseable:

```markdown
### Task 1: Add user validation

**Files:**
- Modify: `src/models/user.py:45-60`
- Test: `tests/models/test_user.py`

**Step 1:** Write the failing test
[... prose steps as before ...]

**Step 5:** Commit

<verify>
- run: `pytest tests/models/test_user.py -v`
  expect: exit 0
- run: `python -c "from src.models.user import validate_email; print(validate_email('bad'))"`
  expect: contains "invalid"
</verify>
```

**Key design choice**: `<verify>` goes at the *end* of the task (after all steps), not inline. This keeps prose steps readable while giving the executor a single verification section to parse after implementation.

### M2: Must-haves (goal-backward validation)

Current state: Plans have a Goal line but no structured list of what must be *true* when the entire plan is done.

Proposed: Add a `## Must-Haves` section after the header, before tasks:

```markdown
## Must-Haves

**Truths** (observable behaviors):
- Users with invalid emails cannot register
- Existing users can update their email with validation
- API returns 422 with field-level errors for invalid input

**Artifacts** (files that must exist with exports):
- `src/models/user.py` exports `validate_email`, `validate_username`
- `tests/models/test_user.py` has ≥3 test cases per validator

**Key Links** (critical wiring):
- Registration endpoint calls `validate_email` before `create_user`
- Update endpoint calls validators before `save`
```

**Key design choice**: Must-haves are plan-level, not task-level. They describe the *outcome* of the entire plan, which is more useful for post-execution verification than per-task checks.

### M3: Requirement traceability

Current state: Plans reference a bead ID but not specific PRD features.

Proposed: Add `requirements` to the YAML frontmatter:

```yaml
---
artifact_type: plan
bead: Demarch-xyz
stage: design
requirements:
  - F1: User validation
  - F3: Error response format
---
```

**Key design choice**: Reference feature IDs from the PRD (F1, F2, etc.) rather than inventing a separate requirement ID namespace. This keeps it simple — PRDs already have numbered features from `/strategy`.

## What NOT to Add

### Waves in plan markdown (SKIP)
The bead description mentions "wave (int, 1-indexed), depends_on (plan IDs for parallel dispatch)". But Clavain already handles this via `.exec.yaml` manifests. Adding waves to both the markdown AND the manifest would create a sync problem. **Keep waves in `.exec.yaml` only.**

### XML task wrapping (SKIP)
GSD wraps tasks in `<task type="auto"><name>...</name><action>...</action></task>`. Clavain's `### Task N:` markdown headers are sufficient — they're already parseable by the executor. XML wrapping would make plans harder to read and write without meaningful gains.

### Per-task must_haves (SKIP)
The `<verify>` block per task is enough. Plan-level must_haves cover the goal-backward validation. Per-task must_haves would be redundant with `<verify>`.

## Implementation Scope

### Changes to `writing-plans/SKILL.md`
1. Add `## Must-Haves` section to plan document header template (after Prior Learnings, before first task)
2. Add `<verify>` block to task template (after last step, before next task)
3. Add `requirements` field to YAML frontmatter template
4. Add guidance for deriving must-haves using goal-backward methodology (3 categories: truths, artifacts, key_links)
5. Add guidance for writing verify blocks (run/expect pairs, exit codes, string matching)

### Changes to `executing-plans/SKILL.md`
1. After each task completes, parse and run `<verify>` block if present
2. Treat verify failure as a deviation Rule 1 (auto-fix bug) — retry the task, not just the verify
3. After all tasks complete, validate plan-level must-haves (check truths are observable, artifacts exist, key_links are wired)
4. Report must-have validation results in the batch report

### Changes to `.exec.yaml` format (NONE)
No changes needed — waves and dependencies stay in the manifest.

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Plans become harder to write (more fields) | Must-haves and verify are optional — omitting them falls back to current behavior |
| Verify blocks are brittle (exact string matching) | Use `contains` matcher, not exact equality. Support `exit 0`/`exit nonzero` for pass/fail |
| Must-haves are redundant with tests | Must-haves are higher-level (user-observable behaviors) — tests are implementation-level |
| Requirement IDs create overhead | Use PRD feature IDs (F1, F2) not a new namespace |

## Open Questions

1. **Verify block format**: YAML-in-markdown (`- run: ... expect: ...`) vs. simpler prose (`Run X → expect Y`)? YAML is more parseable but harder to write.
2. **Must-have validation timing**: After each task, or only after all tasks complete? After-all is simpler but delays failure detection.
3. **Backward compatibility**: Should the executor skip verify/must-haves gracefully when they're absent (yes — must be opt-in)?
