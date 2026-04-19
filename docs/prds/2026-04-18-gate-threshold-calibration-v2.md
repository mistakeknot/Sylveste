---
artifact_type: prd
bead: sylveste-myyw.7
stage: design
date: 2026-04-18
---

# PRD: Gate-threshold calibration schema v2

## Problem

Clavain's quality-gate thresholds (`.clavain/gate-tier-calibration.json`, schema v1) are static — there's no mechanism to record gate-fire outcomes, recompute thresholds from recent evidence, or trigger recalibration automatically. The parent epic `sylveste-myyw` (Autonomy A:L3) requires all three calibration loops to run on SessionEnd without human invocation; gate-threshold calibration is one of those three loops, and today it needs manual `/reflect` to make any change.

## Solution

Replace v1's static JSON with a SQLite-backed v2 store at `.clavain/gate.db` that (a) records each gate fire as a durable row, (b) recomputes per-theme tier state via a rolling-window algorithm on SessionEnd, (c) migrates existing v1 data on first run, and (d) runs entirely without human invocation once wired. The store is distinct from `interspect.db` (owned by sibling bead `sylveste-8n9n`) to preserve code-level boundaries.

## Features

### F1: gate.db storage layer + writer
**What:** Create `.clavain/gate.db` schema (outcomes, tier_state, drain_log tables per brainstorm). Add a writer library in `os/Clavain/internal/gatecal/` that opens/initializes the DB and exposes `RecordOutcome(ctx, row) error`. Wire the writer into `cmdEnforceGate` (`phase.go`) after `ic gate check` returns. Insert failure is non-fatal (log + continue).

