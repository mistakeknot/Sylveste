# PRD: intermem tidy — automatic structural tidy for memory files

**Bead:** iv-d1mcu
**Date:** 2026-03-01
**Status:** Draft

## Problem

Auto-memory files (MEMORY.md) grow unbounded. Claude Code truncates at 200 lines, losing facts at the bottom. Manual curation doesn't scale across dozens of projects. The intermem pipeline handles entry-level promotion/decay but not file-level organization.

## Solution

Add `intermem tidy` — a deterministic (no LLM) command that:

1. **Extracts oversized sections** from MEMORY.md into linked topic files when the file exceeds a line budget
2. **Detects stale counts** (point-in-time snapshots like "48 plugins") and flags them with drift info

## Features

### F1: Section extraction (`tidy.py`)

When MEMORY.md exceeds `--budget` (default: 120 lines):
- Parse into sections using existing scanner section detection
- Score sections by line count
- Skip protected sections: `## Quick Reference`, `## Topic Files`
- For each section exceeding `--section-threshold` (default: 15 lines):
  - Slugify section name → `<slug>.md`
  - If topic file already exists → skip (don't clobber manual curation)
  - Write section content to topic file with `# <Section Name>` header
  - Replace section in MEMORY.md with link in `## Topic Files`
- Create `## Topic Files` section if missing

### F2: Stale count detection (`tidy.py`)

Scan for patterns like `\d+ (plugins|commands|skills|tests|files|modules)`:
- For file/directory-countable patterns, resolve actual count
- Report: `"48 Interverse plugins" → actual: 52 (stale by 4)`
- For un-verifiable counts: flag with `[unverified]`
- Output as report only (no auto-modification)

### F3: SessionStart nudge (`session-start.sh`)

When MEMORY.md exceeds budget:
- Print: `MEMORY.md is N lines (budget: 120). Run /intermem:tidy to review.`
- No auto-tidy — just a nudge

### F4: CLI + skill integration

- CLI: `intermem tidy [--budget N] [--section-threshold N] [--apply] [--project-dir PATH]`
- Skill: `/intermem:tidy` — instructions for invoking the CLI
- Default: dry-run. `--apply` to execute changes.

## Non-goals (v1)

- Historical collapse (needs semantic judgment → v2 with haiku)
- Auto-tidy on SessionStart (too destructive without review)
- LLM calls of any kind
- Changes to the existing promotion pipeline

## Success Criteria

- `intermem tidy --dry-run` completes in < 5 seconds
- f3ar MEMORY.md (98 lines, no topic files) → architecture section extracted to topic file
- Sylveste MEMORY.md (64 lines, 4 topic files) → no changes (under budget)
- Stale count detection catches at least `48 Interverse plugins` drift
- Tests cover: extraction, skip-existing, protected sections, dry-run, stale detection
