---
artifact_type: brainstorm
bead: iv-g36hy
stage: discover
---

# CXDB Sprint Execution Recording

**Date:** 2026-03-09
**Bead:** iv-g36hy (P1, subsumes iv-296)
**Status:** Brainstorm
**Depends on:** None (self-contained — CXDB client already vendored)

## Executive Summary

The bead description says "adds pkg/cxdb/ to clavain-cli with Go SDK integration, type bundle registration, and fork support." But the codebase tells a different story: **80% of this is already built.** The vendored StrongDM CXDB Go client is integrated, 7 type schemas exist in `config/cxdb-types.json`, and phase transitions are already recorded via `cxdbRecordPhaseTransition()` called from `phase.go:407`.

What's actually missing is the **wiring** — making the recording happen reliably during real sprints, not just in theory.

## Current State (What Exists)

### Infrastructure (done)

| Component | File | Status |
|---|---|---|
| CXDB server lifecycle | `cxdb.go` | setup, start, stop, status |
| Client connection | `cxdb_client.go:19-41` | singleton Dial to localhost:9009 |
| Sprint context mapping | `cxdb_client.go:44-71` | bead ID → CXDB context via `ic state` |
| Phase recording | `cxdb_client.go:107-112` | `clavain.phase.v1` turns |
| Dispatch recording | `cxdb_client.go:114-120` | `clavain.dispatch.v1` turns |
| Artifact blob storage | `cxdb_client.go:123-131` | `clavain.artifact.v1` turns |
| Fork support | `cxdb_client.go:134-141` | O(1) context branching |
| Sync from intercore | `cxdb_client.go:186-250` | backfill from `ic run events` |
| Type bundle | `config/cxdb-types.json` | 7 types registered |
| Best-effort helper | `cxdb_client.go:252-276` | fail-open phase recording |
| Phase.go integration | `phase.go:407` | calls `cxdbRecordPhaseTransition` on advance |
| Evidence recording | `evidence.go:200` | calls `cxdbRecordEvidence` on evidence collect |

### Wiring Gaps (what's actually needed)

1. **Dispatch recording is dead code.** `cxdbRecordDispatch` exists but nothing calls it. Dispatches from quality-gates, flux-drive, and parallel agents go unrecorded.

2. **No artifact recording on creation.** When brainstorm, plan, PRD files are created, `cxdbStoreBlob` is never called. The artifact path is recorded in phase transitions, but the content isn't content-addressed.

3. **CXDB server isn't auto-started.** Sprint execution (`/clavain:sprint`) doesn't ensure CXDB is running. If it's not running, all recording silently no-ops (by design — fail-open). This means real sprints produce zero CXDB data unless someone manually runs `clavain-cli cxdb-start`.

4. **No dispatch lifecycle tracking.** A dispatch has start/end, tokens, and result — but only a single `DispatchRecord` struct. There's no way to record "dispatch started" then "dispatch completed with tokens."

5. **Sync is one-shot, not continuous.** `cxdb-sync` backfills from intercore events, but doesn't maintain a cursor for incremental sync.

6. **No query CLI.** Can't inspect the Turn DAG from the shell. `cxdb-fork` exists but there's no `cxdb-inspect` or `cxdb-history`.

7. **Scenario and satisfaction types are unused.** Types exist in the bundle but have no Go structs or recording functions.

## Design Decisions

### D1: Auto-start vs Explicit Opt-in

**Options:**
- **A: Auto-start in sprint-create** — When `clavain-cli sprint-create` runs, also start CXDB if not running. Pro: zero config. Con: another server process.
- **B: Lazy connect on first record** — When any `cxdbRecord*` function is called, check if server is running, start if not. Pro: truly invisible. Con: 500ms latency on first recording in a sprint.
- **C: Explicit opt-in via environment** — `CLAVAIN_CXDB_ENABLED=true`. Pro: no surprise processes. Con: nobody will set it.

**Recommendation: B (lazy connect)** — The fail-open pattern already handles "server not available." Adding a "server not available → start it → retry" step makes recording automatic without surprising behavior. The 500ms startup delay only hits once per session.

### D2: Dispatch Lifecycle (single-event vs start/end pair)

**Options:**
- **A: Single event with final state** — One `clavain.dispatch.v1` turn written when dispatch completes. Contains start_time, end_time, tokens.
- **B: Start/end pair** — Two turns: `clavain.dispatch_start.v1` (agent, model, intent) and `clavain.dispatch_end.v1` (status, tokens, result_hash). Pro: can detect crashed dispatches (start without end). Con: more complex, more types.
- **C: Single event, status field** — Current design. One turn, `status` field is `"started"` or `"completed"` or `"failed"`. Multiple turns per dispatch.

**Recommendation: A (single event, final state)** — Simplest. Crashed dispatches are already handled by the sprint timeout. We don't need sub-second observability of agent dispatches — we need a post-hoc audit trail. Add `duration_ms` and `error_message` fields to the existing `DispatchRecord`.

### D3: Artifact Content Addressing

**Options:**
- **A: CXDB blob storage** — Store file contents as CXDB blobs via the binary API. Pro: everything in one place. Con: CXDB server must be running to read artifacts.
- **B: Filesystem CAS** — `.clavain/blobs/<blake3-hash>`. Pro: readable without CXDB. Con: two systems.
- **C: Hash-only references** — Record the BLAKE3 hash and path in the turn, don't store content. The file itself is in the git repo. Pro: minimal. Con: can't recover deleted artifacts.

