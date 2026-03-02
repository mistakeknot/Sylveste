---
name: tldr-swinton
description: "Token-efficient code reconnaissance for LLMs. Autonomous skills save 48-85% tokens via diff-context, semantic search, structural patterns, and symbol analysis. Includes MCP server for direct tool integration."
---
# Gemini Skill: tldr-swinton

You have activated the tldr-swinton capability.

## Base Instructions
# AGENTS.md - AI Agent Instructions for tldr-swinton

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


Token-efficient code analysis tool for LLMs. Fork of llm-tldr with fixes for TypeScript, Rust, and multi-language support.

**Version**: 0.7.14
**Quick start**: Run `tldrs quickstart` for a concise reference guide.

## Quick Reference

```bash
# Install (development)
uv pip install -e .
uv pip install -e ".[semantic-ollama]"  # FAISS backend: Ollama embeddings
uv pip install -e ".[semantic-colbert]" # ColBERT backend: best quality, ~1.7GB PyTorch
uv pip install -e ".[full]"            # Full stack (Ollama + tiktoken)

# Smoke check
tldrs extract src/tldr_swinton/modules/core/api.py
tldrs structure src/

# After code changes
find . -name "*.pyc" -delete && find . -name "__pycache__" -type d -exec rm -rf {} +
uv pip install -e .
```

Full workflow guide: `docs/agent-workflow.md`

## Architecture

### Source Layout

```
src/tldr_swinton/
├── cli.py                     # CLI entry point, argument parsing
├── manifest.py                # Machine-readable capability manifest
├── presets.py                 # Output presets (compact, minimal, multi-turn)
└── modules/
    ├── core/
    │   ├── api.py             # High-level API functions
    │   ├── ast_extractor.py   # Data structures (FunctionInfo, ModuleInfo), Python extraction
    │   ├── hybrid_extractor.py # Multi-language extraction via tree-sitter
    │   ├── mcp_server.py      # MCP server (24 tools, FastMCP)
    │   ├── daemon.py          # Background daemon (socket-based)
    │   ├── cfg_extractor.py   # Control flow graph extraction
    │   ├── dfg_extractor.py   # Data flow graph extraction
    │   ├── pdg_extractor.py   # Program dependency graph
    │   ├── cross_file_calls.py # Cross-file call graph
    │   ├── output_formats.py  # Format rendering (ultracompact, json, text, etc.)
    │   ├── context_delegation.py # Retrieval plan generation
    │   ├── contextpack_engine.py # ContextPack builder
    │   ├── coherence_verify.py # Cross-file consistency checks
    │   ├── change_impact.py   # Test impact analysis
    │   ├── distill_formatter.py # Compressed context for sub-agents
    │   ├── attention_pruning.py # Symbol access tracking
    │   ├── block_compress.py  # Two-stage compression (knapsack DP)
    │   ├── signature_extractor_pygments.py # Fallback signature extraction
    │   └── engines/
    │       ├── astgrep.py     # Structural code search via ast-grep
    │       ├── delta.py       # Delta-mode orchestration (session tracking, etag)
    │       └── difflens.py    # Git-aware diff context
    ├── semantic/
    │   ├── backend.py         # SearchBackend protocol, CodeUnit, get_backend() factory
    │   ├── faiss_backend.py   # FAISSBackend (Ollama/sentence-transformers + FAISS)
    │   ├── colbert_backend.py # ColBERTBackend (PyLate + PLAID indexing)
    │   ├── index.py           # Thin orchestrator: build_index(), search_index()
    │   ├── bm25_store.py      # BM25 keyword index for hybrid search (RRF fusion)
    │   ├── embeddings.py      # Backward-compat shim (re-exports from faiss_backend)
    │   ├── vector_store.py    # Backward-compat shim (aliases FAISSBackend)
    │   └── semantic.py        # Original 5-layer semantic search (legacy)
    ├── bench/                 # Benchmark harness
    ├── vhs/                   # VHS ref storage
    └── workbench/             # Debugging workbench
```

