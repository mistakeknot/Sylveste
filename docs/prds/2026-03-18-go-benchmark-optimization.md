---
artifact_type: prd
bead: Sylveste-0pvp
stage: design
---

# PRD: Go Benchmark-Driven Optimization Across Core Pillars

## Problem

Hot-path Go functions across all 5 pillars have unnecessary allocations, redundant per-turn computation, and O(n*m) algorithms where O(n) suffices. Baselines from Sylveste-2s7p show classifyComplexity at 55 allocs/call, TopologicalSort at 168 allocs, DiffSpecs at 240 allocs. Per-turn functions like classifyFailure and estimateMessageTokens lack baselines entirely.

## Solution

Systematically benchmark, optimize, and regression-gate every performance-critical function. Each target starts with baseline measurement via interlab harness, then applies targeted optimization (pattern caching, pre-allocation, algorithmic improvement). Changes that don't measurably improve metrics get reverted.

## Features

### Wave 1: Per-Turn Hot Paths (Highest Daily Impact)

#### F1: Optimize classifyFailure — Skaffen agentloop
**Bead:** Sylveste-0pvp.11
**What:** Eliminate redundant ToLower + O(m*n) substring search on every agent turn.
**Acceptance criteria:**
- [ ] Benchmark established for 1K, 10K, 100K char inputs
- [ ] Single-pass scanner replaces double-pass pattern matching
- [ ] Input lowercased once, not per-pattern
- [ ] ns/op reduced by >50% on 10K input
- [ ] Zero allocation regression in interlab harness

#### F2: Optimize estimateMessageTokens — Skaffen agentloop
**Bead:** Sylveste-0pvp.12
**What:** Cache token counts for unchanged messages instead of re-counting all 50-500+ messages every turn.
**Acceptance criteria:**
- [ ] Benchmark established for 20, 50, 100, 500 message contexts
- [ ] Cached estimation returns in <1us for unchanged messages
- [ ] New messages still counted accurately
- [ ] Interlab harness shows >80% reduction for steady-state turns

#### F3: Optimize trust.Evaluator.Evaluate — Skaffen trust
**Bead:** Sylveste-0pvp.16
**What:** Replace linear glob scan with pre-compiled pattern matching for per-tool-call trust evaluation.
**Acceptance criteria:**
- [ ] Benchmark established for 5, 50, 500 learned overrides
- [ ] O(1) or O(log n) lookup replaces O(n) linear scan
- [ ] filepath.Match called at Learn-time, not Evaluate-time
- [ ] ns/op reduced by >70% at 50+ overrides

#### F4: Optimize classifyComplexity — Clavain CLI
**Bead:** Sylveste-0pvp.1
**What:** Eliminate regex allocations and per-word ToLower in complexity heuristic.
**Acceptance criteria:**
- [ ] Baseline: 24us, 2.5KB, 55 allocs (established)
- [ ] Target: <5us, <500B, <5 allocs
- [ ] Single-pass word scanner replaces FindAllString
- [ ] Input lowercased once before keyword matching

#### F5: Optimize extractFileActivity — Skaffen agentloop
**Bead:** Sylveste-0pvp.13
**What:** Pre-filter tool calls by name before JSON unmarshal.
**Acceptance criteria:**
- [ ] Benchmark established for 10, 50, 100 tool calls (5% file ops)
- [ ] JSON unmarshal skipped for non-file-operation tools
- [ ] ns/op reduced by >80% when <10% of calls are file ops

### Wave 2: Per-Session Paths

#### F6: Optimize Graph.Rank (PageRank) — Skaffen repomap
**Bead:** Sylveste-0pvp.14
**What:** Pool rank arrays, add early convergence termination, pre-sort node lists.
**Acceptance criteria:**
- [ ] Benchmark established for 100, 500, 1000 nodes with varying edge density
- [ ] Array pooling eliminates per-call allocations
- [ ] Early convergence terminates when delta < 1e-6
- [ ] >30% improvement on 500-node graph

#### F7: Optimize ScoreMessages + TopK — Skaffen session
**Bead:** Sylveste-0pvp.15
**What:** Replace full sort with min-heap for top-K selection during compaction.
**Acceptance criteria:**
- [ ] Benchmark established for 50, 200, 1000 messages
- [ ] Min-heap selection O(n log k) replaces O(n log n) sort
- [ ] >40% improvement when K << N (e.g., K=50, N=500)

#### F8: Optimize composePlan — Clavain CLI
**Bead:** Sylveste-0pvp.5
**What:** Pre-index fleet by role and capability to avoid repeated map iteration.
**Acceptance criteria:**
- [ ] Baseline: 81us, 44KB, 90 allocs at 30 agents (established)
- [ ] Target: <40us, <20KB, <30 allocs
- [ ] Role index built once at plan start
- [ ] matchRole uses index instead of linear scan

