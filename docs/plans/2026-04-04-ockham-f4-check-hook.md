---
artifact_type: plan
bead: sylveste-32p
stage: plan
---

# F4: `ockham check` + SessionStart hook

PRD: `docs/prds/2026-04-04-ockham-wave1-foundation.md` lines 75-88

## Overview

Add the `ockham check` command — the runtime heartbeat that evaluates signal state, persists authority snapshots, handles re-confirmation timers, and reconstructs sentinels. Wire it into Clavain's SessionStart hook behind a 5-minute TTL.

## Task Breakdown

### T1: `internal/signals/` package + schema (30 min)

New package `internal/signals/` with CGo-free SQLite (`modernc.org/sqlite`).

**Files:**
- `internal/signals/db.go` — `DB` struct, `NewDB(path)`, `Close()`, `WasRecovered() bool`, `ensureSchema()`, `migrateSchema()`
- `internal/signals/db_test.go` — roundtrip tests

**Schema** (version 1):
```sql
CREATE TABLE schema_meta (version INTEGER NOT NULL);
CREATE TABLE signal_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE authority_snapshot (
    agent TEXT NOT NULL,
    domain TEXT NOT NULL,
    hit_rate REAL NOT NULL,
    sessions INTEGER NOT NULL,
    confidence REAL NOT NULL,
    captured_at INTEGER NOT NULL,
    PRIMARY KEY (agent, domain)
);
CREATE TABLE ratchet_state (
    agent TEXT NOT NULL,
    domain TEXT NOT NULL,
    tier TEXT NOT NULL DEFAULT 'shadow',
    promoted_at INTEGER NOT NULL DEFAULT 0,
    demoted_at INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (agent, domain)
);
```

`signal_state` is a key-value bag for timestamps, confirmation windows, and ephemeral state. Ratchet/authority get their own tables because F5/F6 need structured queries.

**Recovery (error-class aware):** `NewDB()` classifies open errors:
- **Corruption** (`SQLITE_CORRUPT`, `SQLITE_NOTADB`, `PRAGMA integrity_check` != "ok", missing file): delete and recreate with defaults. Set `wasRecovered=true`. Log warning to stderr.
- **Transient** (`SQLITE_BUSY`, `SQLITE_LOCKED`): return error directly — do NOT delete the DB. Caller treats as degraded (skip check this session).
- **Schema version mismatch** (file exists, integrity ok, version < expected): run forward migrations (`ALTER TABLE` etc.), not delete+recreate. Only version 1 exists in Wave 1, but the migration path is established for F5/F6 schema additions.

Constructor: `NewDB(path) (*DB, error)` — follows `halt.New()` / `intent.NewStore()` convention. Recovery state exposed via `db.WasRecovered() bool` method (not a return value).

**Default path:** `~/.config/ockham/signals.db` via `DefaultDBPath()` (uses `os.UserConfigDir()` + fallback, matching `halt.DefaultSentinelPath()`).

**Concurrent safety:** All ratchet writes use conditional SQL (`INSERT ... WHERE NOT EXISTS` / `UPDATE ... WHERE promoted_at = 0`) so concurrent cold-starts are first-writer-wins, not last-writer-wins.

**Dependency:** Add `modernc.org/sqlite` to go.mod.

### T2: `ockham check` command skeleton (20 min)

**Files:**
- `cmd/ockham/check.go` — `checkCmd` cobra command, `runCheck()` function

**Behavior:**
1. Open signals.db (recovery on failure)
2. If recovered → set `cold_start=true`
3. Run registered evaluators (initially empty — F5/F6 register theirs)
4. Write results to signals.db
5. Reconstruct factory-paused.json if needed (T4)
6. Close db

**Flags:**
- `--dry-run` — run steps, print what would change, don't write

**Structure:** Local `CheckRunner` struct in `check.go` owns DB lifecycle:
```go
type CheckRunner struct {
    db          *signals.DB
    haltPath    string
    dryRun      bool
}
```

No named `Evaluator` interface in Wave 1 — defer until F5 ships a second evaluator. F4 calls authority snapshot (T3), halt reconstruction (T4), and re-confirmation (T5) as direct method calls on `CheckRunner`. F5 extracts the interface when a concrete second caller exists.

Wave 1: `ockham check` opens the DB, snapshots authority, reconstructs halt sentinel, checks re-confirmation timers, and exits.

### T3: Authority snapshot persistence (20 min)

**Files:**
- `internal/signals/authority.go` — `SaveAuthoritySnapshot(agent, domain, hitRate, sessions, confidence)`, `GetAuthoritySnapshot(agent, domain)`
- `internal/signals/authority_test.go`

