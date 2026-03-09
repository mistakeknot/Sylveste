---
artifact_type: prd
bead: iv-g36hy
stage: strategize
---

# PRD: CXDB Sprint Execution Recording

**Date:** 2026-03-09
**Bead:** iv-g36hy (P1)
**Brainstorm:** [docs/brainstorms/2026-03-09-cxdb-sprint-recording.md](../brainstorms/2026-03-09-cxdb-sprint-recording.md)

## Problem

Sprint execution produces observable data — phase transitions, agent dispatches, artifacts, token costs — but this data is scattered across Intercore events (phases), interstat (tokens), and verdict files (agent results). The CXDB infrastructure exists in clavain-cli but is not wired into the actual sprint lifecycle. `/reflect` and `/galiana` have no structured source for "what happened in this sprint."

## Goal

Make CXDB recording automatic during sprints, with zero additional configuration. After this work, any sprint that runs with the CXDB server available will produce a complete Turn DAG timeline queryable via `clavain-cli cxdb-history <bead-id>`.

## Non-Goals

- Scenario bank or satisfaction scoring (deferred to Gurgeh)
- MCP tool exposure for in-conversation querying
- Cross-sprint aggregation or dashboards
- CXDB server distribution/packaging

## Features

### F1: Lazy CXDB Auto-Start

**What:** When any CXDB recording function fires and the server isn't running, attempt to start it automatically. If the binary isn't installed, silently skip (fail-open preserved).

**Why:** Currently, CXDB recording only works if someone manually runs `clavain-cli cxdb-start`. Nobody does this, so zero sprints produce CXDB data.

**Acceptance:**
- `cxdbRecordPhaseTransition` auto-starts CXDB if binary exists and server not running
- If binary doesn't exist, recording silently no-ops (existing behavior)
- Auto-start adds ≤1s latency on first recording in a session

### F2: Dispatch Recording from Verdicts

**What:** After quality-gates completes, read `.clavain/verdicts/*.json` and write `clavain.dispatch.v1` turns for each agent that ran.

**Why:** `cxdbRecordDispatch` exists as dead code — nothing calls it. Verdicts are the most structured source of dispatch data.

**Acceptance:**
- Each verdict file produces one dispatch turn with agent_name, status, and timestamp
- Duplicate verdicts (same agent + bead + timestamp) are idempotent (no duplicate turns)

### F3: Dispatch Record Enrichment

**What:** Add `duration_ms`, `error_message` fields to `DispatchRecord`. Bump type to `clavain.dispatch.v2` in the bundle.

**Why:** Current DispatchRecord has no way to record failure reasons or timing. These are essential for `/galiana` cost analysis.

**Acceptance:**
- `cxdb-types.json` has `clavain.dispatch.v2` with new fields
- Old `v1` turns remain readable
- Go struct has msgpack tags for new fields

### F4: Artifact Hash Recording

**What:** When `set-artifact` is called (brainstorm, plan, PRD file association), compute BLAKE3 hash of the file and write a `clavain.artifact.v1` turn.

**Why:** Artifacts are referenced by path in phase turns, but their content integrity isn't tracked. Hash recording enables "did the plan change between plan-review and execution?" queries.

**Acceptance:**
- `cmdSetArtifact` calls `cxdbRecordArtifact` with BLAKE3 hash of the file
- Hash computation is in Go (no external binary)
- Files that don't exist are silently skipped (artifact may be set before file is written)

### F5: History Query CLI

**What:** `clavain-cli cxdb-history <bead-id>` outputs a JSON timeline of all turns for a sprint.

**Why:** No way to inspect the Turn DAG from the shell. `/reflect` needs to read sprint history to capture learnings.

**Acceptance:**
- Outputs JSON array sorted by timestamp
- Each entry has: turn_id, type_id, decoded payload (JSON, not msgpack), timestamp
- If CXDB server not running, returns error "CXDB not available"
- If no context exists for bead, returns empty array

### F6: Incremental Sync Cursor

**What:** `cxdb-sync` persists last-synced event ID and only processes new events on subsequent runs.

**Why:** Current sync is one-shot — re-processes all events every time. With incremental sync, it can run periodically without duplicating work.

**Acceptance:**
- `ic state set cxdb_sync_cursor_<bead_id>` tracks last processed event ID
- Second run of `cxdb-sync <bead-id>` only processes events after the cursor
- If cursor state is missing, full sync (backward compatible)

## Implementation Order

F1 → F3 → F4 → F2 → F5 → F6

- F1 first because all other features depend on CXDB being available
- F3 before F2 because verdict sync needs the enriched dispatch type
- F5 after recording features so there's data to query
- F6 last because it's an optimization

## Success Criteria

After this work:
1. A sprint that runs phases brainstorm → strategy → plan → execute → quality-gates produces ≥8 CXDB turns (phase transitions + verdicts)
2. `clavain-cli cxdb-history <bead-id>` returns a readable timeline
3. Zero additional steps required from the user — recording is automatic
