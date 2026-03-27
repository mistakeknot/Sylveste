---
artifact_type: reflection
bead: Sylveste-ekh
stage: reflect
category: patterns
date: 2026-03-09
title: Interhelm Plugin Sprint Learnings
relevance: plugin-development, shell-hooks, quality-gates
---
# Interhelm Plugin Sprint Learnings

## What We Built

New Interverse plugin (interhelm) teaching the "agent-as-operator" pattern — 3 skills, 1 reviewer agent, 3 PostToolUse hooks, Rust templates for diagnostic server + CLI client. 32 files, 4072 lines.

## Key Learnings

### 1. PostToolUse Hook Input Contract

**Problem:** Plan initially used `$TOOL_INPUT` environment variable for hook stdin parsing. PostToolUse hooks receive JSON on stdin (`{"tool_name", "tool_input", "tool_response"}`), not via env vars.

**Impact:** Caught by flux-drive plan review (P0). Would have caused all 3 hooks to silently fail.

**Rule:** Always parse `$(cat)` or `HOOK_INPUT=$(cat)` in PostToolUse hooks, never `$TOOL_INPUT`.

### 2. Shell `echo` vs `printf` for JSON Piping

**Problem:** `echo "$HOOK_INPUT" | python3 -c "..."` corrupts JSON containing `\n` or `\\` because `echo` interprets escape sequences.

**Fix:** Use `printf '%s' "$HOOK_INPUT" | python3 -c "..."` for binary-safe piping.

**Rule:** Never pipe untrusted data through `echo` — always use `printf '%s'`.

### 3. Shell Variable Interpolation into Python

**Problem:** `bump-version.sh` interpolated `$VERSION` directly into a `python3 -c "..."` string. A crafted version string can escape the string literal and execute arbitrary Python code.

**Fix:** Pass via `sys.argv[1]`: `python3 -c "import sys; v=sys.argv[1]; ..." "$VERSION"`

**Rule:** Never interpolate shell variables into inline Python/Ruby/etc code strings. Pass as arguments.

### 4. Mutex Poisoning Cascade in Rust Templates

**Problem:** `state.lock().unwrap()` in all handlers means if any handler panics while holding the lock, the mutex is poisoned and ALL subsequent requests panic — total diagnostic server failure.

**Fix:** `state.lock().unwrap_or_else(|e| e.into_inner())` recovers from poisoned mutex.

**Rule:** In shared-state HTTP servers, always recover from poisoned mutexes rather than propagating panics.

### 5. Hook Guard Ordering Matters for Performance

**Problem:** `cuj-reminder.sh` checked if the command was `git commit` (parsing stdin JSON) before checking if the project even had a diagnostic server. On non-interhelm projects, this wastes stdin parsing on every commit.

**Fix:** Check project guard (CLAUDE.md grep) first, then parse stdin only if relevant.

**Rule:** In hooks that fire broadly, check the cheapest guard (file existence) before the expensive one (stdin parsing).

### 6. Stdin Drain Required Even When Unused

**Problem:** `browser-on-native.sh` didn't read stdin at all. When the Claude hook runtime pipes JSON to PostToolUse hooks, not draining stdin can block the runtime's pipe buffer, especially with large payloads (screenshots).

**Fix:** `cat > /dev/null` at the top of any hook that doesn't need stdin.

**Rule:** Every PostToolUse hook must drain stdin, even if it doesn't use the data.

## Process Observations

- **Flux-drive plan review before execution** caught the P0 stdin contract issue, saving a full rewrite cycle
- **Quality gates after execution** caught 5 blocking issues the plan review missed (shell injection, mutex poisoning, echo corruption) — different review stages catch different issue classes
- **Multi-agent review** had zero conflicts across 4 agents examining the same code — independent discovery with consistent conclusions about the same problem areas (handlers.rs concurrency)
- **Template code needs the same review rigor as production code** — templates become production code in user projects
