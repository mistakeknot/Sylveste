# flash-moe Integration Feasibility Study

**Bead:** Sylveste-5pa
**Date:** 2026-03-26
**Status:** Investigation complete — recommend proceeding

## Summary

[flash-moe](https://github.com/danveloper/flash-moe) is a pure C/Metal inference engine that runs Qwen3.5-397B-A17B (a 397B MoE model) by streaming expert weights from SSD. On our M5 Max 128GB, benchmarks show this is highly feasible with significantly better performance than the original 48GB M3 Max test rig.

## Hardware Benchmarks (M5 Max 128GB, 4TB SSD)

| Test | Throughput | Notes |
|------|-----------|-------|
| Sequential read (4GB) | 36.1 GB/s | 2x faster than M3 Max (17.5 GB/s) |
| Random 6.75MB pread (cold) | 26.7 GB/s | 1.5x faster, simulates expert loading |
| Random 6.75MB pread (warm) | 29.6 GB/s | Page cache hit |
| Sequential write | 5.7 GB/s | Weight preparation |

## Performance Estimate

flash-moe on M3 Max 48GB: **4.36 tok/s** (4-bit)

On our M5 Max 128GB:
- SSD I/O per layer: ~1.6ms (vs 2.41ms on M3 Max)
- Page cache: ~120GB available (vs ~42GB) → 57% of model fits vs ~20%
- Expert cache hit rate: ~85-90% estimated (vs ~71%)
- **Estimated: 7-10 tok/s at 4-bit**
- With warm cache on repeated workloads: potentially **10-12 tok/s**

## Architecture Assessment

### What flash-moe is
- Pure C/Objective-C + Metal compute shaders (~8200 lines total)
- Custom 4-bit/2-bit dequantization kernels
- SSD expert streaming via parallel `pread()` with GCD dispatch
- Relies on OS page cache (no custom LRU)
- Supports tool calling at 4-bit (2-bit breaks JSON)
- Single binary: `./infer` (batch) and `./chat` (interactive TUI)

### What it isn't
- No Python, no frameworks, no library interface
- No HTTP API (only CLI/TUI)
- Only supports Qwen3.5-397B-A17B
- Requires weight preparation: `extract_weights.py` → `model_weights.bin` + `packed_experts/`

## Integration Options

### Option A: Subprocess bridge (recommended first step)
- Build flash-moe binary on the Mac
- interfer calls it as a subprocess, pipes stdin/stdout
- Parse SSE-like output into our existing token streaming protocol
- Pros: Fastest path to running 397B locally, no code changes to flash-moe
- Cons: Extra process, IPC overhead, limited control

### Option B: HTTP wrapper around flash-moe
- Write a thin C/Objective-C HTTP server around `infer.m`
- Expose OpenAI-compatible /v1/chat/completions endpoint
- interfer routes to it like any other model endpoint
- Pros: Clean integration, standard API
- Cons: Requires modifying flash-moe C code

### Option C: Port SSD-streaming to our MLX pipeline
- Implement expert streaming in the Metal worker subprocess
- Use pread() for expert loading, keep InferenceEngine for generation
- Pros: Full control, integrates with existing experiment hooks
- Cons: Major engineering effort, may not match hand-tuned Metal kernels

### Recommendation
Start with **Option A** (subprocess bridge) to validate performance on our hardware. If 7+ tok/s is confirmed, invest in **Option B** for production integration. Option C is a longer-term research project.

## Disk Space Requirements

- Model download (HuggingFace): ~209GB (4-bit Qwen3.5-397B-A17B)
- Extracted non-expert weights: ~5.5GB (`model_weights.bin`)
- Packed experts directory: ~209GB (`packed_experts/`)
- **Total: ~420GB** (original + extracted)
- After extraction, original can be deleted: **~215GB permanent**
- 4TB SSD has ample headroom

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Model quality unverified | Medium | Run eval suite after integration |
| 2-bit breaks tool calling | Low | Use 4-bit only (confirmed working) |
| flash-moe maintenance | Medium | Fork and maintain; code is small (~8K lines) |
| Disk space (215GB) | Low | 4TB SSD, ~5% of capacity |
| Build issues on M5 Max | Low | Standard clang/Metal toolchain |

## Next Steps

1. Clone flash-moe repo
2. Download Qwen3.5-397B-A17B-4bit from HuggingFace (~209GB, several hours)
3. Run extract_weights.py to prepare binary format
4. Build and run `./infer` with timing to validate performance estimate
5. If confirmed: implement subprocess bridge in interfer
6. Create interlab experiment campaign to measure quality vs cloud models
