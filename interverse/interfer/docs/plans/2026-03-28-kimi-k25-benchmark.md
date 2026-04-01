---
bead: sylveste-8v3
date: 2026-03-28
type: plan
complexity: C3
---

# Plan: Benchmark Kimi K2.5 3-bit

## Tasks

### Task 1: Test mlx-lm load path
Try loading Kimi K2.5 via mlx-lm's standard path. Determine if it OOMs
or successfully uses mmap for oversized models.

### Task 2: Benchmark decode performance
If loading succeeds, measure:
- tok/s at 50, 100, 200 tokens generated
- Time to first token
- Peak Metal memory

### Task 3: Quality spot-check
Generate 5 standard prompts and verify coherent output at 3-bit quant.

### Task 4: Record results
Commit benchmark results to `docs/benchmarks/` with model details,
hardware, and performance data.

### Task 5: Assess flash-moe port viability
Based on mlx-lm baseline, decide if flash-moe port is worth the effort
for the 8 tok/s target.
