# Repomap Graph Model Research

Research on graph representation, PageRank variant, and personalization strategy for Skaffen's code reference graph.

## Current State

**Skaffen's repomap** (`os/Skaffen/internal/tui/repomap.go`, 146 lines) is a flat symbol lister: it walks Go files, parses with `go/ast`, and emits exported types and functions grouped by package directory. No graph, no ranking, no personalization. It caps at 100 files and 8000 chars. Called from `/map` command in `tui/commands.go:1000`.

**Intermap** (`interverse/intermap/python/intermap/`) has a full cross-file call graph (`cross_file_calls.py`) with edges as `(src_file, src_func, dst_file, dst_func)` tuples, plus reverse graph traversal (`analysis.py:build_reverse_graph`), impact analysis, dead code detection, and architecture layer inference. This is Python-only, uses tree-sitter, and runs as an MCP plugin sidecar. It has the edge data Skaffen needs but in the wrong language and wrong process.

## Aider's Approach: Analysis

Aider's `repomap.py` ([source](https://github.com/Aider-AI/aider/blob/main/aider/repomap.py)) implements a five-stage pipeline:

### Stage 1: Tag Extraction
Tree-sitter `.scm` query files extract "definition" and "reference" tags per file. Each tag is `(file, identifier, kind)`. This is equivalent to intermap's `build_function_index` + `resolve_calls` but uses tree-sitter queries instead of AST walking.

### Stage 2: Graph Construction
**Nodes are files, not identifiers.** Edges connect referencer files to definer files, labeled with the identifier:

```
G.add_edge(referencer_file, definer_file, weight=mul * sqrt(num_refs), ident=identifier)
```

This is a **file-level multigraph** — multiple edges between the same file pair, one per shared identifier. The edge weight encodes relevance heuristics:

| Condition | Multiplier |
|-----------|-----------|
| Identifier in mentioned_idents | x10 |
| Long snake/kebab/camel (>=8 chars) | x10 |
| Private (starts with `_`) | x0.1 |
| Defined in >5 files (common name) | x0.1 |
| Referencer in chat files | x50 |
| Reference count | x sqrt(N) |

### Stage 3: Personalized PageRank
NetworkX `pagerank(G, personalization=pers)` with file-level personalization:
- Chat files: boost of `100 / len(all_fnames)`
- Mentioned files: same boost
- Files whose path components match mentioned identifiers: same boost
- All other files: default `1 / N`

### Stage 4: Rank Distribution
After PageRank computes per-file scores, Aider distributes each file's rank across its outgoing edges proportionally to edge weight, accumulating per `(file, identifier)` pair. This converts file-level importance into identifier-level importance. ([Issue #2342](https://github.com/Aider-AI/aider/issues/2342) questioned whether this is redundant; it's not — it's the step that extracts identifier salience from file-level PageRank.)

### Stage 5: Binary Search Token Fitting
Binary search finds the maximum number of ranked tags fitting within `max_map_tokens`, accepting solutions within 15% of target.

### Key Insight: The Bipartite Structure is NOT Necessary

Aider uses a **file-to-file** graph, not a bipartite file-identifier graph. Identifiers live on edges, not as nodes. This is deliberate: PageRank operates on file importance, and the edge-weight distribution step recovers identifier-level ranking without doubling node count. The file-level graph is simpler, converges faster, and avoids the "identifier node has no meaningful outlinks" problem that a bipartite structure would create.

## Go Graph Library Evaluation

