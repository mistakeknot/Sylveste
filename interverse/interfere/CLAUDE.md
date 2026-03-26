# interfere

Local MLX-LM inference server for Apple Silicon M5 Max 128GB. Interverse companion plugin for Clavain.

## Quick Start
- `uv run python -m interfere.server` — start server on port 8421
- `curl http://localhost:8421/health` — check status

## Architecture
- Main process: Starlette HTTP (no MLX imports)
- Subprocess: Metal context owner, runs inference via mlx-lm
- Communication: multiprocessing.Queue (spawn context)

## Requirements
- Apple Silicon Mac with MLX installed
- Python 3.12+
