---
title: "Using interfere as-is for token efficiency + game playtesting"
date: 2026-03-27
status: brainstorm
participants: [sma, claude]
---

# Brainstorm: interfere for Token Efficiency & Game Playtesting

## Context

interfere is a local MLX inference server on M5 Max 128GB. Server architecture is complete, benchmarks show 88 tok/s (35B MoE) and 50 tok/s (122B MoE). Track B5 is in shadow mode. Experiments (TurboQuant, early exit, reservoir routing) are advancing independently.

**Question:** While experiments continue, how can we use interfere *today* to improve token efficiency in Clavain and Claude Code — and extend to live game playtesting for Shadow Work?

## Goals (phased)

1. **Cost reduction** — Route high-volume, lower-stakes tasks to local models
2. **Latency reduction** — Eliminate network roundtrips for interactive loops (especially game agent)
3. **Sovereignty** — Keep code and game state local

## Part 1: Token Efficiency for Clavain

### Current Token Spend Profile

| Consumer | Volume | Current Routing | Stakes |
|----------|--------|-----------------|--------|
| Research agents (5 types) | ~30-40% | Haiku/Sonnet | Low — tolerates quality variance |
| C1/C2 subagents (exploration) | ~20-25% | Haiku (Track B2) | Low — deterministic tasks |
| Review agents (12 fd-*) | ~25-30% | Sonnet | Medium-High — safety floors exist |
| Brainstorm/strategy | ~10-15% | Opus | High — needs creative reasoning |

### Proposal: Upgrade Model Tiers for Local Routing

Instead of mapping local models 1:1 to cloud tiers (9B→Haiku, 35B→Sonnet), use *bigger* local models since the marginal cost is zero:

| Cloud Tier | Current Local Map | Proposed Local Map | Rationale |
|------------|------------------|--------------------|-----------|
| Haiku | 9B-4bit (60-80 tok/s) | **35B-A3B MoE** (88 tok/s) | Zero marginal cost; MoE only activates 3B params, so speed is comparable. Quality much higher. |
| Sonnet | 35B-A3B MoE | **122B-A10B MoE** (50 tok/s) | Review agents need quality. 122B with 10B active params trades some speed for much better reasoning. |
| Opus | Not mapped | **122B-A10B MoE** + confidence cascade | For C3 brainstorms that don't need frontier creativity. Cloud Opus as fallback. |

**Key insight:** MoE architecture means the 35B model only runs 3B parameters per token — it's nearly as fast as the 9B but dramatically smarter. There's no reason to use the 9B for anything.

### Shadow-Then-Enforce Rollout

**Phase 1 — Shadow (weeks 1-2):**
- Track B5 stays in shadow mode
- Log what *would* route locally for every task
- interspect collects quality comparison evidence (local output vs cloud output)
- interstat records hypothetical cost savings

**Phase 2 — Evidence Review:**
- After 50+ shadow samples, compare quality per agent type
- If <5% quality regression on a task category → promote to enforce
- If >5% → investigate (model size? prompt format? context length?)

**Phase 3 — Enforce (selective):**
- Research agents → enforce first (lowest risk)
- C1/C2 exploration → enforce second
- fd-* review agents → enforce per-agent based on interspect evidence
- fd-safety, fd-correctness → **always cloud** (safety floors)

### Concrete Config Changes Needed

1. **routing.yaml** — Update model tiers:
   ```yaml
   local_models:
     tier1: local:qwen3.5-35b-a3b-4bit   # was 9B
     tier2: local:qwen3.5-122b-a10b-4bit  # was 35B
   ```

2. **Shadow logging** — Already in place (Track B5 shadow mode). Needs interstat integration to record shadow decisions with hypothetical cost.

3. **Confidence cascade thresholds** — Currently 0.8/0.6. May need per-task-type tuning once we see shadow data.

4. **Memory budget** — 35B (18GB) + 122B (65GB) = 83GB. With 128GB total and 10GB for macOS, that leaves 35GB for KV cache. Tight but workable with kv_bits=8 (the "free lunch" from benchmarks).

### Expected Savings

Conservative (research + C1/C2 only): **40-50% token cost reduction**
Aggressive (+ review agents): **60-70% token cost reduction**
With Opus substitution for C3: **70-80% token cost reduction**

## Part 2: Game Playtesting Agent for Shadow Work

### The Opportunity

Shadow Work already has sophisticated agent infrastructure:
- **sw-agent** CLI with 30+ verbs talking to HTTP debug server (`:8790`)
- **Automated playtest** walking 12 CUJ checkpoints
- **tauri-mcp** with `take_screenshot`, `game_control`, `game_status`
- **12 emergence campaigns** with restart→step→snapshot→assert loops
- **Model escalation**: Priority chain → Claude CLI → Anthropic SDK

