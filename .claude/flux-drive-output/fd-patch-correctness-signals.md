# Flux Drive: Patch Correctness Signals

**Reviewer:** fd-patch-correctness-signals
**Target:** os/Skaffen/ (full Skaffen agent codebase)
**Date:** 2026-03-15
**Lens:** Whether Skaffen has mechanisms to evaluate patch correctness before submission -- pre-submission validation, regression detection, and confidence scoring.

---

## Executive Summary

Skaffen currently has **zero automated patch correctness verification**. The edit and write tools perform only basic I/O error handling (file not found, ambiguous match). There is no syntax checking, no post-edit validation, no aggregate diff review, no test-pass/fail capture, and no empty-diff detection. The quality signal system (mutations) tracks operational telemetry (token efficiency, turn count, tool error rate) but captures nothing about whether the produced patch is semantically correct. For a SWE-bench Lite agent producing patches at 9/10 rate but passing 1/10, this is the primary bottleneck.

---

## Finding 1: Edit tool has no post-edit validation

**File:** `os/Skaffen/internal/tool/edit.go:36-75`

The `EditTool.Execute` method performs a pure string replacement: read file, count occurrences, replace, write back. The only checks are:
- `old_string` not found (line 54)
- Multiple matches without `replace_all` (line 56-60)

**Missing:**
- No syntax check after edit (e.g., `python3 -c "import py_compile; py_compile.compile('file.py', doraise=True)"`)
- No AST parse to verify structural validity
- No detection of broken indentation, unclosed brackets, or malformed constructs
- No file-type-specific validation (Python, Go, JSON, YAML, etc.)

**Impact:** The agent can produce syntactically broken patches without any feedback. The model only sees "replaced 1 occurrence(s)" -- indistinguishable from a correct edit.

**Recommendation:** Add a post-edit validation step in `EditTool.Execute`. After the write succeeds:
```go
// For Python files: py_compile check
// For Go files: go vet check
// For JSON files: json.Valid() check
```
Return the validation result as part of the tool output so the model can self-correct. This should be a non-blocking warning (tool still succeeds), but the model sees e.g., `"replaced 1 occurrence(s) in foo.py\nWARNING: syntax error at line 42: unexpected indent"`.

---

## Finding 2: Write tool has no post-write validation

**File:** `os/Skaffen/internal/tool/write.go:32-58`

Same issue as edit. `WriteTool.Execute` writes atomically via temp file + rename, but performs zero content validation. Returns only byte count.

**Recommendation:** Same as Finding 1 -- add language-aware validation after write.

---

## Finding 3: Agent does NOT see aggregate diff at end of Act phase

**File:** `os/Skaffen/internal/agentloop/loop.go:95-245`

The agent loop (`RunWithContent`) runs turn-by-turn. Each turn calls the LLM, executes tools, emits evidence, and checks stop condition. When the model returns `stop_reason == "end_turn"` (line 228), the loop exits immediately with the response text.

**There is no end-of-phase hook** that presents the agent with an aggregate diff of all changes made during the Act phase. The model never sees the cumulative effect of its edits -- only individual tool results from each turn.

The `git.Git` package (line `git/git.go:52-54`) has `Diff()` which returns `git diff HEAD`, and `DiffAgainst(ref)` (lines 97-106) which can diff against a base ref. These are never called by the agent loop or any orchestrating code.

**Impact:** The model can make individually-correct edits that interact poorly. Without seeing the aggregate diff, it cannot catch:
- Conflicting changes across files
- Incomplete refactors (renamed in one file, not another)
- Accidental revert of earlier changes

**Recommendation:** Add a diff-injection step. When the Act phase ends (or just before Reflect begins), compute `git diff HEAD` against the pre-Act commit, and inject it as context for the Reflect phase prompt. This is a minimal change: the `git.Git` type already supports this, it just needs to be wired.

---

## Finding 4: Reflect phase has no structured test verification

**File:** `os/Skaffen/internal/tool/registry.go:63-66` (phase gate definition for Reflect)

The Reflect phase gate allows: `read`, `glob`, `grep`, `ls`, `bash`, and `edit` (rate-limited to 3, requires prompt). The `bash` tool is unrestricted, so the model *can* run tests -- but nothing in the system prompts, evidence collection, or phase orchestration actually ensures it does.

**File:** `os/Skaffen/internal/session/session.go:77-93`

The `SystemPrompt` method only injects quality history and inspiration data during the **Orient** phase. During Reflect, the model gets the base system prompt with no additional phase-specific instructions. There is no instruction to run the full test suite, verify the patch, or report test pass/fail counts.

**File:** `os/Skaffen/cmd/skaffen/main.go:186-360` (print mode)

In headless mode (`--mode print`), only a **single phase** is run per invocation (line 194-200). The external orchestrator must drive the multi-phase OODARC sequence. If it skips Reflect or doesn't provide a suitable prompt, no verification happens.

**Impact:** Whether tests run during Reflect depends entirely on the model's spontaneous behavior or the external orchestrator's prompt. There is no enforcement, no structured capture of results, and no quality gate.

**Recommendation:**
1. Add a Reflect-phase system prompt suffix that instructs the agent to run the full test suite and report results in a structured format.
2. Add a PostToolUse hook (or post-phase hook) that parses bash tool results for test framework output patterns (pytest, go test, npm test) and captures pass/fail counts.
3. Gate the transition from Reflect to Compound on test results: if tests fail, loop back to Act or abort.

---

## Finding 5: Evidence emitter does NOT capture test pass/fail counts

**File:** `os/Skaffen/internal/agentloop/types.go:77-102` (Evidence struct)

