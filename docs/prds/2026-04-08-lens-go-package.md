---
artifact_type: prd
bead: sylveste-benl.1
brainstorm: docs/brainstorms/2026-04-08-lens-go-package-brainstorm.md
review: docs/research/flux-review/lens-go-package/2026-04-08-synthesis.md
stage: design
---

# PRD: Lens Library Go Package

## Problem

Auraken's lens system (291 lenses, graph relationships, LLM selection, effectiveness tracking, stack orchestration) is locked in a Python runtime. Other Skaffen agents cannot access lens intelligence. The Go ecosystem has no lens capability.

## Solution

Port all four Auraken lens modules to a single Go package at `os/Skaffen/pkg/lens/` with interface boundaries. Custom graph algorithms (no gonum), provider-based LLM calls, and a persistence-agnostic Store interface. Golden fixtures from Python serve as the acceptance test oracle.

## Features

### F0: Golden Fixtures (Prerequisite)
**What:** Capture behavioral baseline from Python Auraken as JSON test oracles before writing any Go.
**Acceptance criteria:**
- [ ] Community assignments for all 291 lenses (lens-id → community-id)
- [ ] Bridge lens IDs with betweenness scores (ordered list, 15 lenses)
- [ ] EMA trajectories for 5 defined event sequences (engaged, ignored, pushed_back, mixed, cold-start)
- [ ] Selector outputs for 10 diverse messages with recorded Haiku responses
- [ ] Stack transition outputs for 3 template types (deep_gold, shallow_gold, wax) across 4-phase sequences
- [ ] All fixtures saved to `os/Skaffen/pkg/lens/testdata/golden_*.json`
- [ ] Python git SHA and model versions documented

### F1: Types + Data Loading
**What:** Define core types and embed lens data with validated loading.
**Acceptance criteria:**
- [ ] `Lens`, `Edge`, `Community`, `LensRef` types in `types.go` with JSON tags on all fields
- [ ] `//go:embed` for `lens_library_v2.json`, `lens_edges.json`, `lens_communities.json`
- [ ] Retry-capable init state machine (not bare sync.Once) — loads on first call, retries on failure
- [ ] Post-parse validation: 291 lenses, 1779 edges, 7 communities, all edge references valid
- [ ] `Reset()` that clears all cached state (graph, communities, bridges) for testing
- [ ] JSON round-trip tests for all exported types
- [ ] `go build ./pkg/lens/...` passes

### F2: Graph Algorithms
**What:** Custom Louvain community detection and Brandes betweenness centrality with deterministic output.
**Acceptance criteria:**
- [ ] `Graph` interface: `Communities()`, `BridgeLenses()`, `Neighbors(id, edgeType)`, `CommunityOf(id)`
- [ ] Louvain: sorted-key iteration before every map loop, resolution=1.0
- [ ] Betweenness: Brandes algorithm on typed edges
- [ ] 10-run determinism test: same communities and bridge set every run
- [ ] Parity tests against golden fixtures: exact community membership match for all 291 lenses
- [ ] Parity tests against golden fixtures: exact bridge lens set with score tolerance (1e-10)
- [ ] Multi-typed edge handling: single adjacency entry per pair with `[]string` types

### F3: LLM Selector
**What:** Provider-based lens selection with typed error handling.
**Acceptance criteria:**
- [ ] `Selector` interface: `Select(ctx, message, history) ([]LensRef, error)`
- [ ] `LLMSelector` implementation using `provider.Provider` (not subprocess)
- [ ] `CollectText()` helper added to provider package (or verified existing)
- [ ] 1-indexed prompt construction matching Python format (scale tags, compact index)
- [ ] JSON response parsing: handles bare arrays, wrapped objects, markdown fences
- [ ] Typed errors: `ErrSelectionTimeout`, `ErrProviderUnavailable`, `ErrInvalidResponse`
- [ ] 15-second context timeout enforced regardless of provider behavior
- [ ] Bounds checking on LLM-returned indices (1 ≤ idx ≤ 291)
- [ ] Parity tests using recorded Haiku responses from golden fixtures

### F4: Evolution Tracker
**What:** EMA effectiveness scoring with persistence-agnostic Store.
**Acceptance criteria:**
- [ ] `Tracker` interface: `RecordEvent(lensID, userID, event)`, `Effectiveness(lensID) float64`
- [ ] `Store` interface: `Load(ctx) error`, `RecordEvent(...)`, `Flush(ctx) error` with documented latency contract
- [ ] EMA parameters: engaged +0.1, ignored -0.05, pushed_back -0.1, floor 0.1, exploration bonus +0.15 (usage < 3)
- [ ] Floor applied AFTER delta: `max(current + delta, 0.1)` — matches Python exactly
- [ ] `usage_count` persisted via Store, not volatile in-memory
- [ ] Engagement classification heuristic: byte-identical phrase lists to Python
- [ ] Parity tests against golden EMA trajectories
- [ ] Concurrent RecordEvent safety (sync.Map or per-key mutex, -race enabled)

### F5: Stack Orchestrator
**What:** Sequential lens application state machine with problem-redefinition transitions.
**Acceptance criteria:**
- [ ] `StackOrchestrator` struct with `sync.Mutex` protecting state
- [ ] `NextPhase(userInput) (Phase, error)` — returns `ErrStackExhausted` when done
- [ ] `Phase` as named typed enum with iota constants
- [ ] Transition templates: deep_gold, shallow_gold, wax (embedded constants)
- [ ] JSON serialization: all state fields exported with json tags, round-trip test
- [ ] Parity tests against golden stack transition outputs

## Non-goals

- Runtime lens data reload from filesystem (embed-only for v1)
- Cosine similarity or embedding-based selection (LLM-only)
- Database migrations from Auraken (separate bead)
- Forge-mode safety fields (contraindications, near_miss — schema'd but empty, port structure only)

## Dependencies

- `provider.Provider` interface at `os/Skaffen/internal/provider/` — need `CollectText()` or equivalent
- Python Auraken must be runnable to generate golden fixtures (F0)
- Lens data files from `apps/Auraken/src/auraken/` (JSON, copied to pkg/lens/data/)

## Open Questions (Resolved)

1. ~~Golden fixtures: prerequisite or parallel?~~ **Prerequisite.** (Flux-review 3/4 convergence)
2. ~~Invariant spec: prerequisite or parallel?~~ **Part of F0.** Python behavioral outputs ARE the spec.
3. ~~Lens data freshness?~~ **Embed-only for v1.** Filesystem override deferred.
4. ~~Cross-package types?~~ **LensRef in pkg/lens/ as cross-package currency.** Full Lens stays internal to graph consumers.

## Review Findings Incorporated

From 4-track flux-review (28 deduplicated findings):
- P0-DETERM → F2 sorted-key iteration requirement
- P0-GOLDEN → F0 as hard prerequisite
- P0-SYNCONCE → F1 retry-capable state machine
- P0-STREAM → F3 CollectText() dependency
- P0-TIMEOUT → F3 typed errors
- P1-RESET → F1 Reset() specification
- P1-EMA → F4 floor-after-delta requirement
- P1-ZOMBIE → F4 usage_count persistence
- P1-LENSREF → F1 LensRef type
- P1-EDGETYPE → F2 multi-typed edge handling
- P1-MUTEX → F5 sync.Mutex requirement
- P1-EXHAUSTED → F5 ErrStackExhausted
