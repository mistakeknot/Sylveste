---
artifact_type: research-findings
reviewer: fd-repomap-tag-extraction-surface
target: interverse/intermap/python/intermap/cross_file_calls.py, os/Skaffen/internal/tui/repomap.go
date: 2026-03-16
---

# Tag Extraction Surface: Intermap Bridge for PageRank-Ready Edge Data

## Grounding

Read before proceeding: `interverse/intermap/python/intermap/cross_file_calls.py` (3400+ lines), `interverse/intermap/python/intermap/extractors.py`, `interverse/intermap/python/intermap/protocols.py`, `interverse/intermap/internal/python/bridge.go`, `interverse/intermap/internal/tools/tools.go`, `os/Skaffen/internal/tui/repomap.go`, `interverse/intermap/python/intermap/analyze.py`.

---

## 1. What cross_file_calls.py Extracts Today

### Definition Extraction (the "function index")

`build_function_index()` (line 1714) dispatches to per-language indexers. Each indexes definitions as `(module_name, symbol_name) -> relative_file_path`:

| Language | Indexer | Node Types for Definitions |
|----------|---------|---------------------------|
| Python | `_index_python_file` (L1761) | `ast.FunctionDef`, `ast.AsyncFunctionDef`, `ast.ClassDef` |
| TypeScript | `_index_typescript_file` (L1785) | `function_declaration`, `method_definition`, `class_declaration`, `lexical_declaration` (arrow functions) |
| Go | `_index_go_file` (L1851) | `function_declaration`, `method_declaration`, `type_declaration > type_spec` |
| Rust | `_index_rust_file` (L1920+) | `function_item`, `struct_item`, `enum_item`, `trait_item`, `impl_item > function_item` |
| Java | `_index_java_file` (L1753+) | `class_declaration`, `method_declaration`, `constructor_declaration` |
| C | `_index_c_file` (L1756+) | `function_definition`, `declaration` (for prototypes) |

**Key detail:** Each definition is indexed under both fully-qualified and simple module names, plus string-key variants (`module.name` or `module/name`). This produces 4 index entries per definition. The index is flat -- no line numbers stored.

### Reference Extraction (call sites)

Per-file call extraction functions (`_extract_*_file_calls`) walk tree-sitter ASTs and classify each call site:

| call_type | Meaning | Resolution |
|-----------|---------|------------|
| `intra` | Callee defined in same file | Resolved immediately to same-file edge |
| `direct` | Bare function call (`foo()`) | Resolved via import map to function index |
| `attr` | Qualified call (`pkg.Func()`, `obj.method()`) | Resolved via import alias to package imports |
| `ref` | Function passed as value (Python only) | Treated as intra-file edge |

### Edge Format

`ProjectCallGraph._edges` (line 143) stores 4-tuples:

```
(src_file: str, src_func: str, dst_file: str, dst_func: str)
```

All paths are relative to project root. This is already very close to PageRank-ready data. The existing `call_graph` command in analyze.py (line 72) returns:

```json
{
  "edges": [["src/main.py", "main", "src/utils.py", "helper"], ...],
  "edge_count": 42
}
```

**Assessment:** The 4-tuple format maps directly to PageRank input. For repo-map, we need `(definer_file, tag_name, referencer_file)` triples. These can be derived from the existing edges by collapsing: `(dst_file, dst_func, src_file)` -- the definition file, the tag name, and the file that references it.

---

## 2. Language Coverage Matrix

