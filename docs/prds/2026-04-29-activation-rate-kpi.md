---
artifact_type: prd
bead: sylveste-8r5h
stage: design
date: 2026-04-29
brainstorm: docs/brainstorms/2026-04-28-activation-rate-kpi-brainstorm.md
---

# PRD: Activation-Rate KPI

## Problem

Sylveste ships infrastructure that runs in `shadow`/`off` mode for weeks. The
"activation-sprint" pattern doc names three documented beads where this
happened (`iv-zsio`, `iv-godia`, `iv-2s7k7`); fail-safe design — every
dependency optional, never blocks — produces a blind spot where silent
degradation to stubs is observationally identical to working correctly.
PHILOSOPHY.md elevates "Wired or it doesn't exist" to a principle, but
the vision lacks a measurable surface for it.

## Solution

Add an **activation-rate KPI** to the North Star table — `% of subsystems
with ≥3 distinct sessions emitting in the 14d after merge`. The KPI fronts
a two-phase implementation: a 1-week passive-detection spike validates
whether existing logs already give us the signal; if not, a kernel-emit
production system follows. v1 reports only; v2 introduces a soft-block
once the threshold is calibrated.

## Features

### F0: Passive-Activation Spike (Phase 0 — 1 week, gating)

**What:** A heuristic detector that derives subsystem activation from `cass`
session logs and `git log`, evaluated against three documented shadow-mode
beads. The spike is a real go/no-go: if heuristics catch ≥2/3, ship passive
as v1 and defer F1–F6 indefinitely. If <2/3, proceed to explicit emit.

**Acceptance criteria:**
- [x] Heuristic spec written: explicit join logic over `cass` session traces + git history, with a documented "what counts as activation" rule (proxy for ≥3 distinct sessions invoking subsystem code paths in the 14d window). See `docs/research/2026-04-29-passive-activation-spike.md`.
- [x] Evaluation harness runs the heuristic against `iv-zsio`, `iv-godia`, `iv-2s7k7` and reports recall (caught/total) plus per-bead detection latency. Harness: `scripts/activation/passive_activation_spike.py`; result: **3/3**.
- [x] Decision recorded as **specific bead-state keys** on the F0 bead (`sylveste-xofc`): `passive_spike_recall=N/3` (e.g., `2/3`) and `next_phase=passive-v1` or `next_phase=explicit-emit-v1`. Recorded values: `passive_spike_recall=3/3`, `next_phase=passive-v1`.
- [x] **`bd set-state` arbitrary-key support verified before spike begins** — `spike_status=started`, `passive_spike_recall=3/3`, and `next_phase=passive-v1` were recorded as Beads state labels/events.
- [x] Spike completes within 7 days of start; at end, the brainstorm's "P1 #6 → resolved" line gets a follow-up note pinning the actual recall number.

**F0 result:** `next_phase=passive-v1`. Phase 1 explicit-event features (F1–F6) are deferred unless passive v1 misses a confirmed activation gap.

### F1: Kernel Subsystem-Event Surface (Ships First in Phase 1)

**What:** Define `SubsystemEvent` as a first-class type in `event.go` —
parallel to `ReviewEvent`, **not** a generic `Event` with a new source.
Subsystem activation is a presence signal, not a state transition, so it
must not share the `FromState` / `ToState` / `Reason` lifecycle contract.
Add a dedicated `Store.AddSubsystemEvent` method, route `cmdEventsRecord
--source=subsystem` to a new `recordSubsystem()` (parallel to
`recordReview`). Ship a DB migration for `subsystem_events`. Expose `ic
events emit-subsystem <name> --entry-point=<path>` and `ic events
list-subsystem --since=<id>`.

**Acceptance criteria:**
- [ ] `subsystem_events` table created via migration: `id INTEGER PK AUTOINCREMENT, run_id TEXT, subsystem TEXT NOT NULL, entry_point TEXT NOT NULL, session_id TEXT NOT NULL, project_dir TEXT, timestamp TIMESTAMP NOT NULL`. Migration applies cleanly on a fresh DB and an existing one (idempotent).
- [ ] `SubsystemEvent` struct defined in `core/intercore/internal/event/event.go` with no `FromState` / `ToState` / `Reason` fields. The generic `Event` struct's `validSources` map is **not** modified — the `SourceSubsystem` constant lives in the subsystem-event domain only.
- [ ] **Falsifiable behavioral test (closes the meta-recursive failure mode):** running `ic events emit-subsystem foo --entry-point=hooks/foo.sh` (without `--source=review`) exits 0, and `ic events list-subsystem --since=0 --limit=1` returns a JSON row matching `{"subsystem":"foo","entry_point":"hooks/foo.sh"}`. The pre-existing rejection at `events.go:307` is removed for this command path or routed around it.
- [ ] Concurrent-emit race test: 50 parallel `ic events emit-subsystem` calls produce 50 rows with 50 unique IDs and no errors.
- [ ] Idempotent re-run: re-applying the migration on an already-migrated DB is a no-op.
- [ ] **Sequencing invariant enforced, not just documented:** an integration test in F1's suite asserts `ic events emit-subsystem` returns 0 against the migrated kernel binary. F2's bash shim contains a `ic version --min=<F1-release-tag>` guard that exits 1 with a clear error if F1 hasn't shipped. F2 cannot pass its own AC against a pre-F1 binary.

