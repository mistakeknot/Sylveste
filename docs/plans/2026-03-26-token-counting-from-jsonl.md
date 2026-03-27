---
artifact_type: plan
bead: Sylveste-uboy.2
stage: planned
---
# Plan: Replace chars/4 with JSONL-based actual token counting

**Bead:** Sylveste-uboy.2
**Goal:** Replace the chars/4 token approximation in synthesize.md Step 3.4c with actual token counts parsed from agent task output JSONL files.

## Context

Task output JSONL files (at `/tmp/claude-*/tasks/{agentId}.output`) contain `message.usage` on each assistant message with actual API token counts:
- `input_tokens` (non-cached)
- `output_tokens`
- `cache_creation_input_tokens`
- `cache_read_input_tokens`

The current chars/4 approximation is inaccurate because: (1) tokenization ratio varies by language/content, (2) it misses cache token categories entirely, (3) it uses output file size as output proxy but ignores input tokens consumed by the prompt.

## Task 1: Create token-count.py helper script

**File:** `interverse/interflux/scripts/token-count.py`
**New file.** Parses a task output JSONL file and returns token counts.

```python
#!/usr/bin/env python3
"""Parse agent task output JSONL for actual token usage.

Usage: token-count.py <output_jsonl_path>
Output (JSON): {"input_tokens": N, "output_tokens": N, "cache_creation": N, "cache_read": N, "total": N}

Falls back to chars/4 estimate if JSONL unavailable or unparseable.
"""
```

Key behaviors:
- Sum `message.usage` fields across all `type=assistant` messages
- `total` = `input_tokens + output_tokens` (billing tokens, excluding cache)
- Output as single-line JSON to stdout
- Exit 0 on success, exit 1 with fallback JSON if JSONL missing/corrupt

## Task 2: Update synthesize.md Step 3.4c

**File:** `interverse/interflux/skills/flux-drive/phases/synthesize.md`
**Change:** Replace the chars/4 block (lines 258-277) with:

1. For each dispatched agent, look up the task output JSONL path
   - The orchestrator knows each agent's task output path from the Agent tool response
   - Store these paths in a mapping during Phase 2 launch (add to monitoring contract)
2. Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/token-count.py <output_path>`
3. Parse the JSON result and write to interstat
4. Fallback: if script unavailable or fails, use chars/4

## Task 3: Update shared-contracts.md — token output path contract

**File:** `interverse/interflux/skills/flux-drive/phases/shared-contracts.md`
**Change:** Add a new contract section documenting that the orchestrator must track task output JSONL paths during dispatch and make them available for token counting in synthesis.

## Build Sequence

Task 1 → Task 3 → Task 2 (script first, then contract, then wire into synthesis)
