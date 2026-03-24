# Plugin Structure Compliance Review: interlore PRD

**Reviewer:** fd-plugin-structure-compliance
**Source PRD:** `docs/prds/2026-03-21-interlore.md`
**Canon reference:** `docs/canon/plugin-standard.md`
**Date:** 2026-03-21

---

## P0 — Will cause silent load failures or duplicate registration

### P0-1: Skills layout not specified — flat vs subdirectory ambiguous

The PRD (F2) says:

> Skills registered: `observe` (for scan engine)

It does not specify that `observe` lives at `skills/observe/SKILL.md`. The canon standard is explicit: "The flat pattern (`skills/foo.md`) is **not valid**. Use `skills/foo/SKILL.md` instead." An implementer reading only the PRD could create `skills/observe.md`, which the plugin loader will not resolve.

**Fix:** F2 acceptance criteria should state:
- `skills/observe/SKILL.md` exists with YAML frontmatter containing `description`
- `plugin.json` lists `"./skills/observe"` (not `"./skills"`)

### P0-2: plugin.json skills array format not specified

The PRD says "Skills registered: `observe`" but does not show the plugin.json `skills` array entry. Canon requires each skill directory listed individually (`"./skills/observe"`). Without this, an implementer may use the invalid `"./skills"` shorthand.

**Fix:** Add to F2 acceptance criteria:
- `plugin.json` `skills` array contains `"./skills/observe"` (per-directory listing, not bare `./skills`)

### P0-3: Hooks declared in plugin.json risk

The PRD (F5) describes a Sprint Stop hook in `hooks.json`, which is correct. However, F2 lists what the plugin scaffold contains without explicitly stating that hooks are NOT declared in `plugin.json`. Canon: "Do NOT declare `hooks` in plugin.json — Claude Code auto-loads `hooks/hooks.json` by convention. Declaring it explicitly causes duplicate hook registration errors."

**Fix:** Add to F2 acceptance criteria:
- `plugin.json` does NOT contain a `hooks` key (hooks auto-load from `hooks/hooks.json`)

---

## P1 — Will fail structural tests or miss canon requirements

### P1-1: Required root files — 6/6 not explicitly enumerated

F2 acceptance criteria lists:

> CLAUDE.md, AGENTS.md, README.md, PHILOSOPHY.md, LICENSE, .gitignore present

This is actually all 6. **Compliant.** No fix needed.

*(Initially flagged as potential gap, but re-reading confirms all 6 are present. Keeping for audit trail.)*

### P1-2: tests/ structural suite underspecified

F2 says:

> `tests/structural/test_structure.py` passes

Canon requires a specific test layout:
```
tests/
├── pyproject.toml          # name: interlore-tests
├── uv.lock
└── structural/
    ├── conftest.py          # project_root, skills_dir, plugin_json fixtures
    ├── helpers.py           # parse_frontmatter(path)
    ├── test_structure.py
    └── test_skills.py       # Skill count, frontmatter validation
```

The PRD only mentions `test_structure.py`. Missing: `pyproject.toml` with `name = "interlore-tests"`, `conftest.py`, `helpers.py`, `test_skills.py`, and `uv.lock`.

**Fix:** Expand F2 acceptance criteria:
- `tests/pyproject.toml` exists with `name = "interlore-tests"`, `requires-python >= 3.12`
- `tests/structural/conftest.py`, `tests/structural/helpers.py`, `tests/structural/test_skills.py` exist
- `test_skills.py` validates `observe` skill frontmatter (description field present)
- `cd tests && uv run pytest -q` passes

### P1-3: bump-version.sh delegation not specified

Canon: "Bump script: `scripts/bump-version.sh` delegates to `ic publish` (preferred) or `interbump.sh` (fallback)."

The PRD mentions "bump script" in F2's general description but does not specify that `scripts/bump-version.sh` must delegate to `ic publish` or `interbump.sh`. An implementer might write a standalone version-bumping script that doesn't integrate with the marketplace pipeline.

