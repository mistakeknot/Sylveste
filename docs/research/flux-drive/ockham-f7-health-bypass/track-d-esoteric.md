---
track: esoteric
agents: [fd-minoan-palatial-archive-sealing, fd-igbo-ofo-oath-binding-emergency-halt, fd-tlingit-potlatch-debt-quenching-emergency-reset]
date: 2026-04-06
---
# Track D: Esoteric Domain Review

## Findings

---

### [P0] factory-paused.json write lacks fsync — write-before-notify is code-order only, not syscall-order

**Agent:** fd-minoan-palatial-archive-sealing
**Source domain:** Pylos palatial archive, c. 1250 BCE — seal-before-dispatch principle
**Isomorphism:** Pylos scribes impressed clay sealings on active tablet series BEFORE dispatching runners to halt outlying operations. A runner who departs before the clay is hardened carries news of a halt while the archive remains in a writable state. The kernel may not have flushed the file to disk by the time the process emits its interspect halt record or logs the BYPASS event.

**Description:** The brainstorm mandates write-before-notify ordering (R2, R3): factory-paused.json must exist on disk before the interspect halt record is written. The existing `reconstructHalt()` in `check.go` (lines 289–343) uses `os.OpenFile` + `f.Write` for the filesystem sentinel — no `f.Sync()` call. The forthcoming BYPASS trigger in `anomaly.Evaluator.Evaluate()` will follow the same pattern. On Linux with a writeback-enabled filesystem (ext4, btrfs default), `write()` returns success when the page cache is updated; the inode may not reach disk for seconds. If the process crashes after the page-cache write but before the kernel flushes, factory-paused.json will not exist on restart, but any interspect record or log line written after the `os.WriteFile` call will persist — external consumers (`halt.IsHalted()` in `governor.go` line 45, `lib-dispatch.sh`) will see no halt while interspect records a BYPASS. This is exactly the runner-before-seal failure: notification escaped before state was durable.

The specific crash window: BYPASS evaluator writes factory-paused.json to page cache → kernel schedules writeback → process crashes before writeback → interspect halt record was written after the `WriteFile` call and IS durable (it goes through the same mechanism, so the ordering guarantee is illusory unless both are synced). At minimum: if either write uses a different sync posture than the other, ordering guarantees collapse.

**Recommendation:** In the BYPASS trigger implementation (and in `reconstructHalt()` for consistency), replace the `os.WriteFile` / `f.Write` + `f.Close()` sequence with an explicit `f.Sync()` before `f.Close()`. One additional line:

```go
if _, err = f.Write(sentinel); err != nil { return err }
if err = f.Sync(); err != nil { return err }  // fsync before notifying
return f.Close()
```

Only after `f.Sync()` returns should the BYPASS trigger proceed to write the interspect halt record or emit any log line. This makes write-before-notify a syscall-level guarantee, not a code-ordering convention.

---

### [P0] resume does not verify dual-sentinel consistency before proceeding — partial-write halts are accepted silently

**Agent:** fd-minoan-palatial-archive-sealing
**Source domain:** Pylos unsealing ceremony — door-seal and tablet-nodule cross-verification
**Isomorphism:** The Pylos wanax required both the archive room door seal AND each tablet series' clay nodule to be intact and mutually consistent before any scribe could resume writing. A door sealed but tablets unsealed indicated tampering or partial failure during the original closure. A single broken seal on one series was treated as evidence of corruption, not a minor discrepancy to overlook.

**Description:** The brainstorm specifies `ockham resume` must clear both sentinels (R4). The code that will implement `resume` is not yet written, but the design has a consistency gap. `reconstructHalt()` in `check.go` (lines 289–343) handles the reverse-inconsistency case: interspect halt-record.json active, factory-paused.json missing → reconstruct the file. But the forward-inconsistency case is unaddressed in the design: factory-paused.json exists, interspect halt-record.json is missing or has status != "active". This state occurs if the BYPASS trigger writes factory-paused.json (step 1) and then crashes before writing the interspect record (step 2). `ockham resume` as designed will delete factory-paused.json and clear the interspect record — but if the interspect record is already missing, `resume` sees a one-sentinel halt and clears it without knowing whether the halt was legitimately triggered or is a corrupted partial-write. The human operator loses the ability to determine whether a real BYPASS occurred.

