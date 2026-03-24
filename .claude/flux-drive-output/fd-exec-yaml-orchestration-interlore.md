# fd-exec-yaml-orchestration: interlore .exec.yaml Review

**Plan:** `docs/plans/2026-03-21-interlore.md`
**Manifest:** `docs/plans/2026-03-21-interlore.exec.yaml`
**Date:** 2026-03-21

---

## Finding 1: task-5 missing dependency on task-2 — CONFIRMED BUG

**Severity:** High

task-5 verify block checks:
```yaml
- run: `test -f interverse/interlore/.claude-plugin/plugin.json`
- run: `python3 -c "import json; d=json.load(open('interverse/interlore/.claude-plugin/plugin.json')); assert len(d['skills'])==1; assert len(d['commands'])==3; print('OK')`
```

`plugin.json` is created in task-2 (Step 2). task-5 depends on `[task-1, task-3, task-4]` but NOT task-2.

The dependency is transitively satisfied — task-3 depends on task-2, and task-5 depends on task-3 — so in a correct dependency-driven orchestrator, task-2 will always complete before task-5 runs. However, the omission is still a manifest hygiene bug: if task-3 were ever removed or refactored to drop its task-2 dependency, task-5 would silently break. The explicit dependency should be declared.

**Recommendation:** Add `task-2` to task-5's depends list:
```yaml
depends: [task-1, task-2, task-3, task-4]
```
This costs nothing (no scheduling change, since task-3 already gates on task-2) but makes the contract explicit.

---

## Finding 2: Bead Demarch-7a8c shared by Task 3 and Task 5 — INTENTIONAL, minor concern

**Severity:** Low (informational)

Task 3 (bead Demarch-7a8c): "Implement interlore:scan observe skill"
Task 5 (bead Demarch-7a8c): "End-to-end scan test on real artifacts"

This is defensible. Task 5 is a validation-only step ("No new files — validation only") that verifies task-3's deliverable works end-to-end. Sharing a bead communicates "this is the same unit of work — implement + validate." The bead tracks the scan capability as a whole.

**Minor concern:** If task-5 fails, the bead can't be partially closed (task-3 done, task-5 not). The orchestrator or `bd close` invocation needs to account for this — closing Demarch-7a8c should only happen after task-5 succeeds, not after task-3. Plan should state this explicitly.

**Recommendation:** No change needed to the exec.yaml. Add a note in the plan's execution notes: "Demarch-7a8c should only be closed after task-5 passes, not after task-3."

---

## Finding 3: Task 1 verify — grep -c check is weak — CONFIRMED

**Severity:** Medium

```yaml
- run: `grep -c "MISSION" docs/canon/doc-structure.md`
  expect: exit 0
```

`grep -c` returns the count of matching lines and exits 0 if any match is found. This confirms the word "MISSION" appears somewhere in the file, but does not validate:
- The document hierarchy table was actually written
- The precedence rule ("MISSION.md takes precedence") is present
- The three-tier structure (MISSION -> VISION + PHILOSOPHY) is intact

A similar weakness exists for the `plugin-standard.md` check.

**Recommendation:** Strengthen to check for structural content:
```yaml
- run: `grep -c "MISSION.md takes precedence" docs/canon/doc-structure.md`
  expect: exit 0
- run: `grep -c "Document Hierarchy" docs/canon/doc-structure.md`
  expect: exit 0