### Core Extraction Pipeline

```
CLI (cli.py) → API (api.py) → extract_file() → HybridExtractor.extract()
  → Language-specific: Python (native AST), TS/Rust/Go/etc (tree-sitter), fallback (Pygments)
  → ModuleInfo with FunctionInfo objects → .to_dict() for JSON
```

### Semantic Search Pipeline

```
tldrs index . → backend.get_backend("auto"|"faiss"|"colbert")
  ├── FAISSBackend: 768d single-vector (Ollama nomic-embed-text-v2-moe)
  └── ColBERTBackend: 48d per-token (PyLate LateOn-Code-edge, PLAID)

tldrs find "query" → Lexical fast-path (BM25 exact match) → Backend.search() → RRF fusion
```

`SearchBackend` protocol (`backend.py`): `build()`, `search()`, `load()`, `save()`, `info()`.

## MCP Server (`tldr-code`)

The MCP server is the primary agent interface. 24 tools organized by category.

**Cost ladder** (cheapest first):
1. `extract(file, compact=True)` ~200 tok -- file map (use instead of Read for overview)
2. `structure(project)` ~500 tok -- directory symbols (use instead of Glob + Reads)
3. `context(entry)` ~400 tok -- call graph around symbol (use instead of reading caller files)
4. `diff_context(project)` ~800 tok -- changed-code context (use instead of git diff + Read)
5. `impact(function)` ~300 tok -- reverse call graph (use before refactoring)
6. `semantic(query)` ~300 tok -- meaning-based search (use instead of Grep for concepts)

### Full Tool Catalog

| Category | Tool | Description |
|----------|------|-------------|
| **Navigation** | `tree` | File tree listing (paths only, no symbols) |
| | `structure` | All symbols across a directory |
| | `search` | Regex search (prefer built-in Grep) |
| | `extract` | Function/class signatures from a file |
| **Context** | `context` | Call graph from a symbol with presets |
| | `diff_context` | Git-aware diff context with symbol mapping |
| | `distill` | Compressed prescriptive context for sub-agent handoff |
| | `delegate` | Prioritized retrieval plan for complex tasks |
| **Flow Analysis** | `cfg` | Control flow graph (basic blocks, cyclomatic complexity) |
| | `dfg` | Data flow graph (variable def-use chains) |
| | `slice` | Program slice (lines affecting/affected by a given line) |
| **Codebase Analysis** | `impact` | Reverse call graph (find all callers) |
| | `dead` | Unreachable code detection (expensive) |
| | `arch` | Architectural layer detection (expensive) |
| | `calls` | Full cross-file call graph (expensive) |
| **Import Analysis** | `imports` | Parse imports from a source file |
| | `importers` | Find files importing a given module |
| **Semantic Search** | `semantic` | Meaning-based code search via embeddings |
| | `semantic_index` | Build/rebuild semantic index |
| | `semantic_info` | Index metadata (backend, model, count) |
| **Quality** | `diagnostics` | Type checker + linter (pyright + ruff) |
| | `change_impact` | Find tests affected by changed files |
| | `verify_coherence` | Cross-file consistency after multi-file edits |
| **Structural** | `structural_search` | AST pattern matching via ast-grep |
| **Admin** | `hotspots` | Most-accessed symbols across sessions |
| | `status` | Daemon uptime and cache statistics |

**Semantic index**: Run `semantic_index()` once before `semantic()`. Use `semantic_info()` to check status. Backends: `faiss` (lighter, Ollama) or `colbert` (better retrieval, heavier).

## Claude Code Plugin

### Commands

| Command | Description |
|---------|-------------|
| `/tldrs-find <query>` | Semantic code search |
| `/tldrs-diff` | Diff-focused context for recent changes |
| `/tldrs-context <symbol>` | Symbol-level context |
| `/tldrs-structural <pattern>` | Structural code search (ast-grep patterns) |
| `/tldrs-quickstart` | Show quick reference guide |
| `/tldrs-extract <file>` | Extract file structure |

