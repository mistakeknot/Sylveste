# BHQ Validation on 7B+ Model

Bead: sylveste-d5e | Parent: sylveste-bhq (CLOSED)

## Goal

Validate BHQ (TurboQuant v3) on a model with head_dim=128 where the Beta distribution concentrates better. Determine if the synthetic attention NMSE advantage (36% at 2-bit, 12% at 3-bit) translates to coherent end-to-end generation.

## Steps

### 1. Select and load model
- Find a 7B model that fits in 128GB with KV cache headroom
- Prefer fp16 weights to avoid double-quantization penalty
- Candidate: `mlx-community/Qwen2.5-7B-Instruct-4bit` (known to work with interfere)
- Alternative: `mlx-community/Qwen2.5-3B-Instruct` (fp16, smaller, head_dim=128)

### 2. Verify model config
- Confirm head_dim >= 128
- Confirm d_model/hidden_size fallback works for this model's ModelArgs
- Check num_kv_heads for GQA support

### 3. Run quality benchmarks
- Short prompts (< 100 tokens): coherence check
- Medium prompts (100-500 tokens): quality comparison
- Compare: FP16 baseline, Native-4, Native-3, Native-2, BHQ-4, BHQ-3, BHQ-2
- Metric: qualitative coherence + benchmark throughput

### 4. Run the autoresearch harness
- `bash interlab-bhq-tune.sh` with the 7B model
- Compare METRIC lines between BHQ and baseline

### 5. Document results
- Update sylveste-bhq notes with findings
- Close sylveste-d5e with verdict: BHQ viable at 2-3 bit on larger models? Y/N

## Kill conditions
- If BHQ-3 quality is worse than Native-4 on 7B, BHQ has no practical value
- If model doesn't fit in memory, try 3B model instead
