---
artifact_type: brainstorm
bead: Sylveste-1ifn
stage: discover
---

# Interrank: Hardware-Aware Model Recommendations

## What We're Building

A new MCP tool `recommend_local_models` in interrank that combines AgMoBench domain scores with hardware constraints (GPU VRAM, quantization quality degradation) to recommend the best open-weight model a user can actually run on their local hardware.

Example query: "What's the best coding model I can run on my RTX 4090?" → returns ranked models with quantization level and adjusted scores.

## Why This Approach

**Snapshot-first**: Extend the agmodb snapshot export to include `parametersBillions`, `activeParametersBillions`, `isMoe`, `isOpenWeight` per model. These fields already exist in agmodb's database (used by the local-calc web UI) but aren't exported to the snapshot that interrank consumes. Copy GPU database + VRAM calc logic (~130 lines of pure functions) into interrank.

Rationale:
- agmodb is the source of truth for model parameters — no duplicate data
- interrank stays snapshot-only (no DB dependency), consistent with its architecture
- GPU/VRAM calc is pure math with no external dependencies — safe to copy
- New `recommend_local_models` tool keeps existing tools unchanged (additive)

Rejected alternatives:
- **Self-contained hardcoded params**: Creates drift as models are added to agmodb
- **Shared npm package**: Over-engineered for ~130 lines of stable code

## Key Decisions

1. **Two-repo scope**: This bead covers both agmodb (snapshot export) and interrank (new tool). Coordinated release.
2. **New tool, not extension**: `recommend_local_models(task, gpu_id | vram_gb)` as dedicated tool rather than adding hardware params to `recommend_model`. Better discoverability, clearer intent.
3. **GPU database copied, not shared**: Copy `gpu-data.ts` + `vram-calc.ts` into `interrank/src/local-calc/`. ~130 lines of pure functions, stable API, no publish pipeline needed.
4. **Quality retention multipliers**: Use agmodb's existing retention curve (FP16→1.0, Q8→0.99, Q5→0.95, Q4→0.9, Q2→0.75) to adjust benchmark scores for quantization degradation.
5. **Open-weight filter**: When hardware constraint is specified, automatically filter to `isOpenWeight=true` models only (can't run proprietary models locally).

## Integration Surface

### agmodb changes (snapshot export)
- `scripts/export-snapshot.ts`: Add `parametersBillions`, `activeParametersBillions`, `isMoe`, `isOpenWeight` to model records
- Bump snapshot version (v2 → v3 or add fields as optional for backward compat)
- Re-export and publish new snapshot

### interrank changes
- `src/types.ts`: Add optional hardware fields to `SnapshotModel`
- `src/local-calc/gpu-data.ts`: Copy GPU database (35 GPUs: NVIDIA, AMD, Apple Silicon)
- `src/local-calc/vram-calc.ts`: Copy VRAM formula, quantization levels, quality retention
- `src/index.ts`: Register `recommend_local_models` tool
- `src/recommend.ts`: Add `recommendLocalModels()` function that:
  1. Resolves GPU → VRAM (via gpu_id lookup or direct vram_gb)
  2. Filters to open-weight models
  3. For each model: finds best quantization that fits, computes adjusted score
  4. Ranks by adjusted weighted score
  5. Returns: model name, quant level, VRAM needed, adjusted score, confidence

### Tool parameters
```
recommend_local_models:
  task: string (required) — natural language task description
  gpu_id: string (optional) — GPU identifier from database (e.g. "rtx-4090")
  vram_gb: number (optional) — direct VRAM in GB (overrides gpu_id)
  limit: number (optional, default 10)
```
At least one of `gpu_id` or `vram_gb` required.

### Response shape
```
{
  gpu: { id, name, vramGb },
  recommendations: [
    {
      slug, name, provider,
      quantization: "Q4",         // best quant that fits
      vramRequired: 14.5,         // GB needed at this quant
      adjustedScore: 82.3,        // score × quality retention
      baseScore: 91.4,            // score at FP16
      qualityRetention: 0.9,      // Q4 retention factor
      confidence: 0.85,
      matchReason: "..."
    }
  ]
}
```

## Open Questions

1. **Snapshot backward compatibility**: Add fields as optional (null for models without data) or bump to v3? Leaning optional to avoid breaking existing interrank instances.
2. **Multi-GPU**: Should we support `vram_gb` values that imply multiple GPUs (e.g., 2×RTX 3090 = 48GB)? Probably not in v1 — just accept raw VRAM.
3. **list_gpus tool**: Should we also expose a `list_gpus` tool so agents can discover available GPU IDs? Low cost to add.
4. **Snapshot refresh timing**: After agmodb publishes new snapshot with hardware fields, interrank auto-refreshes (default 5 min). No special coordination needed.
