---
artifact_type: prd
bead: sylveste-rsj.1.8
stage: strategized
---

# PRD: Compound Autonomy Guard

## Goal

Prevent unreviewed escalation when a fleet orchestrator (Mycroft) auto-dispatches agents with high capability levels. The compound autonomy score (orchestrator_tier × agent_level) must be checked at dispatch time.

## Success Criteria

1. Every agent in fleet-registry.yaml has a `capability_level` (0-4)
2. `fleet_compound_autonomy_check()` returns pass/warn/block based on score thresholds
3. dispatch.sh gates on compound score before launching agents
4. T2 × L3 dispatches require human approval
5. T3 × L3 dispatches are blocked by default

## Non-Goals

- Runtime action monitoring (too complex, monitoring paradox)
- Changing sprint autonomy tiers
- Modifying phase-based deny rules

## Risks

- Over-blocking legitimate Mycroft dispatches → mitigate with advisory mode first
- Incomplete capability_level assignments → mitigate with conservative default (L2)
