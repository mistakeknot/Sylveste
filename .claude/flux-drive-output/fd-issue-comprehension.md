# fd-issue-comprehension Review

Reviewer: Cognitive systems researcher focused on fault model construction in the Orient phase.

Target: `os/Skaffen/` -- full Skaffen agent codebase.

---

## Finding 1 (P0): Orient phase has no structured fault hypothesis instruction

**Location:** `internal/session/session.go:77-93` (SystemPrompt method), `cmd/skaffen/main.go:629-638` (buildSystemPrompt)

**What happens:** The Orient phase system prompt is assembled from two sources: (a) context files (CLAUDE.md, AGENTS.md, SKAFFEN.md walked up from the working directory), and (b) quality history / inspiration data appended during Orient. Neither source injects any instruction telling the model to produce a structured fault hypothesis before tool calls.

The `buildSystemPrompt()` function at `main.go:629` calls `contextfiles.Load(workDir)` which reads generic project context files. The `SystemPrompt()` method at `session.go:77` appends quality history and inspiration only when `phase == tool.PhaseOrient`, but these are aggregate session statistics (avg turns, token efficiency, tool error rates) -- not localization-guiding instructions.

**Why this matters for SWE-bench:** Top SWE-bench solvers emit a structured fault model (file, class, method, code path) before their first tool call. This constrains the search space and prevents unfocused exploration. Without this instruction, the agent in Orient phase will read the issue, then immediately start grepping/reading files without first articulating what it thinks is broken and where. The 9/10 patch rate but 1/10 pass rate strongly suggests the agent is finding *something* to change but not correctly localizing the fault.

**Concrete failure scenario:** Agent receives a Django ORM issue describing a query generating wrong SQL. Without fault hypothesis instructions, it greps broadly for the error message, reads 5-10 files, and starts patching whichever function it finds first rather than reasoning about which ORM codepath constructs the problematic query clause.

**Recommendation:** Add a phase-specific system prompt suffix in `session.go:SystemPrompt()` when `phase == tool.PhaseOrient`. Example content:

```
Before making any tool calls, produce a structured fault hypothesis:
1. SYMPTOM: What observable behavior does the issue describe?
2. MECHANISM: What code path most likely produces this behavior?
3. LOCATION: Which file(s) and function(s) are most likely responsible?
4. EVIDENCE NEEDED: What 1-2 tool calls would confirm or refute this hypothesis?

Output this as a ```fault-hypothesis``` code block, then proceed to tool calls.
```

This is a single-hunk change in `session.go` around line 79.

---

## Finding 2 (P0): Bash tool 10KB output cap truncates diagnostic test output

**Location:** `internal/tool/bash.go:15` (`maxOutputBytes = 10240`), `internal/tool/bash.go:68-69` (truncation logic)

**What happens:** When the agent runs a test suite to reproduce a failure (standard SWE-bench workflow: `python -m pytest tests/test_foo.py -x`), test output including tracebacks, assertion diffs, and multi-line comparison output is capped at exactly 10,240 bytes. The truncation at line 68-69 hard-clips mid-content:

```go
if len(output) > maxOutputBytes {
    output = output[:maxOutputBytes] + "\n... (truncated)"
}
```

**Why this matters for SWE-bench:** Django, sympy, and scikit-learn test failures routinely produce 15-50KB of output. The most diagnostic content -- the actual assertion failure message with expected vs. actual values -- appears at the *end* of the output, after all the collection/setup noise. A 10KB cap almost guarantees the agent sees test names and collection output but not the actual failure message.

**Concrete failure scenario:** `pytest tests/db/test_queries.py -x` produces ~25KB. The agent sees `FAILED` markers and stack frames but the assertion error at line 24,000 of output is truncated. The agent then guesses at the failure cause rather than reading the precise assertion diff.

**Recommendation:** Two complementary changes:

1. **Raise the cap to 50KB** (line 15: `maxOutputBytes = 51200`). This is still well within Claude's context budget for a single tool result.
2. **Keep tail, not head:** Change the truncation logic to preserve the last N bytes where the failure summary lives:

```go
if len(output) > maxOutputBytes {
    output = "... (truncated, showing last " + strconv.Itoa(maxOutputBytes) + " bytes)\n" + output[len(output)-maxOutputBytes:]
}
```

This is a 3-line change in `bash.go`.

---

## Finding 3 (P1): Grep defaults to files_with_matches, losing surrounding context

**Location:** `internal/tool/grep.go:18` (`OutputMode` default), `internal/tool/grep.go:82-96` (`buildRgArgs`)

**What happens:** The grep tool's `output_mode` parameter defaults to `"files_with_matches"` (line 18 comment, line 88 default case), which produces only file paths. When the agent greps for a function name, error string, or code pattern during Orient/Observe, it gets a list of files but not the surrounding code context that would enable fault localization.

```go
default: // files_with_matches
    args = append(args, "-l")
```

