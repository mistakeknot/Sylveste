---
artifact_type: prd
bead: iv-w7bh
stage: design
---

# PRD: Intermap v0.2 Hardening

## Problem

Intermap v0.1.4 has 9 working MCP tools but three reliability/performance gaps: expensive tools (`detect_patterns`, `cross_project_deps`) re-scan on every call with no Go-level caching, `live_changes` misses body-only edits when hunk offsets drift between baseline and working tree, and no performance baselines exist to catch regressions.

## Solution

Add Go-level result caching to the two heaviest tools, fix the body-range detection gap in `live_changes`, establish performance baselines as benchmark tests, and introduce structured error types from the Python sidecar for better crash recovery.

## Features

### F1: Go-level result caching for detect_patterns and cross_project_deps
**What:** Add `cache.Cache` instances in `tools.go` for these two tools, using git HEAD SHA as mtime proxy for cache invalidation.

**Acceptance criteria:**
- [ ] `detect_patterns` handler checks cache before calling Python bridge
- [ ] `cross_project_deps` handler checks cache before calling Python bridge
- [ ] Cache key = project/root path, mtime hash = git HEAD SHA (via `git rev-parse HEAD`)
- [ ] TTL = 5 minutes (consistent with `project_registry`)
- [ ] `refresh` parameter added to both tools to force cache bypass
- [ ] Go test verifies cached result returned on second call (mock bridge, assert single Python invocation)

### F2: Body-range detection fix in live_changes
**What:** Fix hunk-to-symbol mapping to correctly identify body-only edits by extracting symbol ranges from both baseline and working tree, then unioning the results.

**Acceptance criteria:**
- [ ] Extract symbol ranges from both HEAD version and working tree for each changed Python file
- [ ] Map hunks to baseline symbols using old-file line numbers AND to working tree symbols using new-file line numbers
- [ ] Union both symbol sets to produce final affected-symbols list
- [ ] New test case: body-only edit (change inside function, header unchanged) correctly reported
- [ ] Existing test_live_changes.py tests continue to pass

### F3: Performance baselines
**What:** Add benchmark tests measuring wall-clock time for each tool, documenting expected performance and catching regressions.

**Acceptance criteria:**
- [ ] Go benchmarks in `tools_test.go` for detect_patterns, cross_project_deps, code_structure, impact_analysis (Python-bridge tools)
- [ ] Expand `test_live_changes_perf.py` with baselines for live_changes, change_impact
- [ ] Cold-start (no cache) and warm (cached) measurements for cached tools
- [ ] Bounds documented as comments (e.g., "expect < 5s cold, < 50ms warm on 20-file project")
- [ ] Benchmarks are opt-in (tagged/skipped by default, run with explicit flag)

### F4: Structured Python error types
**What:** Replace ad-hoc error strings from the Python sidecar with structured JSON containing error code, message, and recoverable flag.

**Acceptance criteria:**
- [ ] Python sidecar returns `{"error": {"code": "<type>", "message": "<detail>", "recoverable": true/false}}` on errors
- [ ] Error codes: `file_not_found`, `parse_error`, `timeout`, `internal_error`
- [ ] Go bridge parses structured errors and distinguishes recoverable vs fatal
- [ ] Recoverable errors logged but don't trigger sidecar restart
- [ ] Fatal errors trigger existing crash-recovery flow (EOF detection + respawn)
- [ ] Test coverage for each error type round-trip (Python → Go)

## Implementation Order

F1 → F4 → F2 → F3

Rationale: F1 (caching) is self-contained and highest immediate impact. F4 (error types) provides infrastructure that F2 benefits from (parse errors during baseline extraction). F2 (body-range) is the most complex change. F3 (benchmarks) should come last to measure the final state.

## Non-goals

- Persistent on-disk cache (v0.3 — SQLite)
- Go AST body-range detection (v0.3 — language expansion)
- Benchmark CI integration (evaluate after baselines exist)
- New tools or language support
- Changes to the Python sidecar lifecycle (crash recovery is already robust)

## Dependencies

- Existing `internal/cache/cache.go` generic cache (no changes needed)
- Existing `_extract_python_symbol_ranges_from_baseline()` in `live_changes.py` (partial implementation to build on)
- Existing `test_live_changes_perf.py` benchmark infrastructure
- `git rev-parse HEAD` available in runtime environment (standard)

## Open Questions

- **Git HEAD as cache key:** Using `git rev-parse HEAD` as mtime proxy is simple but means cache invalidates on ANY commit, not just changes to analyzed files. Acceptable for 5-min TTL? Alternative: hash mtimes of scanned files (more precise, more expensive to compute).
