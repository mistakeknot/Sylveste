---
artifact_type: prd
bead: iv-5ztam
stage: design
---
# PRD: Interspect Effectiveness Dashboard

## Problem

Interspect can propose, apply, and canary-monitor routing overrides, but cannot answer "are our routing decisions making reviews better?" The canary system prevents regression but doesn't measure improvement. Without effectiveness data, the value of routing changes is anecdotal.

## Solution

Add an `/interspect:effectiveness` command that computes and displays aggregate effectiveness metrics from existing evidence data, showing override rate trends, per-agent hit rates with directional indicators, and actionable recommendations.

## Features

### F1: Effectiveness Report Function
**What:** Core SQL queries against existing evidence + sessions tables to compute before/after metrics for routing changes.

**Acceptance criteria:**
- [ ] Computes override rate (% corrections / total dispatches) for configurable time windows (7d, 30d, 90d)
- [ ] Computes per-agent hit rates from calibration scores
- [ ] Computes trend direction (improving/stable/declining) by comparing recent vs prior window
- [ ] Returns structured data (agent, hit_rate, trend, trend_delta, dispatches, corrections)
- [ ] Handles edge cases: no overrides, no evidence, insufficient data

### F2: Effectiveness Command
**What:** New `/interspect:effectiveness` command displaying the report as a formatted dashboard.

**Acceptance criteria:**
- [ ] Shows active overrides with age and canary status
- [ ] Shows aggregate impact metrics (override rate change, dispatch count change)
- [ ] Shows per-agent trends with directional indicators (improving/stable/declining)
- [ ] Flags declining agents with warning
- [ ] Suggests next actions (investigate, review, celebrate)
- [ ] Accepts optional `--window` flag (default: 30d)

### F3: Effectiveness in Status
**What:** Add a one-line effectiveness summary to the existing `/interspect:status` command.

**Acceptance criteria:**
- [ ] Shows "Effectiveness: override rate X% → Y% (Z% improvement)" in status output
- [ ] Only shown when sufficient data exists (>=2 time windows)
- [ ] Does not slow down status command appreciably

## Non-goals

- Cost/token integration with interstat (can add later)
- Sparkline/graph rendering (plain numbers sufficient for v1)
- Cross-project aggregation (separate feature)
- Automated recommendations beyond warnings (human judgment)

## Dependencies

- Existing evidence + sessions tables in interspect.db
- Existing routing-overrides.json for active override list
- Existing calibration scores (optional, for hit_rate)
