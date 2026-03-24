# fd-plugin-scaffold-correctness-interlore

Review of Task 2 (scaffold) in `/home/mk/projects/Demarch/docs/plans/2026-03-21-interlore.md` against `/home/mk/projects/Demarch/docs/canon/plugin-standard.md`.

## Verdict: 5 issues found (2 will cause test failures, 3 conformance deviations)

---

### Issue 1 — BLOCKING: pyproject.toml in wrong directory

**Plan says:** `tests/structural/pyproject.toml`
**Standard says:** `tests/pyproject.toml` (with `testpaths = ["structural"]`)
**All existing plugins confirm:** `interverse/*/tests/pyproject.toml` (checked interdeep, interwatch — both at `tests/pyproject.toml`)

The plan places pyproject.toml inside `tests/structural/` instead of `tests/`. This means `cd tests && uv run pytest -q` (the standard invocation) will not find it. The plan's own verify step (`cd interverse/interlore && uv run pytest tests/structural/ -v`) would also fail because uv looks for pyproject.toml in cwd or parents, not in the test directory.

**Fix:** Move pyproject.toml to `tests/pyproject.toml`. Keep `testpaths = ["structural"]` and `pythonpath = ["structural"]`.

---

### Issue 2 — BLOCKING: test_skills.py missing pyyaml dependency and parse_frontmatter import

**Plan says:** `from helpers import skill_dirs` in test_skills.py, and pyproject.toml lists only `pytest>=8.0` (no pyyaml).
**Standard says:** `dependencies = ["pytest>=8.0", "pyyaml>=6.0"]`
**All existing plugins:** Import `from helpers import parse_frontmatter` and use pyyaml for frontmatter parsing. The test validates that SKILL.md has YAML frontmatter with `name` and `description`.

Two sub-issues:

a) **Missing pyyaml dependency.** The plan's pyproject.toml omits `"pyyaml>=6.0"`. The helpers.py in the plan defines `skill_dirs()` and `command_files()` but not `parse_frontmatter()`, so it avoids pyyaml — but this means the test_skills.py does not validate frontmatter content, which is a required minimum test per the standard ("SKILL.md files have valid YAML frontmatter with `name` and `description`").

b) **Bare `from helpers import skill_dirs` will work** because `pythonpath = ["structural"]` in pyproject.toml adds the structural directory to sys.path. This is the same pattern used by all existing plugins (`from helpers import parse_frontmatter`). So the import itself is correct — but the plan should use `parse_frontmatter` (with pyyaml) for frontmatter validation, not just check `"name:" in content`.

**Fix:** Add `"pyyaml>=6.0"` to dependencies. Add `parse_frontmatter()` to helpers.py (matching the ecosystem standard implementation). Change test_skills.py to use `parse_frontmatter` for proper YAML frontmatter validation with `assert "name" in fm` and `assert "description" in fm`.

---

### Issue 3 — CONFORMANCE: AGENTS.md header deviates from standard template

**Standard template (plugin-standard.md lines 122-145):**
```markdown
# <plugin-name> — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](./PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.
```

**Plan says:**
```markdown
# AGENTS.md — interlore

## Canonical References
1. [`MISSION.md`](../../MISSION.md) — project mission.
2. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — design bets and principles...
```

Three deviations:
- **Title format:** `AGENTS.md — interlore` vs standard `interlore — Development Guide`. All existing plugins use the standard format (verified interwatch, interdeep).
- **Canonical Reference 1 replaces PHILOSOPHY.md with MISSION.md.** The standard has PHILOSOPHY.md as item 1 and CLAUDE.md as item 2. The plan replaces CLAUDE.md with PHILOSOPHY.md and adds MISSION.md as a new item 1. Task 1 says it will update the standard to "add MISSION.md alongside PHILOSOPHY.md," but Task 1 and Task 2 are declared parallel. If Task 2 runs first, the AGENTS.md will be non-conformant with the *current* standard. If Task 1 runs first, the standard will have changed but only to "add MISSION.md alongside" — not to *replace* CLAUDE.md as item 2.
- **Relative path `../../PHILOSOPHY.md`:** Existing plugins use `./PHILOSOPHY.md` (relative to plugin root) for their own PHILOSOPHY.md, and `../../PHILOSOPHY.md` to reference the monorepo root's PHILOSOPHY.md. The plan references the *monorepo root* PHILOSOPHY.md, which is correct for interlore's use case (it observes the root PHILOSOPHY.md), but deviates from the standard header convention where ref 1 points to the plugin's own PHILOSOPHY.md. Both interwatch and interdeep use relative or local refs.

**Fix:** Use the standard header format. Reference 1 should be `[PHILOSOPHY.md](./PHILOSOPHY.md)` (the plugin's own), reference 2 should be `CLAUDE.md`. If MISSION.md needs to be referenced, add it as a third canonical reference or in a plugin-specific section below the boilerplate.

---

### Issue 4 — CONFORMANCE: CLAUDE.md "Design Decisions" boundary question

**doc-structure.md says:** CLAUDE.md is for "Claude Code ONLY: plugins, hooks, tool preferences, permissions." Any project knowledge is a boundary violation.
**plugin-standard.md says:** CLAUDE.md includes "Design Decisions. No project knowledge — that goes in AGENTS.md."

The plan's CLAUDE.md includes a "Design Decisions (Do Not Re-Ask)" section with 7 bullet items. This matches the plugin-standard.md template exactly (which explicitly includes Design Decisions in CLAUDE.md). Cross-checking existing plugins: both interwatch and interpath CLAUDE.md include Design Decisions sections.

**Verdict: Correct per plugin-standard.md.** Design Decisions are architectural choices that Claude Code must remember every session to avoid re-asking — they are operational configuration, not project knowledge. No change needed.

---

### Issue 5 — CONFORMANCE: .gitignore missing `node_modules/`

**Standard says:** `.gitignore` should exclude `node_modules/`, `__pycache__/`, `*.pyc`, `.venv/`, `.pytest_cache/`, `.claude/`, `.beads/`, `*.log`, OS/editor files.
**Plan includes:** All of the above *except* `node_modules/`.

While interlore is a pure Python/markdown plugin with no node dependencies, the standard lists `node_modules/` as a required exclude. Omitting it deviates from the template.

**Fix:** Add `node_modules/` to .gitignore.

---

### Issue 6 — No hooks in plugin.json: CORRECT

**Standard says (line 112):** "Do NOT declare `hooks` in plugin.json — Claude Code auto-loads `hooks/hooks.json` by convention."

The plan omits `hooks` from plugin.json entirely. Since interlore has no hooks directory and no hooks.json, this is correct behavior. No hooks key should be present.

**Verdict: Correct.** No change needed.

---

## Summary Table

| # | Severity | Item | Status |
|---|----------|------|--------|
| 1 | BLOCKING | pyproject.toml in `tests/structural/` instead of `tests/` | Must fix |
| 2 | BLOCKING | Missing pyyaml dep + weak frontmatter validation in test_skills.py | Must fix |
| 3 | CONFORMANCE | AGENTS.md header deviates from standard template | Should fix |
| 4 | OK | Design Decisions in CLAUDE.md | Correct per standard |
| 5 | CONFORMANCE | .gitignore missing `node_modules/` | Should fix |
| 6 | OK | No hooks in plugin.json | Correct |

### Command path format check

`"commands": ["./commands/scan.md", "./commands/review.md", "./commands/status.md"]` — matches the standard format exactly (`./commands/command-name.md`). Verified against interwatch, interdeep, interpath — all use the same `./commands/*.md` pattern. Correct.