**Behavior in `ockham check`:**
1. Read `~/.clavain/interspect/confidence.json` (existing file written by interspect)
2. Parse per-agent hit rates
3. Upsert into `authority_snapshot` table
4. Skip silently if confidence.json doesn't exist (interspect not yet running)

### T4: Factory-paused.json reconstruction (15 min)

**Files:**
- `cmd/ockham/check.go` — reconstruction as `CheckRunner.reconstructHalt()` method (command layer, not `halt/` — halt stays read-only)

**Behavior in `ockham check`:**
1. If `factory-paused.json` exists → skip (nothing to reconstruct)
2. Read interspect halt record **directly from file** (`~/.clavain/interspect/halt-record.json`) — NO shell-out to `ic`. Define minimal internal struct: `type haltRecord struct { EventID string; Timestamp int64; Reason string }`.
3. If active halt record exists AND sentinel file missing → recreate `factory-paused.json` from record data
4. Source is interspect file, NOT signals.db — interspect is the agent-unwritable sentinel
5. If halt record file doesn't exist → skip silently (fail-open for reconstruction, not for the sentinel itself)
6. Comment documenting the coupling: interspect halt record format is not yet a stable contract

### T5: 30-day re-confirmation trigger (15 min)

**Files:**
- Add to `cmd/ockham/check.go` as `CheckRunner.checkReconfirmation()` method

**Behavior:**
1. Query `ratchet_state` for rows where `tier='autonomous'`
2. For each: use `time.Since(time.Unix(promotedAt, 0))` for duration check (not raw epoch arithmetic)
3. Sanity guard: if `promoted_at` is in the future or > 1 year ago, treat as corrupt → re-confirm immediately (conservative)
4. If overdue → emit re-confirmation (Wave 1: log + set `signal_state` key `reconfirm:<agent>:<domain>=pending`)
5. Stagger: each domain's timer is independent (keyed by its own `promoted_at`)
6. `promoted_at` is set internally at write time, never accepted as caller-supplied input
7. Wave 1 just flags — F6 acts on the flag during ratchet evaluation

### T6: SessionStart hook wiring (15 min)

**Files:**
- `os/Clavain/hooks/session-start.sh` — add ockham check block near the `bd doctor` TTL sentinel (around line 130)

**Pattern** (matches existing `bd doctor` TTL):
```bash
if command -v ockham &>/dev/null; then
    _ock_sentinel="$HOME/.config/ockham/.check-ttl"
    _ock_age=999
    [[ -f "$_ock_sentinel" ]] && _ock_age=$(( $(date +%s) - $(stat -c %Y "$_ock_sentinel" 2>/dev/null || echo 0) ))
    if [[ "$_ock_age" -gt 300 ]]; then
        ockham check 2>/dev/null || true
        mkdir -p "$(dirname "$_ock_sentinel")" 2>/dev/null || true
        touch "$_ock_sentinel" 2>/dev/null || true
    fi
fi
```

Fail-open: if ockham binary not on PATH, skip entirely. If check fails, still touch sentinel (don't retry every session).

### T7: Tests (20 min)

**Go tests** (run with `go test ./... -count=1`):
- `internal/signals/db_test.go` — NewDB/Close, schema creation, recovery from corrupt DB (delete+recreate), transient SQLITE_BUSY (error, no delete), recovery from missing file, schema migration path, concurrent-safe conditional writes
- `internal/signals/authority_test.go` — Save/Get roundtrip, upsert overwrites
- `cmd/ockham/check_test.go` — --dry-run doesn't write, WasRecovered set on corruption recovery, halt reconstruction from file (no ic dependency), re-confirmation sanity guards (future timestamp → immediate reconfirm)

**Shell syntax check:**
- `bash -n os/Clavain/hooks/session-start.sh`

## Execution Order

```
T1 (signals package) → T2 (check command) → T3 (authority) ─┐
                                                              ├→ T7 (tests)
                                           T4 (halt recon) ──┤
                                           T5 (reconfirm) ───┘
T6 (SessionStart hook) — independent, can parallel with T3-T5
```

T1 first (foundation). T2 depends on T1. T3/T4/T5 are independent features within `ockham check` — can be written in any order after T2. T6 is pure shell, independent of Go code. T7 is ongoing (write tests with each task).

## Acceptance Criteria Mapping

| PRD Criterion | Task |
|---|---|
| `ockham check` reads/evaluates/writes signals.db | T1, T2 |
| signals.db schema (timestamps, ratchet, authority, version) | T1 |
| signals.db recovery (fail-safe, not fail-open) | T1 |
| Authority snapshot persistence after interspect read | T3 |
| 30-day re-confirmation (staggered) | T5 |
| TTL sentinel in SessionStart hook | T6 |
| `--dry-run` flag | T2 |
| Reconstruct factory-paused.json from interspect halt record | T4 |
