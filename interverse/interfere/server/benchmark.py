"""Benchmark harness for interfere inference pipeline.

Runs a standard prompt corpus through a model and measures:
  - tok/s (tokens per second, generation only)
  - TTFT (time to first token)
  - total_time (end-to-end including model load if cold)
  - token_count (actual tokens generated)
  - thermal_state (macOS thermal pressure at start/end)

Usage:
    uv run python -m server.benchmark --model <path_or_name> [--max-tokens 100] [--runs 3]
"""

from __future__ import annotations

import json
import statistics
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Any

from .inference import InferenceEngine
from .thermal import ThermalMonitor, ThermalState


# Standard prompt corpus — diverse tasks for quality comparison
PROMPT_CORPUS: list[dict[str, str]] = [
    {
        "name": "coding_function",
        "prompt": "Write a Python function that implements binary search on a sorted array. Include type hints and a docstring.",
        "category": "coding",
    },
    {
        "name": "coding_debug",
        "prompt": "Find the bug in this code and fix it:\ndef fibonacci(n):\n    if n <= 1: return n\n    return fibonacci(n-1) + fibonacci(n-2)\nprint(fibonacci(50))  # This hangs",
        "category": "coding",
    },
    {
        "name": "reasoning_math",
        "prompt": "A farmer has 17 sheep. All but 9 die. How many sheep does the farmer have left? Explain your reasoning step by step.",
        "category": "reasoning",
    },
    {
        "name": "reasoning_logic",
        "prompt": "If all roses are flowers, and some flowers fade quickly, can we conclude that some roses fade quickly? Explain using formal logic.",
        "category": "reasoning",
    },
    {
        "name": "tool_calling",
        "prompt": 'You have access to a function: search(query: str) -> list[str]. The user asks: "What is the weather in Tokyo?" Respond with the correct function call in JSON format.',
        "category": "tool_calling",
    },
    {
        "name": "factual_short",
        "prompt": "What is the capital of Australia? Answer in one word.",
        "category": "factual",
    },
    {
        "name": "creative_short",
        "prompt": "Write a haiku about debugging code.",
        "category": "creative",
    },
    {
        "name": "instruction_following",
        "prompt": "List exactly 5 prime numbers between 20 and 50. Output only the numbers, separated by commas.",
        "category": "instruction",
    },
]


@dataclass
class BenchmarkResult:
    """Result from a single benchmark run."""

    prompt_name: str
    model: str
    tokens_generated: int
    generation_time_s: float
    ttft_s: float
    tok_per_s: float
    thermal_start: str
    thermal_end: str
    output_preview: str  # first 200 chars
    category: str = ""
    kv_bits: int | None = None
    kv_mode: str | None = None  # "turbo_quant" | None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class BenchmarkSummary:
    """Aggregated benchmark results across a corpus."""

    model: str
    total_runs: int
    median_tok_s: float
    mean_tok_s: float
    p5_tok_s: float
    p95_tok_s: float
    median_ttft_s: float
    total_tokens: int
    total_time_s: float
    thermal_start: str
    thermal_end: str
    kv_bits: int | None = None
    kv_mode: str | None = None
    draft_model: str | None = None
    num_draft_tokens: int | None = None
    results: list[BenchmarkResult] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["results"] = [r.to_dict() for r in self.results]
        return d


