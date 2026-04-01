# Plan: flash-moe expert cache tuning (sylveste-vm4)

## Context

Flash-moe proxy (sylveste-vpa) is integrated into interfer. Cold-cache performance on
Qwen3.5-397B is 0.1 tok/s. Flash-moe's ceiling is 11.1 tok/s with warm caches.
The gap is 100% cache misses: 240 SSD reads per token (4 experts × 60 layers).

## Memory Budget (M5 Max 128 GB)

- GPU limit: 96 GB (interfer default)
- Model weights (mmap'd dense): ~5.5 GB
- KV cache + linear attention state: ~0.5 GB
- **Available for expert cache: ~90 GB → max ~16,500 entries (53% of 30,720)**

Expert cache sizing (Q3 hybrid, 5.4 MB/expert):

| Entries | GPU (GB) | Coverage | Estimated hit rate* |
|---------|----------|----------|---------------------|
| 2,581   | 14.0     | 8.4%     | ~60% (Zipf)         |
| 5,000   | 27.2     | 16.3%    | ~75%                |
| 10,000  | 54.4     | 32.6%    | ~88%                |
| 15,000  | 81.6     | 48.8%    | ~93%                |

*Estimated from Zipf distribution of expert routing.

## Tasks

### Task 1: Benchmark script for cache sweep
Create `benchmarks/flashmoe_cache_sweep.sh` that:
- Starts flash-moe with a given `--malloc-cache N` value
- Sends 3 warmup prompts (to populate caches)
- Sends 5 benchmark prompts, captures tok/s from flash-moe's stderr log
- Reports: prefill tok/s, generation tok/s, cache hit rate
- Sweeps: 0 (baseline), 2581, 5000, 10000, 15000

### Task 2: Run the sweep and record results
Execute the benchmark script on this machine. Record the Pareto frontier
data (cache size vs tok/s vs GPU memory) in a results file.

### Task 3: Wire optimal config into interfer defaults
- Update `flashmoe_worker.py` to accept `malloc_cache` parameter
- Add `--flashmoe-malloc-cache` CLI flag to `__main__.py`
- Add `--predict` passthrough as `--flashmoe-predict`
- Set sensible defaults based on benchmark results

### Task 4: Tests
- Unit test for new CLI flags
- Unit test for `--malloc-cache` in FlashMoeWorker command construction

## Non-goals
- Changing flash-moe's C code (we only control CLI args)
- KV cache tuning (separate concern)
- Multi-model cache sharing
