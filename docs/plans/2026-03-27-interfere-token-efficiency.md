---
title: "interfere Token Efficiency & Game Playtesting"
date: 2026-03-27
status: reviewed
bead: sylveste-86r
complexity: C3
---

# Plan: interfere Token Efficiency & Game Playtesting

## Overview

Use interfere's existing server to:
1. Route Clavain tasks to local models via Track B5 (shadow → enforce)
2. Build a playtest bridge connecting Shadow Work's debug API to interfere
3. Wire prompt caching for sustained playtest sessions (one existing-code integration)

## Review Findings Applied

Plan review surfaced 12 issues across 4 agents. Critical fixes:

**Critical (blocking):**
- **C1 (correctness):** PriorityRequestQueue is dead code — concurrent requests interleave token streams. **Fix:** Added Task 0 to wire queue into main.py before any bridge work.
- **C2 (correctness):** New model ID `local:qwen3.5-122b-a10b-4bit` missing from `tier_mappings`. **Fix:** Task 1 now does atomic config update (tier_mappings + complexity_routing together).
- **C3 (architecture):** `_routing_model_tier()` in lib-routing.sh has hardcoded model names — new IDs silently disable safety floors. **Fix:** Task 1 also updates lib-routing.sh.

**High:**
- **H1 (performance):** 35B + 122B coexistence leaves only 13GB KV headroom. **Fix:** Bridge uses 35B exclusively.
- **H2 (architecture):** Bridge script inside interfere couples it to Shadow Work. **Fix:** Moved to `scripts/` at monorepo root.
- **H3 (user-product):** Bridge system prompt had no game domain context. **Fix:** Domain preamble from campaign YAML.

**Medium (addressed in implementation):**
- Shadow cost logging goes to separate `local_routing_shadow` table (not `agent_runs`)
- Cascade empty-response handled as no-op in bridge (with warning log)
- Campaign assertions pause game before reading state (TOCTOU fix)
- PromptCacheManager wired into main.py (Task 3b)
- Bridge sleep is response-gated (after inference completes), interval default 5s

## Task Breakdown

### Task 0: Wire PriorityRequestQueue into interfere server
**Files:** `interverse/interfere/server/main.py`, `interverse/interfere/server/queue.py`
**Effort:** Small (integration of existing code)
**Blocking:** Must complete before Tasks 3, 5, 6.

`PriorityRequestQueue` is fully implemented in `queue.py` but `main.py` bypasses it — calls `worker.generate()` directly. Concurrent HTTP requests interleave token streams via the shared `resp_queue` (no `request_id` filtering in `MetalWorker._recv`).

Fix: Wire queue into `_chat_completions` handler so requests serialize through the worker. Add a `threading.Lock` in `MetalWorker` as a belt-and-suspenders guard. This prevents the bridge + Clavain B5 enforce mode from corrupting each other's outputs.

### Task 1: Update routing.yaml Model Tiers + lib-routing.sh
**Files:** `os/Clavain/config/routing.yaml`, `os/Clavain/scripts/lib-routing.sh`
**Effort:** Small (config + shell function update)

**Atomic update — all three changes in one commit:**

1. Add `local:qwen3.5-122b-a10b-4bit` to `tier_mappings` (tier 3)
2. Update `complexity_routing`:
```yaml
complexity_routing:
  C1: "local:qwen3.5-35b-a3b-4bit"         # was 9B; MoE 3B active, 88 tok/s
  C2: "local:qwen3.5-35b-a3b-4bit"         # same; zero marginal cost
  C3: "local:qwen3.5-122b-a10b-4bit"       # 10B active, 50 tok/s; Clavain only (not playtest)
```
3. Add cases for new model IDs in `_routing_model_tier()` in `lib-routing.sh`:
   - `local:qwen3.5-35b-a3b-4bit` → tier 2
   - `local:qwen3.5-122b-a10b-4bit` → tier 3

Without step 3, safety floors for fd-safety/fd-correctness are silently disabled for the new models.

**Note:** The 122B (65GB) is for Clavain routing only. The playtest bridge uses 35B exclusively to avoid memory contention with the game.

### Task 2: Add Interstat Shadow Cost Logging
**Files:** `os/Clavain/hooks/lib-sprint.sh` (or Track B5 shadow handler)
**Effort:** Small

When Track B5 shadow mode logs a "would route locally" decision, also log:
- `cloud_model`: the model that actually ran
- `cloud_tokens`: input + output tokens consumed
- `local_model`: what would have been used
- `hypothetical_savings_usd`: estimated cost difference

This feeds interstat's cost-query.sh for sprint summaries.

### Task 3: Build Playtest Bridge Script
**Files:** `scripts/playtest-bridge.py` (new, at monorepo root — NOT inside interfere)
**Effort:** Medium

Standalone script at monorepo root. Interfere is a downstream service (it serves inference); the bridge is a consumer that also happens to consume Shadow Work's API. Placing it inside interfere would couple the inference server to a specific game's HTTP contract.

Python script that connects sw-agent HTTP API (localhost:8790) to interfere (localhost:8421):

