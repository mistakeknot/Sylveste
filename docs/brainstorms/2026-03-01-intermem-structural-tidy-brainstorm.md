# intermem: Automatic Structural Tidy for Memory Files

**Bead:** iv-d1mcu
**Date:** 2026-03-01
**Status:** Brainstorm complete

## What We're Building

A new `tidy` capability for intermem that performs structural housekeeping on memory files — not entry-level decay (which `sweep` already handles), but file-level reorganization. Three capabilities:

1. **Line budget enforcement** — when MEMORY.md exceeds ~120 lines, extract topic sections into linked topic files
2. **Stale count pruning** — detect point-in-time counts/snapshots that are guaranteed stale and flag them
3. **Historical collapse** — detect verbose "before the fix" context that's now baked into code

## Why This Matters

MEMORY.md is loaded into every conversation context. At 200+ lines, truncation kicks in and facts at the bottom are lost. At 98 lines (f3ar project), the file is mostly architecture docs that should be a topic file. The Demarch MEMORY.md (64 lines) is well-structured because it was manually curated — but manual curation doesn't scale across dozens of projects.

Current intermem handles *entry promotion* (memory → AGENTS.md/CLAUDE.md) but not *source file organization*. The tidy feature sits before the promotion pipeline: reorganize the source first, so the promotion pipeline works from cleaner input.

## Current State Analysis

**intermem architecture:**
- Python package (`interverse/intermem/intermem/`) with scanner, stability, citations, validator, promoter, pruner, dedup, metadata, journal
- Skills: `/intermem:synthesize` (main), `/intermem:validate` (health check)
- CLI subcommands: `sweep` (periodic decay), `query` (search/browse)
- SessionStart hook: minimal (interbase stubs only, no-op)
- State: `.intermem/stability.jsonl`, `metadata.db`, `promotion-journal.jsonl`

**Memory file format:**
- `## Section` headers group related facts
- `# [YYYY-MM-DD] lesson` entries with bullet context
- `- [topic.md](topic.md)` links in `## Topic Files` section
- Truncation at 200 lines (Claude Code enforced)

**Existing MEMORY.md sizes:**
- f3ar: 98 lines (no topic files — all inline architecture docs)
- Demarch: 64 lines (4 topic files, well-structured)

## Design Decisions

### 1. Shell-first, no LLM for mechanical ops

All three capabilities can be implemented as deterministic operations:
- Line counting and section detection: `awk`/`sed` or Python stdlib
- Stale count detection: regex for `\d+ (commands|plugins|skills|tools|modules)` patterns
- Historical collapse: harder — needs semantic judgment. **Decision: skip for v1.** Focus on capabilities 1 and 2 which are fully deterministic. Add capability 3 later with haiku-tier LLM when we have examples of what "collapsed" looks like.

### 2. Integration point: new CLI subcommand + companion skill

- Add `intermem tidy` CLI subcommand (Python, reuses scanner)
- Add `/intermem:tidy` skill (instructions for running the CLI)
- SessionStart hook can nudge when MEMORY.md exceeds threshold (but does NOT auto-tidy — that's destructive without user review)

### 3. Section extraction algorithm

When MEMORY.md exceeds the line budget:
1. Parse into sections (reuse `scanner.py` section detection)
2. Score each section by line count (biggest sections = best extraction candidates)
3. Skip `## Quick Reference` and `## Topic Files` (these stay in MEMORY.md)
4. For each candidate section exceeding a per-section threshold (~15 lines):
   a. Create `<section-slug>.md` topic file
   b. Move section content to topic file
   c. Replace section in MEMORY.md with a one-line link in `## Topic Files`
5. If `## Topic Files` section doesn't exist, create it

**Output:** Dry-run by default (`--dry-run`). Shows what would be extracted. `--apply` to execute.

### 4. Stale count detection

Regex-based scanning for patterns like:
- `48 Interverse plugins` → stale if actual count differs
- `94 tests across 11 files` → stale if not re-verified
- `15 skills` → point-in-time snapshot

**Challenge:** How to verify? Some counts can be checked (`ls interverse/ | wc -l`), others can't (test counts require running tests). **Decision:** Flag all count patterns with a `[stale?]` marker for human review. Don't auto-delete — counts may still be useful context.

For counts that *can* be verified (file/directory counts), provide the actual count alongside the stored count so the user can see the drift.

### 5. Performance target

< 5 seconds for a typical memory directory. The scanner already parses in milliseconds. The new operations are all I/O-bound (read files, write files). No network calls, no LLM calls.

## Key Decisions

1. **v1 scope: capabilities 1 and 2 only.** Historical collapse (capability 3) requires semantic judgment — defer to v2 with haiku integration.
2. **Dry-run default.** Tidy is destructive (moves content between files). Always show a preview first.
3. **Reuse scanner.py.** Don't parse MEMORY.md twice with different logic.
4. **120-line budget.** Below the 200-line truncation limit with room for growth. Configurable via `--budget N`.
5. **Section threshold: 15 lines.** Sections smaller than this aren't worth extracting to a separate file.
6. **No LLM calls in v1.** Pure Python/shell for all operations. This is a deliberate constraint — tidy should be fast and deterministic.
7. **Nudge on SessionStart, don't auto-tidy.** The hook can print "MEMORY.md is 142 lines (budget: 120). Run /intermem:tidy to reorganize." but should never modify files without explicit user action.

## Implementation Shape

### New files:
- `intermem/tidy.py` — core tidy logic (section extraction, stale count detection)
- `intermem/tests/test_tidy.py` — comprehensive tests
- `skills/tidy/SKILL.md` — skill instructions

### Modified files:
- `intermem/__main__.py` — add `tidy` subcommand
- `hooks/session-start.sh` — add line-count nudge

### Not modified:
- Scanner, stability, promoter, pruner — existing pipeline unchanged
- `synthesize.py` — tidy is independent, not part of the promotion pipeline

## Open Questions

1. Should extracted topic files include a header like `# Topic: <section-name>` or just start with content? (Recommendation: include header for context when read standalone)
2. Should the `## Topic Files` section be sorted alphabetically or by extraction order? (Recommendation: alphabetical for consistency)
3. If a topic file already exists (e.g., `interspect.md`), should tidy merge or skip? (Recommendation: skip — don't risk clobbering manually curated topic files)
