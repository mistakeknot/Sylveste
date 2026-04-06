---
artifact_type: plan
bead: sylveste-fzt
prd: docs/prds/2026-04-06-ockham-f7-health-bypass.md
stage: planned
---
# Plan: Ockham F7 — Health JSON + Tier 3 BYPASS

## Dependency Order

F4 (INV-8 + reorder) must ship first — it fixes the runCheck() step order and adds the allowlist halt guard that F2 (BYPASS trigger) and F3 (resume) depend on. F1 (health) and F2 can be parallel after F4. F3 depends on F2 (needs the halt record format).

```
Batch 1: F4 (INV-8 enforcement + runCheck reorder)
Batch 2: F1 (health JSON) + F2 (BYPASS trigger) — parallel
Batch 3: F3 (ockham resume)
```

---

## Batch 1: F4 — INV-8 enforcement + runCheck reorder (sylveste-ipsk)

### Task 1.1: Reorder runCheck() steps
**File:** `cmd/ockham/check.go:38-80`
**Change:** Swap step order in `runCheck()`:
```go
func runCheck(cmd *cobra.Command, args []string) error {
    // ... db setup unchanged ...

    runner := &CheckRunner{db: db, haltPath: halt.DefaultSentinelPath(), dryRun: checkDryRun}

    // Step 1: Reconstruct halt sentinel from interspect if needed (FIRST)
    if err := runner.reconstructHalt(); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: halt reconstruction degraded: %v\n", err)
    }

    // Step 2: Check halt — if halted, only snapshot authority then return
    halted := halt.New(runner.haltPath).IsHalted()

    // Step 3: Snapshot authority (always — read-only capture of external state)
    if err := runner.snapshotAuthority(); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: authority snapshot degraded: %v\n", err)
    }

    if halted {
        if !checkDryRun {
            fmt.Println("ockham check: factory halted — skipping signal evaluation and reconfirmation")
        }
        return nil
    }

    // Step 4: Evaluate signals (only when not halted)
    if err := runner.evaluateSignals(); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: signal evaluation degraded: %v\n", err)
    }

    // Step 5: Reconfirmation timers (only when not halted)
    if err := runner.checkReconfirmation(); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: reconfirmation check degraded: %v\n", err)
    }

    // ... dry-run message unchanged ...
    return nil
}
```
**Tests:** Update existing `runCheck` tests to verify: (a) reconstructHalt runs first, (b) evaluateSignals skipped when halted, (c) checkReconfirmation skipped when halted.

### Task 1.2: Add halt.Sentinel.RequireRunning() helper
**File:** `internal/halt/halt.go`
**Add:**
```go
// RequireRunning returns an error if the factory is halted.
// Reads factory-paused.json for context (reason, timestamp).
func (s *Sentinel) RequireRunning() error {
    if !s.IsHalted() {
        return nil
    }
    // Read halt record for context
    data, err := os.ReadFile(s.path)
    if err != nil {
        return fmt.Errorf("factory halted: %s exists — run 'ockham resume --confirm' first", s.path)
    }
    var record struct {
        Reason    string `json:"reason"`
        Timestamp int64  `json:"timestamp"`
    }
    if json.Unmarshal(data, &record) != nil || record.Reason == "" {
        return fmt.Errorf("factory halted: %s exists — run 'ockham resume --confirm' first", s.path)
    }
    t := time.Unix(record.Timestamp, 0).Format(time.RFC3339)
    return fmt.Errorf("factory halted since %s (reason: %s) — run 'ockham resume --confirm' first", t, record.Reason)
}
```
**Tests:** 3 tests: not halted returns nil, halted with valid JSON returns context, halted with invalid JSON returns fallback message.