**Why this matters for SWE-bench:** During fault localization, the agent needs to see code surrounding a match to understand the control flow and data dependencies. Getting only file paths forces a second tool call (read) for each match, burning turns and tokens. Worse, the agent must guess *which* file to read first without seeing context, often choosing wrong.

**Additionally:** Even when `output_mode: "content"` is used, there is no support for `-C`, `-A`, or `-B` context lines (the schema at line 23-33 does not expose these parameters). The `buildRgArgs` function at line 81-96 only adds `-n` for line numbers in content mode but never adds context flags.

**Recommendation:**
1. Add `context` parameter to `grepParams` struct and schema (e.g., `Context int json:"context,omitempty"`).
2. In `buildRgArgs`, when `output_mode == "content"` and `Context > 0`, add `-C <n>` to the args.
3. Consider changing the default `output_mode` to `"content"` for Orient/Observe phases (via the `PhasedTool` interface the registry already supports), while keeping `"files_with_matches"` as the default for Act phase where broad file discovery is more useful.

---

## Finding 4 (P0): OODARC FSM is strictly forward-only -- no Observe-Orient re-entry after failed patch

**Location:** `internal/agent/phase.go:40-47` (Advance method), `internal/agent/agent.go:177-238` (runWithContent -- single-phase execution)

**What happens:** The `phaseFSM.Advance()` method can only move forward through the phase sequence (Observe -> Orient -> Decide -> Act -> Reflect -> Compound). There is no `Reset()`, `GoBack()`, or `SetPhase()` method. The `Agent.Run()` method at line 177 executes the loop within a single phase -- the phase is set once via `a.fsm.Current()` at line 178 and never changes during the run.

More critically, in the headless print mode used for SWE-bench (`runPrint` at `main.go:186`), the agent is started at a single `--phase` (default `act`) and runs entirely within that phase. There is no mechanism to:
- Run Orient, get a hypothesis, then transition to Act.
- Run Act, fail a test in Reflect, then re-enter Orient with updated information.

The TUI has a `/advance` command (commands.go:201) but print mode has nothing equivalent.

**Why this matters for SWE-bench:** SWE-bench's primary failure mode is incorrect localization. When a first patch fails tests, the agent needs to revise its fault hypothesis (re-Orient) rather than iteratively modifying the same patch (staying in Act). The current architecture forces the SWE-bench harness to handle multi-phase orchestration externally, or the agent must do everything in a single Act phase without phase-gated behavioral guidance.

**Concrete failure scenario:** Agent in Act phase patches `query.py:line 42`. Test fails. Agent sees the failure and modifies the same line differently. Still fails. The cycle repeats until max turns, never stepping back to question whether `query.py` was the right file.

**Recommendation:** Add a multi-phase print mode that runs the full OODARC pipeline:

```go
// In runPrint, after prompt construction:
phases := []tool.Phase{tool.PhaseOrient, tool.PhaseAct, tool.PhaseReflect}
for _, phase := range phases {
    a.SetPhase(phase) // needs new method on Agent
    result, err = a.Run(ctx, phasePrompt(phase, prompt, lastResult))
}
```

Or, more minimally: add `SetPhase(p tool.Phase)` to the `phaseFSM` (a 3-line method) and expose it on `Agent`, enabling the SWE-bench harness to orchestrate phase transitions.

---

## Finding 5 (P1): Issue text is injected verbatim without structure

**Location:** `cmd/skaffen/main.go:202-210` (prompt reading), `cmd/skaffen/main.go:325-329` (prompt passed to Run)

**What happens:** In print mode, the prompt (which for SWE-bench is the issue text) is read from `-p` flag or stdin at lines 202-210, trimmed, and passed directly to `a.Run(ctx, expandedPrompt)` at line 329. No parsing, structuring, or annotation occurs. The raw issue text -- which typically contains a title, description, reproduction steps, expected behavior, actual behavior, and sometimes a traceback -- arrives as a single undifferentiated string.

```go
prompt = strings.TrimSpace(string(data))
// ...
result, err = a.Run(ctx, expandedPrompt)
```

**Why this matters for SWE-bench:** GitHub issues are noisy. They contain markdown formatting, user commentary, environment details, and tangential information. Top SWE-bench solvers parse the issue into structured fields (symptom, reproduction steps, expected output, actual output, traceback) and present each to the model as labeled sections. This reduces the cognitive load on the model and makes the fault hypothesis more precise.

**Recommendation:** Add an issue structuring step before `Run()` in print mode. This can be as simple as a regex-based parser that detects common GitHub issue patterns:

```go
func structureIssue(raw string) string {
    // Detect and label common sections:
    // - Lines after "Steps to reproduce" or "How to reproduce"
    // - Code blocks (```...```)
    // - Traceback lines (File "...", line N)
    // - "Expected:" / "Actual:" patterns
    structured := "## Issue\n" + raw
    if traceback := extractTraceback(raw); traceback != "" {
        structured += "\n\n## Traceback\n" + traceback
    }
    return structured
}
```

