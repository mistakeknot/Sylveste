---
artifact_type: brainstorm
bead: Sylveste-0pvp
stage: discover
---

# Go Benchmark-Driven Optimization Across Core Pillars

## What We're Building

A systematic optimization pass across all 5 core pillars (Skaffen, Intercore, Intermute, Autarch, Clavain CLI) targeting measurable reductions in ns/op and allocs/op for performance-critical Go functions. Every optimization is gated by interlab harness benchmarks — changes that don't improve metrics get reverted.

## Why This Approach

Baselines established in Sylveste-2s7p revealed that many hot paths have unnecessary allocations, redundant computation per turn, and O(n*m) algorithms where O(n) suffices. The interlab harness infrastructure already exists (go-bench-harness.sh) — we can iterate with confidence.

**Guiding principle:** Benchmark first, optimize second. Every child bead starts by establishing a baseline, then targets a specific metric improvement.

## Key Decisions

### Tier 1 — Per-Turn Hot Paths (highest impact)

These run on EVERY agent turn, so even small improvements compound across thousands of turns per day:

| Target | Current | Problem | Strategy |
|--------|---------|---------|----------|
| `classifyFailure` (Skaffen agentloop) | No baseline | O(m*n) substring search + ToLower on 10K+ chars | Pre-lowercase once, compiled multi-pattern matcher |
| `estimateMessageTokens` (Skaffen agentloop) | No baseline | Iterates ALL messages (50-500+) every turn | Cache token counts for unchanged messages |
| `trust.Evaluator.Evaluate` (Skaffen trust) | No baseline | Linear glob scan per tool call (10-50+ calls/turn) | Pre-compile patterns, trie lookup |
| `classifyComplexity` (Clavain CLI) | 24us/55 allocs | Regex FindAllString + per-word ToLower | Single-pass scanner, pre-lowercase |

### Tier 2 — Per-Session Paths (high impact)

Run once per session or during compaction:

| Target | Current | Problem | Strategy |
|--------|---------|---------|----------|
| `Graph.Rank` (Skaffen repomap) | No baseline | O(nodes*edges*100) PageRank iteration | Pool arrays, early convergence, pre-sort |
| `ScoreMessages + TopK` (Skaffen session) | No baseline | Full O(n log n) sort for partial selection | Min-heap for O(n log k) |
| `composePlan` (Clavain CLI) | 81us/90 allocs | Repeated map iteration, per-role allocation | Pre-index fleet by role/capability |
| `parseFrontmatter` (Skaffen skill) | 20us/127 allocs | YAML reflection overhead | Cache by mtime or hand-roll |

### Tier 3 — Algorithmic Improvements (moderate impact)

Called less frequently but have algorithmic inefficiency:

| Target | Current | Problem | Strategy |
|--------|---------|---------|----------|
| `Assign` (Intercore scoring) | 95us/33 allocs at 20x8 | Fresh pair slice per call | sync.Pool or caller buffer |
| `TopologicalSort` (Intercore portfolio) | 23us/168 allocs at 50 nodes | sort.Strings in inner loop | Heap or pre-sorted adjacency |
| `DiffSpecs` (Autarch gurgeh) | 43us/240 allocs at 50 reqs | O(n*m) requirement comparison | Map-based set diff |
| `ReconcileProject` (Autarch events) | No baseline | Full FS walk + YAML + SHA256 per file | Cache hashes, skip by mtime |

### Tier 4 — Low Priority (benchmarked but fast enough)

| Target | Current | Problem | Strategy |
|--------|---------|---------|----------|
| `PatternsOverlap` (Intermute glob) | 2.6us/13 allocs | Path normalization per call | Pre-normalize at registration |
| `convertToolDefs` (Skaffen agentloop) | No baseline | Rebuilds 50-200 tool list every turn | Cache once, invalidate on change |
| `AtomicWriteFile` (Autarch file) | No baseline | Multiple syscalls per write | Profile syscall overhead |
| `Hub.Broadcast` (Intermute ws) | No baseline | Context per write, no batching | Pool snapshots, batch writes |

## Open Questions

1. **Should we upgrade Intercore and Clavain CLI from Go 1.22 to 1.24?** This would enable `b.Loop()` in benchmarks and newer runtime optimizations. Risk: dependency compatibility.
2. **What's the threshold for "worth optimizing"?** Proposal: only optimize if baseline > 10us or > 50 allocs, unless it's a per-turn function (where even 1us matters at scale).
3. **Execution order:** Start with Tier 1 (highest daily impact) or Tier 3 (established baselines, easier wins)?
