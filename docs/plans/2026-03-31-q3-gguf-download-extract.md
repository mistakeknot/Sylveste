---
bead: sylveste-l2j
title: Download and extract Q3 GGUF experts + overlays for Qwen3.5-397B
complexity: C2
---

# Plan: Q3 GGUF Download & Extraction

## Prerequisites
- Base model already at `~/Models/flash_mlx_4bit/` (confirmed: model_weights.bin, packed_experts/, vocab.bin)
- llama.cpp at `~/projects/llama.cpp` (for gguf Python bindings)
- flash-moe repo at `~/projects/flash-moe` (m5-nax merged, extraction scripts available)

## Steps

### 1. Download Unsloth Q3 GGUF shard
```bash
hf download unsloth/Qwen3.5-397B-A17B-GGUF \
  --include "Qwen3.5-397B-A17B-UD-Q3_K_XL-00001-of-00005.gguf" \
  --local-dir ~/Models/Qwen3.5-Q3-GGUF
```
Only shard 1 needed — expert tensors + embedding + LM head are in shards 1-5 but scripts handle multi-shard via GGUFReader.

Actually: need ALL shards (expert tensors span shards). Full download:
```bash
hf download unsloth/Qwen3.5-397B-A17B-GGUF \
  --include "Qwen3.5-397B-A17B-UD-Q3_K_XL-*.gguf" \
  --local-dir ~/Models/Qwen3.5-Q3-GGUF
```
~163 GB download.

### 2. Extract GGUF embedding (Q8_0)
```bash
python3 autoresearch/extract_gguf_embedding.py \
  --gguf ~/Models/Qwen3.5-Q3-GGUF/Qwen3.5-397B-A17B-UD-Q3_K_XL-00001-of-00005.gguf \
  --llama-cpp-root ~/projects/llama.cpp \
  --out-bin ~/Models/flash_mlx_4bit/gguf/embedding_q8_0.bin \
  --out-json ~/Models/flash_mlx_4bit/gguf/embedding_q8_0.json
```

### 3. Extract GGUF LM head (Q6_K)
```bash
python3 autoresearch/extract_gguf_lm_head.py \
  --gguf ~/Models/Qwen3.5-Q3-GGUF/Qwen3.5-397B-A17B-UD-Q3_K_XL-00001-of-00005.gguf \
  --llama-cpp-root ~/projects/llama.cpp \
  --out-bin ~/Models/flash_mlx_4bit/gguf/lm_head_q6.bin \
  --out-json ~/Models/flash_mlx_4bit/gguf/lm_head_q6.json
```

### 4. Repack Q3 streamed experts (all 60 layers)
```bash
python3 autoresearch/repack_experts_q3.py \
  --model ~/Models/flash_mlx_4bit \
  --gguf ~/Models/Qwen3.5-Q3-GGUF/Qwen3.5-397B-A17B-UD-Q3_K_XL-00001-of-00005.gguf \
  --llama-cpp-root ~/projects/llama.cpp \
  --output ~/Models/flash_mlx_4bit/packed_experts_Q3 \
  --layers all \
  --include-outlier-layer
```

### 5. Smoke test Q3 inference
```bash
~/projects/flash-moe/metal_infer/infer \
  --model ~/Models/flash_mlx_4bit \
  --q3-experts \
  --cache-io-split 4 \
  --gguf-embedding ~/Models/flash_mlx_4bit/gguf/embedding_q8_0.bin \
  --gguf-lm-head ~/Models/flash_mlx_4bit/gguf/lm_head_q6.bin \
  --prompt "What is Apple Neural Engine?" \
  --tokens 50 --stream --timing
```

## Verification
- `packed_experts_Q3/` has 60 layer files + layout.json
- `gguf/embedding_q8_0.bin` and `gguf/lm_head_q6.bin` exist
- Smoke test produces coherent output at >10 tok/s