### F2: Subsystem Emit Helper (helper only — adoption belongs to F5)

**What:** A two-surface helper that subsystems call from their hot path —
`ic events emit-subsystem <name> --entry-point=<path>` for Go callers,
`interspect-emit-subsystem.sh <name> <entry_point>` shim for bash hooks.
Emit-once-per-session-per-subsystem enforced by an `ic state set`
sentinel keyed on `(subsystem, session_id)`. Session IDs are unique so
the sentinel does not need a TTL for dedup; it carries a 7-day storage
TTL purely as garbage-collection housekeeping for finished sessions.

**Acceptance criteria:**
- [ ] Helper script + Go-callable surface exist; both go through the F1
      `recordSubsystem` path.
- [ ] Sentinel logic: check-before-emit (`ic state get`); on miss, emit
      then write the sentinel only after the emit returns success.
- [ ] **Concrete race test:** 50 parallel `interspect-emit-subsystem.sh
      foo hooks/foo.sh` invocations from the same `session_id` produce
      exactly 1 row in `subsystem_events` and exactly 1 sentinel key.
      Test runs in CI; assertion is `SELECT COUNT(*) FROM subsystem_events
      WHERE session_id = ? AND subsystem = ?` returns 1.
- [ ] Helper exit codes are non-fatal: returns 0 on sentinel-hit, returns
      0 on successful emit, returns 0 if the kernel binary is absent
      (so bash hooks can call without `|| true`). Stderr only on hard
      kernel errors.
- [ ] **Sequencing guard:** the bash shim runs `ic version --min=<F1
      release-tag>` at startup; on mismatch, prints a clear "F1 kernel
      release required" message and exits 1. Verified by a CI job that
      runs the shim against a pre-F1 build.
- [ ] Documented in `AGENTS.md` for each subsystem type: where to call
      from in plugins (first hot-path entry per session), daemons (after
      first successful request), MCP servers (after first tool-call
      returns successfully).

**Note:** the 5-plugin reference adoption moves entirely to F5 to remove
the overlap. F2 ships the helper only; F5 closes the adoption loop.

### F3: Interspect Activation Aggregator

**What:** A cursor-driven consumer with the known race in
`_interspect_consume_review_events` (`lib-interspect.sh:2577`) **fixed
by extracting a shared helper**, not by copying the broken pattern with
patches. Introduce `_consume_event_stream <source> <cursor_key>
<processor_fn>` in `lib-interspect.sh` with `BEGIN EXCLUSIVE` around
the read-process-write triple. Refactor the existing review-events
consumer to call it; F3's subsystem-events consumer uses the same
helper. Two consumers, one canonical implementation.

The schema separates an **event log** (immutable rows, one per
emit) from an **aggregate summary** (per-subsystem rollup, computed
at query time). They are different cardinalities and live in different
tables.

**Acceptance criteria:**
- [ ] `activation_events` table created: `id INTEGER PK AUTOINCREMENT,
      source_event_id INTEGER NOT NULL, subsystem TEXT NOT NULL,
      session_id TEXT NOT NULL, ts INTEGER NOT NULL, project_dir TEXT,
      UNIQUE(subsystem, source_event_id)`. The unique constraint backs
      `INSERT OR IGNORE` so cursor regression replays as a no-op.
- [ ] `activation_summary` is a query-time view (or a materialized cache
      with explicit refresh), keyed on `canonical_name`. **Distinct-
      session count uses `COUNT(DISTINCT session_id)`, never `COUNT(*)`.**
      Two emits from the same session count as 1 toward the gate.
- [ ] **Idempotent re-run test:** running the aggregator against the same
      event window twice produces identical `distinct_session_count_14d`
      values (no inflation from replay).
- [ ] **Cursor-reset test:** simulate a cursor regression by setting
      the cursor back to 0; aggregator re-runs without inflating counts
      and without errors.
- [ ] **Concurrent-consumer race test:** two interspect sessions consuming
      in parallel produce identical row counts and zero duplicate
      `(subsystem, source_event_id)` violations.
