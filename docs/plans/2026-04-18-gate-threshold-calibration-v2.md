---
artifact_type: plan
bead: sylveste-myyw.7
stage: plan
date: 2026-04-18
prd: docs/prds/2026-04-18-gate-threshold-calibration-v2.md
brainstorm: docs/brainstorms/2026-04-18-gate-threshold-calibration-v2-brainstorm.md
---

# Plan: Gate-threshold calibration schema v2

Execute in `os/Clavain/` — it's a separate git repo; commit from inside that directory.

Dependencies: `modernc.org/sqlite` (already in `os/Clavain/cmd/clavain-cli/go.mod`). No new modules.

## Pre-flight

- **Git branch:** work from `os/Clavain/` on a new branch `myyw.7-gate-cal-v2`.
- **Test running:** `cd os/Clavain/cmd/clavain-cli && /usr/local/go/bin/go test ./...` — establish green baseline before touching code.

## Task sequence

### T1 — Create `internal/gatecal` package skeleton
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/gatecal.go` (new) — package doc, types, DB open helper
- `os/Clavain/cmd/clavain-cli/gatecal/gatecal_test.go` (new)

**Content:**
- Package `gatecal`.
- Types: `Outcome` struct (fields per schema in brainstorm: `Ts int64; SessionID string; CheckType, Theme, PhaseFrom, PhaseTo, Verdict, TierAtFire, ThemeSource string; EvidenceRef sql.NullString`).
- `type Store struct { db *sql.DB }`.
- `func Open(path string) (*Store, error)` — wraps `sql.Open("sqlite", path+"?_busy_timeout=5000&_journal_mode=WAL")`, runs `ensureSchema` idempotently.
- `func (s *Store) ensureSchema(ctx context.Context) error` — creates `outcomes`, `tier_state`, `drain_log` tables + `idx_outcomes_theme_ts` if missing.
- Tests: Open creates file + tables; re-open is idempotent; schema matches expected columns (introspect via `PRAGMA table_info`).

**Acceptance:** `go test ./gatecal/...` passes.

### T2 — Outcome writer + theme derivation
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/writer.go` (new)
- `os/Clavain/cmd/clavain-cli/gatecal/writer_test.go` (new)
- `os/Clavain/cmd/clavain-cli/gatecal/theme.go` (new) — theme derivation helper
- `os/Clavain/cmd/clavain-cli/gatecal/theme_test.go` (new)

**Content (writer.go):**
```go
func (s *Store) RecordOutcome(ctx context.Context, o Outcome) error {
  _, err := s.db.ExecContext(ctx,
    `INSERT INTO outcomes (ts, session_id, check_type, theme, phase_from, phase_to, verdict, tier_at_fire, theme_source, evidence_ref) VALUES (?,?,?,?,?,?,?,?,?,?)`,
    o.Ts, o.SessionID, o.CheckType, o.Theme, o.PhaseFrom, o.PhaseTo, o.Verdict, o.TierAtFire, o.ThemeSource, o.EvidenceRef,
  )
  return err
}
```

**Content (theme.go):**
- `func DeriveTheme(beadID, checkType string, bdState func(string, string) (string, bool)) (theme, source string)`:
  - If `bdState(beadID, "theme")` returns non-empty → return `(val, "labeled")`.
  - Else if `checkType` has known prefix (e.g., `safety_*`, `quality_*`, `perf_*`) → return `(prefix, "inferred")`.
  - Else → `("default", "default")`.
- `bdState` is an injected function for testability (prod wires to `bd` subprocess / clavain-cli state helper).

**Tests:** roundtrip outcome through RecordOutcome + `SELECT`; verify nullable `EvidenceRef` works; theme derivation hits all three branches.

**Acceptance:** `go test ./gatecal/...` passes.

