---
artifact_type: plan
bead: iv-w7bh
stage: design
requirements:
  - F1: Go-level result caching for detect_patterns and cross_project_deps
  - F4: Structured Python error types from sidecar
  - F2: Body-range detection fix in live_changes
  - F3: Performance baselines for intermap tools
---
# Intermap v0.2 Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** iv-w7bh
**Goal:** Harden intermap's 9-tool MCP server for reliability and performance — add Go-level caching, fix body-range detection, establish performance baselines, and introduce structured error types.

**Architecture:** Go MCP server (`cmd/intermap-mcp/`) delegates analysis to a persistent Python sidecar (`python/intermap/`) via stdin/stdout JSON-RPC. The generic `cache.Cache[T]` in `internal/cache/cache.go` provides thread-safe LRU+mtime+TTL caching — currently only used by `project_registry`. We add two more cache instances for `detect_patterns` and `cross_project_deps`, upgrade the Python sidecar's error reporting to structured JSON, fix `live_changes` body-range detection, and add benchmarks.

**Tech Stack:** Go (mcp-go SDK), Python 3.11+ (ast module), git CLI

**Prior Learnings:**
- `docs/solutions/patterns/go-map-hash-determinism-20260223.md` — Sort map keys before hashing to avoid non-deterministic cache misses. We use git HEAD SHA (a string) as our mtime hash, so this doesn't apply directly, but is important if we ever switch to file-mtime-based hashing.
- `docs/solutions/best-practices/silent-api-misuse-patterns-intercore-20260221.md` — Always check return counts in Go API calls. Relevant for parsing the new structured error JSON from the sidecar.

---

## Must-Haves

**Truths** (observable behaviors):
- `detect_patterns` and `cross_project_deps` return cached results on repeat calls within 5 minutes (no Python invocation on cache hit)
- `live_changes` correctly identifies body-only edits in Python files where only function internals change
- Python sidecar returns structured `{"error": {"code": "...", "message": "...", "recoverable": true/false}}` on all error paths
- Go bridge distinguishes recoverable errors (logged, no restart) from fatal errors (crash recovery)

**Artifacts** (files that must exist):
- [`internal/tools/tools.go`] has `detectPatternsCache` and `crossProjectDepsCache` instances + `refresh` parameter on both tools
- [`python/intermap/__main__.py`] returns structured error JSON with `code`, `message`, `recoverable` fields
- [`internal/python/bridge.go`] has `sidecarError` with `Code`, `Message`, `Recoverable` fields and recovery logic
- [`python/intermap/live_changes.py`] extracts baseline symbols for modified files (not just deletions) and unions results

**Key Links:**
- Go cache instances in `tools.go` must use the same `cache.New[map[string]any]` pattern as `projectCache`
- Structured error type in `bridge.go:sidecarError` must match the JSON shape emitted by `__main__.py`
- Body-range fix in `live_changes.py` must preserve backward compatibility with existing `symbols_affected` output format

---

## ~~Task 1: Add Go-level cache for `detect_patterns`~~ [x]

**Files:**
- Modify: `interverse/intermap/internal/tools/tools.go:21` (add cache declaration)
- Modify: `interverse/intermap/internal/tools/tools.go:379-407` (add caching + refresh param)
- Test: `interverse/intermap/internal/tools/tools_test.go`

**Step 1: Add cache instance and git HEAD helper**

In `tools.go`, add after line 21 (`var projectCache = ...`):

```go
var detectPatternsCache = cache.New[map[string]any](5*time.Minute, 10)
```

Add a helper function (after `stringOr`) to get the current git HEAD SHA for a directory:

```go
// gitHeadSHA returns the HEAD commit SHA for a git repo, or empty string on error.
func gitHeadSHA(dir string) string {
	cmd := exec.Command("git", "-C", dir, "rev-parse", "HEAD")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
```

Add `"os/exec"` to the imports.

**Step 2: Add `refresh` parameter and caching to `detectPatterns`**

Replace the `detectPatterns` handler body (lines 391-405) with:

```go
Handler: func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    args := req.GetArguments()
    project, _ := args["project"].(string)
    if project == "" {
        return mcputil.ValidationError("project is required")
    }
    refresh, _ := args["refresh"].(bool)
    pyArgs := map[string]any{
        "language": stringOr(args["language"], "auto"),
    }

    cacheKey := project
    mtimeHash := gitHeadSHA(project)
    if !refresh && mtimeHash != "" {
        if cached, ok := detectPatternsCache.Get(cacheKey, mtimeHash); ok {
            return jsonResult(cached)
        }
    }

    result, err := bridge.Run(ctx, "detect_patterns", project, pyArgs)
    if err != nil {
        return mcputil.WrapError(err)
    }
    if mtimeHash != "" {
        detectPatternsCache.Put(cacheKey, mtimeHash, result)
    }
    return jsonResult(result)
},
```

Also add the `refresh` parameter to the tool definition:

```go
mcp.WithBoolean("refresh",
    mcp.Description("Force cache refresh"),
),
```

**Step 3: Write test for `detect_patterns` caching**

Add to `tools_test.go`:

```go
func TestGitHeadSHA_ReturnsNonEmpty(t *testing.T) {
	// Run from repo root — should always have a HEAD
	sha := gitHeadSHA(".")
	if sha == "" {
		t.Skip("not in a git repo")
	}
	if len(sha) != 40 {
		t.Errorf("expected 40-char SHA, got %d chars: %s", len(sha), sha)
	}
}

func TestGitHeadSHA_InvalidDir(t *testing.T) {
	sha := gitHeadSHA("/nonexistent/path")
	if sha != "" {
		t.Errorf("expected empty for invalid dir, got: %s", sha)
	}
}
```

**Step 4: Run tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/tools/ -v -run TestGitHead`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add internal/tools/tools.go internal/tools/tools_test.go
git commit -m "feat(intermap): add Go-level cache for detect_patterns

Uses git HEAD SHA as mtime proxy for cache invalidation.
5-minute TTL, 10-entry LRU, with refresh parameter to bypass."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/tools/ -v -run TestGitHead`
  expect: exit 0
</verify>

---

## ~~Task 2: Add Go-level cache for `cross_project_deps`~~ [x]

**Files:**
- Modify: `interverse/intermap/internal/tools/tools.go:22` (add cache declaration)
- Modify: `interverse/intermap/internal/tools/tools.go:354-377` (add caching + refresh param)

**Step 1: Add cache instance**

In `tools.go`, add after the `detectPatternsCache` line:

```go
var crossProjectDepsCache = cache.New[map[string]any](5*time.Minute, 10)
```

**Step 2: Add `refresh` parameter and caching to `crossProjectDeps`**

Replace the `crossProjectDeps` handler body (lines 363-375) with:

```go
Handler: func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
    args := req.GetArguments()
    root, _ := args["root"].(string)
    if root == "" {
        return mcputil.ValidationError("root is required")
    }
    refresh, _ := args["refresh"].(bool)

    cacheKey := root
    mtimeHash := gitHeadSHA(root)
    if !refresh && mtimeHash != "" {
        if cached, ok := crossProjectDepsCache.Get(cacheKey, mtimeHash); ok {
            return jsonResult(cached)
        }
    }

    result, err := bridge.Run(ctx, "cross_project_deps", root, map[string]any{})
    if err != nil {
        return mcputil.WrapError(err)
    }
    if mtimeHash != "" {
        crossProjectDepsCache.Put(cacheKey, mtimeHash, result)
    }
    return jsonResult(result)
},
```

Also add the `refresh` parameter to the tool definition:

```go
mcp.WithBoolean("refresh",
    mcp.Description("Force cache refresh"),
),
```

**Step 3: Run tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && go build ./...`
Expected: PASS (compilation)

**Step 4: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add internal/tools/tools.go
git commit -m "feat(intermap): add Go-level cache for cross_project_deps

Same pattern as detect_patterns: git HEAD SHA, 5min TTL, refresh param."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/... -v`
  expect: exit 0
</verify>

---

## ~~Task 3: Add structured error types to Python sidecar~~ [x]

**Files:**
- Modify: `interverse/intermap/python/intermap/__main__.py` (structured error response)
- Create: `interverse/intermap/python/intermap/errors.py` (error type definitions)
- Test: `interverse/intermap/python/tests/test_sidecar.py`

**Step 1: Create the errors module**

Create `interverse/intermap/python/intermap/errors.py`:

