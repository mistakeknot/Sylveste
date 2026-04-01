"""SSD Streaming for MoE Expert Weights (Phase 0 PoC).

Replaces in-memory SwitchGLU forward with pread-from-disk streaming.
Only the router-selected experts (10 of 512 for Qwen 397B) are loaded
per layer per token, using OS pread() directly into mx.array memoryview
for zero-copy NVMe→GPU transfer.

Usage (standalone benchmark):
    cd interverse/interfer
    uv run python -m server.streaming_switch \\
        --model ~/Models/mlx-community-Qwen3.5-397B-A17B-4bit \\
        --packed-experts ~/Models/mlx-community-Qwen3.5-397B-A17B-4bit/packed_experts \\
        --max-tokens 200

Architecture:
    1. Model loads normally via mlx_lm.load() — all non-expert weights in GPU
    2. Expert weights (SwitchGLU gate/up/down per layer) are NOT loaded to GPU
    3. At each MoE layer:
       a. Router runs (gate projection) → gets top-k expert indices
       b. mx.eval(inds) — sync to CPU to know which experts to load
       c. ThreadPoolExecutor pread() selected experts into pre-allocated buffers
       d. Assign buffers to QuantizedSwitchLinear weight/scales/biases
       e. Standard gather_qmm forward with re-indexed indices (0..k-1)
    4. Shared expert stays GPU-resident (small, always active)
"""

from __future__ import annotations

import ctypes
import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class ExpertLayout:
    """Describes the packed binary layout for one model's experts."""

    expert_size: int  # bytes per expert (e.g. 7,077,888)
    num_experts: int  # e.g. 512
    num_layers: int  # e.g. 60
    components: list[dict]  # name, offset, size, dtype, shape per component

    @classmethod
    def from_file(cls, path: str | Path) -> ExpertLayout:
        with open(path) as f:
            d = json.load(f)
        return cls(
            expert_size=d["expert_size"],
            num_experts=d["num_experts"],
            num_layers=d["num_layers"],
            components=d["components"],
        )


@dataclass
class StreamingState:
    """Per-layer streaming state: file descriptors, buffers, metrics."""

    layer_fds: dict[int, int] = field(default_factory=dict)  # layer_idx -> fd
    layout: ExpertLayout | None = None
    executor: ThreadPoolExecutor | None = None
    # Metrics
    total_pread_bytes: int = 0
    total_pread_calls: int = 0
    total_pread_time: float = 0.0


def open_layer_files(packed_dir: str | Path, layout: ExpertLayout) -> dict[int, int]:
    """Open all layer binary files, return {layer_idx: fd}."""
    fds = {}
    packed_dir = Path(packed_dir)
    for layer_idx in range(layout.num_layers):
        path = packed_dir / f"layer_{layer_idx:02d}.bin"
        if path.exists():
            fds[layer_idx] = os.open(str(path), os.O_RDONLY)
    return fds


def close_layer_files(fds: dict[int, int]) -> None:
    """Close all opened file descriptors."""
    for fd in fds.values():
        os.close(fd)