**Fix:** Add to F2 acceptance criteria:
- `scripts/bump-version.sh` exists, is executable, and delegates to `ic publish` or `interbump.sh`

---

## P2 — Will diverge from convention but won't break loading

### P2-1: Commands registered but directory layout not specified

F2 says:

> Commands registered: `scan.md`, `review.md`, `status.md`

Canon specifies commands live in `commands/` directory and are listed in `plugin.json` as `"./commands/scan.md"`, etc. The PRD doesn't make the directory explicit.

**Fix:** Add to F2:
- `commands/scan.md`, `commands/review.md`, `commands/status.md` exist with YAML frontmatter
- `plugin.json` `commands` array lists `"./commands/scan.md"`, `"./commands/review.md"`, `"./commands/status.md"`

### P2-2: hooks/ directory and hooks.json not in F2 scaffold

F5 references a Sprint Stop hook in `hooks.json`, but F2 (the scaffold feature) doesn't include `hooks/` in the directory structure. Since F5 is a separate feature, the scaffold could ship without hooks, but the PRD should clarify whether `hooks/hooks.json` is part of the initial scaffold or added in F5.

**Fix:** Either:
- Add to F2: `hooks/hooks.json` exists (even if empty array initially)
- Or add to F5: `hooks/hooks.json` created as part of integration wiring

### P2-3: Marketplace registration not mentioned

Canon requires every plugin have an entry in `core/marketplace/.claude-plugin/marketplace.json`. The PRD doesn't mention marketplace registration anywhere.

**Fix:** Add acceptance criterion (F2 or new):
- `core/marketplace/.claude-plugin/marketplace.json` updated with interlore entry (name, source URL, description, version, keywords, strict)

### P2-4: SKILL.md frontmatter requirements underspecified

The `observe` skill needs YAML frontmatter with at least `description` (required) and ideally `name`, `user_invocable`, and `argument-hint`. The PRD doesn't mention frontmatter at all.

**Fix:** Add to F2 or F3:
- `skills/observe/SKILL.md` has YAML frontmatter with `description` field

---

## P3 — Cosmetic or best-practice gaps

### P3-1: plugin.json author field not specified

Canon: `author.name` must be `"mistakeknot"` (not `"MK"`). PRD says "correct schema" but doesn't call this out.

**Fix:** No PRD change needed if implementer follows canon, but noting for review.

### P3-2: .clavain/interlore/ as output directory

F3 writes proposals to `.clavain/interlore/proposals.md`. This is a runtime artifact directory, not a plugin structure issue per se. However, the `.clavain/` directory is Clavain-owned infrastructure. If interlore is a standalone plugin, writing into another pillar's namespace could create ownership ambiguity.

**Fix:** Consider whether proposals should live in a plugin-owned directory (e.g., `.interlore/proposals.md`) or if `.clavain/` is intentionally shared runtime state. Add a design decision note to F3.

### P3-3: No explicit AGENTS.md section ordering

Canon specifies 10 sections in order for AGENTS.md. The PRD doesn't reference this. Not a structural failure — the implementer should follow canon — but worth noting.

---

## Summary

| Priority | Count | Key Theme |
|----------|-------|-----------|
| P0 | 3 | Skills layout ambiguity, plugin.json skills array, hooks declaration risk |
| P1 | 2 | Structural test suite incomplete, bump-version delegation missing |
| P2 | 4 | Commands layout, hooks directory placement, marketplace, SKILL frontmatter |
| P3 | 3 | Author field, output directory ownership, AGENTS.md ordering |

**Overall assessment:** The PRD correctly identifies all 6 required root files and the general plugin structure, but leaves the critical skills subdirectory layout and plugin.json array format unspecified. These P0 gaps are the most likely source of silent load failures. The structural test suite is underspecified relative to canon. All issues are fixable with targeted acceptance criteria additions — no architectural changes needed.
