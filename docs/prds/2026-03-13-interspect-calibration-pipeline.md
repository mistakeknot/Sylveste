---
artifact_type: prd
bead: Demarch-g3a
stage: design
---
# PRD: Interspect Calibration Pipeline — Evidence → Routing Overrides

## Problem
Quality-gates agent verdicts never reach interspect's calibration pipeline because `_discover_interspect_plugin` fails silently in the quality-gates context. Zero `verdict_outcome` events exist in the evidence store. The flywheel is broken: agent performance data is collected but never processed into routing decisions.

## Solution
Fix the broken verdict recording path, upgrade calibration output to v2 schema with source weighting and phase awareness, and add a backfill sweep so existing verdict data isn't lost.

## Features

### F1: Fix verdict recording discovery path
**What:** Diagnose and fix why `_discover_interspect_plugin()` returns empty when called from quality-gates Step 5a, so `_interspect_record_verdict` fires after every quality-gates run.
**Acceptance criteria:**
- [ ] After running `/quality-gates`, new `verdict_outcome` events appear in `interspect.db` evidence table
- [ ] `_discover_interspect_plugin` finds the plugin from both Clavain hooks context and quality-gates skill context
- [ ] Existing verdict JSON files in `.clavain/verdicts/` get backfilled as evidence events

### F2: Calibration schema v2 with source weighting
**What:** Upgrade `_interspect_compute_agent_scores` and `_interspect_write_routing_calibration` to produce v2 output with weighted hit rates and per-phase scores.
**Acceptance criteria:**
- [ ] `routing-calibration.json` includes `schema_version: 2`, `source_weights`, and `weighted_hit_rate` per agent
- [ ] Sessions table has a `source` column (bootstrap/self-building/normal) or evidence context carries source classification
- [ ] Bootstrap sessions weighted 0.5x, self-building 0.7x in hit rate computation
- [ ] Minimum 20 non-bootstrap sessions enforced before weights propagate

### F3: Verdict backfill + sweep mechanism
**What:** One-time backfill of existing `.clavain/verdicts/*.json` files into evidence, plus a SessionStart sweep that catches unrecorded verdicts from previous sessions.
**Acceptance criteria:**
- [ ] Backfill script processes existing verdict files and inserts `verdict_outcome` events
- [ ] SessionStart hook checks for unrecorded verdicts and records them (idempotent)
- [ ] Duplicate prevention: same verdict file is never recorded twice

## Non-goals
- Switching calibration from shadow to enforce mode (that's a separate operational decision)
- Adding new evidence signal types beyond verdict_outcome
- Modifying the routing-overrides.json schema (that's iv-gkj9's scope)
- UI/visualization of calibration data

## Dependencies
- Existing `lib-interspect.sh` functions (all exist, just need fixes + v2 upgrade)
- `.clavain/verdicts/` directory (populated by quality-gates synthesis agent)
- `routing.yaml` calibration section (exists, in shadow mode)

## Open Questions
- None remaining (all resolved in brainstorm)
