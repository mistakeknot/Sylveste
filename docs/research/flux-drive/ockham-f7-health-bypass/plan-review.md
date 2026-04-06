# Plan Review: Ockham F7 — Health JSON + Tier 3 BYPASS + resume + INV-8 enforcement

**Reviewed:** 2026-04-06
**Plan:** `docs/plans/2026-04-06-ockham-f7-health-bypass.md`
**Verdict:** 12 findings (2 P0, 5 P1, 3 P2, 2 P3). The P0s must be fixed before implementation begins.

---

## P0 — Will not compile or silently breaks correctness

### Finding 1: Evaluator.Evaluate() calls `anomaly.ApplyFactoryGuard` with wrong signature

**Severity:** P0
**Task:** 2b.3 (BYPASS trigger in Evaluator.Evaluate)
**Description:** The plan's proposed code calls `anomaly.ApplyFactoryGuard(state.Signals, e.cfg)` passing the full `Config` struct, but the existing function signature is `ApplyFactoryGuard(sigs map[string]ThemeSignal, guard int)` — it takes an `int`, not a `Config`. The existing code in `evaluator.go:100` calls it correctly: `state.Signals = ApplyFactoryGuard(state.Signals, e.cfg.FactoryGuard)`.

**Fix:** In the plan's Task 2b.3 code, the call site should remain as it is in the existing code:
```go
state.Signals = ApplyFactoryGuard(state.Signals, e.cfg.FactoryGuard)
```
Additionally, the plan omits the assignment (`state.Signals = ...`). Without it, the guard result is discarded.

---

### Finding 2: PersistentPreRunE conflicts with existing `init()` + breaks dispatch subcommands

**Severity:** P0
**Task:** 1.3 (PersistentPreRunE allowlist on root command)
**Description:** Two issues:

1. **Subcommand matching is broken.** `cmd.CommandPath()` for `ockham dispatch advise` returns `"ockham dispatch advise"`. After `strings.TrimPrefix(name, "ockham ")`, the result is `"dispatch advise"`. This string is not in the allowlist, so `dispatch advise` (a mutating command that should be blocked when halted) would correctly be blocked. **However**, `dispatch` itself is also not in the allowlist, and neither is `check`. The `check` command is not in `haltAllowed`, which means `ockham check` would be blocked by the PersistentPreRunE when halted — but the *entire point* of Task 1.1 is to let `check` run when halted (it reconstructs the halt, snapshots authority, then short-circuits). This is a direct contradiction.

2. **The `check` command must be in haltAllowed.** The plan's Task 1.1 explicitly redesigns `runCheck()` to work correctly when halted (reconstruct, snapshot authority, skip evaluation). But Task 1.3's allowlist does not include `"check"`. When halted, `ockham check` would fail at the PersistentPreRunE before `runCheck()` is ever called.

**Fix:** Add `"check": true` to the `haltAllowed` map. Also add `"dispatch advise": true` if dispatch-advise should still report (with halt error from governor) rather than being pre-empted, or leave it out if the pre-emption is desired — but document the choice. Consider also whether `"signals"` alone matches or whether subcommand paths like `"signals"` need the full path. For `signals`, `CommandPath()` returns `"ockham signals"`, `TrimPrefix` yields `"signals"` which matches. This is correct.

---

## P1 — Compiles but produces incorrect behavior or test failures

### Finding 3: `RequireRunning()` needs `encoding/json` and `time` imports in halt package

**Severity:** P1
**Task:** 1.2 (halt.Sentinel.RequireRunning)
**Description:** The `halt.go` file currently imports only `"os"` and `"path/filepath"`. The proposed `RequireRunning()` calls `json.Unmarshal` and `time.Unix()`, requiring `"encoding/json"` and `"time"` to be added to the import block. The plan shows the function body but doesn't mention the import additions. If implemented by copy-paste, it won't compile.

**Fix:** Plan should explicitly note that `halt.go` imports must be extended to:
```go
import (
    "encoding/json"
    "fmt"
    "os"
    "path/filepath"
    "time"
)
```

---

### Finding 4: `triggerBypass()` needs imports not present in evaluator.go

**Severity:** P1
**Task:** 2b.4 (triggerBypass implementation)
**Description:** `evaluator.go` currently imports `"encoding/json"`, `"fmt"`, `"os"`, and `"github.com/mistakeknot/Ockham/internal/signals"`. The proposed `triggerBypass()` uses `json.Marshal`, `os.CreateTemp`, `os.Rename`, `os.Chmod`, `filepath.Dir`, `filepath.Join`, `strings.Join`, `os.Getenv`, and references `halt.DefaultSentinelPath()`. This requires adding:
- `"path/filepath"`
- `"strings"`
- `"github.com/mistakeknot/Ockham/internal/halt"`