def _percentile(data: list[float], p: float) -> float:
    """Simple percentile calculation."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    k = (len(sorted_data) - 1) * (p / 100.0)
    f = int(k)
    c = f + 1 if f + 1 < len(sorted_data) else f
    return sorted_data[f] + (k - f) * (sorted_data[c] - sorted_data[f])


def run_benchmark(
    model_name: str,
    max_tokens: int = 100,
    temperature: float = 0.1,
    prompts: list[dict[str, str]] | None = None,
    warm_up: bool = True,
    kv_bits: int | None = None,
    kv_group_size: int = 64,
    draft_model: str | None = None,
    num_draft_tokens: int = 3,
    kv_mode: str | None = None,
) -> BenchmarkSummary:
    """Run the full benchmark corpus against a model.

    Args:
        model_name: HuggingFace model ID or local path.
        max_tokens: Maximum tokens to generate per prompt.
        temperature: Sampling temperature (low for reproducibility).
        prompts: Custom prompt corpus, or None for the default.
        warm_up: If True, run a single warm-up generation first.
        kv_bits: If set, quantize the KV cache to this many bits (2, 4, or 8).
        kv_group_size: Group size for KV cache quantization. Default: 64.
        draft_model: If set, use speculative decoding with this draft model.
        num_draft_tokens: Number of tokens to draft per step. Default: 3.
        kv_mode: If "turbo_quant", enable polar-transformed KV quantization.

    Returns:
        BenchmarkSummary with per-prompt results and aggregated stats.
    """
    from .experiments.config import ExperimentConfig

    if prompts is None:
        prompts = PROMPT_CORPUS

    # Build experiment configs for TurboQuant mode
    experiment_configs = {}
    if kv_mode == "turbo_quant":
        experiment_configs["turbo_quant"] = ExperimentConfig(
            name="turbo_quant",
            enabled=True,
            params={"kv_bits": kv_bits or 4, "kv_group_size": kv_group_size},
        )
        # Engine handles kv_bits internally when turbo_quant is active
        kv_bits = None

    engine = InferenceEngine(experiment_configs=experiment_configs or None)
    thermal = ThermalMonitor()

    # Warm up: load model(s) into memory
    if warm_up:
        list(
            engine.generate(
                "Hello",
                model_name=model_name,
                max_tokens=1,
                kv_bits=kv_bits,
                kv_group_size=kv_group_size,
                draft_model_name=draft_model,
                num_draft_tokens=num_draft_tokens,
            )
        )

    thermal_start = thermal.read()
    results: list[BenchmarkResult] = []
    total_start = time.perf_counter()

    for prompt_info in prompts:
        prompt = prompt_info["prompt"]
        name = prompt_info["name"]
        category = prompt_info.get("category", "")

        # Measure generation
        tokens: list[str] = []
        ttft = 0.0
        gen_start = time.perf_counter()

        for token in engine.generate(
            prompt=prompt,
            model_name=model_name,
            max_tokens=max_tokens,
            temperature=temperature,
            kv_bits=kv_bits,
            kv_group_size=kv_group_size,
            draft_model_name=draft_model,
            num_draft_tokens=num_draft_tokens,
        ):
            if not tokens:
                ttft = time.perf_counter() - gen_start
            tokens.append(token)

        gen_time = time.perf_counter() - gen_start
        tok_count = len(tokens)
        tok_s = tok_count / gen_time if gen_time > 0 else 0.0
        output = "".join(tokens)

        thermal_now = thermal.read()
        results.append(
            BenchmarkResult(
                prompt_name=name,
                model=model_name,
                tokens_generated=tok_count,
                generation_time_s=round(gen_time, 4),
                ttft_s=round(ttft, 4),
                tok_per_s=round(tok_s, 1),
                thermal_start=thermal_start.level,
                thermal_end=thermal_now.level,
                output_preview=output[:200],
                category=category,
                kv_bits=kv_bits,
                kv_mode=kv_mode,
            )
        )

    total_time = time.perf_counter() - total_start
    thermal_end = thermal.read()

    # Aggregate stats
    all_tok_s = [r.tok_per_s for r in results]
    all_ttft = [r.ttft_s for r in results]

    return BenchmarkSummary(
        model=model_name,
        total_runs=len(results),
        median_tok_s=round(statistics.median(all_tok_s), 1),
        mean_tok_s=round(statistics.mean(all_tok_s), 1),
        p5_tok_s=round(_percentile(all_tok_s, 5), 1),
        p95_tok_s=round(_percentile(all_tok_s, 95), 1),
        median_ttft_s=round(statistics.median(all_ttft), 4),
        total_tokens=sum(r.tokens_generated for r in results),
        total_time_s=round(total_time, 2),
        thermal_start=thermal_start.level,
        thermal_end=thermal_end.level,
        kv_bits=kv_bits,
        kv_mode=kv_mode,
        draft_model=draft_model,
        num_draft_tokens=num_draft_tokens if draft_model else None,
        results=results,
    )


def print_summary(summary: BenchmarkSummary) -> None:
    """Print a human-readable benchmark summary."""
    kv_label = (
        f"  KV bits:      {summary.kv_bits}"
        if summary.kv_bits
        else "  KV bits:      none (fp16)"
    )
    print(f"\n{'='*60}")
    print(f"  Benchmark: {summary.model}")
    print(f"{'='*60}")
    if summary.draft_model:
        from pathlib import Path

        draft_name = Path(summary.draft_model).name or summary.draft_model
        print(f"  Draft model:  {draft_name} ({summary.num_draft_tokens} tokens/step)")
    print(kv_label)
    print(f"  Runs:        {summary.total_runs}")
    print(f"  Median tok/s: {summary.median_tok_s}")
    print(f"  Mean tok/s:   {summary.mean_tok_s}")
    print(f"  P5/P95 tok/s: {summary.p5_tok_s} / {summary.p95_tok_s}")
    print(f"  Median TTFT:  {summary.median_ttft_s}s")
    print(f"  Total tokens: {summary.total_tokens}")
    print(f"  Total time:   {summary.total_time_s}s")
    print(f"  Thermal:      {summary.thermal_start} → {summary.thermal_end}")
    print(f"{'='*60}")
    print(f"  {'Prompt':<25} {'Tokens':>6} {'tok/s':>7} {'TTFT':>7} {'Category':<12}")
    print(f"  {'-'*25} {'-'*6} {'-'*7} {'-'*7} {'-'*12}")
    for r in summary.results:
        print(
            f"  {r.prompt_name:<25} {r.tokens_generated:>6} "
            f"{r.tok_per_s:>7.1f} {r.ttft_s:>7.3f} {r.category:<12}"
        )
    print()