#### F9: Optimize parseFrontmatter — Skaffen skill
**Bead:** Sylveste-0pvp.4
**What:** Cache parsed frontmatter by file mtime or replace yaml.Unmarshal with targeted scanner.
**Acceptance criteria:**
- [ ] Baseline: 20us, 11KB, 127 allocs (established)
- [ ] Target: <5us, <2KB, <10 allocs (cache hit) or <12us (hand-rolled)
- [ ] Cache invalidated on mtime change
- [ ] Zero functional regression in skill loading

### Wave 3: Algorithmic Improvements

#### F10: Reduce scoring Assign allocations — Intercore
**Bead:** Sylveste-0pvp.2
**What:** Pre-allocate pair slices or use sync.Pool for scoreAllPairs.
**Acceptance criteria:**
- [ ] Baseline: 95us, 83KB, 33 allocs at 20x8 (established)
- [ ] Target: <70us, <50KB, <15 allocs
- [ ] selectAssignments uses partial sort where applicable

#### F11: Optimize TopologicalSort — Intercore portfolio
**Bead:** Sylveste-0pvp.3
**What:** Replace per-iteration sort.Strings with heap-based ready queue.
**Acceptance criteria:**
- [ ] Baseline: 23us, 14KB, 168 allocs at 50 nodes (established)
- [ ] Target: <15us, <8KB, <50 allocs
- [ ] Deterministic output preserved

#### F12: Optimize DiffSpecs — Autarch gurgeh
**Bead:** Sylveste-0pvp.6
**What:** Map-based set diff replaces O(n*m) linear comparison.
**Acceptance criteria:**
- [ ] Baseline: 43us, 20KB, 240 allocs at 50 reqs (established)
- [ ] Target: <20us, <10KB, <80 allocs
- [ ] diffAcceptanceCriteria and diffCUJs also use map-based approach

#### F13: Benchmark ReconcileProject — Autarch events
**Bead:** Sylveste-0pvp.19
**What:** Cache SHA256 hashes, skip unchanged files by mtime.
**Acceptance criteria:**
- [ ] Benchmark established for 10, 100, 500 spec files
- [ ] Mtime-based skip reduces work for no-change reconciliation by >90%
- [ ] Hash cache persists across reconciliation cycles

#### F14: Benchmark Hub.Broadcast + snapshot — Intermute ws
**Bead:** Sylveste-0pvp.18
**What:** Pool connection snapshots, batch writes.
**Acceptance criteria:**
- [ ] Benchmark established for 10, 100, 1000 connections
- [ ] Snapshot slice pooled with sync.Pool
- [ ] >30% improvement at 100+ connections

### Wave 4: Low Priority

#### F15: Optimize PatternsOverlap — Intermute glob
**Bead:** Sylveste-0pvp.7
**What:** Pre-normalize patterns at registration time.
**Acceptance criteria:**
- [ ] Baseline: 2.6us, 3KB, 13 allocs (established)
- [ ] Target: <1.5us, <1KB, <5 allocs (pre-normalized)

#### F16: Cache convertToolDefs — Skaffen agentloop
**Bead:** Sylveste-0pvp.17
**What:** Cache tool definition list, invalidate only on registry change.
**Acceptance criteria:**
- [ ] Benchmark established for 50, 100, 200 tools
- [ ] Cached path returns in <100ns
- [ ] Invalidation triggered correctly on tool add/remove

#### F17: Benchmark AtomicWriteFile — Autarch file
**Bead:** Sylveste-0pvp.20
**What:** Profile syscall overhead at various file sizes.
**Acceptance criteria:**
- [ ] Benchmark established for 1K, 10K, 100K, 1M files
- [ ] Identify whether directory fsync is the dominant cost
- [ ] Optimize only if >10us overhead beyond raw write

## Non-goals

- **No architectural changes.** These are surgical, function-level optimizations.
- **No new dependencies.** Use stdlib and existing packages only.
- **No API changes.** All optimizations are internal — signatures unchanged.
- **No premature optimization.** Skip targets where baseline is already <1us unless per-turn.

## Dependencies

- Interlab harness infrastructure (go-bench-harness.sh) — already exists
- Per-pillar interlab.sh scripts — already created in Sylveste-2s7p
- Go 1.22+ for Intercore/Clavain, Go 1.24 for Skaffen/Autarch/Intermute

## Open Questions

1. Should Intercore and Clavain CLI upgrade to Go 1.24 for b.Loop() and runtime improvements?
2. For ReconcileProject (F13), is mtime reliable across NFS/mutagen sync?
3. For trust.Evaluate (F3), should we use a radix tree or compiled glob set?
