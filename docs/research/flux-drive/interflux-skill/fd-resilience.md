### Findings Index
- P1 | R1 | "phases/launch.md Step 2.3 monitoring + Step 2.0.5 routing" | Graceful degradation paths are documented per-component but not system-wide — if 3+ progressive enhancements fail simultaneously, cumulative effect is not covered
- P1 | R2 | "phases/launch-codex.md" | Codex dispatch is single-path — no fallback when Codex fails mid-review; "fall back to Task dispatch" is per-agent but not for the orchestrator itself
- P1 | R3 | "phases/synthesize.md Silent Compounding" | Compounding failure is "silently swallow" — best-effort infrastructure with no retry, no dead-letter queue, no health metric
- P2 | R4 | "phases/launch.md Step 2.3 retry policy" | Single retry with tier downgrade; no backoff; no circuit breaker for systemic classifier refusals
- P2 | R5 | "SKILL.md + SKILL-compact.md resource allocation" | Same capability implemented twice; maintenance cost doubles without resilience benefit (it's not a fallback, it's a fork)
- P2 | R6 | "phases/launch.md + phases/expansion.md max_speculative=2" | Cap of 2 speculative expansions is not justified — could be a creative constraint, but no data tested whether 1 or 3 would be better
- P2 | R7 | "phases/reaction.md reaction round fail paths" | "If estimated_reaction_cost == 0: skip to Phase 3" — an edge case skipping reaction entirely has no metric; systematic skips invisible
- P2 | R8 | "phases/synthesize.md Step 3.4c interstat updates" | `2>/dev/null || true` swallows all interstat write errors — can accumulate missed records indefinitely with no alarm
Verdict: needs-changes

### Summary

The skill is well-designed for single-component failure: progressive enhancements skip silently, retries are bounded, fail-open defaults are explicit. What's missing is systemic resilience — the ability to notice that multiple small failures are cumulating, or that a graceful degradation has become the normal path. Compounding, knowledge decay, interstat writes, and reaction rounds all have fail-open paths with no metric on how often they fail. A flux-drive run can "succeed" while silently skipping 4 of its 7 features, and neither the user nor the maintainer has visibility. The skill has excellent creative constraints (budget caps, slot ceilings, token budgets) — these force good behavior — but it lacks the complementary mechanism: explicit monitoring that the constraints are binding correctly.

### Issues Found

1. R1. P1: Degradation paths are local, not system-wide. The skill lists graceful degradation per subsystem: qmd unavailable → skip knowledge context; lib-routing.sh missing → frontmatter defaults; interstat empty → default cost estimates; flux-watch.sh gone → 5s polling; intercept absent → fail-open. Each is sensible. But a system where 3+ degrade at once is degraded enough that the user should be warned — the review has lost triage tuning + routing + cost estimation + filesystem efficiency + reaction gating. Fix: track degradation as a count; if >= 3 progressive enhancements are unavailable, display a degradation banner in the Phase 3 report. Pipe failures should aggregate, not silently compose.

2. R2. P1: Codex dispatch is a single-path mode. `phases/launch-codex.md` L17-18: "If either path resolution fails, fall back to Task dispatch for this run." That fallback is for the initial path-resolution check. Once dispatch starts, if Codex begins failing (network error, dispatch.sh exit code, etc.), the L111-115 error handling is per-agent: retry once, fall back to Task for that agent. But the orchestrator doesn't have a circuit breaker — if 4 of 6 agents fail Codex dispatch, the orchestrator keeps trying Codex for the remaining 2. A better pattern: after 2 Codex failures, give up on Codex entirely and route the rest through Task. Fix: track Codex success rate per run; if rate drops below 0.5, switch the whole run to Task.

