---
bead: iv-544dn
date: 2026-03-05
type: research
status: draft
---

# Interspect Event Validity and Outcome Attribution

**Question:** What event model is sufficient for Interspect and the north-star metric to make correct decisions?

## Executive Summary

1. Intercore already has durable tables for `runs`, `dispatches`, `run_artifacts`, `discoveries`, `review_events`, and `interspect_events`, but the "unified" event stream exposed through `ListAllEvents` and `ic events tail` is not actually complete. It merges phase, dispatch, discovery, coordination, and review events, but excludes `interspect_events`.

2. The strongest quality signal currently available is `review_events`, not raw override counts. A disagreement resolution already records `finding_id`, `agents_json`, `resolution`, `dismissal_reason`, `chosen_severity`, `impact`, `session_id`, and `project_dir`. That is close to a canonical correctness signal if the dismissal taxonomy is treated as authoritative.

3. Outcome attribution above the event layer is still soft. Session to bead and bead to phase are propagated through `/tmp/interstat-bead-{session_id}` and `/tmp/interstat-phase-{bead_id}`. Bead to run is a convention (`runs.scope_id = bead_id` plus `bd state <bead> ic_run_id`). There are now at least three competing denominators for "landed change": raw git commits in a session window, closed beads joined to interstat output, and Galiana's phase-based landed count.

4. This violates a Demarch design invariant. The vision says "if it matters, it's in the database." The current measurement path still relies on temp files, hook-local SQLite, and heuristic JSONL matching in the exact places Interspect needs to trust.

5. The research priority is therefore instrumentation integrity before more learning logic: make the event stream complete, make the attribution chain durable, and make the outcome taxonomy canonical.

## Current Durable Surface

The kernel already persists more than the current measurement story credits it for.

| Surface | Current durable fields | What it supports |
|---|---|---|
| `runs` | `id`, `project_dir`, `phase`, `scope_id`, `metadata`, budget fields | Sprint/run lifecycle, policy state |
| `dispatches` | `id`, `status`, `project_dir`, `scope_id`, token counters, verdict summary, `base_repo_commit` | Agent execution lifecycle and cost |
| `merge_intents` | `dispatch_id`, `run_id`, `base_commit`, `result_commit`, status | Closest existing durable link from execution to landed commit |
| `run_artifacts` | `run_id`, `phase`, `path`, `type`, `dispatch_id` | Durable artifact lineage inside a run |
| `discoveries` | `id`, `source`, `run_id`, `bead_id`, status fields | Discovery promotion and bead association |
| `review_events` | `run_id`, `finding_id`, `agents_json`, `resolution`, `dismissal_reason`, `chosen_severity`, `impact`, `session_id`, `project_dir` | Human-reviewed disagreement outcomes |
| `interspect_events` | `run_id`, `agent_name`, `event_type`, `override_reason`, `context_json`, `session_id`, `project_dir` | Human correction and agent-performance evidence |

Two details matter:

- `review_events` are already part of the kernel-wide event stream through `ListAllEvents`.
- `interspect_events` are durable in the kernel schema, but are only reachable through `ListInterspectEvents`, not the global stream that other consumers tail.

## Current Attribution Chain

What Interspect and the north-star metric actually need is a stable chain from an observed event to a shipped outcome.

### Desired chain

`event -> session -> bead -> run -> dispatch/artifact -> landed change -> outcome`

### Current implementation

| Link | Current mechanism | Strength |
|---|---|---|
| event -> session | Durable for `review_events` and `interspect_events` via `session_id`; absent for most phase/dispatch events | Mixed |
| session -> bead | `/tmp/interstat-bead-{session_id}` written by hooks and route/work helpers | Weak |
| bead -> phase | `/tmp/interstat-phase-{bead_id}` temp file | Weak |
| bead -> run | `runs.scope_id = bead_id` by convention plus `bd state <bead> ic_run_id` | Medium |
| run -> dispatch | `dispatches.scope_id = run_id` by convention in Clavain cutover flow | Medium |
| run -> artifact | `run_artifacts.run_id` | Strong |
| run/session -> landed change | session-window `git log`, or bead-based wrappers around interstat, or Galiana phase heuristics | Weak |
| reviewed finding -> landed change | No durable join | Missing |

