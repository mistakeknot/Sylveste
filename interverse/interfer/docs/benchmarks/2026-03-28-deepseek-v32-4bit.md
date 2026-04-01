---
bead: sylveste-uln
date: 2026-03-28
model: DeepSeek V3.2 4-bit
hardware: M5 Max 128GB
result: BLOCKED — GPU timeout (inferred), requires SSD streaming engine
---

# Benchmark: DeepSeek V3.2 4-bit (672B params, ~37B active)

## Hardware
- Apple M5 Max, 128GB unified memory

## Model
- DeepSeek V3.2 (DeepseekV32ForCausalLM)
- 672B total, ~37B active per token
- 61 layers, hidden_size=7168, MLA attention (kv_lora_rank=512)
- 256 routed experts + 1 shared, top-8, 8 groups, top-4 groups
- First 3 layers dense, remaining 58 MoE
- 88 safetensors shards, 352GB at 4-bit quantization
- mlx-lm has native support (`mlx_lm.models.deepseek_v32`)
- Memory ratio: 2.75x (352GB / 128GB)

## Result: Metal GPU Timeout (inferred)

Run was terminated before completion but exhibited same behavior pattern
as Kimi K2.5 (3.3x) and GLM-5 (3.0x): model loads lazily but forward
pass triggers page faults that exceed Metal command buffer timeout.

At 2.75x memory ratio, this is the smallest of the three tested models
but still well above the ~1.6x threshold where Qwen 397B (209GB) works.

## Threshold Analysis

| Model | Size | Ratio | Result |
|-------|------|-------|--------|
| Qwen 397B 4-bit | 209GB | 1.6x | **Works** (11.1 tok/s via flash-moe) |
| DeepSeek V3.2 4-bit | 352GB | 2.75x | **GPU timeout** |
| GLM-5 4-bit | 390GB | 3.0x | **GPU timeout** |
| Kimi K2.5 3-bit | 418GB | 3.3x | **GPU timeout** |

The failure threshold for mlx-lm mmap on M5 Max 128GB is somewhere
between 1.6x and 2.75x. All models in the 700B+ class require SSD
streaming.