The `halt` import creates a new dependency: `anomaly` -> `halt`. Currently `anomaly` only imports `signals`. This is not a cycle (halt doesn't import anomaly), but it changes the dependency graph and should be noted. The `governor` package already imports both, so this is architecturally fine but represents a new coupling.

**Fix:** Explicitly list all new imports. Note the `anomaly` -> `halt` dependency addition and confirm it doesn't violate any architectural constraint.

---

### Finding 5: `ReadOnly: true` in BeginTx is a no-op with modernc.org/sqlite

**Severity:** P1
**Task:** 2a.2 (health data collection)
**Description:** The plan calls `db.Conn().BeginTx(ctx, &sql.TxOptions{ReadOnly: true})`. The `modernc.org/sqlite` driver does not implement `ReadOnly` transaction options — it silently ignores the flag. The transaction will be a normal read-write transaction. This is not catastrophic (the health command only reads), but it's misleading documentation in the code. If a future developer relies on `ReadOnly` for correctness, it won't provide the expected protection.

**Fix:** Either:
- Remove `ReadOnly: true` and add a comment: `// NOTE: modernc.org/sqlite ignores ReadOnly — we rely on query-only access for safety`
- Or use `PRAGMA query_only = ON` within the transaction (modernc.org/sqlite does support this pragma)

---

### Finding 6: `BEGIN IMMEDIATE` not issued in resume — race with concurrent check

**Severity:** P1
**Task:** 3.2 (runResume ratchet_state reset)
**Description:** The plan says "BEGIN IMMEDIATE ratchet_state reset" in the comment, and mentions "Use raw PRAGMA for IMMEDIATE since Go sql may not support it", but the actual code calls `conn.BeginTx(context.Background(), nil)` — a plain `BEGIN` (deferred). `modernc.org/sqlite` does support `BEGIN IMMEDIATE` via `conn.Exec("BEGIN IMMEDIATE")` but **not** through the `database/sql` `BeginTx` API. The plan acknowledges this tension in a comment but doesn't resolve it.

A deferred `BEGIN` acquires a SHARED lock that upgrades to RESERVED on first write. If `ockham check` is concurrently reading the same DB, the upgrade could fail with SQLITE_BUSY (though `busy_timeout(5000)` mitigates this). The real risk: between `BEGIN` and the `UPDATE`, a concurrent `check` could read stale ratchet_state.

**Fix:** Use explicit transaction management:
```go
_, err = conn.Exec("BEGIN IMMEDIATE")
if err != nil {
    return fmt.Errorf("begin immediate: %w", err)
}
_, err = conn.Exec("UPDATE ratchet_state SET tier='supervised', demoted_at=? WHERE tier='autonomous'", time.Now().Unix())
if err != nil {
    conn.Exec("ROLLBACK")
    return fmt.Errorf("ratchet reset: %w", err)
}
_, err = conn.Exec("COMMIT")
```
This bypasses `database/sql` transaction management but gives the correct lock semantics.

---

### Finding 7: `haltGuard()` removal from intent.go leaves the function as dead code

**Severity:** P1
**Task:** 1.3
**Description:** Task 1.3 says "Remove the individual `haltGuard()` call from `runIntentSet()` (line 60)". This removes the call site but not the `haltGuard()` function definition at `intent.go:51-57`. The function becomes dead code. `go vet` won't flag it (unused exported-looking functions aren't caught), but it's confusing.

**Fix:** Also remove the `haltGuard()` function definition from `intent.go:51-57` since PersistentPreRunE now handles all halt enforcement.

---

## P2 — Suboptimal design or fragility

### Finding 8: Task ordering — Batch 1 tests may fail before Batch 2b completes

**Severity:** P2
**Task:** Batch ordering (1 vs 2b)
**Description:** Task 1.1 reorders `runCheck()` so that `evaluateSignals()` is skipped when halted. The existing `runCheck` tests (if any exist beyond the evaluator tests) would need updating. But more importantly, Task 2b.5 adds `errors.Is(err, anomaly.ErrBypassFailed)` to the signal evaluation error handling in `check.go`. This means `check.go` will import `"errors"` and reference `anomaly.ErrBypassFailed` — but `ErrBypassFailed` doesn't exist until Task 2b.2 is implemented.