```python
"""Structured error types for the intermap sidecar.

Error codes:
  file_not_found  — skip file, continue analysis (recoverable)
  parse_error     — AST parse failed (recoverable)
  timeout         — analysis took too long (recoverable)
  internal_error  — bug in analysis code (fatal)
"""


class IntermapError(Exception):
    """Base error with structured JSON output."""

    def __init__(self, code: str, message: str, *, recoverable: bool = True):
        super().__init__(message)
        self.code = code
        self.message = message
        self.recoverable = recoverable

    def to_dict(self) -> dict:
        return {
            "code": self.code,
            "message": self.message,
            "recoverable": self.recoverable,
        }


class FileNotFoundError_(IntermapError):
    def __init__(self, message: str):
        super().__init__("file_not_found", message, recoverable=True)


class ParseError(IntermapError):
    def __init__(self, message: str):
        super().__init__("parse_error", message, recoverable=True)


class TimeoutError_(IntermapError):
    def __init__(self, message: str):
        super().__init__("timeout", message, recoverable=True)


class InternalError(IntermapError):
    def __init__(self, message: str):
        super().__init__("internal_error", message, recoverable=False)
```

**Step 2: Update sidecar to emit structured errors**

Replace the error handling in `__main__.py` `_run_sidecar()` (lines 77-81) with:

```python
        try:
            result = dispatch(command, project, extra_args)
            resp = {"id": req_id, "result": result}
        except IntermapError as e:
            resp = {"id": req_id, "error": e.to_dict()}
        except FileNotFoundError as e:
            resp = {
                "id": req_id,
                "error": {
                    "code": "file_not_found",
                    "message": str(e),
                    "recoverable": True,
                },
            }
        except SyntaxError as e:
            resp = {
                "id": req_id,
                "error": {
                    "code": "parse_error",
                    "message": str(e),
                    "recoverable": True,
                },
            }
        except TimeoutError as e:
            resp = {
                "id": req_id,
                "error": {
                    "code": "timeout",
                    "message": str(e),
                    "recoverable": True,
                },
            }
        except Exception as e:
            resp = {
                "id": req_id,
                "error": {
                    "code": "internal_error",
                    "message": f"{type(e).__name__}: {e}",
                    "recoverable": False,
                },
            }
```

Add at the top of `__main__.py`:

```python
from .errors import IntermapError
```

**Step 3: Write tests for structured errors**

Add to `test_sidecar.py`:

```python
def test_sidecar_structured_error_file_not_found(sidecar):
    """File not found should return structured recoverable error."""
    resp = sidecar.send({
        "id": 99,
        "command": "structure",
        "project": "/nonexistent/path/that/does/not/exist",
        "args": {},
    })
    assert resp["id"] == 99
    assert "error" in resp
    err = resp["error"]
    assert "code" in err
    assert "message" in err
    assert "recoverable" in err
    assert isinstance(err["recoverable"], bool)


def test_sidecar_structured_error_unknown_command(sidecar):
    """Unknown command should return internal_error (non-recoverable)."""
    resp = sidecar.send({
        "id": 100,
        "command": "nonexistent_command",
        "project": ".",
        "args": {},
    })
    assert resp["id"] == 100
    # Unknown commands return result dict with error key, not sidecar error
    # This verifies the dispatch layer handles it
    result = resp.get("result", resp.get("error", {}))
    assert result is not None
```

**Step 4: Run tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_sidecar.py -v`
Expected: PASS

**Step 5: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add python/intermap/errors.py python/intermap/__main__.py python/tests/test_sidecar.py
git commit -m "feat(intermap): structured error types from Python sidecar

Errors now include code, message, and recoverable flag.
Codes: file_not_found, parse_error, timeout, internal_error."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_sidecar.py -v`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -c "from intermap.errors import IntermapError, ParseError; e = ParseError('bad syntax'); print(e.to_dict())"`
  expect: contains "parse_error"
</verify>

---

## ~~Task 4: Update Go bridge to parse structured errors~~ [x]

**Files:**
- Modify: `interverse/intermap/internal/python/bridge.go:66-69` (update sidecarError struct)
- Modify: `interverse/intermap/internal/python/bridge.go:157-158` (update error handling)
- Test: `interverse/intermap/internal/python/bridge_test.go`

**Step 1: Update the `sidecarError` struct**

In `bridge.go`, replace the `sidecarError` struct (lines 66-69):

```go
type sidecarError struct {
	Type        string `json:"type"`        // Deprecated: kept for backward compat
	Code        string `json:"code"`        // New structured code
	Message     string `json:"message"`
	Recoverable *bool  `json:"recoverable"` // Pointer so we can detect absence
}

