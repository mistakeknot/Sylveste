# Strategy: Flash-MoE Throughput Regression

**Bead:** sylveste-1xj
**Date:** 2026-03-29

## Problem

5.1x expert_io regression after upstream merge. Need to determine: how much is inherent (larger experts) vs fixable (pipeline inefficiency).

## Approach: Differential Diagnosis

1. **Test 2-bit experts** — if throughput scales linearly with expert size (3.9MB → faster), confirms I/O bound. If not, pipeline issue.
2. **Profile mmap vs pread** — the upstream mmaps layer files. Check if mmap path has different I/O scheduling than pread-only path.
3. **Check malloc_cache sizing** — 70.8GB for 10000 entries at 7.1MB/expert. This is 55% of 128GB. Try smaller cache (5000) to reduce memory pressure.
4. **If fixable:** patch the upstream or re-introduce Q3 hybrid support.
5. **If inherent:** update benchmark results, adjust recommended malloc-cache default, document the quality-speed tradeoff.

## Success Criteria

- [ ] Root cause identified (inherent vs fixable vs both)
- [ ] If fixable: patch applied, throughput restored to >5 tok/s
- [ ] If inherent: documented tradeoff, updated AGENTS.md with new recommended config
- [ ] Benchmark re-run with new binary
