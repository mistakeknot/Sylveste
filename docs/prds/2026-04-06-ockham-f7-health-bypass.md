---
artifact_type: prd
bead: sylveste-fzt
stage: design
---
# PRD: Ockham F7 — Health JSON + Tier 3 BYPASS

## Problem

Ockham has no health output for external consumers (Meadowsyn) and no automated emergency halt (Tier 3 BYPASS). The factory can drift into compound failure without triggering escalation to the principal. INV-8 (policy immutability during halt) has enforcement gaps.

## Solution

Ship `ockham health` for machine-readable factory state, automated Tier 3 BYPASS trigger with double-sentinel durability, `ockham resume` for controlled restart, and complete INV-8 enforcement via allowlist pattern.

## Features

### F1: Health JSON command (`ockham health`)
**What:** Machine-readable factory health output for Meadowsyn and operator consumption.
**Acceptance criteria:**
- [ ] `ockham health` outputs JSON with: halted (bool), halt_reason (structured), signals (per-theme with status, drift_pct, advisory_offset, at_advisory_floor, consecutive_clears), pleasure (per-signal with trend and value), themes (string array), last_check (epoch from signal_state), schema_version
- [ ] When halted, halt_reason is `{code, fired_themes[], fired_at}` not a string
- [ ] Health reads ALL data from signals.db persisted state — never calls evaluateSignals()
- [ ] All reads wrapped in `BeginTx(ctx, &sql.TxOptions{ReadOnly: true})` for snapshot consistency
- [ ] Exit 0 when JSON produced (even when halted). Exit 1 on operational failure
- [ ] `--json` flag for structured output (default is also JSON for F7; future: table format default)
- [ ] `last_check` is `MAX(updated_at) FROM signal_state`, not render time

### F2: Tier 3 BYPASS trigger
**What:** Automated emergency halt when >=2 distinct INFORM signals fire simultaneously.
**Acceptance criteria:**
- [ ] `BypassThreshold` field added to `anomaly.Config` (default 2)
- [ ] `Config.Validate()` enforces `BypassThreshold >= 2` — fail at evaluator construction
- [ ] After evaluating all themes in `Evaluator.Evaluate()`, count themes with Status=fired. If >= threshold, trigger BYPASS
- [ ] Sentinel write uses temp-file + `f.Sync()` + `os.Rename()` for atomic durable write
- [ ] Handle `os.IsExist` on O_EXCL: halt already active = success, not error
- [ ] Interspect halt record written AFTER sentinel (soft failure: log + continue, never roll back sentinel)
- [ ] Halt record contains: `{reason, code, triggered_themes[], signal_values{}, timestamp, schema_version}`
- [ ] Typed `ErrBypassFailed` error when sentinel write fails — propagated through evaluateSignals() and runCheck() as non-zero exit
- [ ] Sentinel file permissions: `0400` (owner read-only) to prevent accidental deletion
- [ ] Single-lane-per-bead invariant documented as design constraint in closedBeadsFromBD()

### F3: `ockham resume` command
**What:** Controlled factory restart after BYPASS halt with atomic domain reset.
**Acceptance criteria:**
- [ ] Halt precondition: `if !halt.IsHalted() { return error }` — prevents accidental domain destruction
- [ ] `--confirm` required: without it, exit non-zero with halt context preview (reason, timestamp, fired themes, domain reset count)
- [ ] Dual-sentinel consistency check: if file exists but interspect record missing/resolved, log warning and proceed (partial-write recovery)
- [ ] Resume is idempotent: if interspect says resolved but file exists, continue from ratchet reset step
- [ ] Domain reset uses `BEGIN IMMEDIATE` for exclusive write lock
- [ ] Reset SQL: `UPDATE ratchet_state SET tier='supervised' WHERE tier='autonomous'` (not all tiers)
- [ ] After `tx.Commit()`: `PRAGMA wal_checkpoint(FULL)` before sentinel deletion
- [ ] Sentinel deletion is NEVER deferred — explicit ordered step after commit + checkpoint
- [ ] Clears interspect halt record (set status=resolved)
- [ ] On success: prints structured summary (sentinels cleared, domains reset count, next action)
- [ ] `--json` flag for machine-readable output
- [ ] `ConstrainChecker` interface defined for Tier 2 stub — `nilConstrainChecker` wired, returns empty
- [ ] Pre-halt ratchet_state snapshot saved to interspect halt record before reset (forensics)

### F4: INV-8 enforcement + runCheck reorder
**What:** Complete policy immutability during halt via allowlist pattern and corrected step ordering.
**Acceptance criteria:**
- [ ] `runCheck()` reordered: reconstructHalt → snapshotAuthority → evaluateSignals → checkReconfirmation
- [ ] Top-level halt check in `runCheck()`: if halted, run ONLY reconstructHalt() and snapshotAuthority(), then return
- [ ] `halt.Sentinel.RequireRunning() error` helper for standardized halt-guard errors
- [ ] Halt-guard error includes: halt reason, timestamp, fired themes (read from factory-paused.json)
- [ ] Cobra `PersistentPreRunE` allowlist on root command: only `health`, `signals`, `intent show`, `resume` permitted when halted. All other commands blocked with informative error
- [ ] `reconstructHalt()` fsync fix: add `f.Sync()` before `f.Close()` on existing write path
- [ ] `reconstructHalt()` disagreement logging: if interspect=resolved but file=present, log advisory
- [ ] checkReconfirmation() no longer writes signal_state during halt (blocked by allowlist)

## Non-goals
- Tier 2 CONSTRAIN (F6)
- `--watch` flag for health polling
- Meadowsyn integration
- Authority write tokens
- Causal-independence deduplication (F8)
- Notification channels beyond filesystem

## Dependencies
- F5 (Tier 1 INFORM) — shipped
- signals.db v2 schema — shipped
- anomaly.Evaluator — shipped

## Open Questions
- **Constrained resume persistence:** When F6 adds Tier 2, `--constrained` resume needs a `constrained-mode.json` to prevent re-triggering BYPASS on expected-anomalous themes. Stub the interface now, implement with F6.
- **Theme grouping for root-cause dedup:** Fine-grained lane schemas (auth, auth-delegation, auth-infra) can trigger false BYPASS. Document now, implement `theme_groups` config in F8.