3. R3. P1: Compounding has no dead-letter queue. `phases/synthesize.md` Silent Compounding: "If compounding fails for any reason, the review is still complete — this is best-effort infrastructure. Log the error internally for debugging." The error log destination isn't specified. Repeated compounding failures (e.g., a disk-full condition or a broken sanitizer) are invisible until a user inspects the knowledge directory and notices no new entries. Fix: a `compounding-failures.jsonl` in the plugin state directory, read by a weekly health check.

4. R4. P2: Retry policy lacks backoff and circuit breaker. Step 2.3 retry: "For `.md.partial` only (incomplete): retry once with `run_in_background: false`, timeout 300000ms." No backoff — if the original failed due to an overloaded API, the immediate retry lands in the same overload. No circuit breaker — if 4 of 6 agents fail, all 4 get retried simultaneously, amplifying the overload. Fix: add a small random jitter (30-120s) between retry launches, and skip retry entirely when failure rate in this run exceeds 0.5.

5. R5. P2: Dual implementation, no creative constraint benefit. SKILL.md + SKILL-compact.md are the same capability with different verbosity. Maintaining both doubles the surface area for drift. A true fallback would be: if Claude's context is constrained, the orchestrator automatically loads less detail. Instead, both exist unconditionally. Fix: use a single SKILL.md with progressive disclosure (headings + "read more in phases/..."), eliminating the compact variant. See fd-architecture A1 for detailed case.

6. R6. P2: max_speculative=2 is an assumption lock. `phases/expansion.md` Step 2.2a.6: "Cap: Maximum 2 speculative launches during Stage 1." No data is cited. Could 1 be enough? Could 3 improve recall? The cap is a creative constraint that might drive efficiency or might be throwing away useful expansion. Fix: add a calibration script that sweeps the value against historical runs and reports recall/precision trade-offs. Document the rationale once settled.

7. R7. P2: Silent reaction-round skip has no metric. `phases/reaction.md` Step 2.5.3a: "If `estimated_reaction_cost == 0` (all agents dropped or no pool): skip to Phase 3." The reaction round is skipped with no log entry beyond the line-level "[reaction-budget] Dropped" messages. A project where the reaction round is always skipping (due to budget pressure on every run) loses a feature silently. Fix: emit a `reaction-skipped` event (the code already has `_interspect_emit_reaction_dispatched` — add a parallel `reaction-skipped` with a reason field).

8. R8. P2: interstat writes swallow errors. `phases/synthesize.md` Step 3.4c sqlite3 command: `2>/dev/null || true`. That pattern is consistent across the file. interstat's agent_runs table is what feeds cost estimation (Step 1.2c.2) and trust scoring (Step 2.1e) next run. A sustained write failure means future triage decisions use stale or missing data. Fix: log interstat write errors to a single `{OUTPUT_DIR}/interstat-errors.log`; if the file has >0 entries at end of run, mention in Phase 3 report.

### Improvements

1. IMP-1. Health dashboard. A `/interflux:flux-drive-health` command that reads the last 10 runs and reports: reaction-round skip rate, compounding success rate, progressive enhancement availability rate, retry rate, Codex vs Task dispatch split, budget overrun rate. Reveals cumulative degradation that single-run visibility misses.

2. IMP-2. Anti-fragility: convert some fail-open paths to fail-loud. Specifically: interstat write failure, sanitizer error, Oracle timeout with no partial output. Silent failures are brittle; loud failures with clear remediation paths make the system stronger when maintainers fix them.

3. IMP-3. Creative constraint: deliberate chaos. One in N runs, disable a random progressive enhancement and measure the effect on findings. Builds institutional knowledge about which enhancements matter.

4. IMP-4. MVP for expansion calibration: before adding a new expansion rule (e.g., "incremental expansion"), run a 20-review A/B with the rule off vs on. The current expansion rules accumulated without such a test.

5. IMP-5. Define "phoenix moment" explicitly: when a review returns zero findings and the dispatcher detects unusual conditions (budget exceeded, multiple retries, degradation banner), escalate to a human-gated full-scan. Don't optimize on the degraded happy path.

<!-- flux-drive:complete -->
