---
name: flashmoe-cache-tuning-reflect
type: reflection
bead: sylveste-vm4
date: 2026-03-29
---

## What went well

- The cache tuning flags (`--flashmoe-malloc-cache`, `--flashmoe-predict`) integrated cleanly into the existing FlashMoeWorker architecture — 17 lines of diff across existing files.
- The benchmark script was designed before running experiments, avoiding the common trap of ad-hoc measurement.
- Expert memory math was done upfront: Q3 hybrid experts at 5.4 MB each, 90 GB available → max 16,500 entries (53% coverage). This informed the sweep range.

## What I learned

- flash-moe's system prompt pre-caching takes 150+ seconds for 397B — this blocks the HTTP server entirely. The startup timeout (300s) is load-bearing. Future: consider making flash-moe launch async (serve health before prompt cache finishes).
- `--cache-entries` (LRU in regular memory) and `--malloc-cache` (GPU-resident with zero-copy Metal buffers) are independent knobs. The malloc variant is critical for performance because it avoids the memmove from CPU→GPU on every expert dispatch.
- Expert routing follows Zipf distribution — a cache holding 8% of experts can achieve ~60% hit rate. This means the first few thousand entries have outsized impact; diminishing returns past ~10,000.

## For next time

- The benchmark sweep hasn't been run yet (requires 30+ minutes of machine time per configuration × 5 configs). Create a bead for the actual sweep execution rather than blocking the sprint on it.
- `--predict` flag needs separate evaluation — it uses a temporal predictor trained on routing data. May need `--collect-routing` first to generate training data.
