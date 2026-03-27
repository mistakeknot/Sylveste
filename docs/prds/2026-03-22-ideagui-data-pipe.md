---
artifact_type: prd
bead: Sylveste-ef08
stage: design
---

# PRD: IdeaGUI Data Pipe (F1)

## Problem

Meadowsyn's six visual experiments (F2-F7) need factory data. Two real sources are available — ideagui.json (85 agent sessions from Notion) and clavain-cli factory-status (live fleet/queue/WIP) — but they use incompatible identifiers. Bead IDs encode the beads DB prefix (Sylveste-), not the sub-project. WIP hex agent IDs (CLAUDE_SESSION_ID) have no mapping to roster session names. A naive global merge produces silent data loss.

## Solution

Export two independent data readers. Experiments declare which sources they need. F2/F4 get a lightweight project-level join. F3/F6/F7 consume factory-status only. A small Go prerequisite adds a `project` field to factory-status WIP entries (~5 LOC), eliminating downstream prefix parsing.

## Features

### F1-prereq: Enrich factory-status.go
**What:** Add `Project` field to `wipEntry` and `dispatchEntry` structs.
**Acceptance criteria:**
- [ ] `wipEntry` has `Project string \`json:"project"\`` field
- [ ] Project derived from `strings.ToLower(strings.SplitN(b.ID, "-", 2)[0])`
- [ ] `clavain-cli factory-status --json` WIP entries include `"project": "sylveste"`
- [ ] Existing consumers unaffected (additive JSON field)

### F1a: IdeaGUI Reader
**What:** Parse `transfer/ideagui/ideagui.json` and return the roster. Read once at startup, re-read on mtime change.
**Acceptance criteria:**
- [ ] Reads and validates ideagui.json (throws on missing file or malformed JSON)
- [ ] Returns `{ meta, summary, sessions }` matching the existing schema
- [ ] Caches result; only re-reads when file mtime changes

### F1b: Factory-Status Reader
**What:** Call `clavain-cli factory-status --json` via `execFileSync` (no shell) and parse output.
**Acceptance criteria:**
- [ ] Executes `clavain-cli factory-status --json` with 10s timeout
- [ ] Returns `{ timestamp, fleet, queue, wip, dispatches, watchdog, factory_paused }`
- [ ] Throws on non-zero exit or malformed output

### F1c: Snapshot Generator
**What:** Combine both layers into a snapshot. Project-level join for experiments that need it. Expose unmatched WIP.
**Acceptance criteria:**
- [ ] `generateSnapshot()` returns both layers in a single object
- [ ] WIP entries joined to roster at project level using WIP `project` field
- [ ] Each roster session gets `active_beads[]` (shared across project — documented as project-level, not session-level)
- [ ] `by_project` rollup: `{ [project]: { sessions, active_beads, terminals, agent_types } }`
- [ ] `meta.join_coverage`: percentage of WIP beads matched to a roster project
- [ ] Unmatched WIP beads (prefix doesn't match any roster project) counted in meta, not silently dropped
- [ ] Roster read from cache (not re-parsed every snapshot)

### F1d: CLI Entry Point
**What:** `cli.js` wrapping the module for terminal usage.
**Acceptance criteria:**
- [ ] `node cli.js` outputs single JSON snapshot to stdout
- [ ] `node cli.js --stream` emits one JSON line per interval (default 5s)
- [ ] `--interval N` sets poll interval (validated: NaN → error, minimum 1s)
- [ ] `--ideagui-path <path>` overrides default location
- [ ] `--factory-only` flag: skip roster, emit factory-status layer only (for F3/F6/F7)
- [ ] Exit cleanly on SIGINT/SIGTERM. Catch per-tick errors in stream mode (don't crash on transient failure).

## Non-goals

- **Per-agent matching** — no FK between WIP hex IDs and roster sessions. Phase 2 (SessionStart hook).
- **Sub-project granularity** — bead prefix maps to DB, not component. `Sylveste-ef08` maps to `sylveste`, not `meadowsyn`.
- **History/ring buffer** — F8 (DataPipe) owns snapshot history.
- **Webhook updates** — Phase 2 concern.

## Dependencies

- `clavain-cli` on PATH with `factory-status --json` supporting `project` field (F1-prereq)
- `transfer/ideagui/ideagui.json` synced via mutagen
- Node.js >= 18

## Resolved Questions

- Join strategy: project-level via factory-status `project` field (not bead prefix parsing in JS)
- Hard fail: per-experiment, not global. `--factory-only` flag for experiments that don't need roster.
- Refresh: roster cached at startup, factory-status polled every 5s.