class StreamingMoeBlock:
    """Drop-in replacement for SparseMoeBlock that streams experts from disk.

    MLX's nn.Module.__call__ uses C++ dispatch and ignores instance-level
    __call__ overrides. So instead of monkey-patching __call__, we replace
    the entire layer.mlp with this wrapper that has its own __call__ defined
    at the class level.

    Not an nn.Module itself — just a callable that holds references to the
    original block's sub-modules and the streaming state.
    """

    def __init__(self, block, layer_idx: int, state: StreamingState):
        import mlx.core as mx

        self.gate = block.gate
        self.switch_mlp = block.switch_mlp
        self.shared_expert = block.shared_expert
        self.shared_expert_gate = block.shared_expert_gate
        self.sharding_group = block.sharding_group
        self.norm_topk_prob = block.norm_topk_prob
        self.top_k = block.top_k
        self.num_experts = block.num_experts

        self._state = state
        self._fd = state.layer_fds[layer_idx]
        self._layout = state.layout

        # libc pread for true zero-copy NVMe→Metal buffer transfer
        self._libc = ctypes.CDLL(None)
        self._libc.pread.restype = ctypes.c_ssize_t
        self._libc.pread.argtypes = [
            ctypes.c_int,
            ctypes.c_void_p,
            ctypes.c_size_t,
            ctypes.c_longlong,
        ]

        # Buffer pool: dynamically sized per call.
        # During decode (1 token), num_loaded ≈ 10 (67.5 MB).
        # During prefill (N tokens), num_loaded can be much larger.
        # We track the current buffer capacity and grow as needed.
        self._buf_capacity = 0  # current num_experts allocated
        self._expert_buffers = {}

        self._comp_by_name = {c["name"]: c for c in self._layout.components}

    def __call__(self, x):
        import mlx.core as mx
        from mlx.nn.layers.distributed import sum_gradients

        if self.sharding_group is not None:
            x = sum_gradients(self.sharding_group)(x)

        # Step 1: Run router
        gates = self.gate(x)
        gates = mx.softmax(gates, axis=-1, precise=True)

        k = self.top_k
        inds = mx.argpartition(gates, kth=-k, axis=-1)[..., -k:]
        scores = mx.take_along_axis(gates, inds, axis=-1)
        if self.norm_topk_prob:
            scores = scores / scores.sum(axis=-1, keepdims=True)

        # Step 2: Sync to CPU — unavoidable latency (~1-2ms)
        mx.eval(inds)

        # Step 3: Get unique expert indices across all tokens in batch
        flat_inds = inds.reshape(-1).tolist()
        unique_experts = sorted(set(flat_inds))
        num_loaded = len(unique_experts)
        expert_to_slot = {eidx: slot for slot, eidx in enumerate(unique_experts)}

        # Ensure buffers are large enough for num_loaded experts
        if num_loaded > self._buf_capacity:
            self._buf_capacity = num_loaded
            self._expert_buffers = {}
            for comp in self._layout.components:
                total_bytes = num_loaded * comp["size"]
                buf = mx.zeros(total_bytes, dtype=mx.uint8)
                mx.eval(buf)
                self._expert_buffers[comp["name"]] = buf

        # Step 4: Zero-copy pread directly into mx.array Metal buffers
        t0 = time.monotonic()
        fd = self._fd
        layout = self._layout
        comp_by_name = self._comp_by_name
        expert_buffers = self._expert_buffers
        libc = self._libc

        def _pread_into_buffer(comp_name: str):
            comp = comp_by_name[comp_name]
            buf = expert_buffers[comp_name]
            mv = memoryview(buf)
            base_ptr = ctypes.addressof(ctypes.c_char.from_buffer(mv))
            comp_offset = comp["offset"]
            comp_size = comp["size"]
            bytes_read = 0
            for slot_idx, expert_idx in enumerate(unique_experts):
                file_offset = expert_idx * layout.expert_size + comp_offset
                dst_ptr = base_ptr + slot_idx * comp_size
                n = libc.pread(fd, dst_ptr, comp_size, file_offset)
                bytes_read += n
            return bytes_read

        futures = [
            self._state.executor.submit(_pread_into_buffer, comp["name"])
            for comp in layout.components
        ]
        total_bytes = sum(f.result() for f in futures)

        pread_elapsed = time.monotonic() - t0
        self._state.total_pread_bytes += total_bytes
        self._state.total_pread_calls += len(unique_experts) * len(layout.components)
        self._state.total_pread_time += pread_elapsed

        # Step 5: Reshape buffers and assign to QuantizedSwitchLinear projections
        for proj_name in ("gate_proj", "up_proj", "down_proj"):
            proj = getattr(self.switch_mlp, proj_name)

            w_comp = comp_by_name[f"{proj_name}.weight"]
            s_comp = comp_by_name[f"{proj_name}.scales"]
            b_comp = comp_by_name[f"{proj_name}.biases"]

            w_bytes = num_loaded * w_comp["size"]
            s_bytes = num_loaded * s_comp["size"]
            b_bytes = num_loaded * b_comp["size"]

            # layout.json shapes are per-expert (e.g. [1024, 512] for gate_proj.weight)
            # We prepend num_loaded as the expert dimension
            w_shape = [num_loaded] + w_comp["shape"]
            s_shape = [num_loaded] + s_comp["shape"]
            b_shape = [num_loaded] + b_comp["shape"]

            proj.weight = (
                expert_buffers[f"{proj_name}.weight"][:w_bytes]
                .view(mx.uint32)
                .reshape(w_shape)
            )
            proj.scales = (
                expert_buffers[f"{proj_name}.scales"][:s_bytes]
                .view(mx.bfloat16)
                .reshape(s_shape)
            )
            proj.biases = (
                expert_buffers[f"{proj_name}.biases"][:b_bytes]
                .view(mx.bfloat16)
                .reshape(b_shape)
            )

        # Step 6: Re-index inds from original expert IDs to slot IDs (0..num_loaded-1)
        lookup = mx.zeros(self.num_experts, dtype=mx.uint32)
        for expert_idx, slot in expert_to_slot.items():
            lookup[expert_idx] = slot
        remapped_inds = lookup[inds]

        # Step 7: Forward through switch_mlp with remapped indices
        y = self.switch_mlp(x, remapped_inds)
        y = (y * scores[..., None]).sum(axis=-2)

        # Step 8: Shared expert (always GPU-resident)
        shared_y = self.shared_expert(x)
        shared_y = mx.sigmoid(self.shared_expert_gate(x)) * shared_y
        y = y + shared_y

        if self.sharding_group is not None:
            y = mx.distributed.all_sum(y, group=self.sharding_group)

        return y