**Acceptance criteria:**
- [ ] `.clavain/gate.db` auto-initializes on first `RecordOutcome` call (tables + indexes per schema in brainstorm).
- [ ] `cmdEnforceGate` records one row per gate invocation with `(ts, session_id, check_type, theme, phase_from, phase_to, verdict, tier_at_fire, theme_source, evidence_ref)`.
- [ ] `theme_source` derived from: explicit `bd state` theme label → `labeled`; else `check_type` prefix → `inferred`; else `default`. (Registry infrastructure doesn't exist yet — `labeled` names the actual mechanism.)
- [ ] Insert failure logs to stderr and returns; does not fail the gate.
- [ ] `session_id` sourced from `CLAUDE_SESSION_ID`, falls back to `unknown`.
- [ ] Unit tests cover insert, nullable `evidence_ref`, and fallback paths.

### F2: calibrate-gate-tiers subcommand + algorithm
**What:** New `clavain-cli calibrate-gate-tiers [--auto]` subcommand in `os/Clavain/cmd/clavain-cli/`. Implements the rolling-window algorithm with small-n safety, rational subgrouping by `session_id`, window partitioning at `last_changed_at`, and consecutive-stable-windows precondition for soft→hard promotion. Also implements one-shot v1→v2 migration on first run (archive v1 JSON as `.bak`, seed `tier_state` with `theme='default'`, `theme_source='migrated'`).

**Acceptance criteria:**
- [ ] `calibrate-gate-tiers --auto`: exit 0 if tier state advanced, exit 2 if no new outcomes since last `drain_log.cursor_ts`, exit 1 on error.
- [ ] Drain executes as one SQLite transaction: `BEGIN → read outcomes > cursor → compute per-theme stats → UPSERT tier_state → INSERT drain_log → COMMIT`.
- [ ] `effective_n` = COUNT(DISTINCT session_id), not row count. Promotion rule uses `effective_n`, not `weighted_n`.
- [ ] `effective_n < 10` → no promotion. `fnr == 0 AND effective_n < 20` → no promotion.
- [ ] Window partitioned at `tier_state.last_changed_at`: FPR/FNR computed only on outcomes since most recent tier change.
- [ ] `consecutive_windows_above_threshold ≥ 3` required for soft→hard promotion (in addition to existing FNR, cooldown, 90d-cap rules from `gate_calibration.go`).
- [ ] Empty drain (no new outcomes since cursor) is a **no-op on `consecutive_windows_above_threshold`** — counter neither increments nor resets. Stability means consecutive *data-bearing* drains, not consecutive sessions.
- [ ] Concurrent `calibrate-gate-tiers` invocations tolerate each other: transaction starts with `BEGIN IMMEDIATE` (SQLite write-lock); on `SQLITE_BUSY`, retry with jittered backoff up to 3 attempts; on persistent conflict, exit 1 with a distinguishable error message. Second invocation that sees cursor already advanced past its outcomes exits 2.
- [ ] Per-theme `fnr_threshold` override respected when set; default `0.30` otherwise.
- [ ] First-run migration: reads existing `.clavain/gate-tier-calibration.json`, inserts rows with `theme='default', theme_source='migrated', origin_key=<v1 key>`, archives v1 as `.v1.json.bak`, idempotent on re-run.
- [ ] `--auto` sets `drain_log.invoker='auto'`; bare invocation sets `'manual'`.
- [ ] Unit tests cover: small-n freeze, zero-FNR freeze, window partition at tier change, consecutive-stable precondition, migration idempotency, cursor advancement.

### F3: SessionEnd hook + backward-compat JSON export
**What:** New `os/Clavain/hooks/gate-calibration-session-end.sh` invoking `clavain-cli calibrate-gate-tiers --auto` with a short timeout, registered under `SessionEnd` in Clavain's `hooks.json`. Additionally, after each successful drain the subcommand exports a v1-shaped JSON file (`.clavain/gate-tier-calibration.json`) from `gate.db:tier_state` so existing `ic gate check` consumers continue reading their expected file without a cutover.

**Acceptance criteria:**
- [ ] `hooks.json` includes new SessionEnd entry invoking the hook script.
- [ ] Hook script respects a 10s timeout; on timeout, leaves `drain_log.drain_started` without `drain_committed` and exits cleanly (next SessionEnd resumes).
- [ ] After a successful drain, `.clavain/gate-tier-calibration.json` is regenerated from v2 `tier_state` in v1 schema shape (one entry per `(check_type|phase_from→phase_to)`). **Tiebreak for multiple themes on the same key: worst-case tier wins** (`hard` beats `soft`). Safety-leaning default; documented in-code.
- [ ] `ic gate check` continues to read the JSON without modification. **Integration test:** regenerate JSON from a seeded v2 `tier_state`, invoke `ic gate check` against it, verify zero parse errors and that gate decisions match pre-migration behavior for identical inputs.
- [ ] Manual `calibrate-gate-tiers` (no `--auto`) works identically for `/reflect` invocations.
- [ ] Integration test: seed 30 outcomes across 3 sessions, run hook, verify tier_state updated AND JSON regenerated.

## Non-goals

- Replacing the JSON consumer contract in `ic gate check` (backward-compat export keeps it working; cutover is a follow-up bead).
- Theme registry infrastructure (myyw.7 infers themes from `check_type` prefix; registry is a cross-cutting concern).
- Evidence-ref population from `ic gate check` (column supported; enrichment deferred).
- Retention/compaction of outcomes table (grows unbounded; `VACUUM` policy deferred).
- Unifying with `interspect.db` (explicit non-goal — bead boundary with sylveste-8n9n).

## Dependencies

- `modernc.org/sqlite` — already a Clavain dependency (no new module).
- Existing `os/Clavain/cmd/clavain-cli/gate_calibration.go:62-242` (`cmdCalibrateGateTiers`) — refactored to become the v2 implementation; name preserved where possible.
- Existing `os/Clavain/cmd/clavain-cli/phase.go:231-320` (`cmdEnforceGate`) — adds one RecordOutcome call post-`runIC`.
- `CLAUDE_SESSION_ID` env var — already populated by Claude Code.

## Open Questions

- **Tiebreak when v1→v2 migration collides with fresh v2 rows.** Unlikely (migration runs when v2 empty), but specify: migration no-ops if `tier_state` has any row with `theme='default'` AND matching `(check_type, phase_from, phase_to)`.
- **Theme for gate fires with no matching prefix rule.** Default `theme='default', theme_source='default'`. Registry can reclassify later.
- **Interaction with in-session `/reflect`.** `/reflect` runs the same subcommand without `--auto`. If SessionEnd fires after `/reflect` same session, cursor is already advanced → exit 2 (no-op). Verify integration test covers this.

## Success metrics

The feature succeeds when, for 10 consecutive sprints:
- Every SessionEnd produces a `drain_log` row with `drain_committed != NULL` (or exits 2 for no-op).
- Zero invocations of `/reflect` are required for gate-threshold state to advance.
- `gate-tier-calibration.json` (backward-compat export) remains consumable by `ic gate check` without change.

---

**⚠ SUPERSEDED 2026-04-19** — Based on incorrect architecture (assumed `cmdEnforceGate` needed outcome instrumentation; pre-flight audit showed outcomes already exist as signals in interspect, consumed via `ic gate signals`). See revised brainstorm `docs/brainstorms/2026-04-18-gate-threshold-calibration-v2-brainstorm.md` for the corrected design. Regenerate PRD from the revised brainstorm in a fresh session.
