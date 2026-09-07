---
artifact_type: brainstorm
bead: sylveste-benl.1
stage: discover
---

# Lens Library Go Package

## What We're Building

A complete Go port of Auraken's lens system — selection, graph, evolution, and stack orchestration — as a single public package at `os/Skaffen/pkg/lens/`. This is the foundational intelligence package: style fingerprinting, preference extraction, and profile generation all depend on lens access.

**Scope:** All four Python modules ported as one flat Go package with interface boundaries:
- `lenses.py` → types, JSON loading, `Selector` interface + Haiku implementation
- `lens_graph.py` → custom Louvain community detection, betweenness centrality, graph traversal (no gonum dependency)
- `lens_evolution.py` → effectiveness tracking with EMA scoring, engagement classification
- `lens_stacks.py` → sequential lens application with problem-redefinition transitions

**Data:** 291 lenses, 1,779 typed edges (complements/contrasts/sequences/refines), 7 Louvain communities, 15 bridge lenses. All embedded via `//go:embed` from JSON files.

## Why This Approach

**Flat package with interfaces** over sub-packages. Skaffen's existing code (`internal/provider/`, `internal/agentloop/`) uses this pattern. Go sub-packages create import verbosity and force types public prematurely for tightly-coupled code.

**Custom graph algorithms** over gonum. The graph operations are narrow (Louvain with seed=42, betweenness centrality, typed-edge neighbor traversal). Custom implementation avoids a heavy dependency and ensures deterministic parity with Python's networkx (seed=42, resolution=1.0).

**Skaffen's `provider.Provider`** for LLM calls, not subprocess. Python shells out to `claude -p --model haiku` — a pragmatic hack. Go should use the provider abstraction already in Skaffen, which handles model routing, timeouts, and structured output natively.

**GLM 5.1 via z.ai** as an additional provider option for lens selection. Provider key configured via environment variable (`Z_AI_API_KEY`), not hardcoded. This gives an alternative to Haiku for selection when cost/latency tradeoffs differ.

## Key Decisions

### 1. Package structure: `os/Skaffen/pkg/lens/`
Files: `types.go`, `loader.go`, `graph.go`, `louvain.go`, `betweenness.go`, `selector.go`, `evolution.go`, `stacks.go`, plus `*_test.go` for each.

Core interfaces:
- `Selector` — `Select(ctx, message, history) ([]Lens, error)` — LLM-based lens selection
- `Graph` — `Communities()`, `BridgeLenses()`, `Neighbors(id, edgeType)` — graph queries
- `Tracker` — `RecordEvent(lensID, userID, event)`, `Effectiveness(lensID)` — evolution tracking

### 2. Deterministic graph algorithms (no gonum)
- Louvain community detection: seed=42, resolution=1.0, matching networkx output
- Betweenness centrality: Brandes' algorithm on undirected weighted graph
- Graph stored as adjacency list with typed edges: `map[string][]TypedEdge`

### 3. Data embedding
- `lens_library_v2.json`, `lens_edges.json`, `lens_communities.json` copied to `pkg/lens/data/` and embedded via `//go:embed`
- Parsed once at `Load()` time, cached in package-level `sync.Once`
- `Reset()` for testing (matches Python's `reset_library()`)

### 4. Selector uses provider.Provider
- `HaikuSelector` wraps Skaffen's provider interface
- Constructs same prompt format as Python (1-indexed lens index, scale tags)
- Parses JSON array from LLM output (handles markdown fences, extra text)
- 15-second context timeout, graceful degradation (empty list on error)
- Provider-agnostic: can use Haiku, GLM 5.1, or any provider that satisfies the interface

### 5. Evolution tracking is in-memory with callback persistence
- Python uses SQLAlchemy for `LensUsage` records. Go package defines a `Store` interface for persistence
- In-memory EMA state with same parameters: engaged +0.1, ignored -0.05, pushed_back -0.1, floor 0.1, exploration bonus +0.15 for usage_count < 3
- Callers (Skaffen agent, Intercom) provide persistence implementation

### 6. Stack orchestrator is pure state machine
- `StackOrchestrator` struct with `NextPhase(userInput) Phase` method
- Transition templates (deep_gold, shallow_gold, wax) embedded as constants
- Serializable to/from JSON for session persistence
- No LLM dependency — purely deterministic sequencing

## Open Questions

1. **Parity testing baseline:** Task 0.1 (capture behavioral baseline from Auraken) hasn't been done yet. Should we create golden fixtures as part of this work or treat that as a prerequisite?
2. **Invariant spec:** Task 0.2 (write relational invariant spec) also hasn't been done. Write it as part of plan, or assume the Python code IS the spec?
3. **Lens data freshness:** If lenses are embedded at compile time, how do we handle lens library updates? Rebuild binary, or add runtime reload from filesystem as an alternative?
4. **Cross-package types:** Should `Lens`, `Edge`, `Community` types live in `pkg/lens/` or in a shared `pkg/types/` package? Other packages (fingerprint, extraction) will reference `Lens`.
