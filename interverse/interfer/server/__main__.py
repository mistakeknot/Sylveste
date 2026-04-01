"""Entry point: ``python -m server`` or ``uv run python -m server``."""

from __future__ import annotations

import argparse
import os
import sys

import uvicorn

from .batch_scheduler import BatchScheduler
from .cascade import CascadeConfig
from .main import create_app


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="interfer",
        description="Local MLX-LM inference server for Apple Silicon",
    )
    parser.add_argument(
        "--port", type=int, default=8421, help="Port to listen on (default: 8421)"
    )
    parser.add_argument(
        "--host",
        type=str,
        default="127.0.0.1",
        help="Host to bind (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Start in dry-run mode (fake tokens, no MLX)",
    )
    parser.add_argument(
        "--preload",
        type=str,
        default=None,
        help="Model to preload at startup (e.g., mlx-community/Qwen3.5-35B-A3B-4bit)",
    )
    parser.add_argument(
        "--model-tiers",
        type=str,
        nargs="+",
        default=None,
        help="Cascade model tiers, smallest to largest (e.g., small-4bit large-4bit)",
    )
    parser.add_argument(
        "--cascade-accept",
        type=float,
        default=0.8,
        help="Cascade accept threshold (default: 0.8)",
    )
    parser.add_argument(
        "--cascade-cloud",
        type=float,
        default=0.4,
        help="Cascade cloud fallback threshold (default: 0.4)",
    )
    parser.add_argument(
        "--no-cascade",
        action="store_true",
        help="Disable confidence cascade even if model-tiers are set",
    )
    parser.add_argument(
        "--max-queue-depth",
        type=int,
        default=8,
        help="Max queued inference requests before 503 rejection (default: 8)",
    )
    parser.add_argument(
        "--thermal-reject",
        type=str,
        default="heavy",
        choices=["moderate", "heavy", "trapping", "sleeping"],
        help="Reject requests at this thermal level or above (default: heavy)",
    )

    # Batch scheduler
    bs = parser.add_argument_group(
        "batch-scheduler", "Adaptive batching for concurrent agent requests"
    )
    bs.add_argument(
        "--batch-scheduler",
        action="store_true",
        help="Enable batch scheduler for multi-agent concurrency",
    )
    bs.add_argument(
        "--batch-window-ms",
        type=float,
        default=50.0,
        help="Accumulation window in milliseconds before forming a batch (default: 50)",
    )
    bs.add_argument(
        "--batch-max-size",
        type=int,
        default=8,
        help="Maximum requests per batch (default: 8)",
    )
    bs.add_argument(
        "--batch-preemption",
        action="store_true",
        default=True,
        help="Enable priority preemption (default: True)",
    )
    bs.add_argument(
        "--no-batch-preemption",
        action="store_true",
        help="Disable priority preemption",
    )

    # Flash-MoE integration
    fm = parser.add_argument_group(
        "flash-moe", "Flash-MoE subprocess backend for 700B+ MoE models"
    )
    fm.add_argument(
        "--flashmoe-binary",
        type=str,
        default="",
        help="Path to flash-moe infer binary (enables flash-moe backend)",
    )
    fm.add_argument(
        "--flashmoe-model",
        type=str,
        default="",
        help="Model directory for flash-moe (e.g., ~/Models/mlx-community-Qwen3.5-397B-A17B-4bit)",
    )
    fm.add_argument(
        "--flashmoe-port",
        type=int,
        default=0,
        help="Port for flash-moe HTTP API (0 = auto-pick, default: 0)",
    )
    fm.add_argument(
        "--flashmoe-model-name",
        type=str,
        default="flash-moe",
        help="Model name for routing requests to flash-moe (default: flash-moe)",
    )
    fm.add_argument(
        "--flashmoe-args",
        type=str,
        default="",
        help='Extra CLI args passed to the flash-moe binary as a single string (e.g., "--think-budget 2048")',
    )
    fm.add_argument(
        "--flashmoe-only",
        action="store_true",
        help="Use only flash-moe backend, skip MetalWorker (saves ~5 GB GPU)",
    )
    fm.add_argument(
        "--flashmoe-malloc-cache",
        type=int,
        default=0,
        help="GPU-resident expert cache entries (0 = disabled, 5000 = ~35 GB recommended for 128GB)",
    )
    fm.add_argument(
        "--flashmoe-predict",
        action="store_true",
        help="Enable temporal expert prediction (prefetch during GPU compute wait)",
    )

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    cascade_config = CascadeConfig(
        accept_threshold=args.cascade_accept,
        cloud_threshold=args.cascade_cloud,
        enabled=not args.no_cascade,
    )

    # Expand ~ in flash-moe paths
    flashmoe_binary = (
        os.path.expanduser(args.flashmoe_binary) if args.flashmoe_binary else ""
    )
    flashmoe_model = (
        os.path.expanduser(args.flashmoe_model) if args.flashmoe_model else ""
    )

    # Build batch scheduler if enabled
    batch_scheduler: BatchScheduler | None = None
    if args.batch_scheduler:
        batch_scheduler = BatchScheduler(
            accumulation_window_ms=args.batch_window_ms,
            max_batch_size=args.batch_max_size,
            preemption_enabled=args.batch_preemption and not args.no_batch_preemption,
        )

    app = create_app(
        dry_run=args.dry_run,
        model_tiers=args.model_tiers,
        cascade_config=cascade_config,
        max_queue_depth=args.max_queue_depth,
        thermal_reject_level=args.thermal_reject,
        flashmoe_binary=flashmoe_binary,
        flashmoe_model_path=flashmoe_model,
        flashmoe_port=args.flashmoe_port,
        flashmoe_extra_args=args.flashmoe_args.split() if args.flashmoe_args else None,
        flashmoe_model_name=args.flashmoe_model_name,
        flashmoe_only=args.flashmoe_only,
        flashmoe_malloc_cache=args.flashmoe_malloc_cache,
        flashmoe_predict=args.flashmoe_predict,
        batch_scheduler=batch_scheduler,
    )

    if args.preload and not args.dry_run:
        import httpx

        # Start uvicorn in a thread, preload model via HTTP, then serve
        import threading

        server = uvicorn.Server(
            uvicorn.Config(app, host=args.host, port=args.port, log_level="info")
        )
        thread = threading.Thread(target=server.run, daemon=True)
        thread.start()

        # Wait for server to be ready
        import time

        for _ in range(30):
            try:
                r = httpx.get(f"http://{args.host}:{args.port}/health", timeout=1.0)
                if r.status_code == 200:
                    break
            except Exception:
                pass
            time.sleep(0.5)

        # Preload model
        print(f"Preloading model: {args.preload}")
        try:
            r = httpx.post(
                f"http://{args.host}:{args.port}/v1/models/load",
                json={"model": args.preload},
                timeout=180.0,
            )
            if r.status_code == 200:
                print(f"Model preloaded: {args.preload}")
            else:
                print(f"Preload failed: {r.text}")
        except Exception as e:
            print(f"Preload error: {e}")

        thread.join()
    else:
        uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
