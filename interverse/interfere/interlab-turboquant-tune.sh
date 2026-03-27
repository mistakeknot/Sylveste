#!/usr/bin/env bash
# Autoresearch benchmark for TurboQuant polar-transformed KV cache.
# Emits METRIC lines for interlab's py-bench-harness.
#
# Mutation parameters (set by autoresearch via env vars):
#   TQ_KV_BITS    - native quantization bits (2, 4, 8). Default: 4
#   TQ_QJL_ENABLED - QJL residual correction (true/false). Default: false
#   TQ_JL_DIM     - JL projection dimensions (32-256). Default: 256
#   TQ_MODEL      - model to benchmark. Default: test model
#   TQ_MAX_TOKENS - max tokens per prompt. Default: 200
#
# Usage:
#   bash interlab-turboquant-tune.sh                    # defaults
#   TQ_KV_BITS=2 bash interlab-turboquant-tune.sh       # test 2-bit
#   TQ_QJL_ENABLED=true TQ_JL_DIM=128 bash interlab-turboquant-tune.sh

set -euo pipefail
cd "$(dirname "$0")"

# Configure experiment via env vars
export INTERFERE_EXP_TURBO_QUANT_ENABLED=true
export INTERFERE_EXP_TURBO_QUANT_KV_BITS="${TQ_KV_BITS:-4}"
export INTERFERE_EXP_TURBO_QUANT_QJL_ENABLED="${TQ_QJL_ENABLED:-false}"
export INTERFERE_EXP_TURBO_QUANT_JL_DIM="${TQ_JL_DIM:-256}"

MODEL="${TQ_MODEL:-mlx-community/Qwen2.5-0.5B-Instruct-4bit}"
MAX_TOKENS="${TQ_MAX_TOKENS:-200}"

echo "=== TurboQuant Benchmark ==="
echo "  model: $MODEL"
echo "  kv_bits: ${TQ_KV_BITS:-4}"
echo "  qjl_enabled: ${TQ_QJL_ENABLED:-false}"
echo "  jl_dim: ${TQ_JL_DIM:-256}"
echo "  max_tokens: $MAX_TOKENS"
echo ""

# Run TurboQuant benchmark
result=$(uv run python -m server.benchmark_cli \
    --model "$MODEL" \
    --kv-mode turbo_quant \
    --max-tokens "$MAX_TOKENS" \
    --json 2>/dev/null) || { echo "METRIC error 1"; exit 1; }

# Emit interlab METRIC lines
python3 -c "
import json, sys
d = json.loads('''$result''')
print(f'METRIC tok_per_s {d.get(\"median_tok_s\", 0)}')
print(f'METRIC mean_tok_per_s {d.get(\"mean_tok_s\", 0)}')
print(f'METRIC ttft_s {d.get(\"median_ttft_s\", 0)}')
print(f'METRIC total_tokens {d.get(\"total_tokens\", 0)}')
print(f'METRIC total_time_s {d.get(\"total_time_s\", 0)}')
print(f'METRIC kv_mode {d.get(\"kv_mode\", \"standard\")}')
print(f'METRIC kv_bits {d.get(\"kv_bits\", \"none\")}')
"

# Run baseline (vanilla kv_bits, no polar transform) for comparison
echo ""
echo "=== Baseline (kv_bits=${TQ_KV_BITS:-4}, no polar) ==="
baseline=$(uv run python -m server.benchmark_cli \
    --model "$MODEL" \
    --kv-bits "${TQ_KV_BITS:-4}" \
    --max-tokens "$MAX_TOKENS" \
    --json 2>/dev/null) || { echo "METRIC baseline_error 1"; exit 0; }

python3 -c "
import json
d = json.loads('''$baseline''')
print(f'METRIC baseline_tok_per_s {d.get(\"median_tok_s\", 0)}')
print(f'METRIC baseline_ttft_s {d.get(\"median_ttft_s\", 0)}')
"
