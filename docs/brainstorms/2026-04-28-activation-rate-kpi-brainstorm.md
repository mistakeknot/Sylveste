---
artifact_type: brainstorm
bead: sylveste-8r5h
stage: discover
date: 2026-04-28
---

# Activation-Rate KPI Brainstorm

> Add an activation-rate KPI to the North Star table — measuring the fraction of subsystems that produce telemetry-confirmed invocation within 14 days of merge. Direct attack on the most documented failure mode in the corpus: shadow-mode infrastructure that ships but never wires up.

## What We're Building

A measurable surface for the PHILOSOPHY.md principle "Wired or it doesn't exist."

The work proceeds in two phases — an evidence-gathering spike, then the production system.

### Phase 0 — Passive-spike against known shadow-mode beads (1 week)

Before committing 63 plugins to an emit-helper annotation, validate that explicit emit is necessary. Spike a passive activation-detector that derives signal from existing `cass` session logs and `git log` activity, and run it against the three documented shadow-mode beads (`iv-zsio`, `iv-godia`, `iv-2s7k7`). Pass criterion: heuristics catch ≥2 of 3 (≥80% recall). If passive catches the historical failures, ship it as v1 and defer explicit emit to v2 only when a concrete miss surfaces. If passive misses ≥2 of 3, proceed to Phase 1 explicit-emit as planned. The spike has a fixed time-box and a concrete go/no-go signal.

### Phase 1 — Explicit-emit production system (only if Phase 0 fails)

Three artifacts:

