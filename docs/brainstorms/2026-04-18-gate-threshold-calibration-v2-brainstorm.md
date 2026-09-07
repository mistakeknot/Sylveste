---
artifact_type: brainstorm
bead: sylveste-myyw.7
stage: discover
date: 2026-04-18
revised: 2026-04-19
revision_note: "v3 — course corrected after pre-flight audit of phase.go and gate_calibration.go discovered the outcome stream already exists upstream in interspect. Earlier drafts (v1 jsonl, v2 SQLite outcome-writer) assumed cmdEnforceGate needed instrumentation. It doesn't."
---

# Gate-threshold calibration schema v2 — brainstorm

## What We're Building

Clavain's existing v1 gate calibration (`cmdCalibrateGateTiers` in `os/Clavain/cmd/clavain-cli/gate_calibration.go`) already does the right data-flow shape: consume `ic gate signals --since-id=<cursor>`, apply a weighted-decay algorithm over TP/FP/TN/FN signals, promote soft→hard tiers, write a JSON file consumed by `ic gate check`. What it doesn't have: persistent per-theme state, SessionEnd automation, and the algorithmic refinements (window partitioning at tier change, consecutive-stable-windows precondition, small-n safety, per-theme FNR override).

**v2 keeps the data source** (`ic gate signals`) **and backward-compat JSON output** (unchanged shape so `ic gate check` doesn't care). **v2 changes the state store** to SQLite `.clavain/gate.db` for per-theme keying, migration audit trail, and drain-log observability. **v2 adds a SessionEnd hook** so calibration runs without `/reflect`.

## Why This Approach (v3)

Earlier drafts proposed instrumenting `cmdEnforceGate` to write gate-fire outcomes into a separate jsonl/DB. Pre-flight audit showed that v1 already consumes a richer signal stream (`ic gate signals` returns per-sub-check `{EventID, RunID, CheckType, FromPhase, ToPhase, Signal, CreatedAt, Category}` emitted by IC when gate checks run). Instrumenting cmdEnforceGate would create a parallel — and less granular — data path. The right move is to consume the existing signal stream and upgrade the downstream state store + algorithm.

This simplifies scope:
- **No edit to `phase.go`.** cmdEnforceGate untouched.
- **Same signal source as v1.** Schema of `ic gate signals` is fixed; gate.db just stores processed state.
- **Migration is JSON → SQLite tier_state only.** Outcomes are transient — we don't need a durable outcomes table because signals live in interspect already.
- **Backward-compat export is free.** The same JSON we write today for `ic gate check` is just regenerated from tier_state.

## Key Decisions

### Storage

- **File:** `.clavain/gate.db` (SQLite, `modernc.org/sqlite` — already in `go.mod`).
- **Tables:**
  ```sql
  CREATE TABLE tier_state (
    theme TEXT NOT NULL,
    check_type TEXT NOT NULL,
    phase_from TEXT NOT NULL,
    phase_to TEXT NOT NULL,
    tier TEXT NOT NULL DEFAULT 'soft',
    fpr REAL, fnr REAL,
    weighted_n REAL NOT NULL DEFAULT 0,
    consecutive_windows_above_threshold INTEGER NOT NULL DEFAULT 0,
    locked INTEGER NOT NULL DEFAULT 0,
    change_count_90d INTEGER NOT NULL DEFAULT 0,
    last_changed_at INTEGER,
    fnr_threshold REAL,              -- nullable per-row override
    origin_key TEXT,                 -- v1 lineage
    theme_source TEXT NOT NULL,      -- 'labeled' | 'inferred' | 'default' | 'migrated'
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (theme, check_type, phase_from, phase_to)
  );

  CREATE TABLE drain_log (
    drain_started INTEGER NOT NULL,
    drain_committed INTEGER,
    signals_processed INTEGER,
    since_id_before INTEGER,
    since_id_after INTEGER,
    state_changes INTEGER,
    invoker TEXT NOT NULL            -- 'auto' | 'manual'
  );

  -- Optional observability table — mirror of recent signals for SQL inspection.
  -- Populated on drain from ic gate signals output. Not authoritative.
  CREATE TABLE signals_cache (
    event_id INTEGER PRIMARY KEY,
    run_id TEXT, check_type TEXT,
    phase_from TEXT, phase_to TEXT,
    signal TEXT, category TEXT, created_at INTEGER
  );
  ```

### Algorithm (v2 on top of v1 formulas)

Keep v1's FPR/FNR formulas verbatim:
- `fpr = weightedFP / (weightedTP + weightedFP)`
- `fnr = weightedFN / (weightedTN + weightedFN)`
- Weight: exponential decay with 30-day half-life: `weight = exp(-ln2 * age_days / 30)`
- `weighted_n = weightedTP + weightedFP + weightedTN + weightedFN`

v2 algorithmic additions:
- **Per-theme keying:** signals grouped by `(theme, check_type, phase_from, phase_to)` instead of v1's `(check_type, phase_from, phase_to)`. Theme derived from `check_type` prefix (inferred) or from an explicit label on the bead (`bd state <bead> theme` → `labeled`) or `default`.
- **Window partitioning at tier change:** signals with `created_at < tier_state.last_changed_at` are **excluded** from the weighted aggregation. Mixing pre- and post-change signals blurs the rate estimates on the tier that's currently in effect.
- **Consecutive-stable precondition (for soft→hard promotion):** in addition to existing `fnr > 0.30 && weighted_n >= 10 && cooldown && velocity`, require `consecutive_windows_above_threshold >= 3`. Counter increments on each non-empty drain where threshold is exceeded; resets to zero when threshold is not exceeded; **empty drains are no-ops on the counter** (stability means consecutive *data-bearing* drains).
- **Small-n safety:** `weighted_n < 10 → no promotion` (already in v1). **New:** `fnr == 0 && weighted_n < 20 → no promotion` (prevents "perfect small sample" lock-in).
- **Per-theme FNR override:** nullable `tier_state.fnr_threshold` column. When set, overrides default 0.30. Unset for v1-migrated rows.
- **Rational subgrouping note:** the brainstorm review suggested `session_id` for subgrouping to handle autocorrelation of in-session gate fires. The signal stream doesn't carry session_id; it carries `run_id` (per-ic-run). Use `run_id` as the autocorrelation subgrouping key — same spirit, correct primitive. Weighted count already dampens single-run dominance via time decay, but if empirical drift shows run-id clustering issues, add per-run weight cap later.

### Drain flow

`calibrate-gate-tiers [--auto]`:
1. Open `.clavain/gate.db` (initialize schema idempotently).
2. If `tier_state` empty and `.clavain/gate-tier-calibration.json` exists → **v1→v2 migration** first:
   - Read v1 JSON, insert each entry as `theme='default', theme_source='migrated', origin_key='<v1 composite key>'`.
   - Rename v1 JSON to `.clavain/gate-tier-calibration.v1.json.bak`.
3. Read `since_id_before = SELECT MAX(since_id_after) FROM drain_log WHERE drain_committed IS NOT NULL`.
4. Subprocess: `runICJSON(&sr, "gate", "signals", "--since-id=<since_id_before>")`.
5. **`BEGIN IMMEDIATE`** (SQLite write-lock at transaction start; retry with jittered backoff on SQLITE_BUSY, max 3 attempts).
6. `INSERT INTO drain_log (drain_started, invoker, since_id_before)` capturing rowid.
7. If `len(sr.Signals) == 0`: `UPDATE drain_log SET drain_committed=?, signals_processed=0, since_id_after=since_id_before, state_changes=0`; COMMIT; exit 2.
8. Partition signals by `(theme, check_type, phase_from, phase_to)` — derive theme per signal.
9. For each group: filter to `created_at > tier_state.last_changed_at`; compute weighted FPR/FNR/N; UPSERT tier_state with promotion rule (including consecutive-stable counter, small-n safety, per-theme override).
10. `INSERT INTO signals_cache` (best-effort mirror, truncate beyond 30 days on a periodic basis).
11. `UPDATE drain_log SET drain_committed=?, signals_processed=<n>, since_id_after=<cursor>, state_changes=<count>`.
12. **COMMIT.**
13. Regenerate backward-compat JSON from tier_state (T7 in plan): worst-case tier wins tiebreak.

Exit codes: `0` if `state_changes > 0` OR `signals_processed > 0`; `2` if `signals_processed == 0`; `1` on error.

### SessionEnd hook

- `os/Clavain/hooks/gate-calibration-session-end.sh`: `timeout 10 clavain-cli calibrate-gate-tiers --auto; exit 0`.
- Registered in Clavain's hooks.json under `SessionEnd` (record format per Demarch memory).
- `/reflect` continues to call `calibrate-gate-tiers` without `--auto` for manual invocations. The `invoker` column distinguishes for myyw.10 streak tracking.

### v1 → v2 migration

Idempotent. Runs once when `tier_state` is empty and v1 JSON exists. Preserves `origin_key` for audit. Archives v1 as `.bak`. Future drains see non-empty `tier_state` and skip the migration block.

### Backward compatibility

- `cmdEnforceGate` unchanged.
- `ic gate check --calibration-file=<path>` still reads the JSON file — we regenerate it after every drain from v2 state so no consumer breaks.
- Cutover of `ic gate check` to read gate.db directly is an explicit non-goal (follow-up bead).

## Open Questions

- **Does `ic gate signals` always return every signal since `--since-id`?** Need to verify cursor semantics with a small test — if it caps at N rows, we need pagination. Plan should check.
- **Signal schema stability.** If `ic gate signals` ever adds new signal types beyond tp/fp/tn/fn, our grouping logic would silently drop them. Add a log on unknown signal type so we notice.
- **`signals_cache` retention.** Unbounded growth. Either periodic VACUUM/DELETE or skip populating it entirely and rely on the interspect DB for ad-hoc queries. Default: populate but prune on each drain to last 30 days.
- **Category column usage.** `gateSignal.Category` is populated by IC. Currently unused by v1 — should v2 use it for theme derivation if `check_type` prefix doesn't match? Maybe. Defer until we see real categories.

## References

- v1 source: `os/Clavain/cmd/clavain-cli/gate_calibration.go:15-288`
- v1 consumer: `os/Clavain/cmd/clavain-cli/phase.go:cmdEnforceGate` (unchanged in v2)
- Signal source: `ic gate signals --since-id=N` returns `{EventID, RunID, CheckType, FromPhase, ToPhase, Signal, CreatedAt, Category}`
- Review synthesis (still applies): `docs/research/flux-review/gate-threshold-calibration-v2/2026-04-18-synthesis.md`
- Superseded PRD (needs regeneration): `docs/prds/2026-04-18-gate-threshold-calibration-v2.md`
- Superseded plan (needs regeneration): `docs/plans/2026-04-18-gate-threshold-calibration-v2.md`
- Sibling bead: `sylveste-8n9n` (Interspect calibration v2) — owns `.clavain/interspect/interspect.db`
- Downstream consumer: `sylveste-myyw.10` (10-sprint streak tracking) — reads `drain_log.invoker`
