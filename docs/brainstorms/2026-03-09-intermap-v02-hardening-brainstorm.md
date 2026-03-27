---
artifact_type: brainstorm
bead: iv-w7bh
stage: discover
---

# Intermap v0.2: Hardening

**Bead:** iv-w7bh
**Date:** 2026-03-09
**Status:** Brainstorming

## What We're Building

Harden intermap's existing 9-tool suite for reliability and performance before expanding language coverage or adding new capabilities. v0.1.4 is functionally complete but has three known gaps: uncached expensive tools, imprecise body-edit detection in live_changes, and no performance baselines.

## Current State

Intermap v0.1.4: 9 MCP tools, Go host + Python sidecar, 6 Go test files + 9 Python test files (67 tests). All tools work. The Go-level cache (`internal/cache/cache.go`) is generic LRU+mtime+TTL but only `project_registry` uses it. Python-side tools run full analysis per call.

### Performance Observations

- `detect_patterns` scans all Go/Python files in a project, parsing ASTs each time. On a large project (intermap itself: 18 Python files + 6 Go packages), this is noticeable but not slow. On the Sylveste monorepo root, it could be expensive.
- `cross_project_deps` walks all projects scanning go.mod, pyproject.toml, plugin.json. Results change only when those files change — perfect caching candidate.
- `live_changes` body-range detection works for Python (AST-based line ranges) but has a documented gap: when only the body of a function changes and the header line is unchanged, the hunk-to-symbol mapping can miss the edit if the hunk starts mid-body.
- Python sidecar's in-process `FileCache` helps with repeated file reads but doesn't help when the MCP server restarts between sessions.

## Key Decisions

### D1: Go-level caching for detect_patterns and cross_project_deps

**What:** Add `cache.Cache` instances in `tools.go` for these two tools, keyed by project path + mtime hash of the scanned files.

**Why:** These tools have stable outputs that only change when source files change. The generic cache is already written and proven with `project_registry`. Adding caching is mechanical.

**Cache key strategy:**
- `detect_patterns`: key = project path, mtime hash = max mtime of *.go + *.py files (or git HEAD SHA as proxy)
- `cross_project_deps`: key = root path, mtime hash = combined hash of go.mod + pyproject.toml + plugin.json mtimes across all projects

**TTL:** 5 minutes (same as project_registry). The sidecar's in-process FileCache handles finer-grained invalidation for repeated calls within the TTL window.

### D2: Symbol body-range detection fix in live_changes

**What:** When a git diff hunk falls entirely within a function/method body (no header line changed), the current hunk-to-symbol mapping can miss it. Fix by using AST span ranges (start_line, end_line) for overlap detection instead of relying on hunk context lines.

**Current approach:** `_extract_python_symbol_ranges()` in `live_changes.py` already extracts AST spans via `ast.parse()`. The gap is in `_range_contains_line()` — it checks if a changed line falls within a symbol's range, but the baseline symbol ranges come from the HEAD version while line numbers come from the working tree. When a hunk adds/removes lines, the offsets drift.

**Fix approach:** For each changed file, extract symbol ranges from BOTH the baseline (HEAD) and working tree versions. Map hunks to baseline symbols using baseline line numbers, and to working tree symbols using new line numbers. Union the results. This is already partially implemented (`_extract_python_symbol_ranges_from_baseline()` exists) — the gap is in the union step.

### D3: Performance baselines

**What:** Add benchmark tests that measure wall-clock time for each tool against a representative project. Track as test assertions with generous bounds (e.g., `detect_patterns` on a 20-file project should complete in < 5s).

**Why:** Without baselines, performance regressions are invisible. Benchmarks serve as both documentation ("this tool takes ~Xms") and regression tests.

**Approach:**
- Go benchmarks in `tools_test.go` for the full round-trip (Go → Python sidecar → response)
- Python benchmarks in `test_live_changes_perf.py` (already exists, needs expansion)
- Measure cold-start (first call, no cache) and warm (cached) separately

### D4: Structured error types from Python

**What:** Replace ad-hoc error strings from the Python sidecar with structured JSON error responses containing error code, message, and recoverable flag.

**Why:** The Go bridge currently treats all Python errors as opaque strings. Structured errors enable the Go side to distinguish recoverable errors (file not found → skip file) from fatal errors (Python crash → restart sidecar).

**Error taxonomy:**
- `file_not_found` — skip file, continue analysis (recoverable)
- `parse_error` — AST parse failed, report file as unparseable (recoverable)
- `timeout` — analysis took too long (recoverable with reduced scope)
- `internal_error` — bug in analysis code (fatal)

## Open Questions

- **Go-only body-range detection?** The Python fix only helps Python files. Go files use a simpler extraction (`go doc` style) that doesn't have body ranges. Should we add Go AST body-range detection in v0.2, or defer to v0.3 with language expansion?
- **Cache persistence across restarts?** The Go cache is in-memory only. Should we add an optional on-disk cache (file-backed) in v0.2, or keep that for v0.3 (SQLite)?
- **Benchmark CI integration?** Should benchmarks run in CI and block on regression, or be developer-only? CI integration adds overhead but prevents silent regressions.

## Success Criteria

- `detect_patterns` and `cross_project_deps` return cached results on repeat calls (verified by Go test with mock bridge)
- `live_changes` correctly identifies body-only edits in Python files (verified by existing test_live_changes.py test suite + new body-edit test case)
- Performance baselines exist for all 9 tools with documented expected ranges
- Python sidecar returns structured JSON errors for all known error types
- All existing tests continue to pass (67 Python + Go tests)
