---
track: adjacent
agents: [fd-go-crash-recovery-atomicity, fd-sqlite-concurrent-access, fd-state-machine-halt-invariants, fd-cli-safety-critical-ux, fd-go-error-handling-propagation]
date: 2026-04-06
---
# Track A: Adjacent Domain Review

## Findings

### [P0] Resume without prior halt silently resets all autonomous domains to supervised
**Agent:** fd-state-machine-halt-invariants
**Description:** The brainstorm's R4 specifies that `ockham resume` resets all `ratchet_state` entries to `tier='supervised'` atomically. However, it does not specify a guard checking whether the factory is currently halted before executing the reset. If an operator runs `ockham resume` as a precautionary measure when no halt is active, the SQLite transaction `UPDATE ratchet_state SET tier='supervised' WHERE tier='autonomous'` succeeds silently. Every domain that had legitimately earned autonomous status through the ratchet is demoted with no audit trail and no warning. The earned autonomy (which may have taken weeks of successful operation to achieve) is destroyed. The factory continues to operate, but now every dispatch decision is re-gated through supervised review, creating an invisible regression in factory throughput. There is no mechanism in the current design to detect this happened or to restore the prior tier levels.
**Recommendation:** Add a halt-state precondition check at the top of the resume command: `if !halt.IsHalted() { return fmt.Errorf("factory is not halted — nothing to resume") }`. This is a one-line guard in the new `runResume()` function. Exit with a non-zero code and a clear message. This guard also prevents the domain reset SQL from executing when there is nothing to resume.

---

### [P1] BYPASS trigger sentinel write failure silently degrades in check.go's error handling pattern
**Agent:** fd-go-error-handling-propagation
**Description:** The brainstorm places the BYPASS trigger inside `anomaly.Evaluator.Evaluate()`, which is called from `check.go:evaluateSignals()` at line 108. The existing pattern in `evaluateSignals()` wraps the result: `return fmt.Errorf("evaluate: %w", err)`. However, `runCheck()` at line 61-62 catches this error with `fmt.Fprintf(os.Stderr, "ockham: signal evaluation degraded: %v\n", err)` and continues, returning `nil` (exit 0). This means if the BYPASS trigger fires but `os.WriteFile` for `factory-paused.json` fails (disk full, permissions error, read-only filesystem), the error propagates up to `evaluateSignals()`, which returns it, but `runCheck()` logs it to stderr and exits 0. The factory continues operating unsupervised. A cron job monitoring exit codes sees success. The BYPASS condition (2+ fired themes indicating simultaneous anomalies) is swallowed. This is a safety-critical failure: the system detected an emergency condition but failed to act on it and reported success.
**Recommendation:** Introduce a distinction between degraded-continue errors and safety-critical errors in the BYPASS path. The cleanest approach: `Evaluator.Evaluate()` should return a typed error (e.g., `ErrBypassFailed`) when the BYPASS trigger fires but sentinel write fails. `evaluateSignals()` checks for this type: `if errors.Is(err, anomaly.ErrBypassFailed) { return err }` (propagate, do not degrade). `runCheck()` similarly: `if errors.Is(err, anomaly.ErrBypassFailed) { return err }` (exit non-zero). This preserves the degraded-continue pattern for non-safety-critical errors (bead ingest failures, prune failures) while making BYPASS sentinel failures fatal.

---

### [P1] Double-sentinel divergence state (file absent, record active) has a recovery window where IsHalted() returns false
**Agent:** fd-go-crash-recovery-atomicity
**Description:** The brainstorm's R2 specifies write-before-notify ordering: write `factory-paused.json` first, then `halt-record.json`. This is correct for the trigger path. But consider the resume path (D3): clear interspect halt record -> reset ratchet_state (tx) -> delete `factory-paused.json`. If the process crashes after clearing the interspect record but before deleting `factory-paused.json`, the system is in state (file=present, record=resolved). `IsHalted()` returns true (correct: file exists), but `reconstructHalt()` at `check.go:289-343` checks `if _, err := os.Stat(r.haltPath); err == nil { return nil }` — it short-circuits because the file exists. So this state is safe.

