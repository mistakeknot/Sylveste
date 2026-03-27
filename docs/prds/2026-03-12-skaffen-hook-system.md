---
artifact_type: prd
bead: Sylveste-6i0.2
stage: design
---
# PRD: Skaffen Hook System

## Problem

Skaffen has zero extensibility points. All 5 competitors (Claude Code, Codex CLI, Gemini CLI, OpenCode, Amp) ship lifecycle hooks. Users cannot run scripts at session start, gate tool execution, react to tool completion, or receive event notifications. This blocks per-project customization, audit logging, and safety guardrails.

## Solution

Add a lifecycle hook system with 4 events (SessionStart, PreToolUse, PostToolUse, Notification), external command execution, two-level config hierarchy (global + project), and fail-open semantics. Follow Claude Code's proven `hooks.json` schema for familiarity.

## Features

### F1: Hook Types & Config Loader

**What:** Define hook event types, config structs, and two-level config loading from `~/.skaffen/hooks.json` (global) and `.skaffen/hooks.json` (per-project) with merge.

**Acceptance criteria:**
- [ ] `Event` type enum with 4 values: `SessionStart`, `PreToolUse`, `PostToolUse`, `Notification`
- [ ] `Config` struct with `Hooks map[Event][]HookGroup` matching Claude Code schema
- [ ] `HookGroup` struct with `Matcher string` (glob) and `Hooks []HookDef`
- [ ] `HookDef` struct with `Type string`, `Command string`, `Timeout int` (seconds)
- [ ] `LoadConfig(globalPath, projectPath string) (*Config, error)` loads and merges both files
- [ ] Missing files are not errors (empty config)
- [ ] Per-project hooks append after global hooks within each event
- [ ] Invalid JSON returns descriptive error with file path

### F2: Hook Executor

**What:** Execute hook commands as external processes with JSON stdin/stdout, configurable timeout, and fail-open error handling.

**Acceptance criteria:**
- [ ] `Executor` struct with `Run(ctx, event Event, toolName string, payload interface{}) (*HookResult, error)`
- [ ] Hooks receive JSON payload on stdin
- [ ] PreToolUse hooks return `{"decision": "allow"|"deny"|"ask"}` on stdout
- [ ] Timeout per-hook (default 10s for PreToolUse, 30s for SessionStart, 5s for PostToolUse/Notification)
- [ ] Hook crash or timeout → log warning, return "allow" (fail-open)
- [ ] Environment variables set: `SKAFFEN_SESSION_ID`, `SKAFFEN_WORK_DIR`, `SKAFFEN_PHASE`
- [ ] Matcher filtering: only run hooks whose `Matcher` glob matches the tool name (for PreToolUse/PostToolUse) or `"*"` for all
- [ ] Sequential execution within an event; first "deny" short-circuits for PreToolUse

### F3: PreToolUse + PostToolUse Integration

**What:** Wire hook executor into `agentloop.Loop.executeToolsWithCallbacks()` so hooks gate tool execution and observe results.

**Acceptance criteria:**
- [ ] `Loop` accepts a `HookRunner` interface (or concrete executor) via `WithHooks()` option
- [ ] PreToolUse hooks run before the existing `ToolApprover` callback
- [ ] If any PreToolUse hook returns "deny", tool is blocked (skip approver)
- [ ] If PreToolUse hooks return "allow", still run approver (hooks can't override trust)
- [ ] If PreToolUse hooks return "ask", fall through to normal approval flow
- [ ] PostToolUse hooks fire after `registry.Execute()` returns, in a background goroutine
- [ ] PostToolUse receives tool name, input, result content, and is_error flag
- [ ] Agent layer passes hooks through via `agent.WithHooks()` option → `agentloop.WithHooks()`

### F4: SessionStart + Notification Integration

**What:** Fire SessionStart hooks before agent creation in main.go, and Notification hooks on errors, phase changes, and budget warnings.

**Acceptance criteria:**
- [ ] SessionStart hooks fire in `runTUI()` and `runPrint()` before agent creation
- [ ] SessionStart payload includes `session_id`, `work_dir`, `mode` ("tui" or "print")
- [ ] SessionStart hooks run with 30s timeout, non-blocking (timeout → warn and continue)
- [ ] Notification hooks fire on: agent errors, OODARC phase transitions, budget threshold warnings
- [ ] Notification payload includes `event_type`, `message`, `severity` ("info"|"warning"|"error")
- [ ] `Executor.Notify(ctx, eventType, message, severity string)` convenience method
- [ ] Notification hooks are advisory-only (no blocking, fire-and-forget in background)

## Non-goals

- Hook marketplace or discovery — hooks are just file paths
- In-process hooks (Go plugins, Wasm) — external commands only for v1
- Hook ordering guarantees between global and project beyond "project runs after global"
- Hook caching or memoization — every invocation is fresh
- Hook chaining dependencies — no DAG, just sequential execution

## Dependencies

- Existing `agentloop.ToolApprover` callback pattern (for PreToolUse wrapping)
- Existing `trust.Evaluator` (hooks layer before trust, trust is final authority)
- `filepath.Match` for glob matching (same as trust.go)
- `os/exec` for external command execution

## Open Questions

- Should PostToolUse hooks receive truncated tool results for large outputs? (Defer to implementation — start with full content, add truncation if perf issues arise)
- Should Notification hooks have a debounce for rapid-fire events? (Defer — start without, add if needed)