### Task 1.3: Add PersistentPreRunE allowlist on root command
**File:** `cmd/ockham/root.go`
**Change:** Add halt-guard allowlist:
```go
// haltAllowed lists commands that may run when factory is halted.
// check MUST be here — Task 1.1 redesigns runCheck() to work when halted.
var haltAllowed = map[string]bool{
    "check": true, "health": true, "signals": true, "resume": true,
    "intent show": true, "intent validate": true,
    "help": true, "version": true,
}

func init() {
    rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
        name := cmd.CommandPath()          // e.g., "ockham intent show"
        name = strings.TrimPrefix(name, "ockham ")
        if haltAllowed[name] {
            return nil
        }
        h := halt.New(halt.DefaultSentinelPath())
        return h.RequireRunning()
    }
}
```
Remove the individual `haltGuard()` call from `runIntentSet()` (line 60) AND the `haltGuard()` function definition (intent.go:51-57) — the PersistentPreRunE now handles all halt enforcement.
**Tests:** Test that `intent set --theme=x` fails when halted, `intent show` succeeds when halted, `check` succeeds when halted.

### Task 1.4: fsync fix in reconstructHalt()
**File:** `cmd/ockham/check.go:333-342`
**Change:** Add `f.Sync()` before close:
```go
_, err = f.Write(sentinel)
if err != nil {
    return err
}
if err := f.Sync(); err != nil {
    return err
}
return f.Close()
```
**Tests:** Existing reconstructHalt tests still pass (functional behavior unchanged).

### Task 1.5: reconstructHalt() disagreement logging
**File:** `cmd/ockham/check.go:310-313`
**Change:** After `if record.Status != "active"`, add:
```go
if record.Status == "resolved" {
    // Check if file still exists (resume may have been interrupted)
    if _, err := os.Stat(r.haltPath); err == nil {
        fmt.Fprintf(os.Stderr, "ockham: halt-record.json resolved but %s still present — resume may have been interrupted; run 'ockham resume --confirm'\n", r.haltPath)
    }
}
return nil
```
**Tests:** 1 test: interspect resolved + file present → logs advisory.

---

## Batch 2a: F1 — Health JSON command (sylveste-9pj1)

### Task 2a.1: Add health command shell
**File:** `cmd/ockham/health.go` (new)
**Create:** New cobra command `health` with `--json` flag. Opens signals.DB, reads all state in a read transaction, marshals to JSON, prints.
```go
var healthJSON bool

var healthCmd = &cobra.Command{
    Use:   "health",
    Short: "Display factory health state (machine-readable)",
    RunE:  runHealth,
}

func init() {
    // health is always JSON — no --json flag needed. Machine-readable by design.
    rootCmd.AddCommand(healthCmd)
}
```

### Task 2a.2: Implement health data collection
**File:** `cmd/ockham/health.go`
**Logic:**
1. Open signals.DB (read-only)
2. Begin read transaction: `tx, err := db.Conn().BeginTx(ctx, nil)` (NOTE: modernc.org/sqlite ignores ReadOnly; we rely on query-only access)
3. Read halt state from `halt.Sentinel` + `factory-paused.json` content
4. Query `signal_state` for all `inform:*` keys → parse JSON → build signals map
5. Query `signal_state` for all `pleasure:*` keys → parse JSON → build pleasure map
6. Query `SELECT MAX(updated_at) FROM signal_state` → `last_check`
7. Query `SELECT DISTINCT theme FROM bead_metrics` → themes list
8. Commit transaction
9. Build health struct, marshal JSON, print

**Health struct:**
```go
type HealthOutput struct {
    Halted        bool                       `json:"halted"`
    HaltReason    *HaltReasonOutput          `json:"halt_reason"`
    Signals       map[string]SignalOutput     `json:"signals"`
    Pleasure      map[string]PleasureOutput   `json:"pleasure"`
    Themes        []string                   `json:"themes"`
    LastCheck     int64                      `json:"last_check"`
    SchemaVersion int                        `json:"schema_version"`
}

type HaltReasonOutput struct {
    Code         string   `json:"code"`
    FiredThemes  []string `json:"fired_themes"`
    FiredAt      int64    `json:"fired_at"`
}

type SignalOutput struct {
    Status           string  `json:"status"`
    DriftPct         float64 `json:"drift_pct"`
    AdvisoryOffset   int     `json:"advisory_offset"`
    AtAdvisoryFloor  bool    `json:"at_advisory_floor"`
    ConsecutiveClears int    `json:"consecutive_clears"`
}

type PleasureOutput struct {
    Trend string  `json:"trend"`
    Value float64 `json:"value"`
}
```
**Tests:** 5 tests: empty DB, halted state, fired signals, pleasure trends, exit code always 0.

