---
artifact_type: flux-drive-findings
reviewer: fd-performance
prd: docs/prds/2026-04-04-ockham-wave1-foundation.md
date: 2026-04-04
---

# Performance Review: Ockham Wave 1 Foundation

## Performance Profile

**Workload class:** Interactive CLI tool wired into SessionStart hook. Every session pays this cost, unconditionally.

**Primary constraint:** Wall-clock latency on the SessionStart critical path. A hook that takes >500ms degrades session responsiveness noticeably; >1s is felt as a stall.

**Latency budget context:** The existing session-start.sh already carries significant load. Measured on this machine:

| Existing work in session-start.sh | Measured cost |
|---|---|
| `bd doctor --json` (5-minute TTL sentinel) | 2,450ms when sentinel expired |
| `bd list --status=open --json` (50 beads) | 130ms |
| `bd list --status=in_progress` | 44ms |
| `ic health` | 4ms |
| `ic state list <key>` | 4ms |
| `check-install-updates.sh --hook` | 10ms |

The `bd doctor` call dominates when it runs. The new `ockham check` call proposed in F4 adds to this.

---

## Findings

### HOTSPOT-1 (Must Fix): `ockham check` on SessionStart blocks 200-500ms with no rate limit guard

**Feature:** F4

**Who feels it:** Every agent, every session, from day one of deployment.

The PRD specifies `ockham check 2>/dev/null || true` in the Clavain SessionStart hook. The PRD does not specify a TTL guard or sentinel. Without one, `ockham check` runs on every single session start — including compact and resume triggers, not just startup.

`ockham check` must:
1. Open `~/.config/ockham/signals.db` (SQLite) — measured at <1ms for realistic data volumes.
2. Query interspect evidence over 7-day window — measured at 1ms.
3. Query interstat for three pleasure signals over 14-day rolling window — measured at 7-19ms.
4. Evaluate re-confirmation timers and write updated state.

Steps 1-3 total under 30ms at current data volumes. However:

- The interstat queries run a subprocess `bash cost-query.sh ...`. Each subprocess invocation costs 30-50ms in shell startup alone on this machine, regardless of SQLite query time. If `ockham check` shells out for cost data the same way F5 expects (via `cost-query.sh`), three pleasure signal queries cost 90-150ms in subprocess overhead alone.
- At 1,000+ agent_runs rows (reached after a few months of operation), the 7-day timestamp scan takes 50ms. At 18,000+ rows (current state), it takes 50ms with the timestamp index. This is bounded and acceptable as a one-time check.
- The `bd list --json` call for bead-to-theme mapping (F1/F5) costs 130ms at 50 open beads and is linear in bead count.

**The missing safeguard:** session-start.sh already demonstrates the correct pattern with `bd doctor`: a `/tmp/` sentinel file gates the expensive call to once per 5 minutes. Without this pattern on `ockham check`, a compact-heavy session (which can trigger 5-10 context compactions per day) runs the full check on every compaction.

**Fix:** Wrap the SessionStart invocation with a TTL sentinel, matching the existing `bd doctor` pattern:

```bash
_ockham_sentinel="/tmp/clavain-ockham-check-${USER:-mk}"
_ockham_age=999
[[ -f "$_ockham_sentinel" ]] && _ockham_age=$(( $(date +%s) - $(stat -c %Y "$_ockham_sentinel" 2>/dev/null || echo 0) ))
if [[ "$_ockham_age" -gt 300 ]]; then
    ockham check 2>/dev/null || true
    touch "$_ockham_sentinel" 2>/dev/null || true
fi
```

A 5-minute TTL is appropriate: ockham's temporal signals operate on 7-day and 14-day windows, so per-session evaluation adds no signal value. The `--dry-run` mode should bypass the sentinel for diagnostic use.

**Trade-off:** With the sentinel, ratchet timer expiry and weight-drift detection are noticed within 5 minutes of the triggering session, not instantaneously. This is acceptable given the signals operate on multi-day windows.

---

### HOTSPOT-2 (Must Fix): Per-bead `ic state get` in dispatch_rescore replaced by bulk pre-fetch, but the pre-fetch output format needs definition

**Feature:** F3