Furthermore, if `resume` only checks `halt.IsHalted()` (filesystem sentinel) and does not verify that halt-record.json.status == "active" before proceeding, a stale or corrupted factory-paused.json left by an operator or a failed test will be cleared without audit trail.

**Recommendation:** At the start of `ockham resume`, implement an explicit consistency check:

1. Read halt-record.json. If factory-paused.json exists but halt-record.json is missing or status != "active", print a warning: "factory-paused.json exists but no active interspect halt record found — possible partial-write during BYPASS trigger. Proceeding with resume but recording inconsistency." Write an anomaly note to interspect before clearing. Do not block the resume, but do not silently swallow the inconsistency.
2. If halt-record.json exists with status == "active" but factory-paused.json is missing, the design already handles this via `reconstructHalt()` — make resume call `reconstructHalt()` first so it can confirm both sentinels before clearing them.

---

### [P1] `ockham health` construction may depend on `evaluateSignals()` — blocked during halt, violating read-only guarantee

**Agent:** fd-minoan-palatial-archive-sealing
**Source domain:** Pylos sealed-period access — qa-si-re-u reading tribute schedules during archive closure
**Isomorphism:** During the Pylos emergency closure, local administrators (qa-si-re-u) could consult tribute schedules to continue tax collection but could not modify allocations. The "consultation mechanism" must remain functional during the sealed period — an archive that is also unreadable during crisis is worse than useless; it severs the principal's ability to understand the factory state.

**Description:** The brainstorm (R1) requires `ockham health` to work when halted: "must work when halted (read-only operation)". D5 specifies that `evaluateSignals()` in `check.go` should add a halt check at the top of the function, blocking signal evaluation when halted. If `ockham health` constructs its JSON by calling `evaluateSignals()` or any path that passes through the anomaly evaluator (which already checks halt in `governor.go` line 45), the health command will return incomplete signal data or an error when the factory is halted — precisely when accurate health data is most critical.

The specific risk: the brainstorm's health JSON (D2) includes per-theme signal status (`"signals": {"auth": {"status": "cleared", ...}, "perf": {"status": "fired", ...}}`). If health reads this from a fresh `evaluateSignals()` run, it will be blocked by the halt guard. If health reads from signals.db's last-known state, it will work correctly. The design does not yet specify which path `ockham health` takes, but the implementation must explicitly read signal state from signals.db (via `r.db.GetSignalState("inform:<theme>")` or equivalent) rather than triggering a new evaluation.

**Recommendation:** Specify in the implementation plan that `ockham health` reads all data from persisted state (signals.db signal_state table, the halt sentinel file, ratchet_state) with no live evaluation. Add a comment in the health command implementation: `// health is read-only: reads last persisted state, never calls evaluateSignals`.

---

### [P1] INV-8 enforcement uses an enumerated blocklist — new write paths default to permitted

**Agent:** fd-igbo-ofo-oath-binding-emergency-halt
**Source domain:** Igbo ikpo ala — categorical prohibition on all authority changes, not an enumerated list of specific actions
**Isomorphism:** The ikpo ala declaration freezes ALL authority transactions community-wide without the declaring elders needing to enumerate land transfers, title bestowals, succession recognitions, and debt contracts separately. The prohibition applies to the category "authority changes." An enumerated blocklist requires future implementers to remember to add each new write path — a structural safety property degraded to a documentation convention.

**Description:** The brainstorm (R5) identifies three INV-8 enforcement points: `Governor.Evaluate()` (governor.go line 45), `ockham intent set`, and `evaluateSignals()` in check.go. This is an enumerated blocklist. The brainstorm itself notes that signals.db signal_state can be modified, ratchet_state can be changed, and advisory offsets can be recalculated. None of these are explicitly mentioned as halt-guarded. Specific gaps visible in the current code:

- `check.go` `evaluateSignals()` (lines 83–123): no halt check currently. The governor blocks at line 45, but `evaluateSignals()` calls `eval.Evaluate()` directly without going through the governor. If a future feature adds a direct call to `r.db.SetSignalState()` outside `evaluateSignals()`, it bypasses the halt guard entirely.
- `check.go` `checkReconfirmation()` (lines 346–385) calls `r.flagReconfirm()` which calls `r.db.SetSignalState(key, "pending", ...)` (line 403). This write path is not halt-guarded. During a halt, re-confirmation signals should not be generated — the factory is frozen and the re-confirmation timer should pause, not fire.
- `snapshotAuthority()` (lines 235–276) writes to signals.db via `r.db.SaveAuthoritySnapshot()`. The brainstorm says snapshotAuthority must still work during halt (D5), but authority snapshots are read-only captures of external interspect state — they do not modify policy. However, if `SaveAuthoritySnapshot` also updates any signal_state rows, that is an unguarded policy write.

**Recommendation:** Replace the enumerated blocklist with an allowlist pattern. Add a top-level halt check at the start of `runCheck()` (check.go line 38) that gates the entire check run. Explicitly allowlist the three operations that must continue during halt: `reconstructHalt()`, `snapshotAuthority()` (read-only), and the forthcoming `ockham health`. Everything else defaults to blocked. The implementation in runCheck should look like:

```go
halted := halt.New(runner.haltPath).IsHalted()
if halted {
    // Only these operations are permitted during halt:
    _ = runner.reconstructHalt()
    return nil  // skip evaluateSignals, checkReconfirmation, everything else
}
```

This makes the allowlist structural — a new check step added to `runCheck()` will default to being skipped during halt unless the implementer explicitly adds it before the halt guard.

---

### [P1] Halt enforcement is behavioral, not structural — any caller that skips `halt.IsHalted()` can dispatch during BYPASS

**Agent:** fd-igbo-ofo-oath-binding-emergency-halt
**Source domain:** Igbo ikpo ala — sacred prohibition with divine enforcement, structurally impossible to bypass
**Isomorphism:** The ikpo ala carries force because Ala (earth deity) witnesses the declaration — violation is believed to bring supernatural punishment. The prohibition is self-enforcing at the deepest motivational level, not dependent on each community member choosing to honor it. In code terms: structural enforcement (the halt check is on the only path to dispatch) vs behavioral enforcement (each subsystem chooses to call `halt.IsHalted()`).

**Description:** `halt.IsHalted()` is currently an `os.Stat()` call (halt.go line 28–31) that any caller must explicitly invoke. `governor.go` line 45 calls it. But `check.go` `evaluateSignals()` (line 83) calls `eval.Evaluate()` directly through `anomaly.Evaluator.Evaluate()` without going through the governor — the governor's halt check is bypassed. The brainstorm acknowledges this at D5: "check.go calls evaluateSignals() independently." The fix is noted (add explicit halt check at top of evaluateSignals), but the root issue remains: there is no single chokepoint that ALL dispatch-affecting writes must pass through.

The specific risk is `lib-dispatch.sh` integration. The brainstorm states Clavain's self-dispatch calls the governor, which checks halt. But if `lib-dispatch.sh` ever calls `bd` commands directly based on signals.db state (rather than going through `ockham check` + governor), or if a future sprint executor reads ratchet_state without calling governor.Evaluate(), the halt is not enforced for that dispatch path. The halt is structural only for paths that flow through `governor.Evaluate()`.

**Recommendation:** For the F7 scope, the minimum fix is adding the halt check at the top of `evaluateSignals()` (as D5 specifies). Document explicitly in the function comment that `evaluateSignals` is a write-path and must check halt before any db write. For the architectural concern, add a `// INVARIANT: all dispatch-affecting writes must check halt.IsHalted() before executing` comment at the top of check.go, and track the structural dispatch chokepoint as a follow-on item for F8 or the Alwe/Zaka integration work.

---

### [P1] Root-cause deduplication counts themes, not causes — shared infrastructure failure triggers BYPASS