Currently all using *cloud* Claude. A local agent loop would:
- Eliminate API latency for rapid playtest iterations
- Enable continuous overnight playtesting (no token budget limit)
- Keep game state private (sovereignty)

### Two Approaches

#### Approach A: Structured Agent (Use Existing Infrastructure)

Use sw-agent's HTTP debug server + interfere for text reasoning. No vision needed.

```
Loop:
  1. sw-agent status → JSON game state
  2. interfere (122B MoE) reasons about state → next action
  3. sw-agent executes action via HTTP API
  4. Repeat at game speed
```

**Pros:** Works today with zero interfere changes. Uses proven interhelm pattern (structured queries > screenshots). 50 tok/s is fast enough for strategic decisions (one decision per 2-3 seconds). **Cons:** Can't catch visual bugs or UI glitches. Limited to what the debug API exposes.

#### Approach B: Vision Agent (Requires interfere Extension)

Use screenshots + multimodal model for visual verification.

```
Loop:
  1. tauri-mcp take_screenshot → PNG
  2. interfere (Qwen3-VL MoE) reasons about screenshot → visual assessment + action
  3. sw-agent executes action
  4. Repeat
```

**Pros:** Catches visual bugs, UI layout issues, rendering glitches. Closer to human playtester experience. **Cons:** Requires extending interfere schema to accept images (~2-3 days work). Vision models are slower and more memory-hungry. Not needed for emergence testing (which is state-based).

#### Recommended: Approach A now, Approach B later

Approach A gives 90% of the value with zero interfere changes. The sw-agent debug server already exposes rich game state (countries, agents, events, issues, deployments, economy). Emergence campaigns and CUJ checkpoints are all state-based assertions.

Approach B becomes valuable when:
- We're testing UI/UX (not simulation correctness)
- MetalFX upscaling visual quality needs validation
- We want to simulate a human player's visual experience

### Continuous Playtesting Architecture

```
┌─────────────────────────────────────────────┐
│  Playtest Orchestrator (Clavain/interlab)   │
│  • Runs emergence campaigns overnight       │
│  • Cycles through 12 YAML scenarios         │
│  • Records metrics per run                  │
│  ┌──────────────┐  ┌──────────────────────┐ │
│  │ interfere    │  │ sw-agent HTTP API    │ │
│  │ (122B MoE)   │←→│ localhost:8790       │ │
│  │ Reasoning    │  │ Game state + control │ │
│  └──────────────┘  └──────────────────────┘ │
│         ↑                    ↑               │
│   Local inference     Shadow Work (Tauri)    │
│   50 tok/s            60 FPS simulation      │
│   Zero API cost       Bevy + MetalFX         │
└─────────────────────────────────────────────┘
```

**Cost: $0/night** (vs current playtest at ~$2-5/run in API tokens)

## Part 3: Immediate Actions (What We Can Do Today)

### Action 1: Promote Track B5 Shadow → Instrumented Shadow
Add interstat logging to shadow decisions so we measure hypothetical savings.

### Action 2: Update routing.yaml Model Tiers
Swap 9B → 35B MoE as Tier 1, 35B → 122B MoE as Tier 2.

### Action 3: Build sw-agent ↔ interfere Bridge
A thin adapter that:
- Reads game state from sw-agent HTTP API
- Formats it as a prompt for interfere
- Sends to interfere `/v1/chat/completions`
- Parses response into sw-agent actions

### Action 4: Run First Local Playtest
One emergence campaign (e.g., `climate-cascade`) running entirely on local inference.

### Action 5: Collect Evidence
After 50+ task samples (shadow mode) and 3+ playtest runs:
- Compare quality: local vs cloud per agent type
- Measure: tok/s, TTFT, memory pressure, thermal state
- Decision: which categories promote to enforce

## Open Questions

1. **Memory contention**: Can 35B + 122B coexist in memory, or do we need sequential loading with model swapping?
2. **Prompt format**: Do Qwen MoE models need different system prompts than Claude for review/research tasks?
3. **Playtest latency**: Is 50 tok/s fast enough for real-time strategy decisions, or do we need the 35B (88 tok/s) for time-critical actions?
4. **Overnight thermal**: Can M5 Max sustain continuous inference overnight without throttling?

## Original Intent

The experiments (TurboQuant, early exit, reservoir routing) continue independently. This brainstorm is about using interfere's *current* capabilities — the server that works today — to start saving tokens and testing games now, without waiting for research to land.

Trigger-to-feature mappings for future iterations:
- TurboQuant lands → 2x more KV cache headroom → can load both models simultaneously
- Early exit lands → 1.3x faster inference → game agent decisions in <1.5s
- Reservoir routing lands → automatic complexity classification → smarter model selection
- flash-moe lands → 397B model at 7-10 tok/s → Opus-quality local inference
