---
artifact_type: prd
bead: Demarch-og7m
stage: design
batch: 3
---
# PRD: Monorepo Consolidation Batch 3

## Problem

Batch 2 hardened safety floors, phase gates, autonomy, shadow tracking, and subagent routing. But the multi-agent coordination layer has three gaps that manifest at 5+ concurrent agents: unbounded reservation accumulation starves other agents, interspect evidence writes silently fail under contention, and no CODEOWNERS means merge chaos as contributor count grows.

## Solution

Three targeted fixes to the multi-agent coordination surface: reservation resource limits, SQLite write durability, and GitHub governance.

## Features

### F1: Reservation Resource Limits (.12)

**What:** Add per-agent reservation cap (max 10 active), TTL ceiling (max 24 hours), and expired reservation cleanup sweep.

**Root cause:** `Reserve()` in `intermute/internal/storage/sqlite/sqlite.go:1450-1548` has no `COUNT(*) WHERE agent_id = ? AND released_at IS NULL` check before insert. No TTL cap — callers can request arbitrarily long durations. Expired reservations persist forever.

**Files:**
- `core/intermute/internal/storage/sqlite/sqlite.go` — add limit check + TTL cap in Reserve()
- `core/intermute/internal/http/handlers_reservations.go` — validate TTL in request handler

**Acceptance criteria:**
- [ ] Reserve() rejects when agent has >= 10 unreleased reservations (returns error with count)
- [ ] TTL capped at 1440 minutes (24h) regardless of request value
- [ ] Expired reservations auto-swept on Reserve() call (opportunistic cleanup, same transaction)
- [ ] Existing tests pass — no behavioral change for agents within limits
- [ ] Per-agent limit configurable via constant (easy to adjust later)

### F2: Interspect Evidence Write Durability (.27)

**What:** Set `busy_timeout=5000`, add retry wrapper for SQLite writes, and log evidence insertion failures instead of silently swallowing them.

**Root cause:** `lib-interspect.sh:130-232` opens interspect.db with WAL mode but no `busy_timeout` (defaults to 0ms — immediate fail). All `sqlite3` calls use `|| true` which silently swallows `SQLITE_BUSY` errors. At 5+ concurrent agents writing evidence, insertions are lost with no trace.

**Files:**
- `interverse/interspect/hooks/lib-interspect.sh` — busy_timeout, retry wrapper, error logging

**Acceptance criteria:**
- [ ] `PRAGMA busy_timeout=5000` set in schema initialization
- [ ] New helper `_interspect_sqlite_write()` wraps sqlite3 calls with 3x retry (1s, 2s, 4s backoff)
- [ ] Failed writes after retry log to stderr with table name, error, and SQL fragment
- [ ] Existing `|| true` patterns replaced with `_interspect_sqlite_write` for INSERT/UPDATE operations
- [ ] SELECT queries unchanged (reads don't contend under WAL)
- [ ] `bash -n` syntax check passes

### F3: CODEOWNERS (.26)

**What:** Create `.github/CODEOWNERS` at monorepo root with per-pillar ownership mapping.

**Root cause:** Monorepo root has no CODEOWNERS. Subproject CODEOWNERS don't apply at GitHub repo level. Any approver can merge changes to high-risk paths (kernel, hooks, manifests).

**Files:**
- Create: `.github/CODEOWNERS`

**Acceptance criteria:**
- [ ] High-risk paths mapped: `core/` (intercore, intermute), `os/Clavain/`, `os/Skaffen/`, key Interverse plugins
- [ ] `@mistakeknot` as owner for all kernel paths
- [ ] Wildcard fallback `* @mistakeknot` for uncovered paths
- [ ] File uses GitHub CODEOWNERS syntax (tested: `gh api repos/mistakeknot/Demarch/codeowners/errors` returns empty)

## Execution Order

```
All parallel — no inter-dependencies:
  ├── F1: Reservation limits (.12) — intermute Go
  ├── F2: Evidence write durability (.27) — interspect bash
  └── F3: CODEOWNERS (.26) — monorepo root
```

## Non-goals

- Event pipeline nucleation (.17) — deferred, needs per-source cursor design
- Event schema typed contract (.21) — deferred, needs JSONSchema + validation pipeline
- Circular-wait deadlock (.29) — deferred, rare edge case at current scale
- Phase FSM lift (.1) / Event unification (.2) — dedicated sub-epics

## Dependencies

- F1 (.12): None
- F2 (.27): None
- F3 (.26): None
