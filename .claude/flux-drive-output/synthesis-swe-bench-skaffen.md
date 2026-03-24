# SWE-bench Lite Readiness Review: Skaffen Synthesis

**Date:** 2026-03-15
**Target:** `os/Skaffen/` (Go-based coding agent, OODARC workflow)
**Review Scope:** Five flux-drive agents evaluated issue comprehension, localization toolchain, test validation, model routing, and patch correctness.
**Current Baseline:** 1/10 pass rate, 9/10 produce patches
**Goal:** #1 on SWE-bench Lite (~60% pass rate)

---

## Executive Summary

The 9/10 patch production vs 1/10 pass rate gap reveals a **complete separation of concerns**: Skaffen can read code and generate edits, but has no end-to-end validation framework. Five review agents identified **40 distinct findings** across 8 dimensions. The highest-priority fixes fall into three categories:

1. **Fault Localization & Understanding (P0)** — Agent cannot articulate a hypothesis before patching
2. **Test Validation & Iteration (P0)** — Agent produces patches but never validates them systematically
3. **Patch Quality Verification (P0)** — Agent receives no feedback on syntax/semantic correctness

Implementing the top 10 recommendations (effort: 20-30 hours) should yield **+20-35 percentage points** on SWE-bench Lite.

---

## Agent Findings Summary

| Agent | Focus | Key Severity | Critical Findings |
|-------|-------|--------------|------------------|
| **fd-issue-comprehension** | Orient phase, fault hypothesis, issue parsing | 7 P0/P1 | No fault hypothesis instruction (P0), bash truncation (P0), grep context (P1), FSM forward-only (P0) |
| **fd-localization-toolchain** | Code navigation efficiency, tool design | 6 CRITICAL/HIGH | Grep -C missing (P0), glob `**` broken (P0), truncation head-only (P0), no tool guidance (P0) |
| **fd-test-validation-loop** | Reflect phase, test execution, iteration | 10 CRITICAL/HIGH | No Reflect behavior (P0), no pre/post test comparison (P0), no FSM loopback (P0) |
| **fd-model-routing-calibration** | Per-turn model selection, budget management | 6 CRITICAL | Token-only complexity (P0), budget cliff (P0), SetInputTokens never called (P0) |
| **fd-patch-correctness-signals** | Edit validation, test result capture, diff review | 8 CRITICAL/P1 | No post-edit validation (P0), empty diff not detected (P0), no test capture (P1) |

**Convergence:** All 5 agents independently identified the same root causes:
- Lack of structured test validation loop
- Truncation hiding diagnostic output
- No instruction to form fault hypotheses before patching
- Tool limitations burning tokens on localization

---

## Consolidated Findings (Priority Order)

### P0: Blocking Issues (Must Fix for SWE-bench)

#### 1. **Reflect Phase Has No Behavioral Implementation** (Test-Validation-Loop F1)
- **Impact:** Agent never runs tests systematically; entire validation depends on LLM discretion
- **Severity:** CRITICAL — explains 1/10 vs 9/10 gap
- **Location:** `internal/agentloop/loop.go:95-245`, `internal/agent/agent.go:177-238`
- **Fix:** Implement `ReflectOrchestrator` that runs tests, parses exit code, classifies failures, and injects results into next turn
- **Effort:** Medium (2-3 hours)
- **Expected Impact:** +15-20 percentage points

#### 2. **No Pre/Post Test Baseline Comparison** (Test-Validation-Loop F3)
- **Impact:** Agent cannot measure whether patch improves, regresses, or has no effect
- **Severity:** CRITICAL
- **Location:** Missing feature (no code file)
- **Fix:** Capture baseline test results before Act phase; diff against post-patch results; inject `[+3 passing, -1 failing]` into Reflect
- **Effort:** Medium (2-3 hours)
- **Expected Impact:** +10-15 percentage points

#### 3. **No Fault Hypothesis Instruction in Orient** (Issue-Comprehension F1)
- **Impact:** Agent reads issue then immediately greps/reads files without articulating what's broken or where
- **Severity:** P0 — directly addresses "finds something to change but not the right thing"
- **Location:** `internal/session/session.go:77-93`, `cmd/skaffen/main.go:629-638`
- **Fix:** Add phase-specific system prompt suffix for Orient that instructs: before tool calls, emit structured fault hypothesis (symptom, mechanism, location, evidence needed)
- **Effort:** Small (1 hour) — single prompt addition
- **Expected Impact:** +5-10 percentage points