**Recommendation: C (hash-only references)** — Artifacts (brainstorms, plans, PRDs) already live in git-tracked `docs/`. Duplicating them into CXDB or a CAS adds complexity for zero benefit. The hash lets us verify integrity; git provides storage and history.

### D4: Where to Wire Dispatch Recording

The dispatch recording needs to intercept agent launches. Current dispatch paths:

| Dispatch Path | File | How Agents Are Launched |
|---|---|---|
| Quality gates | `quality-gates.md` SKILL | Agent tool with subagent_type |
| Flux-drive review | `flux-drive.md` SKILL | Agent tool with subagent_type |
| Sprint parallel work | `dispatching-parallel-agents.md` SKILL | Agent tool |
| Codex delegation | `codex-delegate` agent | Bash `codex exec` |
| Direct subagent | `/clavain:work` | Agent tool in plan execution |

**Problem:** These are all prompt-level orchestration. The Agent tool doesn't call clavain-cli before/after dispatch. There's no hook point.

**Options:**
- **A: Post-hoc from interstat** — interstat already tracks token usage per session. Build a `cxdb-sync-dispatches` command that reads interstat data and writes dispatch turns.
- **B: Hook-based** — Add a clavain hook (post-tool or post-agent) that calls `clavain-cli cxdb-record-dispatch` after each agent dispatch.
- **C: Verdict-based** — After quality-gates, the verdict system already writes structured files to `.clavain/verdicts/`. Read those and generate dispatch turns.

**Recommendation: A+C hybrid** — Use verdicts for quality-gate dispatches (most structured data). Use interstat for token attribution. Don't try to intercept Agent tool calls — that's fighting the abstraction.

### D5: Query Interface

**Options:**
- **A: CLI only** — `clavain-cli cxdb-history <bead-id>` outputs JSON timeline.
- **B: CLI + MCP** — Also expose via MCP tools for in-conversation querying.
- **C: CLI + dashboard** — Render a TUI or HTML timeline.

**Recommendation: A** — Start with CLI. The primary consumer is `/reflect` (which needs to see what happened in a sprint) and `/galiana` (which needs aggregate stats). Both can parse JSON. MCP exposure can come later.

## Implementation Scope (What's Actually Needed)

Given the infrastructure is already built, the real work is narrow:

### W1: Lazy auto-start (D1 decision)

Modify `cxdbRecordPhaseTransition` and friends to attempt `cmdCXDBStart` on first invocation if server not running. Approximately 15 lines.

### W2: Dispatch recording from verdicts (D4 decision)

New function `cxdbSyncVerdicts(beadID)` that reads `.clavain/verdicts/*.json`, extracts agent name, model, status, and token estimates, and writes `clavain.dispatch.v1` turns. Called after quality-gates completes.

### W3: Dispatch recording enrichment

Add `duration_ms`, `error_message`, `start_time`, `end_time` fields to `DispatchRecord` and `cxdb-types.json`. Bump to `clavain.dispatch.v2`.

### W4: Artifact hash recording

New function `cxdbRecordArtifactHash(beadID, artifactType, path)` that computes BLAKE3 of the file and writes a `clavain.artifact.v1` turn. Called from `cmdSetArtifact` in phase.go.

### W5: History query CLI

New command `cxdb-history <bead-id>` that connects to CXDB, queries all turns for the sprint context, and outputs a JSON timeline sorted by timestamp. Approximately 40 lines.

### W6: Incremental sync cursor

Modify `cmdCXDBSync` to persist `last_synced_event_id` via `ic state` and only process new events on subsequent runs. Approximately 10 lines.

## Out of Scope (Explicitly Deferred)

- **Scenario/satisfaction recording** — Types exist but no consumers. Ship when Gurgeh scenarios are built.
- **MCP tools** — Query via MCP. Ship when autarch-mcp integration happens.
- **Cross-sprint DAG visualization** — Interesting but no immediate consumer.
- **CXDB server binary packaging** — `cxdb-setup` downloads from GitHub releases. Works for dev; packaging for distribution is a separate concern.

## Risks

1. **CXDB server binary availability.** If the `cxdb-server` binary isn't installed, everything silently no-ops. This is the correct behavior — recording is additive observability, not a correctness requirement. But it means early sprints won't have data.

2. **Vendor CXDB client stability.** The vendored Go client at `vendor-src/cxdb/clients/go/` is from StrongDM's public repo. If the binary protocol changes, the client breaks. Mitigation: pin the server version in `cxdb-setup --version`.

3. **Dolt interaction.** CXDB uses its own data directory (`.clavain/cxdb/data/`), separate from beads' Dolt. No interaction expected, but two databases increases operational surface.

## Open Questions

1. **Should iv-296 be closed?** The bead describes "adopt CXDB architecture as lightweight embedded infrastructure." That's already done — vendored client, type bundle, recording functions, server lifecycle management. The remaining work (wiring) is iv-g36hy's scope. Recommend: close iv-296 as "already implemented (infrastructure layer)" and make iv-g36hy self-contained.

2. **Should iv-ho3 still block this?** iv-ho3 (StrongDM Factory Substrate) is a meta-epic covering 6 capabilities. CXDB is just one of them (#2). The CXDB infrastructure is already built without waiting for the full factory substrate. Recommend: remove iv-ho3 as a blocker for iv-g36hy.

3. **Verdict file format.** The verdict system writes JSON files, but is the schema stable enough to parse programmatically? Need to verify the structure in `lib-verdict.sh`.
