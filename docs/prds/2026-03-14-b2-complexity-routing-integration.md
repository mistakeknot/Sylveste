# PRD: B2 Complexity-Aware Routing Integration

**Bead:** iv-jgdct
**Date:** 2026-03-14
**Status:** Draft

## Problem Statement

B2 complexity-aware routing infrastructure is fully implemented but has zero callers. `routing_resolve_agents()` branches on complexity mode but never receives a `--complexity` tier, so every dispatch falls through to B1 static routing. Subagents get the same model regardless of task difficulty.

## Goal

Wire complexity signal collection into all production dispatch points so that the existing B2 classification (C1-C5) and override logic actually affects model selection. Ship in shadow mode first (log what would change), then enable enforce mode after validating shadow output.

## Features

### F1: Add `--complexity` flag to `routing_resolve_agents`

**File:** `os/Clavain/scripts/lib-routing.sh`

Add `--complexity <tier>` parameter to `routing_resolve_agents()`. When provided, pass it through to `routing_resolve_model_complex` on line 1115. This is the only lib-routing.sh change needed — the resolver already handles the tier correctly.

**Acceptance:**
- `routing_resolve_agents --phase executing --agents "fd-safety,fd-architecture" --complexity C5` returns Opus for both agents (in enforce mode)
- Without `--complexity`, behavior is identical to current (B1 fallback)
- Shadow mode logs show `[B2-shadow]` entries when complexity is provided

### F2: Flux-drive complexity classification at dispatch

**File:** `interverse/interflux/skills/flux-drive/phases/launch.md` Step 2.0.5

Before calling `routing_resolve_agents`, classify the review target's complexity:
- Token count: approximate from review file size
- File count: from triaged file list or git diff
- Reasoning depth: heuristic (default 3, +1 for security/architecture targets)

Pass classified tier as `--complexity` to `routing_resolve_agents`.

**Acceptance:**
- Large documents (>4000 tokens) classify as C4/C5
- Small single-file changes classify as C1/C2
- Shadow log lines appear during flux-drive reviews

### F3: Quality-gates complexity classification at dispatch

**File:** `os/Clavain/commands/quality-gates.md`

Same pattern as F2: classify diff complexity before dispatching review agents.

**Acceptance:**
- Quality-gates passes complexity tier to agent dispatch
- Shadow logs appear during quality-gates runs

## Non-Goals

- Per-agent complexity classification (future B2.1)
- Switching to enforce mode (separate decision after shadow validation)
- Sprint brainstorm/work phase integration (already uses bead-level complexity from /route)
- Changes to routing.yaml thresholds or overrides (existing values are reasonable)

## Rollout

1. Ship all changes with `complexity.mode: shadow` (current setting)
2. Monitor shadow logs for 1 week
3. If tier assignments are reasonable, switch to `enforce` via routing.yaml

## Dependencies

- Builds on: iv-k8xn (B2 infrastructure, closed)
- Unblocks: iv-i198 (B3 adaptive routing — needs B2 active to layer on)
