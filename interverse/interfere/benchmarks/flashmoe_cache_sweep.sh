#!/usr/bin/env bash
# Flash-MoE expert cache sweep benchmark
# Tests different --malloc-cache sizes and measures tok/s.
#
# Usage:
#   ./benchmarks/flashmoe_cache_sweep.sh [CACHE_SIZES...]
#   ./benchmarks/flashmoe_cache_sweep.sh 0 2581 5000 10000 15000
#
# Requires: flash-moe binary, Qwen3.5-397B model files

set -euo pipefail

BINARY="${FLASHMOE_BINARY:-$HOME/projects/flash-moe/metal_infer/infer}"
BINARY_DIR="$(dirname "$BINARY")"
MODEL="${FLASHMOE_MODEL:-$HOME/Models/flash_mlx_4bit}"
PORT="${FLASHMOE_PORT:-8423}"
THINK_BUDGET="${FLASHMOE_THINK_BUDGET:-512}"

# Default sweep: 0 (no cache), 2581, 5000, 10000, 15000
CACHE_SIZES=("${@:-0 2581 5000 10000 15000}")
if [[ "${#CACHE_SIZES[@]}" -eq 1 && "${CACHE_SIZES[0]}" == *" "* ]]; then
    read -ra CACHE_SIZES <<< "${CACHE_SIZES[0]}"
fi

WARMUP_PROMPTS=3
BENCH_PROMPTS=5
MAX_TOKENS=32
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_FILE="${SCRIPT_DIR}/results_$(date +%Y%m%d_%H%M%S).tsv"
LOGFILE="/tmp/flashmoe_bench.log"

# Benchmark prompts (varied complexity to exercise different expert routes)
PROMPTS=(
    "What is the capital of France? Answer in one word."
    "Explain quantum entanglement in two sentences."
    "Write a haiku about autumn."
    "What are the first 5 prime numbers?"
    "Translate 'hello world' to Japanese."
    "What is the derivative of x^3?"
    "Name three programming languages created in the 1990s."
    "What color is the sky on Mars?"
)

kill_flashmoe() {
    pkill -f "infer.*--serve.*$PORT" 2>/dev/null || true
    sleep 2
}

check_memory_pressure() {
    # Returns 1 if system-wide free memory < 10% (real pressure, not just swap usage)
    # macOS aggressively compresses to swap even with 83% free — swap alone is unreliable
    local free_pct
    free_pct=$(memory_pressure 2>/dev/null | grep -o 'free percentage: [0-9]*%' | grep -o '[0-9]*' || echo "100")
    echo "  Memory free: ${free_pct}%"
    if [[ "$free_pct" -lt 10 ]]; then
        echo "WARNING: System memory free ${free_pct}% < 10% threshold — memory pressure too high" >&2
        return 1
    fi
    return 0
}

wait_for_ready() {
    local timeout="${1:-300}"
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q "ok"; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "ERROR: flash-moe did not become ready within ${timeout}s" >&2
    return 1
}

send_prompt() {
    local prompt="$1"
    local max_tokens="$2"
    # Use curl with streaming; flash-moe will log timing to stderr/logfile
    curl -s --max-time 300 "http://127.0.0.1:$PORT/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":$max_tokens,\"stream\":true}" \
        >/dev/null 2>&1
}

extract_metrics() {
    # Parse flash-moe's stderr log for generation metrics
    # Format: [serve] chatcmpl-N generated=M tokens in Xms (Y.YY tok/s)
    local log="$1"
    local skip_first="$2"  # skip first N entries (warmup)

    grep "generated=" "$log" | tail -n +"$((skip_first + 1))" | while read -r line; do
        local toks=$(echo "$line" | grep -o 'generated=[0-9]*' | cut -d= -f2)
        local tps=$(echo "$line" | grep -o '[0-9.]*  *tok/s' | awk '{print $1}')
        echo "$toks $tps"
    done
}

extract_cache_stats() {
    # Parse malloc_cache final stats from log (may not exist for cache=0)
    local log="$1"
    grep "malloc_cache.*Final\|malloc_cache.*hit rate\|cache.*hits.*misses" "$log" | tail -1 || true
}

echo "═══════════════════════════════════════════════════════"
echo "Flash-MoE Expert Cache Sweep Benchmark"
echo "═══════════════════════════════════════════════════════"
echo "Binary:    $BINARY"
echo "Model:     $MODEL"
echo "Port:      $PORT"
echo "Cache sizes: ${CACHE_SIZES[*]}"
echo "Warmup:    $WARMUP_PROMPTS prompts"
echo "Benchmark: $BENCH_PROMPTS prompts × $MAX_TOKENS tokens"
echo "Results:   $RESULTS_FILE"
echo "═══════════════════════════════════════════════════════"
echo ""

# Write TSV header (RESULTS_FILE is already in SCRIPT_DIR which exists)
printf "cache_entries\tcache_gb\tstartup_s\tmean_tps\tmedian_tps\tmin_tps\tmax_tps\tcache_hits\tcache_misses\thit_rate\tpredict\n" > "$RESULTS_FILE"