| Language | tree-sitter Parser | Import Parsing | Def Indexing | Call Extraction | Full Call Graph | Notes |
|----------|-------------------|----------------|--------------|-----------------|-----------------|-------|
| Python | stdlib `ast` | `parse_imports` (L358) | Yes | `_extract_file_calls` (L2188) | `_build_python_call_graph` (L2921) | Best coverage. Uses `CallVisitor` AST walker with ref tracking. |
| TypeScript | `tree_sitter_typescript` | `parse_ts_imports` (L404) | Yes | `_extract_ts_file_calls` (L2299) | `_build_typescript_call_graph` (L2995) | Handles named/default/namespace imports, arrow fns, `this.method()`. |
| Go | `tree_sitter_go` | `parse_go_imports` (L488) | Yes | `_extract_go_file_calls` (L2431) | `_build_go_call_graph` (L3103) | Handles receiver types, `selector_expression` for pkg.Func. Package resolution is path-based (no module graph). |
| Rust | `tree_sitter_rust` | `parse_rust_imports` (L552) | Yes | `_extract_rust_file_calls` (L2530) | `_build_rust_call_graph` (L3192) | Handles `use`/`mod`, `scoped_identifier`, `field_expression`. Resolves `crate::`/`self::`/`super::`. |
| Java | `tree_sitter_java` | `parse_java_imports` (L652) | Yes | `_extract_java_file_calls` (L2650) | `_build_java_call_graph` (L3315) | Handles `method_invocation`, `object_creation_expression`, static imports. |
| C | `tree_sitter_c` | `parse_c_imports` (L938) | Yes | `_extract_c_file_calls` (L2799) | `_build_c_call_graph` (L3382) | Handles `#include`, function calls. No header-to-source resolution. |
| Ruby | `tree_sitter_ruby` | `parse_ruby_imports` (L1084) | **No** | **No** | **No** | Import parsing only (`require`, `require_relative`). |
| PHP | `tree_sitter_php` | `parse_php_imports` (L1393) | **No** | **No** | **No** | Import parsing only (`use`, `require`, `include`). |
| Kotlin | `tree_sitter_kotlin` | `parse_kotlin_imports` (L728) | **No** | **No** | **No** | Import parsing only. |
| Swift | `tree_sitter_swift` | `parse_swift_imports` (L1532) | **No** | **No** | **No** | Import parsing only. |
| C# | `tree_sitter_c_sharp` | `parse_csharp_imports` (L1618) | **No** | **No** | **No** | Import parsing only (`using`). |
| Scala | `tree_sitter_scala` | `parse_scala_imports` (L823) | **No** | **No** | **No** | Import parsing only. |
| Lua | `tree_sitter_lua` | `parse_lua_imports` (L1174) | **No** | **No** | **No** | Import parsing only (`require`). |
| Elixir | `tree_sitter_elixir` | `parse_elixir_imports` (L1279) | **No** | **No** | **No** | Import parsing only (`import`, `alias`, `use`). |
| C++ | `tree_sitter_cpp` | **No** | **No** | **No** | **No** | Parser exists but no extraction code. |

**Summary:** 6 languages have full call graph support (Python, TS, Go, Rust, Java, C). 8 additional languages have import parsing but no definition indexing or call extraction. C++ has a parser factory but zero extraction code.

---

## 3. Bridge Serialization: Can It Return Structured Edge Lists?

**Yes, with zero bridge changes.**

The bridge (`bridge.go`, line 107) passes arbitrary `map[string]any` args and receives arbitrary `map[string]any` results. It is fully schema-agnostic -- the Go side does `json.Marshal`/`json.Unmarshal` on `map[string]any`. The sidecar protocol is newline-delimited JSON with `{id, command, project, args}` requests and `{id, result, error}` responses.

The existing `call_graph` command in `analyze.py` (line 72) already returns an edge list:

```python
return {
    "edges": [list(e) for e in graph.edges],  # list of [src_file, src_func, dst_file, dst_func]
    "edge_count": len(graph.edges),
}
```

**The problem is not bridge serialization.** The problem is that this command is not exposed as an MCP tool. It exists in the Python dispatcher but has no corresponding Go tool registration in `tools.go`. Adding one requires only a new function in `tools.go` following the exact pattern of `codeStructure()` (line 239).

---

## 4. Proposed `reference_edges` MCP Tool

### Rationale

The existing `call_graph` command returns full 4-tuples. For PageRank repo-map construction, the consumer (Skaffen) needs:

1. **Definition tags:** `(file, symbol_name, line_number, kind)` -- what is defined where
2. **Reference edges:** `(referencer_file, tag_name, definer_file)` -- who references what
3. **Language auto-detection** -- Skaffen should not need to know the project language

The existing `call_graph` command is close but lacks line numbers and kind information. Rather than modifying it, a new purpose-built command keeps the existing interface stable.

### Schema

**Command name:** `reference_edges`

**Request:**
```json
{
  "project": "/path/to/project",
  "language": "auto",
  "include_definitions": true,
  "max_files": 500
}
```

**Response:**
```json
{
  "definitions": [
    {
      "file": "internal/agent/agent.go",
      "name": "RunPhase",
      "line": 142,
      "kind": "function",
      "scope": "Agent"
    }
  ],
  "edges": [
    {
      "src_file": "internal/agent/decide.go",
      "src_symbol": "decidePhase",
      "dst_file": "internal/agent/agent.go",
      "dst_symbol": "RunPhase"
    }
  ],
  "files_scanned": 47,
  "language": "go",
  "edge_count": 312,
  "definition_count": 89
}
```