---

## Batch 2b: F2 — Tier 3 BYPASS trigger (sylveste-d5cw)

### Task 2b.1: Add BypassThreshold to Config + Validate
**File:** `internal/anomaly/drift.go`
**Change:** Add field to `Config`:
```go
type Config struct {
    // ... existing fields ...
    BypassThreshold int // minimum distinct fired themes to trigger BYPASS (default 2, min 2)
}

func DefaultConfig() Config {
    return Config{
        // ... existing defaults ...
        BypassThreshold: 2,
    }
}

func (c Config) Validate() error {
    if c.BypassThreshold < 2 {
        return fmt.Errorf("bypass_threshold must be >= 2: values below 2 cause immediate halt on any INFORM signal")
    }
    return nil
}
```
**Tests:** 2 tests: valid config, threshold < 2 returns error.

### Task 2b.2: Add ErrBypassFailed typed error
**File:** `internal/anomaly/anomaly.go`
**Add:**
```go
import "errors"

// ErrBypassFailed indicates the BYPASS trigger detected an emergency condition
// but failed to write the sentinel file. This is a safety-critical error that
// must NOT be swallowed by degraded-continue patterns.
var ErrBypassFailed = errors.New("BYPASS trigger failed: sentinel write unsuccessful")
```

### Task 2b.3: Implement BYPASS trigger in Evaluator.Evaluate()
**File:** `internal/anomaly/evaluator.go`
**Change:** After the theme evaluation loop, count fired themes. If >= threshold, trigger BYPASS.
```go
func (e *Evaluator) Evaluate(themes []string, now int64) (State, error) {
    if err := e.cfg.Validate(); err != nil {
        return State{}, err
    }
    // ... existing theme evaluation loop ...

    // After factory guard (existing code — correct signature):
    state.Signals = ApplyFactoryGuard(state.Signals, e.cfg.FactoryGuard)

    // BYPASS trigger: count distinct fired themes
    firedThemes := make([]string, 0)
    for theme, sig := range state.Signals {
        if sig.Status == StatusFired {
            firedThemes = append(firedThemes, theme)
        }
    }
    if len(firedThemes) >= e.cfg.BypassThreshold {
        if err := e.triggerBypass(firedThemes, state, now); err != nil {
            return state, fmt.Errorf("%w: %v", ErrBypassFailed, err)
        }
    }

    return state, nil
}
```

