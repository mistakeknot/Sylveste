---
bead: sylveste-dui
title: "Brainstorm: Fix generated agent prompt engineering bugs"
date: 2026-03-29
---

# Brainstorm: Fix Generated Agent Prompt Engineering Bugs

## Bug 1: `_short_title()` produces broken section headers

The function splits on `[,.\-—]` and truncates at 60 chars. This produces:

- "Accord theory: how perfumers select ingredients whose int..." — mid-word truncation
- "Assess whether the evidence" — dash in "evidence-gathering" triggers split, loses key noun
- "Assemblage as late" — hyphen in "late-binding" triggers split
- "AgentDropout threshold of 0" — period in "0.6" triggers split
- "At 500+ nodes" — from "At 500+ nodes, the naive O(n²)..." — loses the actual concern

### Root cause

The regex `[,.\-—]` treats hyphens and periods as sentence-level delimiters. But review_area bullets commonly contain:
- Hyphenated compound words: "late-binding", "evidence-gathering", "read-your-writes"
- Decimal numbers: "0.6", "0.7"
- Namespace separators: "json.RawMessage"

### Fix

Replace the naive character-class split with a smarter approach:
1. Don't split on hyphens at all (they're word-joiners, not clause separators)
2. Don't split on periods followed by digits (decimal numbers)
3. Don't split on periods preceded by lowercase and followed by uppercase (namespace separators)
4. Keep the comma and em-dash splits (these are genuine clause separators)
5. Increase truncation limit from 60 to 80 chars (review sections have plenty of space)
6. When truncating, break at the last word boundary, not mid-word

## Bug 2: Identical suffix (NOT confirmed in template)

The fd-prompt-engineering review flagged a 29-word suffix on every bullet. Examination of the template shows `render_agent()` renders `- {area}` without any suffix. The issue was likely in a specific LLM spec generation run, not in the template. The flux-gen LLM prompt (flux-gen.md) does not instruct the LLM to add suffixes.

**Verdict:** Not a template bug. If it recurs, it's an LLM behavior that should be addressed in the flux-gen prompt with a "do NOT append generic review instructions to review_areas" rule. But since we can't reproduce it in the current code, no fix needed.

## Scope

Fix `_short_title()` only. The suffix issue is not reproducible in the current codebase.
