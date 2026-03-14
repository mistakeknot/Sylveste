---
artifact_type: plan
bead: Demarch-g4ja
stage: design
requirements:
  - "Gap 1: Override consumption in lib-routing.sh"
---
# Interspect Override Consumption — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-g4ja
**Goal:** Make lib-routing.sh read `.claude/routing-overrides.json` so interspect overrides actually affect routing.

**Architecture:** Add `_routing_read_override()` function to lib-routing.sh, called between B1 (per-agent override) and B1b (calibration). Pattern follows existing `_routing_read_calibration()`.

---

## Tasks

- [x] 1. Add `_routing_read_override()` function to lib-routing.sh
  - Finds `.claude/routing-overrides.json` via `$CLAUDE_PROJECT_DIR` or git root (same as calibration)
  - Returns: "exclude" if agent is excluded, model name if agent has an approved model recommendation, empty if no match
  - Validates: JSON structure, action field, status field
  - Strips namespace prefix for lookup (same as calibration: `fd-safety` not `interflux:review:fd-safety`)

- [x] 2. Wire `_routing_read_override()` into `routing_resolve_model()`
  - Insert between line 560 (per-agent override) and line 562 (calibration)
  - If override returns "exclude": set result to special sentinel "_EXCLUDED_" and return early
  - If override returns a model name: set result to that model (overrides calibration)
  - Precedence: routing.yaml agent override > interspect override > calibration > phase/category defaults

- [x] 3. Handle "exclude" in callers
  - `routing_resolve_model()` returns "_EXCLUDED_" for excluded agents
  - Callers (flux-drive triage, quality-gates) check for "_EXCLUDED_" and skip the agent
  - Document the sentinel value

- [x] 4. Add tests
  - Test: override file missing → no effect (graceful)
  - Test: override file malformed → no effect (graceful)
  - Test: exclude action → returns "_EXCLUDED_"
  - Test: approved model recommendation → returns recommended model
  - Test: pending proposal → no effect (only approved overrides apply)
  - Test: expired override → no effect

- [x] 5. Create follow-up beads for Gaps 2-5
