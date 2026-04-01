---
title: "Phase 1: Bring up local inference pipeline"
date: 2026-03-27
status: draft
bead: sylveste-bpw
complexity: C3
---

# Plan: Phase 1 Bring Up

## Status Assessment

The server skeleton works end-to-end — Metal worker spawns, models load, tokens stream via SSE. But 5 features are implemented-but-not-wired, and prompt formatting is broken.

## Task Breakdown

### Task 1: Fix prompt formatting + chat template (P0)
**Files:** `server/main.py`, `server/inference.py`
**Blocking:** Everything else depends on correct prompts.

The server currently extracts only the last user message (main.py:139). System prompts are silently dropped. The model receives raw text, not a formatted conversation.

Fix:
1. In `main.py._chat_completions`: pass the full `messages` array to the worker, not just the extracted prompt string.
2. In `inference.py.generate()`: accept `messages` instead of `prompt`. Use `tokenizer.apply_chat_template(messages, add_generation_prompt=True)` to build the formatted prompt. This handles system prompts, multi-turn context, and model-specific formatting (e.g., Qwen's `<|im_start|>` tokens).
3. Update `metal_worker.py` GENERATE payload to carry `messages` alongside `prompt` (backward compat: if `messages` present, use chat template; if only `prompt`, use raw text).

### Task 2: Wire thermal monitoring into /health (P1)
**Files:** `server/main.py`, `server/metal_worker.py`
**Effort:** Small

Import ThermalMonitor in the main process (it uses macOS notify API, no Metal dependency). Add thermal state to /health response. The playtest bridge already checks /health for thermal — this just makes the data available.

### Task 3: Add model warm-up endpoint (P1)
**Files:** `server/main.py`
**Effort:** Small

Add `POST /v1/models/load` endpoint that calls `worker.load_model(model_name)`. Also add optional `--preload <model>` CLI flag to `__main__.py` that loads a model at startup. This eliminates cold-load latency on first inference.

### Task 4: Wire confidence cascade (P2)
**Files:** `server/main.py`, `server/cascade.py`
**Effort:** Medium

Wire ConfidenceCascade into the `/v1/chat/completions` handler. When enabled (via request param or server config), the cascade probes with the first few tokens and escalates if confidence is below threshold. For now, escalation means returning an empty response with a header indicating cloud fallback is needed (the caller decides whether to actually call cloud).

### Task 5: Create MCP server stub (P2)
**Files:** `server/mcp.py` (new)
**Effort:** Small

Create the `server/mcp.py` that plugin.json references. Minimal tools:
- `interfer_health` — return server health + thermal + loaded models
- `interfer_generate` — proxy to /v1/chat/completions
- `interfer_models` — list available/loaded models

### Task 6: Steady-state smoke test (P1)
**Files:** No new files — operational
**Effort:** Small

Start the server for real (not test harness), preload the 35B model, run:
1. Multi-turn conversation with system prompt
2. Measure tok/s at steady state (after model is warm)
3. Verify thermal data appears in /health
4. Run the playtest-local verb against it

## Execution Order

```
Task 1 (prompt fix) ──── BLOCKING: must complete first
                   │
Task 2 (thermal) ──┐
Task 3 (warm-up) ──┼── parallel, after Task 1
Task 5 (MCP stub) ──┘
                   │
Task 4 (cascade) ──── after Task 1 (uses the fixed message flow)
                   │
Task 6 (smoke test) ── after all above
```

## Success Criteria

- [ ] System prompts and multi-turn context reach the model via chat template
- [ ] /health returns thermal state
- [ ] --preload flag loads model at startup
- [ ] MCP server starts without error
- [ ] 35B MoE at steady-state >60 tok/s (benchmarked at 88 tok/s)
- [ ] playtest-local verb receives model output that references game domain context
