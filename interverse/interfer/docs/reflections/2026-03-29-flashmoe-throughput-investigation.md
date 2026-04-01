---
name: flashmoe-throughput-investigation-reflect
description: Investigation of apparent 10x throughput regression after flash-moe upstream merge
type: reflection
bead: sylveste-1xj
date: 2026-03-29
---

## Root Cause: Not a Regression

The 12.2 tok/s on the old Q3 hybrid build was invalid. The Q3 format read 5.4MB from 7.1MB experts, producing garbage output (repeated EOS) that inflated cache hit rates. Real throughput with correct 4-bit experts: 2-3 tok/s.

## Key Evidence

Old build generated token_id=0 (EOS) for tokens 2-9. New build generates diverse coherent tokens. Same experts re-routed = 99.4% hits. Diverse routing = 60-78% hits.

## What We Fixed

- Benchmark script: removed --q3-experts, added explicit weight paths, updated expert size
- FlashMoeWorker: passes explicit --weights/--manifest/--vocab (upstream requires them)
- AGENTS.md: corrected performance data, invalidated old benchmarks

## Lesson

Always validate output quality alongside throughput. Fast garbage is worse than slow correctness.
