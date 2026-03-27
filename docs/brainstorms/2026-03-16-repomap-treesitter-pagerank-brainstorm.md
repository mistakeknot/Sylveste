---
artifact_type: brainstorm
bead: Sylveste-6i0.17
stage: discover
---

# Repo Map: Tree-Sitter Code Graph with PageRank

## What We're Building

A conversation-aware, token-budgeted repository map for Skaffen that uses tree-sitter tag extraction, a file-level reference graph, and personalized PageRank to rank code context by relevance to the current conversation. Replaces the current flat `go/ast` symbol listing with a dynamically ranked map that adapts to what the user is working on.

The repo map is injected as a dynamic priompt Element into Skaffen's system prompt, with phase-aware priority (boosted during Orient/Observe, demoted during Reflect/Compound) and binary-search token fitting.

## Why This Approach

### Grounded in PHILOSOPHY.md

- **"Adopt mature external tools"** — Intermap already has 3200+ lines of battle-tested tree-sitter extraction across 15+ languages. Rebuilding this in Go would violate the composition principle.
- **"Sovereignty Over Convenience"** — Skaffen owns the entire pipeline from graph construction onward. Only the Parse stage is delegated. The prompt-assembly chain (graph → rank → fit → format) runs in-process as pure Go.
- **"Graceful Degradation Everywhere"** — If intermap is unavailable, Skaffen falls back to the current `go/ast` map. No regression from today. Each layer degrades independently.
- **"Infrastructure unlocks autonomy"** — A relevance-ranked repo map gives the agent structural orientation that directly improves tool call accuracy and reduces hallucination.

### Why Aider-Style PageRank

5-agent parallel research (build-vs-integrate, graph-model, priompt-integration, alternatives, tag-extraction) converged independently on the same architecture:

- **LocAgent (ACL 2025)** confirms graph-based code localization is SOTA at 92.7% accuracy
- **Aider's approach** is the only one with a proven open-source implementation and years of production usage
- **Alternatives evaluated and ranked**: embedding-based (intersearch), LSP, git-signal, BM25, CASS. All are weaker as primary strategies but valuable as supplementary layers
- **Competitive survey**: Cursor, Copilot, Continue.dev, Cline all use layered retrieval. No tool relies on a single technique.

## Key Decisions

### 1. Hybrid Architecture: Intermap for Parsing, Go for Everything Else

**Pipeline stage ownership:**

| Stage | Owner | Fallback |
|-------|-------|----------|
| **Parse** (tag extraction) | intermap MCP (`reference_edges` tool) | `go/ast` for Go, regex for others |
| **Graph** (build adjacency) | Skaffen (Go, ~50 LOC) | Always available |
| **Rank** (personalized PageRank) | Skaffen (Go, ~80 LOC) | Always available |
| **Fit** (binary-search token budget) | Skaffen (Go, priompt ContentFunc) | Always available |
| **Format** (render to prompt text) | Skaffen (Go, priompt Element) | Always available |

**Why not all-intermap:** Personalization vector changes per turn (conversation context). Sending it to Python each turn adds latency and couples Skaffen to intermap's process. The ranking must be in-process.

**Why not all-Go:** CGO_ENABLED=0 blocks native tree-sitter bindings. No viable pure-Go multi-language parser today (wazero-based `malivvan/tree-sitter` is pre-release but promising).

### 2. File-Level Graph with Identifier-Labeled Edges

```
Edge: (referencer_file) --[identifier, weight]--> (definer_file)
```