The Evidence struct captures per-turn operational metrics: tokens in/out, tool call names, file activity, stop reason, budget, complexity tier. It does **not** capture:
- Test pass/fail/error/skip counts
- Build success/failure
- Lint/vet results
- Any semantic correctness signal

**File:** `os/Skaffen/internal/mutations/signal.go:28-33` (HardSignals struct)

The `HardSignals` struct has `TestsPassed *bool` and `BuildSuccess *bool` fields, but these are **never populated**. The `Aggregate` function (`mutations/aggregate.go:27-96`) only computes `TokenEfficiency`, `TurnCount`, `ComplexityTier`, `ToolErrorRate`, and `Outcome` from the last turn. `TestsPassed` and `BuildSuccess` remain nil.

**Impact:** The quality signal feedback loop (Orient reads history from past sessions) contains zero information about patch correctness. The agent's "mutation suggestions" optimize for token efficiency and turn count -- orthogonal to actual patch quality. The Pareto front (`signal.go:90-108`) ranks sessions without any axis measuring whether the produced code actually works.

**Recommendation:**
1. Parse bash tool results during Reflect phase for test output patterns and record pass/fail counts in evidence.
2. Populate `HardSignals.TestsPassed` and `HardSignals.BuildSuccess` in `Aggregate()`.
3. Add a correctness axis to `QualitySignal.Scores()` so the Pareto front prefers sessions that produced passing patches.

---

## Finding 6: Clean git diff (no changes) is NOT detected as failure signal

**File:** `os/Skaffen/internal/agentloop/loop.go:177-213` (evidence emission)

The evidence emitter records `outcome: "success"` whenever `stop_reason == "end_turn"` (line 183-184), and `outcome: "tool_use"` when the model continues with tool calls. There is no check for whether any file modifications actually occurred.

**File:** `os/Skaffen/internal/git/git.go:27-32` (HasChanges)

`git.HasChanges()` exists and works, but is never called by the agent loop or evidence system.

**Impact:** A session where the agent reasons extensively but produces zero file changes will be recorded as `outcome: "success"`. On SWE-bench, this means a no-op patch is treated as a successful session in the quality history, polluting the Pareto front and biasing future mutation suggestions.

**Recommendation:** After the Act phase completes, check `git.HasChanges()`. If no changes exist:
1. Set `outcome: "no_patch"` in evidence
2. Return this as a failure signal to the Compound phase
3. Exclude no-patch sessions from quality signal aggregation

---

## Finding 7: No semantic verification of patch correctness

**No file -- absence of capability**

There is no mechanism to verify:
- Edge case coverage (does the fix handle boundary conditions?)
- Docstring/comment consistency with code changes
- Type annotation correctness
- Import statement validity
- Whether the patch actually addresses the issue described in the prompt

The edit tool operates purely on string matching. The model must self-evaluate correctness from its own reasoning, with no external verification beyond what it chooses to run via bash.

**Recommendation (longer-term):**
1. For Python (the SWE-bench target language): after edit, run `python3 -c "import ast; ast.parse(open('file.py').read())"` to catch syntax errors
2. Run `python3 -m py_compile file.py` for byte-compile verification
3. Consider a lightweight static analysis pass (pyflakes, ruff --check) gated to Reflect phase
4. For import verification: `python3 -c "import the_module"` after edits

---

## Finding 8: PostToolUse hooks could enable validation but are advisory-only

**File:** `os/Skaffen/internal/hooks/executor.go:109-130`

PostToolUse hooks fire after every tool execution, receive the tool name, input, result, and error status, and can run arbitrary commands. This is the natural extension point for post-edit validation. However:

1. PostToolUse hooks are **advisory** (fire-and-forget, line 353 in loop.go -- runs in a goroutine)
2. Their output is discarded -- the model never sees it
3. They run on `context.Background()` so they can outlive the turn

**Recommendation:** Add a **synchronous** PostToolUse variant for `edit` and `write` tools whose output is appended to the tool result. This lets validation hooks feed results back to the model within the same turn.

---

## Priority-Ordered Recommendations

For maximum SWE-bench impact with minimum code change:

| Priority | Finding | Change Size | Expected Impact |
|----------|---------|-------------|-----------------|
| **P0** | F1/F2: Add py_compile after edit/write for .py files | ~30 lines in edit.go/write.go | Catches syntax-broken patches immediately |
| **P0** | F6: Detect empty diff as failure | ~15 lines in agent.go | Prevents no-op "success" sessions |
| **P1** | F3: Inject aggregate diff before Reflect | ~25 lines in agent.go | Model sees cumulative effect |
| **P1** | F4: Add Reflect system prompt for test running | ~10 lines in session.go | Structured test verification |
| **P2** | F5: Populate TestsPassed in evidence | ~40 lines in aggregate.go | Quality loop learns from correctness |
| **P2** | F5: Add correctness axis to Scores() | ~5 lines in signal.go | Pareto front selects working patches |
| **P3** | F7: AST parse after Python edits | ~20 lines | Catches structural errors before tests |
| **P3** | F8: Synchronous post-edit hook variant | ~50 lines | Extensible validation pipeline |

---

## Key Architectural Observation

Skaffen's quality signal system (mutations) is **operationally sophisticated** -- Pareto fronts, task-type bucketing, cross-session inspiration, mutation suggestions. But it optimizes a proxy metric (token efficiency, turn count) rather than the target metric (patch correctness). The infrastructure is there; it just needs correctness signals plumbed through.

The gap between "9/10 produce patches" and "1/10 pass" is almost certainly dominated by:
1. Syntax errors the model cannot detect (no validation feedback)
2. Semantic errors the model never revisits (no aggregate diff review)
3. Test failures the model never runs (no Reflect phase enforcement)

These are fixable with ~150 lines of code in edit.go, write.go, agent.go, session.go, and aggregate.go.
