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

Plan review surfaced 4 issues addressed below:
- **P1 (performance):** 35B + 122B coexistence leaves only 13GB KV headroom in 96GiB Metal limit. **Fix:** Use 35B exclusively for playtest bridge (not 122B). 35B-A3B at 88 tok/s with 18GB leaves ample room.
- **P1 (user-product):** Bridge system prompt had no game domain context. **Fix:** Include Shadow Work domain preamble from campaign YAML.
- **P2 (performance):** PromptCacheManager exists in prompt_cache.py but isn't wired into main.py. **Fix:** Added Task 3b.
- **P2 (user-product):** Task 5 shadow-to-enforce timeline undefined. **Fix:** Scoped as "gather baseline + check existing samples" not open-ended.

## Task Breakdown

### Task 1: Update routing.yaml Model Tiers
**Files:** `os/Clavain/config/routing.yaml`
**Effort:** Small (config only)

Upgrade local model tiers so Haiku-tier tasks use 35B MoE (not 9B):

```yaml
complexity_routing:
  C1: "local:qwen3.5-35b-a3b-4bit"         # was 9B; MoE 3B active, 88 tok/s
  C2: "local:qwen3.5-35b-a3b-4bit"         # same; zero marginal cost
  C3: "local:qwen3.5-122b-a10b-4bit"       # 10B active, 50 tok/s; Clavain only (not playtest)
```

Keep the 9B in tier_mappings as draft model for speculative decoding.

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
**Files:** `interverse/interfere/scripts/playtest-bridge.py` (new)
**Effort:** Medium

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

### Task 4: Campaign Adapter
**Files:** `interverse/interfere/scripts/campaign-adapter.py` (new)
**Effort:** Small

Reads Shadow Work campaign YAML files and translates them into:
- Initial game setup (restart, step to starting tick)
- Assertion checks at campaign checkpoints
- Domain context extraction (objective, win condition) for bridge system prompt
- Pass/fail summary

This reuses the existing campaign format from `shadow-work/tools/sw-agent/campaigns/`.

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