**MCP tool definition (Go side):**

```go
func referenceEdges(bridge *pybridge.Bridge) server.ServerTool {
    return server.ServerTool{
        Tool: mcp.NewTool("reference_edges",
            mcp.WithDescription("Extract definition tags and cross-file reference edges for repo-map PageRank construction."),
            mcp.WithString("project", mcp.Description("Project root path"), mcp.Required()),
            mcp.WithString("language", mcp.Description("Language (auto, python, go, typescript, rust, java, c)")),
            mcp.WithBoolean("include_definitions", mcp.Description("Include definition list with line numbers (default true)")),
            mcp.WithNumber("max_files", mcp.Description("Max files to scan (default 500)")),
        ),
        Handler: func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
            args := req.GetArguments()
            project, _ := args["project"].(string)
            if project == "" {
                return mcputil.ValidationError("project is required")
            }
            pyArgs := map[string]any{
                "language":            stringOr(args["language"], "auto"),
                "include_definitions": boolOr(args["include_definitions"], true),
                "max_files":           intOr(args["max_files"], 500),
            }
            result, err := bridge.Run(ctx, "reference_edges", project, pyArgs)
            if err != nil {
                return mcputil.WrapError(err)
            }
            return jsonResult(result)
        },
    }
}
```

### Python-side implementation sketch

The new `reference_edges` command in `analyze.py` would:

1. Auto-detect language from file extensions if `language == "auto"`
2. Call `build_function_index()` -- extend it to return line numbers and kinds
3. Call `build_project_call_graph()` for the detected language
4. Reshape the 4-tuple edges into the response schema
5. Include the definition list with line numbers if `include_definitions` is true

**Key change needed in `build_function_index`:** Currently the index maps `(module, name) -> file_path`. To support line numbers and kinds, extend the value to a dataclass or named tuple: `(file_path, line_number, kind)`. This is a ~50-line change across the 6 `_index_*_file` functions, each of which already has access to the line number from tree-sitter nodes but discards it.

### Adaptation Assessment

**Minimal changes needed. No new pipeline.**

The core `build_project_call_graph` and `build_function_index` functions already produce the exact data PageRank needs. The changes are:

1. **~50 lines:** Extend index value to include line number and kind (modify the 6 `_index_*_file` functions)
2. **~30 lines:** New `reference_edges` command in `analyze.py` that reshapes existing output
3. **~25 lines:** New Go tool in `tools.go` (following existing pattern exactly)
4. **~10 lines:** Auto-language detection (count file extensions in project)
5. **~5 lines:** Register new tool in `RegisterAll()`

Total: ~120 lines of changes, all additive, no refactoring.

---

## 5. Quality Gap: ctags vs tree-sitter

### For definition extraction

ctags (universal-ctags) produces `(tag_name, file, line, kind)` entries and is extremely fast. For *definition* extraction alone, ctags is competitive with tree-sitter. However:

- ctags does not extract *references* -- it only finds definitions
- ctags cannot scope a call site to its enclosing function
- ctags does not parse import statements

For PageRank repo-map, the critical signal is not "where is X defined" (ctags handles this) but "which file references X" (ctags cannot do this). tree-sitter's ability to walk into function bodies and identify `call_expression` nodes targeting specific identifiers is the key differentiator.

### For reference extraction

tree-sitter is strictly superior to ctags for the def/ref disambiguation that PageRank requires. The current intermap extractors walk into function bodies and classify call sites by type (`intra`, `direct`, `attr`, `ref`). This call-type classification enables accurate cross-file edge resolution through import analysis.

**Verdict:** ctags is useful as a fast fallback for *definitions only* when tree-sitter is unavailable, but cannot replace tree-sitter for reference extraction.

---

## 6. Go-Native Fallback Design

When intermap is unavailable (no Python, sidecar crash, plugin not loaded), Skaffen needs a Go-native fallback for repo-map generation.

### Current state: repomap.go

`os/Skaffen/internal/tui/repomap.go` (146 lines) uses `go/parser` to extract exported symbols from Go files only. It produces a text display listing packages and their exported types/functions. It does **not** extract references, cross-file edges, or line numbers.

### Proposed extension: go/ast reference pairs

Go's `go/ast` + `go/types` packages can provide full definition and reference information for Go code without any external dependencies.

**Phase 1 (minimal, ~150 lines):** Extend `extractGoSymbols()` to also extract identifiers used in function bodies, classify them as local vs imported, and emit `(referencer_file, tag_name)` pairs. This requires:

1. Parse with `parser.ParseComments` mode (already using mode 0)
2. Walk `ast.FuncDecl.Body` looking for `ast.SelectorExpr` (package-qualified calls) and `ast.CallExpr` with `ast.Ident` callees
3. Cross-reference with the package's import list (`ast.File.Imports`)
4. Build a per-file symbol table from `ast.File.Decls`

```go
type TagDef struct {
    File   string // relative path
    Name   string // symbol name
    Line   int    // definition line
    Kind   string // "func", "type", "method"
    Scope  string // receiver type for methods, empty otherwise
}

type RefEdge struct {
    SrcFile   string // file containing the reference
    SrcSymbol string // enclosing function making the reference
    DstName   string // name being referenced
    DstPkg    string // package qualifier (empty for intra-package)
}
```

**Phase 2 (full, ~300 lines):** Use `golang.org/x/tools/go/packages` to load full type information. This resolves cross-package references precisely by using the Go type checker. This is more accurate than Phase 1 but introduces a dependency on the `x/tools` module.

**Recommendation:** Phase 1 is sufficient for Skaffen's repo-map. The `go/ast` approach handles the most common case (Go code with standard import structure) without external dependencies, maintaining CGO_ENABLED=0. The intermap bridge handles the multi-language case when available.

### Non-Go languages without intermap

For non-Go languages when intermap is unavailable, fall back to ctags-style regex extraction (definitions only, no references). The existing `BasicRegexExtractor` in `interverse/intermap/python/intermap/extractors.py` (line 72) already has regex patterns for `.go`, `.ts`, `.tsx`, `.js`, `.rs`. Port these 5 regex patterns to Go (~40 lines) for a degraded-but-present fallback.

---

## 7. Signal-to-Noise Assessment

### High confidence (use directly for PageRank)

- **Python call graph:** stdlib `ast` parsing is deterministic and handles all modern Python syntax. The `CallVisitor` class (line 2127) correctly distinguishes direct calls, attribute calls, and function references. Import resolution is thorough.
- **Go call graph:** tree-sitter Go grammar is mature. The extractor handles `function_declaration`, `method_declaration`, `type_declaration`, and `selector_expression` call sites. Package import alias resolution works correctly.
- **TypeScript call graph:** tree-sitter TypeScript handles `import_statement` variants (named, default, namespace) and `call_expression` with `member_expression` chains.

### Medium confidence (usable with caveats)

- **Rust call graph:** Handles `crate::`/`self::`/`super::` module resolution. However, trait method dispatch and generic bounds are not resolved -- a call to `trait_method()` may not find the impl it dispatches to. `scoped_identifier` parsing handles `Type::method()` but not `<Type as Trait>::method()`.
- **Java call graph:** Method overloading and polymorphic dispatch are not resolved. A call to `process()` matches any `process` in the index by simple name, not by type signature.
- **C call graph:** Header-to-source resolution is absent. Cross-file calls through headers are tracked as edges to the header file, not the implementation file.

### Low confidence (definitions only, no references)

- Ruby, PHP, Kotlin, Swift, C#, Scala, Lua, Elixir -- import parsing exists but no definition indexing or call extraction. These languages contribute zero edges to PageRank.
- C++ -- parser factory exists but no extraction code at all.

### Recommendation for repo-map

Start with the 3 high-confidence languages (Python, Go, TypeScript). These cover the vast majority of Demarch's own codebase. Add Rust and Java as secondary. Do not rely on the other languages for edge quality; use their import data only for file-level dependency hints.

---

## 8. Summary of Recommendations

1. **Expose `reference_edges` as a new MCP tool** in intermap. ~120 lines of additive changes. No new pipeline needed -- reshape existing `build_project_call_graph` + extended `build_function_index` output.

2. **Extend `build_function_index` to return line numbers and kinds.** ~50 lines across 6 `_index_*_file` functions. The data is already available from tree-sitter nodes; it is just discarded today.

3. **Add auto-language detection** in the new command. Count file extensions, pick dominant language, or scan all detected languages and merge edges.

4. **Go-native fallback in Skaffen:** Extend `repomap.go` with `go/ast` reference pair extraction (~150 lines). This handles the Go-only case when intermap is unavailable. Port the 5 regex patterns from `BasicRegexExtractor` for degraded non-Go fallback (~40 lines).

5. **Do not invest in ctags integration.** tree-sitter's reference extraction is the differentiating capability. ctags adds no signal for the PageRank graph construction problem.

6. **Language priority for edge quality:** Python > Go > TypeScript >> Rust > Java > C >> everything else (definition-only).