1. **New kernel event surface — `subsystem_events` table + `SourceSubsystem`**. Add a fifth event table alongside `review_events` / `dispatch_events` / `coordination_events` / phase events. Schema: `id, run_id, subsystem, entry_point, session_id, project_dir, timestamp`. Dedicated cursor and dedup key — no contention with other consumers. `event.go` gets `SourceSubsystem = "subsystem"` added to the `validSources` map and an `event_type` column branch in `cmdEventsRecord`. **This must ship before any subsystem adopts the emit helper** — without the kernel-side surface, every emit call exits 3 from a `|| true` bash hook (the activation-rate KPI silently failing the same way it's designed to detect).

2. **Subsystem opt-in helper** — `ic events emit-subsystem <name> <entry_point>` for Go callers, `interspect-emit-subsystem.sh` shim for bash hooks. Emit-once-per-session-per-subsystem is enforced by an `ic state set` sentinel keyed on `(subsystem, session_id)` with a TTL matching session lifetime. Check-before-emit, write-after-confirmed-success.

3. **Interspect activation aggregator + CLI** — a cursor-driven consumer that mirrors `_interspect_consume_review_events` *with the known race fixed*: read-process-write triple wrapped in `BEGIN EXCLUSIVE`, and the activation table includes a `source_event_id` column with `INSERT OR IGNORE` so cursor regression replays as a no-op. Materializes `activation(subsystem, canonical_name, first_merge_ts, last_emit_ts, distinct_session_count_14d, source_event_ids[])`. CLI: `interspect activation [--since=14d] [--format=table|json]`.

### North Star integration

`docs/sylveste-vision.md` gets a new KPI row under **Quality**: `Activation rate · % of subsystems with ≥3 distinct sessions emitting in the 14d after merge`. A three-week observation window runs before the rate is reported anywhere public. The metric ships as **report-only** for the first quarter; in v2 (after baseline calibration), failing 2 consecutive baseline windows triggers a soft-block: the next PR touching the subsystem requires an explicit `--ack-low-activation` flag at merge. No automatic enforcement before threshold is calibrated.

## Why This Approach

- **Closed-loop fidelity over indirect inference.** Passive derivation from cass logs / git activity cannot distinguish "tool touched a file in the plugin" from "the plugin's hot path actually ran." The activation-sprint pattern doc names the failure mode exactly: silent degradation to stubs is observationally identical to working correctly. An explicit emit forces every subsystem to declare its hot path and threads the signal through the path that produces real work.
- **Reuses an event bus we already have.** Kernel already exposes `review_events` / `dispatch_events` / `coordination_events` via `ic events list-*` with cursor pagination. Interspect already consumes one such stream successfully. The pattern is proven; an `activation_events` table fits beside the others.
- **Subsystem scope = plugin manifests.** "Subsystem" is grounded in `plugin.json` files plus a small kernel-module list — a finite, externally-legible registry of ~63 plugins + ~6 kernel components. No ambiguity about what's being measured.
- **Merge timestamp is cheap.** First commit touching a subsystem's manifest path, computed on demand from `git log --diff-filter=A`. Cached in the `activation` row after first computation.
- **Three-week baseline before gating.** The Goodhart caveat (PHILOSOPHY.md § Measurement) applies: a measure becomes a target the moment it's enforced. Reporting first, gating later, with the threshold derived from the observed distribution rather than picked a priori.

## Key Decisions

1. **"Wired" is defined as ≥3 distinct sessions emitting within 14 days of merge.** Single-emit gaming is the dominant risk; distinct sessions ties the signal to user-meaningful work and resists the "emit once on a test SessionStart" trivial pass. The number 3 is a starting point, not a fixed truth — the calibration job can adjust it from observed distribution.
2. **Phase 0 spike is a real go/no-go**, not a soft fork. Explicit success criterion (≥2 of 3 known shadow-mode beads detected) and a bounded budget (1 week). If passive wins, explicit emit is deferred indefinitely.
3. **New `subsystem_events` table + `SourceSubsystem`**, not a piggyback on existing event types. The cursor-and-dedup contract is its own concern; mixing it into review/dispatch/interspect tables creates consumer contention.
4. **One canonical helper, two surfaces** — `ic events emit-subsystem <name> <entry_point>` for Go, `interspect-emit-subsystem.sh` shim for bash. Both go through the same `cmdEventsRecord` branch.
5. **Emit-once-per-session sentinel must be durable** — stored via `ic state set` keyed on `(subsystem, session_id)` with TTL = max session lifetime. Not an in-memory shell variable.
6. **Cursor + activation-table dedup is mandatory, not best-effort** — `BEGIN EXCLUSIVE` around the read-process-write triple AND `source_event_id` column with `INSERT OR IGNORE`. The reference pattern in `lib-interspect.sh:2577` lacks both; we copy the structure, not the bug.
7. **Gate failure is report-only in v1, soft-block in v2.** Owners get notifications during baseline; soft-block (PR requires `--ack-low-activation`) only activates after threshold is calibrated and proven against ≥1 quarter of data. No automatic enforcement before trust is earned.
8. **Window is 14d primary; 7d and 30d reported alongside** — low-frequency subsystems use the 30d gate, declared via a `low_frequency: true` flag in `plugin.json`.
9. **Subsystem identity is `canonical_name` from `plugin.json`**, not directory path. Renames and monorepo splits (Demarch-og7m active) don't break activation rows. Orphan rows are flagged on aggregator startup, not silently retained.
10. **`first_merge_ts` uses `git log --follow --diff-filter=AR`** to track renames; raw commit hash stored alongside the timestamp for auditability. Monorepo-restructure events get a manual `activation_baseline_ts` override.
11. **Baseline threshold is observed across `(activated + unactivated)`**, not the opt-in cohort alone. Unactivated subsystems report as `not-yet-instrumented` (separate counter); the gate's denominator is fleet-total, not adopters-only.
12. **Goodhart circuit-breaker** — if pass rate exceeds 90% for 2 consecutive quarters, `clavain-cli rotate-metric` retires activation-rate from the gate and surfaces a follow-up bead. Rotation is automatic, not manual discipline.
13. **Subsystem registry comes from `plugin.json` manifests + an explicit kernel-module list** — single source of truth, version-controlled.
14. **Daemon and MCP-only emit contracts are documented in `AGENTS.md` per subsystem type before instrumentation adoption.** Daemon emits after first successful request handled; MCP server emits after first tool call returns successfully. Document, then code.

## Open Questions

Most questions from the original draft were resolved in the revision round above. These remain genuinely open and belong in the plan / strategy step:

- **Phase 0 spike — what does the passive heuristic actually look like?** Best guess: join `cass` session logs (which subsystem files were touched in tool-use trajectories) with `git log` for the 14d window post-merge of each plugin. Score: did any session in 14d post-merge invoke ≥3 distinct call paths into this plugin's directory? Plan must specify the exact heuristic and how it's evaluated against `iv-zsio` / `iv-godia` / `iv-2s7k7`.
- **Per-skill granularity in v2** — plugin-level activation can hide "shipped but wired wrong" failures inside multi-skill plugins. Reporting `unactivated_skill_count` alongside the per-plugin signal is a v1 companion observation; promoting per-skill to a gate is a v2 decision driven by what the v1 data shows.
- **Where the dashboard renders.** `interspect activation` CLI is the v1 surface. A web view (meadowsyn? interpath?) is out of scope for this bead.
- **Calibration trigger.** Default: after 21 days of data and ≥40 subsystems instrumented, fire `clavain-cli calibrate` analogue to compute the gate threshold and write it back as a config. Plan should confirm whether `clavain-cli` already has a calibration-write surface or whether a new one is needed.
- **Cross-project federation** — when Sylveste's primitives generalize to non-software domains, what does activation-rate mean for a research-synthesis sprint? Out of scope for v1; flagged for the eventual generalization bead.

## Review Findings & Refinements (2026-04-28)

Three review lenses (systems, decisions, correctness) surfaced 2 P0 and 6 P1 findings. The plan must address each before execution.

### P0 — must-fix before any code lands

1. **`SourceActivation` does not exist; the kernel will silently reject every emit.** `core/intercore/cmd/ic/events.go:307` hard-rejects every source ≠ `SourceReview` with exit 3, and `cmdEventsRecord` has no branch for an activation event type. Plan must extend `event.go` (`validSources`), the store switch in `cmdEventsRecord`, the CLI surface, and ship a DB migration for an `activation_events` table — **before** any subsystem adopts the helper. Failing to sequence this means every emit call exits 3 from a `|| true` bash hook, the table stays empty, and the KPI silently reports zero. The activation-rate KPI failing in shadow mode is the exact failure it's designed to detect.

2. **Cursor-advance race + missing dedup key.** The reference `_interspect_consume_review_events` pattern at `interverse/interspect/hooks/lib-interspect.sh:2577` reads cursor → fetches → processes → writes cursor without compare-and-swap. Two concurrent sessions can regress the cursor and replay events. Plan must (a) wrap the read-process-write triple in `BEGIN EXCLUSIVE`, and (b) add a `source_event_id` column to the activation table with `INSERT OR IGNORE` keyed on it so replay is a no-op.

### P1 — significant changes to design

3. **Emit-without-integration creates a one-shot gaming loop.** A stub plugin can emit on `SessionStart` and pass the gate forever. Plan must require either ≥N invocations across the window (proposed: ≥3 in 14d) **and** an explicit emit-placement audit checklist applied during PR review. The KPI measures *receipts of work happening*, not "the helper got called once."

4. **Closed feedback loop is undefined.** The brainstorm names a gate but not the consequence of failing it. Plan must specify: failure rule (e.g., subsystem fails the gate for 2 consecutive baseline windows), automatic action (PR-block? Owner notification? Manual review escalation?), and how the action gets reverted once activation resumes.

5. **25th-percentile threshold has survivorship bias.** The observed distribution is dominated by subsystems that adopted emit because their owners are confident the integration works. Plan must compute the threshold over `(activated + unactivated)`, treat unactivated subsystems as `not-yet-instrumented` (separate from gate failure), and document the cohort definition explicitly.

6. **Passive-first spike was dismissed without a reversibility check.** Explicit emit across ~63 plugins is high-commitment. Plan should include a **Phase 0** (≤1 week) that derives heuristic activation from existing `cass` session logs against the three known shadow-mode beads (iv-zsio, iv-godia, iv-2s7k7); if heuristics catch ≥80% of those cases, ship passive as v1 and defer explicit emit to v2 once a concrete shortcoming surfaces.

7. **`first_merge_ts` is wrong on file renames and monorepo splits.** Epic Demarch-og7m (monorepo consolidation) is active. `git log --diff-filter=A` returns the destination's date for renames. Plan must use `git log --follow --diff-filter=AR`, store the source commit hash for auditability, and require a manual `activation_baseline_ts` override for monorepo-restructure events.

8. **Session-emit-once sentinel must be durable.** A shell variable doesn't survive process restart within a session. Plan must store the sentinel via `ic state set` keyed on `(subsystem, session_id)` with a TTL matching the maximum session lifetime; check-before-emit, write-after-confirmed-success.

### P2 / P3 — track in the plan but not blocking

- **Window too short for low-frequency subsystems** — emit 7d, 14d, and 30d simultaneously; the gate uses 30d for any subsystem flagged `low-frequency` in its registry entry.
- **Per-plugin granularity leaks "shipped wrong" failures inside plugins** — explicit decision in the plan: v1 is per-plugin, with the `unactivated_skill_count` reported as a companion observation. Per-skill granularity is v2 with a clear adoption trigger.
- **Pre-baseline plugins need a clock rule** — the activation clock starts at `max(plugin_first_merge_ts, helper_adoption_ts)`; everything earlier is pre-baseline and reports separately.
- **Goodhart rotation is currently manual** — add a circuit breaker in the plan: if pass-rate stays >90% for two consecutive quarters, fire a `clavain-cli rotate-metric` event that retires activation-rate from the gate.
- **Subsystem rename produces orphan rows** — add `canonical_name` to `plugin.json`; orphan registry rows are flagged on aggregator startup.
- **Stored `invocation_count_14d` drifts under sliding window** — compute counts at query time from raw events; the cached column is a known-stale convenience only.
- **Daemon / MCP emit points are unspecified** — daemon emits after first successful request, MCP server emits after first tool-call returns successfully. Document the contract in `AGENTS.md` for each subsystem type before instrumentation adoption.

### Net effect on the brainstorm (resolved 2026-04-29)

All four blocking findings (P0 #1, P1 #3, P1 #4, P1 #6) have been resolved through a second round of design questions:

- **P0 #1 → resolved.** New `subsystem_events` table and `SourceSubsystem` source. The "must ship before any subsystem adopts the helper" sequencing is captured in Phase 1 §1.
- **P1 #3 → resolved.** "Wired" = ≥3 distinct sessions emitting in 14d. Single-emit gaming is the dominant risk; distinct-session count maps to user-meaningful work and is what the gate enforces.
- **P1 #4 → resolved.** v1 = report-only with owner notifications. v2 = soft-block (PR requires `--ack-low-activation`) only after threshold is calibrated against ≥1 quarter of data. No automatic enforcement before trust is earned.
- **P1 #6 → resolved; F0 executed 2026-04-29.** Phase 0 was run against the three known shadow-mode / activation-sprint fixtures (`iv-zsio`, `iv-godia`, `iv-2s7k7`) using existing CASS traces + git history. The prototype harness caught **3/3**, so the next phase is **passive-v1** and explicit subsystem-event emits stay deferred until passive misses a confirmed gap. Report: `docs/research/2026-04-29-passive-activation-spike.md`; harness: `scripts/activation/passive_activation_spike.py`.

Remaining P0 / P1 items from the original review are operational, not architectural — they're captured in Key Decisions #5–#10 (cursor + dedup + sentinel + git-history correctness) and become plan-level checklists.

The other P2 / P3 findings remain in the "track in the plan but not blocking" list above — the strategy step inherits them.

## Source

- `docs/research/flux-engine/sylveste-mission-leverage-20260426.md` — Leverage #1 (R1: activation gap as documented, recurrent pattern).
- `docs/solutions/patterns/activation-sprint-last-mile-gap-20260307.md` — three documented instances; "fail-safe design produces a blind spot" insight.
- `docs/sylveste-vision.md` — North Star table, Goodhart caveat, baseline methodology.
- `core/intercore/internal/event/event.go` — existing event types and `validSources` map; the `Source*` extension point for a new event source.
- `interverse/interspect/hooks/lib-interspect.sh` (line 2577) — `_interspect_consume_review_events` is the template for the new consumer.
- `interverse/interspect/AGENTS.md` — companion-plugin pattern; SQLite DB at `.clavain/interspect/interspect.db`.
- PHILOSOPHY.md — "Wired or it doesn't exist"; § Receipts Close Loops § Measurement (rotation discipline).
