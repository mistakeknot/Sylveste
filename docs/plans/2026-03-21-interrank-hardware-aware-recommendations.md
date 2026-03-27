---
artifact_type: plan
bead: Sylveste-1ifn
stage: planned
---

# Plan: Interrank Hardware-Aware Model Recommendations

PRD: docs/prds/2026-03-21-interrank-hardware-aware-recommendations.md

## Overview

Three features across two repos. F1 (agmodb snapshot) must ship first so interrank can consume real data. F2 and F3 (interrank) can be built in parallel with mock data, then validated against the real snapshot.

## Task Sequence

### Task 1: Extend agmodb `getModels()` query with hardware fields
**Bead:** Sylveste-2wwg (F1)
**Repo:** `/home/mk/projects/agmodb`
**Files:**
- `src/lib/db/queries/models.ts` — add `parametersBillions`, `activeParametersBillions`, `isMoe`, `isOpenWeight` to `ModelWithStats` type and both select queries

**Steps:**
1. Add 4 fields to `ModelWithStats` type: `parametersBillions: number | null`, `activeParametersBillions: number | null`, `isMoe: boolean`, `isOpenWeight: boolean`
2. Add the 4 columns to the `.select()` in `getModels()`: `parametersBillions: models.parametersBillions`, `activeParametersBillions: models.activeParametersBillions`, `isMoe: models.isMoe`, `isOpenWeight: models.isOpenWeight`
3. Same for `getModelBySlug()`

**AC:** `ModelWithStats` includes hardware fields. Queries return the data.

### Task 2: Extend agmodb snapshot type and export
**Bead:** Sylveste-2wwg (F1)
**Repo:** `/home/mk/projects/agmodb`
**Files:**
- `src/lib/snapshot/types.ts` — add optional hardware fields to `SnapshotModel`
- `scripts/export-snapshot.ts` — map hardware fields in `toSnapshotModel()`
- `scripts/validate-snapshot.ts` — add optional field validation

**Steps:**
1. Add to `SnapshotModel` in `src/lib/snapshot/types.ts`:
   ```typescript
   parametersBillions: number | null;
   activeParametersBillions: number | null;
   isMoe: boolean | null;
   isOpenWeight: boolean | null;
   ```
2. In `export-snapshot.ts`, update `toSnapshotModel()` to include:
   ```typescript
   parametersBillions: model.parametersBillions ?? null,
   activeParametersBillions: model.activeParametersBillions ?? null,
   isMoe: model.isMoe ?? null,
   isOpenWeight: model.isOpenWeight ?? null,
   ```
3. **Bump snapshot version to 3** in `export-snapshot.ts` (`version: 3`) — consistent with v2 bump for modelFamilies. Documents that hardware fields are present.
4. Update `validate-snapshot.ts` to check new fields are present (nullable is OK)
5. Build and verify: `pnpm build`

**AC:** Snapshot JSON includes hardware fields at version 3. Backward compatible (nullable). Build passes.

### Task 3: Publish new agmodb snapshot
**Bead:** Sylveste-2wwg (F1)
**Repo:** `/home/mk/projects/agmodb`

**Steps:**
1. Run `pnpm snapshot:export` (or equivalent) to generate new snapshot
2. Verify output: `jq '.models[0] | keys' dist/agmodb-snapshot.json` shows new fields
3. Verify coverage: `jq '[.models[] | select(.parametersBillions != null)] | length' dist/agmodb-snapshot.json` — expect ≥20
4. Commit and push to agmodb repo
5. Publish to `data-snapshot-latest` release (via CI or manual `gh release upload`)

**AC:** New snapshot available at `data-snapshot-latest`. ≥20 models have `parametersBillions`.

**Gate:** Pause here for user — agmodb changes need DB access (Neon) to export. May need to be done separately.