Now consider the BYPASS trigger path crash: if the process dies after writing `halt-record.json` but before writing `factory-paused.json` (inverted write order due to a bug), the system is in state (file=absent, record=active). `IsHalted()` returns false. `reconstructHalt()` at line 311 checks `record.Status != "active"` and would reconstruct. BUT: reconstructHalt() runs in Step 3 of `runCheck()`, while `evaluateSignals()` runs in Step 2. If the halt guard (D5) is placed at the top of `evaluateSignals()`, it calls `IsHalted()` which returns false, so signal evaluation proceeds. The BYPASS trigger fires again (same conditions), attempts to write `factory-paused.json`, and this succeeds. The file is now created, and then `halt-record.json` is written again (overwriting the existing active record). This is self-healing. However, during the window between `runCheck()` start and `evaluateSignals()` completing, `IsHalted()` returns false, and if a concurrent `ockham dispatch advise` runs, it will proceed through `governor.Evaluate()` without the halt guard blocking it. The dispatch would succeed during what should be a halted state.
**Recommendation:** Ensure the BYPASS trigger write order is enforced as `factory-paused.json` FIRST (matching R2's write-before-notify contract). Add a comment in the BYPASS trigger code: `// CRITICAL: file write MUST precede record write — R2 write-before-notify`. Additionally, consider having `reconstructHalt()` run BEFORE `evaluateSignals()` in the `runCheck()` sequence (move Step 3 before Step 2) so that any divergent state from a previous crash is repaired before signal evaluation begins.

---

### [P1] Health command reads multiple tables without a transaction, producing inconsistent snapshots
**Agent:** fd-sqlite-concurrent-access
**Description:** The brainstorm's D2 specifies health output including halt status, signal states, pleasure signals, authority snapshot summary, and ratchet state. The existing `signals.go` command (which serves as a template for health) reads `signal_state` rows via sequential queries at lines 38-77 without a transaction wrapper. The new health command will similarly need to read `signal_state`, `authority_snapshot`, and `ratchet_state`. Without an explicit `BEGIN` / `COMMIT` (read transaction), these reads are not snapshot-consistent under SQLite WAL mode. A concurrent `ockham check` could commit between the signal_state read and the ratchet_state read, producing a health JSON where signals show 2 fired themes (pre-BYPASS) but ratchet_state shows all domains at supervised (post-resume from a different session). Meadowsyn would display contradictory data: "BYPASS condition detected" alongside "all domains supervised, no halt active." For a dashboard that operators rely on during incidents, inconsistent snapshots erode trust.
**Recommendation:** Wrap all health reads in a single read transaction. In the new health command: `tx, err := db.Conn().BeginTx(ctx, &sql.TxOptions{ReadOnly: true})` and use `tx.QueryRow` / `tx.Query` for all reads, then `tx.Commit()`. This gives a consistent point-in-time snapshot under WAL mode. This is approximately 5 lines of additional code.

---

### [P1] evaluateSignals() halt guard could block reconstructHalt() in degraded call sequence
**Agent:** fd-state-machine-halt-invariants
**Description:** The brainstorm's D5 proposes adding a halt check at the top of `evaluateSignals()`. The current call order in `runCheck()` (check.go lines 56-73) is: snapshotAuthority -> evaluateSignals -> reconstructHalt -> checkReconfirmation. Each step is independent: if evaluateSignals() returns early due to the halt guard, runCheck() continues to reconstructHalt(). So reconstructHalt() is NOT blocked by the evaluateSignals() halt guard. This is correct as designed.

However, there is a subtler issue: the brainstorm's D5 says "evaluateSignals() should check halt BEFORE evaluation." If evaluateSignals() returns early (nil error) when halted, the BYPASS trigger code inside Evaluator.Evaluate() never runs. This is correct behavior when halted. But what about the scenario where the factory is halted AND `evaluateSignals()` contains the BYPASS trigger code? If someone adds future logic that needs to run during halt (e.g., de-escalation timers, signal age tracking), placing the halt guard at the top of evaluateSignals() creates a maintenance trap where all code inside the function is unconditionally blocked during halt, even code that should be read-only.
**Recommendation:** The halt guard in evaluateSignals() should be clearly documented: `// Halt guard: skip ALL signal evaluation when halted (INV-8). Read-only operations (snapshotAuthority, reconstructHalt, checkReconfirmation) are separate steps in runCheck() and are NOT blocked by this guard.` Additionally, if future de-escalation timers are needed, they should be a separate step in runCheck(), not embedded in evaluateSignals().

---

### [P1] persistSignal() silently discards SetSignalState errors, causing redundant BYPASS triggers
**Agent:** fd-go-error-handling-propagation
**Description:** In `evaluator.go` lines 118-124, `persistSignal()` calls `e.db.SetSignalState()` but does not check or return the error. Similarly, `persistPleasure()` at lines 126-138 discards errors from `SetSignalState()`. For F7, this creates a concrete problem: after the BYPASS trigger fires and halts the factory, the signal states that caused the BYPASS (2+ themes with `StatusFired`) should be persisted so that the next `ockham check` (after resume) can see them in `loadPriorSignal()`. If `persistSignal()` silently fails, the next check run starts with `StatusCleared` for that theme (line 108: `return ThemeSignal{Theme: theme, Status: StatusCleared}`). If the drift condition still holds, the signal fires again, and if 2+ themes fire, BYPASS triggers again. The O_EXCL write in `reconstructHalt()` at check.go line 333 returns `os.IsExist` which is handled gracefully (line 335: `return nil`), so this does not crash. But it produces redundant halt events in the audit trail (interspect), polluting incident forensics.
**Recommendation:** Change `persistSignal()` to return an error: `func (e *Evaluator) persistSignal(theme string, sig ThemeSignal) error`. The caller in `Evaluate()` (line 90) should check the error. For the BYPASS code path specifically, a failed persist after a successful sentinel write should be logged as a warning but not fail the BYPASS (the halt is already effective). For non-BYPASS evaluations, the existing degraded-continue pattern is acceptable, but the error should at minimum be logged to stderr (matching the pattern at evaluator.go line 95 for prune errors).

---

### [P1] Resume command missing --confirm flag enforcement with clear actionable error
**Agent:** fd-cli-safety-critical-ux
**Description:** The brainstorm's Q4 recommends requiring `--confirm` to prevent accidental resume. This is the correct UX decision, but the brainstorm does not specify what happens when `--confirm` is absent. For safety-critical CLIs, the failure mode matters as much as the guard itself. If `ockham resume` without `--confirm` silently no-ops (exits 0, no output), the operator believes the factory resumed when it did not. If it prints an error but exits 0, shell scripts treat it as success. The brainstorm also does not specify what the `--confirm` flag's value should be (boolean flag? confirmation string like `--confirm=RESUME`?).
**Recommendation:** Without `--confirm`: exit non-zero with message `"ockham resume requires --confirm to proceed. This will reset all domains to supervised tier.\nCurrent halt reason: <reason from factory-paused.json>\nHalted since: <timestamp from factory-paused.json>\nRun: ockham resume --confirm"`. This tells the operator: (1) what they need to do, (2) why the factory was halted, (3) when it was halted, (4) what the consequence of resuming is. Use a boolean `--confirm` flag (not a confirmation string) since the halt reason display gives the operator enough context to make an informed decision. The boolean approach matches Go CLI conventions (cobra flags).

---

### [P2] Health command exit code semantics not specified for halted state
**Agent:** fd-cli-safety-critical-ux
**Description:** The brainstorm's R1 says health "must work when halted (read-only operation)" but does not specify the exit code. If `ockham health` returns exit 0 when halted, automated consumers (Meadowsyn shell polling, monitoring scripts) that check exit codes as a health proxy will not alert. If it returns non-zero, `jq` pipeline consumers that parse the JSON on stdout may skip processing because the command "failed." Both are valid, but the choice must be explicit. The existing `ockham dispatch advise` returns non-zero when halted (governor.Evaluate returns error at governor.go line 49), creating a precedent where halt = non-zero. But health is a read command, and read commands conventionally return 0 if they successfully produced output.
**Recommendation:** `ockham health` should always exit 0 when it successfully produces JSON (even when halted). The halt state is data, not an error. Consumers should check the `halted` field in the JSON output. Reserve non-zero exits for operational failures (DB open failed, JSON marshal failed). Document this in `--help`: "Exit 0: health JSON produced. Exit 1: failed to produce health JSON. The 'halted' field in the output indicates factory halt state." This matches the convention of `kubectl get` (exit 0 with degraded state in output) rather than `systemctl is-active` (exit non-zero for inactive).

---

### [P2] Resume output not specified -- operator cannot verify success
**Agent:** fd-cli-safety-critical-ux
**Description:** The brainstorm specifies what resume DOES (clear sentinels, reset ratchet_state) but not what it PRINTS on success. After a high-stress incident (factory halted due to 2+ anomalous themes), the operator needs confirmation that the resume succeeded and what the resulting state is. Without explicit output, the operator must run `ockham health` separately to verify, which adds latency and cognitive load during incident recovery.
**Recommendation:** On successful resume, print a structured summary: `"Factory resumed. Sentinels cleared: factory-paused.json, halt-record.json. Domains reset: N domains -> supervised tier (from autonomous). Next ockham check will re-evaluate signal state."` If `--json` is provided, output the same as JSON for Meadowsyn consumption. This is a UX detail that should be part of the implementation spec, not deferred to the implementer's discretion.

---

### [P2] INV-8 halt-guard error message lacks context for informed resume decisions
**Agent:** fd-cli-safety-critical-ux
**Description:** The brainstorm's D4 specifies the halt-guard message as `"factory is halted -- run 'ockham resume' first"`. This message is implemented in `intent.go` line 54 as `"factory halted: %s exists -- run 'ockham resume' first"` where `%s` is the file path. The file path is an internal implementation detail that does not help the operator. The message does not include: (1) WHY the factory halted (the `reason` field from `factory-paused.json`), (2) WHEN it halted (the `timestamp` field), (3) whether there are still active fired signals that caused the halt. Without this context, the operator may blindly run `ockham resume` without investigating the root cause, which defeats the purpose of the algedonic halt.
**Recommendation:** Enhance `haltGuard()` in `intent.go` (line 51) to read `factory-paused.json`, parse the reason and timestamp fields, and include them in the error message: `"factory halted since <time> (reason: <reason>) -- investigate with 'ockham signals' then run 'ockham resume --confirm'"`. If the file cannot be parsed (corrupt or empty), fall back to the current message. This is approximately 10 lines of additional code in `haltGuard()`.

---

### [P2] WAL file deletion in recover() races with concurrent health reads
**Agent:** fd-sqlite-concurrent-access
**Description:** In `signals/db.go` lines 210-212, `recover()` deletes the database file plus `-wal` and `-shm` files: `os.Remove(db.path + suffix)` for each suffix. If `ockham health` (a read-only command) has the database open in WAL mode at the same moment that a concurrent `ockham check` triggers recovery (detected corruption), the `-wal` deletion can cause the health command's SQLite connection to return `SQLITE_IOERR` or read stale/corrupt data. This is because SQLite's WAL mode maintains the -wal file as a shared resource between connections. In practice, this is unlikely because recovery only triggers on confirmed corruption and health commands are short-lived, but the window exists.
**Recommendation:** Add a comment documenting this known race: `// NOTE: concurrent readers may see SQLITE_IOERR during recovery. This is acceptable because recovery only triggers on confirmed corruption, and the alternative (not recovering) is worse.` If the health command encounters a database error during a read, it should produce a degraded health JSON (with an `"error"` field) rather than failing silently or crashing.

---

### [P2] BYPASS threshold of 0 or 1 in configurable Config would fire on every check
**Agent:** fd-state-machine-halt-invariants
**Description:** The brainstorm's Q1 recommends making the BYPASS threshold configurable in `anomaly.Config` with default 2. If a user sets this to 0, BYPASS fires whenever 0+ themes are fired (always, since 0 >= 0 is true). If set to 1, BYPASS fires on any single fired theme, making every INFORM signal an immediate halt. The current `Config` struct in `drift.go` (lines 10-18) does not validate field values. `DefaultConfig()` returns sane defaults, but if the config is loaded from a file or overridden programmatically, there is no validation gate.
**Recommendation:** Add a validation function for Config (called from `NewEvaluator` or `Evaluate`): `if cfg.BypassThreshold < 2 { return error("bypass_threshold must be >= 2: values below 2 cause immediate halt on any INFORM signal") }`. Alternatively, clamp to minimum 2 in `DefaultConfig()` and document the invariant. This prevents an accidental config change from creating a factory that halts on every check cycle.

---

### [P2] check.go always exits 0 regardless of safety-critical failures
**Agent:** fd-go-error-handling-propagation
**Description:** In `check.go` lines 56-73, `runCheck()` logs every step error to stderr and returns `nil`. This means `ockham check` always exits 0 regardless of whether signal evaluation failed, halt reconstruction failed, authority snapshot failed, or reconfirmation check failed. For cron-scheduled check runs, this makes it impossible to detect check failures via exit code monitoring. While the degraded-continue pattern is appropriate for individual step failures in isolation, the aggregate effect is that a completely broken check (all 4 steps failed) still reports success.
**Recommendation:** Track whether any step produced a non-degraded error and return a final error if safety-critical steps failed. Minimally: if `evaluateSignals()` returns an error AND the error is a BYPASS failure (typed error from finding #2), `runCheck()` must return non-zero. For a broader fix: count failed steps and return a summary error if more than N steps failed, e.g., `"ockham check: 3/4 steps degraded -- see stderr for details"`. This preserves degraded-continue for individual steps while surfacing systemic failures.

---

### [P2] Resume ratchet reset SQL must filter on tier correctly
**Agent:** fd-sqlite-concurrent-access
**Description:** The brainstorm's D3 specifies: `UPDATE ratchet_state SET tier='supervised' WHERE tier='autonomous'`. The ratchet_state schema (db.go lines 32-38) has three possible tiers implied by the system: shadow, supervised, and autonomous. The vision doc's halt protocol (vision.md line 342) says "All domains reset to supervised atomically." The WHERE clause `tier='autonomous'` only resets autonomous domains. Shadow domains remain at shadow tier. Supervised domains remain at supervised. This is arguably correct: shadow domains should not be promoted to supervised by a resume, and supervised domains are already at the target level. However, the brainstorm text says "domain reset: all ratchet_state entries reset to 'supervised' atomically" (R4) without a WHERE clause, which contradicts the SQL in D3. If the intent is truly "all entries," the SQL should be `UPDATE ratchet_state SET tier='supervised'` (no WHERE), which would promote shadow domains to supervised -- a safety regression since shadow domains have not earned supervised trust.
**Recommendation:** The D3 SQL (`WHERE tier='autonomous'`) is correct. The R4 text is imprecise. Clarify R4 to read: "all ratchet_state entries with tier='autonomous' reset to 'supervised' atomically. Shadow and supervised tiers are not affected." This prevents an implementer from reading R4 literally and omitting the WHERE clause.

---

### [P2] O_EXCL race between BYPASS trigger and reconstructHalt() on concurrent check invocations
**Agent:** fd-go-crash-recovery-atomicity
**Description:** The BYPASS trigger (new code in `Evaluator.Evaluate()`) will write `factory-paused.json`, and `reconstructHalt()` (check.go line 333) also writes `factory-paused.json` using `os.O_EXCL`. If two concurrent `ockham check` invocations run simultaneously and both detect a BYPASS condition, both will attempt to create the file with O_EXCL. One succeeds, the other gets `os.IsExist`. In `reconstructHalt()`, this is handled gracefully (line 335: `return nil`). The new BYPASS trigger code must also handle `os.IsExist` gracefully -- the file already exists means the halt is already in effect, which is the desired outcome. If the BYPASS trigger treats `os.IsExist` as an error and propagates it, the second concurrent check invocation would report a BYPASS failure when the halt is actually working correctly.
**Recommendation:** In the BYPASS trigger sentinel write, use the same O_EXCL + IsExist pattern as `reconstructHalt()`: `f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0644); if os.IsExist(err) { /* halt already active, proceed to record write */ }; if err != nil { return ErrBypassFailed }`. This makes both code paths handle the race identically.

---

### [P3] Partial sentinel write on BYPASS trigger leaves inconsistent double-sentinel state
**Agent:** fd-go-crash-recovery-atomicity
**Description:** The brainstorm specifies writing `factory-paused.json` first, then `halt-record.json`. If the first write succeeds but the second fails (e.g., `~/.clavain/interspect/` directory does not exist), the system is in state (file=present, record=absent/stale). `IsHalted()` returns true (correct), so the factory is halted. But the double-sentinel guarantee is broken: `reconstructHalt()` checks the record for reconstruction purposes, and future code may rely on the record for audit trail or incident forensics. The brainstorm does not specify a recovery path for this divergence direction.
**Recommendation:** After BYPASS trigger writes both sentinels, if the second write fails, log a prominent warning: `"CRITICAL: halt sentinel written but interspect record failed: %v -- halt is effective but audit trail is incomplete"`. Do NOT roll back the first write (the file is the safety-critical sentinel). The operator will see the warning on stderr and can manually investigate. Additionally, `ockham health` should include a `sentinel_consistency` field that checks both sentinels and reports divergence.

---

### [P3] health JSON schema_version field needs forward-compatibility contract
**Agent:** fd-cli-safety-critical-ux
**Description:** The brainstorm's D2 includes `"schema_version": 2` in the health JSON. This implies Meadowsyn will check this field to handle schema changes. However, there is no specification for: (1) what Meadowsyn should do when it encounters an unknown schema_version (fail? ignore unknown fields? degrade?), (2) whether fields can be added without incrementing the version (additive-only changes), (3) whether removing a field requires a version bump. Without this contract, the first schema change will require coordinating Meadowsyn and Ockham releases.
**Recommendation:** Document the contract: "schema_version increments on breaking changes (field removal, type change). Additive changes (new fields) do not increment. Consumers must ignore unknown fields." This is a JSON API versioning convention that should be stated once and referenced. Add it as a comment in the health command implementation.

---

### [P3] loadPriorSignal silently returns StatusCleared on unmarshal errors
**Agent:** fd-go-error-handling-propagation
**Description:** In `evaluator.go` lines 105-116, `loadPriorSignal()` returns `StatusCleared` on both `GetSignalState` errors (line 107) and `json.Unmarshal` errors (line 113). This means a corrupt signal_state entry (garbled JSON from a partial write) is silently treated as "no prior signal," causing a full re-evaluation from scratch. For most signals, this is a benign degradation. For the BYPASS trigger, however, re-evaluating from scratch when prior state is corrupt means: if 2+ themes still have drift above the fire threshold, BYPASS fires again. Combined with the O_EXCL handling, this is safe (the file already exists). But the corrupt state is never surfaced to the operator and never self-repairs (the corrupt entry stays in signal_state forever, overwritten only if the key matches exactly).
**Recommendation:** Log unmarshal errors to stderr at `loadPriorSignal()` line 113: `fmt.Fprintf(os.Stderr, "ockham: corrupt signal state for %q, treating as cleared: %v\n", theme, err)`. This makes the degradation visible in logs without changing the functional behavior.
