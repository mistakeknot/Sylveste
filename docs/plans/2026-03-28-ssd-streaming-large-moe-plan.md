---
bead: sylveste-8v3
epic: sylveste-14g
date: 2026-03-28
status: plan
---

# Plan: SSD Streaming Inference for 700B+ MoE Models

## Phase 1: DeepSeek V3.2 Baseline (highest probability of success)

### Task 1.1: Download DeepSeek V3.2 GGUF 1-bit
- Download `unsloth/DeepSeek-V3.2-GGUF` UD-TQ1_0 (~131GB)
- Path: `~/.cache/huggingface/models/DeepSeek-V3.2-GGUF-1bit/`
- **Why 1-bit:** Nearly fits in 128GB RAM. Minimal SSD swap needed.

### Task 1.2: Benchmark DeepSeek V3.2 via Ollama
- `ollama pull` or create a Modelfile pointing at the GGUF
- Run: `ollama run deepseek-v3.2-1bit "Explain quantum computing in 200 words"`
- Measure: tok/s, time to first token, output quality
- If ollama doesn't support the model directly, use `llama-cli` from llama.cpp

### Task 1.3: Benchmark with optimization flags
- Build llama.cpp from source with Metal support
- Test configurations:
  - `-ngl 99` (all layers to GPU)
  - `-ngl 99 -ot ".ffn_.*_exps.=CPU"` (experts on CPU, attention on GPU)
  - `--fit on` (auto-distribute)
  - Various `-c` context sizes (512, 2048, 4096)
- Record: tok/s for each configuration

### Task 1.4: Also test 2-bit GGUF if 1-bit quality is poor
- Download `UD-Q2_K_XL` (~200GB) only if 1-bit output is incoherent
- Compare quality vs speed tradeoff

**Exit criteria:** DeepSeek V3.2 benchmark numbers recorded. Decision on whether 8 tok/s is achievable.

## Phase 2: GLM-5 Baseline

### Task 2.1: Download GLM-5 GGUF 1-bit
- Download `unsloth/GLM-5-GGUF` UD-TQ1_0 (~176GB)
- Note: GLM-5's sparse attention (DSA) indexer tensors are unused in llama.cpp — quality may be suboptimal

### Task 2.2: Benchmark GLM-5 via llama.cpp
- Same flag matrix as Task 1.3
- Extra attention to quality — DSA missing in llama.cpp may degrade output

**Exit criteria:** GLM-5 benchmark numbers. Quality assessment (is it usable without DSA?).

## Phase 3: Kimi K2.5 Baseline

### Task 3.1: Download Kimi K2.5 GGUF 1-bit
- Download `unsloth/Kimi-K2.5-GGUF` UD-TQ1_0 (~240GB)
- This is the largest — 112GB overflow beyond RAM

### Task 3.2: Benchmark Kimi K2.5 via llama.cpp
- Same flag matrix
- Expected: <2 tok/s based on published benchmarks for <240GB RAM

**Exit criteria:** Kimi K2.5 baseline number. If <3 tok/s, flag for custom engine investigation.

## Phase 4: Hypura Evaluation (if Phase 1-3 baselines are below target)

### Task 4.1: Install and test Hypura
- Clone from `github.com/t8/hypura`
- Test with DeepSeek V3.2 GGUF first (most likely to work)
- Compare tok/s vs llama.cpp baseline

### Task 4.2: Test Hypura MoE router interception
- Verify it correctly intercepts expert selection for each architecture
- Measure cache hit rate improvement

**Exit criteria:** Hypura performance numbers. Decision on whether it's a viable path.

## Phase 5: SSD Profiling + Page Cache Analysis

### Task 5.1: Run flash-moe's cache_pread_bench on M5 Max
- `cd /Users/sma/projects/flash-moe/metal_infer && make cachebench`
- Measure actual NVMe pread throughput at various split counts
- Compare to published specs (7.4 GB/s sequential)

### Task 5.2: Profile page cache during inference
- Monitor `vm_stat` during llama.cpp inference
- Measure page fault rate, cache hit rate
- Identify if the bottleneck is SSD bandwidth vs page cache misses

**Exit criteria:** SSD benchmark numbers. Page cache behavior documented.

## Phase 6: Decision Gate

After Phases 1-5, we'll have:
- Baseline tok/s for all 3 models via llama.cpp
- Hypura numbers (if tested)
- SSD profiling data

**Decision matrix:**
| If baseline is... | Then... |
|-------------------|---------|
| 8+ tok/s | Done — document and close bead |
| 5-8 tok/s | Optimize flags, try Hypura, profile page cache |
| 2-5 tok/s | Evaluate flash-moe port vs Hypura optimization |
| <2 tok/s | Consider 2-bit GGUF, or flash-moe port required |

## Phase 7: Custom Engine (only if Phase 6 requires it)

### Task 7.1: Evaluate flash-moe port feasibility
- Compare Kimi K2.5 architecture to Qwen3.5-397B (which flash-moe supports)
- Identify shared components vs model-specific code
- Estimate: how much of flash-moe's infer.m can be reused?

### Task 7.2: Build minimal SSD streaming prototype
- Reuse flash-moe's pread + page cache pattern
- Implement model-agnostic weight loading from safetensors
- Target: proof-of-concept on DeepSeek V3.2 (most similar to Qwen3.5)

## Dependencies

- Ollama 0.18.2 installed ✓
- flash-moe built and working ✓
- All MLX weights downloaded ✓
- GGUF downloads needed for Phases 1-3

## Files in scope

- `/Users/sma/projects/flash-moe/` — reference implementation
- `/Users/sma/projects/Sylveste/interverse/interfer/` — interfer server (future integration)
- `~/.cache/huggingface/models/` — model storage