#### 4. **Bash Output Truncation Preserves Head, Loses Tail** (Issue-Comprehension F2, Localization-Toolchain F3)
- **Impact:** Test failure details (assertion diffs, tracebacks) appear at end of 15-50KB output, but 10KB cap cuts them off
- **Severity:** P0 — agent sees `FAILED` markers but not the actual error
- **Location:** `internal/tool/bash.go:14-15,67-69`
- **Fix:** Change truncation to keep both head (setup info) and tail (errors):
  ```go
  if len(output) > maxOutputBytes {
      headSize := 2048
      tailSize := maxOutputBytes - headSize
      output = output[:headSize] + "\n... (truncated) ...\n" + output[len(output)-tailSize:]
  }
  ```
- **Effort:** Small (30 minutes)
- **Expected Impact:** +5-8 percentage points

#### 5. **Phase FSM Forward-Only, No Retry Cycle** (Issue-Comprehension F4, Test-Validation-Loop F9)
- **Impact:** Agent cannot re-enter Orient after failed patch; single-pass approach prevents iterative debugging
- **Severity:** P0 — architectural blocker for multi-phase iteration
- **Location:** `internal/agent/phase.go:40-47`, `internal/agent/agent.go:177-238`
- **Fix:** Add `SetPhase(p tool.Phase)` method to FSM; implement Act-Reflect-Act cycle with configurable max iterations (e.g., 5)
- **Effort:** Medium (2-3 hours)
- **Expected Impact:** +10-15 percentage points

#### 6. **Grep Missing -A/-B/-C Context Lines** (Issue-Comprehension F3, Localization-Toolchain F1)
- **Impact:** Every grep requires separate read call to see context; wastes 5-20K tokens per session
- **Severity:** P0 for efficiency — agent can work around but at high cost
- **Location:** `internal/tool/grep.go:14-19,81-96`
- **Fix:** Add `context`, `before_context`, `after_context` int parameters; emit `-C N`, `-B N`, `-A N` flags
- **Effort:** Small (1 hour)
- **Expected Impact:** +3-5 percentage points (efficiency, fewer wasted turns)

#### 7. **No Post-Edit Syntax Validation** (Patch-Correctness F1-F2)
- **Impact:** Agent produces syntactically broken patches without feedback; model cannot self-correct
- **Severity:** P0 — directly causes syntax errors in 1/10 passing patches
- **Location:** `internal/tool/edit.go:36-75`, `internal/tool/write.go:32-58`
- **Fix:** After edit/write, run `python3 -c "import py_compile; py_compile.compile('file.py')"` for .py files; return validation result as tool output
- **Effort:** Small (30 minutes)
- **Expected Impact:** +3-5 percentage points

#### 8. **Empty Diff Not Detected** (Patch-Correctness F6)
- **Impact:** No-op sessions (all reasoning, no edits) recorded as "success" in quality history
- **Severity:** P0 — pollutes Pareto front, biases mutations
- **Location:** `internal/agentloop/loop.go:177-213`, `internal/git/git.go:27-32`
- **Fix:** After Act phase, check `git.HasChanges()`. If false, set `outcome: "no_patch"` in evidence; exclude from quality aggregation
- **Effort:** Small (15 minutes)
- **Expected Impact:** +2-3 percentage points

#### 9. **Glob `**` Pattern Silently Broken** (Localization-Toolchain F2)
- **Impact:** Agent cannot recursively discover Python files in multi-level packages; falls back to bash find
- **Severity:** P0 for repo structure discovery
- **Location:** `internal/tool/glob.go:48-49`
- **Fix:** Replace `filepath.Glob` with `github.com/bmatcuk/doublestar/v4` or implement `filepath.WalkDir + filepath.Match` fallback
- **Effort:** Small (1 hour, includes dependency)
- **Expected Impact:** +2-3 percentage points

#### 10. **SetInputTokens Never Called** (Model-Routing F6)
- **Impact:** Complexity classifier receives `inputTokens=0`, shadow mode logs garbage data, enforce mode would demote all turns to Haiku
- **Severity:** Critical bug for future routing infrastructure
- **Location:** `internal/router/router.go:152-155`, `internal/agentloop/loop.go:121`
- **Fix:** Add `TokenCount int` to `SelectionHints` struct; in agentloop, set before calling `router.SelectModel()`
- **Effort:** Small (30 minutes)
- **Expected Impact:** +0% now (shadow mode), critical for future