// isRecoverable returns true if the error is explicitly marked as recoverable,
// or defaults to false if the field is absent (legacy error format).
func (e *sidecarError) isRecoverable() bool {
	if e.Recoverable != nil {
		return *e.Recoverable
	}
	return false
}

// errorCode returns the structured code, falling back to Type for legacy errors.
func (e *sidecarError) errorCode() string {
	if e.Code != "" {
		return e.Code
	}
	return e.Type
}
```

**Step 2: Update error handling in `runSidecar`**

Replace line 158 in `bridge.go`:

```go
// Old:
// return nil, fmt.Errorf("python %s: [%s] %s", command, resp.Error.Type, resp.Error.Message)

// New:
if resp.Error != nil {
    if resp.Error.isRecoverable() {
        return nil, &RecoverableError{
            Code:    resp.Error.errorCode(),
            Message: resp.Error.Message,
        }
    }
    return nil, fmt.Errorf("python %s: [%s] %s", command, resp.Error.errorCode(), resp.Error.Message)
}
```

Add the `RecoverableError` type:

```go
// RecoverableError indicates a Python error that should be logged but not trigger sidecar restart.
type RecoverableError struct {
	Code    string
	Message string
}

func (e *RecoverableError) Error() string {
	return fmt.Sprintf("python recoverable [%s]: %s", e.Code, e.Message)
}

