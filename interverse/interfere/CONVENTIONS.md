# Conventions

## Code Style
- Python 3.12+, type hints everywhere
- `from __future__ import annotations` in every module
- `uv run` for all commands (never bare `pip install`)
- `uv run pytest tests/ -v` for testing

## MLX Safety
- Never import `mlx.core` at module level in the HTTP process — only inside Metal subprocess methods
- Always call `mx.metal.set_memory_limit(relaxed=False)` before any model load
- Use `multiprocessing.get_context("spawn")` — never fork
- Check `mx.metal.get_active_memory()` before loading a second model

## Server
- OpenAI-compatible `/v1/chat/completions` is the only inference endpoint
- SSE format: `data: {JSON}\n\n` per chunk, `data: [DONE]\n\n` at end
- Priority queue: lower number = higher priority
- All request validation returns 400 with `{"error": {"message": ..., "type": "invalid_request_error"}}`

## Experiments
- Every experiment hook lives in `server/experiments/`
- Each hook has `enabled` flag and stats counters (`exit_rate`, etc.)
- Experiments are tracked via interlab campaigns
- Kill criterion: quality regression > 2% on coding eval OR latency regression > 20%

## Git
- Trunk-based: commit to main
- Files are gitignored at Demarch root (`interverse/`), use `git add -f` or own repo
- Commit message format: `feat(interfere): description` or `fix(interfere): description`

## Testing
- pytest + pytest-asyncio (strict mode)
- `pytest.importorskip("mlx")` for tests that need Metal
- `@pytest.mark.skipif(sys.platform != "darwin")` for macOS-only tests
- Import from `server.*` (not `interfere.server.*`) — hatchling maps `server/` as the package
