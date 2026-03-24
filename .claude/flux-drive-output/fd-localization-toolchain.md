# Flux Drive: Localization Toolchain Review

**Reviewer focus:** Whether Skaffen's 7 built-in tools provide sufficient code navigation capability to localize a bug in an unfamiliar repo within a token budget.

**Reviewed codebase:** `os/Skaffen/` -- tool implementations, system prompts, context budget management.

---

## Executive Summary

Skaffen's toolchain has the right tool shapes but is missing critical parameters and behaviors that top SWE-bench agents rely on for efficient localization. The six findings below collectively explain why 9/10 patches land but only 1/10 passes: the agent can find files and make edits, but its navigation tools burn excessive tokens on irrelevant content during localization, exhausting context budget before developing accurate understanding. Estimated impact if all six are fixed: +15-25 percentage points on SWE-bench Lite.

---

## Finding 1: Grep lacks context line support (-A/-B/-C)

**Severity:** CRITICAL for localization
**Files:** `os/Skaffen/internal/tool/grep.go:14-19` (grepParams struct), `grep.go:81-96` (buildRgArgs)

The grep tool exposes only `pattern`, `path`, `glob`, and `output_mode`. There are no `-A` (after), `-B` (before), or `-C` (context) parameters. When the agent finds a match in `content` mode, it gets only the matching line with `-n` line numbers.

For bug localization in Python repos (SWE-bench's target), finding `def some_method` is useless without seeing the surrounding 5-10 lines of implementation. The agent must fall back to a separate `read` call to see context, which costs an entire additional LLM turn (prompt re-ingestion + output tokens).

**Token cost:** Each missing context-grep forces a read tool call, costing ~1 extra turn at 1K-4K output tokens. Over a typical 5-grep localization sequence, this wastes 5K-20K tokens and 5 extra turns.

**Recommendation:** Add `context`, `before_context`, and `after_context` integer parameters to `grepParams`. In `buildRgArgs`, emit `-C N`, `-B N`, or `-A N` flags accordingly:

```go
// In grepParams:
Context       int `json:"context,omitempty"`        // -C lines
BeforeContext int `json:"before_context,omitempty"` // -B lines
AfterContext  int `json:"after_context,omitempty"`  // -A lines

// In buildRgArgs, after output mode switch:
if p.Context > 0 {
    args = append(args, "-C", strconv.Itoa(p.Context))
} else {
    if p.BeforeContext > 0 {
        args = append(args, "-B", strconv.Itoa(p.BeforeContext))
    }
    if p.AfterContext > 0 {
        args = append(args, "-A", strconv.Itoa(p.AfterContext))
    }
}
```

---

## Finding 2: Glob uses filepath.Glob which does not support recursive `**` patterns

**Severity:** CRITICAL for repo structure mapping
**File:** `os/Skaffen/internal/tool/glob.go:48-49`

```go
pattern := filepath.Join(base, p.Pattern)
matches, err := filepath.Glob(pattern)
```

Go's `filepath.Glob` does not support the `**` doublestar pattern. Calling `glob(pattern="**/*.py")` will return zero matches because `**` is treated as a literal directory name (which doesn't exist). This is documented in Go's stdlib: "Glob ignores file system errors such as I/O errors reading directories. The only possible returned error is ErrBadPattern, when pattern is malformed."

SWE-bench repos are multi-level Python packages. Without `**` support, the agent cannot efficiently discover all Python files in the repo. It must resort to `bash` with `find` commands, which burns tokens on the bash output format overhead and doesn't benefit from mtime sorting.

The tool schema description says `e.g., '**/*.go', 'src/*.ts'` -- this advertises a capability that doesn't work.

**Recommendation:** Replace `filepath.Glob` with the `doublestar` package (`github.com/bmatcuk/doublestar/v4`) or implement recursive walk + match:

```go
import "github.com/bmatcuk/doublestar/v4"
// ...
matches, err := doublestar.Glob(os.DirFS(base), p.Pattern)
```