If someone implements Batch 1 and tries to compile before Batch 2b, it will work fine (the error handling for bypass isn't added until 2b.5). The batching is correct as stated. However, if an implementer tries to add 2b.5 before 2b.2, it will fail to compile.

**Fix:** No change needed to batch ordering. Add a note that Task 2b.5 depends on 2b.2 (not just batch-level dependency).

---

### Finding 9: `snapshotRatchetState()` in resume.go — `ratchet_state` schema lacks `agent` column documentation

**Severity:** P2
**Task:** 3.2 (snapshotRatchetState)
**Description:** The `ratchet_state` schema in `db.go:32-38` has columns `(agent, domain, tier, promoted_at, demoted_at)`. The plan's `snapshotRatchetState()` queries `SELECT agent, domain, tier FROM ratchet_state WHERE tier='autonomous'` — this is correct and will work.

However, the `UPDATE` in Task 3.2 (`UPDATE ratchet_state SET tier='supervised', demoted_at=? WHERE tier='autonomous'`) only sets `tier` and `demoted_at`, not `promoted_at`. `promoted_at` retains its old value. This is correct (we want to know when it was originally promoted), but the plan should document this choice explicitly since `checkReconfirmation()` reads `promoted_at` to compute 30-day windows. After resume, `promoted_at` still reflects the old promotion time, so demoted+re-promoted domains would get correct fresh `promoted_at` only when re-promoted.

**Fix:** Add a comment in the plan: "promoted_at is intentionally preserved — re-promotion through the normal ratchet will set a fresh promoted_at."

---

### Finding 10: Health command `--json` defaults to `true` — no non-JSON path

**Severity:** P2
**Task:** 2a.1 (health command shell)
**Description:** The plan sets `healthJSON` default to `true`:
```go
healthCmd.Flags().BoolVar(&healthJSON, "json", true, "JSON output (default)")
```
But there is no `else` branch for non-JSON output. If someone passes `--json=false`, the command would need a human-readable formatter that doesn't exist. This differs from the existing `signals` command which has both JSON and tabwriter paths.

**Fix:** Either:
- Remove the `--json` flag entirely (always JSON, as the command name suggests machine-readable output)
- Or add a human-readable fallback path in the implementation spec

---

## P3 — Cosmetic or low-impact

### Finding 11: `nilConstrainChecker` type in resume.go is unexported but implements exported interface

**Severity:** P3
**Task:** 3.2 (ConstrainChecker stub)
**Description:** `ConstrainChecker` is an exported interface and `nilConstrainChecker` is unexported — this is fine Go style for internal implementation. But since both are in `package main`, the exported interface is not actually importable by other packages. The interface could be unexported too.

**Fix:** Make `ConstrainChecker` unexported: `constrainChecker`. Or leave as-is since it's package main.

---

### Finding 12: `reconstructHalt()` disagreement logging (Task 1.5) changes control flow

**Severity:** P3
**Task:** 1.5 (reconstructHalt disagreement logging)
**Description:** The plan says to add logging after `if record.Status != "active"`, but the proposed code changes the structure. Currently, `record.Status != "active"` hits a single `return nil`. The plan adds a nested check (`if record.Status == "resolved"`) that only fires for one specific non-active status. For other non-active statuses (e.g., an unknown status string), the behavior is unchanged. This is correct but the "after" phrasing is ambiguous — it should be "replace the `return nil`" or "add before the existing `return nil`".

**Fix:** Clarify in the plan that the code block replaces lines 311-312 (the bare `return nil`) with the conditional check followed by `return nil`.

---

## Summary Table

| # | Sev | Task | Issue |
|---|-----|------|-------|
| 1 | P0 | 2b.3 | `ApplyFactoryGuard` called with wrong type (`Config` vs `int`), result not assigned |
| 2 | P0 | 1.3 | `check` command missing from `haltAllowed` — blocks the core check-when-halted flow |
| 3 | P1 | 1.2 | Missing `encoding/json` and `time` imports in halt.go |
| 4 | P1 | 2b.4 | Missing `path/filepath`, `strings`, `halt` imports in evaluator.go; new dependency edge |
| 5 | P1 | 2a.2 | `ReadOnly: true` silently ignored by modernc.org/sqlite |
| 6 | P1 | 3.2 | `BEGIN IMMEDIATE` stated in comment but not actually issued; plain `BEGIN` used |
| 7 | P1 | 1.3 | `haltGuard()` function left as dead code after call site removal |
| 8 | P2 | Batch | Task 2b.5 depends on 2b.2 (intra-batch dependency not documented) |
| 9 | P2 | 3.2 | `promoted_at` preservation after demotion is intentional but undocumented |
| 10 | P2 | 2a.1 | `--json` defaults true with no non-JSON output path |
| 11 | P3 | 3.2 | Exported `ConstrainChecker` in package main is un-importable |
| 12 | P3 | 1.5 | Ambiguous "add after" phrasing for control flow change |

---

## Import Cycle Analysis

No import cycles are introduced:

```
halt        -> os, path/filepath, encoding/json, time, fmt (NEW: json, time, fmt)
anomaly     -> signals, halt (NEW: halt), encoding/json, fmt, os, path/filepath, strings (NEW: path/filepath, strings)
governor    -> anomaly, authority, halt, intent, scoring (unchanged)
cmd/ockham  -> anomaly, halt, signals, intent, governor (unchanged)
```

The new `anomaly -> halt` edge does not create a cycle. No package in the `halt` chain imports `anomaly`.

## Test Isolation Analysis

- `t.TempDir()` usage is consistent across all existing tests and proposed new tests — no shared state risks.
- BYPASS trigger tests need temp sentinel paths (not `DefaultSentinelPath()` which touches `~/.config/`) — the plan should ensure `triggerBypass()` accepts a sentinel path parameter or uses DI, rather than hardcoding `halt.DefaultSentinelPath()`. Currently the plan hardcodes it, which means BYPASS tests will write to `~/.config/ockham/factory-paused.json` on the test runner.
  - **This is a P1-adjacent concern**: Task 2b.4 hardcodes `sentinelPath := halt.DefaultSentinelPath()` inside `triggerBypass()`. Tests cannot override this. Either the Evaluator needs a sentinel path field, or `triggerBypass` needs a path parameter.