The weakest joins are exactly the ones needed for outcome-based learning.

## What The Code Says Today

### 1. The unified event stream is only partially unified

`core/intercore/internal/event/store.go` merges five tables in `ListAllEvents`: `phase_events`, `dispatch_events`, `discovery_events`, `coordination_events`, and `review_events`.

That matters for two reasons:

- `review_events` are already tail-able through `ic events tail`, so any consumer comment that says review events are outside the union stream is stale.
- `interspect_events` are still excluded, even though `SourceInterspect` and the `interspect_events` table exist in the kernel.

There is a second nuance: review events are present in the generic stream, but not at full fidelity. In the bus projection, `finding_id` becomes `from_state`, `resolution` becomes `to_state`, and `agents_json` is shoved into `reason`. Critical fields such as `dismissal_reason`, `chosen_severity`, `impact`, `session_id`, and `project_dir` do not survive the generic shape. So the system has both problems at once:

- one evidence class is missing from the unified stream
- another is technically present, but flattened enough that serious consumers still need a side-channel API

This creates an architectural mismatch: Interspect is supposed to learn from the kernel's event stream, but some of its own evidence class is still off to the side.

### 2. The north-star denominator is not canonical yet

There are now three live definitions of "landed" in the repo:

- the baseline note for `iv-b46xi` counts raw git commits inside a session window
- `ic cost baseline` wraps interstat bead-level output and closed beads
- Galiana derives landed work from telemetry expectations around phase transitions

This is worse than an implementation gap; it means the economic north star is not yet a single metric.

The baseline note for `iv-b46xi` is explicit about several current limitations:

- bead attribution was initially missing and later patched through `/tmp/interstat-bead-{session_id}`
- main-session tokens come from SessionEnd JSONL parsing
- `wall_clock_ms` is still zero
- landed changes are approximated by commits that occurred during the measured session window

`interverse/interstat/hooks/post-task.sh` confirms the current attribution path:

- reads `/tmp/interstat-bead-{session_id}`
- reads `/tmp/interstat-phase-{bead_id}`
- inserts `bead_id` and `phase` into `agent_runs`

`interverse/interstat/scripts/analyze.py` then backfills token usage by matching JSONL files to `agent_runs` with increasingly loose heuristics:

1. `session_id + agent_name`
2. `session_id + agent_name` including already parsed rows
3. any unparsed row for the same `session_id` where `subagent_type IS NOT NULL`

That is acceptable for a first baseline. It is not strong enough for routing or autonomy decisions.

The important nuance from the kernel schema is that Demarch is not starting from zero here. `dispatches.base_repo_commit` and `merge_intents.result_commit` are already the beginnings of a durable landed-outcome chain; the current metrics paths simply do not consume them.

### 3. Interspect still operates a parallel evidence model

`interverse/interspect/hooks/lib-interspect.sh` maintains its own SQLite `evidence` table and computes:

- override rate
- false-positive rate
- finding density
- canary outcomes

It also converts kernel `review_events` into local `disagreement_override` evidence by mapping `dismissal_reason` into `override_reason`:

| review dismissal | local override reason |
|---|---|
| `agent_wrong` | `agent_wrong` |
| `deprioritized` | `deprioritized` |
| `already_fixed` | `stale_finding` |
| `not_applicable` | `agent_wrong` |
| empty + severity override | `severity_miscalibrated` |

This translation is useful, but it also means the learning layer is already interpreting the signal, not just storing it. Once that happens in a plugin-local DB, reproducing or auditing the original evidence becomes harder.

### 4. The run/bead join is durable only by convention

The cutover docs already describe the current migration contract:

- `ic run create --scope-id="$bead_id"`
- `bd set-state "$bead_id" "ic_run_id=$run_id"`

That is enough for Clavain to bridge old bead-centric workflows into Intercore. It is not yet a first-class attribution model. The kernel does not know that `scope_id` is a bead ID; it only knows that some scope string exists.