**Agent:** fd-igbo-ofo-oath-binding-emergency-halt
**Source domain:** Igbo ikpo ala — multi-lineage threshold requires independent disputes across lineages
**Isomorphism:** Ikpo ala is declared only when disputes erupt across MULTIPLE lineages simultaneously. A single lineage's crisis resolved by that lineage's ofo-holder does not justify community-wide freeze. If a single infrastructure failure affects multiple lineages simultaneously, it is still a single-lineage governance problem that happens to have cross-lineage symptoms.

**Description:** The brainstorm (R2) specifies: "Root cause deduplication: count distinct themes with fired signals, not raw signal count. Trigger condition: ≥2 themes have Status=fired at evaluation time." The deduplication is theme-level, not cause-level. If the interspect database is slow (a single infrastructure event), both `auth` theme signals (authority checks degrade) and `perf` theme signals (cycle times inflate because interspect latency adds to each bead's completion time) may fire simultaneously. The evaluator in `anomaly.Evaluator.Evaluate()` — called from `check.go` line 108 — will see two fired themes and trigger BYPASS. This is a single root cause (interspect DB) triggering a factory halt designed for compound failure.

The brainstorm acknowledges this at Q1 (threshold configurability) but does not address causal independence. The vision doc says `distinct_root_causes >= 2` — "root causes", not "themes" — but the implementation as designed counts themes.

**Recommendation:** For F7, accept the theme-count proxy as the initial implementation but add a `bypass_min_distinct_themes` config field in `anomaly.Config` alongside the threshold, and document in code comments that theme-count is a proxy for root-cause independence. Add a P1-to-address item: evaluate whether common-cause suppression (e.g., if all fired themes share a common infrastructure dependency visible in signals.db, suppress BYPASS and emit a diagnostic INFORM instead) is warranted in F8. For now: configurable threshold default=2 in Config, as Q1 recommends.

---

### [P0] `ockham resume` may delete factory-paused.json before ratchet_state reset commits — interrupted potlatch failure

**Agent:** fd-tlingit-potlatch-debt-quenching-emergency-reset
**Source domain:** Tlingit potlatch — interrupted destruction ceremony leaves wealth destroyed but debts unquenched
**Isomorphism:** If a potlatch ceremony is interrupted after coppers are broken but before the witnessing is complete, the community is in a worse state than before — wealth is destroyed but debts are not quenched. The copper destruction (factory-paused.json deletion) must occur AFTER the witnessing is complete (ratchet_state reset committed). A partial ceremony is worse than no ceremony.

**Description:** The brainstorm specifies D3 ordering: clear interspect halt record → reset ratchet_state (SQLite tx) → delete factory-paused.json. File deletion is explicitly last because it unblocks dispatch. This ordering is correct in the design. However, the implementation risk is in deferred function execution in Go. If `resume` is written as:

```go
defer os.Remove(haltPath)  // clean up sentinel
// ... do interspect clear ...
// ... do sqlite tx ...
```

...the deferred `os.Remove` will execute even if the SQLite transaction fails or panics. The sentinel is destroyed (factory unblocked) but domains remain at pre-halt autonomy tiers. Agents will be dispatched at `autonomous` tier without human oversight, which is the exact failure the BYPASS was designed to prevent.

Even without a deferred mis-use: if the code structure is `clear interspect → reset SQLite → delete file` but the SQLite step uses multiple statements rather than a single `UPDATE ... WHERE 1=1` in one transaction, a crash between statements leaves some domains at `supervised` and others at `autonomous`. The file still exists (not yet deleted), so halt is preserved — but the ratchet_state is now corrupt. On the next `ockham resume`, the partially-reset state will be fully reset, which may incorrectly promote domains that should have stayed at `supervised` (they were already there from the partial reset, so they get reset to `supervised` again — harmless in this direction). The more dangerous case: if the partial reset set some domains to `supervised` that were at `autonomous`, and the process crashes, those domains are at `supervised` but the halt sentinel still blocks dispatch — the factory is halted AND some domains have already been demoted. Next resume will still work correctly (it resets all to `supervised`), so this is a P1 degradation (state inconsistency visible during the crash window) rather than P0 (if file deletion is truly last).

**Recommendation:** Never use `defer os.Remove(haltPath)` in `ockham resume`. The file deletion must be an explicit, ordered step that only executes after the SQLite transaction has committed and the commit has been confirmed. Use a single `UPDATE ratchet_state SET tier='supervised' WHERE tier != 'supervised'` in one SQLite `BEGIN IMMEDIATE; ... COMMIT` block. Only call `os.Remove(haltPath)` in the happy path after `tx.Commit()` returns nil. Document this ordering invariant in a comment above the deletion call.

---

### [P1] SQLite domain reset likely uses DEFERRED locking — concurrent `ockham check` can read or write ratchet_state during reset

**Agent:** fd-tlingit-potlatch-debt-quenching-emergency-reset
**Source domain:** Tlingit potlatch — no new inter-clan obligations during the destruction ceremony
**Isomorphism:** During the potlatch destruction ceremony, all inter-clan transactions are frozen — no new gift obligations, no debt acknowledgments. A new obligation created during the quenching process would corrupt the calculus of what is being reset. The SQLite transaction for domain reset must close the state-modification space entirely during execution.

**Description:** Go's `database/sql` package uses DEFERRED transaction isolation by default when `db.Begin()` or `db.BeginTx(context.Background(), nil)` is called. SQLite's DEFERRED mode acquires no lock until the first read or write. A concurrent `ockham check` run (scheduled via cron, which is the likely deployment) can read or modify `ratchet_state` — for example, `checkReconfirmation()` reads `ratchet_state` at line 347 — during the gap between `resume` starting its transaction and `resume` acquiring a write lock. In the worst case, a concurrent `evaluateSignals()` call that modifies `signal_state` or triggers a ratchet promotion during the reset window means resume's `UPDATE ratchet_state SET tier='supervised'` overwrites the concurrent write with the reset value, silently discarding it.

For `ockham resume`, this is not merely a data-race concern — it is a safety concern. If a domain was promoted to `autonomous` concurrently with resume's reset transaction, the promotion is overwritten to `supervised`. This is the correct outcome (resume should revoke autonomy), but it happens without any record that the promotion occurred, which may confuse future forensic analysis.

**Recommendation:** Use `BEGIN IMMEDIATE` for the domain reset transaction:

```go
tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
```

Or use SQLite's IMMEDIATE mode via a raw `PRAGMA` / `BEGIN IMMEDIATE` statement if the Go SQLite driver supports it. This acquires a RESERVED lock immediately, preventing any concurrent write from modifying ratchet_state during the reset. Concurrent reads are still permitted (RESERVED does not block readers in WAL mode), which is acceptable — a concurrent `ockham health` reading ratchet_state during reset will see either the pre-reset or post-reset state consistently, not a partial view.

---

### [P2] Pre-halt ratchet_state is not preserved before reset — forensic reconstruction impossible

**Agent:** fd-tlingit-potlatch-debt-quenching-emergency-reset
**Source domain:** Tlingit potlatch — witness record preserves the pre-ceremony obligation state even after obligations are quenched
**Isomorphism:** The potlatch witness record preserves what debts existed before the destruction ceremony, even though those debts are extinguished. The memory of the obligation persists after the material is destroyed. This enables post-ceremony reconstruction of why the ceremony was triggered and whether it was proportionate.

**Description:** The brainstorm's D3 design overwrites `ratchet_state` (sets all tiers to `supervised`) without first recording what tiers each domain held at halt time. After a successful `ockham resume`, there is no way to determine whether the halted factory had 3 domains at `autonomous`, or 1, or 0. This matters for post-incident review: if the BYPASS was a false positive (single infrastructure failure misidentified as compound crisis), the principal needs to know whether the factory was operating at elevated autonomy when the halt fired. A factory at full `supervised` across all domains that triggered BYPASS from a spurious signal deserves a different response than one at `autonomous` in 3 domains.

The interspect halt record (halt-record.json) contains `reason`, `timestamp`, and `event_id` but the brainstorm does not specify that it records the per-domain authority state at halt time.

**Recommendation:** Before executing the `UPDATE ratchet_state SET tier='supervised'` transaction in `ockham resume`, perform a `SELECT agent, domain, tier FROM ratchet_state` and serialize the result as a `pre_halt_authority_snapshot` field in the interspect halt record (or as a separate `halt-authority-snapshot.json` in the same directory). This is a read before the write — it does not affect the reset atomicity — and it costs one additional SELECT query. The snapshot enables post-incident forensics without blocking the reset.

---

### [P3] `--constrained` resume semantics are ambiguous — selective vs. uniform-then-apply

**Agent:** fd-tlingit-potlatch-debt-quenching-emergency-reset
**Source domain:** Tlingit potlatch — named-debt restoration requires full quench first, then explicit revival from witness record
**Isomorphism:** The potlatch's named-debt restoration mode (specific obligations revived after full quenching) is categorically safer than selective quenching (only some debts extinguished while others are left standing). Full quench + selective revival starts from a known clean state; selective quenching starts from an unknown dirty state.

**Description:** The brainstorm (R4) specifies `--constrained` flag: "resumes with frozen themes still frozen (Tier 2 check)." This is ambiguous between two implementations:

A. Selective reset: reset only the domains that are NOT under Tier 2 CONSTRAIN constraints, leave constrained domains untouched. This means some domains are reset to `supervised` and others remain at their pre-halt tier. This creates non-uniform authority state.

B. Full reset + re-apply: reset ALL domains to `supervised`, then apply Tier 2 CONSTRAIN constraints on top of the now-clean state. This is the Tlingit model — all debts quenched, then specific named obligations restored from the witness record.

Implementation A is dangerous because "frozen themes still frozen" could mean those domains stay at `autonomous` (their pre-halt level) while other domains are reset to `supervised`. This is the cross-reference inconsistency that the brainstorm's D3 atomicity requirement was designed to prevent: some domains at `autonomous`, others at `supervised`, with cross-domain bead dependencies between them.

The brainstorm notes that "currently no Tier 2 in codebase, so this is a no-op stub." This is the right time to specify the semantics correctly before Tier 2 is implemented.

**Recommendation:** Document explicitly in the `ockham resume --constrained` implementation comment: "--constrained performs a full domain reset to 'supervised' followed by selective Tier 2 constraint application, not a selective reset. All domains reach 'supervised' before any constraint is re-applied." This ensures that when Tier 2 CONSTRAIN is implemented in F6, the `--constrained` resume mode has a safe, unambiguous semantic.

---

### [P3] `ockham resume` requires `--confirm` but the brainstorm does not specify `--confirm` validation failure mode

**Agent:** fd-minoan-palatial-archive-sealing
**Source domain:** Pylos unsealing ceremony — the wanax's personal verification is required before any scribe may resume writing
**Isomorphism:** The unsealing ceremony required the wanax's personal seal verification before scribes resumed. A scribe who unsealed tablets without the wanax present had violated protocol even if the tablets were authentic — the verification ceremony was itself part of the safety system, not merely a formality.

**Description:** Q4 recommends `--confirm` flag to prevent accidental resumes. The brainstorm does not specify what happens if someone runs `ockham resume` without `--confirm`. The options are: (a) exit with a helpful error and a preview of what resume would do, (b) silently no-op, (c) interactive prompt. Options (b) and (c) are problematic in automated environments (b is silent failure, c blocks automation). Option (a) is correct — fail loudly, show what the resume would have done, require explicit flag.

**Recommendation:** Implement `ockham resume` without `--confirm` as an explicit error with a preview:

```
ockham: factory is halted since <timestamp> (reason: <reason>)
  domains that would be reset: auth=autonomous perf=autonomous open=supervised
  run 'ockham resume --confirm' to proceed
```

This makes the accidental-resume protection visible and informative rather than silent. The preview of which domains would be reset mirrors the Pylos wanax's inspection of both sentinels before ordering the archive opened.