If adding a dependency is undesirable, implement a `filepath.WalkDir` + `filepath.Match` fallback when the pattern contains `**`.

---

## Finding 3: Output truncation preserves head, discards tail -- wrong for diagnostics

**Severity:** HIGH for pytest/test output interpretation
**Files:** `os/Skaffen/internal/tool/bash.go:14-15,67-69`, `os/Skaffen/internal/tool/grep.go:63-64`

```go
const maxOutputBytes = 10240 // 10KB

if len(output) > maxOutputBytes {
    output = output[:maxOutputBytes] + "\n... (truncated)"
}
```

Both `bash` and `grep` truncate by keeping the first 10KB and discarding the rest. For pytest output, the critical information -- the actual assertion error, traceback, and FAILED summary line -- appears at the **end** of the output. The first 10KB is typically test collection, passing tests, and verbose setup output that is diagnostically useless.

SWE-bench tasks regularly require running `pytest` to verify fixes. With head-only truncation, the agent sees "test output" but not "what failed", leading to incorrect patches.

**Recommendation:** Change to tail-preserving truncation, or better, keep both head and tail with a middle elision:

```go
if len(output) > maxOutputBytes {
    // Keep first 2KB (setup info) + last 8KB (errors/summary)
    headSize := 2048
    tailSize := maxOutputBytes - headSize
    output = output[:headSize] +
        "\n\n... (truncated " + strconv.Itoa(len(output)-maxOutputBytes) + " bytes) ...\n\n" +
        output[len(output)-tailSize:]
}
```

This matches Claude Code's behavior and is what top SWE-bench agents use.

---

## Finding 4: Bash uses CombinedOutput -- stderr/stdout interleaved non-deterministically

**Severity:** MEDIUM for pytest diagnostic quality
**File:** `os/Skaffen/internal/tool/bash.go:65`

```go
out, err := cmd.CombinedOutput()
```

`CombinedOutput()` merges stdout and stderr into a single byte stream with OS-level interleaving. For pytest, this means tracebacks (stderr) and test output (stdout) appear in arbitrary order, making it harder for the LLM to parse diagnostic information.

Additionally, there is no way for the agent to request stderr-only output (common for seeing only errors from a test run).

**Recommendation:** Capture stdout and stderr separately, and present them in a structured format:

```go
var stdout, stderr bytes.Buffer
cmd.Stdout = &stdout
cmd.Stderr = &stderr
err := cmd.Run()
// Format output as: stdout first, then stderr clearly labeled
```

Alternatively, add a `capture_stderr` boolean parameter that returns only stderr when set. This is especially valuable for `python -m pytest -x` where the user only wants the failure traceback.

---

## Finding 5: No system prompt teaches tool usage patterns for code localization

**Severity:** HIGH for agent effectiveness
**Files:** `os/Skaffen/internal/contextfiles/contextfiles.go` (entire file), `os/Skaffen/cmd/skaffen/main.go:626-639`

The system prompt is assembled entirely from project context files (SKAFFEN.md, CLAUDE.md, AGENTS.md) found in the directory hierarchy. There is **no built-in system prompt content** that teaches the agent:

1. How to use `glob` to map repo structure before diving into files
2. How to combine `grep` + `read` for efficient localization
3. That `read` supports `offset` and `limit` for targeted file inspection
4. How to use `grep` in `files_with_matches` mode first, then `content` mode for context
5. The 10KB output cap and how to work around it (e.g., filtering test output through `tail`)
6. That `**` patterns don't work in glob (currently -- see Finding 2)

Claude Code's system prompt (~8K tokens) dedicates significant space to tool usage guidance. Skaffen's agent gets zero tool guidance unless the target repo happens to have a SKAFFEN.md with tool tips.

For SWE-bench, this means the agent must independently discover effective search strategies on every instance, burning localization tokens on trial-and-error.

**Recommendation:** Add a built-in system prompt element (via priompt with `Stable: true, Priority: 90`) that teaches the localization playbook:

```
## Available Tools

You have 7 tools for code navigation and modification:

### Localization Strategy
1. Start with `glob` to understand repo structure: `glob(pattern="*.py")` for top-level, `ls` for directories
2. Use `grep(output_mode="files_with_matches")` to find relevant files by symbol/error text
3. Use `grep(output_mode="content")` to see matching lines with line numbers
4. Use `read(file_path, offset=N, limit=M)` to read specific sections -- avoid reading entire large files
5. When running tests, pipe through `tail -100` to see failures within the 10KB output limit

### Token Efficiency
- read defaults to 2000 lines. Always set limit for large files.
- grep defaults to files_with_matches mode. Use content mode only when you need to see the code.
- Output is capped at 10KB. For pytest, use: bash(command="pytest test_file.py -x 2>&1 | tail -80")
```

This should be a priompt Element rendered into the system prompt, not a SKAFFEN.md file that only appears in specific repos.

---

## Finding 6: Read tool has no line count / file size reporting

**Severity:** MEDIUM for token budget awareness
**File:** `os/Skaffen/internal/tool/read.go:35-92`

When the agent reads a file, it gets the content but no metadata about total file size. If a file has 5000 lines and the agent reads lines 1-2000 (default), it doesn't know there are 3000 more lines. There is no indication like "showing lines 1-2000 of 5000" that would prompt the agent to continue reading.

For SWE-bench, Python files are often 500-2000 lines. The agent might read the first 2000 lines of a 2500-line file and miss the relevant class defined at line 2200.

**Recommendation:** After scanning the file, report total line count in the output:

```go
// After the scan loop, add:
totalLines := lineNum
if emitted < totalLines - (offset - 1) {
    fmt.Fprintf(&b, "\n[Showing lines %d-%d of %d total]", offset, offset+emitted-1, totalLines)
}
```

---

## Summary Table

| # | Finding | Severity | Est. SWE-bench Impact | Effort |
|---|---------|----------|----------------------|--------|
| 1 | Grep missing -A/-B/-C context lines | CRITICAL | +5-8% | 1 hour |
| 2 | Glob `**` pattern silently broken | CRITICAL | +3-5% | 1 hour |
| 3 | Head-only truncation loses test failures | HIGH | +5-8% | 30 min |
| 4 | CombinedOutput interleaves stderr/stdout | MEDIUM | +1-2% | 1 hour |
| 5 | No system prompt tool usage guidance | HIGH | +5-10% | 2 hours |
| 6 | Read lacks total line count reporting | MEDIUM | +1-2% | 15 min |

**Priority order for implementation:** 5 > 1 > 3 > 2 > 6 > 4

Finding 5 (system prompt) is highest priority because it multiplies the effectiveness of every other tool -- even with current tool limitations, better prompting would teach the agent to work around them. Finding 1 (context lines) is next because it eliminates the most wasted turns during localization. Finding 3 (truncation) is critical for the pytest-heavy SWE-bench workflow.

---

## Additional Observations

**Positive design choices:**
- Read tool already supports `offset` and `limit` parameters (`read.go:17-18`) -- this is a strong primitive that most SWE-bench agents lack. The problem is purely that nothing teaches the agent to use them.
- Grep correctly falls back from `rg` to `grep` (`grep.go:54-57`), ensuring it works in Docker containers without ripgrep.
- The 10KB cap is shared between bash and grep via the `maxOutputBytes` constant (`bash.go:15`), making it easy to adjust both.
- Phase gating (`registry.go:49-72`) correctly restricts write tools during Observe/Orient/Decide, preventing premature edits before localization is complete.

**Not in scope but worth noting:**
- No Python import graph / AST analysis tools exist. The agent cannot trace `from module import Class` chains without manual grep. For SWE-bench, this would be valuable but is a larger investment than the six findings above.
- The priompt system (`masaq/priompt/priompt.go`) is well-designed for budget management but underutilized -- only `PriomptSession` uses it, and the main path (`JSONLSession`) bypasses it entirely with a raw string prompt. Wiring the system prompt through priompt would enable the tool guidance element from Finding 5 to be budget-aware.