Even wrapping the issue in `## Issue Text\n<content>` headers would help the model distinguish issue text from system prompt instructions.

---

## Finding 6 (P2): Quality history injection surfaces session-level statistics, not localization strategy patterns

**Location:** `internal/session/session.go:96-132` (formatQualityHistory), `internal/mutations/signal.go:17-25` (QualitySignal struct), `internal/mutations/mutate.go:14-110` (Suggest)

**What happens:** The quality history injected during Orient (via `formatQualityHistory` at session.go:96) reports:
- Average turns
- Token efficiency
- Tool error count
- Max complexity tier
- Success/failure count

The suggestion system (`mutate.go:14-110`) generates advice like "Break into smaller steps" or "Reduce context" based on turn counts and efficiency ratios. Neither system tracks *how* the agent localized a fault (which tools it used, what search patterns worked, whether it read the traceback first vs. grepping).

**What's missing from QualitySignal (signal.go:17-25):** There is no field for:
- Localization strategy (e.g., "traceback-first", "grep-for-error", "read-test-file")
- Files touched during Orient/Observe phases
- Whether the hypothesis was revised after a failed patch
- Which tool call sequence led to correct localization

**Why this matters for SWE-bench:** The mutations system could be the mechanism by which Skaffen learns *how* to localize faults. Currently it learns *whether* sessions were efficient, but not *which fault-finding strategies worked*. A bug-fix task that succeeded in 5 turns by reading the traceback first should teach future sessions to prioritize traceback reading over broad grep.

**Recommendation:** Extend `QualitySignal` with a `LocalizationTrace` field:

```go
type QualitySignal struct {
    // ... existing fields ...
    Localization LocalizationTrace `json:"localization,omitempty"`
}

type LocalizationTrace struct {
    Strategy      string   `json:"strategy"`       // inferred: traceback-first, grep-first, test-first
    FilesExplored int      `json:"files_explored"` // count of unique files read during Orient
    TargetFile    string   `json:"target_file"`    // file that was ultimately patched
    HypothesisRevisions int `json:"hypothesis_revisions"` // how many times localization changed
}
```

Then teach `FormatSuggestions` to surface the best localization strategy for the task type.

---

## Finding 7 (P1): Observe phase is defined but unreachable from print mode

**Location:** `cmd/skaffen/main.go:195-200` (phase validation), `internal/tool/tool.go:33` (PhaseObserve constant), `internal/tool/registry.go:50-52` (Observe gate)

**What happens:** `PhaseObserve` is defined as a phase constant and has tool gates (read, glob, grep, ls), but the print mode phase validation at `main.go:195-200` explicitly excludes it:

```go
switch phase {
case tool.PhaseOrient, tool.PhaseDecide, tool.PhaseAct, tool.PhaseReflect, tool.PhaseCompound:
    // valid
default:
    return fmt.Errorf("invalid phase %q ...")
}
```

The `observe` phase is never reachable in headless print mode.

**Why this matters for SWE-bench:** The Observe phase (read-only tools, no bash) is the natural home for initial issue comprehension -- reading the issue, examining the repository structure, and building a mental model of the codebase before forming a fault hypothesis in Orient. Without it, the agent either starts in Orient (where it should already be forming hypotheses) or Act (where it can write code immediately).

**Recommendation:** Add `tool.PhaseObserve` to the valid phase list in `main.go:196`. This is a one-line change.

---

## Summary

| # | Finding | Severity | Effort | Impact on SWE-bench |
|---|---------|----------|--------|---------------------|
| 1 | No fault hypothesis instruction in Orient prompt | P0 | Small (add prompt suffix) | Directly addresses 1/10 pass rate |
| 2 | 10KB bash output truncates test failure details | P0 | Small (change constant + tail logic) | Agent can't read assertion diffs |
| 3 | Grep defaults to file-list mode, no context lines | P1 | Medium (add param + schema) | Wastes turns on localization |
| 4 | FSM is forward-only, no re-entry after failed patch | P0 | Medium (add SetPhase + orchestration) | Prevents hypothesis revision |
| 5 | Issue text injected verbatim without structure | P1 | Small (add structuring wrapper) | Reduces model's comprehension accuracy |
| 6 | Quality history lacks localization strategy data | P2 | Medium (extend signal struct) | No learning about fault-finding approaches |
| 7 | Observe phase unreachable from print mode | P1 | Trivial (one line) | Missing dedicated comprehension phase |

The highest-leverage changes are Findings 1 and 2: inject a fault hypothesis instruction into Orient's system prompt, and fix the bash output truncation so the agent can actually read test failure messages. Together these address the gap between "I read the issue" and "I know which code path is responsible" that the 1/10 pass rate reveals.