### T3.0 — Audit `cmdEnforceGate` variable availability (pre-flight for T3)
**Action only, no file changes.**
Read `phase.go:231-320` end-to-end. Enumerate which of these are in-scope at the insertion point (~line 314): `stateDir`, `beadID`, `checkType`, `fromPhase`, `toPhase`, `verdict`, `tierAtFire`, `bdStateFn`. For any missing: document how to derive (e.g., `tierAtFire` comes from the calibration file IC read; may need a pre-call lookup). Write the audit inline as comments in T3 before coding.

### T3 — Wire RecordOutcome into `cmdEnforceGate`
**Files:**
- `os/Clavain/cmd/clavain-cli/phase.go` (edit `cmdEnforceGate`)

**Content:** After `runIC("gate", "check", runID)` returns in `phase.go:~314`:
```go
store, err := gatecal.Open(filepath.Join(stateDir, "gate.db"))
if err == nil {
    defer store.Close()
    theme, src := gatecal.DeriveTheme(beadID, checkType, bdStateFn)
    _ = store.RecordOutcome(ctx, gatecal.Outcome{
        Ts: time.Now().Unix(),
        SessionID: os.Getenv("CLAUDE_SESSION_ID"),
        CheckType: checkType, Theme: theme, ThemeSource: src,
        PhaseFrom: fromPhase, PhaseTo: toPhase,
        Verdict: verdict, TierAtFire: tierAtFire,
        EvidenceRef: sql.NullString{},
    })
} else {
    fmt.Fprintln(os.Stderr, "gatecal: open failed:", err)
}
```
If the open fails, log + continue. Never fail the gate on calibration error.

**Test:** Add to existing `phase_test.go` a case that invokes `cmdEnforceGate` against a real temp `stateDir`, verifies a row lands in `gate.db:outcomes`. Mock `runIC` if it's currently untestable; otherwise skip the e2e portion and rely on gatecal unit tests.

**Acceptance:** existing `phase_test.go` tests still pass; new test added.

### T4.0 — Extract v1 FPR/FNR formula (pre-flight for T4)
**Action only, no file changes.**
Read `gate_calibration.go:62-242` to pin the exact FPR/FNR formula v1 uses. Port it verbatim into T4's Drain implementation. If the rolling-window interpretation diverges (e.g., v1 computes over all history, v2 over 30-day window), document the divergence in `drain.go` as a comment AND set a `DRAIN_FORMULA_V1_COMPAT` boolean to gate the behavior behind a feature flag until migrated data stabilizes.

