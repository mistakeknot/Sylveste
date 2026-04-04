---
artifact_type: flux-drive-finding
reviewer: fd-architecture
brainstorm: docs/brainstorms/2026-04-03-ockham-vision-brainstorm.md
revision_reviewed: 3
date: 2026-04-03
---

# Architecture Review — Ockham Vision Brainstorm (rev 3)

## Verification of Prior Findings

### P0 — Bead-to-theme mapping: RESOLVED

Section 2 establishes `theme = bead.lane` with a clear fallback (`open` for unlaned beads). The terminology collision between "lane" (intercore kernel entity) and "theme" (Ockham policy label) is explicitly addressed. The mapping uses `bd list --json | jq '.[] | {id, lane}'` with no new data model. This is the minimal correct fix.

### P1 — Dispatch renamed to Scoring with typed structs: PARTIALLY RESOLVED

The brainstorm (Section 1) correctly renames the package to "Scoring" and specifies typed input structs (`IntentVector`, `AuthorityState`, `AnomalyState`). The dependency direction — "Scoring receives structs, imports nothing" — is a sound isolation model.

However, the fix is incomplete at the documentation layer. `os/Ockham/AGENTS.md` and `os/Ockham/CLAUDE.md` both still name the package `dispatch` and the directory `internal/dispatch/`. The code directory itself is `internal/dispatch/`. Three authoritative documents (AGENTS.md, CLAUDE.md, directory name) contradict the brainstorm's rename. Until AGENTS.md, CLAUDE.md, and the directory are updated, the package will be built as `dispatch` regardless of what the brainstorm intends. This is a documentation/implementation alignment gap, not a blocking architecture issue, but it will cause confusion at build time.

Additionally: the brainstorm specifies that Scoring receives structs but never identifies what orchestrates the assembly — which caller gathers `IntentVector + AuthorityState + AnomalyState` and invokes Scoring. See NEW-P0 below.

### P1 — ockham_weight injection: RESOLVED

Section 3 specifies bulk pre-fetch (`ic state list "ockham_offset" --json` once per dispatch cycle), placement before perturbation and before the floor guard, and logging of both `raw_score` and `final_score`. The timing and observability concerns are addressed.

Note: the floor guard issue at line 207 of lib-dispatch.sh (`(( adjusted_score < 1 )) && adjusted_score=1`) interacts with the offset in a way the brainstorm does not fully specify — see NEW-P1 below.

### P1 — CLI temporal model: RESOLVED

Section header "Temporal model" explicitly states signals.db (SQLite at `~/.config/ockham/signals.db`) persists signal timestamps and confirmation windows. Multi-window confirmation operates on stored timestamps, not in-memory timers. This is the correct fix.

### P1 — Tier 3 write/notify ordering: RESOLVED

Section 5, Tier 3: "Write factory-paused.json FIRST, then notify." Explicit. Safety Invariant 5 reinforces this. Fixed.

---

## New Findings

### NEW-P0 — Missing orchestration layer: Scoring assembly has no owner

**Location:** Section 1, Key Decision 1 (subsystem table)

The brainstorm's core decoupling claim — Scoring receives typed input structs from Intent, Authority, and Anomaly — requires an orchestration layer that assembles those structs and calls Scoring. No such layer is named or designed. The subsystem table lists four packages but shows no component that calls `Scoring(IntentVector, AuthorityState, AnomalyState)`.

This is the previous god-module risk reappearing at the call site. If the CLI entrypoint (`cmd/ockham`) assembles the structs and calls Scoring, then `cmd/ockham` imports all four internal packages and is the god module. If a new `governor` or `engine` package does it, that package is unnamed and undesigned. The brainstorm's dependency diagram — "Intent → (no deps) | Authority → interspect | Anomaly → all read-only | Scoring → receives structs, imports nothing" — describes module-level imports but leaves the orchestration topology unspecified.

The smallest fix: name the orchestrator explicitly. The CLI entrypoint is a legitimate choice, but if it grows beyond struct assembly and Scoring invocation it will accumulate logic that belongs in a policy layer. A thin `internal/governor` package with a single exported function `Evaluate(ctx, stores) WeightVector` would be cleaner and is the most natural boundary for the Wave 1 wiring described in Section 10.

Severity: P0. Without this, the implementation will improvise the topology and the decoupling guarantees become aspirational.

---

### NEW-P1 — ±12 bound does not preserve priority ordering