def install_streaming(
    model,
    packed_dir: str | Path,
    layout_path: str | Path | None = None,
    num_io_workers: int = 4,
) -> StreamingState:
    """Install SSD streaming on all MoE layers of a model.

    Args:
        model: mlx-lm Model object (language_model.model.layers accessible).
        packed_dir: Directory with layer_XX.bin files.
        layout_path: Path to layout.json (defaults to packed_dir/layout.json).
        num_io_workers: Number of parallel pread threads.

    Returns:
        StreamingState for metrics tracking and cleanup.
    """
    packed_dir = Path(packed_dir)
    if layout_path is None:
        layout_path = packed_dir / "layout.json"

    layout = ExpertLayout.from_file(layout_path)

    state = StreamingState(
        layout=layout,
        executor=ThreadPoolExecutor(max_workers=num_io_workers),
    )

    # Open layer files
    state.layer_fds = open_layer_files(packed_dir, layout)
    if not state.layer_fds:
        raise FileNotFoundError(f"No layer_XX.bin files found in {packed_dir}")

    # Access model layers
    # Handle both qwen3_5_moe (language_model.model.layers) and direct models
    if hasattr(model, "language_model"):
        layers = model.language_model.model.layers
    elif hasattr(model, "model") and hasattr(model.model, "layers"):
        layers = model.model.layers
    else:
        raise ValueError("Cannot find model layers")

    # Replace each MoE layer's mlp with a StreamingMoeBlock wrapper.
    # MLX's nn.Module.__call__ uses C++ dispatch and ignores instance-level
    # __call__ overrides, so we must replace the entire object.
    patched = 0
    for layer_idx, layer in enumerate(layers):
        if hasattr(layer.mlp, "switch_mlp") and hasattr(layer.mlp, "gate"):
            if layer_idx in state.layer_fds:
                layer.mlp = StreamingMoeBlock(layer.mlp, layer_idx, state)
                patched += 1

    print(
        f"[streaming] Patched {patched}/{len(layers)} layers, "
        f"opened {len(state.layer_fds)} layer files"
    )
    return state


