# Brainstorm: clavain-cli sprint-init — Consolidated Sprint Bootstrap

**Bead:** Demarch-czxk
**Date:** 2026-03-18

## Problem

Sprint actions (e.g., `/clavain:sprint shadow-work-hqu0`) produce ugly, noisy output:
- 4+ separate Bash tool calls for bootstrap, interstat registration, discovery, and complexity check
- Raw environment variable exports visible in Claude Code's tool-call chrome
- Debug-style output (`CLAVAIN_ROOT=/Users/sma/.codex/clavain`) instead of formatted status

Claude Code's native tool-call rendering (`⏺ Bash(export CLAVAIN_ROOT=...)`) cannot be changed — it's client-side. But we control: (a) the number of tool calls, (b) what Bash commands print, and (c) what Claude says between calls.

## Philosophy Grounding

Three principles converge on the solution:

1. **"Human attention is the bottleneck"** (Vision §5, Clavain Vision §4) — output must be presented for quick, confident review. Four noisy tool calls fail this.
2. **"Composition through contracts"** (PHILOSOPHY.md §3) — inline Bash in sprint.md leaks mechanism into the UX layer.
3. **Masaq is the visual layer** — themed Go components exist (statusbar, meter, sparkline, spinner). Clavain as a Claude Code plugin uses Bash today, but "if the host platform changes, opinions survive; UX wrappers are rewritten." Visual rendering belongs in Go, not in Bash heredocs.

## Options Explored

**Option A: Bootstrap consolidation script (Bash)**
- Single `sprint-init.sh` script consolidating all init steps
- Pro: Simple, one tool call
- Con: Bash can't use masaq themes, couples visual layer to wrong language

**Option B: Prose polish + formatted Bash output**
- Keep separate commands, improve Claude's framing text
- Pro: No new code
- Con: Still 4 tool calls, lipstick on a pig

**Option C: clavain-cli subcommand (Go + masaq)**
- New `sprint-init` subcommand in clavain-cli
- Uses masaq/theme for Tokyo Night colors, lipgloss for formatting
- Single binary call: `clavain-cli sprint-init "$BEAD_ID"`
- Pro: Right layer (Go), uses existing theme system, one clean tool call, graceful degradation
- Con: Requires Go code + masaq dependency in clavain-cli

## Decision

**Option C** — `clavain-cli sprint-init` subcommand.

Follows the existing pattern: clavain-cli already has `sprint-find-active`, `sprint-advance`, `sprint-budget-remaining`, `complexity-label`, etc. Adding `sprint-init` is a natural extension. The visual rendering is in Go where masaq lives — not in Bash.

## Output Design

```
── Sprint: Demarch-czxk ─────────────────────────
 Complexity: 3/5 (moderate)
 Phase:      planned → execute
 Budget:     42k / 120k (35%)
──────────────────────────────────────────────────
```

Colors from masaq Tokyo Night: Primary (#7aa2f7) for borders/labels, Info (#7dcfff) for values, Success (#9ece6a) for healthy metrics, Warning (#e0af68) for budget >70%, Muted (#565f89) for separators.

## Scope

1. `clavain-cli sprint-init <bead_id>` — Go subcommand
2. Update `sprint.md` — replace 4 inline Bash blocks with single CLI call
3. Update `sprint.md` — instruct Claude to emit concise phase headers
