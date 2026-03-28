"""Entry point: ``python -m server`` or ``uv run python -m server``."""

from __future__ import annotations

import argparse
import sys

import uvicorn

from .cascade import CascadeConfig
from .main import create_app


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="interfere",
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
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    cascade_config = CascadeConfig(
        accept_threshold=args.cascade_accept,
        cloud_threshold=args.cascade_cloud,
        enabled=not args.no_cascade,
    )
    app = create_app(
        dry_run=args.dry_run,
        model_tiers=args.model_tiers,
        cascade_config=cascade_config,
        max_queue_depth=args.max_queue_depth,
        thermal_reject_level=args.thermal_reject,
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
