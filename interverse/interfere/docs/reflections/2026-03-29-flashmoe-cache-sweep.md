---
name: flashmoe-cache-sweep-reflect
description: Learnings from flash-moe expert cache sweep benchmark on M5 Max
type: reflection
bead: sylveste-rb6
date: 2026-03-29
---

## What Worked

- The malloc-cache sweep produced clear, actionable data: 10000 entries (54GB) is the throughput sweet spot at 12.2 tok/s mean, 15000 is worse due to memory pressure.
- Cache telemetry (`--cache-telemetry`) was valuable: showed 99.4% hit rate across all configs with zero evictions — the throughput difference is from I/O path efficiency, not hit rate.
- Metal NAX (Neural Architecture eXtensions) on M5 Max provides significant acceleration — confirmed by the 10 tok/s+ throughput vs 0.08 tok/s on CPU fallback.

## What Didn't Work

- **Shader loading requires CWD = binary dir.** flash-moe looks for `shaders.metal` in CWD, not relative to the binary. The first two benchmark runs (3 total attempts) ran with CPU fallback because the script ran from the interfere directory. Fix: `(cd "$BINARY_DIR" && "${CMD[@]}")`.
- **`set -euo pipefail` + grep no-match = silent crash.** The `extract_cache_stats` function used `grep` without `|| true`. When config=0 had no `malloc_cache` lines, grep returned 1, pipefail killed the script after printing bench results but before writing the TSV row. Lost 40 minutes of benchmark time before diagnosing.
- **LRU cache (--cache-entries) has pread EFAULT on GPU Metal path.** The kyz fix only covered the malloc-cache I/O path. Config=0 still uses Metal MTLBuffer pointers as pread destinations, causing errno 14. Created sylveste-kjl for follow-up.

## Surprising Findings

- 15000 entries (82GB) is **slower** than 10000 (54GB). The extra 28GB of cache competes with Metal GPU buffers for unified memory bandwidth. On Apple Silicon, unified memory means CPU and GPU share the same physical RAM — oversized caches create contention even when the system reports 84% free memory.
- 2581 entries (14GB) is only 13% slower than the optimal 10000 (10.6 vs 12.2 tok/s). For memory-constrained scenarios, this is surprisingly viable.
- Startup time at 15000 is 27s vs 9s at 10000 — the pre-allocation of 82GB of zero-copy Metal wrappers is expensive.

## Decision Record

**Recommended default: `--flashmoe-malloc-cache 10000`** for 128GB systems.
Rationale: best throughput, 54GB cache leaves 74GB for model weights + Metal buffers + OS.
