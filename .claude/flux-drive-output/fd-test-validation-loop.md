# Flux Drive: Test Validation Loop

**Reviewer focus:** How Skaffen runs tests after a patch, interprets failure output, decides to retry or give up, and avoids convergence to a non-passing local minimum.

**Verdict: The Reflect phase is structurally hollow.** Skaffen has no programmatic test validation loop. The "Reflect" phase is a system prompt concept with tool gating, but there is no agent-driven test-run-interpret-retry cycle implemented in code. The entire test validation burden falls on whatever the LLM decides to do with a bash tool in a single-shot loop, with no structured feedback or convergence control.

---

## Finding 1: Reflect Phase Has No Behavioral Implementation

**Severity: CRITICAL**
**Files:** `os/Skaffen/internal/agent/agent.go:177-238`, `os/Skaffen/internal/agentloop/loop.go:95-245`

The Reflect phase is not a distinct code path. `Agent.Run()` at line 177 delegates to `agentloop.Loop.RunWithContent()` with a `SelectionHints{Phase: "reflect"}` hint. The inner loop at `loop.go:111-242` is a generic Decide-Act loop that runs identically regardless of phase. There is no phase-specific orchestration: no test invocation, no output parsing, no pass/fail classification, no retry decision tree.

The only phase-aware behavior is:
- Tool gating (`gated_registry.go:18`): Reflect gets `read, glob, grep, ls, bash, edit(rate-limited to 3)`
- Model selection (`router.go:25`): Reflect defaults to Opus
- System prompt construction (`session.go:79`): Only Orient gets extra quality history; Reflect gets the bare system prompt

**Recommendation:** Implement a `ReflectOrchestrator` that wraps the inner loop with structured test execution. Minimum viable: (1) run the project's test command, (2) parse exit code + output, (3) classify the result as pass/fail/env-error, (4) if fail, inject the failure diff into the next LLM turn, (5) enforce a hypothesis retry budget.

---

## Finding 2: No Distinction Between Environment Failure, Test Runner Failure, and Logic Failure

**Severity: CRITICAL**
**Files:** `os/Skaffen/internal/tool/bash.go:41-92`

The bash tool returns a flat `ToolResult{Content: "exit code: N\n<output>", IsError: exitCode != 0}` at line 88-91. There is no structured classification of what failed. A `ModuleNotFoundError` (environment), `pytest: command not found` (test runner), `FAILED test_foo.py::test_bar` (logic failure), and `Segmentation fault` (crash) all arrive as identical unstructured text blobs to the LLM.

The LLM must parse raw bash output to determine what happened, but the system prompt provides no guidance on this classification. The output is also truncated to 10KB (`maxOutputBytes = 10240` at line 16), which can cut off the actual failure details in large test suites.

**Recommendation:** Add a `TestRunner` tool or a structured wrapper around bash that:
- Separates stderr from stdout
- Classifies exit codes (0=pass, 1=test failure, 2=usage error, 127=command not found, 139=segfault)
- Parses common test frameworks (pytest, go test, jest) for structured failure extraction
- Returns a structured result: `{status: "fail", framework: "pytest", failures: [{test: "...", error: "...", diff: "..."}], env_errors: [...]}`

---

## Finding 3: No Pre-Patch vs Post-Patch Test Comparison

**Severity: CRITICAL**
**Files:** `os/Skaffen/internal/agent/agent.go:177-238` (entire Run flow)

There is no mechanism to capture a baseline test run before patching and compare it with a post-patch test run. The agent has no concept of "which tests were already failing" vs "which tests my patch broke" vs "which tests my patch fixed." Without this, the agent cannot determine whether its changes caused a regression, made progress, or had no effect.

The `Evidence` struct (`agentloop/types.go:77-102`) tracks tool calls, token usage, and timing, but nothing about test outcomes (pass count, fail count, newly passing/failing tests).

**Recommendation:** Before Act phase begins, run the test suite and store the baseline as a structured artifact (test name -> pass/fail map). After each patch attempt in Reflect, run the suite again and diff against baseline. Surface the delta: "2 newly passing, 0 newly failing, 47 unchanged" vs "1 newly failing (regression)." This single change would be the highest-impact improvement for SWE-bench.

---

## Finding 4: No Per-Hypothesis Retry Limit

**Severity: HIGH**
**Files:** `os/Skaffen/internal/agentloop/loop.go:111` (`for turn < l.maxTurns`)

The only loop control is a global `maxTurns` counter (default 100, set at `cmd/skaffen/main.go:49`). There is no concept of "hypothesis" or "attempt." The agent can spend all 100 turns trying variations of the same wrong fix approach without any mechanism to detect or interrupt this pattern.

