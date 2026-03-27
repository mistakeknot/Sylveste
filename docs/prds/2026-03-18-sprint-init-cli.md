# PRD: clavain-cli sprint-init

**Bead:** Sylveste-czxk
**Date:** 2026-03-18
**Status:** Draft

## Problem

Sprint bootstrap in `sprint.md` requires 4+ separate Bash tool calls (environment export, interstat registration, discovery scan, complexity check), each producing raw debug output visible in Claude Code's tool-call chrome. This wastes human attention and violates "human attention is the bottleneck."

## Solution

A single `clavain-cli sprint-init <bead_id>` Go subcommand that:
1. Bootstraps environment (validates bead exists, reads sprint state)
2. Registers interstat session attribution
3. Runs work discovery scan
4. Reads complexity and budget
5. Outputs a formatted status banner using masaq/theme colors

## Requirements

### P0: Core CLI
- `clavain-cli sprint-init <bead_id>` subcommand
- Consolidates: bead validation, complexity read, budget read, phase read
- Outputs structured banner with: bead ID, title, complexity, phase, budget
- Uses masaq/theme Tokyo Night colors via lipgloss
- Graceful degradation: plain text when NO_COLOR set or output piped
- Returns non-zero on invalid bead

### P0: sprint.md Update
- Replace 4 inline Bash blocks (bootstrap, interstat, discovery, complexity) with single `clavain-cli sprint-init` call
- Update Claude's framing instructions: concise phase headers, no "Let me bootstrap..."

### P1: Interstat Registration
- `sprint-init` writes bead→session attribution file
- Calls `ic session attribute` if ic available (fail-soft)

### P2: Discovery Integration
- `sprint-init` runs discovery scan, includes actionable beads in output
- Deferred: can add later without changing the interface

## Non-Requirements
- No changes to Claude Code's tool-call rendering (we can't control that)
- No TUI/interactive mode — this is a one-shot CLI command
- No changes to other sprint subcommands

## Acceptance Criteria
1. `clavain-cli sprint-init Sylveste-czxk` produces formatted banner with bead, complexity, phase, budget
2. sprint.md bootstrap section uses single CLI call
3. `NO_COLOR=1 clavain-cli sprint-init Sylveste-czxk` produces plain text
4. Invalid bead ID returns non-zero exit code
5. Missing bd/ic/complexity gracefully degrade (partial output, not crash)

## Success Metric
Sprint actions show 1 tool call for init instead of 4+. Human sees formatted status, not raw environment variables.
