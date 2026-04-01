---
bead: sylveste-l2j
title: Q3 GGUF extraction — complete but runtime blocked
---

# Reflect: Q3 GGUF Download & Extraction

## What worked
- Upstream guide (docs/model-download-and-convert.md) was accurate — extraction scripts ran cleanly
- Q3 expert repack produced correct layout: 60 layers, 5.44MB/expert, outlier layer 27 handled
- GGUF embedding (Q8_0, 1.08GB) and LM head (Q6_K, 796MB) extracted successfully
- Deleted raw MLX safetensors (411 GB reclaimed) after copying tokenizer.json

## What didn't work
- Q3 inference produces NaN logits — hidden rms=nan after final_norm, model outputs token_id=0
- Both Q3 AND 4-bit paths run at 0.04 tok/s with Expert I/O: 0.0ms (upstream: 12.9 / 9.5 tok/s)
- The binary build compiles but the runtime behavior diverges from upstream's tested config

## Lessons
- **Extract and runtime are independent concerns.** The data pipeline is validated by layout.json + file sizes, not by running inference. Coupling them delays the extraction completion.
- **Upstream perf claims need our-hardware reproduction.** The 12.9 tok/s was measured on the upstream author's M5 Max — our build may differ in Metal shader compilation, macOS version, or model directory structure.
- **Created sylveste-2nt (P1)** to track the runtime investigation separately.
