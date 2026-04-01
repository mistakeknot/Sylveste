---
bead: sylveste-8v3
date: 2026-03-28
type: brainstorm
---

# Benchmarking Kimi K2.5 3-bit (1T params, 32B active)

## Model Facts

- Architecture: DeepSeek V3 derivative (KimiK25ForConditionalGeneration)
- Total params: ~1T, Active: 32B per token
- 61 layers, hidden_size=7168, MLA attention (kv_lora_rank=512)
- 256 routed experts + 1 shared, top-8 selection per token
- First 3 layers dense, remaining 58 are MoE
- 91 safetensors shards, 418GB total at 3-bit quantization
- Multimodal (vision + text) — benchmarking text only
- mlx-lm has native support (`mlx_lm.models.kimi_k25`)

## Constraints

- M5 Max 128GB unified memory — model is 3.3x RAM
- Must use SSD streaming (mmap or pread-based)
- M5 Max SSD: ~36 GB/s sequential read, ~30 GB/s random read
- OS page cache: critical for hot-expert caching

## Benchmark Approaches (ordered by effort)

### Approach 1: mlx-lm with mmap (lowest effort)

mlx-lm supports loading safetensors via mmap. For models larger than RAM, the
OS page cache manages eviction. Expected performance: 1-3 tok/s (cold), possibly
5+ tok/s (warm, if expert reuse is high).

```bash
uv run python -m mlx_lm.generate \
  --model ~/.cache/huggingface/models/Kimi-K2.5-3bit/ \
  --prompt "Explain quantum computing in simple terms" \
  --max-tokens 100
```

Risk: mlx-lm may OOM trying to load the full model into Metal buffer memory.
The mmap path needs to be verified — mlx might try to allocate 418GB Metal buffers
even when using mmap, which would fail on 128GB.

### Approach 2: flash-moe port (highest performance)

Port flash-moe's Metal+pread SSD streaming to Kimi K2.5. Requires:
1. Generate expert_index.json for Kimi's safetensors layout
2. Export vocab.bin from Kimi's tokenizer
3. Modify infer.m for MLA attention (vs standard GQA in Qwen)
4. Repack experts into streaming-friendly layout

Estimated effort: 2-3 days. Expected performance: 6-10 tok/s based on Qwen 397B
baseline (11.1 tok/s) scaled by model size ratio.

### Approach 3: llama.cpp partial offload (if GGUF exists)

Check if GGUF conversion exists. llama.cpp supports partial GPU offload with
SSD streaming for remaining layers.

## Benchmark Protocol

1. Cold start: time to first token (model load + prefill)
2. Warm decode: tok/s after first few tokens (page cache warm)
3. Sustained decode: tok/s over 200 token generation
4. Memory pressure: peak Metal memory usage
5. Quality check: generate 5 standard prompts, spot-check coherence

## Decision

Start with Approach 1 (mlx-lm mmap) to get a baseline. If it works at all,
we have data. If it OOMs, that tells us we need Approach 2 or 3.