### Task 4: Extend interrank `SnapshotModel` type
**Bead:** Sylveste-id2y (F2)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/types.ts` — add optional hardware fields

**Steps:**
1. Add to `SnapshotModel`:
   ```typescript
   parametersBillions?: number | null;
   activeParametersBillions?: number | null;
   isMoe?: boolean | null;
   isOpenWeight?: boolean | null;
   ```
   Fields are optional (`?`) so existing snapshots without them still load.

**AC:** Type extended. Build passes. Existing snapshot loading unaffected.

### Task 5: Add local-calc module to interrank
**Bead:** Sylveste-id2y (F2)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/local-calc/gpu-data.ts` — copy from agmodb, export only `GpuSpec`, `GPU_DATABASE`, `getGpuById` (omit `getGpusByCategory` — no caller in interrank)
- `src/local-calc/vram-calc.ts` — copy from agmodb
- `src/local-calc/index.ts` — selective barrel re-export (only symbols with callers)

**Steps:**
1. Create `src/local-calc/` directory
2. Copy `gpu-data.ts` from `/home/mk/projects/agmodb/src/lib/local-calc/gpu-data.ts`. Add provenance header: `// Vendored from agmodb:src/lib/local-calc/gpu-data.ts on 2026-03-21. Update by diffing against source.`
3. Copy `vram-calc.ts` from `/home/mk/projects/agmodb/src/lib/local-calc/vram-calc.ts`. Add same provenance header.
4. Create `index.ts` barrel: re-export only symbols that `recommendLocalModels` and the MCP tool actually call: `GpuSpec`, `GPU_DATABASE`, `getGpuById`, `ModelParams`, `QuantizationLevel`, `estimateVramGb`, `bestQuantization`, `adjustedScore`, `QUANT_QUALITY_RETENTION`, `DEFAULT_ADVANCED`. Do NOT re-export `getGpusByCategory`, `availableVramWithOffloading`, `getVisibleQuantLevels` (no callers).
5. Build: `pnpm build`

**AC:** `src/local-calc/` exists with GPU database (35 GPUs) and VRAM calc. Barrel exports only used symbols. Build passes.

### Task 6: Add local-calc unit tests
**Bead:** Sylveste-id2y (F2)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/local-calc/vram-calc.test.ts`
- `src/local-calc/gpu-data.test.ts`

**Steps:**
1. `gpu-data.test.ts`:
   - `getGpuById("rtx-4090")` returns spec with 24GB VRAM
   - `getGpuById("nonexistent")` returns undefined
   - GPU_DATABASE has ≥35 entries
2. `vram-calc.test.ts`:
   - `estimateVramGb({ parametersBillions: 70, activeParametersBillions: null, isMoe: false }, "Q4")` → 70×0.5 + 1.0 + 0.5 = 36.5
   - `bestQuantization(70B model, 24GB)` → null (doesn't fit)
   - `bestQuantization(7B model, 24GB)` → "FP16"
   - `adjustedScore(90, "Q4")` → 81 (90 × 0.9)
   - MoE expert offloading: 8x22B model (22B active) at Q4 → uses 22B not 176B
   - `fitsInVram(7B, "FP16", 24)` → true
3. Run: `pnpm test`

**AC:** All tests pass. Coverage for VRAM estimation, quantization selection, quality retention, MoE offloading.

### Task 7: Implement `recommendLocalModels` function
**Bead:** Sylveste-0szu (F3)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/recommend.ts` — add `recommendLocalModels()` and types

**Steps:**
1. Add types:
   ```typescript
   export type LocalModelRecommendation = {
     slug: string;
     name: string;
     provider: string;
     quantization: QuantizationLevel;
     vramRequired: number;
     adjustedScore: number;
     baseScore: number;
     qualityRetention: number;
     benchmarkCoverage: number;  // renamed from 'confidence' to avoid confusion with hardware-fit confidence
     matchReason: string;        // "Scored on: <benchmark names>; quantized to <level>"
   };

   export type LocalRecommendResult = {
     gpu?: { id: string; name: string; vramGb: number };  // present when gpu_id provided
     vramGb: number;             // effective VRAM used for calculation
     totalModels: number;        // total open-weight models in snapshot
     evaluatedModels: number;    // models with parametersBillions populated
     skippedModels: number;      // open-weight models missing hardware metadata
     snapshotNote?: string;      // diagnostic when snapshot lacks hardware fields
     recommendations: LocalModelRecommendation[];
   };

   export type LocalRecommendOptions = {
     vramGb: number;
     limit?: number;
     provider?: string;
   };
   ```
