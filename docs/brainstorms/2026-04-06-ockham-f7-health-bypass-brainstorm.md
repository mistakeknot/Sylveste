# Ockham F7: Health JSON + Tier 3 BYPASS — Brainstorm

**Bead:** sylveste-fzt | **Date:** 2026-04-06
**Prior art:** F5 shipped Tier 1 INFORM (drift detection, pleasure signals). F1 shipped halt sentinel check. check.go already has reconstructHalt() and reconfirmation logic.

## Context

F7 completes the algedonic escalation path: Tier 1 (INFORM, shipped F5) → Tier 2 (CONSTRAIN, F6 future) → **Tier 3 (BYPASS, this feature)**. It also adds the `ockham health` command for Meadowsyn consumption and fully enforces INV-8 (policy immutability during halt).

The vision doc specifies: Tier 3 fires when `distinct_root_causes >= 2` fire simultaneously while at reduced oversight. Write-before-notify ordering. At least one notification path independent of Clavain. Resume resets all domains to supervised. Atomic reset transaction.

## Requirements (from vision doc + bead description)

### R1: Health JSON output (`ockham health`)
- Machine-readable factory health for Meadowsyn consumption
- Fields: halt status, active signals (INFORM/CONSTRAIN/BYPASS), pleasure signals, authority snapshot summary, intent summary, last check timestamp
- Must work when halted (read-only operation)
- `--watch` flag for polling (future, not F7)

### R2: Tier 3 BYPASS trigger
- Automated: fires when `distinct_root_causes >= 2` INFORM signals are fired simultaneously
- Root cause deduplication: count distinct themes with fired signals, not raw signal count
- Trigger condition: ≥2 themes have Status=fired at evaluation time
- Write-before-notify: create factory-paused.json FIRST, then record to interspect, then log
- Crash safety: if process dies between file write and interspect record, file is the authority; reconstructHalt() already handles the reverse case

### R3: Double-sentinel pattern
- Primary: `factory-paused.json` (filesystem, fast, checked by halt.IsHalted())
- Secondary: interspect halt record (`~/.clavain/interspect/halt-record.json`)
- Both written on BYPASS trigger; reconstructHalt() already recreates file from interspect record
- On resume: both must be cleared

### R4: `ockham resume` command
- Removes factory-paused.json
- Clears interspect halt record (set status=resolved)
- Checks active Tier 2 signals (CONSTRAIN) — currently no Tier 2 in codebase, so this is a no-op stub
- `--constrained` flag: resumes with frozen themes still frozen (Tier 2 check)
- Without `--constrained`: full resume, all themes unfrozen
- Domain reset: all ratchet_state entries reset to "supervised" atomically
- Atomic: if crash mid-reset, domains stay at pre-halt level; next resume retries full reset

### R5: Policy immutability during halt (INV-8)
- Governor.Evaluate() already returns error when halted — this is implemented
- Extend: `ockham intent set` must refuse writes when halted
- Extend: signal evaluation in check.go must skip when halted (already partially done — governor skips, but check.go evaluateSignals() runs independently)
- Read operations (health, signals, intent show) must still work

## Design Decisions

### D1: Where does BYPASS trigger live?
**In the evaluator** (anomaly.Evaluator.Evaluate). After evaluating all theme signals, count fired themes. If ≥2, trigger BYPASS. This is natural — the evaluator already iterates themes and knows their states.

### D2: Health output structure
```json
{
  "halted": false,
  "halt_reason": null,
  "signals": {
    "auth": {"status": "cleared", "drift_pct": 0.05, "advisory_offset": 0},
    "perf": {"status": "fired", "drift_pct": 0.23, "advisory_offset": -1}
  },
  "pleasure": {
    "pass_rate": {"trend": "stable", "value": 0.87},
    "cycle_time": {"trend": "improving", "value": 150000},
    "cost": {"trend": "stable", "value": 2.45}
  },
  "themes": ["auth", "perf", "open"],
  "last_check": 1743955200,
  "schema_version": 2
}
```

### D3: Resume atomicity
Use a single SQLite transaction for domain reset. ratchet_state UPDATE SET tier='supervised' WHERE tier='autonomous'. If the transaction succeeds, delete factory-paused.json. If it fails, file remains and next resume retries.

Order: clear interspect halt record → reset ratchet_state (tx) → delete factory-paused.json. File deletion is last because it's the signal that unblocks dispatch.

### D4: Halt-guard in intent CLI
`intent set` and `intent freeze` check halt.IsHalted() before writing. Returns explicit error: "factory is halted — run `ockham resume` first".

### D5: Halt-guard in check.go signal evaluation
check.go's evaluateSignals() should check halt BEFORE evaluation. Currently governor.Evaluate() checks halt, but check.go calls evaluateSignals() independently. Add explicit halt check at top of evaluateSignals().

