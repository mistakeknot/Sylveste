---
name: BHQ validation results on Qwen2.5-3B
description: Lloyd-Max centroid quantization (TurboQuant v3) dramatically outperforms MLX native affine quantization at 4-bit on models with head_dim=128
type: experiment-result
tags: [interfer, bhq, turbo-quant, kv-cache, quantization, mlx]
bead: sylveste-d5e
date: 2026-03-27
---

## Finding

BHQ-4 produces coherent text while Native-4 produces garbage on Qwen2.5-3B-Instruct-4bit (head_dim=128, GQA 8:1).

## Evidence

Model: `mlx-community/Qwen2.5-3B-Instruct-4bit` (36 layers, hidden=2048, head_dim=128)

### Quality (TCP/UDP prompt)
- **FP16**: Perfect coherent answer about TCP vs UDP
- **Native-4**: "TCP TCP (Transmission (Transmission Transmission..." — repetitive garbage
- **BHQ-4**: "TCP and UDP are two of the most common protocols..." — grammatical, answers question
- **BHQ-3**: Starts coherent, degrades after ~30 tokens

### Throughput
| Mode | Median TPS | Ratio vs FP16 |
|------|-----------|---------------|
| FP16 | 76.8 | 1.00x |
| Native-4 | 82.5 | 1.07x |
| BHQ-4 | 56.1 | 0.73x |
| BHQ-3 | 65.8 | 0.86x |

## Why BHQ wins

1. **Norm preservation**: BHQ stores per-vector norms (fp16) + quantized unit-direction. Native affine quantizes the raw (un-normalized) vectors, losing both magnitude and direction information.
2. **Optimal centroids**: Lloyd-Max centroids are MSE-optimal for the post-rotation Beta distribution. Native affine uses uniform grid + scale + bias which is suboptimal for the concentrated coordinate distribution.
3. **head_dim=128 concentrates the Beta distribution** better than head_dim=64 (the 0.5B model). At d=128, each coordinate has std ~0.088 vs ~0.125 at d=64 — tighter concentration means fewer centroids cover more of the distribution mass.

## Why 0.5B failed but 3B worked

The 0.5B model has head_dim=64, which is borderline for Beta concentration. Also, it has 4-bit weight quantization, so KV quantization on top is double-quantization. The 3B model also has 4-bit weights but the larger head_dim provides enough precision headroom.

## Next steps

- `sylveste-naj`: Speed optimization (30% gap to close)
- `sylveste-ipu`: QJL residual for sub-3-bit inner products