```
Loop:
  1. Check interfere /health for thermal state (before inference, not just at loop start)
  2. GET localhost:8790/diag/status-lite → game state
  3. GET localhost:8790/diag/emergence → emergence overview
  4. GET localhost:8790/diag/events/feed?limit=10 → recent events
  5. Format as system prompt (with domain preamble) + user message for interfere
  6. POST localhost:8421/v1/chat/completions → model reasons about state
  7. Parse structured response → POST localhost:8790/control/{action}
  8. Wait for response completion before sleeping (avoid queuing during GPU-heavy scenes)
  9. Sleep --interval seconds (default: 5s, not 2s — accounts for 35B prefill + generation)
```

**System prompt template** (includes game domain context):
```
You are a strategic advisor for Shadow Work, a real-time grand strategy simulation.
The simulation models ~100 fundamental forces across 15 pillars: Climate, Technology,
Diplomacy, Economy, Population, Pandemic, Healthcare, Resource Scarcity, Infrastructure,
Military, Politics, Culture, Institutions, Policy, Public Finance.

You receive game state snapshots including country metrics, emergence signals, and
recent events. Your goal is to advance the campaign's objectives by making strategic
decisions. Respond with JSON:
{"action": "step|pause|speed|recruit|deploy", "params": {...}, "reasoning": "..."}

Campaign objective: {campaign.objective}
Win condition: {campaign.win_condition}
Current checkpoint: {campaign.current_checkpoint}
```

**Features:**
- `--campaign <name>` flag to load campaign YAML (assertions, stop conditions, domain context)
- `--model <local-model-id>` flag (default: `local:qwen3.5-35b-a3b-4bit`)
- `--interval <seconds>` decision frequency (default: 5s)
- `--max-ticks <n>` safety limit
- Logs decisions + game state to JSONL for post-hoc analysis
- Thermal check before each inference call (not just at loop start)
- Records tok/s per inference call for performance tracking

### Task 3b: Wire PromptCacheManager into interfere
**Files:** `interverse/interfere/server/main.py`
**Effort:** Small (integration of existing code)

`prompt_cache.py` is fully implemented but `main.py` never instantiates it. Wire it into the `/v1/chat/completions` handler so repeated calls with the same system prompt skip prefill. This converts ~1s prefill per bridge loop iteration to near-zero after the first call.

This is the highest-leverage optimization for sustained playtest sessions.

### Task 4: Campaign Loading (folded into bridge)
**Files:** Part of `scripts/playtest-bridge.py` (no separate file)
**Effort:** Included in Task 3

Campaign loading is part of the bridge's `--campaign` flag handler, not a separate script. It:
- Reads Shadow Work campaign YAML from `--campaigns-dir` (configurable, default: `../shadow-work/tools/sw-agent/campaigns/`)
- Extracts domain context (objective, win condition) for system prompt
- Sets up initial game state (restart, step to starting tick)
- Runs assertion checks at campaign checkpoints (pauses game before reading state to avoid TOCTOU)
- Outputs pass/fail summary

No hardcoded cross-repo paths — the campaigns directory is always a CLI argument.

### Task 5: Shadow Sprint Baseline
**Files:** No new files — operational
**Effort:** Small

**Scoped as decision gate, not open-ended data gathering:**
1. Check how many shadow samples already exist since Track B5 was promoted to shadow on 2026-03-26
2. If <50 samples: run one sprint with instrumented logging, document findings
3. If >=50 samples: review interspect evidence, make enforce/defer decision
4. Query interstat for hypothetical cost savings

**Exit criteria:** Document with sample count, quality comparison, and enforce/defer recommendation.

### Task 6: First Local Playtest
**Files:** No new files — operational
**Effort:** Small

**Prerequisites:** Record tok/s baseline with game NOT running (isolate GPU contention).

Start interfere (35B model only) + Shadow Work, run `climate-cascade` campaign via playtest bridge:
- Record: decisions made, assertion pass rate, tok/s (game on vs off), thermal state
- Compare against a cloud-based run of the same campaign
- Document findings

**Success bar for this sprint:** Loop runs to completion without crashes. Assertions are a bonus — if pass rate is low, the finding is "bridge needs richer game context" not "sprint failed."

## Execution Order

```
Task 1 (config) ──┐
Task 2 (logging) ──┼── parallel, independent
Task 3 (bridge) ──┤
Task 3b (cache)  ──┘
                   │
Task 4 (adapter) ──── depends on Task 3
                   │
Task 5 (shadow baseline) ── depends on Tasks 1+2
Task 6 (local playtest) ── depends on Tasks 3+3b+4
```

Tasks 1, 2, 3, 3b can all run in parallel. Task 4 depends on Task 3. Tasks 5 and 6 are operational runs after code is ready.

## Success Criteria

- [ ] routing.yaml has upgraded model tiers (35B for C1/C2, 122B for C3)
- [ ] Shadow mode logs hypothetical cost savings to interstat
- [ ] PromptCacheManager wired into interfere server
- [ ] Playtest bridge runs climate-cascade campaign loop to completion on local inference
- [ ] Shadow baseline document with sample count and enforce/defer recommendation
- [ ] Computer-use model research doc written with recommendation (DONE: Qwen3-VL-30B-A3B)

## Out of Scope

- Promoting Track B5 from shadow to enforce (needs evidence from Task 5 first)
- Adding vision/multimodal to interfere (see investigation doc; Qwen3-VL-30B-A3B recommended for future sprint)
- Modifying interfere experiments (TurboQuant, early exit, etc.)
- Changing interspect evidence collection
- Running the 122B model during playtest sessions (memory contention with game)