### Skills (4 autonomous)

| Skill | Trigger |
|-------|---------|
| `tldrs-session-start` | Before reading code for bugs, features, refactoring, tests, reviews, migrations |
| `tldrs-map-codebase` | Understanding architecture, exploring unfamiliar projects, onboarding |
| `tldrs-interbench-sync` | Syncing interbench eval coverage after tldrs capability changes |
| `finding-duplicate-functions` | Auditing codebases for semantic duplication |

### Hooks

| Hook | Matcher | Action |
|------|---------|--------|
| `Setup` | (session start) | Checks tldrs install, semantic index, ast-grep; provides project summary |
| `PreToolUse` | Serena `replace_symbol_body` | Runs `tldrs impact` to show callers before edits |
| `PreToolUse` | Serena `rename_symbol` | Same caller analysis |
| `PostToolUse` | `Read` | Compact `tldrs extract` on large files (>300 lines, once per file per session) |

### Plugin File Layout

```
.claude-plugin/
├── plugin.json          # Manifest (version, MCP server, references)
├── commands/            # 6 slash commands
├── hooks/
│   ├── hooks.json       # Hook definitions
│   ├── setup.sh         # Setup hook
│   ├── pre-serena-edit.sh # Caller analysis before Serena edits
│   └── post-read-extract.sh # Auto-extract on large file reads
└── skills/              # 4 orchestration skills
    ├── tldrs-session-start/
    ├── tldrs-map-codebase/
    ├── tldrs-interbench-sync/
    └── finding-duplicate-functions/
```

## Codex Skill

Repo-scoped at `.codex/skills/tldrs-agent-workflow/`. Mirrors `docs/agent-workflow.md`.

## CLI Decision Tree

See `docs/agent-workflow.md` for the full workflow. Summary:

1. **Recent changes?** `tldrs diff-context --project . --preset compact`
2. **Symbol context?** `tldrs context <entry> --project . --preset compact`
3. **File/folder overview?** `tldrs structure src/` or `tldrs extract <file>`
4. **Semantic search?** `tldrs index .` then `tldrs find "query"`
5. **Structural patterns?** `tldrs structural 'def $FUNC($$$ARGS): return None' --lang python`
6. **Deep analysis?** `tldrs slice`, `tldrs cfg`, `tldrs dfg`
7. **Capability manifest?** `tldrs manifest --pretty`

## Critical Rules

### Import Convention

All internal imports MUST use relative imports:
```python
# CORRECT
from .hybrid_extractor import HybridExtractor
from .ast_extractor import FunctionInfo

# WRONG - imports from old llm-tldr package
from tldr.hybrid_extractor import HybridExtractor
```

### Language Field Required

When creating `FunctionInfo` for non-Python languages, ALWAYS set the `language` field:
```python
FunctionInfo(name=func_name, params=params, return_type=return_type,
             language="typescript")  # Controls signature() output format
```

The `language` field determines signature format:
- `"typescript"` -> `async function name(params): Type`
- `"rust"` -> `fn name(params) -> Type`
- `"python"` (default) -> `def name(params) -> Type`

### Function Name Cleaning

TypeScript/JavaScript function names must be cleaned of modifiers:
```python
for prefix in ("export ", "async ", "default "):
    if name.startswith(prefix):
        name = name[len(prefix):]
```

### Embeddings Must Be L2-Normalized (FAISS Backend)

FAISS `IndexFlatIP` expects normalized vectors for cosine similarity. Handled by `_l2_normalize()` in `faiss_backend.py`. ColBERT uses MaxSim scoring -- normalization not needed.

### Incremental Index Updates

Both backends support incremental updates (only new/changed files re-embedded).
- **FAISS**: reconstructs unchanged vectors via `faiss.reconstruct()`
- **ColBERT**: uses PLAID `add_documents()` for adds. Cannot delete -- full rebuild at >= 20% deletions. Hard rebuild after 50 incremental updates.

## Key Data Structures