### Task 2b.4: Implement triggerBypass() with atomic durable write
**File:** `internal/anomaly/evaluator.go`
**Add:**
```go
// NOTE: Evaluator gains a sentinelPath field set by NewEvaluator() for testability.
// NewEvaluator(db, cfg) → NewEvaluator(db, cfg, sentinelPath string)
func (e *Evaluator) triggerBypass(firedThemes []string, state State, now int64) error {
    sentinelPath := e.sentinelPath // set via NewEvaluator; tests pass t.TempDir() path

    // Build structured halt record
    record := map[string]any{
        "reason":           "BYPASS",
        "code":             "bypass_multi_root_cause",
        "triggered_themes": firedThemes,
        "signal_values":    state.Signals,
        "timestamp":        now,
        "schema_version":   1,
    }
    data, err := json.Marshal(record)
    if err != nil {
        return err
    }

    // Step 1: Atomic durable sentinel write (temp + fsync + rename)
    dir := filepath.Dir(sentinelPath)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return err
    }
    tmp, err := os.CreateTemp(dir, ".factory-paused-*.json")
    if err != nil {
        return err
    }
    tmpPath := tmp.Name()
    defer os.Remove(tmpPath) // cleanup temp on any failure path

    if _, err := tmp.Write(data); err != nil {
        tmp.Close()
        return err
    }
    if err := tmp.Sync(); err != nil {
        tmp.Close()
        return err
    }
    if err := tmp.Close(); err != nil {
        return err
    }
    if err := os.Chmod(tmpPath, 0400); err != nil {
        return err
    }
    // Atomic rename — if sentinel already exists (concurrent BYPASS), this overwrites
    // which is acceptable (halt is already active with same or similar reason)
    if err := os.Rename(tmpPath, sentinelPath); err != nil {
        return err
    }

    // Step 2: Write interspect halt record (soft failure — never roll back sentinel)
    interspectPath := filepath.Join(os.Getenv("HOME"), ".clavain", "interspect", "halt-record.json")
    interspectRecord := map[string]any{
        "event_id":  fmt.Sprintf("bypass-%d", now),
        "timestamp": now,
        "reason":    fmt.Sprintf("BYPASS: %d distinct root causes fired: %s", len(firedThemes), strings.Join(firedThemes, ", ")),
        "status":    "active",
        "triggered_themes": firedThemes,
    }
    irData, _ := json.Marshal(interspectRecord)
    if err := os.MkdirAll(filepath.Dir(interspectPath), 0755); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: interspect halt record degraded (mkdir): %v\n", err)
    } else if err := os.WriteFile(interspectPath, irData, 0644); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: interspect halt record degraded (write): %v\n", err)
    }

    fmt.Fprintf(os.Stderr, "ockham: BYPASS triggered — %d distinct root causes: %s\n",
        len(firedThemes), strings.Join(firedThemes, ", "))
    return nil
}
```
**Tests:** 6 tests: below threshold no trigger, at threshold triggers, sentinel written with fsync, interspect failure doesn't fail trigger, concurrent trigger (file exists), ErrBypassFailed typed error propagation.

### Task 2b.5: Propagate ErrBypassFailed through check.go
**File:** `cmd/ockham/check.go:61-62`
**Change:** In `runCheck()`, after the signal evaluation step (which now only runs when not halted per Task 1.1):
```go
if err := runner.evaluateSignals(); err != nil {
    if errors.Is(err, anomaly.ErrBypassFailed) {
        return err // safety-critical: exit non-zero
    }
    fmt.Fprintf(os.Stderr, "ockham: signal evaluation degraded: %v\n", err)
}
```
**Tests:** 1 test: ErrBypassFailed propagates to exit non-zero.

### Task 2b.6: Document single-lane-per-bead invariant
**File:** `cmd/ockham/check.go:174-227`
**Change:** Add comment at top of `closedBeadsFromBD()`:
```go
// closedBeadsFromBD shells out to bd to get recently closed beads with metrics.
// INVARIANT: Each bead maps to exactly one lane (first lane: label found).
// This ensures bead populations are disjoint per-theme, which is required
// for BYPASS root-cause deduplication (distinct_root_causes >= 2 means
// distinct theme names, which is a valid proxy for causal independence
// ONLY when bead populations are disjoint). If multi-lane beads are
// introduced, BYPASS deduplication must be re-evaluated.
```
No functional change — documentation only.

---

## Batch 3: F3 — ockham resume command (sylveste-lc8x)

### Task 3.1: Add resume command shell
**File:** `cmd/ockham/resume.go` (new)
**Create:**
```go
var resumeConfirm bool
var resumeConstrained bool
var resumeJSON bool

var resumeCmd = &cobra.Command{
    Use:   "resume",
    Short: "Resume factory after BYPASS halt",
    RunE:  runResume,
}

func init() {
    resumeCmd.Flags().BoolVar(&resumeConfirm, "confirm", false, "Confirm resume (required)")
    resumeCmd.Flags().BoolVar(&resumeConstrained, "constrained", false, "Resume with frozen themes still frozen (Tier 2)")
    resumeCmd.Flags().BoolVar(&resumeJSON, "json", false, "JSON output")
    rootCmd.AddCommand(resumeCmd)
}
```

