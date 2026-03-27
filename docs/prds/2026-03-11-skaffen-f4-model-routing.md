---
artifact_type: prd
bead: Sylveste-4xp
stage: design
---
# PRD: Skaffen F4 — Model Routing

## Problem

Skaffen v0.1 uses a NoOpRouter that always returns the same model regardless of OODARC phase, task complexity, or token budget. This means brainstorming uses the same model as git operations, wasting cost on simple phases and underperforming on creative ones.

## Solution

Replace NoOpRouter with a DefaultRouter that selects models based on phase defaults (matching Clavain's economy routing table), configurable overrides (JSON + env vars), token budget tracking with graceful degradation, and complexity-aware promotion/demotion.

## Features

### F4a: DefaultRouter with Phase Defaults

**What:** Phase-aware model selection using Clavain's proven economy routing table as defaults, with fallback chain.

**Acceptance criteria:**
- [x] `DefaultRouter` struct implements `agent.Router` interface
- [x] Phase default map: brainstorm=opus, plan/build/review/ship=sonnet
- [x] Fallback chain: opus → sonnet → haiku (hardcoded for v0.2)
- [x] `SelectModel(phase)` returns model name + human-readable reason
- [x] `RecordUsage(usage)` method to feed budget tracker (no-op if no budget set)
- [x] Model names use canonical IDs: `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`
- [x] Tests: correct model per phase, fallback chain resolution, reason strings

### F4b: Config Loading (JSON + Env Vars)

**What:** Three-layer config resolution: env vars > routing.json > hardcoded defaults.

**Acceptance criteria:**
- [x] Load `~/.skaffen/routing.json` at router creation (optional, missing file = use defaults)
- [x] JSON schema: `{"phases": {"brainstorm": "opus", ...}, "budget": {"max_tokens": N, "mode": "graceful"}}`
- [x] Env var override: `SKAFFEN_MODEL_BUILD=haiku` overrides the build phase model
- [x] Env var format: `SKAFFEN_MODEL_<PHASE>` where phase is uppercased
- [x] Resolution order: env var > JSON > hardcoded default
- [x] Read Clavain's `config/routing.yaml` as additional source when available (parse `subagents.phases` section)
- [x] Tests: JSON overrides defaults, env overrides JSON, missing file graceful

### F4c: Budget Tracker with Degradation

**What:** Per-session token budget tracking with configurable enforcement modes.

**Acceptance criteria:**
- [x] `BudgetTracker` struct: tracks cumulative input + output tokens
- [x] Three modes: `graceful` (default), `hard-stop`, `advisory`
- [x] Graceful: 0-80% configured model, 80-100% downgrade to cheapest in fallback chain, 100%+ warn + continue on haiku
- [x] Hard-stop: return error from SelectModel at 100% budget
- [x] Advisory: never change model, just track and log
- [x] Budget thresholds configurable in routing.json: `{"budget": {"max_tokens": 1000000, "mode": "graceful", "degrade_at": 0.8}}`
- [x] `--budget` CLI flag: `skaffen --budget 500000 -p "..."` sets max tokens
- [x] Budget state reported in evidence emission (tokens spent / budget / percentage)
- [x] Tests: degradation at thresholds, hard-stop error, advisory passthrough

### F4d: Complexity Layer (Shadow Mode)

**What:** Task complexity classification (C1-C5) that can promote/demote model selection.

**Acceptance criteria:**
- [x] Classify complexity from prompt token count (C1: <300, C2: <800, C3: <2000, C4: <4000, C5: 4000+)
- [x] Shadow mode (default): log what would change but don't apply
- [x] Enforce mode: C4-C5 promote to opus, C1-C2 demote to haiku
- [x] Mode set via routing.json `{"complexity": {"mode": "shadow"}}` or env `SKAFFEN_COMPLEXITY_MODE`
- [x] Shadow log written to evidence JSONL (field: `complexity_tier`, `complexity_override`)
- [x] Tests: classification thresholds, shadow vs enforce behavior

## Non-goals

- Configurable fallback chains (hardcoded for v0.2)
- Rate-limit detection and automatic retry with fallback model
- Multi-provider routing (e.g., route to Gemini for certain phases)
- Cost estimation in USD (just token counting)
- Interspect calibration integration (B3 — uses Clavain's, not Skaffen's own)

## Dependencies

- Skaffen v0.1 complete (F1-F3, F5-F7) — done
- Clavain routing.yaml schema (for compatibility parsing) — exists at config/routing.yaml

## Open Questions

- None — all decisions made in brainstorm.
