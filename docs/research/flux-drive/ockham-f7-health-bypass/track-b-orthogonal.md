---
track: orthogonal
agents: [fd-nuclear-scram-sequencing, fd-icu-alarm-escalation, fd-safety-board-policy-freeze, fd-psm-dual-confirmation]
date: 2026-04-06
---
# Track B: Orthogonal Discipline Review

## Context

F7 brainstorm reviewed against actual code: `os/Ockham/internal/halt/halt.go`,
`os/Ockham/cmd/ockham/check.go`, `os/Ockham/internal/governor/governor.go`,
`os/Ockham/internal/anomaly/evaluator.go`, `os/Ockham/internal/anomaly/drift.go`.

The BYPASS trigger does not yet exist in code — the findings below are pre-implementation
review of the design as specified in the brainstorm.

---

## Findings

### [P1] Interspect write error on BYPASS must not roll back the halt

**Agent:** fd-nuclear-scram-sequencing
**Source discipline:** Nuclear reactor protection systems — actuator-first sequencing
**Description:**
The brainstorm specifies write-before-notify ordering (R2): create factory-paused.json FIRST, then record to interspect, then log. It further specifies that crash recovery falls back to the file as the authority. However, the error-handling design is not yet locked: if the BYPASS trigger function is written with a shared error-return branch that rolls back factory-paused.json when interspect write fails, the halt is silently voided. The design intent — that the file is the authority and interspect failure is tolerable — must be encoded in the error handling, not left as a convention that a future refactor can silently invert.

The existing `reconstructHalt()` in `check.go` (line 289) is correctly written in the actuator-first direction: it writes the sentinel with `O_EXCL` before returning. The BYPASS trigger must follow the same discipline. Specifically, `triggerBYPASS()` (to be implemented in `anomaly.Evaluator.Evaluate`) must return success after the filesystem write succeeds, treating interspect write failure as a logged degradation — not as a trigger to call `os.Remove(haltPath)`.

**Recommendation:** In the BYPASS trigger function, separate the error paths: `if err := writeHaltSentinel(); err != nil { return err }` is a hard failure; `if err := writeInterspectRecord(); err != nil { fmt.Fprintf(os.Stderr, "ockham: interspect halt record degraded: %v\n", err) }` is a soft degradation. The function must return nil after the sentinel write succeeds regardless of interspect result.

---

### [P1] Tier 2 CONSTRAIN stub in `ockham resume` must fail visibly, not silently no-op

**Agent:** fd-nuclear-scram-sequencing
**Source discipline:** Nuclear reactor protection — post-trip restart checklists gate on verified physical conditions
**Description:**
The brainstorm specifies (R4) that `ockham resume` checks active Tier 2 CONSTRAIN signals, which is a no-op stub because Tier 2 does not exist yet. This is structurally identical to a SCRAM restart checklist item that returns "OK" unconditionally because the instrumentation is not yet installed. When Tier 2 ships in F6, the stub is invisible — it has been passing silently and no test exercises the CONSTRAIN-active gate. The resume command would then allow restart into a factory that still has active constraints.

The stub must be written to make its incompleteness detectable: an interface that future Tier 2 can implement, with a TODO that fails at compile time or at least at test time until fulfilled. A comment is not sufficient.

**Recommendation:** Define a `ConstrainChecker` interface in the resume path: `type ConstrainChecker interface { ActiveConstraints() ([]string, error) }`. Wire a `nilConstrainChecker` stub that always returns empty. When Tier 2 ships, the real implementation replaces the stub. This makes the wiring point explicit and the stub's presence testable.

---

### [P1] `evaluateSignals()` runs BEFORE `reconstructHalt()` — a recovered halt is not respected in the same check cycle

**Agent:** fd-nuclear-scram-sequencing
**Source discipline:** Nuclear reactor protection — halt authority precedes all evaluation
**Description:**
In `check.go`'s `runCheck()` (lines 56–72), the step order is:

```
Step 1: snapshotAuthority()
Step 2: evaluateSignals()    ← runs first
Step 3: reconstructHalt()    ← halt reconstruction happens here
Step 4: checkReconfirmation()
```