---

### P1: High-Priority Improvements

#### 11. **Grep Defaults to File-List Mode** (Issue-Comprehension F3)
- **Impact:** Lost context forces second tool call per match
- **Fix:** Change default output_mode to `"content"` for Orient/Observe phases
- **Effort:** 30 minutes
- **Expected Impact:** +1-2 percentage points

#### 12. **No Structural Issue Parsing** (Issue-Comprehension F5)
- **Impact:** Raw GitHub issue text lacks labels (symptom, reproduction steps, traceback)
- **Fix:** Wrap issue with markdown headers: `## Issue\n##Traceback\n...`
- **Effort:** 1 hour
- **Expected Impact:** +1-2 percentage points

#### 13. **Observe Phase Unreachable** (Issue-Comprehension F7)
- **Impact:** Read-only comprehension phase not available in print mode
- **Fix:** Add `tool.PhaseObserve` to phase validation at `main.go:196`
- **Effort:** 5 minutes (one line)
- **Expected Impact:** +0% (architectural clarity, enables structured pre-analysis)

#### 14. **No System Prompt Tool Guidance** (Localization-Toolchain F5)
- **Impact:** Agent must re-discover effective search strategies on every task
- **Fix:** Add built-in system prompt element teaching: glob for repo structure, grep for file discovery, grep context mode, read with offset/limit
- **Effort:** 2 hours (priompt integration + testing)
- **Expected Impact:** +3-5 percentage points

#### 15. **No Test Framework Output Parsing** (Test-Validation-Loop F2)
- **Impact:** bash tool returns unstructured text; LLM must parse pytest output manually
- **Severity:** Blocks reliable test result capture
- **Fix:** Add structured `TestResult` response from bash when command contains `test`, `pytest`, etc.; parse exit code + output for failure classification
- **Effort:** Medium (2-3 hours, multiple test framework support)
- **Expected Impact:** +3-5 percentage points

#### 16. **No Hypothesis Retry Budget** (Test-Validation-Loop F4)
- **Impact:** Agent can spend all turns on one wrong file/approach without triggering course correction
- **Fix:** Track per-hypothesis attempts (same file + fix pattern = one hypothesis); after 3 failures, force different approach
- **Effort:** Medium (2 hours)
- **Expected Impact:** +2-3 percentage points

#### 17. **CombinedOutput Interleaves Stderr/Stdout** (Localization-Toolchain F4)
- **Impact:** Tracebacks and test output appear in arbitrary order
- **Fix:** Capture stdout and stderr separately; label clearly in output
- **Effort:** 1 hour
- **Expected Impact:** +1-2 percentage points

#### 18. **Read Tool Lacks Total Line Count** (Localization-Toolchain F6)
- **Impact:** Agent doesn't know if it's read file fully (e.g., 2000/5000 lines)
- **Fix:** After read, append `[Showing lines N-M of P total]`
- **Effort:** 30 minutes
- **Expected Impact:** +1 percentage point

#### 19. **Quality History Lacks Localization Strategy** (Issue-Comprehension F6)
- **Impact:** Mutations cannot teach which fault-finding approaches worked
- **Fix:** Extend `QualitySignal` with `LocalizationTrace` (strategy, files_explored, hypothesis_revisions)
- **Effort:** 2 hours
- **Expected Impact:** +2-3 percentage points (future learning)

#### 20. **Budget Demotion Is Binary Cliff** (Model-Routing F4)
- **Impact:** At 80%, system jumps from Opus to Haiku; loses context comprehension mid-task
- **Fix:** Implement stepped demotion: 80% -> Sonnet, 95% -> Haiku; add phase-awareness (never demote during Reflect)
- **Effort:** 1 hour
- **Expected Impact:** +1-2 percentage points (if budget is tight)

---

### P2: Quality Improvements (Post-Baseline)

#### 21. **No Aggregate Diff Review** (Patch-Correctness F3)
- **Impact:** Agent sees individual edits but not cumulative effect across files
- **Fix:** Before Reflect, inject `git diff HEAD` as context
- **Effort:** 1 hour
- **Expected Impact:** +2-3 percentage points

#### 22. **TestsPassed/BuildSuccess Never Populated** (Patch-Correctness F5, Test-Validation-Loop F7)
- **Impact:** Quality signal feedback loop optimizes for token efficiency, not correctness
- **Fix:** Populate `HardSignals.TestsPassed` in `Aggregate()` by parsing bash results
- **Effort:** 1 hour
- **Expected Impact:** +1-2 percentage points (future learning)

