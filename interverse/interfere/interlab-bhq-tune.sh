#!/usr/bin/env bash
# Autoresearch benchmark for BHQ (TurboQuant v3) Lloyd-Max KV cache quantization.
# Emits METRIC lines for interlab's py-bench-harness.
#
# Mutation parameters (set by autoresearch via env vars):
#   BHQ_KV_BITS   - centroid quantization bits (2, 3, 4, 8). Default: 3
#   BHQ_MODEL     - model to benchmark. Default: test model
#   BHQ_MAX_TOKENS - max tokens per prompt. Default: 200
#
# Usage:
#   bash interlab-bhq-tune.sh                    # defaults
#   BHQ_KV_BITS=2 bash interlab-bhq-tune.sh     # test 2-bit

set -euo pipefail
cd "$(dirname "$0")"

MODEL="${BHQ_MODEL:-mlx-community/Qwen2.5-0.5B-Instruct-4bit}"
MAX_TOKENS="${BHQ_MAX_TOKENS:-200}"
KV_BITS="${BHQ_KV_BITS:-3}"

echo "=== BHQ (TurboQuant v3) Benchmark ==="
echo "  model: $MODEL"
echo "  kv_bits: $KV_BITS"
echo "  max_tokens: $MAX_TOKENS"
echo ""

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Run BHQ benchmark
uv run python -m server.benchmark_cli \
    --model "$MODEL" \
    --kv-mode bhq \
    --kv-bits "$KV_BITS" \
    --max-tokens "$MAX_TOKENS" \
    --json > "$tmpdir/bhq.json" 2>/dev/null || { echo "METRIC error 1"; exit 1; }

# Emit interlab METRIC lines
uv run python -c "
import json, sys
with open('$tmpdir/bhq.json') as f:
    d = json.load(f)
print(f'METRIC tok_per_s {d.get(\"median_tok_s\", 0)}')
print(f'METRIC mean_tok_per_s {d.get(\"mean_tok_s\", 0)}')
print(f'METRIC ttft_s {d.get(\"median_ttft_s\", 0)}')
print(f'METRIC total_tokens {d.get(\"total_tokens\", 0)}')
print(f'METRIC total_time_s {d.get(\"total_time_s\", 0)}')
print(f'METRIC kv_mode {d.get(\"kv_mode\", \"standard\")}')
print(f'METRIC kv_bits {d.get(\"kv_bits\", \"none\")}')
"

# Run baseline (vanilla kv_bits, no BHQ) for comparison
echo ""
echo "=== Baseline (kv_bits=${KV_BITS}, no BHQ) ==="
uv run python -m server.benchmark_cli \
    --model "$MODEL" \
    --kv-bits "$KV_BITS" \
    --max-tokens "$MAX_TOKENS" \
    --json > "$tmpdir/baseline.json" 2>/dev/null || { echo "METRIC baseline_error 1"; exit 0; }

uv run python -c "
import json
with open('$tmpdir/baseline.json') as f:
    d = json.load(f)
print(f'METRIC baseline_tok_per_s {d.get(\"median_tok_s\", 0)}')
print(f'METRIC baseline_ttft_s {d.get(\"median_ttft_s\", 0)}')
"