If the factory-paused.json is absent but halt-record.json is active (the crash-recovery scenario), `evaluateSignals()` runs at Step 2 without halt protection. `reconstructHalt()` at Step 3 will repair the sentinel, but signal evaluation has already executed against a factory that was, in intent, halted. D5 in the brainstorm proposes adding a halt check at the top of `evaluateSignals()`, but if `reconstructHalt()` runs after evaluation, the D5 halt guard checks `halt.IsHalted()` against a file that does not yet exist, and the guard passes unconditionally.

**Recommendation:** Reorder `runCheck()` to: Step 1: `reconstructHalt()`, Step 2: `snapshotAuthority()`, Step 3: `evaluateSignals()` (with D5 halt guard), Step 4: `checkReconfirmation()`. This ensures that by the time evaluateSignals runs, the sentinel file is in the correct state regardless of whether this is a cold-start recovery or a normal cycle.

---

### [P2] Resume atomicity: SQLite-succeeds-but-file-delete-fails leaves inconsistent state that silently re-executes domain reset on next resume

**Agent:** fd-nuclear-scram-sequencing
**Source discipline:** Nuclear reactor protection — crash recovery must not have unbounded side effects
**Description:**
D3 specifies the resume order: clear interspect halt record → reset ratchet_state (SQLite tx) → delete factory-paused.json. If the SQLite transaction succeeds but the file deletion fails, the next `ockham resume` attempt will re-execute the SQLite `UPDATE SET tier='supervised'` on a ratchet_state that may have already been partially re-promoted after the first resume. The idempotency of the SQLite reset is accidental (resetting 'supervised' to 'supervised' is a no-op), not guaranteed by the design.

**Recommendation:** After the SQLite transaction commits, record a "reset-committed" marker in the sentinel file itself before deletion (e.g., `{"status": "resume-committed", ...}`). If the subsequent file deletion fails, the next resume attempt reads the marker and skips the SQLite reset, proceeding directly to file deletion and interspect clear. This makes the resume idempotent by design rather than by accident.

---

### [P1] Health JSON `signals` object is missing actuator state — consumer cannot distinguish a firing signal from a saturated actuator

**Agent:** fd-icu-alarm-escalation
**Source discipline:** ICU alarm management — every alarm tier has a mandatory linked action visible to the consumer
**Description:**
The proposed health JSON schema (D2) exposes `"advisory_offset": -1` for a fired signal but does not expose whether that offset is at the floor (`OffsetMin`, which from `drift.go` is effectively `-MaxAdvisoryPerCycle` per cycle and potentially capped by `FactoryGuard`). A Meadowsyn consumer reading `status: fired, advisory_offset: -1` cannot determine whether Ockham is still actively responding or whether the actuator has been at floor for 10 cycles with no remaining headroom. The ICU parallel: a cardiac monitor showing arrhythmia without indicating whether the nurse has acknowledged it and medication has been administered.

