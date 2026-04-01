---
title: "Local Vision-Language Models for Computer Use on Apple Silicon"
date: 2026-03-27
bead: sylveste-86r
status: complete
---

# Local Vision-Language Models for Computer Use (M5 Max 128GB)

## Recommendation

**Primary: Qwen3-VL-30B-A3B-Instruct (4-bit MLX)**
- MoE: 30B total / 3B active — best quality-per-FLOP ratio
- ~18 GB memory (same as our text-only Qwen3.5-35B-A3B)
- Full MLX support via mlx-community (multiple quantization levels)
- Native structured action output: `{"action": "left_click", "coordinate": [x, y]}`
- Supported actions: left_click, right_click, double_click, triple_click, middle_click, left_click_drag, key, type, scroll, hscroll, wait
- Strong GUI grounding (ScreenSpot family scores >93%)
- Apache 2.0 license

**Fallback / fast path: Qwen3-VL-8B-Instruct (4-bit MLX)**
- ~8 GB memory, ~200+ tok/s on M5 Max
- 93.6% ScreenSpot (Thinking variant)
- Better for rapid-fire action loops (<1s decisions)

## Latency Analysis

Target: Sub-2-second per action decision (screenshot → action output)

| Phase | Cold (new screenshot) | Warm (cached prefix) |
|-------|----------------------|---------------------|
| Screenshot capture | ~50-100ms | ~50-100ms |
| Image encoding (ViT) | 1.5-2.0s | ~0ms (cached) |
| Token generation (20-50 tokens) | 0.4-1.7s | 0.4-1.7s |
| **Total** | **~2.0-2.5s** | **~0.5-1.0s** |

Key optimization: **prefix caching via vllm-mlx** — if screenshot hasn't changed much, cached prefix eliminates re-encoding (28x speedup demonstrated on M4 Max).

## Recommended Architecture: Hybrid API + Vision

```
Decision Loop:
  1. Query game state via HTTP API (structured JSON) → <100ms
  2. Feed state to text-only LLM for decision-making → fast
  3. Every N actions, take screenshot → feed to Qwen3-VL for visual verification → ~2s
  4. If visual state diverges from API state, switch to full vision mode
```

## Models Evaluated

| Model | Params (Active) | MLX | GUI Actions | ScreenSpot-Pro | Memory (4-bit) | Verdict |
|-------|----------------|-----|-------------|----------------|----------------|---------|
| **Qwen3-VL-30B-A3B** | 31B (3B) | Yes | Yes | ~58%* | ~18 GB | **Use this** |
| Qwen3-VL-8B | 8B | Yes | Yes | ~50-55%* | ~8 GB | Fast fallback |
| Qwen3-VL-32B | 32B | Yes | Yes | 60.5% | ~20 GB | Dense; slower than MoE |
| Qwen3-VL-235B-A22B | 235B (22B) | Yes | Yes | 61.8% | ~140 GB | Doesn't fit 128GB |
| UI-TARS-7B | 7B | Broken | Yes | 61.6% | ~5 GB | MLX coordinates broken |
| UI-TARS-72B | 72B | No (GGUF only) | Yes | SOTA | ~42 GB | No MLX path |
| ShowUI-2B | 2B | Partial | Grounding only | N/A | ~3 GB | Too small for reasoning |
| CogAgent-9B | 18B | No | Yes | N/A | N/A | No MLX support |
| OS-Atlas-7B | 7B | No | Grounding only | 18.9% | N/A | Outperformed |
| Kimi-VL-A3B | 16B (2.8B) | No | Yes | N/A | N/A | No MLX yet |

## What to Skip

- **UI-TARS via MLX**: Community conversions generate incorrect coordinates. Dealbreaker.
- **CogAgent**: No MLX support path.
- **Qwen3-VL-235B-A22B**: Does not fit 128GB at useful quantization levels.
- **ShowUI standalone**: Too small for autonomous agent reasoning.

## Memory Budget (Dual-Model Setup)

```
Text model:   Qwen3.5-35B-A3B-4bit  = ~18 GB
Vision model: Qwen3-VL-30B-A3B-4bit = ~18 GB
Total models:                         ~36 GB
macOS + game (Bevy/MetalFX):          ~15 GB
KV cache pool:                        ~77 GB (ample)
```

Both models are MoE with ~3B active params — they can coexist without memory pressure.

## Sources

- [Qwen3-VL GitHub](https://github.com/QwenLM/Qwen3-VL)
- [Qwen3-VL Technical Report](https://arxiv.org/abs/2511.21631)
- [mlx-community Qwen3-VL Collection](https://huggingface.co/collections/mlx-community/qwen3-vl)
- [UI-TARS GitHub](https://github.com/bytedance/UI-TARS)
- [UI-TARS MLX Issue #193](https://github.com/bytedance/UI-TARS/issues/193)
- [vllm-mlx Paper](https://arxiv.org/abs/2601.19139)
- [MLX-VLM GitHub](https://github.com/Blaizzy/mlx-vlm)
- [Apple MLX + M5 Research](https://machinelearning.apple.com/research/exploring-llms-mlx-m5)
- [ScreenSpot-Pro Leaderboard](https://gui-agent.github.io/grounding-leaderboard/)