- [ ] **Shared helper extracted:** `_consume_event_stream` exists in
      `lib-interspect.sh`. The existing `_interspect_consume_review_events`
      is rewritten to call it. F3's subsystem consumer is the second
      caller of the shared helper, not a third copy of the cursor pattern.
      Regression test: existing review-events consumption still works.
- [ ] **Rename test:** a plugin's manifest path moves; `first_merge_ts`
      resolves to the original add commit via `git log --follow
      --diff-filter=AR`. The source commit SHA is stored on the
      `activation_summary` row for auditability.
- [ ] **Orphan handling:** aggregator startup logs registry rows whose
      `plugin.json` is missing; orphans are flagged in the dashboard
      (separate status), not silently retained or deleted.

### F4: `interspect activation` CLI

**What:** A new command surface that returns per-subsystem activation
state, supports `--since=7d|14d|30d`, formats `--format=table|json`, and
distinguishes three statuses: `activated`, `instrumented-but-quiet`,
`not-yet-instrumented`.

**Acceptance criteria:**
- [ ] `interspect activation` lists every subsystem in the **full
      registry** (every `plugin.json` + kernel-module list), with status,
      `first_merge_ts`, **`COUNT(DISTINCT session_id)`** for 7d / 14d /
      30d, and time since last emit. Subsystems with zero rows in
      `activation_events` appear as `not-yet-instrumented` — never
      omitted.
- [ ] Fleet rollup line: `% activated = activated / (activated +
      instrumented-but-quiet + not-yet-instrumented)`. Denominator
      explicitly includes `not-yet-instrumented` so the rollup cannot
      be 100% by construction.
- [ ] `--format=json` output is round-trippable into the calibration
      job (schema documented in code; downstream consumers depend on it).
- [ ] **Performance gate enforced in CI:** a benchmark fixture with
      70 subsystems and 30d of seeded events; CI asserts the command
      completes in <500ms on the standard runner. Fixture and assertion
      script land alongside F4.

### F5: Plugin Registry Annotations + Reference Adoption

**What:** Extend `plugin.json` schema with `canonical_name` (stable
identity across renames). **`low_frequency: bool` is deferred to the
follow-up calibration bead** — it only matters once a soft-block gate
exists, and bundling it with `canonical_name` mixes an identity contract
with a measurement parameter. Adopt the F2 helper in 5 representative
plugins covering: one hook-only, one command-only, one skill-heavy, one
daemon-style, one MCP-style.

**Acceptance criteria:**
- [ ] `plugin.json` schema docs updated; existing manifests get
      backfilled with `canonical_name` defaulting to the plugin directory
      name. One commit per logical change (schema + backfill).
- [ ] **5 reference plugins reach status `activated` in
      `interspect activation`** — meaning the F4 dashboard shows ≥3
      distinct sessions per plugin in 14d, not just one emit. The
      adoption proves the *full* KPI threshold fires, not just that
      instrumentation runs. Sessions can be real dev work or autonomous
      agent runs; the AC closes when `interspect activation
      --format=json | jq '[.subsystems[] | select(.status=="activated")]
      | length'` returns ≥5.
- [ ] Adoption checklist published in `AGENTS.md` for the rest of the
      fleet to follow.

### F6: North Star Integration + Observation Methodology

**What:** Edit `docs/sylveste-vision.md` to add the activation-rate KPI to
the North Star table under **Quality**. Document the 3-week observation
window methodology, the v1-report-only / v2-soft-block transition, and the
Goodhart-rotation circuit-breaker.

The Goodhart breaker's **trigger mechanism is decided at plan time, not
left as documentation**: F6 either (a) wires `clavain-cli rotate-metric`
if it exists, or (b) ships a stub command that opens a follow-up bead
when the trigger condition fires. F6 does not close until one of these
two paths is concrete.

**Acceptance criteria:**
- [ ] North Star table row added: `Quality | Activation rate | % of subsystems with ≥3 distinct sessions emitting in 14d after merge`.
- [ ] Methodology section names: 3-week observation window before any threshold publication; threshold derives from observed distribution over `(activated + instrumented-but-quiet + not-yet-instrumented)`, not adopters-only; v1 is report-only; v2 (soft-block) requires explicit calibration approval.
- [ ] **Goodhart circuit-breaker is exercisable, not just documented:** plan resolves whether `clavain-cli rotate-metric` exists. If yes, F6 wires it and runs a dry-run test (pass-rate fixture set artificially >90% for 2 consecutive quarters → command opens a follow-up bead). If no, F6 ships a stub `clavain-cli rotate-metric --create-followup-bead` that opens a follow-up bead and exits 0; the dry-run test verifies the bead gets opened.
- [ ] Cross-reference back to PHILOSOPHY.md "Wired or it doesn't exist" added.

## Non-goals

- **Per-skill granularity.** v1 reports per-plugin. The companion observation
  `unactivated_skill_count` ships in v1; per-skill gating is a v2 decision
  driven by what v1 data shows.
