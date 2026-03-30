---
artifact_type: plan
bead: sylveste-rsj.1.8
stage: planned
---

# Plan: Compound Autonomy Guard

## Tasks

### 1. Add `capability_level` field to fleet-registry.yaml
- [x] Define capability_level (0-4) for each agent in fleet-registry.yaml
- [ ] Add field to fleet-registry.schema.json (skipped — schema not enforced at runtime)
- [x] L0: read-only (drift-check, status). L1: analysis (fd-* reviewers). L2: local mutations (work agents). L3: external effects (ship, publish). L4: infrastructure (reserved).
- [x] Default unset agents to L2 (conservative)
- **Files:** `os/Clavain/config/fleet-registry.yaml`

### 2. Add compound autonomy thresholds to default-policy.yaml
- [x] Add `compound_autonomy` section with score thresholds
- [x] Scores: 0-2 auto, 3-4 advisory, 6+ require approval, 9+ blocked
- **Files:** `os/Clavain/config/default-policy.yaml`

### 3. Implement `fleet_compound_autonomy_check()` in lib-fleet.sh
- [x] Function: takes mycroft_tier and agent_name, looks up capability_level, computes score
- [x] Returns: 0 (pass), 1 (advisory/warn), 2 (require approval), 3 (blocked)
- [x] Reads thresholds from default-policy.yaml
- **Files:** `os/Clavain/scripts/lib-fleet.sh`

### 4. Wire check into dispatch.sh
- [x] Before agent launch, call `fleet_compound_autonomy_check`
- [x] On advisory: log warning, proceed
- [x] On require_approval: prompt user (or set `MYCROFT_OVERRIDE=true` to bypass)
- [x] On blocked: refuse dispatch, log reason
- **Files:** `os/Clavain/scripts/dispatch.sh`

### 5. Wire check into session-start.sh Mycroft context
- [x] When Mycroft assignment detected, compute compound score and inject into context
- [x] Display compound autonomy level in sprint status banner
- **Files:** `os/Clavain/hooks/session-start.sh`

### 6. Tests
- [x] Add test cases to test_fleet.bats for compound autonomy check
- [x] Test: T1×L1=1 (pass), T2×L2=4 (advisory), T2×L3=6 (approval), T3×L3=9 (blocked)
- **Files:** `os/Clavain/tests/shell/test_fleet.bats`

## Dependencies

- Fleet registry must be readable (existing lib-fleet.sh)
- dispatch.sh must exist (existing)

## Estimated complexity: C3 (6 files, clear scope, no ambiguity)
