---
name: interspect
description: "Agent performance profiler and routing optimizer. Collects evidence about flux-drive agent accuracy, proposes routing overrides for underperforming agents, and monitors canary periods. Companion plugin for Clavain."
---
# Gemini Skill: interspect

You have activated the interspect capability.

## Base Instructions
# interspect — Development Guide

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


> Cross-AI documentation for interspect. Works with Claude Code, Codex CLI, and other AI coding tools.

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/interspect` |
| Namespace | `interspect:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 0 skills, 12 commands, 0 agents, 3 hooks (SessionStart + PostToolUse + Stop), 1 script |
| License | MIT |

### Release workflow
```bash
scripts/bump-version.sh <version>   # bump, commit, push, publish
```

## Overview

**interspect** is an agent performance profiler and routing optimizer — a Clavain companion plugin. Collects evidence about flux-drive agent accuracy, proposes routing overrides for underperforming agents, and monitors canary periods.

**Problem:** Flux-drive agents have variable quality per domain. Bad routing wastes tokens and produces poor reviews. No evidence-based way to tune agent selection.

**Solution:** Three hooks collect evidence passively. 12 commands provide analysis, override management, and canary monitoring. Evidence stored in SQLite; routing overrides written to `.claude/routing-overrides.json`.

**Plugin Type:** Claude Code command + hook plugin (Clavain companion)
**Current Version:** 0.1.5

## Architecture

```
interspect/
├── .claude-plugin/
│   └── plugin.json               # Metadata only (commands/hooks via convention)
├── commands/
│   ├── interspect.md             # Main analysis — detect patterns, classify, report
│   ├── interspect-status.md      # Overview — sessions, evidence, canaries
│   ├── interspect-evidence.md    # Detailed agent evidence view
│   ├── interspect-correction.md  # Record manual correction event
│   ├── interspect-propose.md     # Propose routing override from patterns
│   ├── interspect-override.md    # Apply routing override directly
│   ├── interspect-revert.md      # Revert override or disable overlays
│   ├── interspect-approve.md     # Approve pending modification
│   ├── interspect-health.md      # Signal diagnostics
│   ├── interspect-enable-autonomy.md
│   ├── interspect-disable-autonomy.md
│   └── interspect-unblock.md     # Unblock stalled modification
├── hooks/
│   ├── hooks.json                # SessionStart + PostToolUse(Task) + Stop
│   ├── lib-interspect.sh         # Core library (114KB monolith)
│   ├── interspect-session.sh     # SessionStart: record, consume kernel events, canary check
│   ├── interspect-evidence.sh    # PostToolUse: record evidence on Task tool use
│   └── interspect-session-end.sh # Stop: close session record
├── scripts/
│   └── bump-version.sh
├── docs/
│   └── research/                 # Architecture/quality/correctness/safety reviews
├── CLAUDE.md
├── AGENTS.md                     # This file
├── PHILOSOPHY.md
└── LICENSE
```

## Commands

| Command | Purpose |
|---------|---------|
| `/interspect` | Analyze evidence — detect patterns, classify by counting-rule thresholds |
| `/interspect:status` | Overview — session counts, evidence stats, active canaries |
| `/interspect:evidence` | Detailed agent evidence view |
| `/interspect:correction` | Record a manual correction event |
| `/interspect:propose` | Propose routing override from ready patterns |
| `/interspect:override` | Apply a routing override directly |
| `/interspect:revert` | Revert override or disable overlays |
| `/interspect:approve` | Approve pending modification |
| `/interspect:health` | Signal diagnostics |
| `/interspect:enable-autonomy` | Enable autonomous modification mode |
| `/interspect:disable-autonomy` | Disable autonomous modification mode |
| `/interspect:unblock` | Unblock a stalled modification |

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `interspect-session.sh` | SessionStart | Record session, consume kernel events, check canary alerts |
| `interspect-evidence.sh` | PostToolUse (Task) | Record evidence from Task tool use |
| `interspect-session-end.sh` | Stop | Close session record |

## Core Library

`hooks/lib-interspect.sh` (114KB) is the monolithic core. All commands source it. Discovery path: first checks `~/.claude/plugins/cache/*/clavain/*/hooks/lib-interspect.sh`, then `~/projects/*/os/clavain/hooks/lib-interspect.sh`. Uses path search (not `$CLAUDE_PLUGIN_ROOT`) to enable sourcing from Clavain hooks.

## Canary Monitoring

When a routing override is applied, it enters a canary period:
- **Window:** 20 uses over 14 days
- **Alert threshold:** 20% regression
- SessionStart hook injects `additionalContext` warning if canary alerts exist

## Data Storage

- **Evidence DB:** `.clavain/interspect/interspect.db` (SQLite, per-project)
- **Routing overrides:** `.claude/routing-overrides.json` (cross-repo contract)
- **Protected paths:** `.clavain/interspect/protected-paths.json`

## Integration Points

| Tool | Relationship |
|------|-------------|
| Clavain | Primary integration — Clavain discovers interspect via `_discover_interspect_plugin()`, sources `lib-interspect.sh` |
| Intercore | Dual-read from `interspect_events` kernel table via `ic interspect query`; kernel events consumed at session start |
| flux-drive agents | The subjects being profiled; routing overrides target flux-drive agent IDs |
| interpulse | interpulse monitors context pressure; interspect monitors routing quality (complementary) |

## Testing

```bash
cd tests && uv run pytest -q
```

## Decay Policy

Evidence and calibration data (C2) follow intermem's decay model:

| Data type | Grace period | Decay rate | Hysteresis | Action |
|-----------|-------------|------------|------------|--------|
| Evidence records | 90 days | Excluded from analysis after 90d | N/A | Old evidence not counted in pattern detection |
| Canary windows | 14 days | Window expires after 14d or 20 uses | N/A | Auto-evaluated at expiry |
| Routing overrides | None | Permanent until reverted | N/A | Manual revert via `/interspect:revert` |
| Session records | 90 days | Excluded from baseline after 90d | N/A | Old sessions not counted in canary baselines |

**Standard pattern:** Grace period → linear exclusion → no hysteresis needed (evidence is append-only, not demotable). Interspect uses a 90-day rolling window rather than per-entry decay because evidence is statistical — individual records don't go "stale," but old aggregate patterns lose relevance.

## Known Constraints

- `lib-interspect.sh` is 114KB — monolithic by necessity (all commands need the same DB/routing/canary functions)
- plugin.json has no `commands` or `hooks` keys — they load via convention (commands/ dir, hooks/hooks.json)
- Missing README.md (interspect is the only repo without one)
- Discovery uses path search rather than `$CLAUDE_PLUGIN_ROOT` — required for cross-plugin sourcing from Clavain


