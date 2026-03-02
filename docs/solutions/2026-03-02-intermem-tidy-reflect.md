---
title: "intermem tidy: structural memory file management"
category: pattern
tags: [intermem, memory, auto-memory, tidy]
bead: iv-o54wi
date: 2026-03-02
---

# Reflect: intermem tidy sprint

## What Was Built

`intermem tidy` — a deterministic (no LLM) command that extracts oversized sections from MEMORY.md into linked topic files when the file exceeds a line budget. Also detects stale counts (e.g., "48 plugins" when there are actually 52).

Shipped: `tidy.py` (core logic), `/intermem:tidy` skill, SessionStart nudge.

## What Went Well

- **Deterministic approach was right.** No LLM calls means predictable, fast, and free. The section-extraction heuristic (score by line count, skip protected sections, don't clobber existing topic files) handles the common case well.
- **Dry-run default was right.** Memory files are sensitive — auto-modification without review would erode trust. The dry-run → `--apply` flow respects user intent.
- **The PRD → plan pipeline was efficient.** Clear PRD with non-goals (no LLM, no auto-tidy) kept scope tight.

## What Was Skipped

- **Tests not written.** Step 5 (test_tidy.py) was not implemented before the sprint was closed. The plan specified 12 test cases covering edge cases (empty files, unicode slugs, protected sections). This should be backfilled.

## Patterns Learned

- **Protected sections are essential for any tidy tool.** `Quick Reference` and `Topic Files` must never be extracted — they're the structural backbone. Any future tidy expansion needs this allowlist.
- **Slug collision detection matters.** The "skip if topic file exists" guard prevents data loss when multiple sections would slugify to the same name, or when the user has manually curated a topic file.

## Complexity Calibration

Estimated: C3 (moderate). Actual: C2-C3 — straightforward implementation of well-defined spec, but the section parsing edge cases (nested headers, empty sections) added real complexity. The skill and hook integration were trivial.