### T4 — Rolling-window algorithm + drain transaction
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/drain.go` (new)
- `os/Clavain/cmd/clavain-cli/gatecal/drain_test.go` (new)

**Content (drain.go):**
- `type DrainResult struct { RowsIngested int64; CursorTS int64; StateChanges int64 }`.
- `func (s *Store) Drain(ctx context.Context, now int64, invoker string, windowDays int) (DrainResult, error)`:
  - `BEGIN IMMEDIATE` (write-lock at start). On `SQLITE_BUSY`, retry with jittered backoff up to 3 times (100ms, 250ms+jitter, 500ms+jitter).
  - Read `last_cursor_ts` = `SELECT COALESCE(MAX(cursor_ts),0) FROM drain_log WHERE drain_committed IS NOT NULL`.
  - `INSERT INTO drain_log(drain_started, invoker) VALUES (?, ?)` capturing rowid for later update.
  - Select new outcomes: `SELECT ... FROM outcomes WHERE ts > last_cursor_ts ORDER BY ts`.
  - **Empty case:** if no new rows, `UPDATE drain_log SET drain_committed=?, rows_ingested=0, cursor_ts=? WHERE rowid=?`, COMMIT, return `DrainResult{RowsIngested:0, StateChanges:0}`. Caller maps to exit code 2.
  - **Non-empty case:** group outcomes by `(theme, check_type, phase_from, phase_to)`. For each group:
    - Fetch current tier_state row (or insert default `tier='soft', consecutive_windows_above_threshold=0, change_count_90d=0`).
    - **Partition at last_changed_at:** filter outcomes to `ts > tier_state.last_changed_at` (NULL treated as 0).
    - `effective_n = COUNT(DISTINCT session_id)`, `fpr = count(verdict='fail')/effective_n` where tier=hard; `fnr` = pass-through rate of eventually-bad outcomes (keep v1 formula for symmetry; adapt if v1 diverged).
    - **Promotion check (soft→hard):**
      - Require `tier == 'soft'` AND `locked == 0` AND `effective_n >= 10` AND not (`fnr == 0 AND effective_n < 20`) AND `fnr > fnr_threshold_effective` (`fnr_threshold` override or 0.30 default) AND `change_count_90d <= 2` AND (`last_changed_at IS NULL OR now - last_changed_at >= 7*86400`).
      - If all pass: increment `consecutive_windows_above_threshold`. If counter now ≥ 3, promote tier=hard, set `last_changed_at=now`, increment `change_count_90d`, reset counter to 0. Else just save counter.
      - Else (FNR dropped below threshold): reset counter to 0.
    - UPSERT `tier_state` with new stats.
  - `UPDATE drain_log SET drain_committed=?, rows_ingested=?, cursor_ts=? WHERE rowid=?` where cursor_ts = max(ts) of ingested outcomes.
  - `COMMIT`.

**Tests (table-driven):**
- Empty outcomes → counter not mutated, cursor not advanced, exit=2 semantics (returns `RowsIngested==0, StateChanges==0`).
- Single-session 20 pass outcomes, zero fail → no promotion (small-n + zero-fnr guard).
- 3 sessions × 4 fail each → `effective_n=3`, below 10, no promotion.
- 15 sessions mixed, fnr 0.4, first drain → counter=1, no promote.
- Same → counter=1; second drain with same profile → counter=2; third drain → promote.
- Tier change mid-window: seed outcomes before `last_changed_at`, assert they don't affect stats.
- Concurrent drain (goroutines): start two goroutines both calling `Drain`; both succeed without corruption; one returns `RowsIngested>0`, the other returns `RowsIngested==0`.
- Concurrent drain (processes): spawn a second `clavain-cli calibrate-gate-tiers --auto` via `exec.Command` while the first drain is in `BEGIN IMMEDIATE`; verify the second either waits-then-no-ops (exit 2) or receives `SQLITE_BUSY` and retries successfully — never corrupts cursor.

**Acceptance:** all tests pass; table cases cover all 5 pin-list items.

### T5 — `calibrate-gate-tiers` subcommand
**Files:**
- `os/Clavain/cmd/clavain-cli/gate_calibration.go` (edit — keep existing `cmdCalibrateGateTiers` as wrapper; delegate to new v2 path)

**Content:**
- Extend `cmdCalibrateGateTiers` to:
  1. Check for `.clavain/gate-tier-calibration.json` AND empty `gate.db:tier_state` — if so, run migration (T6).
  2. Parse `--auto` flag; `invoker := "manual"` if unset, `"auto"` if set.
  3. Open gatecal.Store.
  4. Call `Drain(ctx, time.Now().Unix(), invoker, 30)`.
  5. Regenerate backward-compat JSON (T7).
  6. Exit codes: `0` on `RowsIngested > 0 || StateChanges > 0`; `2` on `RowsIngested == 0`; `1` on error. (On `RowsIngested > 0` but `StateChanges == 0`, still exit 0 since outcomes were consumed.)
- Preserve existing stub behavior as fallback path if `gate.db` cannot be opened.

**Acceptance:** `clavain-cli calibrate-gate-tiers --help` shows new `--auto` flag; invoking against empty gate.db returns exit 2; invoking with seeded outcomes returns exit 0.

### T6 — v1 → v2 migration
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/migrate.go` (new)
- `os/Clavain/cmd/clavain-cli/gatecal/migrate_test.go` (new)