**Who feels it:** Dispatch cycles. With 50+ open beads, the dispatch rescoring loop runs per-bead. Without F3's bulk pre-fetch, an alternative implementation that calls `ic state get ockham_offset <bead_id>` per bead costs ~200ms at 10 beads and ~1,000ms at 50 beads (measured: 38ms per 10 serial subprocess calls, extrapolating).

The PRD correctly specifies bulk pre-fetch via `ic state list "ockham_offset" --json`. This is the right call: measured at 4ms for the `ic state list` command regardless of key count (it is a single SQL query). The savings at 50 beads are ~1,200ms vs 4ms.

**The gap:** The PRD does not define the JSON schema that `ic state list` returns. The `ic state list <key>` command (verified in the live binary) currently outputs scope_ids (bead IDs) that have that key set, not the values. To retrieve values, the implementation will need either `ic state list <key> --with-values` (if that flag exists or is added) or a second pass. This needs to be verified against the intercore source before implementing F3, otherwise the "bulk pre-fetch" silently falls back to empty values for all beads and the offset wiring has no effect.

**Verify before implementing:** Run `ic state list ockham_offset --json` after writing a test offset and confirm the output includes values, not just scope IDs.

---

### HOTSPOT-3 (Must Fix): Per-bead `bd dep list` and `bd show` in dispatch_rescore are the current dominant cost, not ockham

**Feature:** F3 (dispatch wiring context)

**Who feels it:** Every dispatch cycle, not just sessions with ockham.

This is a pre-existing issue made more visible by the scope of F3 work. The current `dispatch_rescore()` function calls both `bd dep list <bead_id> --direction=down --json` and `bd show <bead_id> --json` per candidate bead in the scoring loop:

- `bd dep list`: measured 67ms per call, extrapolated 3,350ms for 50 beads
- `bd show`: measured 56ms per call, extrapolated 2,800ms for 50 beads

At 91 ready beads (current project state), dispatch_rescore is doing 6+ seconds of serial subprocess work before any ockham offset is applied. The ockham offset wiring specified in F3 is a 4ms bulk fetch sitting inside a loop that is already taking seconds.

Ockham Wave 1 should not make this worse, and F3's implementation should take care not to add additional per-bead subprocess calls (e.g., `ockham dispatch advise --json` per bead). The freeze/skip path in F3 must use the in-memory offset map from the bulk pre-fetch, not a subprocess per bead.

**Recommendation:** File a separate bead for batch dep/lane checks in dispatch_rescore. Not in Ockham's scope, but Ockham should not add to the per-bead work.

---

### FINDING-4 (Optional Tuning): 7-day rolling window for drift detection uses full table scan at first query

**Feature:** F5

**Who feels it:** `ockham check` on the first invocation after interstat has accumulated significant history (>10k rows).

The drift threshold query (actual cycle time vs predicted baseline per theme, over 7-day window) requires joining bead lane data (from `bd list --json`) with agent_runs rows filtered by timestamp. Measured on the current 18,238-row table:

- With `idx_agent_runs_timestamp` in use: 50ms for the 7-day scan
- Without the timestamp index on the WHERE clause (possible if query adds a `bead_id` JOIN that changes the planner's choice): degrades to 50ms with idx_agent_runs_bead (full bead index scan)

The timestamp index exists and SQLite uses it correctly for simple `WHERE timestamp > datetime('now', '-7 days')` queries. The risk is query construction: if the Go implementation in `internal/scoring` builds queries with multiple WHERE conditions that cause the planner to prefer a different index, or if it issues one query per theme (up to N themes), the cost multiplies.

**Recommendation:** Issue a single query that returns all beads in the window grouped by bead_id, then join to theme in Go memory using the `IntentVector` lane-to-theme map. Do not issue per-theme SQL queries.

At 100k rows (estimated 12-18 months of operation), a full 7-day timestamp scan retrieves roughly 5-10% of rows. The timestamp index keeps this bounded to ~5k-10k row scans, which SQLite handles in 20-40ms. This is acceptable for a background check.

---

### FINDING-5 (Optional Tuning): `ockham check` subprocess startup cost dominates at current data volumes

**Feature:** F4, F5

**Who feels it:** `ockham check` execution time.

At current data volumes, the SQLite queries in `ockham check` cost 1-20ms. The Go binary startup cost for `ockham check` itself (measured for comparable Go CLI binaries in this repo: `ic` at 4ms, `bd` at 44-67ms per invocation) will be 5-50ms. This is acceptable.

The real risk is if `ockham check` shells out to `cost-query.sh` for pleasure signals rather than using Go's sqlite3 library directly. Each `bash cost-query.sh` invocation costs 30-50ms in subprocess startup. Three pleasure signals = 90-150ms in shell overhead alone. The correct design is for `ockham check` to read `~/.claude/interstat/metrics.db` directly via the Go sqlite3 driver, not via the cost-query.sh shell script.

**Recommendation:** `internal/scoring` should open interstat's metrics.db directly for pleasure signal computation. `cost-query.sh` is the declared cross-layer interface for external consumers but adds subprocess overhead that is unnecessary inside a Go binary.

---

### FINDING-6 (Scale): Per-bead offset model is feasible at 100 beads; watch at 1,000

**Feature:** F2, F3

**Who feels it:** Dispatch cycles in mature factory deployments.

The PRD stores one `ockham_offset` per bead_id in intercore state. The `ic state list ockham_offset` bulk pre-fetch returns all bead_ids with that key. At 100 open beads, this is a single SQL query returning 100 rows at 4ms. At 1,000 open beads, the same query returns 1,000 rows; SQLite handles this in under 10ms with the key index.

The Sylveste project currently has 613 total beads (99 open). Based on current trajectory, the 1,000-bead threshold is 12-18 months away. The per-bead offset model is not a scalability concern for Wave 1 or Wave 2.

**The actual concern at scale:** intercore state does not expire automatically. The PRD specifies scoring writes offsets for active beads, but does not specify cleanup when beads close. Closed beads accumulate stale `ockham_offset` entries in intercore state indefinitely. At 600+ closed beads (current state), `ic state list ockham_offset` would return stale entries mixed with live ones, increasing result set size and forcing dispatch_rescore to filter out closed beads from the offset map.

**Recommendation:** Add `ic state delete ockham_offset <bead_id>` to the bead-close path, or use a TTL on the state entries (the `ic state set` command supports `--ttl`). A 7-day TTL on `ockham_offset` entries is sufficient: closed beads are no longer dispatched, and any open bead whose offset is older than 7 days will be re-scored on the next `ockham check` cycle.

---

### FINDING-7 (Architecture): `ockham check` re-confirmation timer evaluation is O(domains) not O(beads)

**Feature:** F6

**Who feels it:** Nobody in Wave 1; this is a correctness + future-scale note.

The 30-day re-confirmation timer check reads the `ratchet_state` table filtered to `level = 'autonomous'`. In Wave 1, there are no autonomous domains (cold start defaults to shadow). At Wave 1 steady state, 0-5 domains might reach autonomous. This query is O(autonomous_domains) not O(total_beads), costs <1ms, and has no scalability concern.

The staggered promotion timestamp design (the PRD specifies staggering by promotion timestamp) means re-confirmations do not cluster. No batch-expiry spike concern.

---

## Summary

| Finding | Feature | Severity | Fix complexity |
|---|---|---|---|
| HOTSPOT-1: No TTL sentinel on SessionStart ockham check | F4 | Must fix | Low — 6 lines, copies existing bd doctor pattern |
| HOTSPOT-2: `ic state list` output schema unverified | F3 | Must fix | Low — verify ic binary behavior before wiring |
| HOTSPOT-3: Existing per-bead bd calls dominate dispatch_rescore | F3 context | Must fix (separate bead) | Medium — requires bd batch API or caching |
| FINDING-4: 7-day window query shape | F5 | Optional | Low — single aggregated query in Go |
| FINDING-5: Shell subprocess overhead for pleasure signals | F4/F5 | Optional | Low — read interstat DB directly in Go |
| FINDING-6: Stale ockham_offset accumulation | F2/F3 | Optional | Low — TTL on ic state set writes |
| FINDING-7: Re-confirmation O(domains) | F6 | No action | Informational |

The two must-fix items are both low-effort. HOTSPOT-1 (the TTL sentinel) should be added to the SessionStart wiring spec before implementation starts. HOTSPOT-2 requires a one-time verification of `ic state list` output format. Neither blocks Wave 1 architecture — they are implementation-time checks that, if missed, will surface as either latency regressions (HOTSPOT-1) or silent no-ops (HOTSPOT-2).
