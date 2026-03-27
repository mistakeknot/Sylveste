---
artifact_type: prd
bead: Sylveste-6i0.17
stage: design
---

# PRD: Conversation-Aware Repo Map with PageRank

## Problem

Skaffen's current `/map` command produces a flat, alphabetical Go-only symbol listing capped at 8000 chars with no relevance ranking, no multi-language support, and no integration into the system prompt. The agent has no automatic structural orientation — it can't see which files are most relevant to the current conversation without the user explicitly running `/map`.

## Solution

A layered retrieval system that injects a relevance-ranked repository map into Skaffen's system prompt as a dynamic priompt Element. Uses tree-sitter tag extraction (via intermap MCP), a file-level reference graph, and personalized PageRank to rank code context by conversation relevance. Degrades gracefully through 4 layers (graph → BM25 → go/ast → empty).

## Features

### F1: PriomptSession Migration

**What:** Migrate `main.go` from flat string prompts to `[]priompt.Element` sections via `NewPriomptSession()`, enabling dynamic, phase-aware, budget-managed prompt composition.

**Acceptance criteria:**
- [ ] `cmd/skaffen/main.go` uses `session.NewPriomptSession(inner, sections)` instead of `session.New()` with flat string
- [ ] Context files (CLAUDE.md, SKAFFEN.md, AGENTS.md) are a Stable priompt Element at Priority 85
- [ ] Fault localization guidance is a Dynamic Element at Priority 65 with Act phase boost
- [ ] All existing tests pass with the new session type
- [ ] Evidence pipeline still captures priompt metadata (stable_tokens, excluded_elements)
- [ ] Both TUI and print modes work with PriomptSession

### F2: Repomap Package with Go-Native PageRank

**What:** Extract `repomap.go` from `internal/tui/` to a new `internal/repomap/` package, add file-level reference graph, personalized PageRank (~80 LOC), and binary-search token fitting. Wire as a priompt Element.

**Acceptance criteria:**
- [ ] New `internal/repomap/` package with `Graph`, `Rank()`, `NewElement()` exported
- [ ] Personalized PageRank implementation: sparse adjacency, power iteration, personalization vector, <15ms for 500-file repo
- [ ] Binary-search token fitting within ContentFunc (15% budget heuristic, 8K cap, 500-token floor)
- [ ] priompt.Element with Priority 35, Stable=false, PhaseBoost for all 6 OODARC phases
- [ ] Go-native `go/ast` tag extraction extended to emit reference pairs (cross-file `SelectorExpr` resolution)
- [ ] Mtime-based graph cache with partial invalidation for single-file edits
- [ ] `/map` TUI command uses the new package (thin wrapper)
- [ ] Tests: PageRank convergence on known graph, token fitting respects budget, cache invalidation works

### F3: Intermap `reference_edges` MCP Tool

**What:** Add a new MCP tool to intermap that exposes tree-sitter tag extraction data as PageRank-ready edge triples, with line numbers, kinds, and auto-language detection.

**Acceptance criteria:**
- [ ] New `reference_edges` tool in `interverse/intermap/internal/tools/tools.go`
- [ ] Python `reference_edges` command in `analyze.py` reshaping `build_project_call_graph` output
- [ ] `build_function_index` extended to return line numbers and kinds (~50 lines across 6 indexers)
- [ ] Auto-language detection (count file extensions, pick dominant)
- [ ] Response schema: `{definitions: [{file, name, line, kind, scope}], edges: [{src_file, src_symbol, dst_file, dst_symbol}], files_scanned, language, edge_count}`
- [ ] Tool registered in intermap's `RegisterAll()` with proper MCP schema
- [ ] Works for all 6 full-graph languages: Python, Go, TypeScript, Rust, Java, C

### F4: Skaffen-Intermap Integration with Graceful Degradation

**What:** Wire Skaffen's repomap package to call intermap's `reference_edges` MCP tool, cache by git SHA, and fall back to Go-native extraction when intermap is unavailable.

**Acceptance criteria:**
- [ ] MCP call to `reference_edges` in repomap package, triggered on graph cache miss
- [ ] Edge list cached by git HEAD SHA (reuse intermap's gitHeadSHA pattern)
- [ ] Graceful degradation: if MCP call fails or intermap not loaded, fall back to F2's `go/ast` extraction
- [ ] No regression when intermap is absent — behavior identical to F2
- [ ] Cache invalidation on git commit (SHA change)
- [ ] Integration test: mock MCP server returns edges, graph is built, PageRank produces expected ranking

### F5: Conversation Personalization

**What:** Seed PageRank personalization with conversation context: edited files, git-diff working set, and mentioned identifiers.

**Acceptance criteria:**
- [ ] Chat/edited files set teleport weight ×10 in personalization vector
- [ ] Git-diff files (unstaged + staged) set teleport weight ×5
- [ ] Mentioned identifiers detected in conversation text boost edge weights ×10 for matching edges
- [ ] Personalization signals accessible from priompt RenderContext (conversation text, phase)
- [ ] Map ranking visibly changes when user mentions a file or symbol
- [ ] Test: synthetic conversation with file mentions produces expected rank ordering

## Non-goals

- **BM25 fallback layer** — deferred to a later iteration. Go-native `go/ast` is sufficient as the floor.
- **intersearch embedding pre-filtering** — optional enhancement, not core.
- **`malivnan/tree-sitter` pure-Go evaluation** — monitor maturity, don't depend on it yet.
- **Multi-agent repo map** — Skaffen is single-agent. No shared map state.
- **Real-time file watching** — mtime-based cache invalidation is sufficient. No fsnotify.

## Dependencies

- **Masaq priompt** — Element/ContentFunc/Render API. Already a dependency.
- **Intermap** — For F3/F4. Intermap is in the same monorepo. Must be published/updated before F4 can consume the new tool.
- **PriomptSession** — Already exists at `session/priompt_session.go` but not wired in `main.go`. F1 addresses this.

## Open Questions

1. **`go/packages` vs `go/ast`** — `go/packages` gives full type-checked resolution but adds x/tools dependency. Decide during F2 implementation. Default: stick with `go/ast` for now, upgrade later.
2. **Conversation text access in ContentFunc** — priompt's `RenderContext` has Phase, Model, TurnCount, Budget. Does it need a ConversationText field for F5's identifier extraction? May need a priompt API extension.
3. **Edge weight distribution** — Aider's Stage 4 (distribute file rank across outgoing edges for identifier-level ranking) adds complexity. Implement in F2 or defer to F5? Default: defer to F5.
