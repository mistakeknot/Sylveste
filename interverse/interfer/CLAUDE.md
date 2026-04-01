# interfer

Local MLX-LM inference server for Apple Silicon M5 Max 128GB. Interverse companion plugin for Clavain.

## Quick Start
- `uv run python -m server --dry-run` — start server in dry-run mode on port 8421
- `uv run python -m server` — start server with MLX inference
- `curl http://localhost:8421/health` — check status
- Verified model: `mlx-community/Qwen2.5-0.5B-Instruct-4bit` (test model, cached)
- Production models: see AGENTS.md § Memory Budget for MoE-first tier layout

## Architecture
- Main process: Starlette HTTP (no MLX imports)
- Subprocess: Metal context owner, runs inference via mlx-lm
- Communication: multiprocessing.Queue (spawn context)

## Requirements
- Apple Silicon Mac with MLX installed
- Python 3.12+