### 5. The public contracts are incomplete for measurement consumers

The repo ships JSON contracts for the generic event and the typed Interspect event, but not for a typed review event. That reinforces the current ambiguity:

- the generic bus contract is too lossy for review analytics
- the typed review event exists in storage and CLI behavior, but not as a first-class public contract

If measurement is meant to be replayable across components, typed review outcomes need the same contract discipline as the rest of the event surface.

## Validity Findings

### F1 [P0]: The global event stream excludes `interspect_events`

This is the highest-priority structural gap. If the official answer to "what happened?" requires both `ListAllEvents` and `ListInterspectEvents`, then there is no single canonical event history for learning consumers.

**Why it matters**

- A replay or counterfactual evaluator cannot reconstruct the full evidence trail from one stream.
- Any downstream consumer that trusts `ic events tail` is blind to explicit correction signals.
- The system creates pressure for plugin-local side channels because the kernel stream is incomplete.

Closely related: even the `review_events` that do appear on the bus are flattened enough to drop fields that matter for attribution and scoring. A complete stream also needs to be a sufficiently expressive stream.

### F2 [P0]: Session, bead, and phase attribution still depend on temp files

`/tmp/interstat-session-id`, `/tmp/interstat-bead-{session_id}`, and `/tmp/interstat-phase-{bead_id}` are operationally clever but architecturally fragile.

**Failure modes**

- stale or missing files after crashes
- attribution loss when work moves across sessions
- invisible drift between what the user thinks they are working on and what interstat records

This is exactly the category of state the Demarch vision says must not live in temp files.

### F3 [P0]: "Landed change" has multiple conflicting definitions

The repo currently uses at least three different denominators for landed work:

- raw commits in a session window
- closed beads joined to interstat output
- Galiana phase-based landed inference

That supports experimentation, but not a trusted north star.

It cannot answer:

- which run produced this landed change?
- which bead consumed the spend?
- which review outcomes or routing decisions preceded the landing?
- which later revert or defect should be attributed back to that run?

Without a durable landed-change entity and a single canonical denominator, outcome attribution will stay approximate.

### F4 [P1]: The learning system stores interpreted evidence without event lineage

The local Interspect evidence store preserves useful summaries, but not a clean lineage edge back to the kernel event ID that produced them.

That makes several future tasks harder:

- replaying the same evidence against new scoring logic
- auditing whether a mapping rule was wrong
- distinguishing raw observation from derived interpretation

The specific risk is that a taxonomy change quietly rewrites history in the derived layer.

### F5 [P1]: Phase and dispatch activity are not session-attributable enough

`review_events` and `interspect_events` have `session_id`. Phase and dispatch events do not.

That means:

- orchestration activity is joinable to a run, but not directly to a user session
- multi-session work on the same run is hard to attribute cleanly
- session-level efficiency metrics have to infer causality from time windows

If the north star wants "cost per landable change" and "signal per gate", session identity cannot remain optional metadata on only some event types.

### F6 [P1]: The dismissal taxonomy is nearly canonical, but one mapping is still lossy

The current review pipeline is much better than raw override counting because it distinguishes:

- `agent_wrong`
- `deprioritized`
- `already_fixed`
- `not_applicable`
- severity mismatch

But the consumer currently maps `not_applicable` to `agent_wrong`. That may be defensible in some cases, but it collapses a semantic distinction at the evidence layer rather than in a derived metric.

The right place for that choice is a reporting rule or scored view, not the raw fact table.

### F7 [P2]: The current denominator ignores dark sessions and unmeasured work

The PRD already calls out dark and abandoned sessions as needed evidence, but the current measurement stack does not make them first-class durable entities.

If a hard session fails before interstat backfill or before any useful event fires, the system silently undercounts failure. That biases every optimization toward the visible happy path.

### F8 [P2]: Typed review outcomes are not a first-class public contract

The storage model and CLI already treat review outcomes as a distinct event type, but the public contracts lag behind that reality.

This increases drift risk:

- consumers may overuse the generic flattened event shape
- tooling cannot validate review payloads the same way it can validate generic and Interspect events
- future schema evolution for review outcomes has no explicit compatibility boundary

