# fd-repomap-alternatives: Non-Aider Approaches to Conversation-Aware Code Context Retrieval

## Executive Summary

Aider's tree-sitter + PageRank approach remains the strongest primary strategy for Skaffen's repomap, but the research reveals that the best production systems use **layered retrieval** -- not a single technique. The recommended architecture is: Aider-style graph as the primary ranker, with BM25 as a fast no-graph fallback, git-signal heuristics as a personalization seed, and intersearch embedding_query as an optional reranking layer. Each layer degrades independently to the current go/ast naive map.

---

## 1. Competitive Landscape Survey

### Cursor
- **Architecture:** Hybrid semantic-lexical indexing. Uses Turbopuffer (vector DB optimized for high-dimensional similarity search) to index code chunk embeddings. Local context gathering, cloud inference.
- **Key innovation (2026):** "Dynamic context discovery" -- agent dynamically retrieves context per-turn instead of stuffing static context upfront. A/B testing showed 46.9% token reduction in MCP-tool runs.
- **Retrieval path:** Open file + cursor position + imports -> @codebase triggers semantic search over project vector index -> .cursorrules system prompt wrapping.
- **Takeaway:** Embedding-based retrieval works at scale, but Cursor invests heavily in proprietary infrastructure (Turbopuffer). Not reproducible without similar investment.
- Sources: [InfoQ - Dynamic Context Discovery](https://www.infoq.com/news/2026/01/cursor-dynamic-context-discovery/), [BitPeak - How Cursor Works](https://bitpeak.com/how-cursor-works-deep-dive-into-vibe-coding/)

### GitHub Copilot
- **Architecture:** Remote embedding index (proprietary transformer tuned for code, similar to text-embedding-ada-002) + local hybrid fallback for uncommitted changes. Uses GitHub's non-neural code search (ripgrep-class) + LSP (IntelliSense) for symbol resolution + semantic embeddings.
- **Key insight:** Hybrid approach combining exact lexical search with semantic similarity, plus LSP type hierarchies for cross-file references.
- **Takeaway:** LSP integration for type resolution is a real differentiator, but requires a running language server -- heavy for a zero-infrastructure agent.
- Sources: [VS Code Docs - Workspace Context](https://code.visualstudio.com/docs/copilot/reference/workspace-context), [GitHub Docs - Indexing Repos](https://docs.github.com/copilot/concepts/indexing-repositories-for-copilot-chat)

### Continue.dev
- **Architecture:** Embedding-based codebase indexing (sentence-transformers) + tree-sitter AST parsing + ripgrep text search. ~50 results from vector DB -> reranker API -> top 10. Supports MCP context providers for custom RAG.
- **Key detail:** Uses a "repository map" during codebase retrieval for Claude/Llama/Gemini/GPT-4o families -- structurally similar to Aider's approach.
- **Takeaway:** Confirms the pattern: embeddings for recall, structural map for orientation, reranker for precision.
- Sources: [Continue Docs - Context Providers](https://docs.continue.dev/customize/custom-providers), [Continue Docs - Codebase Awareness](https://docs.continue.dev/guides/codebase-documentation-awareness)

### Cline
- **Architecture:** Three-tier retrieval without any embedding index: (1) ripgrep lexical search, (2) fzf fuzzy matching, (3) Tree-sitter AST parsing. Intelligence emerges from LLM-driven orchestration, not pre-computed vectors.
- **Key insight:** Achieves 17.5% context utilization (comparable to embedding-based systems) with zero indexing infrastructure. The LLM itself acts as the reranker.
- **Takeaway:** Validates the "no-index" approach. For Skaffen's zero-infrastructure philosophy, this is the strongest existence proof that tool-based exploration can match embedding-based retrieval.
- Sources: [Cline Discussion #4275](https://github.com/cline/cline/discussions/4275), [Preprints.org - Code Retrieval Study](https://www.preprints.org/manuscript/202510.0924)

### Probe (probelabs)
- **Architecture:** Rust-based. Combines ripgrep speed with tree-sitter AST parsing. BM25/TF-IDF/hybrid ranking. Zero indexing required. Query language with AND/OR/+required/-excluded.
- **Key insight:** AST-aware structural search without embeddings or graph construction. When an LLM is the consumer, the LLM translates intent into boolean queries and Probe returns complete AST blocks in milliseconds.
- **Takeaway:** Demonstrates that BM25 over AST-extracted symbols is a viable middle ground between naive grep and full graph analysis.
- Sources: [Probe GitHub](https://github.com/probelabs/probe), [Probe Features](http://probeai.dev/features)

### LocAgent (ACL 2025)
- **Architecture:** Parses codebases into directed heterogeneous graphs (files, classes, functions as nodes; imports, invocations, inheritance as edges). LLM agents traverse the graph with SearchEntity/TraverseGraph/RetrieveEntity tools.
- **Performance:** 92.7% file-level localization accuracy, 12% improvement in issue resolution. Fine-tuned 32B model matches SOTA at 86% cost reduction.
- **Takeaway:** Graph-guided exploration is the academic SOTA for code localization, but requires graph construction infrastructure. The graph structure is very similar to what Aider builds (file nodes, reference edges), validating the approach.
- Sources: [LocAgent Paper](https://arxiv.org/abs/2503.09089), [LocAgent GitHub](https://github.com/gersteinlab/LocAgent)

---

## 2. Alternative Approaches Evaluated

### 2A. LSP as Tag Source

**Question:** Can Skaffen query gopls for symbol defs/refs instead of parsing go/ast directly?

**Findings:**
- gopls provides `textDocument/definition`, `textDocument/references`, and `workspace/symbol` LSP methods that return structured location data.
- `golang.org/x/tools/go/packages` provides programmatic access to full type-checked ASTs, call graphs, and SSA form -- without running an LSP server. This is pure Go, CGO_ENABLED=0 compatible.
- gopls-mcp exists as a Claude plugin, suggesting the MCP-over-LSP path is well-trodden.

**Verdict:** For Go-only repos, `go/packages` is strictly superior to both go/ast (richer type info) and LSP (no server process). For multi-language support, LSP requires per-language server processes -- violates zero-infrastructure. Tree-sitter (via wazero CGO-free bindings) is the multi-language answer.

**Recommendation:** Use `go/packages` for Go (upgrade from go/ast), tree-sitter via `malivvan/tree-sitter` (wazero, CGO_ENABLED=0) for other languages. Do NOT depend on LSP servers.

### 2B. Embedding Retrieval (intersearch)

**Question:** Can intersearch's embedding_query replace PageRank for ranking file relevance?

**Findings:**
- intersearch uses nomic-embed-text-v1.5 (768d) with per-project SQLite vector storage. Query is brute-force cosine similarity over all indexed files -- O(n) scan per query.
- Embeds full file content, not symbol-level chunks. Returns file-level results, not symbol-level.
- Requires Python runtime (sentence-transformers) and model download (~500MB). Cold start: model loading takes seconds.
- Research benchmarks show: for bug localization (NL->PL), embeddings significantly outperform BM25. For code completion (PL->PL), BM25 outperforms embeddings. Hybrid BM25+embedding consistently beats either alone.

**Critical gap:** intersearch indexes file content, not symbol definitions. Aider's PageRank ranks *symbols within files*, not files. To replace PageRank, you'd need symbol-level embedding chunks, which intersearch doesn't support today.

**Verdict:** intersearch embedding_query is a viable **file-level pre-filter** (narrow from 1000 files to 50 candidates before graph analysis), but NOT a replacement for symbol-level ranking. The Python dependency and cold start also make it unsuitable as the primary path in a zero-infrastructure Go binary.

**Recommendation:** Use as optional Layer 3 (reranking/pre-filtering) when intersearch MCP server is available. Never depend on it for core functionality.

### 2C. Git-Signal Heuristics

**Question:** Can recently modified files and co-changed files provide useful context without any analysis infrastructure?

**Findings:**
- `git log --name-only` gives recency signal. `git log --follow` gives file rename tracking.
- Co-change analysis: files that are frequently modified together in the same commit are likely architecturally related. This is a well-known heuristic in software evolution research.
- CASS `context <path>` provides session-level co-edit history across 15 agent providers (though the index needs rebuilding).

**Strengths:**
- Zero infrastructure: git is always available.
- Conversation-aware: recently touched files in the current session are the strongest relevance signal.
- Complements structural analysis: git signals capture *temporal* coupling that static analysis misses.

**Weaknesses:**
- New repos or first-time contributors have no history.
- Recency bias: doesn't capture stable architectural dependencies.

**Verdict:** Excellent as a **personalization seed** for PageRank. Aider already supports this: PageRank's `personalization` parameter biases the walk toward seed files. Git-modified files and conversation-mentioned files are ideal seeds.

**Recommendation:** Use as Layer 1 seed data. Feed recently-modified files + conversation-referenced files as PageRank personalization weights.

### 2D. No-Graph Baseline: BM25/TF-IDF over Symbol Names

**Question:** What quality ceiling does BM25 over symbol names achieve vs PageRank?

**Findings:**
- Multiple pure Go BM25 libraries exist: `crawlab-team/bm25` (port of rank_bm25, parallel/batched), `bm25s-go` (sparse pre-computed scores), `go-nlp/bm25`.
- BM25 over symbol names gives keyword-matching relevance without graph construction.
- Research shows BM25 significantly outperforms embeddings for code-to-code retrieval (PL->PL). For natural-language-to-code (NL->PL), embeddings win.
- Probe (Rust) demonstrates BM25/TF-IDF over AST-extracted blocks as a production-viable approach with millisecond latency.

**Quality ceiling analysis:**
- BM25 finds symbols that *lexically match* the query -- good for "find all uses of FooBar".
- PageRank finds symbols that are *structurally important* to the query context -- good for "what do I need to understand to work on package X?"
- BM25 misses transitive dependencies (A calls B calls C; searching for A won't surface C).
- PageRank captures transitive importance through random walk propagation.

**Verdict:** BM25 is a strong **fallback** when graph construction fails or is too slow, but has a lower quality ceiling than PageRank for architectural orientation. The quality gap is most pronounced on large, deeply-nested codebases.

**Recommendation:** Use as Layer 2 fallback. BM25 over extracted symbol names, with the same tag extraction infrastructure as the graph approach. If graph construction succeeds, BM25 results can boost graph results via score fusion.

### 2E. CASS Session Intelligence

**Question:** Can CASS provide useful context for repomap personalization?

**Findings:**
- `cass context <path>` finds sessions related to a file path.
- `cass search "query"` does hybrid search across all agent session history.
- Currently requires index rebuild (`cass index --full`), but when available provides cross-agent file relevance data.

**Verdict:** CASS is a **long-term personalization signal**, not a retrieval mechanism. "Files that agents frequently work on together" is a co-change signal similar to git but richer (captures reasoning, not just diffs). Useful as a secondary seed for PageRank personalization, behind git signals.

**Recommendation:** Optional Layer 1 supplement. Query `cass context <current_file>` to boost related files in PageRank personalization. Degrade silently when CASS index is unavailable.

---

## 3. Tree-Sitter in Pure Go (CGO_ENABLED=0)

Skaffen requires CGO_ENABLED=0. Three options exist for multi-language AST parsing:

| Approach | CGO? | Performance | Maturity |
|----------|------|-------------|----------|
| `go/ast` (current) | No | Native | Stable, Go-only |
| `go/packages` + type checker | No | Native | Stable, Go-only, richer |
| `smacker/go-tree-sitter` | **Yes (CGO)** | Native C speed | Mature, 30+ languages |
| `malivvan/tree-sitter` (wazero) | **No** | ~1.5x overhead vs C | Pre-release, 30+ languages |
| `tree-sitter/go-tree-sitter` (official) | **Yes (CGO)** | Native C speed | Official, newest |

**Recommendation:** Start with `go/packages` for Go (strictly better than go/ast, zero new deps). Add `malivvan/tree-sitter` (wazero) when multi-language support is needed. The 1.5x Wasm overhead is negligible for tag extraction (I/O bound, not compute bound). Monitor for maturity -- it's pre-release.

---

## 4. Ranked Shortlist

### Rank 1: Aider-Style Graph (Primary Strategy)
- **Quality:** Highest. Structural importance via PageRank captures transitive dependencies.
- **Complexity:** Medium. Requires tag extraction + graph construction + PageRank. All implementable in pure Go.
- **Latency:** ~100-500ms for medium repos (cached tags, incremental graph rebuild).
- **Relation to current baseline:** Replaces it. Current go/ast map is the degraded fallback.
- **Go implementation path:** `go/packages` for Go tags, `crawlab-team/bm25` for tokenization utils, custom PageRank (the algorithm is ~50 lines), `malivvan/tree-sitter` for non-Go languages later.

### Rank 2: BM25 over Symbol Names (Fast Fallback)
- **Quality:** Medium. Lexical matching misses transitive dependencies but finds direct matches fast.
- **Complexity:** Low. Reuses tag extraction from Rank 1. BM25 scoring is a pure function.
- **Latency:** ~10-50ms. No graph construction needed.
- **Relation to graph:** Layers underneath. Fires when graph construction fails, times out, or repo is too large.
- **Go implementation path:** `crawlab-team/bm25` or `bm25s-go`. Both pure Go, zero CGO.

### Rank 3: Git-Signal Personalization (Enhancement Layer)
- **Quality:** High for conversation-relevance, low for cold-start architectural discovery.
- **Complexity:** Very low. Shell out to `git log` or use go-git.
- **Latency:** ~50-100ms for git log parsing.
- **Relation to graph:** Layers on top. Provides personalization weights to PageRank, biasing results toward recently-relevant files. Also seeds BM25 query expansion.

---

## 5. Verdict on intersearch embedding_query

**Not viable as a primary alternative.** Three blocking issues:

1. **Granularity mismatch:** intersearch indexes whole files, not symbols. Repomap needs symbol-level ranking.
2. **Infrastructure dependency:** Requires Python runtime + sentence-transformers + model download. Violates Skaffen's CGO_ENABLED=0 and zero-infrastructure constraints.
3. **Cold start:** Model loading takes seconds. Repomap needs sub-second response.

**Viable as an optional enhancement:** If the intersearch MCP server happens to be running (common in Interverse-equipped environments), file-level semantic search can pre-filter candidates before graph analysis. This is Layer 3 -- nice to have, never required.

---

## 6. Recommended Architecture: Layered Retrieval Stack

```
Layer 0 (always available):  go/ast naive map (current baseline)
         |
         v  [upgrade path]
Layer 1 (seed):              git recency + conversation files + optional CASS context
         |
         v  [personalization weights]
Layer 2 (primary):           Aider-style tree-sitter tags -> reference graph -> PageRank
         |                   Falls back to BM25 over tags if graph too large / timeout
         v  [token-fitted output]
Layer 3 (optional):          intersearch embedding_query for file pre-filtering
                             (only when MCP server available)
```

**Degradation path:** Layer 2 fails -> BM25 fallback -> Layer 0 naive map. Each layer degrades independently. The system produces useful output even with only Layer 0.

**Implementation order:**
1. Upgrade go/ast to `go/packages` for richer Go symbol extraction (immediate win, no new deps beyond x/tools).
2. Implement tag cache + reference graph + PageRank (core Aider port).
3. Add BM25 fallback using `crawlab-team/bm25`.
4. Add git-signal personalization.
5. Add tree-sitter via wazero for non-Go languages (when `malivvan/tree-sitter` stabilizes).
6. Wire intersearch embedding_query as optional Layer 3 via MCP.

---

## 7. Key Research Signals

- **"Some prominent agent development teams have abandoned RAG in favor of more direct, exploratory methods"** -- the Cline/Probe approach of tool-based exploration without pre-built indices is a credible alternative. But Skaffen already has the repomap concept; the question is making it better, not whether to have one.
- **Hybrid BM25+embedding consistently beats either alone** across CodeRAG-Bench benchmarks. This validates the layered approach.
- **LocAgent (ACL 2025) confirms graph-based traversal is SOTA** for code localization at 92.7% accuracy. The graph structure matches Aider's approach closely.
- **Cline achieves 17.5% context utilization with zero infrastructure** -- comparable to Cursor's embedding-heavy approach. The LLM itself is a powerful reranker when given structural primitives.

## Sources

- [InfoQ - Cursor Dynamic Context Discovery](https://www.infoq.com/news/2026/01/cursor-dynamic-context-discovery/)
- [VS Code Docs - Copilot Workspace Context](https://code.visualstudio.com/docs/copilot/reference/workspace-context)
- [Continue.dev - Context Providers](https://docs.continue.dev/customize/custom-providers)
- [Continue.dev - Codebase Awareness](https://docs.continue.dev/guides/codebase-documentation-awareness)
- [Cline Code Retrieval Discussion](https://github.com/cline/cline/discussions/4275)
- [Probe - Semantic Code Search](https://github.com/probelabs/probe)
- [LocAgent - ACL 2025](https://arxiv.org/abs/2503.09089)
- [Aider Repomap Blog Post](https://aider.chat/2023/10/22/repomap.html)
- [Aider DeepWiki - Repository Mapping System](https://deepwiki.com/Aider-AI/aider/4.1-repository-mapping)
- [RepoMapper MCP Server](https://github.com/pdavis68/RepoMapper)
- [malivvan/tree-sitter (wazero, CGO-free)](https://github.com/malivvan/tree-sitter)
- [crawlab-team/bm25 (Go)](https://github.com/crawlab-team/bm25)
- [CodeRAG-Bench](https://aclanthology.org/2025.findings-naacl.176.pdf)
- [Exploratory Study of Code Retrieval in Coding Agents](https://www.preprints.org/manuscript/202510.0924)
- [go/packages](https://pkg.go.dev/golang.org/x/tools/go/packages)
- [BitPeak - How Cursor Works](https://bitpeak.com/how-cursor-works-deep-dive-into-vibe-coding/)
- [GitHub Docs - Indexing Repos for Copilot](https://docs.github.com/copilot/concepts/indexing-repositories-for-copilot-chat)
- [wazero vs CGO 2026](https://wasmruntime.com/en/blog/wazero-vs-cgo-2026)
