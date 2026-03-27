---
title: "interfere Token Efficiency & Game Playtesting"
date: 2026-03-27
status: draft
bead: sylveste-86r
---

# PRD: interfere Token Efficiency & Game Playtesting

## Problem

Clavain sprints consume significant cloud API tokens. Research agents (~30-40% of volume) and C1/C2 tasks (~20-25%) are high-volume, low-stakes work that doesn't need frontier models. Meanwhile, Shadow Work playtesting runs $2-5/session in API costs, limiting continuous testing. interfere has a working server with benchmarked models but Track B5 isn't being used yet.

## Solution

Two features, one infrastructure:

### Feature 1: Local Model Routing for Clavain (Track B5 Enforce)

Upgrade Track B5 from shadow to enforce for eligible task categories. Use bigger-than-necessary local models (35B MoE for Haiku-tier, 122B MoE for Sonnet-tier) since marginal cost is zero.

**Acceptance criteria:**
- [ ] routing.yaml updated with new model tiers (35B as tier1, 122B as tier2)
- [ ] Shadow mode logs hypothetical cost savings to interstat
- [ ] After 50+ shadow samples, quality comparison shows <5% regression per task category
- [ ] Research agents and C1/C2 tasks promoted to enforce mode
- [ ] Safety floors maintained: fd-safety, fd-correctness always use cloud

### Feature 2: sw-agent ↔ interfere Bridge for Game Playtesting

Thin adapter connecting Shadow Work's sw-agent HTTP API to interfere for zero-cost playtesting.

**Acceptance criteria:**
- [ ] Bridge reads game state from sw-agent (localhost:8790)
- [ ] Formats state as prompts for interfere (/v1/chat/completions)
- [ ] Parses model responses into sw-agent actions
- [ ] One emergence campaign (climate-cascade) completes successfully on local inference
- [ ] Playtest results comparable to cloud-based runs

## Non-Goals

- Vision/multimodal support (Approach B — deferred until UI testing needed)
- Modifying interfere's inference engine or experiment hooks
- Changing interspect's evidence collection (it already works in shadow mode)
- Running both 35B + 122B simultaneously (sequential loading is fine for now)

## Dependencies

- interfere server running on localhost:8421
- Shadow Work debug server running on localhost:8790
- Track B5 shadow mode already active in routing.yaml
- interspect evidence collection already functional
- interstat metrics DB at ~/.claude/interstat/metrics.db

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Memory contention (35B + 122B = 83GB) | Medium | Blocks dual-model | Sequential loading; kv_bits=8 for headroom |
| Qwen MoE prompt format differs from Claude | Medium | Quality regression | Test with existing prompts first; adapt if needed |
| Overnight thermal throttling | Low | Slower inference | Thermal monitor already built; add cooldown pauses |
| sw-agent API changes break bridge | Low | Bridge fails | Pin API version; bridge is thin adapter |

## Features Breakdown

### F1: Routing Config Update
Update routing.yaml model tiers. Pure config change.

### F2: Interstat Shadow Logging
Add cost-comparison logging to Track B5 shadow decisions. When a task would route locally, log both the hypothetical local cost ($0) and the actual cloud cost.

### F3: sw-agent Bridge Script
Python script that loops: read state → prompt → infer → act. Uses interfere's OpenAI-compatible API.

### F4: Evidence Collection & Promotion
After shadow period, review interspect evidence and promote categories that pass the <5% quality bar.