### Task 3.2: Implement runResume()
**File:** `cmd/ockham/resume.go`
**Logic:**
```go
func runResume(cmd *cobra.Command, args []string) error {
    h := halt.New(halt.DefaultSentinelPath())

    // 1. Precondition: factory must be halted
    if !h.IsHalted() {
        return fmt.Errorf("factory is not halted — nothing to resume")
    }

    // 2. Read halt context for display
    haltData, _ := os.ReadFile(h.Path())
    var haltRecord struct {
        Reason         string   `json:"reason"`
        Code           string   `json:"code"`
        TriggeredThemes []string `json:"triggered_themes"`
        Timestamp      int64    `json:"timestamp"`
    }
    _ = json.Unmarshal(haltData, &haltRecord)

    // 3. Without --confirm: show preview and exit
    if !resumeConfirm {
        fmt.Fprintf(os.Stderr, "Factory halted since %s\n", time.Unix(haltRecord.Timestamp, 0).Format(time.RFC3339))
        fmt.Fprintf(os.Stderr, "Reason: %s\n", haltRecord.Reason)
        if len(haltRecord.TriggeredThemes) > 0 {
            fmt.Fprintf(os.Stderr, "Fired themes: %s\n", strings.Join(haltRecord.TriggeredThemes, ", "))
        }
        // Count domains that would be reset
        db, err := signals.NewDB(signals.DefaultDBPath())
        if err == nil {
            defer db.Close()
            var count int
            db.Conn().QueryRow("SELECT COUNT(*) FROM ratchet_state WHERE tier='autonomous'").Scan(&count)
            fmt.Fprintf(os.Stderr, "Domains to reset: %d autonomous → supervised\n", count)
        }
        fmt.Fprintf(os.Stderr, "\nRun: ockham resume --confirm\n")
        return fmt.Errorf("resume requires --confirm")
    }

    // 4. Open signals.db
    db, err := signals.NewDB(signals.DefaultDBPath())
    if err != nil {
        return fmt.Errorf("signals.db: %w", err)
    }
    defer db.Close()

    // 5. Dual-sentinel consistency check
    interspectPath := filepath.Join(os.Getenv("HOME"), ".clavain", "interspect", "halt-record.json")
    irData, irErr := os.ReadFile(interspectPath)
    if irErr != nil {
        fmt.Fprintf(os.Stderr, "ockham: warning — factory-paused.json exists but no interspect halt record (possible partial-write during BYPASS trigger)\n")
    } else {
        var ir struct{ Status string `json:"status"` }
        if json.Unmarshal(irData, &ir) == nil && ir.Status != "active" {
            fmt.Fprintf(os.Stderr, "ockham: warning — interspect halt record status=%q (expected 'active') — possible interrupted resume\n", ir.Status)
        }
    }

    // 6. Snapshot pre-halt ratchet_state for forensics
    preHaltSnapshot := snapshotRatchetState(db)

    // 7. Clear interspect halt record
    resolvedRecord := map[string]any{
        "status":    "resolved",
        "resolved_at": time.Now().Unix(),
        "pre_halt_authority": preHaltSnapshot,
    }
    if rd, err := json.Marshal(resolvedRecord); err == nil {
        _ = os.WriteFile(interspectPath, rd, 0644)
    }

    // 8. BEGIN IMMEDIATE ratchet_state reset
    // modernc.org/sqlite does not support IMMEDIATE via BeginTx — use raw SQL
    conn := db.Conn()
    if _, err := conn.Exec("BEGIN IMMEDIATE"); err != nil {
        return fmt.Errorf("begin immediate: %w", err)
    }
    _, err = conn.Exec("UPDATE ratchet_state SET tier='supervised', demoted_at=? WHERE tier='autonomous'", time.Now().Unix())
    if err != nil {
        conn.Exec("ROLLBACK")
        return fmt.Errorf("ratchet reset: %w", err)
    }
    if _, err := conn.Exec("COMMIT"); err != nil {
        return fmt.Errorf("commit: %w", err)
    }

    // 9. WAL checkpoint
    _, _ = conn.Exec("PRAGMA wal_checkpoint(FULL)")

    // 10. Delete sentinel — NEVER deferred, explicit after commit+checkpoint
    if err := os.Chmod(h.Path(), 0600); err != nil {
        fmt.Fprintf(os.Stderr, "ockham: chmod sentinel: %v\n", err)
    }
    if err := os.Remove(h.Path()); err != nil {
        return fmt.Errorf("remove sentinel: %w (factory may still appear halted)", err)
    }

    // 11. Constrain checker stub
    // When Tier 2 ships (F6), this becomes real
    checker := nilConstrainChecker{}
    constraints, _ := checker.ActiveConstraints()
    if len(constraints) > 0 && !resumeConstrained {
        fmt.Fprintf(os.Stderr, "ockham: active constraints: %s — consider --constrained\n", strings.Join(constraints, ", "))
    }

    // 12. Output summary
    resetCount := len(preHaltSnapshot)
    // ... print or json output ...
    return nil
}

// ConstrainChecker checks for active Tier 2 CONSTRAIN signals.
type ConstrainChecker interface {
    ActiveConstraints() ([]string, error)
}

type nilConstrainChecker struct{}
func (nilConstrainChecker) ActiveConstraints() ([]string, error) { return nil, nil }

func snapshotRatchetState(db *signals.DB) []map[string]string {
    rows, err := db.Conn().Query("SELECT agent, domain, tier FROM ratchet_state WHERE tier='autonomous'")
    if err != nil { return nil }
    defer rows.Close()
    var snap []map[string]string
    for rows.Next() {
        var a, d, t string
        rows.Scan(&a, &d, &t)
        snap = append(snap, map[string]string{"agent": a, "domain": d, "tier": t})
    }
    return snap
}
```
**Tests:** 8 tests: not halted error, without --confirm shows preview, --confirm succeeds, sentinel deleted after commit, idempotent resume (interspect already resolved), ratchet_state reset, pre-halt snapshot captured, ConstrainChecker stub returns empty.