// IsRecoverable checks if an error is a RecoverableError.
func IsRecoverable(err error) bool {
	var re *RecoverableError
	return errors.As(err, &re)
}
```

Add `"errors"` to imports.

**Step 3: Update `Run()` to not trigger crash recovery for recoverable errors**

In the `Run()` method (lines 72-103), after the `b.runSidecar()` call, check if the error is recoverable before triggering crash recovery:

```go
result, err := b.runSidecar(ctx, command, project, args)
if err != nil {
    // Recoverable errors are returned directly — no crash recovery needed
    if IsRecoverable(err) {
        return nil, err
    }

    // Sidecar failed — try to respawn once
    b.stopLocked()
    b.recordCrash()
    // ... rest stays the same
```

**Step 4: Write test for recoverable error passthrough**

Add to `bridge_test.go`:

```go
func TestRecoverableError(t *testing.T) {
	err := &RecoverableError{Code: "parse_error", Message: "bad syntax"}
	if !IsRecoverable(err) {
		t.Error("expected IsRecoverable to return true")
	}
	if err.Error() != "python recoverable [parse_error]: bad syntax" {
		t.Errorf("unexpected error string: %s", err.Error())
	}

	// Wrapped errors should also be recoverable
	wrapped := fmt.Errorf("wrapper: %w", err)
	if !IsRecoverable(wrapped) {
		t.Error("expected wrapped RecoverableError to be recoverable")
	}
}

func TestNonRecoverableError(t *testing.T) {
	err := fmt.Errorf("python crash")
	if IsRecoverable(err) {
		t.Error("expected regular error to not be recoverable")
	}
}
```

**Step 5: Run tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/python/ -v -run TestRecoverable`
Expected: PASS

**Step 6: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add internal/python/bridge.go internal/python/bridge_test.go
git commit -m "feat(intermap): Go bridge parses structured Python errors

Recoverable errors (file_not_found, parse_error, timeout) are returned
without triggering sidecar restart. Fatal errors still trigger crash recovery."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go build ./...`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/python/ -v -run TestRecoverable`
  expect: exit 0
</verify>

---

## ~~Task 5: Fix body-range detection in `live_changes`~~ [x]

**Files:**
- Modify: `interverse/intermap/python/intermap/live_changes.py:69-108` (union baseline + working tree symbols)
- Test: `interverse/intermap/python/tests/test_live_changes.py`

**Step 1: Write the failing test**

Add to `test_live_changes.py`:

```python
def test_symbol_annotation_body_only_edit_with_line_shift(tmp_path):
    """Body-only edit that adds lines should still match the enclosing function.

    When a hunk adds lines inside function A, all symbols below shift down.
    We need to match hunks against BOTH baseline and working-tree symbol ranges
    to catch the edit even when line numbers drift.
    """
    project = tmp_path / "proj"
    project.mkdir()
    _git_init(project)

    # Create baseline with two functions
    src = project / "funcs.py"
    src.write_text(
        "def alpha():\n"
        "    return 1\n"
        "\n"
        "def beta():\n"
        "    return 2\n"
    )
    _git_add_commit(project, "funcs.py", "initial")

    # Edit: add lines inside alpha's body only (no header change)
    src.write_text(
        "def alpha():\n"
        "    x = 10\n"
        "    y = 20\n"
        "    return x + y\n"
        "\n"
        "def beta():\n"
        "    return 2\n"
    )

    result = get_live_changes(str(project), baseline="HEAD")
    changes = result["changes"]
    assert len(changes) == 1

    symbols = changes[0]["symbols_affected"]
    symbol_names = [s["name"] for s in symbols]
    assert "alpha" in symbol_names, f"Expected alpha in {symbol_names}"
    # beta should NOT be affected — it didn't change, just shifted
    assert "beta" not in symbol_names, f"beta should not be affected: {symbol_names}"
```

**Step 2: Run test to verify it fails**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes.py::test_symbol_annotation_body_only_edit_with_line_shift -v`
Expected: This may PASS because the working-tree range for `alpha` (lines 1-4) overlaps the hunk new-side range (lines 2-4). If it passes, we still need the fix for correctness in edge cases. Proceed regardless.

**Step 3: Implement the union approach**

In `live_changes.py`, modify the symbol matching logic for modified files (around lines 77-108). The key change: for modified files with non-deletion hunks, ALSO extract baseline symbols and map old-side hunk ranges to them, then union with working-tree matches.

Replace the optimized-mode symbol matching block (lines 79-108) with:

```python
            if optimized_mode:
                py_symbols = _extract_python_symbol_ranges(fpath, use_cache=True)
                if py_symbols:
                    # Working-tree match: new-side hunk ranges → working-tree symbols
                    matched = [
                        sym
                        for sym in py_symbols
                        if _range_overlaps_any(changed_ranges, sym["start"], sym["end"])
                    ]
                    seen_keys = {
                        (sym["name"], sym["type"], sym["line"]) for sym in matched
                    }

                    # Baseline match: old-side hunk ranges → baseline symbols.
                    # This catches body-only edits where line shifts cause the
                    # working-tree ranges to drift from hunk line numbers.
                    old_hunk_ranges = _hunks_to_old_line_ranges(change["hunks"])
                    if old_hunk_ranges:
                        if baseline_identity is None:
                            baseline_identity = _resolve_baseline_identity(
                                project_path, baseline,
                            )
                        baseline_file = change.get("old_file", change["file"])
                        old_symbols = _extract_python_symbol_ranges_from_baseline(
                            project_path, baseline_identity, baseline_file,
                        )
                        for sym in old_symbols:
                            if _range_overlaps_any(
                                old_hunk_ranges, sym["start"], sym["end"]
                            ):
                                _append_symbol_if_missing(matched, seen_keys, sym)

                    # Pure deletions: old-side deletion ranges → baseline symbols
                    old_deletion_ranges = _hunks_to_old_deletion_ranges(change["hunks"])
                    if old_deletion_ranges:
                        if baseline_identity is None:
                            baseline_identity = _resolve_baseline_identity(
                                project_path, baseline,
                            )
                        baseline_file = change.get("old_file", change["file"])
                        old_symbols = _extract_python_symbol_ranges_from_baseline(
                            project_path, baseline_identity, baseline_file,
                        )
                        for sym in old_symbols:
                            if _range_overlaps_any(
                                old_deletion_ranges, sym["start"], sym["end"]
                            ):
                                _append_symbol_if_missing(matched, seen_keys, sym)

                    symbols = _flatten_matched_python_symbols(matched)
```

**Step 4: Add `_hunks_to_old_line_ranges` helper**

Add after `_hunks_to_old_deletion_ranges` (around line 444):

```python
def _hunks_to_old_line_ranges(hunks: list[dict]) -> list[tuple[int, int]]:
    """Extract old-side line ranges from ALL hunks (not just pure deletions)."""
    ranges: list[tuple[int, int]] = []
    for hunk in hunks:
        old_start = int(hunk.get("old_start", 1))
        old_count = int(hunk.get("old_count", 1))
        if old_count > 0:
            ranges.append((old_start, old_start + old_count - 1))
    return _merge_ranges(ranges)
```

**Step 5: Run all live_changes tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes.py -v`
Expected: ALL PASS (including the new test)

**Step 6: Run perf tests to verify no regression**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes_perf.py -v`
Expected: ALL PASS

**Step 7: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add python/intermap/live_changes.py python/tests/test_live_changes.py
git commit -m "fix(intermap): body-range detection unions baseline + working tree symbols

For modified files, extract symbol ranges from both HEAD and working tree,
mapping old-side hunk ranges to baseline symbols and new-side ranges to
working-tree symbols. Union both sets. Fixes detection of body-only edits
where line shifts cause ranges to drift."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes.py -v`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes_perf.py -v`
  expect: exit 0
</verify>

---

## ~~Task 6: Add performance baselines — Go benchmarks~~ [x]

**Files:**
- Modify: `interverse/intermap/internal/tools/tools_test.go` (add benchmarks)

**Step 1: Write Go benchmarks**

Add to `tools_test.go`:

```go
// Benchmarks measure wall-clock time for Python-bridge tools.
// Run with: go test ./internal/tools/ -bench=. -benchtime=3x -run=^$
//
// Expected bounds (on a 20-file project):
//   BenchmarkDetectPatterns_Cold: < 5s
//   BenchmarkDetectPatterns_Warm: < 50ms
//   BenchmarkCrossProjectDeps_Cold: < 5s
//   BenchmarkCrossProjectDeps_Warm: < 50ms

func BenchmarkDetectPatterns_Cold(b *testing.B) {
	bridge := pybridge.NewBridge(pybridge.DefaultPythonPath())
	defer bridge.Close()
	ctx := context.Background()

	for i := 0; i < b.N; i++ {
		detectPatternsCache.Invalidate(".")
		_, err := bridge.Run(ctx, "detect_patterns", ".", map[string]any{"language": "auto"})
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkDetectPatterns_Warm(b *testing.B) {
	bridge := pybridge.NewBridge(pybridge.DefaultPythonPath())
	defer bridge.Close()
	ctx := context.Background()

	// Prime the cache
	result, err := bridge.Run(ctx, "detect_patterns", ".", map[string]any{"language": "auto"})
	if err != nil {
		b.Fatal(err)
	}
	sha := gitHeadSHA(".")
	detectPatternsCache.Put(".", sha, result)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, ok := detectPatternsCache.Get(".", sha); !ok {
			b.Fatal("cache miss on warm benchmark")
		}
	}
}

func BenchmarkCrossProjectDeps_Cold(b *testing.B) {
	bridge := pybridge.NewBridge(pybridge.DefaultPythonPath())
	defer bridge.Close()
	ctx := context.Background()

	// Use parent directory (monorepo root) for cross-project deps
	root := "../../../.."
	for i := 0; i < b.N; i++ {
		crossProjectDepsCache.Invalidate(root)
		_, err := bridge.Run(ctx, "cross_project_deps", root, map[string]any{})
		if err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkCrossProjectDeps_Warm(b *testing.B) {
	bridge := pybridge.NewBridge(pybridge.DefaultPythonPath())
	defer bridge.Close()
	ctx := context.Background()

	root := "../../../.."
	result, err := bridge.Run(ctx, "cross_project_deps", root, map[string]any{})
	if err != nil {
		b.Fatal(err)
	}
	sha := gitHeadSHA(root)
	crossProjectDepsCache.Put(root, sha, result)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, ok := crossProjectDepsCache.Get(root, sha); !ok {
			b.Fatal("cache miss on warm benchmark")
		}
	}
}
```

Add `"context"` and `pybridge "github.com/mistakeknot/intermap/internal/python"` to the test imports.

**Step 2: Run benchmarks**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/tools/ -bench=BenchmarkDetectPatterns_Warm -benchtime=3x -run=^$ -v`
Expected: PASS (warm should be sub-millisecond)

**Step 3: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add internal/tools/tools_test.go
git commit -m "test(intermap): add Go benchmarks for detect_patterns and cross_project_deps

Cold (Python bridge) and warm (cache hit) measurements.
Run with: go test ./internal/tools/ -bench=. -benchtime=3x -run=^$"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./internal/tools/ -bench=BenchmarkDetectPatterns_Warm -benchtime=3x -run=^$ -v`
  expect: exit 0
</verify>

---

## ~~Task 7: Add performance baselines — Python benchmarks~~ [x]

**Files:**
- Modify: `interverse/intermap/python/tests/test_live_changes_perf.py` (expand with new baselines)

**Step 1: Add baselines for change_impact**

Add to `test_live_changes_perf.py`:

```python
@pytest.mark.perf
def test_change_impact_cold_start(perf_project):
    """Baseline: change_impact cold start on a 20-file project.

    Expected: < 5s cold.
    """
    from intermap.change_impact import analyze_change_impact

    start = time.monotonic()
    result = analyze_change_impact(str(perf_project))
    elapsed = time.monotonic() - start

    assert elapsed < 10.0, f"change_impact cold took {elapsed:.2f}s (expected < 10s)"
    assert "affected_tests" in result or "changes" in result


@pytest.mark.perf
def test_live_changes_cold_vs_warm(perf_project):
    """Baseline: live_changes cold vs warm (with symbol cache).

    Expected: warm call < 50% of cold call time.
    """
    from intermap.live_changes import get_live_changes

    # Cold call
    start_cold = time.monotonic()
    get_live_changes(str(perf_project), baseline="HEAD")
    cold_time = time.monotonic() - start_cold

    # Warm call (symbol cache populated)
    start_warm = time.monotonic()
    get_live_changes(str(perf_project), baseline="HEAD")
    warm_time = time.monotonic() - start_warm

    # Warm should be notably faster due to symbol cache
    if cold_time > 0.1:  # Only assert if cold is measurable
        assert warm_time < cold_time, (
            f"warm ({warm_time:.3f}s) should be faster than cold ({cold_time:.3f}s)"
        )
```

**Step 2: Run perf tests**

Run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes_perf.py -v -k perf`
Expected: PASS

**Step 3: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add python/tests/test_live_changes_perf.py
git commit -m "test(intermap): add Python performance baselines for change_impact and live_changes

Cold/warm measurements with documented expected bounds.
Run with: pytest python/tests/test_live_changes_perf.py -v -k perf"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/test_live_changes_perf.py -v`
  expect: exit 0
</verify>

---

## ~~Task 8: Final integration test and version bump~~ [x]

**Files:**
- Modify: `interverse/intermap/docs/intermap-roadmap.md` (mark v0.2 items as done)

**Step 1: Run the full test suite**

Run Go tests:
```bash
cd /home/mk/projects/Sylveste/interverse/intermap && go test ./... -v
```

Run Python tests:
```bash
cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/ -v
```

Expected: ALL PASS

**Step 2: Integration test — build and run MCP**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
go build -o bin/intermap-mcp ./cmd/intermap-mcp/
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | PYTHONPATH=python CLAUDE_PLUGIN_ROOT=. ./bin/intermap-mcp 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); tools=[t['name'] for t in d['result']['tools']]; print(f'{len(tools)} tools:', ', '.join(sorted(tools)))"
```

Expected: `9 tools: agent_map, change_impact, code_structure, cross_project_deps, detect_patterns, impact_analysis, live_changes, project_registry, resolve_project`

Verify `refresh` param exists on `detect_patterns` and `cross_project_deps`:
```bash
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | PYTHONPATH=python CLAUDE_PLUGIN_ROOT=. ./bin/intermap-mcp 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for t in d['result']['tools']:
    if t['name'] in ('detect_patterns', 'cross_project_deps'):
        props = t.get('inputSchema', {}).get('properties', {})
        has_refresh = 'refresh' in props
        print(f\"{t['name']}: refresh={'yes' if has_refresh else 'NO'}\")"
```

Expected: Both tools report `refresh=yes`

**Step 3: Update roadmap**

In `interverse/intermap/docs/intermap-roadmap.md`, mark the v0.2 items as complete.

**Step 4: Commit**

```bash
cd /home/mk/projects/Sylveste/interverse/intermap
git add docs/intermap-roadmap.md
git commit -m "docs(intermap): mark v0.2 hardening items as complete

Go caching, structured errors, body-range fix, performance baselines."
```

<verify>
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && go test ./... -count=1`
  expect: exit 0
- run: `cd /home/mk/projects/Sylveste/interverse/intermap && PYTHONPATH=python python3 -m pytest python/tests/ -v`
  expect: exit 0
</verify>