The `tool/registry.go:237-252` rate limit on edit in Reflect phase (3 calls) is a weak approximation, but it's per-phase-session, not per-hypothesis. There is no detection of: "I've tried 3 different edits to the same file and tests still fail in the same way."

**Recommendation:** Implement hypothesis tracking:
- Each distinct edit pattern (target file + change type) is a hypothesis
- Track test results per hypothesis: `hypothesis_id -> [attempt_1_result, attempt_2_result, ...]`
- If a hypothesis fails 3 times, mark it exhausted and force the agent to try a different approach (different file, different function, different fix strategy)
- Emit a structured "hypothesis abandoned" event to the Evidence system

---

## Finding 5: Git Snapshot/Revert Is Primitive and Disconnected from Reflect

**Severity: HIGH**
**Files:** `os/Skaffen/internal/git/git.go:35-49`

The git module provides `AutoCommit()` (line 35) and `Undo()` (line 46, which does `git reset --soft HEAD~1`). However:

1. `Undo()` only reverts the most recent commit. There is no multi-level undo or named snapshots.
2. There is no mechanism to create pre-patch checkpoints automatically. The git module is not called from the agent loop at all -- it is a tool available to the LLM, not integrated into the phase lifecycle.
3. The LLM must decide to use git operations itself. Nothing prevents the agent from making 5 patches without committing, losing the ability to revert to any intermediate state.
4. There is no `git stash`, `git tag`, or branch-based isolation for hypothesis exploration.

**Recommendation:** Integrate git snapshots into the Act/Reflect lifecycle:
- Auto-commit before every test run (tagged as `skaffen/attempt-N`)
- If tests fail and the agent wants to try a different approach, revert to the pre-attempt tag
- Maintain a stack of attempt tags so the agent can backtrack to any previous state
- Add `DiffBetweenAttempts(a, b int)` to help the agent understand what changed between attempts

---

## Finding 6: No Structured Detection of Environment Bootstrap Failures

**Severity: HIGH**
**Files:** `os/Skaffen/internal/tool/bash.go:41-92`, `os/Skaffen/internal/agent/agent.go:177`

When running SWE-bench tasks, common environment issues include:
- Virtual environment not activated
- Dependencies not installed
- Wrong Python version
- Missing test fixtures or data files
- Database not running

All of these manifest as bash tool errors with `IsError: true`, indistinguishable from actual test failures. The agent can waste its entire turn budget trying to "fix" code when the actual problem is environmental setup.

There is no pre-flight environment check in the Reflect phase, no structured error taxonomy, and no early termination when environment setup fails repeatedly.

**Recommendation:** Add an environment validation step at the start of Reflect:
1. Run a minimal smoke test (e.g., `python -c "import <module>"`) before running the full test suite
2. If the smoke test fails with import/path errors, classify as environment failure and attempt environment repair (install deps, activate venv) before re-running
3. If environment repair fails 3 times, abort with a structured error rather than burning turns
4. Track environment health in Evidence so the Compound phase can learn from bootstrap patterns

---

## Finding 7: The Compound Phase Cannot Learn Test Failure Patterns

**Severity: MEDIUM**
**Files:** `os/Skaffen/internal/mutations/aggregate.go:27-96`, `os/Skaffen/internal/mutations/signal.go:17-46`

The `QualitySignal` struct has `TestsPassed *bool` and `BuildSuccess *bool` fields (signal.go:29-30), but `Aggregate()` (aggregate.go:27-96) never populates them. They are always nil. The aggregator only computes:
- Token efficiency (line 70-71)
- Turn count (line 72)
- Max complexity tier (line 79)
- Tool error rate (line 86)
- Last turn outcome (line 89)

Since test pass/fail data is never captured in quality signals, the Compound->Orient feedback loop (mutations/mutate.go, mutations/inspire.go) cannot learn from test outcomes. The `Suggest()` function (mutate.go:15-98) gives advice based on turn count and token efficiency, not whether tests passed.

**Recommendation:** Populate `TestsPassed` and `BuildSuccess` in `Aggregate()`:
- Scan evidence for bash tool calls that look like test invocations (heuristic: command contains "test", "pytest", "go test", etc.)
- Check the exit code of the last test run
- Add `TestsPassedCount`, `TestsFailedCount` fields to `HardSignals` for richer signal
- Use test outcome data in `Suggest()` to give approach-specific advice ("Previous sessions that passed tests used X approach")

---

## Finding 8: Phase Softening Allows Edit in Reflect But Without Strategic Guidance

**Severity: MEDIUM**
**Files:** `os/Skaffen/internal/tool/registry.go:63-66`

The Reflect phase allows `edit` with `{RateLimit: 3, RequirePrompt: true}` (registry.go:65). This is a reasonable safety valve -- the agent can make small corrections discovered during review. However:

1. The rate limit resets if the agent is restarted or the loop re-enters Reflect (registry.go:117-121 `ResetRateCounts()`)
2. There is no semantic constraint -- the 3 edits could all be to the same file, all trying the same broken approach
3. `RequirePrompt: true` only matters in TUI mode (trust evaluator). In headless/print mode (SWE-bench), the trust evaluator is nil, so edits proceed without approval
4. The system prompt doesn't tell the model that edits in Reflect are rate-limited or what they should be used for

**Recommendation:** Make the edit constraint smarter for SWE-bench:
- Instead of a flat rate limit, track edit targets: "3 edits to distinct locations" vs "3 edits to the same spot"
- If 2 edits to the same location both followed by failing tests, block further edits to that location (force a different approach)
- Inject the rate limit into the tool description so the LLM knows it has limited edits: "You have N remaining edit attempts in this phase"

---

## Finding 9: The Phase FSM Is Forward-Only -- No Act-Reflect-Act Cycle

**Severity: HIGH**
**Files:** `os/Skaffen/internal/agent/phase.go:10-52`

The phase FSM (`phase.go:20-52`) is strictly linear: Observe -> Orient -> Decide -> Act -> Reflect -> Compound. `Advance()` (line 40) only moves forward. There is no way to return from Reflect to Act for another iteration.

For SWE-bench, the desired cycle is: Act (patch) -> Reflect (test) -> if fail, Act (new patch) -> Reflect (test) -> ... until pass or budget exhausted. The current architecture forces a single Act phase followed by a single Reflect phase, with no loopback.

The only looping happens within a single phase via the inner `agentloop.Loop` (which can make multiple tool calls), but this is a Decide-Act loop within one phase, not a cross-phase iteration.

**Recommendation:** Add phase loopback to the FSM:
- Allow `Reflect -> Act` transition when tests fail (in addition to `Reflect -> Compound` when tests pass)
- Add `Rewind(target Phase)` method to `phaseFSM` that validates only backward transitions
- Track iteration count per Act-Reflect cycle with a configurable max (e.g., 5 cycles)
- The Reflect phase's final output should be a structured verdict: `{action: "retry", reason: "2 tests still failing"}` or `{action: "advance", reason: "all tests pass"}`

---

## Finding 10: Headless Print Mode Has No Test-Aware Orchestration

**Severity: HIGH**
**Files:** `os/Skaffen/cmd/skaffen/main.go:186-360`

In `runPrint()` (main.go:186), the agent is launched with a single `a.Run(ctx, expandedPrompt)` call (line 329). There is no pre-run test baseline, no post-run test verification, no multi-phase orchestration. The print mode starts at whatever `--phase` is specified (default "act") and runs the inner loop until `end_turn` or `maxTurns`.

For SWE-bench, the harness calls skaffen once in print mode. The entire problem-solving lifecycle -- reading the issue, understanding the codebase, writing a patch, running tests, iterating -- must happen within that single `Run()` call, mediated entirely by the LLM's judgment about when and how to test.

**Recommendation:** Add a `--swe-bench` or `--test-loop` mode to print that:
1. Runs an initial test baseline
2. Enters an Act-Reflect cycle with structured test comparison
3. Enforces per-hypothesis retry limits
4. Auto-creates git snapshots between attempts
5. Produces a structured output (patch file + test results) rather than just text

---

## Summary: Priority-Ordered Recommendations

| Priority | Finding | Impact on SWE-bench | Effort |
|----------|---------|---------------------|--------|
| P0 | F3: No pre/post test comparison | Cannot measure patch progress | Medium |
| P0 | F9: No Act-Reflect-Act cycle | Single-shot patching, no iteration | Medium |
| P0 | F1: Reflect has no behavioral impl | Tests are entirely LLM-discretionary | High |
| P1 | F2: No failure classification | LLM misdiagnoses env errors as code bugs | Medium |
| P1 | F4: No per-hypothesis retry limit | Burns turns on dead-end approaches | Medium |
| P1 | F5: Git snapshots disconnected | Cannot cleanly backtrack | Low |
| P1 | F6: No env bootstrap detection | Wastes turns on setup issues | Medium |
| P2 | F10: Print mode has no test orchestration | No structured SWE-bench workflow | Medium |
| P2 | F7: Compound cannot learn test patterns | No cross-session test learning | Low |
| P2 | F8: Edit softening lacks strategy | Rate limit is blunt, not smart | Low |

The root cause of the 1/10 pass rate despite 9/10 patch production is clear: Skaffen produces patches but has no structured mechanism to validate them against tests, compare pre/post results, or iterate when tests fail. The agent is making one shot at a fix and stopping, when SWE-bench success requires iterative refinement guided by test feedback.
