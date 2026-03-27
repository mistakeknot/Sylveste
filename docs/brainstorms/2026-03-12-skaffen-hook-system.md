# Brainstorm: Skaffen Hook System (Sylveste-6i0.2)

**Bead:** Sylveste-6i0.2
**Date:** 2026-03-12

## Problem

Skaffen has zero extensibility points. All 5 competitors (Claude Code, Codex CLI, Gemini CLI, OpenCode, Amp) have lifecycle hooks. Users cannot:
- Run scripts at session start (e.g., env validation, project setup)
- Gate tool execution (e.g., block `rm -rf` project-wide)
- React to tool completion (e.g., log, notify, audit)
- Receive notifications on events (e.g., errors, phase changes)

## Design Space

### Hook Events (4 minimum)

| Event | Fires When | Can Block? | Input |
|-------|-----------|------------|-------|
| **SessionStart** | Before TUI renders or agent starts | No (advisory) | session_id, work_dir, mode |
| **PreToolUse** | Before each tool executes | Yes (allow/deny) | tool_name, tool_input |
| **PostToolUse** | After each tool completes | No (advisory) | tool_name, tool_input, tool_result, is_error |
| **Notification** | On errors, phase changes, budget warnings | No (advisory) | event_type, message, severity |

### Config Format

Follow Claude Code's `hooks.json` schema — proven pattern, familiar to users:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "bash",
        "hooks": [
          {
            "type": "command",
            "command": ".skaffen/hooks/validate-bash.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### Config Hierarchy

Two levels (matches existing plugins.toml pattern):
1. `~/.skaffen/hooks.json` — user-global hooks
2. `.skaffen/hooks.json` — per-project hooks (git-committable)

**Merge strategy:** Both files loaded. Per-project hooks run AFTER global hooks. For PreToolUse, first "deny" wins (short-circuit).

### Integration Points

1. **SessionStart** — fires in `runTUI()` / `runPrint()` before agent creation. Non-blocking with timeout.
2. **PreToolUse** — wraps the existing `ToolApprover` callback in `agentloop.Loop`. Hook runs first; if hook says "deny", skip approver entirely. If hook says "allow", still run approver (hooks can't override trust policy). If hook says "ask", fall through to normal TUI approval.
3. **PostToolUse** — fires after `registry.Execute()` in `executeToolsWithCallbacks()`. Advisory only, runs in background goroutine to avoid blocking the agent loop.
4. **Notification** — fires from TUI/agent on specific events. Implemented as a simple channel that hooks subscribe to.

### Hook Execution Model

- Hooks are **external commands** (shell scripts, binaries)
- Input: JSON on stdin (event-specific payload)
- Output: JSON on stdout (for PreToolUse: `{"decision": "allow"|"deny"|"ask"}`)
- Timeout: configurable per-hook (default 10s for PreToolUse, 30s for SessionStart)
- Failure mode: hook crash/timeout → proceed (fail-open for safety)
- Env vars passed: `SKAFFEN_SESSION_ID`, `SKAFFEN_WORK_DIR`, `SKAFFEN_PHASE`

### Key Decisions

1. **Fail-open, not fail-closed.** A broken hook should not break the agent. Log warning and continue.
2. **Hooks cannot override trust.** PreToolUse hooks can deny (tighten) but cannot allow what trust blocks. Trust evaluator is the final authority.
3. **No hook chaining complexity.** Hooks within an event run sequentially. No dependency DAG.
4. **Matcher is glob-based.** `"matcher": "bash"` matches tool name. `"matcher": "*"` matches all. Same `filepath.Match` as trust.go.

## Architecture

```
internal/hooks/
  types.go      — Event enum, Config struct, HookDef struct
  loader.go     — LoadConfig(globalPath, projectPath) → merged config
  executor.go   — RunHook(ctx, event, payload) → HookResult
  executor_test.go
  loader_test.go
```

Wire into main.go:
- Load hooks after config, before agent creation
- Pass hook executor to agent via new `WithHooks()` option
- Agent passes it down to agentloop via `SetPreToolHook()` / `SetPostToolHook()`

## Not Doing

- **Hook marketplace/discovery** — just file paths, no registry
- **In-process hooks** (Go plugins, Wasm) — shell commands only for v1
- **Hook ordering guarantees** between global and project — both run, project after global
- **Hook caching/memoization** — every invocation is fresh
