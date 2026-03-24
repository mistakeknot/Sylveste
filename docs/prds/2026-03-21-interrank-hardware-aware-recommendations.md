---
artifact_type: prd
bead: Demarch-1ifn
stage: design
---

# PRD: Interrank Hardware-Aware Model Recommendations

## Problem

Agents asking "what's the best model for X?" get benchmark-ranked recommendations, but no way to filter by what they can actually run locally. A user with an RTX 4090 (24GB VRAM) needs to know which open-weight models fit, at what quantization, and how much quality they lose.

## Solution

Extend the agmodb→interrank snapshot pipeline with hardware metadata, and add a `recommend_local_models` MCP tool that combines task-based scoring with VRAM-aware filtering and quantization-adjusted quality scores.

## Features

### F1: Extend agmodb snapshot with hardware fields

**What:** Add model hardware metadata to the snapshot export so interrank can filter by open-weight status and compute VRAM requirements.

**Acceptance criteria:**
- [ ] `export-snapshot.ts` includes `parametersBillions`, `activeParametersBillions`, `isMoe`, `isOpenWeight` per model
- [ ] Fields are nullable (backward compatible — existing interrank instances ignore unknown fields)
- [ ] New snapshot published to `data-snapshot-latest` release
- [ ] `validate-snapshot.ts` updated to check new fields exist
- [ ] At least 20 models have `parametersBillions` populated (based on agmodb DB coverage)

**Repo:** `mistakeknot/agmodb`

### F2: Add local-calc module to interrank

**What:** Copy GPU database and VRAM calculation logic from agmodb into interrank, and extend the snapshot type to accept hardware fields.

**Acceptance criteria:**
- [ ] `src/local-calc/gpu-data.ts` contains GPU database (35+ GPUs: NVIDIA, AMD, Apple Silicon)
- [ ] `src/local-calc/vram-calc.ts` contains VRAM formula, quantization levels, quality retention multipliers
- [ ] `src/types.ts` `SnapshotModel` extended with optional `parametersBillions`, `activeParametersBillions`, `isMoe`, `isOpenWeight`
- [ ] `src/local-calc/` has unit tests for VRAM estimation and quality retention
- [ ] `getGpuById()` resolves GPU IDs to specs

**Repo:** `mistakeknot/interrank` (via `interverse/interrank/`)

### F3: `recommend_local_models` MCP tool

**What:** New MCP tool that recommends the best open-weight models a user can run on their local hardware, ranked by quantization-adjusted benchmark scores.

**Acceptance criteria:**
- [ ] Tool registered as `recommend_local_models` with Zod schema validation
- [ ] Accepts `task` (required), `gpu_id` (optional), `vram_gb` (optional), `limit` (optional, default 10)
- [ ] Requires at least one of `gpu_id` or `vram_gb`
- [ ] Filters to `isOpenWeight=true` models only
- [ ] For each model: finds best quantization that fits VRAM, applies quality retention to score
- [ ] Returns: model info, quantization level, VRAM required, adjusted score, base score, confidence
- [ ] GPU info included in response when `gpu_id` provided
- [ ] Returns empty results with explanation if no models fit
- [ ] Unit tests for recommendation logic with mock snapshot data

**Repo:** `mistakeknot/interrank` (via `interverse/interrank/`)

## Non-goals

- Multi-GPU support (e.g., 2×RTX 3090 = 48GB) — accept raw `vram_gb` for this use case
- Inference speed estimation (memory bandwidth → tokens/sec) — future iteration
- `list_gpus` tool — can add later if agents need to discover GPU IDs
- Modifying existing `recommend_model` tool — `recommend_local_models` is additive

## Dependencies

- agmodb database must have `parametersBillions`, `isOpenWeight` populated for models (already shipped in local-calc feature)
- interrank snapshot auto-refresh (default 5 min) handles picking up new snapshot after agmodb publishes

## Open Questions

- Should `recommend_local_models` also accept a `provider` filter? Probably yes for consistency with `recommend_model`.
- Snapshot version bump (v2→v3) or just optional fields? Leaning optional for backward compat.
