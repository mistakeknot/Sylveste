---
title: "interfere Token Efficiency & Game Playtesting"
date: 2026-03-27
status: draft
bead: sylveste-86r
complexity: C3
---

# Plan: interfere Token Efficiency & Game Playtesting

## Overview

Use interfere's existing server (no engine changes) to:
1. Route Clavain tasks to local models via Track B5 (shadow → enforce)
2. Build a playtest bridge connecting Shadow Work's debug API to interfere
3. Evaluate local vision models for future computer-use agent capability

## Task Breakdown

### Task 1: Update routing.yaml Model Tiers
**Files:** `os/Clavain/config/routing.yaml`
**Effort:** Small (config only)

Upgrade local model tiers so Haiku-tier tasks use 35B MoE (not 9B) and Sonnet-tier tasks use 122B MoE:

```yaml
complexity_routing:
  C1: "local:qwen3.5-35b-a3b-4bit"         # was 9B; MoE 3B active, 88 tok/s
  C2: "local:qwen3.5-35b-a3b-4bit"         # same; zero marginal cost
  C3: "local:qwen3.5-122b-a10b-4bit"       # was nemotron-30b; 10B active, 50 tok/s
```

Remove the 9B from complexity routing (keep it in tier_mappings as draft model for speculative decoding).

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
  1. GET localhost:8790/diag/status-lite → game state
  2. GET localhost:8790/diag/emergence → emergence overview
  3. GET localhost:8790/diag/events/feed?limit=10 → recent events
  4. Format as system prompt + user message for interfere
  5. POST localhost:8421/v1/chat/completions → model reasons about state
  6. Parse structured response → POST localhost:8790/control/{action}
  7. Sleep 2-3s (or configurable interval)
```

**System prompt template:**
```
You are a grand strategy game player. You receive game state and must decide
the next strategic action. Respond with JSON:
{"action": "step|pause|speed|recruit|deploy", "params": {...}, "reasoning": "..."}
```

**Features:**
- `--campaign <name>` flag to load campaign YAML (assertions, stop conditions)
- `--model <local-model-id>` flag to pick the interfere model
- `--interval <seconds>` for decision frequency
- `--max-ticks <n>` safety limit
- Logs decisions + game state to JSONL for post-hoc analysis
- Exits cleanly on thermal throttle (check interfere /health)

### Task 4: Campaign Adapter
**Files:** `interverse/interfere/scripts/campaign-adapter.py` (new)
**Effort:** Small

Reads Shadow Work campaign YAML files and translates them into:
- Initial game setup (restart, step to starting tick)
- Assertion checks at campaign checkpoints
- Pass/fail summary

This reuses the existing campaign format from `shadow-work/tools/sw-agent/campaigns/`.

### Task 5: Run First Shadow Sprint with Instrumented Logging
**Files:** No new files — operational
**Effort:** Small

Run a normal Clavain sprint with Track B5 shadow logging active. After the sprint:
- Query interstat for hypothetical savings
- Review interspect evidence for quality comparison
- Document findings

### Task 6: Run First Local Playtest
**Files:** No new files — operational
**Effort:** Small

Start interfere + Shadow Work, run `climate-cascade` campaign via playtest bridge:
- Record: decisions made, assertion pass rate, tok/s, thermal
- Compare against a cloud-based run of the same campaign
- Document findings

### Task 7: Computer-Use Model Evaluation (Research)
**Files:** `interverse/interfere/docs/investigations/2026-03-27-computer-use-models.md` (new)
**Effort:** Medium (research only, no code)

Evaluate vision-language models for future computer-use capability:
- Qwen3-VL, Qwen3-VL-MoE — MLX availability, memory, latency
- UI-TARS, ShowUI, CogAgent — computer-use specialists
- Benchmark scores (ScreenSpot, OSWorld)
- Recommendation for which to try first on M5 Max

This is research output only — no interfere changes in this sprint.

## Execution Order

```
Task 1 (config) ──┐
Task 2 (logging) ──┼── parallel, independent
Task 3 (bridge) ──┘
                   │
Task 4 (adapter) ──── depends on Task 3
                   │
Task 5 (shadow sprint) ── depends on Tasks 1+2
Task 6 (local playtest) ── depends on Tasks 3+4
                   │
Task 7 (research) ──── independent, can run anytime
```

Tasks 1, 2, 3, 7 can all run in parallel. Task 4 depends on Task 3. Tasks 5 and 6 are operational runs after code is ready.

## Success Criteria

- [ ] routing.yaml has upgraded model tiers (35B for C1/C2, 122B for C3)
- [ ] Shadow mode logs hypothetical cost savings to interstat
- [ ] Playtest bridge runs climate-cascade campaign to completion on local inference
- [ ] Campaign assertion pass rate >=80%
- [ ] Computer-use model research doc written with clear recommendation
- [ ] Zero interfere engine changes needed

## Out of Scope

- Promoting Track B5 from shadow to enforce (needs evidence from Task 5 first)
- Adding vision/multimodal to interfere (deferred to Task 7 research findings)
- Modifying interfere experiments (TurboQuant, early exit, etc.)
- Changing interspect evidence collection
