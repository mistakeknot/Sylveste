---
bead: sylveste-2nt
title: Q3 inference NaN — two bugs, one CWD and one expert-size mismatch
---

# Reflect: Q3 GGUF Inference NaN Fix

## Root causes (two independent bugs)

**Bug 1: Missing shaders.metal (CWD-dependent).** The flash-moe binary searches for `shaders.metal` at `./shaders.metal` and `./metal_infer/shaders.metal`. When invoked from a different directory, Metal initialization fails silently and falls back to CPU — producing 0.04 tok/s and NaN logits because the CPU path doesn't support Q3 dequant. Fix: set `cwd` in FlashMoeWorker's subprocess spawn to the binary's repo root.

**Bug 2: Malloc-cache uses wrong expert size for layer 27.** `active_expert_size()` returns the Q3 hybrid size (5.44 MB) for ALL layers, but layer 27's outlier experts are 7.34 MB. The malloc-cache allocated 5.44 MB entries, and pread into undersized buffers caused EFAULT (-1). Fix: malloc-cache allocates at `max_expert_size_for_current_config()` (7.34 MB). Fused layer forward uses `layer_expert_size(layer_idx)` for pread (6 sites fixed).

## Lessons
- **Always check the first line of output.** The `ERROR: Cannot find shaders.metal` was printed FIRST but I initially only looked at the timing breakdown at the end.
- **Per-layer polymorphism needs per-layer plumbing.** The Q3 outlier layer is a special case that 13 callsites must handle. Grep for `active_expert_size` to find all sites — several utility functions still use it and will break if called with a layer-27 context.
- **The "Hello" 1-token test was a false positive.** It worked because single-token prompts with cold page cache bypass the pread path entirely (mmap serves the data). Multi-token prompts with warm cache exposed both bugs.
