---
artifact_type: reflection
bead: Demarch-py89
date: 2026-03-26
sprint_outcome: shipped
---
# Reflection: F7 — bd doctor auto-run with corruption blocking (Demarch-py89)

## What happened

Upgraded the existing `bd doctor --json` check in session-start.sh to separate errors (corruption) from warnings (stale hooks), write a corruption sentinel file, and block `sprint-init` when corruption is detected. 3 tasks, ~23 LOC across 2 files.

## Design choice: sentinel file vs direct doctor call

Used a file sentinel (`/tmp/clavain-bd-corruption-$USER`) rather than calling `bd doctor` again from `sprint-init`. Reasons:
1. `bd doctor` takes ~27ms — acceptable once per 5 minutes in SessionStart, but not on every sprint-init
2. The SessionStart hook already has the TTL gating; duplicating it would be fragile
3. The sentinel persists until the next SessionStart clears it (after `bd doctor --fix`), which is the correct lifecycle

## Lessons

1. **v0.7 B:L2 is close.** This was the last open P1. After closing, only the parent epic (Demarch-0rgc) and the meta-epic (Demarch-enxv) remain in-progress. The gate calibration loop (Track A) is the remaining gap.
2. **The prioritization triage earlier in this session surfaced the right work order.** By anchoring P1 to version gates, we closed 6 orphan beads and shipped 2 real features — all gate-blocking — instead of working on any of the 38 former-P1 non-gate items.