2. Implement `recommendLocalModels(task, benchmarks, models, options)`:
   - Filter models to `isOpenWeight === true` AND `parametersBillions != null`
   - **Type coercion** (CRITICAL): When constructing `ModelParams` for vram-calc, coerce optional snapshot fields to required types:
     ```typescript
     const params: ModelParams = {
       parametersBillions: model.parametersBillions!, // already filtered to non-null
       activeParametersBillions: model.activeParametersBillions ?? null,
       isMoe: model.isMoe ?? false, // undefined/null → false (prevents silent MoE miscalculation)
     };
     ```
   - For each model: call `bestQuantization(params, options.vramGb)` — skip if null (doesn't fit)
   - Score remaining models using existing `scoreBenchmarks()` + weighted scoring (same as `recommendModels`)
   - Apply `adjustedScore()` with the selected quantization level
   - Sort by adjusted score descending
   - **Diagnostic on empty result**: If zero models pass filtering, include `snapshotNote` indicating why (no hardware metadata in snapshot vs. nothing fits the VRAM constraint)
   - Return `LocalModelRecommendation[]`

**AC:** Function filters, quantizes, scores, and ranks. Type coercion for ModelParams is explicit. Empty results include diagnostic. Pure function, no side effects.

### Task 8: Add `recommendLocalModels` unit tests
**Bead:** Sylveste-0szu (F3)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/recommend.test.ts` — add test section

**Steps:**
1. Create mock models with hardware fields (extend existing `makeModel` helper):
   - Open-weight 7B model (fits on 8GB at Q4)
   - Open-weight 70B model (needs 48GB at Q4)
   - Closed-source model (should be filtered out)
   - MoE model (176B total, 22B active)
2. Test cases:
   - 24GB VRAM: returns 7B and MoE model, not 70B or closed
   - 8GB VRAM: returns only 7B at Q4 or Q5
   - Closed models always filtered out
   - Model with `isOpenWeight: undefined` (old snapshot) filtered out — distinct from `isOpenWeight: false`
   - Empty result when nothing fits — includes diagnostic `snapshotNote`
   - Empty result when no models have `parametersBillions` — diagnostic says "hardware metadata not present"
   - Adjusted scores < base scores (quality retention applied)
   - `benchmarkCoverage` (not `confidence`) populated correctly
   - Provider filter works
   - MoE model uses `activeParametersBillions` via coercion (`isMoe ?? false`)
3. Run: `pnpm test`

**AC:** All test cases pass. Edge cases covered.

### Task 9: Register `recommend_local_models` MCP tool
**Bead:** Sylveste-0szu (F3)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`
**Files:**
- `src/index.ts` — add tool registration

**Steps:**
1. Add import: `import { recommendLocalModels } from "./recommend.js"` and local-calc imports
2. Register tool with Zod schema:
   ```typescript
   server.registerTool("recommend_local_models", {
     description: "Recommend open-weight models that fit on local hardware, ranked by quantization-adjusted benchmark scores. Provide gpu_id (e.g. 'rtx-4090') to look up a known GPU, vram_gb to specify VRAM directly, or both (vram_gb overrides gpu_id lookup). At least one is required. VRAM estimates assume minimal context windows. For multi-GPU setups, pass combined VRAM as vram_gb. Quantization levels tried: Q4, Q5, Q8, FP16 (Q2 excluded by default).",
     inputSchema: {
       task: z.string().describe("Natural language task description"),
       gpu_id: z.string().optional().describe("GPU identifier (e.g. 'rtx-4090', 'm4-max-128gb')"),
       vram_gb: z.number().optional().describe("Available VRAM in GB (overrides gpu_id lookup)"),
       provider: z.string().optional().describe("Filter by provider"),
       limit: z.number().min(1).max(MAX_LIMIT).optional().describe("Max results (default 10)"),
     },
   }, async (input) => {
     // Validate: at least one of gpu_id or vram_gb
     // Resolve gpu_id → vramGb via getGpuById()
     // Check snapshot has hardware data; return structured diagnostic if not
     // Call recommendLocalModels()
     // Format response as LocalRecommendResult with GPU info envelope
   });
   ```
3. Handle validation:
   - Neither `gpu_id` nor `vram_gb` → error message
   - `gpu_id` not found → error message listing valid IDs
   - `vram_gb` from `gpu_id` lookup, overridden by explicit `vram_gb`
   - Snapshot lacks hardware fields → return `LocalRecommendResult` with `snapshotNote: "Current snapshot (v2) does not include hardware metadata. Upgrade to snapshot v3."`
4. Build: `pnpm build`

**AC:** Tool registered. Schema validates input. Responds with recommendations, diagnostic for old snapshots, or clear error.

### Task 10: Integration test and final validation
**Bead:** Sylveste-0szu (F3)
**Repo:** `/home/mk/projects/Sylveste/interverse/interrank`

**Steps:**
1. Run full test suite: `pnpm test`
2. Build: `pnpm build`
3. Smoke test with local snapshot (if available): `pnpm mcp` and call `recommend_local_models` via MCP
4. Verify existing tools still work (no regressions)

**AC:** All tests pass. Build clean. No regressions.

## Execution Order

```
Task 1 ─→ Task 2 ─→ Task 3   (agmodb, sequential — DB → export → publish)
                         ↓ (gate: user approval for agmodb push)
Task 4 ─┐
        ├─→ Task 7 ─→ Task 8 ─→ Task 9 ─→ Task 10   (interrank F3)
Task 5 ─┘
  ↓
Task 6   (local-calc tests, runs after Task 5)
```

Tasks 1-3 (agmodb) and Tasks 4-6 (interrank F2) are independent — can be parallelized.
Tasks 4 AND 5 are co-prerequisites for Task 7 (types + local-calc both needed).
Task 6 (local-calc tests) can run independently after Task 5.
Task 3 (publish snapshot) is a gate — needs DB access.

## Risk Assessment

- **Low risk:** Interrank changes are purely additive — new types, new module, new tool. No changes to existing tools.
- **Medium risk:** agmodb snapshot export requires DB access (Neon). If DB isn't available, can proceed with interrank work using mock data and publish snapshot later.
- **Mitigation:** Optional fields in interrank types mean it works with old snapshots (structured diagnostic returned until new snapshot arrives).

## Plan Review Findings (incorporated)

Reviewed by architecture, correctness, and product agents. P0 fixes applied to plan above:

1. **[Correctness CRITICAL]** Type coercion for `ModelParams` — `isMoe ?? false` prevents silent MoE miscalculation. Added to Task 7.
2. **[Architecture]** Snapshot version bump to v3 — added to Task 2.
3. **[Architecture]** Selective barrel exports — updated Task 5 to export only used symbols.
4. **[Architecture]** Execution diagram fixed — Tasks 4+5 as co-prerequisites for Task 7.
5. **[Product CRITICAL]** Pre-snapshot diagnostic — `LocalRecommendResult` envelope with `snapshotNote` added to Task 7 types and Task 9.
6. **[Product]** `confidence` → `benchmarkCoverage` rename — updated Task 7 type.
7. **[Product]** Tool description expanded — Q2 exclusion, multi-GPU workaround, VRAM caveats. Updated Task 9.
8. **[Product]** `matchReason` format specified — includes benchmark names and quantization level.
9. **[Correctness]** `isOpenWeight: undefined` test case — added to Task 8.
10. **[Architecture]** Provenance headers on vendored files — added to Task 5.

### Deferred (not blocking execution):
- `activeParametersBillions = 0` truthiness edge case (pathological, no real data has this)
- Fixed 1.0GB KV cache approximation (pre-existing in agmodb, documented in tool description)
- `SnapshotStore.get()` double-fetch race (pre-existing, not introduced by this change)
- `list_gpus` tool (future iteration)
- `fitsAt: QuantizationLevel[]` array in response (nice-to-have, can add later)