### Option 1: `alixaxel/pagerank` (Recommended)
- **Pure Go, zero CGO, zero dependencies** ([source](https://github.com/alixaxel/pagerank))
- Sparse adjacency: `map[uint32]map[uint32]float64`
- ~62 lines of code. Weighted edges supported.
- **Missing:** No personalization vector. Teleportation is uniform `(1-alpha)/N`.
- **Fix:** Fork or inline the 62 lines and replace the uniform teleport with a custom distribution. This is a 5-line change: replace `inverse := 1 / float64(len(self.nodes))` with a lookup into a personalization map, and adjust the leak redistribution similarly.
- API: `graph.Link(src, dst, weight)` then `graph.Rank(0.85, 1e-6, callback)`
- Node IDs are `uint32` — need a bidirectional `string <-> uint32` mapping for file paths.

### Option 2: `dcadenas/pagerank`
- Pure Go, no CGO. Uses inverted adjacency list (optimized for "pull" model).
- No personalization support.
- Slightly more code than alixaxel but same convergence model.
- Less actively maintained.

### Option 3: `gonum/graph/network.PageRankSparse`
- Pure Go (the graph/network package doesn't use BLAS/LAPACK).
- Requires `graph.Directed` interface — heavier abstraction than needed.
- **No personalization vector** in the API.
- gonum is a large dependency (~many packages) for one function.
- Would pull in gonum's graph interfaces, which conflict with Skaffen's zero-heavy-dependency principle.

### Option 4: `dominikbraun/graph`
- Generic graph library with BFS, DFS, topological sort.
- **No PageRank implementation** at all. Would still need hand-rolled iteration.
- Useful for graph structure but overkill as a PageRank container.

### Option 5: Hand-rolled (~80 lines)
- Inline a personalized PageRank with sparse adjacency.
- Full control over personalization, convergence, and memory layout.
- No external dependency. Testable with known graphs.

### Recommendation: Inline Option 5 (based on alixaxel's structure)

The alixaxel implementation is 62 lines. Adding personalization brings it to ~80 lines. This is small enough to own outright, avoids a dependency for a core algorithm, and gives full control over the personalization vector. Matches PHILOSOPHY.md "Composition Over Capability" — small, scoped, no unnecessary abstraction.

## Pure Go Personalized PageRank: Implementation Sketch

```go
package repomap

// Graph holds a sparse weighted directed graph for PageRank.
type Graph struct {
    edges map[uint32]map[uint32]float64 // src -> dst -> weight
    nodes map[uint32]struct{}
}

func NewGraph() *Graph {
    return &Graph{
        edges: make(map[uint32]map[uint32]float64),
        nodes: make(map[uint32]struct{}),
    }
}

func (g *Graph) Link(src, dst uint32, weight float64) {
    g.nodes[src] = struct{}{}
    g.nodes[dst] = struct{}{}
    if g.edges[src] == nil {
        g.edges[src] = make(map[uint32]float64)
    }
    g.edges[src][dst] += weight
}

// Rank computes personalized PageRank.
// personalize maps node -> teleport weight (will be normalized).
// If nil, uniform teleportation is used.
func (g *Graph) Rank(alpha float64, tol float64, personalize map[uint32]float64,
    callback func(node uint32, rank float64)) {

    n := len(g.nodes)
    if n == 0 {
        return
    }

    // Build node list and index
    nodeList := make([]uint32, 0, n)
    for id := range g.nodes {
        nodeList = append(nodeList, id)
    }

    // Normalize personalization vector
    teleport := make([]float64, n)
    idx := make(map[uint32]int, n)
    for i, id := range nodeList {
        idx[id] = i
    }
    if personalize != nil {
        var sum float64
        for _, id := range nodeList {
            teleport[idx[id]] = personalize[id]
            sum += personalize[id]
        }
        if sum > 0 {
            for i := range teleport {
                teleport[i] /= sum
            }
        } else {
            for i := range teleport {
                teleport[i] = 1.0 / float64(n)
            }
        }
    } else {
        for i := range teleport {
            teleport[i] = 1.0 / float64(n)
        }
    }

    // Precompute outbound weights
    outWeight := make([]float64, n)
    for src, dsts := range g.edges {
        for _, w := range dsts {
            outWeight[idx[src]] += w
        }
    }

    // Initialize ranks uniformly
    rank := make([]float64, n)
    for i := range rank {
        rank[i] = 1.0 / float64(n)
    }
    newRank := make([]float64, n)

    // Power iteration
    for iter := 0; iter < 100; iter++ {
        // Collect dangling node mass
        var danglingSum float64
        for i, id := range nodeList {
            if outWeight[i] == 0 {
                danglingSum += rank[i]
            }
            _ = id
        }

        // Compute new ranks
        for i := range newRank {
            // Teleport + dangling redistribution (personalized)
            newRank[i] = (1-alpha)*teleport[i] + alpha*danglingSum*teleport[i]
        }

        // Propagate through edges
        for src, dsts := range g.edges {
            si := idx[src]
            if outWeight[si] == 0 {
                continue
            }
            for dst, w := range dsts {
                di := idx[dst]
                newRank[di] += alpha * rank[si] * w / outWeight[si]
            }
        }

        // Check convergence (L1 norm)
        var diff float64
        for i := range rank {
            d := newRank[i] - rank[i]
            if d < 0 {
                d = -d
            }
            diff += d
        }

        rank, newRank = newRank, rank
        if diff < tol {
            break
        }
    }

    for i, id := range nodeList {
        callback(id, rank[i])
    }
}
```

**Key properties:**
- Zero dependencies, zero CGO
- Sparse adjacency via nested maps — O(E) memory
- Personalization vector replaces uniform teleport
- Dangling node mass redistributed via personalization (not uniform) — this is the correct formulation for personalized PageRank
- L1 convergence with 100-iteration cap
- ~90 lines including comments

## Convergence Performance Estimates

PageRank typically converges in 20-50 iterations on sparse graphs. Here are estimates for Skaffen's use case:

| Repo Size (files) | Estimated Edges | Iterations to tol=1e-6 | Wall Clock (Go, sparse maps) |
|---|---|---|---|
| 100 | ~500 | 15-25 | <1ms |
| 500 | ~3,000 | 25-40 | 1-3ms |
| 2,000 | ~15,000 | 35-50 | 5-15ms |
| 10,000 | ~80,000 | 40-60 | 30-80ms |

**Rationale:** Each iteration is O(E) — one pass over all edges. For a 2000-file repo with ~15K edges and 40 iterations, that's 600K map lookups. Go hash map lookups are ~50-100ns each, giving ~30-60ms. With pre-sorted adjacency slices instead of maps, this drops to ~5-15ms.

**At Skaffen's target scale (100-2000 files), this is negligible.** Even the worst case (10K files) is well under 100ms. The tag extraction step (tree-sitter or go/ast parsing) will dominate by 10-100x.

**Optimization path if needed:** Replace `map[uint32]map[uint32]float64` with sorted `[]Edge` slices and binary search. This gives cache-friendly iteration and drops per-iteration time by ~3-5x. Not worth doing until profiling shows PageRank itself (not tag extraction) is the bottleneck.

## HITS Authority Score vs PageRank

HITS computes two scores per node: hub (good outlinker) and authority (good inlink target). For code navigation, we care about authority — "which files are most referenced by the context?"

### Comparison

| Dimension | PageRank | HITS Authority |
|-----------|----------|---------------|
| Computation | Offline (query-independent) or personalized (query-time) | Query-dependent (must compute per query) |
| Personalization | Natural: teleport vector biases toward context files | Awkward: must weight the base set, no standard formulation |
| Convergence | Guaranteed (stochastic matrix) | Can oscillate on certain graph structures |
| Implementation | ~80 lines | ~60 lines (but needs base-set selection logic) |
| Quality for code nav | Good: identifies "important" files via reference density | Comparable for hub/authority separation, but code graphs don't have clear hub/authority structure |
| Caching | File-level graph cacheable; personalization is cheap re-run | Requires full recomputation per query since base set changes |

### Verdict: PageRank wins

Code dependency graphs are not web-like bipartite structures. They don't have a clear hub/authority dichotomy — most files both define and reference identifiers. HITS's core insight (separating hubs from authorities) doesn't add value here. PageRank with personalization gives equivalent or better retrieval quality with simpler implementation and better caching properties.

**Flag per decision lens:** HITS adds complexity (base-set selection, oscillation handling) without measurable retrieval improvement for code graphs. Skip it.

## Personalization Signals

### Signal 1: Chat/Edited Files (High Value)
Files the user has mentioned, opened, or edited in the current session. These are the strongest signal — the user is actively working here.

**Implementation:** Set teleport weight to `10.0` for these files, `1.0` for all others. The exact ratio matters less than the magnitude gap.

### Signal 2: Git-Diff Files (Medium Value)
Files changed since the base branch. These represent the working set — code that's been modified and likely needs cross-references.

**Implementation:** Set teleport weight to `5.0` for git-diff files not already in Signal 1.

### Signal 3: Mentioned Identifiers (Medium Value)
When the user mentions a function or type name in chat, boost files that define or reference that identifier.

**Implementation:** This is Aider's `mentioned_idents` approach. Apply edge weight multiplier (x10) rather than teleport boost — it's more targeted since it operates on specific edges, not whole files.

### Signal 4: Import Proximity (Low Value, High Complexity)
Files that are import-adjacent to chat files. Requires import graph resolution.

**Implementation:** Not worth the complexity initially. PageRank's random walk already captures this transitively — files frequently imported by chat files will rank higher naturally.

**Flag per decision lens:** Signal 4 adds import-resolution complexity for marginal improvement over what PageRank already captures. Defer until empirical evidence shows ranking gaps.

### Recommended Priority
Ship Signals 1+2 first (chat files + git diff). Add Signal 3 (mentioned identifiers via edge weights) in the second pass. Skip Signal 4 unless ranking quality is demonstrably poor.

## Recommended Graph Edge Semantics

### File-Level Edges (Match Aider)

Use **file-to-file edges labeled with identifiers**, not identifier-level nodes:

```
Edge: (referencer_file) --[ident, weight]--> (definer_file)
```

**Why file-level, not identifier-level:**
1. **Node count stays manageable.** A 2000-file repo might have 50K identifiers. File-level graph: 2K nodes. Identifier-level: 52K nodes. PageRank convergence time scales with node count.
2. **Personalization is per-file.** The signals we have (chat files, git diff, edited files) are file-level. Boosting a file node is natural. Boosting 200 identifier nodes in that file requires identifier enumeration.
3. **Edge-weight distribution recovers identifier ranking.** Aider's Stage 4 proves this works: after PageRank computes file importance, distribute each file's rank across its outgoing edges proportionally to weight, accumulating per `(file, ident)`. This gives identifier-level ranking without identifier-level nodes.
4. **Caching is simpler.** The file graph changes when files are added/removed/modified. Identifier-level graphs change on every edit to any function body — much higher invalidation rate.

### Edge Data Sources

For Go (Skaffen's primary language), the tag extraction can use `go/ast` (already in repomap.go) extended to extract:
- **Definitions:** exported types, functions, methods, constants, interfaces
- **References:** identifiers used in function bodies that resolve to definitions in other files

For multi-language support, delegate to intermap's tree-sitter sidecar via MCP. The Go-native path covers Skaffen's own codebase; intermap covers everything else.

### Hybrid Approach for Edge Construction

```
1. Fast path (Go-native):
   go/ast parse → extract defs + refs → resolve refs via package index → edges

2. Rich path (intermap MCP):
   intermap code_structure + impact_analysis → cross-file call edges

3. Merge: deduplicate edges, prefer intermap weights when both sources report
```

The fast path is synchronous and sub-second for <500 files. The rich path is async (MCP roundtrip) and provides higher-quality edges. Use fast path for initial render; upgrade with rich path when available.

## Cache Strategy Recommendation

### Approach: Mtime-Based Graph Invalidation + Cheap PageRank Recomputation

**Graph cache (expensive to build, slow to invalidate):**
- Cache the file-to-file edge graph keyed on `{root_dir, file_set_hash}`
- `file_set_hash` = sorted list of `(path, mtime)` for all source files
- On cache hit: reuse graph, skip tag extraction
- On cache miss: rebuild graph from scratch (tag extraction is the expensive part)
- Storage: in-memory `map[string]*CachedGraph` with LRU eviction (3-5 entries)

**PageRank recomputation (cheap, do every time):**
- DO NOT cache PageRank results. The personalization vector changes every query (different chat files, different git diff). Recomputing PageRank on a cached graph is <15ms for 2000 files — cheaper than cache management overhead.
- The binary search token fitting also runs fresh each time (different max_map_tokens, different context).

**Invalidation granularity:**
- File added/removed: invalidate entire graph (new node)
- File modified: invalidate edges for that file only (partial rebuild)
- Partial rebuild: re-extract tags for modified file, update its edges in the graph, keep all other edges. This avoids full re-parse for single-file edits.

### Why NOT full cache of ranked output:
The ranked output depends on `(graph state, personalization, max_tokens)`. Personalization changes every turn. Caching the final output would require keying on all three, and the hit rate would be near zero. Cache the graph (stable), recompute the rank (cheap).

### Implementation Sketch

```go
type GraphCache struct {
    mu     sync.Mutex
    graphs map[string]*cachedGraph // rootDir -> cached
}

type cachedGraph struct {
    graph     *Graph
    fileMtimes map[string]time.Time
    builtAt   time.Time
}

func (c *GraphCache) Get(root string, files []FileInfo) (*Graph, bool) {
    c.mu.Lock()
    defer c.mu.Unlock()
    cached, ok := c.graphs[root]
    if !ok {
        return nil, false
    }
    // Check if any file was modified
    for _, f := range files {
        if cached.fileMtimes[f.Path] != f.Mtime {
            // Partial invalidation: could rebuild just this file's edges
            return nil, false
        }
    }
    if len(files) != len(cached.fileMtimes) {
        return nil, false // files added or removed
    }
    return cached.graph, true
}
```

## Integration with Existing Codebase

### What to Reuse from intermap
- `analysis.py:build_reverse_graph` and `build_forward_graph` — the edge tuple format `(src_file, src_func, dst_file, dst_func)` is compatible. Skaffen's Go graph would use the same semantic: function-level edges aggregated into file-level weights.
- `cross_file_calls.py:build_project_call_graph` — the Python sidecar can provide higher-quality edges via MCP when available.

### What NOT to Port
- intermap's architecture analysis, dead code detection, circular dependency detection — these are separate tools, not repomap concerns. Keep them in intermap.
- tree-sitter language parsers — Skaffen is Go-first. Use `go/ast` for Go, delegate to intermap MCP for other languages.

### Migration Path
1. **Phase 1:** Replace current `generateRepoMap` with graph-ranked output. Keep `go/ast` for tag extraction. Add PageRank with personalization from chat files. No intermap dependency.
2. **Phase 2:** Add git-diff personalization signal. Add edge-weight distribution for identifier-level ranking. Binary search token fitting.
3. **Phase 3:** Optional intermap MCP integration for multi-language edge enrichment.

## Summary of Recommendations

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Graph edge semantics | File-level with identifier labels | Smaller graph, natural personalization, proven by Aider |
| PageRank library | Hand-rolled (~80 lines) | Zero dependency, full personalization control |
| HITS vs PageRank | PageRank | Code graphs lack hub/authority structure; HITS adds complexity without quality gain |
| Personalization signals | Chat files + git diff first | High signal, low implementation cost |
| Convergence concern | None at target scale | <15ms for 2000 files, 40 iterations |
| Cache strategy | Cache graph, recompute rank | Graph is expensive to build; rank is cheap with personalization |
| intermap integration | Phase 3, optional | Go-native path covers primary use case |
