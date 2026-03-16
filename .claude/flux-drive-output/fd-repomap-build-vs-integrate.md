# fd-repomap-build-vs-integrate: Build vs Integrate Decision

## Executive Summary

**Recommendation: Hybrid architecture.** Go owns the entire pipeline from graph construction onward (graph, rank, fit, format). Intermap supplies multi-language tag extraction via a new `reference_edges` MCP tool. Skaffen's existing `go/ast` repomap serves as the zero-dependency fallback. This preserves sovereignty for the critical-path prompt assembly while reusing 3200+ lines of battle-tested tree-sitter extraction without rebuilding it.

This is grounded in three PHILOSOPHY.md principles:
1. **"Adopt mature external tools as dependencies rather than rebuilding them"** (Composition Over Capability, External Tools) -- intermap's tree-sitter layer across 15+ languages is exactly the kind of thing that should be adopted, not reimplemented.
2. **"Graceful Degradation Everywhere"** (Skaffen PHILOSOPHY.md) -- every optional dependency degrades silently; intermap being unavailable must not break the repo map.
3. **"Sovereignty Over Convenience"** (Skaffen PHILOSOPHY.md) -- Skaffen owns its inference pipeline end-to-end; the prompt-assembly chain (graph -> rank -> fit -> format) cannot depend on an external process being alive.

---

## 1. Pipeline Stage Decision Matrix

The Aider-style repo map pipeline has five stages. Each is evaluated for where it should live.