def unload_expert_weights(model) -> int:
    """Remove expert weights from GPU memory after streaming is installed.

    The streaming patches load experts on-demand from disk, so the
    pre-loaded weight tensors are wasted GPU memory. This function
    replaces them with tiny placeholders.

    Returns number of bytes freed (approximate).
    """
    import mlx.core as mx

    if hasattr(model, "language_model"):
        layers = model.language_model.model.layers
    elif hasattr(model, "model") and hasattr(model.model, "layers"):
        layers = model.model.layers
    else:
        return 0

    bytes_freed = 0
    for layer in layers:
        if not (hasattr(layer.mlp, "switch_mlp") and hasattr(layer.mlp, "gate")):
            continue
        switch = layer.mlp.switch_mlp
        for proj_name in ("gate_proj", "up_proj", "down_proj"):
            proj = getattr(switch, proj_name)
            for attr in ("weight", "scales", "biases"):
                if hasattr(proj, attr) and getattr(proj, attr) is not None:
                    old = getattr(proj, attr)
                    bytes_freed += old.nbytes
                    # Replace with tiny placeholder — streaming_call will overwrite
                    setattr(proj, attr, mx.zeros(1, dtype=mx.uint8))

    print(
        f"[streaming] Freed ~{bytes_freed / 1024**3:.1f} GB of expert weights from GPU"
    )
    return bytes_freed


def cleanup_streaming(state: StreamingState) -> None:
    """Close file descriptors and shut down thread pool."""
    close_layer_files(state.layer_fds)
    if state.executor:
        state.executor.shutdown(wait=False)


# ---------------------------------------------------------------------------
# Standalone benchmark
# ---------------------------------------------------------------------------


def _load_model_streaming(model_path: str, packed_dir: str | Path):
    """Load model with lazy=True, then selectively eval only non-expert weights.

    This avoids loading 200+GB of expert weights into GPU memory on a 128GB machine.
    Expert weights are replaced with tiny placeholders — the streaming patches will
    load them on-demand from packed_experts/ via pread.
    """
    import mlx.core as mx
    from mlx_lm import load

    print(f"[streaming] Loading model lazily from {model_path}...")
    t0 = time.monotonic()
    model, tokenizer = load(model_path, lazy=True)

    # Identify which parameters are expert weights (switch_mlp projections)
    # and which are non-expert (embeddings, attention, layernorm, router, shared expert)
    from mlx.utils import tree_flatten

    all_params = tree_flatten(model.parameters())

    expert_params = []
    non_expert_params = []
    for name, param in all_params:
        if "switch_mlp." in name:
            expert_params.append((name, param))
        else:
            non_expert_params.append((name, param))

    expert_bytes = sum(p.nbytes for _, p in expert_params)
    non_expert_bytes = sum(p.nbytes for _, p in non_expert_params)
    print(
        f"[streaming] Expert params: {len(expert_params)} "
        f"({expert_bytes / 1024**3:.1f} GB, will be streamed from disk)"
    )
    print(
        f"[streaming] Non-expert params: {len(non_expert_params)} "
        f"({non_expert_bytes / 1024**3:.1f} GB, loading to GPU)"
    )

    # Eval only non-expert parameters to materialize them in GPU memory
    non_expert_values = [p for _, p in non_expert_params]
    mx.eval(*non_expert_values)

    # Replace expert weight tensors with tiny placeholders
    # (They were lazy-loaded but never evaluated, so no GPU memory was used)
    freed = unload_expert_weights(model)

    # Clear any lazy graph references
    mx.clear_cache()

    load_time = time.monotonic() - t0
    print(
        f"[streaming] Model ready in {load_time:.1f}s "
        f"(loaded {non_expert_bytes / 1024**3:.1f} GB to GPU)"
    )

    return model, tokenizer, freed