The `ThemeSignal` struct in `anomaly.go` (line 18) already carries `AdvisoryOffset` and `ConsecutiveClears`. The health JSON must expose both, plus a derived field `at_floor: bool` (true when `AdvisoryOffset <= -FactoryGuard/numThemes` or when the FactoryGuard has capped this theme's offset).

**Recommendation:** Add to the per-signal health JSON object: `"advisory_offset": -1, "consecutive_clears": 0, "at_advisory_floor": false`. The `at_advisory_floor` field is computed at health-render time as `sig.AdvisoryOffset == -(cfg.MaxAdvisoryPerCycle)` AND `sig.Status == StatusFired`. One struct field addition in the health render path, zero changes to the evaluator.

---

### [P1] Pleasure signal trends in health JSON must use the same window as dispatch decisions

**Agent:** fd-icu-alarm-escalation
**Source discipline:** ICU alarm management — display and decision windows must not diverge
**Description:**
The brainstorm does not specify which window the health JSON pleasure trends are computed over. The evaluator (`evaluator.go` line 82–86) uses `cfg.MaxWindow` (default 30 beads) for the rolling window. If the health command recomputes pleasure signals over a different window (e.g., 24h wall-clock for readability), the principal reads health JSON showing `cycle_time: improving` while Ockham's ratchet logic is simultaneously reacting to a degraded 30-bead window. This is a trust-destroying inconsistency: the dashboard says improving, the dispatch weights say degraded.

**Recommendation:** Health JSON must read pleasure state from `signal_state` (the already-persisted pleasure signals in `signals.db`), not recompute from raw metrics. The `persistPleasure()` path in `evaluator.go` (line 126–138) already writes `pleasure:{name}:{theme}` keys to `signal_state`. The health command reads these persisted values, so the display window is always identical to the decision window by construction.

---

### [P2] `halt_reason` in health JSON must be structured, not a Go error string

**Agent:** fd-icu-alarm-escalation
**Source discipline:** ICU alarm management — alarm reason must be machine-parseable for automated routing
**Description:**
The `haltRecord` struct in `check.go` (line 281) has `Reason string`. If health JSON propagates this as a free-form string (e.g., `"2 distinct root causes fired simultaneously: auth, perf"`), Meadowsyn's alerting logic must parse natural language to know which themes fired. The structured information is available at halt-write time — the evaluator knows exactly which themes have `Status == StatusFired`.

**Recommendation:** Change `halt_reason` in health JSON from a string to:
```json
"halt_reason": {
  "code": "bypass_multi_root_cause",
  "fired_themes": ["auth", "perf"],
  "fired_at": 1743955200
}
```
This requires the BYPASS trigger to write a structured halt record rather than a string reason. The `haltRecord` struct in `check.go` should grow a `FiredThemes []string` field and a `Code string` field. One struct change, zero consumer-side string parsing.

---

### [P2] `last_check` in health JSON must be the last completed check cycle timestamp, not the health render time

**Agent:** fd-icu-alarm-escalation
**Source discipline:** ICU alarm management — stale-state detection requires check-cycle time, not render time
**Description:**
The brainstorm specifies `last_check` as a field in health JSON without defining whether it is the wall-clock time of the last completed `ockham check` cycle or the time the health command rendered the JSON. These diverge when check cycles are slow or when health is polled frequently. A Meadowsyn consumer using `last_check` to detect stale state (e.g., "last check was > 10 minutes ago, show warning") will see always-fresh values if the health command writes `time.Now()` rather than the stored last-check timestamp.

The signals.db already writes `updated_at` on every `signal_state` row (`check.go` line 403: `r.db.SetSignalState(key, "pending", now.Unix())`). The `last_check` field should be the MAX of all `updated_at` values in `signal_state`, not `time.Now()` at health-render time.

**Recommendation:** In the health command implementation, compute `last_check` as `SELECT MAX(updated_at) FROM signal_state` against the signals.db. One SQL query, no new state.

---

### [P1] INV-8 write-block inventory is incomplete: `bd set-state` writes from running agents are not covered

**Agent:** fd-safety-board-policy-freeze
**Source discipline:** ICAO Annex 13 investigation — evidence preservation requires a complete write inventory, not just the most visible operations
**Description:**
The brainstorm's INV-8 implementation (D4, D5) blocks `intent set`, `intent freeze`, and signal evaluation. It does not address `bd set-state` writes: agents that were dispatched before the BYPASS halt fired continue running until they naturally complete. These agents write bead custom state via `bd set-state` during their shutdown window. This bead state is evidence that the principal uses to diagnose the halt cause — it is the factory's equivalent of flight crew notes written after an incident. Allowing post-halt agent writes to modify bead state before the principal reads it contaminates the evidence base.

The halt does not instantly kill running agents (the brainstorm correctly notes this). The INV-8 write-block must extend to any state mutation that changes the diagnostic picture visible to the principal.

This is a design-boundary question, not a bug in existing code, but it must be resolved before implementation. Two approaches: (a) do not block `bd set-state` — accept that running agents can still write state during the shutdown window, document this as a known limitation; (b) add a halt check to the `bd` wrapper at `~/.local/bin/bd` that blocks set-state when factory-paused.json exists, at the cost of potentially interrupting legitimate agent shutdown writes.

**Recommendation:** Take approach (a) as an explicit documented decision: running agents may write bead state during the shutdown window; this is acceptable because the principal's primary diagnostic evidence is the halt record and signal state (which are frozen). Document the boundary in the `ockham resume` error message and in the halt record itself. Add a `NOTE: agents running at halt time may have written bead state during shutdown window` field to the halt record JSON.

---

### [P1] `evaluateSignals()` halt check (D5) may not cover all invocation paths

**Agent:** fd-safety-board-policy-freeze
**Source discipline:** ICAO Annex 13 investigation — write-block must cover all operational paths, not just the primary path
**Description:**
D5 adds a halt check at the top of `evaluateSignals()` in `check.go`. However, `evaluateSignals()` is a method on `CheckRunner` (line 83), and the halted check in the governor (`governor.go` line 45) is separate. The brainstorm notes this split explicitly ("governor.Evaluate() checks halt, but check.go calls evaluateSignals() independently").

The finding is that any invocation of `ockham check` — direct CLI, cron, SessionStart hook — goes through `runCheck()` which calls `evaluateSignals()`. If D5 adds the halt guard at the top of `evaluateSignals()`, all invocations are covered. The risk is that a `--dry-run` flag (line 84–87) currently bypasses evaluation entirely, but the dry-run guard returns early before the halt check that D5 would add. Depending on implementation order, `--dry-run` could silently bypass the halt guard.

**Recommendation:** In the D5 implementation, place the halt guard BEFORE the dry-run check: `if isHalted { return nil }` then `if r.dryRun { ... }`. This ensures that `--dry-run` on a halted factory does not print "would evaluate signals" — it silently returns, consistent with the principle that halted state is authoritative over all operations.

---

### [P2] Blocked-operation error for halted factory should include halt timestamp and fired themes

**Agent:** fd-safety-board-policy-freeze
**Source discipline:** ICAO Annex 13 investigation — blocked-operation notifications include investigation reference and scope
**Description:**
D4 specifies the error message: `"factory is halted — run ockham resume first"`. This is correct but loses the halt context. An operator receiving this error at 3am cannot determine how long the factory has been halted or which themes fired BYPASS without separately running `ockham health`. The governor's existing error in `governor.go` (line 49) is `fmt.Errorf("factory halted: %s exists", g.halt.Path())` — also bare.

**Recommendation:** Define `ErrFactoryHalted` as a struct type carrying `HaltedAt int64` and `FiredThemes []string`, loaded from factory-paused.json at halt.IsHalted() time. The CLI formats it as: `"factory halted since 2026-04-06T03:14:00Z (auth, perf) — run ockham resume to continue"`. The `halt.Sentinel` can expose `LoadRecord() (*HaltRecord, error)` so all callers can enrich their errors without re-reading the file independently.

---

### [P1] Root-cause deduplication treats theme-tag co-occurrence as causal independence

**Agent:** fd-psm-dual-confirmation
**Source discipline:** IEC 61511 Safety Instrumented Systems — redundancy requires independent failure modes, not just distinct channel labels
**Description:**
The BYPASS trigger counts distinct themes with `Status == StatusFired` (R2: "count distinct themes with fired signals, not raw signal count"). This is a 2-of-N voting logic where each theme is treated as an independent channel. However, themes in the current evaluator (`evaluator.go`) are derived from bead lane labels. If 80% of beads are tagged with both `auth` and `perf` lanes, a single underlying corpus quality event (e.g., a batch of long-running cross-domain beads) fires both theme signals simultaneously, and the `>= 2 distinct themes` check passes — triggering BYPASS for what is effectively one root cause.

The `EvaluateDrift()` function in `drift.go` (lines 38–82) computes drift independently per-theme using the theme's own bead population. Two themes share beads if those beads have both lane labels — but `closedBeadsFromBD()` in `check.go` (lines 174–227) assigns each bead to exactly ONE lane (the first `lane:` label found, line 202–208). So in the current implementation, bead populations are disjoint per-theme: a bead is in exactly one theme. This partially mitigates the common-cause concern.

However, the mitigation is accidental, not designed. If the label extraction logic changes (e.g., multi-lane beads), common-cause firing becomes possible without any guard.

**Recommendation:** Document the single-lane-per-bead invariant as an explicit design constraint in `closedBeadsFromBD()` and in the BYPASS trigger: "Bead populations are disjoint by construction (each bead maps to exactly one lane). If multi-lane beads are introduced, the BYPASS root-cause deduplication must be re-evaluated." Add a comment in the BYPASS trigger code referencing this constraint by name.

---

### [P1] `reconstructHalt()` is not called on process startup — only on check cycles that find an inconsistent state

**Agent:** fd-psm-dual-confirmation
**Source discipline:** IEC 61511 Safety Instrumented Systems — channel reconciliation must occur at system startup, not only during steady-state polling
**Description:**
The crash scenario specified in the brainstorm (R2: "if process dies between file write and interspect record, file is the authority") has a reverse: process dies after writing interspect halt record but BEFORE creating factory-paused.json. On next startup, `halt.IsHalted()` returns false (file absent). `reconstructHalt()` in `check.go` (line 289) handles this case — but only when called. In `runCheck()` (line 38), `reconstructHalt()` is called at Step 3, after `evaluateSignals()` at Step 2.

This means: on the first `ockham check` after a crash-during-write, `evaluateSignals()` runs without the halt sentinel. The evaluator may fire new signals or clear existing ones against a factory that is, by interspect record, halted. Only at Step 3 does `reconstructHalt()` repair the file — but the evaluation has already run.

This is the same finding as the fd-nuclear-scram-sequencing P1 above (step reordering), but the fd-psm lens adds: `reconstructHalt()` should also be called during `ockham health` and `ockham resume` startup paths, not only in `runCheck()`. Any Ockham invocation that reads or acts on halt state should first ensure the halt state is internally consistent.

**Recommendation:** Extract `reconstructHalt()` into `halt.Sentinel.EnsureConsistent(interspectRecordPath)` and call it at the start of any Ockham command that reads halt state (check, health, resume). This gives the sentinel package ownership of its own consistency guarantee rather than relying on check.go's step ordering.

---

### [P2] BYPASS threshold lower bound of 2 must be enforced at config load, not as a convention

**Agent:** fd-psm-dual-confirmation
**Source discipline:** IEC 61511 Safety Instrumented Systems — safety function bounds must be validated at system initialization, not documented in a comment
**Description:**
Q1 in the brainstorm recommends making the BYPASS threshold configurable in `anomaly.Config` with a default of 2. The existing `Config` struct in `drift.go` (lines 10–19) has no bounds validation — callers receive the default from `DefaultConfig()` but if a config file overrides the threshold, no guard prevents `bypass_threshold: 1`. A threshold of 1 converts BYPASS from a multi-cause guard into a single-INFORM tripwire: the first INFORM signal on any theme triggers a full factory halt, making INFORM and BYPASS behaviorally identical.

The `Config` struct does not have a `BypassThreshold` field yet — this is new for F7. The field should be added with a validation function.

**Recommendation:** Add `BypassThreshold int` to `Config` with default 2. Add `func (c Config) Validate() error` that returns an error if `BypassThreshold < 2` (with message: "bypass_threshold must be >= 2; a value of 1 makes BYPASS equivalent to INFORM") or if `BypassThreshold > len(configured_themes)` (unreachable threshold). Call `Validate()` in `NewEvaluator()` and fail fast at evaluator construction time. This is one method addition and one call site.

---

### [P3] Resume command must display halt reason and fired themes before accepting `--confirm`

**Agent:** fd-nuclear-scram-sequencing
**Source discipline:** Nuclear reactor protection — restart-without-context is a distinct failure mode from restart-without-intent
**Description:**
The brainstorm recommends (Q4) requiring `--confirm` on `ockham resume`. The agent files note that `--confirm` alone is insufficient as the sole cognitive barrier: the operator must see the halt reason and active signal state before confirming, not just be asked "are you sure?" A principal who types `ockham resume --confirm` at 3am may not remember why the factory halted or whether the underlying condition has been resolved.

**Recommendation:** Before accepting `--confirm`, `ockham resume` prints:
```
Factory halted since 2026-04-06T03:14:00Z
Reason: BYPASS — 2 distinct root causes fired simultaneously
Fired themes: auth (drift 23%), perf (drift 31%)
Active INFORM signals: auth, perf
All domains will be reset to: supervised

Proceed? Pass --confirm to continue.
```
This is output-only behavior, zero state changes, and ensures the operator sees system state in context before confirming.