- **Web dashboard.** `interspect activation` CLI is the v1 surface. A
  meadowsyn / interpath view is out of scope.
- **Gate enforcement at merge time in v1.** Soft-block (`--ack-low-activation`)
  is v2 only, after baseline calibration approves a threshold.
- **Cross-project federation.** Activation-rate as a portable signal across
  external Sylveste-built projects waits for the generalization bead.
- **Calibration job + threshold-write surface.** The calibration job that
  reads activation data and writes a gate threshold belongs to a follow-up
  bead; this bead delivers the data, not the gate.

## Dependencies

- **Kernel work in `core/intercore`** — F1 must land via the kernel's
  release cycle before F2 / F3 can wire to it. Migration must apply cleanly
  on existing dev DBs.
- **`cass` session logs** — F0 spike depends on cass being indexed and
  queryable; the SessionStart hook auto-indexes when stale, so this should
  hold by default.
- **`bd` and `clavain-cli` state-store** — F2 sentinel depends on durable
  `ic state set` with TTL.
- **Three documented shadow-mode beads** — F0 evaluation depends on
  `iv-zsio` / `iv-godia` / `iv-2s7k7` records still being readable in the
  bead history; verify before spike begins.

## Strategy Review Findings & Refinements (2026-04-29)

Two review lenses (architecture, acceptance-criteria-quality) surfaced 4 P0 and 6 P1 findings against the first PRD draft. All are folded back above. Summary:

**P0 — fixed in-place:**
1. **F1 used the wrong event shape.** The unified `Event` struct in `event.go` is a lifecycle-transition contract (`FromState` / `ToState` / `Reason`); subsystem activation is a presence signal. Fixed: F1 now defines `SubsystemEvent` as a first-class type parallel to `ReviewEvent`, with its own `Store.AddSubsystemEvent`. The `validSources` map for the generic `Event` is **not** modified.
2. **F1 AC2 was a mechanism test, not a behavioral one.** Fixed: F1 now has an explicit falsifiable AC that `ic events emit-subsystem` exits 0 without `--source=review`, closing the meta-recursive failure mode.
3. **F2 sentinel TTL=24h was nonsense** — session_id is unique, so dedup needed no TTL. Fixed: TTL re-cast as 7-day storage GC, with the dedup guarantee restated.
4. **F2 race AC was vague.** Fixed: 50 parallel calls, exact SQL assertion, runs in CI.

**P1 — fixed in-place:**
5. **Sequencing without enforcement.** Fixed: F2 shim runs `ic version --min=<F1-tag>` and exits 1 on mismatch; F1 ships an integration test confirming emit returns 0; F2 has a CI job that runs the shim against a pre-F1 binary.
6. **F3 copied a known-broken cursor pattern.** Fixed: F3 now requires extracting `_consume_event_stream` as a shared helper and refactoring the existing review-events consumer to use it. Two consumers, one canonical implementation.
7. **F3 ACs tested schema not behavior.** Fixed: idempotent re-run, cursor-reset, and concurrent-consumer race tests are explicit ACs.
8. **F4 <500ms unverifiable.** Fixed: benchmark fixture lands alongside F4; CI asserts.
9. **F5 "real session" ambiguous.** Fixed: F5 AC now requires `interspect activation` to show ≥5 plugins as `activated` (≥3 distinct sessions each), proving the full KPI fires — not just that emit ran once.
10. **`COUNT(DISTINCT session_id)` not enforced.** Fixed: F3 AC pins the query; F4 AC repeats the requirement at the dashboard layer.

**P2 / P3 absorbed structurally** (not deferred to plan-level):
- Activation table split into `activation_events` (immutable rows) + `activation_summary` (rollup).
- F2 vs F5 5-plugin overlap removed: F2 ships helper only; F5 owns adoption.
- F4 explicitly includes `not-yet-instrumented` in the rollup denominator.
- `low_frequency` deferred to the calibration follow-up bead — only matters with a soft-block.

## Open Questions

- **F0 heuristic spec.** What's the exact join? Default proposal: a
  subsystem counts as "passively activated" if cass session logs in the
  14d post-merge window show ≥3 distinct session IDs whose tool-call
  trajectories include any file under that subsystem's directory. Plan
  step refines.
- **Subsystem registry ground truth.** Plugin manifests cover 63 plugins;
  what kernel-side modules should also be tracked? Proposal: only kernel
  components with their own AGENTS.md and a public CLI surface (`ic`,
  `bd`). Plan step enumerates.
- **Calibration trigger location.** Does `clavain-cli` already have a
  `rotate-metric` / `calibrate-metric` surface, or does this bead add a
  stub for the follow-up calibration bead to fill in? Plan step audits.
