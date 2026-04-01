#!/usr/bin/env bash
# Interlab benchmark: measure tok/s at different kv_group_size values.
# Outputs METRIC lines for interlab to parse.
set -euo pipefail

MODEL="${INTERFERE_MODEL:-$HOME/.cache/huggingface/models/Qwen3.5-35B-A3B-4bit}"
KV_BITS="${INTERFERE_KV_BITS:-8}"
KV_GROUP_SIZE="${INTERFERE_KV_GROUP_SIZE:-64}"
MAX_TOKENS="${INTERFERE_MAX_TOKENS:-100}"

cd "$(dirname "$0")"

echo "=== interlab benchmark: kv_group_size=$KV_GROUP_SIZE, kv_bits=$KV_BITS ==="
echo "Model: $MODEL"

# Run benchmark and capture JSON output
result=$(.venv/bin/python -m server.benchmark_cli \
  --model "$MODEL" \
  --kv-bits "$KV_BITS" \
  --kv-group-size "$KV_GROUP_SIZE" \
  --max-tokens "$MAX_TOKENS" \
  --json 2>&1)

# Parse metrics from JSON
median_tps=$(echo "$result" | .venv/bin/python -c "import json,sys; d=json.load(sys.stdin); print(d['median_tok_s'])")
mean_tps=$(echo "$result" | .venv/bin/python -c "import json,sys; d=json.load(sys.stdin); print(d['mean_tok_s'])")
p5_tps=$(echo "$result" | .venv/bin/python -c "import json,sys; d=json.load(sys.stdin); print(d['p5_tok_s'])")
p95_tps=$(echo "$result" | .venv/bin/python -c "import json,sys; d=json.load(sys.stdin); print(d['p95_tok_s'])")
ttft=$(echo "$result" | .venv/bin/python -c "import json,sys; d=json.load(sys.stdin); print(d['median_ttft_s'])")

# Output METRIC lines for interlab
echo "METRIC median_tok_s=$median_tps"
echo "METRIC mean_tok_s=$mean_tps"
echo "METRIC p5_tok_s=$p5_tps"
echo "METRIC p95_tok_s=$p95_tps"
echo "METRIC median_ttft_s=$ttft"
echo "METRIC kv_group_size=$KV_GROUP_SIZE"
echo "METRIC kv_bits=$KV_BITS"