#### 23. **Reflect Phase Lacks System Prompt** (Patch-Correctness F4)
- **Impact:** No instruction to run tests; depends on LLM discretion
- **Fix:** Add Reflect-phase system prompt suffix: "Run full test suite, report pass/fail counts in structured format"
- **Effort:** 30 minutes
- **Expected Impact:** +2-3 percentage points

#### 24. **Budget Tracker Has No Shadow Analysis** (Model-Routing F3)
- **Impact:** Cannot tell if complexity classifier would cause misrouting
- **Fix:** Add tool to analyze shadow data: "Would have demoted X% of turns"
- **Effort:** 1 hour
- **Expected Impact:** +0% (visibility only)

#### 25. **Complexity Tier Uses Token Count Only** (Model-Routing F1)
- **Impact:** Misroutes if enforce mode enabled (ties reasoning difficulty to input length, not task complexity)
- **Fix:** Use task features: files touched, tool call density, error rate, phase context
- **Effort:** 2-3 hours
- **Expected Impact:** +0% now (all Opus); critical for post-baseline optimization

---

## Convergence Analysis

**Cross-Agent Consensus (mentioned by 3+ agents):**
- Bash output truncation (Findings 1,2,4,15) — unanimous
- Reflect phase lacks structure (Findings 1,2,9) — unanimous
- Grep context lines needed (Findings 3,1,14) — unanimous
- Fault hypothesis instruction missing (Findings 5,1) — strong
- Tool guidance in system prompt needed (Findings 2,1,14) — strong
- No pre/post test comparison (Findings 3,5) — strong

**Single-Agent Findings (architectural insights):**
- FSM is forward-only (Issue-Comprehension)
- Glob `**` broken (Localization-Toolchain)
- SetInputTokens never called (Model-Routing) — critical infrastructure bug

---

## Implementation Roadmap

### Phase 1: Foundational (Effort: 15-20 hours, Expected: +20-30%)
**Implement in this order** — each enables the next:

1. **Add fault hypothesis instruction to Orient** (1h) — enables agent to form better hypotheses before exploring
2. **Fix bash truncation** (0.5h) — agent can now see test failures
3. **Implement Reflect orchestrator** (3h) — structured test running and validation
4. **Add pre/post test baseline** (2.5h) — agent can measure patch progress
5. **Add post-edit syntax validation** (0.5h) — agent gets feedback on broken edits
6. **Detect empty diff** (0.25h) — prevents no-op sessions
7. **Add SetInputTokens wiring** (0.5h) — fixes shadow data collection
8. **Fix FSM to enable Act-Reflect-Act** (3h) — agent can iterate
9. **Add grep context lines** (1h) — reduces localization token waste
10. **Fix glob `**` pattern** (1h) — enables repo structure discovery

### Phase 2: Polish (Effort: 10-15 hours, Expected: +3-8%)
11. Structured issue parsing
12. Observe phase unreachable fix
13. Add system prompt tool guidance
14. Test framework output parsing
15. Hypothesis retry budgeting
16. Quality history localization strategy

### Phase 3: Optimization (Post-baseline, 40%+ pass rate)
17. Complexity tier feature engineering
18. Budget demotion step function
19. Aggregate diff review
20. Quality signal correctness axis

---

## Estimated Timeline

| Phase | Hours | Pass Rate Projection | Confidence |
|-------|-------|----------------------|------------|
| Baseline (current) | 0 | 1/10 (10%) | High |
| Phase 1 (all 10) | 15-20 | 4-6/10 (40-60%) | High |
| Phase 1 + Phase 2 (all 15) | 25-35 | 5-7/10 (50-70%) | Medium |
| + Phase 3 (all 25) | 40-55 | 6-8/10 (60-80%) | Low (depends on convergence patterns) |

**Top 5 bang-for-buck fixes** (effort 5 hours, expect +15-20%):
1. Fault hypothesis instruction (1h)
2. Bash truncation fix (0.5h)
3. Reflect orchestrator (3h)
4. Pre/post test baseline (2.5h)
5. Post-edit syntax validation (0.5h) + empty diff detection (0.25h)

---

## Key Architectural Insights

### Observation: Mutation System Over-Engineered, Under-Fed
The quality signal pipeline (Pareto front, task-type bucketing, inspiration injection) is sophisticated but starved of data. It optimizes for:
- Token efficiency
- Turn count
- Tool error rate

