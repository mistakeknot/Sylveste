---
name: intertrust
description: "Agent trust scoring — reputation tracking, severity-weighted decay, and suppression candidates."
---
# Gemini Skill: intertrust

You have activated the intertrust capability.

## Base Instructions
# intertrust — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
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


Agent trust scoring engine for Claude Code. Companion plugin for [Clavain](https://github.com/mistakeknot/Clavain).

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/intertrust` |
| Namespace | `intertrust:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 1 command, 1 library, 0 hooks, 0 MCP servers |
| License | MIT |

### Release workflow

```bash
ic publish --patch   # or: ic publish <version>
```

## Architecture

```
intertrust/
├── .claude-plugin/
│   └── plugin.json            # Plugin manifest
├── hooks/
│   └── lib-trust.sh           # Trust scoring library (sourced, not executed)
├── commands/
│   └── trust-status.md        # /trust-status command
└── tests/
    └── test_trust_scoring.sh  # 11 end-to-end tests
```

### Data model

Single table in the shared `.interspect/interspect.db`:

```sql
CREATE TABLE trust_feedback (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts TEXT NOT NULL,
    session_id TEXT NOT NULL,
    agent TEXT NOT NULL,
    project TEXT NOT NULL,
    finding_id TEXT NOT NULL,
    severity TEXT NOT NULL,        -- P0, P1, P2, P3
    outcome TEXT NOT NULL,         -- "accepted" or "discarded"
    review_run_id TEXT,
    weight REAL NOT NULL DEFAULT 1.0  -- severity weight
);
```

### Score algorithm

1. Query `trust_feedback` for (agent, project) → time-decay-weighted accepted/total sums
2. Query `trust_feedback` for agent (all projects) → global score
3. Blend: `trust = (w * project_score) + ((1-w) * global_score)` where `w = min(1.0, project_count/20)`
4. Floor at 0.05, cap at 1.0
5. New project inherits global score; no data at all → 1.0 (neutral)

Time decay: `weight * 1/(1 + days_old/30)` — half-life ~30 days.

Severity weights: P0=4.0, P1=2.0, P2=1.0, P3=0.5.

### Library API

```bash
source "$INTERTRUST_PLUGIN/hooks/lib-trust.sh"

# Record a finding outcome
_trust_record_outcome "$session_id" "fd-safety" "my-project" "finding-1" "P1" "accepted" "run-123"

# Compute trust for one agent
score=$(_trust_score "fd-safety" "my-project")  # → "0.92"

# Batch-load all agents (avoids N queries in dispatch loop)
_trust_scores_batch "my-project"  # → agent\tscore (TSV)

# Full report table
_trust_report

# Severity weight lookup
_trust_severity_weight "P0"  # → "4.0"
```

### Consumer discovery

Consumers find the library via filesystem scan:

```bash
TRUST_PLUGIN=$(find ~/.claude/plugins/cache -path "*/intertrust/*/hooks/lib-trust.sh" 2>/dev/null | head -1)
```

Fallback to legacy interspect location for backward compatibility:

```bash
[[ -z "$TRUST_PLUGIN" ]] && TRUST_PLUGIN=$(find ~/.claude/plugins/cache -path "*/interspect/*/hooks/lib-trust.sh" 2>/dev/null | head -1)
```

### Integration points

| Consumer | Function | When |
|----------|----------|------|
| interflux launch.md (Step 2.1e) | `_trust_scores_batch()` | Before agent dispatch — multiplies triage score by trust |
| clavain resolve.md (Step 5) | `_trust_record_outcome()` | After finding resolution — records accepted/discarded |
| `/trust-status` command | `_trust_report()` | On-demand — shows trust table with suppression candidates |

### Backward compatibility

- `_interspect_project_name()` shim maps to `_trust_project_name()` for callers using old API
- Shared DB: both intertrust and interspect create `trust_feedback` via `CREATE TABLE IF NOT EXISTS`
- Both consumer integration points use fallback discovery (try intertrust first, then interspect)

## Testing

```bash
bash tests/test_trust_scoring.sh
```

11 tests covering:
1. No data → neutral trust (1.0)
2. All accepted → high trust
3. All discarded → low trust (above floor)
4. Mixed outcomes → intermediate trust
5. Severity weighting (P0 > P3)
6. Global fallback for new project
7. Batch loading multiple agents
8. Report generation
9. Floor enforcement (never below 0.05)
10. Invalid outcome rejection
11. Backward compatibility shim

## Design decisions

- **Self-contained** — no dependency on lib-interspect.sh (utility functions inlined)
- **Shared DB** — trust_feedback table in interspect.db (not a separate DB)
- **Fail-open** — all functions return neutral 1.0 on any error
- **Progressive enhancement** — trust is never a gate, always a multiplier
- **No hooks** — purely a library + command plugin; data is written by external callers