**Content:**
- `func (s *Store) MigrateFromV1(ctx context.Context, v1Path string) error`:
  - Check `tier_state` is empty (`SELECT COUNT(*)`). If non-empty, return nil (idempotent).
  - Parse v1 JSON using the existing `GateCalibrationFile` struct from `gate_calibration.go:17-34`.
  - `BEGIN IMMEDIATE`.
  - For each entry, split v1 key (`check_type|phase_from|phase_to`) and INSERT row with `theme='default', theme_source='migrated', origin_key=<v1 key>`.
  - `COMMIT`.
  - `os.Rename(v1Path, v1Path+".v1.json.bak")` — only after COMMIT succeeds.
- Called from T5 before Drain.

**Tests:** seed v1 JSON with 3 entries, run MigrateFromV1, verify 3 rows in tier_state with `theme='default'`, `origin_key` matches; run again, verify no duplicate inserts; verify `.bak` file exists.

**Acceptance:** round-trip test passes; idempotent on re-run.

### T7 — Backward-compat JSON export
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/export.go` (new)
- `os/Clavain/cmd/clavain-cli/gatecal/export_test.go` (new)

**Content:**
- `func (s *Store) ExportV1JSON(ctx context.Context, path string) error`:
  - `SELECT check_type, phase_from, phase_to, tier, fpr, fnr, weighted_n, change_count_90d, locked, last_changed_at FROM tier_state` — grouped by v1 key, **tiebreak: worst-case tier (`hard > soft`)**. If multiple rows share same `(check_type, phase_from, phase_to)`, pick the row with tier=`hard` if any exists; else use the most recently changed row.
  - Marshal into existing `GateCalibrationFile` struct (preserve v1 shape exactly — no new fields).
  - Write atomically via tmp + rename: `os.WriteFile(path+".tmp", ...)`, then `os.Rename(path+".tmp", path)`.

**Tests:**
- Single-theme `default` export matches input → JSON schema-compatible with v1.
- Two themes `default` + `safety` for same key: `safety` has tier=hard, export picks hard.
- Atomic write: verify `.tmp` doesn't linger after successful export.
- **Integration test (T7b):** seed gate.db with known tier_state, run ExportV1JSON, invoke `ic gate check` on the output, verify no parse errors. **Test harness policy:** if `ic` binary is absent, the test builds a **fake `ic gate check`** — a minimal Go test helper that parses v1 JSON using the `GateCalibrationFile` struct and reports parse success. The test NEVER skips silently; it runs either against real `ic` or the fake. Mark real-`ic` path vs fake-path explicitly in test output.

**Acceptance:** export_test.go passes including integration test (or skip with marker if `ic` unavailable).

### T8.0 — hooks.json format audit (pre-flight for T8)
**Action only, no file changes.**
Read existing `os/Clavain/hooks.json` (or `.claude-plugin/plugin.json`). Confirm it uses record format (`{"hooks":{"EventName":[{"hooks":[...]}]}}`) not legacy array format. If array-shaped, flag to user before T8 — switching format affects all other Clavain hooks. If record-shaped, T8 proceeds by adding a SessionEnd sibling entry.

### T8 — SessionEnd hook
**Files:**
- `os/Clavain/hooks/gate-calibration-session-end.sh` (new, executable)
- `os/Clavain/.claude-plugin/plugin.json` or `os/Clavain/hooks.json` (edit — add SessionEnd entry)

**Content (shell):**
```bash
#!/usr/bin/env bash
# SessionEnd hook — recalibrates gate thresholds from accumulated outcomes.
timeout 10 clavain-cli calibrate-gate-tiers --auto 2>&1 | head -20
exit 0  # never block session exit on calibration failure
```

**Content (plugin.json/hooks.json):** register under `SessionEnd` alongside any existing hooks. Record format (not array) per Demarch memory: `{"hooks":{"SessionEnd":[{"hooks":[{"type":"command","command":"<path-to-script>"}]}]}}`.

**Test:** manually run `bash hooks/gate-calibration-session-end.sh` with seeded outcomes, verify exit 0, verify drain_log has a new row.

**Acceptance:** hook executes cleanly under `timeout 10`; plugin.json validates (no ZodError on plugin reload); drain_log populated.

### T9 — Full-flow integration test
**Files:**
- `os/Clavain/cmd/clavain-cli/gatecal/integration_test.go` (new)

**Content:**
- Build temp workspace.
- Seed 30 outcomes across 3 sessions (10 each), fnr=0.40 for one theme, 0.0 for another.
- Run `calibrate-gate-tiers --auto` three times (simulating three consecutive SessionEnds with fresh outcomes mid-way).
- Verify: after run 3, the theme with fnr=0.40 promotes to hard; the theme with fnr=0.0 stays soft.
- Verify `drain_log` has 3 rows with `invoker='auto'`, all with `drain_committed` non-null.
- Verify backward-compat JSON at `.clavain/gate-tier-calibration.json` contains one entry per v1 key with the worst-case tier.

**Acceptance:** integration test green.

### T10 — Docs + changelog
**Files:**
- `os/Clavain/CHANGELOG.md` or equivalent (append)
- `os/Clavain/docs/gate-calibration.md` (new or update)

**Content:**
- One-paragraph note on v2 schema, new subcommand flag, new hook.
- Link to PRD + brainstorm.
- Migration path for users: "automatic on first SessionEnd after upgrade; v1 JSON archived as .bak."

**Acceptance:** docs readable; changelog entry present.

## Test strategy

- Unit tests per file (gatecal package): covers schema init, writer, theme, drain, migrate, export.
- Integration test (T9): covers end-to-end hook → drain → export.
- Existing `phase_test.go`: must still pass after T3 edit.
- Manual smoke test before commit: `cd os/Clavain/cmd/clavain-cli && go test ./... && go build && ./clavain-cli calibrate-gate-tiers --auto` against a real `.clavain/` (confirm exit 2 with empty store).

## Risk mitigations

- **RecordOutcome failure blocks gate:** explicitly guard `cmdEnforceGate` — swallow all gatecal errors, log to stderr only.
- **SQLite concurrency:** `BEGIN IMMEDIATE` + retry handles multi-agent races.
- **Hook exceeds timeout:** `timeout 10` in shell script; exit 0 always; next SessionEnd resumes via cursor.
- **v1 → v2 migration goes wrong:** migration is idempotent, reversible via restoring `.bak`. Don't delete v1 — just rename.
- **Backward-compat JSON corrupts `ic gate check`:** keep v1 shape exactly; integration test asserts.

## Out of scope (explicitly)

- Cutover of `ic gate check` to read `gate.db` directly — follow-up bead.
- Theme registry infrastructure — separate cross-cutting effort.
- Outcomes table retention / VACUUM policy — defer.
- `clavain-cli gate-streak` observability command for myyw.10 — myyw.10 owns its read path.

## Sequencing + dependencies

T1 → T2 → T3 (outcome writer wired)
T1 → T4 (drain algorithm)
T4, T6 → T5 (subcommand glues them)
T5, T4 → T7 (export consumes tier_state)
T5 → T8 (hook calls subcommand)
T1-T8 → T9 (integration test)
T9 → T10 (docs after green)

## Commit plan

- **C1:** T1 + T2 (storage layer + writer + theme — no wiring yet)
- **C2:** T3 (wire into cmdEnforceGate)
- **C3:** T4 (drain algorithm + tests)
- **C4a:** T6 (migration) — reviewable in isolation
- **C4b:** T5 + T7 (subcommand + export)
- **C5:** T8 (hook registration)
- **C6:** T9 (integration test)
- **C7:** T10 (docs + changelog)

Each commit must pass `go test ./... && go build` before the next. PR is the full branch after C7.

---

**⚠ SUPERSEDED 2026-04-19** — Based on incorrect architecture (outcome-writer in `cmdEnforceGate`). Correct architecture consumes `ic gate signals` (same as v1). See revised brainstorm `docs/brainstorms/2026-04-18-gate-threshold-calibration-v2-brainstorm.md`. Regenerate plan in a fresh session.
