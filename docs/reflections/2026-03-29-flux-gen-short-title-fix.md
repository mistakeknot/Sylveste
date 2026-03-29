---
bead: sylveste-dui
title: "Reflect: _short_title() truncation fix"
date: 2026-03-29
type: reflection
---

# Reflection: _short_title() Fix

## What worked
- **Investigation narrowed scope**: The bead originally described two bugs (suffix + truncation). Reading the actual code showed the suffix issue isn't reproducible in the current template — it was likely a one-time LLM behavior. Focused on the real bug only.
- **Grep across all generated agents** revealed the full scope: truncated headers like "At 500+ nodes", "Assess whether the evidence", "Assemblage as late" — all from hyphens/periods being treated as clause delimiters.

## What surprised
- The regex `[,.\-—]` is a character class, so `\-` matches a single hyphen character. Compound words like `read-your-writes` and `evidence-gathering` get split at the first hyphen. Decimal numbers like `0.6` get split at the period. This was the root cause for ~30% of broken headers.

## Fix
- Split on clause-level delimiters only: `", "`, `" — "`, `" - "` (all require surrounding spaces)
- Increased limit from 60 to 80 chars
- Truncate at word boundary (rfind space) instead of mid-word with `...`
