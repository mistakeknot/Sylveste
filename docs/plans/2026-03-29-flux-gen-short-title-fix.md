---
bead: sylveste-dui
title: "Plan: Fix _short_title() truncation in generate-agents.py"
date: 2026-03-29
type: plan
---

# Plan: Fix _short_title() Truncation

## Summary

Fix `_short_title()` in generate-agents.py to stop producing broken section headers. Single function, ~20 lines changed.

## Tasks

### Task 1: Write tests (TDD)
**File:** `tests/structural/test_generate_agents.py`

Add `TestShortTitle` class with cases for:
- Hyphenated compounds preserved: "Check read-your-writes failures" → "Read-your-writes failures"
- Decimal numbers preserved: "AgentDropout threshold of 0.6 is too aggressive" → "AgentDropout threshold of 0.6 is too aggressive"
- Namespace dots preserved: "Check json.RawMessage representation" → "Json.RawMessage representation"
- Comma split works: "Check migrations, especially rollbacks" → "Check migrations"
- Em-dash split works: "Review the design — focus on safety" → "Review the design"
- Long titles truncate at word boundary: 90-char input → max 80 chars ending at word boundary, no `...`
- Leading verb stripping still works: "Verify that tests pass" → "Tests pass"

### Task 2: Fix _short_title()
**File:** `scripts/generate-agents.py`

1. Replace regex `[,.\-—]` with smarter splitting:
   - Split on `, ` (comma-space), ` — ` (em-dash with spaces), ` - ` (spaced dash)
   - Do NOT split on bare hyphens (word-joiners) or periods (decimals, namespaces)
2. Increase truncation limit from 60 to 80
3. Truncate at last word boundary (space), not mid-word
4. Drop the `...` suffix — just truncate cleanly

### Task 3: Verify existing tests still pass
Run full test suite.

## Execution Order
Task 1 → Task 2 → Task 3