BUT: reconstructHalt() must still run when halted (it's a read+reconstruct operation). And snapshotAuthority() should still capture snapshots (read-only capture of external state). Only signal evaluation and intent writes are blocked.

## Open Questions

### Q1: BYPASS threshold — hardcoded or configurable?
Vision doc says `distinct_root_causes >= 2`. This feels like it should be in anomaly.Config alongside other thresholds. **Recommendation: configurable in Config, default 2.**

### Q2: Interspect halt record write mechanism
check.go already reads halt-record.json. For writing, should we:
- (a) Write halt-record.json directly (simple, filesystem-only)
- (b) Shell out to an interspect CLI
- (c) Use interspect's evidence insertion API

**Recommendation: (a) direct file write.** Interspect is still file-based, and F7 shouldn't take a dependency on interspect's internal API. The file format is already a contract (check.go reads it).

### Q3: Notification path independent of Clavain
Vision doc requires ≥1 notification path independent of Clavain. Options:
- (a) Write to a well-known file that Meadowsyn polls
- (b) Send a system notification (notify-send or similar)
- (c) Defer — Meadowsyn isn't built yet; health JSON is the interface

**Recommendation: (c) defer.** `ockham health` IS the Clavain-independent path — any consumer (Meadowsyn, cron, shell script) can poll it. The filesystem sentinel is already independent.

### Q4: Resume confirmation prompt
Should `ockham resume` require `--force` or `--confirm` to prevent accidental resumes?
**Recommendation: yes, require `--confirm` flag.** Accidental resume is worse than accidental halt (halt is always safe, resume is not).

## Flux-Review Resolutions (4-track, 16 agents, 48 raw → 12 deduped findings)

### P0-1: fsync on sentinel writes (3/4 convergence)
**Resolution:** Add `f.Sync()` before `f.Close()` in both `reconstructHalt()` and BYPASS trigger. Use temp-file + fsync + rename pattern for atomic durable writes.

### P0-2: Resume without halt guard
**Resolution:** Add `if !halt.IsHalted() { return "factory is not halted" }` at top of resume.

### P0-3: evaluateSignals() halt guard (3/4 convergence)
**Resolution:** Add halt check at top of evaluateSignals(), BEFORE dry-run check. Brainstorm D5 already specifies this — confirmed as P0.

### P0-4: Never defer sentinel deletion
**Resolution:** Sentinel deletion is an explicit ordered step after `tx.Commit()` returns nil. Document: "never defer os.Remove on sentinel path."

### P1-1: BYPASS error propagation
**Resolution:** Typed `ErrBypassFailed` error. `runCheck()` propagates this type (exit non-zero), degrades other errors.

### P1-2: Reorder runCheck() — reconstructHalt() first (3/4 convergence)
**Resolution:** New order: reconstructHalt → snapshotAuthority → evaluateSignals (with D5 guard) → checkReconfirmation.

### P1-3: INV-8 allowlist pattern (3/4 convergence)
**Resolution:** Top-level halt check in `runCheck()`. Only reconstructHalt() and snapshotAuthority() run when halted. Everything else defaults to blocked. Use Cobra `PersistentPreRunE` allowlist for CLI commands.

### P1-4: Health reads persisted state only
**Resolution:** `ockham health` reads from signals.db signal_state table. Never calls evaluateSignals(). Add `at_advisory_floor` and `consecutive_clears` per signal.

### P1-5: Root-cause deduplication documented
**Resolution:** Document single-lane-per-bead invariant as design constraint. Add `BypassThreshold` to Config with `Validate() error` (min 2). Track causal independence for F8.

### P2-1: Structured halt_reason + advisory floor
**Resolution:** `halt_reason: {code, fired_themes[], fired_at}`. Per-signal: `at_advisory_floor`, `consecutive_clears`. `last_check` = `MAX(updated_at) FROM signal_state`.

### P2-2: Health read transaction
**Resolution:** Wrap health reads in `BeginTx(ctx, &sql.TxOptions{ReadOnly: true})` for snapshot consistency.

### P3-1: Resume displays context before --confirm
**Resolution:** Without --confirm: exit non-zero, show halt reason, timestamp, fired themes, domain reset preview.

## Updated Design Decisions

### D2 (updated): Health output structure
```json
{
  "halted": false,
  "halt_reason": null,
  "signals": {
    "auth": {"status": "cleared", "drift_pct": 0.05, "advisory_offset": 0, "at_advisory_floor": false, "consecutive_clears": 3},
    "perf": {"status": "fired", "drift_pct": 0.23, "advisory_offset": -1, "at_advisory_floor": false, "consecutive_clears": 0}
  },
  "pleasure": {
    "pass_rate": {"trend": "stable", "value": 0.87},
    "cycle_time": {"trend": "improving", "value": 150000},
    "cost": {"trend": "stable", "value": 2.45}
  },
  "themes": ["auth", "perf", "open"],
  "last_check": 1743955200,
  "schema_version": 2
}
```
When halted, `halt_reason` becomes: `{"code": "bypass_multi_root_cause", "fired_themes": ["auth", "perf"], "fired_at": 1743955200}`

### D3 (updated): Resume atomicity
Order: check IsHalted() → verify dual-sentinel consistency → clear interspect halt record → `BEGIN IMMEDIATE` ratchet_state reset → `PRAGMA wal_checkpoint(FULL)` → delete factory-paused.json. File deletion LAST, never deferred. Resume is idempotent: if interspect says resolved but file exists, continue from ratchet reset step.

### D5 (updated): Halt-guard as allowlist
In `runCheck()`: check halt first. If halted, run ONLY reconstructHalt() and snapshotAuthority(). Everything else (evaluateSignals, checkReconfirmation) is blocked. Reorder: reconstructHalt → snapshotAuthority → evaluateSignals → checkReconfirmation.

### D6 (new): Tier 2 stub interface
Define `ConstrainChecker` interface in resume path. Wire `nilConstrainChecker` stub. Makes the wiring point explicit for F6.

### D7 (new): BYPASS trigger write pattern
```
1. Write halt sentinel: temp file → fsync → rename (atomic + durable)
2. Write interspect record (soft failure: log + continue)
3. Return nil after sentinel succeeds — interspect failure is degradation, not rollback
4. Handle O_EXCL / IsExist: halt already active = success
```

## Scope Boundaries

**In scope:** health JSON, BYPASS trigger, double-sentinel writes, resume command, halt guards on writes, runCheck() reorder, INV-8 allowlist, fsync durability, structured halt_reason
**Out of scope:** Tier 2 CONSTRAIN (F6), Meadowsyn polling integration, --watch flag, authority write tokens, notification channels beyond filesystem, causal-independence deduplication (F8)
