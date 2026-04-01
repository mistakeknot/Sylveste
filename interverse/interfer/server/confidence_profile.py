"""Profile per-token confidence distributions across models.

Collects max softmax probability for every generated token to understand
how much "easy" generation exists (high confidence = potential for early
exit / layer skipping). Answers: what fraction of tokens are generated
with >90%, >95%, >99% confidence?

Usage:
    uv run python -m server.confidence_profile --model <path>
    uv run python -m server.confidence_profile --model <path> --save docs/benchmarks/
"""

from __future__ import annotations

import argparse
import json
import statistics
from datetime import datetime
from pathlib import Path

from .benchmark import PROMPT_CORPUS


def profile_confidence(
    model_name: str,
    max_tokens: int = 200,
    temperature: float = 0.0,
    prompts: list[dict[str, str]] | None = None,
) -> dict:
    """Run each prompt and collect per-token confidence values."""
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler

    if prompts is None:
        prompts = PROMPT_CORPUS

    model, tokenizer = load(model_name)
    mx.eval(model.parameters())
    sampler = make_sampler(temp=temperature)

    # Warm up
    list(
        stream_generate(model, tokenizer, prompt="Hello", max_tokens=1, sampler=sampler)
    )

    results = []
    all_confidences: list[float] = []

    for prompt_info in prompts:
        prompt = prompt_info["prompt"]
        name = prompt_info["name"]
        category = prompt_info.get("category", "")

        token_confidences: list[float] = []
        for response in stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            if response.logprobs is not None:
                probs = mx.softmax(response.logprobs, axis=-1)
                confidence = float(mx.max(probs))
                token_confidences.append(confidence)

        all_confidences.extend(token_confidences)
        results.append(
            {
                "prompt_name": name,
                "category": category,
                "tokens": len(token_confidences),
                "mean_confidence": round(statistics.mean(token_confidences), 4)
                if token_confidences
                else 0,
                "median_confidence": round(statistics.median(token_confidences), 4)
                if token_confidences
                else 0,
                "pct_above_90": round(
                    sum(1 for c in token_confidences if c > 0.90)
                    / len(token_confidences)
                    * 100,
                    1,
                )
                if token_confidences
                else 0,
                "pct_above_95": round(
                    sum(1 for c in token_confidences if c > 0.95)
                    / len(token_confidences)
                    * 100,
                    1,
                )
                if token_confidences
                else 0,
                "pct_above_99": round(
                    sum(1 for c in token_confidences if c > 0.99)
                    / len(token_confidences)
                    * 100,
                    1,
                )
                if token_confidences
                else 0,
            }
        )

    # Compute thresholds for potential speedup estimation
    thresholds = [0.80, 0.85, 0.90, 0.95, 0.99]
    threshold_pcts = {}
    for t in thresholds:
        count = sum(1 for c in all_confidences if c > t)
        threshold_pcts[str(t)] = (
            round(count / len(all_confidences) * 100, 1) if all_confidences else 0
        )

    summary = {
        "model": model_name,
        "total_tokens": len(all_confidences),
        "mean_confidence": round(statistics.mean(all_confidences), 4)
        if all_confidences
        else 0,
        "median_confidence": round(statistics.median(all_confidences), 4)
        if all_confidences
        else 0,
        "threshold_pcts": threshold_pcts,
        "per_prompt": results,
    }
    return summary


def print_profile(summary: dict) -> None:
    """Print a human-readable confidence profile."""
    print(f"\n{'='*65}")
    print(f"  Confidence Profile: {Path(summary['model']).name}")
    print(f"{'='*65}")
    print(f"  Total tokens:       {summary['total_tokens']}")
    print(f"  Mean confidence:    {summary['mean_confidence']}")
    print(f"  Median confidence:  {summary['median_confidence']}")
    print(f"\n  Tokens above threshold (potential early exit):")
    for t, pct in summary["threshold_pcts"].items():
        bar = "█" * int(pct / 2) + "░" * (50 - int(pct / 2))
        print(f"    >{t}: {bar} {pct:5.1f}%")
    print(
        f"\n  {'Prompt':<25} {'Tokens':>6} {'Mean':>6} {'Med':>6} {'>90%':>6} {'>95%':>6} {'>99%':>6}"
    )
    print(f"  {'-'*25} {'-'*6} {'-'*6} {'-'*6} {'-'*6} {'-'*6} {'-'*6}")
    for r in summary["per_prompt"]:
        print(
            f"  {r['prompt_name']:<25} {r['tokens']:>6} "
            f"{r['mean_confidence']:>6.3f} {r['median_confidence']:>6.3f} "
            f"{r['pct_above_90']:>5.1f}% {r['pct_above_95']:>5.1f}% {r['pct_above_99']:>5.1f}%"
        )
    print()


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="interfer-confidence-profile",
        description="Profile per-token confidence distributions",
    )
    parser.add_argument("--model", required=True, help="Model path or HF ID")
    parser.add_argument(
        "--max-tokens", type=int, default=200, help="Max tokens per prompt"
    )
    parser.add_argument(
        "--save", type=str, default=None, help="Save JSON to this directory"
    )
    args = parser.parse_args(argv)

    summary = profile_confidence(model_name=args.model, max_tokens=args.max_tokens)
    print_profile(summary)

    if args.save:
        save_dir = Path(args.save)
        save_dir.mkdir(parents=True, exist_ok=True)
        model_slug = Path(args.model).name or args.model.replace("/", "_")
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        filename = f"{timestamp}-{model_slug}-confidence.json"
        save_path = save_dir / filename
        with open(save_path, "w") as f:
            json.dump(summary, f, indent=2)
        print(f"Results saved to {save_path}")


if __name__ == "__main__":
    main()
