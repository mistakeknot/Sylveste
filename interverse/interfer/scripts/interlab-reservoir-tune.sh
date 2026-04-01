#!/usr/bin/env bash
set -euo pipefail
# interlab-reservoir-tune.sh — Evaluation harness for reservoir routing MLP.
#
# Accepts hyperparams as env vars (interlab campaign sets these per run):
#   HIDDEN_DIM     (default: 4096)
#   BOTTLENECK_DIM (default: 64)
#   ACTIVATION     (default: relu)
#   NUM_CLASSES    (default: 3)
#   LABEL_SCHEME   (default: 3class)
#   EPOCHS         (default: 50)
#   LR             (default: 1e-3)
#   SEED           (default: 42)
#   DATA_PATH      (optional — generates data if unset)
#   OUTPUT_PATH    (default: reservoir_weights.safetensors)
#
# Emits METRIC lines to stdout for interlab ingestion.
# stderr is captured separately to avoid corrupting METRIC stream.

export HIDDEN_DIM=${HIDDEN_DIM:-4096}
export BOTTLENECK_DIM=${BOTTLENECK_DIM:-64}
export ACTIVATION=${ACTIVATION:-relu}
export NUM_CLASSES=${NUM_CLASSES:-3}
export LABEL_SCHEME=${LABEL_SCHEME:-3class}
export EPOCHS=${EPOCHS:-50}
export LR=${LR:-1e-3}
export SEED=${SEED:-42}

cd "$(dirname "$0")/.."

STDERR_LOG=$(mktemp /tmp/reservoir-train-stderr.XXXXXX.log)
trap 'rm -f "$STDERR_LOG"' EXIT

uv run python3 -m server.experiments.train_reservoir 2>"$STDERR_LOG"
EXIT_CODE=$?

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "METRIC error=1"
    echo "METRIC benchmark_exit_code=$EXIT_CODE"
    cat "$STDERR_LOG" >&2
    exit $EXIT_CODE
fi