for cache_size in "${CACHE_SIZES[@]}"; do
    echo ""
    echo "───────────────────────────────────────────────────"
    echo "Testing: --malloc-cache $cache_size"
    echo "───────────────────────────────────────────────────"

    if ! check_memory_pressure; then
        echo "ABORT: Skipping cache=$cache_size and remaining configs due to memory pressure"
        break
    fi

    kill_flashmoe
    : > "$LOGFILE"

    # Build command
    CMD=("$BINARY" --model "$MODEL" --q3-experts --think-budget "$THINK_BUDGET" --serve "$PORT")
    if [[ "$cache_size" -gt 0 ]]; then
        CMD+=(--malloc-cache "$cache_size")
    fi
    # Always enable cache-entries as LRU fallback + telemetry
    CMD+=(--cache-entries 2500 --cache-telemetry)

    echo "Command: ${CMD[*]}"
    t_start=$(date +%s)

    # Start flash-moe from binary dir (shaders.metal must be in CWD)
    (cd "$BINARY_DIR" && "${CMD[@]}") > "$LOGFILE" 2>&1 &
    FM_PID=$!

    if ! wait_for_ready 300; then
        echo "SKIP: flash-moe failed to start with cache=$cache_size"
        kill_flashmoe
        continue
    fi

    t_ready=$(date +%s)
    startup_s=$((t_ready - t_start))
    echo "Startup: ${startup_s}s"

    # Validation: first prompt captures SSE response to verify inference works
    echo "Validating inference output..."
    validation_resp=$(curl -s --max-time 120 "http://127.0.0.1:$PORT/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"What is 2+2? Answer with just the number."}],"max_tokens":8,"stream":true}' 2>/dev/null || echo "")
    if [[ -z "$validation_resp" ]]; then
        echo "ERROR: Inference validation failed for cache=$cache_size (empty response)"
        kill_flashmoe
        continue
    fi
    # SSE response: check for any content delta or [DONE]
    if echo "$validation_resp" | grep -q '\[DONE\]'; then
        content=$(echo "$validation_resp" | grep -o '"content":"[^"]*"' | head -3 | tr '\n' ' ')
        echo "  Validation OK: $content"
    elif echo "$validation_resp" | grep -q '"error"'; then
        echo "ERROR: Inference returned error for cache=$cache_size"
        echo "  $(echo "$validation_resp" | head -3)"
        kill_flashmoe
        continue
    else
        echo "  Validation: got response ($(echo "$validation_resp" | wc -c | tr -d ' ') bytes)"
    fi

    # Warmup phase
    echo "Warming up ($WARMUP_PROMPTS prompts)..."
    for i in $(seq 1 "$WARMUP_PROMPTS"); do
        prompt_idx=$(( (i - 1) % ${#PROMPTS[@]} ))
        echo -n "  warmup $i/$WARMUP_PROMPTS..."
        send_prompt "${PROMPTS[$prompt_idx]}" "$MAX_TOKENS"
        echo " done"
    done

    # Benchmark phase
    echo "Benchmarking ($BENCH_PROMPTS prompts)..."
    for i in $(seq 1 "$BENCH_PROMPTS"); do
        prompt_idx=$(( (WARMUP_PROMPTS + i - 1) % ${#PROMPTS[@]} ))
        echo -n "  bench $i/$BENCH_PROMPTS..."
        send_prompt "${PROMPTS[$prompt_idx]}" "$MAX_TOKENS"
        echo " done"
    done

    # Extract metrics
    # Skip validation prompt + warmup prompts (validation is the first generation entry)
    skip_count=$((WARMUP_PROMPTS + 1))
    mapfile -t tps_values < <(extract_metrics "$LOGFILE" "$skip_count" | awk '{print $2}')

    if [[ ${#tps_values[@]} -eq 0 ]]; then
        echo "WARNING: No generation metrics found in log"
        mean_tps="0"
        median_tps="0"
        min_tps="0"
        max_tps="0"
    else
        # Calculate stats
        sorted=($(printf '%s\n' "${tps_values[@]}" | sort -g))
        n=${#sorted[@]}
        min_tps="${sorted[0]}"
        max_tps="${sorted[$((n-1))]}"
        median_tps="${sorted[$((n/2))]}"

        sum=0
        for v in "${tps_values[@]}"; do
            sum=$(echo "$sum + $v" | bc -l 2>/dev/null || echo "$sum")
        done
        mean_tps=$(echo "scale=2; $sum / $n" | bc -l 2>/dev/null || echo "0")
    fi

    # Cache stats
    cache_stats=$(extract_cache_stats "$LOGFILE")
    cache_gb=$(echo "scale=1; $cache_size * 5439488 / 1000000000" | bc -l 2>/dev/null || echo "0")

    # Parse hit/miss from log (use cache telemetry if malloc_cache stats unavailable)
    if [[ -n "$cache_stats" ]]; then
        cache_hits=$(echo "$cache_stats" | grep -o '[0-9]* hits' | awk '{print $1}' || echo "0")
        cache_misses=$(echo "$cache_stats" | grep -o '[0-9]* misses' | awk '{print $1}' || echo "0")
        hit_rate=$(echo "$cache_stats" | grep -o '[0-9.]*%' | head -1 || echo "0%")
    else
        # Fall back to cache telemetry effective hit rate
        hit_rate=$(grep "Effective hit rate:" "$LOGFILE" | tail -1 | grep -o '[0-9.]*%' || echo "N/A")
        cache_hits="N/A"
        cache_misses="N/A"
    fi

    echo ""
    echo "Results: mean=${mean_tps} tok/s, median=${median_tps}, range=[${min_tps}, ${max_tps}]"
    echo "Cache:   ${cache_gb} GB, hit_rate=${hit_rate}"
    echo "Startup: ${startup_s}s"

    # Write TSV row
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$cache_size" "$cache_gb" "$startup_s" \
        "$mean_tps" "$median_tps" "$min_tps" "$max_tps" \
        "${cache_hits:-0}" "${cache_misses:-0}" "${hit_rate:-0%}" \
        "off" >> "$RESULTS_FILE"

    kill_flashmoe
done

echo ""
echo "═══════════════════════════════════════════════════════"
echo "Results saved to: $RESULTS_FILE"
echo "═══════════════════════════════════════════════════════"
cat "$RESULTS_FILE" | column -t -s $'\t'
