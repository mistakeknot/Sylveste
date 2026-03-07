---
artifact_type: brainstorm
bead: iv-zsio
stage: discover
---

# Discovery Pipeline Integration

**Bead:** iv-zsio
**Date:** 2026-03-06

## Problem Statement

The Clavain vision describes a multi-source discovery pipeline with confidence tiers and adaptive thresholds. The bead says "integrate full discovery pipeline into sprint workflow" — but investigation reveals the pipeline is already implemented in interphase (665-line lib-discovery.sh with scoring, action inference, orphan detection, claim awareness, telemetry). It's just never deployed.

## Root Cause

Interphase's `plugin.json` declares only `"skills": ["./skills/beads-workflow"]` — no hooks reference. Claude's plugin installer only copies files referenced by the manifest. Result: the installed plugin directory is empty (0 files), so Clavain's delegation shim falls through to stubs and returns `DISCOVERY_UNAVAILABLE`.

The hooks directory contains:
- `hooks.json` — PostToolUse heartbeat, bead-autoclaim, SessionEnd release
- `lib-discovery.sh` (665 lines) — full discovery scanner with multi-factor scoring
- `lib-gates.sh` (25K) — gate validation, dual persistence
- `lib-phase.sh` (5K) — phase state tracking
- `bead-autoclaim.sh`, `heartbeat.sh`, `session-end-release.sh`

None of these get installed because `plugin.json` doesn't reference `"hooks": "./hooks/hooks.json"`.

## Fix

1. Add `"hooks": "./hooks/hooks.json"` to interphase's `.claude-plugin/plugin.json`
2. Bump version
3. Publish interphase
4. Verify: `claude plugin install interphase@interagency-marketplace`, check hooks are present
5. Verify: Clavain's shim finds interphase, `discovery_scan_beads()` returns real data

## Scope Assessment

What was expected to be a multi-session build (Effort 4, Risk 3) is actually a one-line manifest fix plus publish. The implementation already exists. The integration already exists. The only thing broken is the packaging.

## What This Unlocks

Once interphase hooks deploy correctly:
- `discovery_scan_beads()` returns scored JSON instead of `DISCOVERY_UNAVAILABLE`
- Phase tracking works (`lib-phase.sh` — set/get/infer bead phases)
- Gate validation works (`lib-gates.sh` — enforce gates before execution)
- Heartbeat keeps claims fresh (`heartbeat.sh`)
- Bead auto-claim on first edit (`bead-autoclaim.sh`)
- Session-end auto-release (`session-end-release.sh`)

## What Remains After This Fix (Deferred)

Per the vision, the full discovery pipeline also needs:
- Event-driven scan triggers (currently manual `/route` only)
- Confidence tiering with autonomous actions (auto-create bead for high confidence)
- Adaptive thresholds via feedback loop
- Kernel event emission from interject

These are separate features, not part of this integration fix.
