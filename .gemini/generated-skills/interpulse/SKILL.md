---
name: interpulse
description: "Session context monitoring — pressure tracking, token estimation, threshold warnings"
---
# Gemini Skill: interpulse

You have activated the interpulse capability.

## Base Instructions
# interpulse — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](./PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](./PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


> Cross-AI documentation for interpulse. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interpulse` |
| Namespace | `interpulse:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 1 skill, 0 commands, 0 agents, 1 hook (PostToolUse), 2 scripts |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interpulse** is a session context pressure monitor with dual-threshold awareness — combines heuristic pressure tracking (tool calls + time decay + token estimation) with real context window remaining percentage from Claude Code. Debounces warnings to avoid spam, with severity escalation bypass.

**Problem:** Claude Code sessions accumulate context silently. By the time you notice degradation, you've lost important context to compaction. No early warning system.

**Solution:** PostToolUse hook uses dual-threshold logic: `level = max(pressure_level, context_level)`. Pressure tracks tool call weight with time decay. Context reads Claude Code's `context_window.remaining_percentage` and normalizes for the 16.5% autocompact buffer. Either metric can trigger warnings. Debounces at 5 calls between warnings, with severity escalation bypassing debounce.

**Plugin Type:** Claude Code skill + hook plugin
**Current Version:** 0.1.2

## Architecture

```
interpulse/
├── .claude-plugin/
│   └── plugin.json               # 1 skill
├── skills/
│   └── status/SKILL.md           # Pressure dashboard
├── hooks/
│   ├── hooks.json                # PostToolUse registration
│   └── context-monitor.sh        # Pressure tracker with warn/checkpoint logic
├── lib/
│   └── interpulse-lib.sh         # Shared state management (_ip_session_id, _ip_state_file, etc.)
├── scripts/
│   ├── bump-version.sh
│   └── validate-gitleaks-waivers.sh
├── tests/
│   ├── pyproject.toml
│   └── structural/
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
├── README.md
└── LICENSE
```

## Dual-Threshold Model

Level = max(pressure_level, context_level) — either metric can trigger warnings.

### Pressure Thresholds (heuristic)

| Parameter | Value |
|-----------|-------|
| Standard tool call | +1.0 pressure |
| Heavy tool calls (Read, Grep, Task, WebFetch, WebSearch) | +1.5 pressure |
| Idle decay | -0.5 per 10 minutes |
| Token estimate | cumulative tool output length / 4 |

| Zone | Pressure | Est. Tokens | Action |
|------|----------|-------------|--------|
| Green | < 60 | < 150k | Normal |
| Yellow | 60+ | ~150k | Warning |
| Orange | 90+ | ~180k | Strong warning |
| Red | 120+ | ~200k | Auto-checkpoint |

### Context Thresholds (ground truth)

Reads `context_window.remaining_percentage` from PostToolUse stdin JSON and normalizes for Claude Code's 16.5% autocompact buffer. Falls back to pressure-only when absent.

| Zone | Usable Remaining | Example Raw % | Action |
|------|-----------------|---------------|--------|
| Green | > 35% | > 46% | Normal |
| Yellow | <= 35% | <= 46% | Warning |
| Orange | <= 20% | <= 33% | Strong warning |
| Red | <= 10% | <= 25% | Auto-checkpoint |

### Debounce

- 5 tool calls minimum between repeated warnings at the same level
- Severity escalation (e.g., yellow→orange, orange→red) bypasses debounce and fires immediately
- Debounce state stored at `/tmp/interpulse-debounce-${SESSION_ID}.json`

## Session State

Ephemeral file at `/tmp/interpulse-${SESSION_ID}.json`:
```json
{"calls": 0, "last_call_ts": 0, "pressure": 0.0, "heavy_calls": 0, "est_tokens": 0}
```

Resets each session by design — pressure tracking is session-scoped.

## Interband Payload

Written to `~/.interband/interpulse/pressure/${SESSION_ID}.json` for statusline and other consumers:
```json
{"level": "yellow", "pressure": 65.5, "est_tokens": 155000, "ts": 1741318800, "context_usable": 30, "context_raw": 41.5}
```

`context_usable` and `context_raw` are only present when `context_window.remaining_percentage` is available. The `level` field uses the pre-debounce severity so consumers always see the raw signal.

## Component Conventions

### Shared Library
`lib/interpulse-lib.sh` provides:
- `_ip_session_id`, `_ip_state_file`, `_ip_read_state`, `_ip_write_state` — session state management
- `_ip_context_remaining` — extract `context_window.remaining_percentage` from hook stdin JSON
- `_ip_normalize_usable_context` — normalize raw % to usable % (accounting for 16.5% buffer)
- `_ip_context_level` — map usable remaining % to severity level
- `_ip_max_level` — return the higher severity of two levels

Guards against double-loading. Sourced by both the hook and skill scripts.

### Hook
`hooks/context-monitor.sh` — PostToolUse hook, fires on `Edit|Write|Bash|Task|NotebookEdit|MultiEdit`. Timeout: 5s. Registered in `hooks/hooks.json` (separate from plugin.json).

## Integration Points

| Tool | Relationship |
|------|-------------|
| intercheck | interpulse extracted from intercheck; intercheck now focuses on code quality |
| interspect | interspect monitors routing quality; interpulse monitors context pressure (complementary) |

## Testing

```bash
cd tests && uv run pytest -q
```

## Known Constraints

- Pressure thresholds are heuristic — actual compaction depends on message structure, not just token count
- Context thresholds use ground truth when available, but `context_window.remaining_percentage` may be absent in subagents or older Claude Code versions
- Session state is ephemeral (`/tmp/`) — no cross-session pressure history
- Extracted from intercheck; context monitoring is orthogonal to code quality