---

## Test Summary

| Batch | Package | New Tests | Estimated |
|-------|---------|-----------|-----------|
| 1 | halt, cmd/ockham | 8 | runCheck reorder (3), RequireRunning (3), PersistentPreRunE (2) |
| 2a | cmd/ockham | 5 | health output variants |
| 2b | anomaly, cmd/ockham | 9 | Config.Validate (2), BYPASS trigger (6), error propagation (1) |
| 3 | cmd/ockham | 8 | resume variants |
| **Total** | | **~30** | |

All tests use `t.TempDir()` for isolation. BYPASS trigger tests create temp sentinel paths. Resume tests create temp DB + sentinel.

## Files Changed

| File | Change Type | Batch |
|------|------------|-------|
| `internal/halt/halt.go` | Modified (RequireRunning) | 1 |
| `internal/halt/halt_test.go` | Modified (+3 tests) | 1 |
| `cmd/ockham/root.go` | Modified (PersistentPreRunE) | 1 |
| `cmd/ockham/check.go` | Modified (reorder, fsync, disagreement log, ErrBypass propagation) | 1, 2b |
| `internal/anomaly/anomaly.go` | Modified (ErrBypassFailed) | 2b |
| `internal/anomaly/drift.go` | Modified (BypassThreshold, Validate) | 2b |
| `internal/anomaly/drift_test.go` | Modified (+2 tests) | 2b |
| `internal/anomaly/evaluator.go` | Modified (BYPASS trigger, triggerBypass) | 2b |
| `internal/anomaly/evaluator_test.go` | Modified (+6 tests) | 2b |
| `cmd/ockham/health.go` | **New** | 2a |
| `cmd/ockham/health_test.go` | **New** | 2a |
| `cmd/ockham/resume.go` | **New** | 3 |
| `cmd/ockham/resume_test.go` | **New** | 3 |
| **Total** | 13 files (2 new, 11 modified) | |