**FunctionInfo** (`modules/core/ast_extractor.py`):
```python
@dataclass
class FunctionInfo:
    name: str; params: list[str]; return_type: str | None
    docstring: str | None; is_method: bool = False; is_async: bool = False
    decorators: list[str] = field(default_factory=list)
    line_number: int = 0; language: str = "python"
```

**ModuleInfo** (`modules/core/ast_extractor.py`): Container for file analysis results.

**CodeUnit** (`modules/semantic/backend.py`): Minimal metadata for search results (id, name, file, line, unit_type, signature, file_hash).

## Delta Context Mode

Delta mode tracks delivered symbols per session and skips re-sending unchanged code. Provides ~60% savings in multi-turn conversations **when code is unchanged**.

- Works best with `diff-context` (full code bodies). Less useful with `context` (already signatures-only).
- Usage: `--session-id <id>` or `--delta` flag. Auto-generate: `--session-id auto`.
- State stored in `.tldrs/state.sqlite3`. Sessions expire after 24h inactivity.

**Caveat**: Delta savings collapse to near-zero if code changes between calls. Most valuable for iterative Q&A, not active editing.

## Compression Modes

`diff-context --compress` supports:
- **`two-stage`**: Indent-aware block detection + knapsack DP. Saves 35-73% tokens.
- **`chunk-summary`**: LLM-ready summaries replacing code. Saves 85-95% but loses detail.

See `docs/dev-reference.md` for promotion gate criteria.

## Output Caps

`context`, `diff-context`, and `slice` support `--max-lines` and `--max-bytes` post-format truncation:
```bash
tldrs context main --project . --max-lines=20
tldrs diff-context --project . --max-bytes=4096
```
Truncated output gets a `[TRUNCATED: ...]` marker. JSON output remains valid with `"truncated": true`.

## Semantic Search Backends

| Backend | Model | Dimensions | Install | Quality |
|---------|-------|-----------|---------|---------|
| **FAISS** | `nomic-embed-text-v2-moe` (475M) | 768d single-vector | `[semantic-ollama]` | Good |
| **ColBERT** | `LateOn-Code-edge` (17M) | 48d per-token | `[semantic-colbert]` | Best |

```bash
tldrs index . --backend faiss    # or colbert, or auto
tldrs index . --rebuild           # Force full rebuild
tldrs index --info                # Check status
```

Both backends use `threading.RLock` with snapshot pattern for concurrent build/search.

## Operational Notes

### Embedding Model
- Current: `nomic-embed-text-v2-moe` (475M, 768d, MoE)
- **NOT** `nomic-embed-code` (7.1B, 3584d) -- different model
- Jina-code-0.5b evaluated but not adopted (not on Ollama)

### Do NOT Adopt
- Stack Graphs: archived Sept 2025
- LSP: conflicts with offline/static analysis approach
- pylate-rs for LateOn-Code-edge: projection head missing, dimension mismatch

### Gotchas
- Ollama naming: community models use `user/model` format. Always `ollama pull` to verify.
- ThreadPoolExecutor + local GPU Ollama: no speedup (GPU serializes internally).

## Related Projects

| Project | What | Path |
|---------|------|------|
| **interbench** | Eval/regression for tldrs outputs | `core/interbench` (in Demarch monorepo) |

**interbench sync**: When adding new tldrs formats or flags, 4 interbench files must stay in sync. Use the automated check:
```bash
tldrs manifest | python3 /home/mk/projects/Demarch/core/interbench/scripts/check_tldrs_sync.py
```
Or use the `/tldrs-interbench-sync` skill for guided remediation.

## tldr-bench Datasets

Benchmark datasets live in the `tldr-bench/data` submodule (`github.com/mistakeknot/tldr-bench-datasets`).
```bash
git submodule update --init --recursive
cd tldr-bench/data && git lfs install && git lfs pull && cd -
```
Do not add large dataset files directly -- update the datasets repo and bump the submodule.

## Dev Reference

Debugging, testing, version history, and contributor procedures are in `docs/dev-reference.md`.