**Location:** Section 3, "Dispatch integration via additive weight offsets"

The brainstorm states: "the priority gap between adjacent tiers is ~24 points in lib-dispatch.sh's scoring." This figure is incorrect.

The actual scoring formula in `interverse/interphase/hooks/lib-discovery.sh` (`score_bead()`) assigns:
- P0: 60, P1: 48, P2: 36, P3: 24, P4: 12

The gap between adjacent tiers is **12 points**, not 24. An ockham_offset of +12 on a P3 bead produces the same base priority score (36) as a P2 bead with offset 0 — plus phase and recency modifiers can then push the P3 bead ahead. A +12 offset is therefore capable of crossing a full priority tier boundary in common cases.

The brainstorm's safety claim — "intent can nudge ties and close races, but can never cause a P3 bead to outrank a P1 bead" — is true for a two-tier skip, but false for a one-tier skip. P3+12 can outrank P2+0 whenever phase and recency scores are comparable.

Two options:
1. Reduce the bound to ±6 (half the tier gap), which limits Ockham to influencing within-tier ordering only.
2. Accept one-tier crossing as intentional and document it explicitly — "intent can promote a bead one priority tier" — removing the false safety claim.

Option 1 is the conservative and architecturally honest choice. Option 2 is valid if the principal understands the semantics, but the current text misleads by claiming priority ordering is preserved when it is not.

Severity: P1. The offset integration will work mechanically, but the safety guarantee stated in the brainstorm is false given the actual scoring constants. This needs resolution before the Wave 1 wiring spec is written.

---

### NEW-P1 — Freeze constraint is misarchitected as an extreme offset

**Location:** Section 4 (intent.yaml schema comment), Section 3 (bound description), Safety Invariant 6

The brainstorm describes freeze as `ockham_offset = -999` ("effectively blocked"). This conflicts with two existing mechanisms:

1. `lib-dispatch.sh` line 196-200: a frozen lane is handled via `ic lane status` metadata (`paused: true`), which causes a hard `continue` (bead is skipped entirely, not just scored low). This path is already implemented and correct.
2. `lib-dispatch.sh` line 207: the floor guard `(( adjusted_score < 1 )) && adjusted_score=1` would raise any score, including -999, to 1 — making the "effectively blocked" offset ineffective without a separate exclusion path.

If Ockham uses offset -999 for freeze, and the floor guard applies after adding the offset, frozen beads will receive score 1 and remain claimable. The existing lane-pause path is the correct mechanism for freeze. Ockham's freeze constraint should call `ic lane update --metadata="paused:true"` (as listed in Section 9 "What already works") rather than writing an extreme offset.

The brainstorm mentions this in Section 9 but contradicts it in Section 4. The schema comment `freeze: [] # weight set to -999` should instead read `freeze: [] # sets lane paused:true via ic lane update`. The -999 design should be removed to avoid the floor-guard conflict.

Severity: P1. Leaving both mechanisms in place means freeze semantics depend on which path executes first — the offset path silently fails (floor guard rescues the bead to score 1) while the lane-pause path correctly blocks it.

---

### NEW-P2 — signals.db creates a reconciliation gap with primary sources

**Location:** Section header "Temporal model" / Key Decision 1 (Anomaly subsystem)

signals.db persists signal timestamps and confirmation windows so the CLI can operate statelessly between invocations. This is the correct fix for the in-memory timer problem. However, the brainstorm treats signals.db as ground truth for temporal state while treating interspect, interstat, and beads as ground truth for signal conditions — and does not specify how these are reconciled when they diverge.

Concrete scenario: A Tier 2 CONSTRAIN signal fires and is recorded in signals.db. Before the de-escalation stability window completes, someone manually resolves the underlying condition (e.g., closes the quarantined beads, fixes the circuit breaker). Interspect now shows the condition cleared. signals.db still shows the signal active and the stability window in progress. The next CLI invocation reads signals.db, sees the window not yet expired, and holds the CONSTRAIN despite the underlying condition being gone.

This is not an edge case — it's the normal recovery path. The brainstorm's de-escalation rule (Section 5) says "both windows must simultaneously drop below threshold," which requires reading current conditions from the primary sources. But if signals.db is the state store, de-escalation also requires re-evaluating conditions against primary sources on each CLI invocation. The brainstorm does not specify whether each `ockham` invocation re-reads all conditions from interspect/beads/interstat or only checks signals.db timestamps.