It should also optimize for:
- Patch correctness (syntax valid, tests pass)
- Localization accuracy (hypothesis matches actual fault location)
- Iteration effectiveness (improvement per turn)

**Fix:** Plumb correctness signals through to `QualitySignal` and `Pareto.Scores()`. Current infrastructure will handle it.

### Observation: Reflect Phase Is Ghost Code
The Reflect phase exists as a concept (system prompt gate, tool registry entry, phase constant) but has zero behavioral implementation. It's a placeholder that the LLM tries to fill in on its own. This is the primary blocker.

### Observation: Print Mode Assumes External Orchestration
The headless print mode works for single-phase invocation, but SWE-bench needs multi-phase. The harness must orchestrate Observe -> Orient -> Act -> Reflect -> Compound, but the tool doesn't support this well. **Fix:** Add `--swe-bench` mode or wire up multi-phase in runPrint.

### Observation: Truncation Is Everywhere
Bash truncates at 10KB, grep truncates at 10KB, evidence emission truncates field sizes. The design assumes "if output is big, the model doesn't need it." Reality: SWE-bench needs the tail (errors) not the head (setup).

---

## Risk Assessment

**Low Risk (implement immediately):**
- Fault hypothesis instruction — pure system prompt, no code change
- Bash truncation — changes a constant and 5 lines of logic
- Post-edit syntax validation — isolated tool feature
- Empty diff detection — small logic addition
- SetInputTokens wiring — ~10 lines

**Medium Risk (test in staging):**
- Reflect orchestrator — new control flow, affects phase lifecycle
- Pre/post test baseline — requires test framework detection, parsing
- FSM phase loopback — architectural change to phase FSM
- Grep context lines — new parameter, ripples through schema

**High Risk (implement carefully):**
- System prompt tool guidance — if too verbose, could exceed budget; needs priompt integration
- Test framework parsing — brittle across pytest/go test/jest; requires robust regex
- Hypothesis retry budgeting — complex state tracking; risk of false positives

---

## Success Criteria

| Metric | Current | Target | Confidence |
|--------|---------|--------|------------|
| Pass Rate | 1/10 (10%) | 6/10 (60%) | Medium |
| Patch Production | 9/10 (90%) | 8/10 (80%) | High (some sessions will fail earlier if hypothesis is detected wrong) |
| Avg Turns per Task | ~50 | ~40-45 | Medium |
| Avg Token Usage | ~35K | ~30-35K | Low (may increase due to test validation) |
| False Negatives (patch works but test doesn't run) | ~40% | <5% | High (Reflect orchestrator will fix) |

---

## Appendix: Full Finding Map

**By Severity:**
- P0 (critical, blocks progress): Findings 1-10
- P1 (high priority): Findings 11-20
- P2 (quality polish): Findings 21-25

**By Category:**
- Localization (Findings 1, 3, 6, 9, 11, 12, 13, 14, 19): Agent cannot find the right code
- Validation (Findings 2, 4, 5, 7, 8, 15, 16, 21, 23): Agent cannot verify patches work
- Efficiency (Findings 6, 11, 17, 18): Token/turn waste
- Routing (Findings 10, 20, 24, 25): Model selection correctness

**By Effort:**
- <1 hour (quick wins): Findings 7, 13, 8, 11, 23, 18, 17
- 1-2 hours: Findings 1, 3, 4, 9, 12, 14, 21, 22, 24
- 2-3 hours: Findings 2, 5, 15, 19, 25
- 3+ hours: Findings 6, 10

---

## Verdict

Skaffen is **architecturally sound but incomplete**. The OODARC phase framework, tool registry, git integration, and quality signal system are well-designed. The gaps are:

1. **Missing behavioral implementations** for Reflect and test validation
2. **Truncation design** that loses diagnostic data
3. **No instruction** to form hypotheses before exploring
4. **Tool parameter gaps** (grep context, glob `**`, etc.)

These are **not fundamental problems**; they are **fixable with 20-30 hours of targeted development**. The estimated +20-35 percentage point improvement is achievable and confidence is **high** for reaching 40-50%, **medium** for reaching 60%.

**Recommendation:** Implement Phase 1 (top 10 findings) immediately. This is low-risk, high-impact, and will establish whether 60% is an achievable goal. Then assess Phase 2/3 based on observed trajectory.