def benchmark_streaming(
    model_path: str,
    packed_dir: str,
    prompts: list[str] | None = None,
    max_tokens: int = 200,
    num_io_workers: int = 4,
) -> dict:
    """Run streaming inference benchmark, return metrics dict."""
    import mlx.core as mx
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler

    if prompts is None:
        prompts = [
            "Explain the concept of zero-copy I/O in operating systems.",
            "Write a Python function that implements binary search.",
            "What are the key differences between RISC and CISC architectures?",
            "Describe how modern SSDs achieve high throughput.",
            "Explain the CAP theorem and its implications for distributed systems.",
        ]

    model, tokenizer, freed = _load_model_streaming(model_path, packed_dir)

    # Install streaming patches (monkey-patch SparseMoeBlock.__call__)
    state = install_streaming(model, packed_dir, num_io_workers=num_io_workers)

    sampler = make_sampler(temp=0.7)

    results = []
    for i, prompt in enumerate(prompts):
        print(f"\n[benchmark] Prompt {i+1}/{len(prompts)}: {prompt[:60]}...")

        state.total_pread_bytes = 0
        state.total_pread_calls = 0
        state.total_pread_time = 0.0

        tokens_out = 0
        text_out = []
        t_start = time.monotonic()
        t_first = None

        for response in stream_generate(
            model,
            tokenizer,
            prompt=prompt,
            max_tokens=max_tokens,
            sampler=sampler,
        ):
            if t_first is None and response.text:
                t_first = time.monotonic()
            if response.text:
                text_out.append(response.text)
            tokens_out = response.generation_tokens

        t_end = time.monotonic()
        elapsed = t_end - t_start
        ttft = (t_first - t_start) if t_first else 0.0
        tps = tokens_out / elapsed if elapsed > 0 else 0.0

        result = {
            "prompt_idx": i,
            "tokens": tokens_out,
            "elapsed_s": elapsed,
            "ttft_s": ttft,
            "tok_per_s": tps,
            "pread_bytes": state.total_pread_bytes,
            "pread_calls": state.total_pread_calls,
            "pread_time_s": state.total_pread_time,
            "pread_throughput_gbs": (
                state.total_pread_bytes / state.total_pread_time / 1024**3
                if state.total_pread_time > 0
                else 0
            ),
            "peak_memory_gb": response.peak_memory,
        }
        results.append(result)

        print(
            f"  {tokens_out} tokens in {elapsed:.1f}s = {tps:.1f} tok/s "
            f"(TTFT {ttft:.2f}s, pread {state.total_pread_time:.2f}s "
            f"@ {result['pread_throughput_gbs']:.1f} GB/s)"
        )

    # Summary
    cleanup_streaming(state)

    avg_tps = sum(r["tok_per_s"] for r in results) / len(results)
    avg_ttft = sum(r["ttft_s"] for r in results) / len(results)
    avg_pread_gbs = sum(r["pread_throughput_gbs"] for r in results) / len(results)

    summary = {
        "model_path": model_path,
        "packed_dir": packed_dir,
        "num_prompts": len(prompts),
        "max_tokens": max_tokens,
        "avg_tok_per_s": avg_tps,
        "avg_ttft_s": avg_ttft,
        "avg_pread_throughput_gbs": avg_pread_gbs,
        "expert_weight_freed_gb": freed / 1024**3,
        "per_prompt": results,
    }

    print(f"\n{'='*60}")
    print(
        f"SUMMARY: {avg_tps:.1f} tok/s avg, {avg_ttft:.2f}s TTFT avg, "
        f"{avg_pread_gbs:.1f} GB/s pread avg"
    )
    print(f"Expert weights freed: {freed / 1024**3:.1f} GB")
    print(f"{'='*60}")

    return summary


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="SSD Streaming MoE Benchmark")
    parser.add_argument("--model", required=True, help="Model path")
    parser.add_argument(
        "--packed-experts", required=True, help="Packed experts directory"
    )
    parser.add_argument("--max-tokens", type=int, default=200)
    parser.add_argument("--io-workers", type=int, default=4)
    args = parser.parse_args()

    results = benchmark_streaming(
        model_path=args.model,
        packed_dir=args.packed_experts,
        max_tokens=args.max_tokens,
        num_io_workers=args.io_workers,
    )

    # Save results
    out_path = (
        Path(__file__).parent.parent / "docs" / "benchmarks" / "streaming_phase0.json"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved to {out_path}")
