"""CLI for running interfere benchmarks.

Usage:
    uv run python -m server.benchmark_cli --model <path_or_name>
    uv run python -m server.benchmark_cli --model <path> --max-tokens 200 --json
    uv run python -m server.benchmark_cli --model <path> --save results/
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

from .benchmark import print_summary, run_benchmark


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="interfere-benchmark",
        description="Benchmark interfere inference pipeline",
    )
    parser.add_argument(
        "--model",
        required=True,
        help="HuggingFace model ID or local path",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=100,
        help="Max tokens per prompt (default: 100)",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.1,
        help="Sampling temperature (default: 0.1)",
    )
    parser.add_argument(
        "--no-warmup",
        action="store_true",
        help="Skip warm-up generation (measures cold start)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="output_json",
        help="Output results as JSON instead of table",
    )
    parser.add_argument(
        "--kv-bits",
        type=int,
        default=None,
        choices=[2, 4, 8],
        help="Quantize KV cache to N bits (2, 4, or 8). Default: no quantization.",
    )
    parser.add_argument(
        "--kv-group-size",
        type=int,
        default=64,
        help="Group size for KV cache quantization (default: 64)",
    )
    parser.add_argument(
        "--draft-model",
        type=str,
        default=None,
        help="Draft model for speculative decoding (path or HF ID)",
    )
    parser.add_argument(
        "--num-draft-tokens",
        type=int,
        default=3,
        help="Tokens to draft per step in speculative decoding (default: 3)",
    )
    parser.add_argument(
        "--kv-mode",
        type=str,
        choices=["standard", "turbo_quant", "bhq"],
        default="standard",
        help="KV cache mode: 'standard' (mlx-lm), 'turbo_quant' (rotation+affine), or 'bhq' (Lloyd-Max centroids)",
    )
    parser.add_argument(
        "--save",
        type=str,
        default=None,
        help="Save JSON results to this directory",
    )

    args = parser.parse_args(argv)

    kv_mode = args.kv_mode if args.kv_mode != "standard" else None

    summary = run_benchmark(
        model_name=args.model,
        max_tokens=args.max_tokens,
        temperature=args.temperature,
        warm_up=not args.no_warmup,
        kv_bits=args.kv_bits,
        kv_group_size=args.kv_group_size,
        draft_model=args.draft_model,
        num_draft_tokens=args.num_draft_tokens,
        kv_mode=kv_mode,
    )

    if args.output_json:
        print(json.dumps(summary.to_dict(), indent=2))
    else:
        print_summary(summary)

    if args.save:
        save_dir = Path(args.save)
        save_dir.mkdir(parents=True, exist_ok=True)
        model_slug = Path(args.model).name or args.model.replace("/", "_")
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        kv_suffix = f"-kv{args.kv_bits}" if args.kv_bits else ""
        if kv_mode == "turbo_quant":
            kv_suffix = f"-turbo{args.kv_bits or 4}"
        draft_suffix = f"-spec{args.num_draft_tokens}" if args.draft_model else ""
        filename = f"{timestamp}-{model_slug}{kv_suffix}{draft_suffix}.json"
        save_path = save_dir / filename
        with open(save_path, "w") as f:
            json.dump(summary.to_dict(), f, indent=2)
        print(f"Results saved to {save_path}")


if __name__ == "__main__":
    main()