## Canonical Validity Contract

Before more autonomy or routing adaptation, Demarch needs a compact contract for what counts as measurement-grade evidence.

### Raw facts

These should be durable, append-only, and minimally interpreted:

- session started
- session ended
- bead claimed or changed
- run created
- phase advanced or blocked
- dispatch spawned, completed, failed
- artifact created
- review finding resolved
- manual correction recorded
- landed change recorded
- revert or defect recorded

### Required joins on every measurement-grade fact

Not every event needs every field, but the measurement layer needs a durable way to resolve each fact to:

- `session_id`
- `project_dir`
- `bead_id`
- `run_id`
- `dispatch_id` when relevant
- `artifact_id` or output path when relevant
- upstream `source_event_id` when the fact is derived from another event

### Derived metrics

These should not be stored as if they were raw facts:

- override rate
- false-positive rate
- finding density
- cost per landable change
- canary degradation verdicts

Those belong in SQL views, reports, or rollups whose lineage points back to the raw events above.

## Recommended Research Outcomes

### 1. Make the kernel event surface complete

Pick one of two models and enforce it consistently:

- **Preferred:** include `interspect_events` in the global event stream with consistent cursor semantics.
- **Fallback:** keep multiple streams, but explicitly define the full measurement read model as `events + interspect_events + session ledger`, not "the event stream."

The current in-between state is the problem.

Whichever model wins, the typed review outcome shape should also become a public contract instead of living only in storage and CLI code.

### 2. Replace temp-file attribution with a durable session ledger

Demarch needs a first-class durable record for:

- `session_id`
- `bead_id`
- `run_id`
- `phase`
- `project_dir`
- `started_at`
- `ended_at`
- host agent / toolchain metadata

Whether this lives as a new kernel table or another durable relation, it should become the authoritative join between host sessions, beads, and runs. Temp files can remain a transport mechanism, but not the source of truth.

### 3. Promote landed change to a first-class outcome

The kernel already has partial ingredients for this in `dispatches.base_repo_commit` and `merge_intents.result_commit`, but no canonical landed-outcome entity. Add one.

Minimum fields:

- `commit_sha`
- `project_dir`
- `run_id`
- `bead_id`
- `session_id`
- `merged_at`
- optional `reverted_at`
- optional downstream defect or gate-failure links

Once this exists, the north star can be measured from durable joins instead of windowed git approximations.

### 4. Preserve raw review semantics and do scoring in views

Treat the review dismissal taxonomy as canonical raw data. If `not_applicable` should count against an agent for one report, do that in the report. Do not collapse it in the evidence ingestion path.

This keeps future analysis reversible.

### 5. Attach lineage IDs to derived evidence

If Interspect keeps a local evidence cache for performance, each derived row should carry:

- `source_table`
- `source_event_id`
- `derivation_version`

That preserves replayability and makes taxonomy changes auditable.

### 6. Measure coverage, not just outcomes

Every serious metrics system needs a coverage metric. Demarch should explicitly track:

- sessions with start but no end
- sessions with no bead attribution
- runs with no landed outcome
- landed changes with no run or bead link
- review outcomes with no upstream dispatch lineage

Coverage gaps should block confidence in autonomy claims.

## Decision Criteria For iv-544dn

This bead should be considered successful when it produces agreement on three concrete decisions:

1. What is the canonical measurement read model: one event stream, or multiple explicitly required streams?
2. What is the durable join between `session_id`, `bead_id`, and `run_id`?
3. What is the first-class entity for a landed outcome, so the north-star denominator stops being a time-window approximation?

Until those three are settled, routing evals, canary policy, and autonomy policy will all be built on unstable attribution.

## Recommended Follow-On Work

1. Schema/design task: add a durable session ledger and landed-change entity to Intercore.
2. Consumer task: unify or formally version the measurement read model for `ic events`.
3. Interspect task: stop collapsing raw dismissal semantics during ingestion; move those mappings into reports.
4. Metrics task: rebuild the north-star baseline from durable joins once the landed-change entity exists.
