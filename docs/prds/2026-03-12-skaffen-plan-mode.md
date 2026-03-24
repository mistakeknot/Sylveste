# PRD: Skaffen Plan Mode

**Bead:** Demarch-6i0.21
**Date:** 2026-03-12
**Status:** Draft
**Brainstorm:** [docs/brainstorms/2026-03-12-skaffen-plan-mode.md](../brainstorms/2026-03-12-skaffen-plan-mode.md)

## Problem Statement

Users need a safe, read-only exploration mode when working with Skaffen. Currently, the agent loop starts in Build phase (full tool access) by default. There is no way to:
- Explore an unfamiliar codebase without risk of accidental modification
- Perform impact analysis before committing to changes
- Do code review or audit in a guaranteed-safe mode
- Toggle between "thinking" and "doing" mid-session

4 of 5 competing coding agents ship plan mode (Claude Code, Codex, Gemini, Amp-partial). This is table stakes.

## Non-Goal

This is NOT a replacement for Clavain's sprint planning workflow (brainstorm → strategy → write-plan). That workflow produces planning *documents*. Plan mode provides safe *exploration* — they're complementary.

## Solution

Add a toggleable Plan Mode to Skaffen that restricts the agent to read-only tools.

### Architecture

Skaffen's existing infrastructure already supports this:
- `PhasePlan` constant exists in `internal/tool/tool.go`
- Tool gates defined: `PhasePlan → {read, glob, grep, ls}` (read-only)
- `GatedRegistry` supports swappable gate maps
- `ToolApprover` callback can intercept tool calls at runtime

### User-Facing Behavior

**Entry points:**
1. CLI: `skaffen --plan-mode` starts in plan mode
2. TUI: `Shift+Tab` toggles plan mode mid-session
3. Slash command: `/plan` toggles (matches CC/Codex convention)

**When plan mode is active:**
- Status bar shows `[PLAN]` indicator
- Write tools (write, edit) are unavailable — tool calls rejected with explanation
- Bash is unavailable — prevents accidental side effects
- Read, glob, grep, ls remain available
- Agent's system prompt includes plan-mode context ("You are in read-only exploration mode")
- Conversation context is preserved across mode transitions

**When toggling OFF plan mode:**
- Confirmation prompt: "Exit plan mode and allow modifications?"
- All tools become available per current OODARC phase gates
- Status bar returns to normal phase display

### Features

**F1: Plan mode gates (core)**
- Add `PlanModeGates` map to `gated_registry.go` — all phases get read-only tool set
- Add `planMode` field to Agent with `WithPlanMode(bool)` option
- When plan mode on, swap `DefaultGates` for `PlanModeGates`
- Add `--plan-mode` CLI flag

**F2: TUI toggle**
- Shift+Tab keybinding toggles plan mode
- Status bar shows `[PLAN]` badge (using existing Masaq status bar component)
- Exit confirmation before toggling off

**F3: System prompt injection**
- When plan mode active, prepend exploration context to system prompt
- "You are in plan mode (read-only). Explore, analyze, and explain. Do not suggest modifications — the user will toggle to build mode when ready."
- Remove plan-mode context when toggling off

## Acceptance Criteria

1. `skaffen --plan-mode` starts with read-only tools only
2. Write/edit/bash tool calls are rejected with "plan mode active" message
3. Shift+Tab toggles between plan and normal mode mid-session
4. Status bar shows `[PLAN]` when active
5. Conversation context preserved across toggles
6. Spawned subagents inherit plan mode restriction

## Effort Estimate

| Feature | Hours | Risk |
|---------|-------|------|
| F1: Plan mode gates | 2 | Low |
| F2: TUI toggle | 2.5 | Low |
| F3: System prompt injection | 1 | Low |
| **Total** | **5.5** | **Low** |

## Out of Scope (Future)

- Model routing for plan mode (cheaper model during exploration)
- Plan summary generation on exit
- Interspect evidence emission during plan-mode exploration
- Plan-mode-specific slash commands (e.g., `/plan save` to snapshot findings)