The smallest fix: specify that each CLI invocation performs a full condition re-evaluation against primary sources before reading signals.db timestamps. signals.db stores only the temporal envelope (when did the condition first fire, when did it clear), not the condition truth. This must be stated explicitly in the design.

Severity: P2. The signals.db design is sound in concept but incomplete in its reconciliation contract. Without this specification, the implementation will vary in behavior depending on whether developers treat signals.db as a cache or a source of truth.

---

### NEW-P2 — Weight-outcome feedback loop has no actuation path

**Location:** Section 10, "Weight-outcome feedback loop"

The feedback loop emits a Tier 1 INFORM signal and logs a `weight_drift` event to interspect when a theme's actual-vs-predicted ratio degrades. Tier 1 INFORM is described in Section 5 as "Signal fires, dispatch offsets adjust. Recovery is automatic when signal clears." But the brainstorm does not specify what adjusts the offsets in response to a Tier 1 INFORM from weight_drift detection.

The loop reads outcome data from interstat/interspect, detects drift, and emits a signal. For this to be a feedback loop rather than just monitoring, something must respond to the signal by adjusting policy — either by modifying intent.yaml, by adjusting ockham_offsets, or by triggering principal review. None of these response paths is described. The Intercept integration ("distills a local model after 50+ evaluations") is the only response mentioned, and it is speculative extensibility without a concrete consumer in Phases 1-3.

Without an actuation path, the feedback loop is an alarm that fires into the void. The principal must act on Tier 1 INFORM manually, which means this is not a feedback loop — it is monitoring with a governance label. That may be the right Phase 1 design (monitoring before actuation), but it should be stated explicitly rather than presented as a closed loop.

The Intercept integration (local model distillation at 50+ evaluations) should be deferred to Wave 2 or later. Wave 1 should specify only: detect drift, emit INFORM, log to interspect, surface in `ockham health` output. The principal acts on the INFORM. Autonomous offset adjustment is Wave 2+ scope.

Severity: P2. The feedback loop as described creates an expectation of closed-loop behavior that is not architecturally wired. Naming it a "feedback loop" without an actuation path is an accuracy issue that will mislead the Wave 1 implementation scope.

---

### NEW-P3 — AGENTS.md package naming diverges from brainstorm

**Location:** `os/Ockham/AGENTS.md` package table, `os/Ockham/CLAUDE.md` structure section

Both AGENTS.md and CLAUDE.md name the fourth internal package `dispatch` (with `Scorer`, `WeightConfig`, `DispatchAdvice` types). The brainstorm renames it to `scoring`. The code directory `os/Ockham/internal/dispatch/` also uses the old name.

This is a low-severity documentation drift issue but it will generate confusion when implementation begins: the brainstorm and the authoritative module docs will disagree on the package name. Both documents should be updated to reflect the rename before Wave 1 implementation work is started.

Severity: P3. No architectural consequence yet (no code exists), but becomes a P1 friction source the moment a developer starts building.

---

## Summary

| ID | Severity | Status | Description |
|----|----------|--------|-------------|
| P0 (prior) | — | Resolved | Bead-to-theme mapping via lane labels |
| P1 (prior) | — | Resolved | Scoring package with typed input structs (naming gap noted) |
| P1 (prior) | — | Resolved | ockham_weight injection timing, bulk pre-fetch, logging |
| P1 (prior) | — | Resolved | CLI temporal model with signals.db |
| P1 (prior) | — | Resolved | Tier 3 write-before-notify ordering |
| NEW-P0 | P0 | New | Missing orchestration layer — no owner for Scoring assembly |
| NEW-P1 | P1 | New | ±12 bound crosses priority tiers (actual gap is 12, not 24) |
| NEW-P1 | P1 | New | Freeze as offset -999 conflicts with floor guard and existing lane-pause path |
| NEW-P2 | P2 | New | signals.db reconciliation contract unspecified |
| NEW-P2 | P2 | New | Feedback loop (Section 10) has no actuation path — is monitoring, not a loop |
| NEW-P3 | P3 | New | AGENTS.md/CLAUDE.md still name the package `dispatch` |

All five prior findings are resolved. Three new structural issues require attention before Wave 1 implementation: the missing orchestration layer (NEW-P0), the incorrect priority gap claim leading to an unsafe offset bound (NEW-P1), and the freeze/floor-guard conflict (NEW-P1). The remaining two new findings (NEW-P2 x2) are design completeness gaps that should be addressed in the brainstorm before it advances to a plan.