- **Nodes are files**, not identifiers — keeps graph at 2K nodes for a 2K-file repo (vs 52K with identifier nodes)
- **Identifiers live on edges** — PageRank computes file importance, then edge-weight distribution recovers identifier-level ranking (Aider's proven technique)
- **Personalization is per-file** — signals (edited files, git diff, mentioned files) are file-level

### 3. Hand-Rolled Personalized PageRank (~80 Lines Go)

- No existing Go library supports personalization vectors (alixaxel, dcadenas, gonum all lack it)
- Power iteration converges in <15ms for 2000-file repos (40 iterations × 15K edges)
- Zero dependencies, zero CGO
- **Personalization signals (priority order):**
  1. Chat/edited files (weight ×10)
  2. Git-diff files (weight ×5)
  3. Mentioned identifiers (edge weight ×10, not teleport)

### 4. Priompt Integration

```go
priompt.Element{
    Name:     "repomap",
    Priority: 35,
    Stable:   false,
    PhaseBoost: map[string]int{
        "observe": +15, "orient": +15, "decide": +5,
        "act": 0, "reflect": -15, "compound": -20,
    },
    Render: repomapContentFunc(workDir, ranker),
}
```

- **Stable: false** — map changes between turns; making it stable would invalidate the entire cache prefix on any rank change
- **Priority 35** — below context files (80-90) and fault localization (65), above optional context
- **ContentFunc** uses 15% budget heuristic with 8K hard cap and 500-token floor
- **Cache graph, recompute rank** — graph is expensive (tag extraction), rank is cheap (<15ms)

### 5. One New Intermap MCP Tool: `reference_edges`

~120 lines total (50 Python + 25 Go + misc). The data already exists in `build_project_call_graph()._edges` — just needs a thin MCP wrapper. Returns `(definer_file, symbol, referencer_file)` triples with line numbers and kinds.

### 6. Layered Retrieval Stack

```
Layer 0 (always):    go/ast naive map (current baseline, Go-only)
Layer 1 (seed):      git recency + conversation files → personalization weights
Layer 2 (primary):   tree-sitter tags → reference graph → PageRank
                     Falls back to BM25 over tags if graph too large/timeout
Layer 3 (optional):  intersearch embedding pre-filtering (when MCP available)
```

Each layer degrades independently. System always produces useful output.

### 7. Prerequisite: PriomptSession Migration

`main.go` currently uses flat string prompts via `session.New()`, not `PriomptSession`. The migration to `[]priompt.Element` sections is required before the repomap Element can be wired in. `PriomptSession` exists but isn't connected.

## Open Questions

1. **`malivvan/tree-sitter` (wazero)** — pre-release pure-Go tree-sitter via WASM. If it stabilizes, could eventually replace the intermap dependency for parsing. Monitor maturity. ~1.5x overhead vs native C, negligible for tag extraction (I/O bound).

2. **`go/packages` vs `go/ast`** — `go/packages` (golang.org/x/tools) provides full type-checked ASTs with cross-package resolution, strictly better than `go/ast` for Go-only fallback. Trade: adds x/tools dependency. Worth it?

3. **BM25 fallback implementation** — `crawlab-team/bm25` (pure Go) or roll our own? Research shows BM25 over symbol names outperforms embeddings for code-to-code retrieval.

4. **Conversation personalization depth** — Aider extracts mentioned identifiers from chat text via regex. How deep should Skaffen go? Simple approach: file paths + explicit @-mentions. Complex approach: NLP extraction of identifier-like tokens from conversation.

5. **Multi-language edge quality** — 6 languages have full call graph support in intermap (Python, Go, TS, Rust, Java, C). 8 more have imports only. What's the degradation strategy for import-only languages?

## Implementation Sequence

1. **Phase 1 — Infrastructure** (no intermap changes):
   - Extract `repomap.go` to `internal/repomap/` package
   - Implement graph + PageRank + binary-search fitting in pure Go
   - Wire as priompt Element with ContentFunc
   - Use current `go/ast` as data source (Go-only, flat ranking by proximity)
   - Migrate `main.go` from `session.New()` to `NewPriomptSession()` (prerequisite)

2. **Phase 2 — Intermap integration**:
   - Add `reference_edges` MCP tool to intermap (~120 lines)
   - Add MCP call in Skaffen's repomap package
   - Cache edge list by git SHA
   - Fall back to Phase 1 if intermap unavailable

3. **Phase 3 — Personalization**:
   - Add git-diff personalization signal
   - Add edge-weight distribution for identifier-level ranking
   - Add conversation-mentioned identifier detection

4. **Phase 4 — Polish** (deferred):
   - BM25 fallback layer
   - `definition_tags` MCP tool for richer symbol signatures
   - `malivnan/tree-sitter` evaluation for pure-Go parsing
   - intersearch embedding pre-filtering

## Research Sources

Full research outputs in `.claude/flux-drive-output/`:
- `fd-repomap-build-vs-integrate.md` — hybrid architecture decision matrix
- `fd-repomap-graph-model.md` — PageRank algorithm, implementation sketch, convergence benchmarks
- `fd-repomap-priompt-integration.md` — Element design, token partition model, cache analysis
- `fd-repomap-alternatives.md` — competitive survey, layered retrieval architecture
- `fd-repomap-tag-extraction-surface.md` — language coverage matrix, MCP tool schema, Go fallback design
