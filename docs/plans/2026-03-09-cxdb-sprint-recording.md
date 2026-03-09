# Plan: CXDB Sprint Execution Recording

**Bead:** iv-g36hy
**Date:** 2026-03-09
**PRD:** [docs/prds/2026-03-09-cxdb-sprint-recording.md](../prds/2026-03-09-cxdb-sprint-recording.md)
**Brainstorm:** [docs/brainstorms/2026-03-09-cxdb-sprint-recording.md](../brainstorms/2026-03-09-cxdb-sprint-recording.md)

## Goal

Wire CXDB recording into the sprint lifecycle so it happens automatically. All changes in `os/clavain/cmd/clavain-cli/`.

## Tasks

### T1: Lazy auto-start in recording helpers
**Files:** `cxdb_client.go`

- [x] Add `cxdbEnsureRunning()` function: checks `cxdbAvailable()`, if false and binary exists (`cxdbBinaryPath()` stat), calls `cmdCXDBStart(nil)`. Returns bool. Cache result in package-level `var cxdbStartAttempted bool` to avoid retrying in same process.
- [x] Replace `if !cxdbAvailable() { return }` in `cxdbRecordPhaseTransition` with `if !cxdbEnsureRunning() { return }`
- [x] Do the same for `cxdbRecordEvidence` in `evidence.go`

### T2: Enrich DispatchRecord and bump type version
**Files:** `cxdb_client.go`, `config/cxdb-types.json`

- [x] Add fields to `DispatchRecord`: `DurationMs uint64 (tag 10)`, `ErrorMessage string (tag 11)`
- [x] Add `clavain.dispatch.v2` to `cxdb-types.json` with new fields (keep `v1` for backward compat)
- [x] Update `cxdbRecordDispatch` to use type ID `"clavain.dispatch.v2"`

### T3: Artifact hash recording in set-artifact
**Files:** `phase.go`, `cxdb_client.go`

- [x] Add `cxdbRecordArtifact(beadID, artifactType, path string)` function using `zeebo/blake3` (already indirect dep)
- [x] Call `cxdbRecordArtifact` at end of `cmdSetArtifact` (after the ic artifact add)

### T4: Dispatch recording from verdict files
**Files:** `cxdb_client.go` (new function), `main.go` (new command)

- [x] Add `cmdCXDBSyncVerdicts(args []string) error` with verdict JSON parsing
- [x] Register `"cxdb-sync-verdicts"` in `main.go` switch

### T5: History query CLI
**Files:** `cxdb_client.go` (new function), `main.go` (new command)

- [x] Add `cmdCXDBHistory(args []string) error` with msgpack→JSON decoding
- [x] Register `"cxdb-history"` in `main.go` switch

### T6: Incremental sync cursor
**Files:** `cxdb_client.go`

- [x] Read cursor from `ic state get cxdb_sync_cursor_<bead_id>`
- [x] Filter events to only those after cursor
- [x] Write cursor after processing: `ic state set cxdb_sync_cursor_<bead_id> <last_event_id>`

### T7: Tests
**Files:** `cxdb_client_test.go`, `cxdb_test.go`

- [x] Test `cxdbEnsureRunning` returns false when no binary exists
- [x] Test `DispatchRecord` v2 msgpack round-trip with new fields (DurationMs, ErrorMessage)
- [x] Test `cmdCXDBHistory` with no CXDB server (graceful error)
- [x] Test verdict file JSON parsing
- [x] Test `cxdbRecordArtifact` no-ops gracefully when no server
- [x] Update type bundle test count (7 → 8 types)

## Execution Order

T1 → T2 → T3 → T4 → T5 → T6 → T7

## Risks

- **BLAKE3 dependency** (T3): Used `zeebo/blake3` (already indirect dep from CXDB client). Promoted to direct. No new dependencies.
- **Verdict file format** (T4): Verified against real `.clavain/verdicts/fd-architecture.json`. Format is stable.
- **CXDB server binary** (T1): Lazy-start only works if binary is installed. No binary = silent no-op = same as today.