```

---

## Finding 4: timeout_per_task 300s for task-2's 15-file scaffold — TIGHT BUT LIKELY OK

**Severity:** Low

Task 2 creates approximately 15 files across 9 steps: plugin.json, README.md, CLAUDE.md, AGENTS.md, PHILOSOPHY.md, LICENSE, .gitignore, bump-version.sh, pyproject.toml, conftest.py, helpers.py, test_structure.py, test_skills.py, scan.md, review.md, status.md, SKILL.md (stub). Plus `git init`, `git add`, `git commit`, and `uv run pytest`.

The plan provides full file content inline (no research or generation needed). For a Claude Code executor writing pre-specified content, 5 minutes is sufficient — each file write is ~2-5 seconds, git operations ~5 seconds, pytest ~10-15 seconds. Total realistic time: 60-120 seconds.

**Risk factor:** `uv run pytest` on first invocation may need to create a venv and resolve dependencies (pytest>=8.0). On a cold cache, this could take 30-60 seconds. Still within budget.

**Recommendation:** No change needed. The 300s limit has adequate margin.

---

## Finding 5: task-2 files field is directory path — AMBIGUOUS SCOPING

**Severity:** Medium

```yaml
files: [interverse/interlore/]
```

All other tasks use specific file paths or directory globs:
- task-1: `[MISSION.md, PHILOSOPHY.md, docs/canon/doc-structure.md, docs/canon/plugin-standard.md]`
- task-3: `[interverse/interlore/skills/observe/SKILL.md, interverse/interlore/skills/observe/references/]`
- task-5: `[.gitignore]`

The trailing slash on `interverse/interlore/` signals "entire directory" but the orchestrator behavior is undefined: does it use this for file-locking (prevent parallel writes), for change detection, or purely as documentation? The exec.yaml schema has no `files_semantics` field.

**Concern:** If the orchestrator uses `files` for write-locking to prevent parallel conflicts, the broad `interverse/interlore/` scope would unnecessarily block task-3 and task-4 from running until task-2 completes — but they already depend on task-2 via `depends`, so this is moot in practice. It would become a problem if a future task were added that touches a different subtree of `interverse/interlore/` and was intended to be parallel with task-2.

**Recommendation:** Either enumerate key files (plugin.json, README.md, etc.) for consistency, or document in the exec.yaml schema that directory paths mean "all files under this tree."

---

## Finding 6: max_parallel: 5 vs actual parallelism — NO BUG

**Severity:** Informational

`max_parallel: 5` but the dependency graph permits at most 2 concurrent tasks (task-1 and task-2 in Wave 1). Wave 2 is fully sequential (task-3 then task-4). Wave 3 has only task-5.

The `max_parallel` field is a ceiling, not a floor — the orchestrator should respect dependency edges and only parallelize where `depends` permits. Setting it to 5 is harmless; it just means "don't artificially limit parallelism beyond what the dependency graph dictates."

**Recommendation:** No change needed. A value of 2 would be more precise but 5 is not wrong.

---

## Finding 7: Wave 2 contains task-3 and task-4 but they are sequential — MISLEADING WAVE LABEL

**Severity:** Medium

```yaml
- name: "Wave 2 — skill implementation"
  tasks:
    - id: task-3
      depends: [task-2]
    - id: task-4
      depends: [task-3]
```

task-4 depends on task-3, so they cannot run in parallel. Grouping them in a single "Wave" implies parallelism (the Wave 1 label "independent foundations" reinforces this reading — its two tasks actually are parallel). A reader or a wave-based (non-dependency-driven) orchestrator could misinterpret Wave 2 as "run task-3 and task-4 in parallel."

The `mode: dependency-driven` field should save a correct orchestrator — it would use `depends` edges, not wave boundaries. But the wave labels are misleading for human readers.

**Recommendation:** Either:
1. Split into Wave 2a (task-3) and Wave 2b (task-4), or
2. Add a comment: `# sequential within wave — task-4 depends on task-3`

---

## Summary

| # | Finding | Severity | Action |
|---|---------|----------|--------|
| 1 | task-5 missing task-2 dependency | High | Add `task-2` to depends |
| 2 | Bead Demarch-7a8c shared (task-3, task-5) | Low | Add close-after-task-5 note |
| 3 | grep -c MISSION verify is weak | Medium | Strengthen grep patterns |
| 4 | 300s timeout for task-2 scaffold | Low | No change needed |
| 5 | task-2 files is directory, not file list | Medium | Enumerate or document semantics |
| 6 | max_parallel: 5 vs 2 actual | Informational | No change needed |
| 7 | Wave 2 mislabeled as parallel | Medium | Split or annotate |

**Blocking issues:** Finding 1 (missing dependency) should be fixed before execution. Findings 3, 5, and 7 are quality improvements that reduce misinterpretation risk.