| Stage | Description | Owner | Rationale | Fallback if owner unavailable |
|-------|-------------|-------|-----------|-------------------------------|
| **Parse** | Extract definition/reference tags from source files | **intermap MCP** (new `reference_edges` tool) | 3200 lines of tree-sitter across 15+ languages; rewriting this in Go would take weeks and violate the "adopt mature tools" principle. CGO_ENABLED=0 makes native Go tree-sitter impossible (see Section 2). | Skaffen `go/ast` extracts Go-only definitions (current `repomap.go`); for non-Go repos, fall back to regex-based identifier extraction (extend `extractors.py`'s BasicRegexExtractor pattern in Go). |
| **Graph** | Build identifier-reference bipartite graph | **Skaffen (Go)** | Pure data structure construction from edge list. No external dependency needed. ~50 lines of Go. Must be in-process for cache invalidation control. | Always available (pure Go). |
| **Rank** | Personalized PageRank over the graph | **Skaffen (Go)** | Power iteration is ~30 lines of Go with a sparse adjacency map. No CGO needed. Must be in-process because the personalization vector changes per conversation turn. | Always available (pure Go). |
| **Fit** | Binary-search token budget fitting | **Skaffen (Go)** | Token budget arithmetic is core to priompt. Must live in the same process as the tokenizer and budget state. | Always available (pure Go). |
| **Format** | Render ranked files + symbols into prompt text | **Skaffen (Go)** | Output is a priompt.Element. Must be in-process. | Always available (pure Go). |

**Key insight:** Only the Parse stage benefits from delegation. Everything downstream is lightweight Go computation that must be in-process for sovereignty, latency, and cache control reasons.

---

## 2. Go Tree-Sitter Binding Assessment: CGO_ENABLED=0 Is a Hard Blocker

### smacker/go-tree-sitter

The primary Go tree-sitter binding (`github.com/smacker/go-tree-sitter`) wraps the C tree-sitter library via CGO. It requires `CGO_ENABLED=1` and a C compiler at build time. This is incompatible with Skaffen's `CGO_ENABLED=0` constraint, which exists for:
- Single static binary distribution
- Cross-compilation simplicity
- No C toolchain requirement on build machines

### Pure-Go alternatives

| Option | Viability | Assessment |
|--------|-----------|------------|
| **go-tree-sitter (smacker)** | Blocked | Requires CGO. Non-negotiable constraint violation. |
| **WASM tree-sitter** (wasmer/wazero) | Theoretically possible | Load tree-sitter WASM grammars into a Go WASM runtime. Adds 10-20MB to binary, ~5-10ms startup per language, grammar maintenance burden. No production-grade Go implementation exists. Experimental. |
| **participle / PEG parsers** | Partial | Go parser generators can handle 1-2 languages with custom grammars. Not viable for 15+ languages. Massive grammar authoring effort. |
| **go/ast (stdlib)** | Go only | Already used in `repomap.go` (lines 100-145). Extracts exported types and functions. No cross-file references. No other languages. |
| **Regex-based tag extraction** | Degraded | Intermap's `BasicRegexExtractor` (extractors.py lines 72-100) shows the pattern: regex per language for function/class definitions. Gets ~70% of definitions with zero dependencies. No reference extraction. |
| **ctags binary** | External dep | Universal Ctags produces tags for 100+ languages. Could shell out to `ctags --output-format=json`. But this is another external binary dependency -- if we're accepting external deps, intermap via MCP is better (richer data, already integrated). |

**Verdict:** There is no viable path to pure-Go multi-language tree-sitter parsing. The CGO_ENABLED=0 constraint makes this a non-starter. The only question is which external parsing surface to delegate to.

---

## 3. Intermap Python Sidecar: Latency and Sovereignty Audit

### Startup Cost

From `internal/python/bridge.go` (lines 218-265):
- Sidecar spawns `python3 -u -m intermap --sidecar` on first use
- Ready signal handshake occurs before first request
- Estimated cold start: 500-1500ms (Python interpreter + tree-sitter grammar loading)
- Subsequent requests: ~5-50ms per file batch (sidecar persists, FileCache survives across calls)

### Crash Recovery

From `bridge.go` (lines 291-309):
- Crash tracking: 3 crashes in 10 seconds triggers fallback to single-shot mode
- Single-shot mode: per-call subprocess, ~200ms overhead per call
- This is robust production code -- not a concern

### MCP Path Latency Budget

The MCP path from Skaffen to intermap adds:
1. **Skaffen MCP client** (`internal/mcp/client.go`): JSON-RPC over stdio. ~1-2ms serialization.
2. **intermap Go server** receives request, delegates to Python bridge.
3. **Python sidecar** processes request. For a 500-file project: ~200-500ms for full graph build (includes file I/O + tree-sitter parsing).
4. **Response**: JSON back through stdio. ~1-2ms.

**Total estimated round-trip for Parse stage:** 200-500ms (warm sidecar), 700-2000ms (cold start).

### Does This Matter on the OODARC Critical Path?

The repo map is a **system prompt component** that changes when:
- The conversation mentions new files/symbols (personalization vector update)
- A git commit changes the working tree
- A new OODARC phase begins (PhaseBoost changes priority)

It does NOT need to be recomputed every turn. Caching the Parse output (edge list) by git HEAD SHA is sufficient -- the same cache key intermap already uses (`gitHeadSHA()` in tools.go lines 517-524).

**Critical path analysis:**
- Parse is called ~once per git commit, not per turn. 200-500ms amortized over 5-20 turns is 10-100ms per turn equivalent.
- Graph/Rank/Fit/Format are per-turn operations but are pure Go computation: estimated <5ms for a 500-file repo.
- The MCP latency is acceptable for a non-per-turn operation.

---

## 4. Graceful Degradation Design

### When intermap MCP is available (happy path)

```
intermap.reference_edges(project, language) -> edge list
    |
    v
Go: build bipartite graph -> personalized PageRank -> binary-search fit -> priompt.Element
```

### When intermap MCP is unavailable (degraded path)

```
Skaffen go/ast (Go files only) -> simple symbol list, no references
    |
    v
Go: file-level dedup -> priority by file proximity to conversation -> linear truncation -> priompt.Element
```

This mirrors the current behavior of `generateRepoMap()` in `repomap.go` -- a flat package/symbol listing truncated at 8000 chars. The degraded path is exactly what Skaffen ships today.

### Detection

Skaffen's MCP Manager (`internal/mcp/manager.go`, `LoadAll()` at line 50) already handles this: servers that fail to connect are skipped with a warning. The `handleCaller.CallTool()` method (line 114) returns `CallResult{IsError: true}` on failure. The repomap builder would check for this and fall back.

---

## 5. Intermap Tool Surface Gap Analysis

### What exists today

| Tool | Returns | Useful for PageRank? |
|------|---------|---------------------|
| `code_structure` | `{files: [{path, functions, classes, imports}]}` | **Partial.** Has definitions per file but not cross-file references. Missing the "which file references which symbol" data needed for graph edges. |
| `impact_analysis` | `{targets: {func_ref: {callers: [...]}}}` | **Partial.** Returns reverse call graph for a single function. Would need N calls (one per function) to build the full graph -- prohibitively expensive. |
| `change_impact` | Affected tests for changed files | Not directly useful for repo map. |
| `detect_patterns` | Architectural patterns | Not useful for tag graph. |
| `live_changes` | Git diff with symbols | Useful as personalization signal but not for graph construction. |

### Gap: No tool returns the full edge list

The data exists in Python. `build_project_call_graph()` (cross_file_calls.py line 2871) produces `ProjectCallGraph._edges` -- a set of `(src_file, src_func, dst_file, dst_func)` tuples. But no MCP tool exposes this raw edge list.

### Minimum new tool surface needed

**One new tool: `reference_edges`**

```json
{
  "name": "reference_edges",
  "description": "Extract all definition-reference edges across a project for graph construction. Returns (definer_file, tag_name, referencer_file) triples.",
  "inputs": {
    "project": "string (required) - project root path",
    "language": "string (optional, default auto) - language hint",
    "include_intra_file": "boolean (optional, default false) - include same-file references"
  },
  "output": {
    "edges": [
      {"def_file": "path/to/definer.go", "symbol": "FuncName", "ref_file": "path/to/referencer.go"},
      ...
    ],
    "files_scanned": 142,
    "language": "go",
    "git_sha": "abc123"
  }
}
```

This differs from `impact_analysis` in three critical ways:
1. Returns ALL edges at once (not per-target)
2. Returns edges as flat triples (not nested caller trees)
3. Includes the `git_sha` for cache keying by the consumer

**Implementation cost in intermap:** ~30-50 lines of Python. The data is already computed by `build_project_call_graph()`. The new tool just serializes `_edges` into the JSON format above. ~20 lines in `tools.go` for the Go MCP wrapper.

### Optional enhancement: `definition_tags`

For higher-quality repo map formatting, Skaffen also needs the symbol signatures (not just names). A second optional tool:

```json
{
  "name": "definition_tags",
  "inputs": {"project": "string", "language": "string"},
  "output": {
    "tags": [
      {"file": "path/to/file.go", "name": "FuncName", "kind": "function", "signature": "func FuncName(ctx context.Context) error", "line": 42},
      ...
    ]
  }
}
```

This is lower priority -- Skaffen can format with just file + symbol name initially, and add signatures later.

---

## 6. Sovereignty Risk Assessment

### Risk: Python sidecar dependency for core prompt assembly

| Factor | Assessment |
|--------|------------|
| **Process lifecycle** | Intermap's bridge.go handles crash recovery, auto-respawn, and fallback to single-shot mode. Production-grade. |
| **Version drift** | Intermap and Skaffen are in the same monorepo. They drift together. Low risk. |
| **Port conflicts** | N/A -- MCP uses stdio, not network ports. |
| **Python availability** | Requires `python3` on PATH with tree-sitter packages installed. This is the main sovereignty concern. |
| **Blast radius** | If intermap crashes or is unavailable, Skaffen degrades to `go/ast` map. The blast radius is "worse repo map quality," not "broken agent." |

### Verdict: Acceptable sovereignty risk

The key insight from Skaffen's PHILOSOPHY.md is that MCP tools are explicitly accepted as "slower than built-ins" (Tradeoffs We Accept, bullet 3). The tradeoff is "plugin compatibility with the entire Interverse ecosystem." The repo map is not different from any other MCP tool -- it adds latency but gains capability that cannot be replicated in pure Go.

The sovereignty principle is satisfied because:
1. Skaffen owns the entire pipeline from graph construction onward
2. The Parse stage is the only delegated step, and it has a concrete fallback
3. The fallback (current `go/ast` map) is what ships today -- no regression

### Irreversible dependency analysis

| Dependency | Reversible? | Notes |
|------------|-------------|-------|
| intermap `reference_edges` tool schema | Yes | Skaffen consumes JSON edges. Any tool producing the same schema would work. Not coupled to intermap's internals. |
| MCP protocol | Yes | Standard protocol. Could switch to any MCP server implementing the same tools. |
| Python/tree-sitter | Yes (via fallback) | The fallback path exists from day one. Removing intermap degrades quality, doesn't break functionality. |
| Graph/Rank Go code | N/A | In-process, no external dependency. |
| priompt integration | N/A | In-process, no external dependency. |

**No irreversible dependencies are created by this architecture.**

---

## 7. Comparison with Alternatives

### Alternative A: All-Go with ctags binary

Shell out to Universal Ctags for tag extraction instead of intermap.
- **Pro:** No Python dependency.
- **Con:** Another external binary. Ctags produces definitions but not references -- insufficient for PageRank graph construction. Would need supplementary regex-based reference scanning in Go.
- **Verdict:** Worse than intermap. Ctags gives less data and adds a different external dependency.

### Alternative B: All-intermap (delegate everything including PageRank)

Add a `ranked_repo_map` tool to intermap that does the full pipeline and returns formatted text.
- **Pro:** One MCP call, simplest integration.
- **Con:** Violates sovereignty -- personalization vector (conversation context) would need to be sent to intermap on every turn. Token budget and priompt state would need to cross the MCP boundary. Tight coupling. Can't cache the graph separately from the personalization. Slower (full recomputation per turn).
- **Verdict:** Rejected. The personalization and fitting must live in Go because they depend on per-turn conversation state and priompt budget.

### Alternative C: All-Go with WASM tree-sitter

Load tree-sitter WASM grammars into wazero.
- **Pro:** Pure Go binary. No external processes.
- **Con:** No production implementation exists. Grammar WASM files add 10-20MB per language. Startup cost per grammar. Maintenance burden for WASM grammar updates. Experimental.
- **Verdict:** Interesting long-term option but not viable today. Could replace intermap's Parse role in the future without changing the architecture -- the interface (edge list JSON) stays the same.

---

## 8. Implementation Sequence

1. **Phase 1 (Skaffen-side, no intermap changes):**
   - Move `repomap.go` from `tui/` to a new `internal/repomap/` package
   - Add graph construction, PageRank, and token fitting in pure Go
   - Wire output as a priompt.Element with ContentFunc
   - Use current `go/ast` extraction as the data source (Go-only, no references, flat ranking by file proximity)
   - This ships the infrastructure without any external dependency

2. **Phase 2 (intermap addition):**
   - Add `reference_edges` tool to intermap (~50 lines Python + ~20 lines Go)
   - Publish intermap update

3. **Phase 3 (Skaffen integration):**
   - Add MCP call to `reference_edges` in Skaffen's repomap package
   - Cache edge list by git SHA
   - Fall back to Phase 1 behavior if intermap unavailable
   - This is the hybrid architecture at full capability

4. **Phase 4 (optional, deferred):**
   - Add `definition_tags` tool for richer symbol signatures
   - Add conversation-aware personalization vector seeding
   - Investigate WASM tree-sitter as a future replacement for the Python sidecar

---

## 9. Decision Summary

| Question | Answer |
|----------|--------|
| Can Skaffen do multi-language tree-sitter parsing in pure Go? | **No.** CGO_ENABLED=0 blocks smacker/go-tree-sitter. No viable pure-Go alternative for 15+ languages. |
| Is intermap's MCP latency acceptable? | **Yes.** Parse is amortized (~once per git commit), not per-turn. 200-500ms is fine. |
| Does intermap already expose the data Skaffen needs? | **Almost.** The data exists in `build_project_call_graph()` but no tool returns the raw edge list. One new tool (`reference_edges`) fills the gap. |
| What if intermap is unavailable? | **Skaffen degrades to current behavior.** `go/ast` flat symbol listing, no cross-file references, no PageRank. Exactly what ships today. |
| Is the Python sidecar dependency a sovereignty violation? | **No.** Skaffen owns graph->rank->fit->format. Parse delegation via MCP is the same pattern as every other Interverse tool. Fallback exists. |
| Are there irreversible dependencies? | **No.** The edge list schema is a clean interface. Any producer works. Fallback exists from day one. |

**Final recommendation:** Hybrid. Skaffen owns the pipeline. Intermap feeds it.
