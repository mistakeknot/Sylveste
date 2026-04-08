---
artifact_type: architecture-review
subject_prd: docs/prds/2026-04-07-fluxbench-closed-loop-model-discovery.md
bead: sylveste-s3z6
reviewer: fd-architecture (flux-drive:interflux)
reviewed: 2026-04-07
prior_review: docs/research/flux-drive/fluxbench-brainstorm-review/fd-architecture.md
---

# Architecture Review: FluxBench Closed-Loop Model Discovery PRD

## Findings Index

| Sev | ID | Feature | Finding |
|-----|----|---------|---------|
| P0 | ARCH-01 | F1/F4/F7 | FluxBench scoring entry point has no declared caller — scoring engine would be dead code without explicit wiring into the qualification run path |
| P0 | ARCH-02 | F1 | `fluxbench-score.sh` reads "qualification run output JSON" but no qualification run currently writes structured JSON output — the format contract between runner and scorer is undefined |
| P1 | ARCH-03 | F1/F2 | Circular baseline dependency partially mitigated by human-annotated fixtures (F2) but calibration script still derives thresholds from Claude baseline, not ground truth; the fixture set anchors recall but not the binary thresholds |
| P1 | ARCH-04 | F3 | Store-and-forward JSONL resolves the AgMoDB REST API problem from the brainstorm, but the sync mechanism writes to AgMoDB via git commit — `fluxbench-sync.sh` now owns a cross-repo git write that no existing interflux script has precedent for; auth and repo-access contract are unresolved open questions |
| P1 | ARCH-05 | F4 | Drift detection writes to `fluxbench-results.jsonl` (F4) and reads from `model-registry.yaml` (F1/F3), but the write path that demotes a model to `qualifying` is unspecified — F4 says "model demoted to qualifying" but names no owner for the registry mutation |
| P1 | ARCH-06 | F5 | Weekly scheduled qualification agent is a new autonomous agent execution pattern (scheduled via `clavain-cli schedule`) not present anywhere in current interflux — introduces a second dispatch path outside the flux-drive three-phase protocol, with no spec-conformance model |
| P2 | ARCH-07 | F3/F6 | Two-repo write path (interflux JSONL → AgMoDB commit → interrank snapshot) means F6's TASK_DOMAIN_MAP change has no effect until AgMoDB accepts the commit and interrank refreshes its snapshot; the PRD treats F3→F6 as a dependency but the round-trip latency (potentially days for snapshot refresh) is not acknowledged |
| P2 | ARCH-08 | F7 | Challenger slot modifies the triage scoring path ("triage allocates 1 slot") but triage logic is inside the 30K SKILL.md — the PRD's "key files" lists only `agent-roles.yaml` and `budget.yaml`, missing the actual decision point in the skill |
| P2 | ARCH-09 | F5 | `fluxbench-qualify.sh` runs candidates against F2 fixtures and then calls `fluxbench-score.sh` — this is the same scoring path as production qualification but driven by a script, not a session; LLM-as-judge for `persona-adherence` cannot run outside a Claude Code session context |
| P2 | ARCH-10 | F4 | Drift detection sampling logic ("every Nth review, shadow-run 1 active non-Claude agent") must intercept the existing cross-model dispatch shadow path; the PRD says "existing cross-model dispatch infrastructure" but that infrastructure is currently in `shadow` mode (not enforcing), making this a shadow-on-shadow dependency |
| P3 | ARCH-11 | F1 | 9-metric schema extends `model-registry.yaml` with 6 new fields alongside the 3 existing ones; the comment in the registry says fields are written by qualification scripts but no existing script performs writes — the registry is currently edit-only; the write path needs tooling |
| P3 | ARCH-12 | F6 | `TASK_DOMAIN_MAP` addition of `"fluxbench"` category to `"code review"` / `"agent"` / `"automation"` archetypes applies the domain boost to any benchmark with `category: "fluxbench"` — but the domain boost is additive to token-overlap scoring, meaning fluxbench-scored models receive a systematic advantage over equally capable models without fluxbench scores, regardless of actual performance delta |

---

## Detailed Analysis

### Context and Prior Review Delta

The brainstorm review (prior file: `fluxbench-brainstorm-review/fd-architecture.md`) raised six findings: three P1s (no AgMoDB write API, Claude circular dependency, dual source of truth) and three P2s. This PRD resolves two of those six structurally:

- **ARCH-1 (AgMoDB has no write API)**: Resolved. The PRD explicitly adopts the store-and-forward git-commit path, matching how existing scrapers ingest into AgMoDB. This is the right call — it matches the repo's existing ingest convention.
- **ARCH-3 (dual source of truth)**: Partially resolved. `model-registry.yaml` is treated as the local authoritative cache, and AgMoDB becomes the shared persistence layer for snapshot consumers (interrank). The ownership is clearer than in the brainstorm. However, the write path for demoting a model (ARCH-05 below) is still unspecified.

The brainstorm's ARCH-2 (Claude circular dependency) is addressed via F2's human-annotated fixtures but not fully resolved — see ARCH-03.

---

### P0: Wiring and Contract Gaps

**ARCH-01 — Scoring engine has no declared caller.**

PHILOSOPHY.md's "Wired or it doesn't exist" criterion states that a feature's completion bar requires "where is it called from?" answered explicitly. `fluxbench-score.sh` is described as a script that "reads qualification run output JSON" but no feature in the PRD names the thing that invokes it during a normal review session. F4 (drift detection) calls it for shadow run comparison. F5 (auto-qualification) calls it from `fluxbench-qualify.sh`. But neither F1 nor any other feature describes how FluxBench scoring gets triggered during a standard qualification run — the kind that would populate the registry for a new model going through the `candidate → qualifying → qualified` lifecycle. The acceptance criteria for F1 says "model-registry.yaml updated with FluxBench scores on qualification" but doesn't name which script or hook triggers the scoring. Without an explicit caller in the qualification path, the scoring engine can pass all its tests and never run.

Smallest fix: F1's acceptance criteria must include "called by [specific script/hook] when a qualification run completes."

**ARCH-02 — Undefined format contract between qualification runner and scorer.**

`fluxbench-score.sh` "reads qualification run output JSON" — but examining the existing infrastructure, qualification runs today produce peer-findings JSONL (`findings-helper.sh`) and agent output markdown files, not a structured JSON blob. The format of this input JSON is undeclared in F1's acceptance criteria. Without a schema, the scorer cannot be implemented independently of the qualification run, and F2 (calibration baseline) cannot be written against it. This is a hidden blocking dependency within Phase 1.

Smallest fix: F1 must define the input schema for `fluxbench-score.sh` (field names, types, source) before F2 can proceed. The two features are listed as independent (F2 has no dependency on F1) but F2's calibration script calls F1's scorer.

---

### P1: Boundary Violations and Unspecified Ownership

**ARCH-03 — Threshold derivation still circular even with human-annotated fixtures.**

F2 correctly introduces human-annotated ground-truth fixtures to break the Claude-as-reference monoculture. This addresses the brainstorm's ARCH-2 at the recall dimension: whether a model finds the same findings as Claude is replaced by whether a model finds the human-annotated findings. However, F1's acceptance criteria specify concrete threshold values (format-compliance >=95%, finding-recall >=60%, false-positive-rate <=20%, severity-accuracy >=70%) as pre-set constants. F2's calibration script is described as computing "threshold baselines" but F1 has already hardcoded the thresholds. The calibration result has no mechanism to update F1's gate values — F2 becomes measurement-only, not calibration-active. The four-stage closed-loop pattern from PHILOSOPHY.md requires stage 3 (calibrate from history) to feed back into stage 4 (defaults become fallback). As designed, stages 1-2 are implemented, stages 3-4 are not.

Smallest fix: F1's thresholds must be declared as configurable defaults in `fluxbench-metrics.yaml`, readable by `fluxbench-calibrate.sh`, and overridable by its output. The hardcoded values become fallbacks, not gates.

**ARCH-04 — Cross-repo git write is new territory for interflux.**

The store-and-forward pattern is architecturally sound. But `fluxbench-sync.sh` committing to the AgMoDB repo requires: (a) the AgMoDB repo to be cloned locally or accessible by path, (b) git credentials for a non-interflux repo, (c) a conflict resolution strategy when two interflux instances sync concurrently. None of the existing interflux scripts perform cross-repo git writes. Open Questions 1 ("SSH key or token? Who owns the AgMoDB repo pipeline?") acknowledges the auth gap, but the PRD treats this as implementation detail rather than an architectural constraint that shapes the design.

If AgMoDB is maintained by a separate team or org, the sync script becomes an integration seam with external governance. The PRD should specify whether interflux pushes to a fork/PR or directly to main, and what happens when the sync fails (orphaned local results, retry backoff, alerting). The acceptance criterion "sync script idempotent — re-running doesn't duplicate entries" is necessary but not sufficient — it handles the re-run case but not the concurrent-write case.

**ARCH-05 — Registry mutation on drift demotion has no owner.**

F4's acceptance criteria states "drift flag: any core metric drops >15% from qualified baseline → model demoted to `qualifying`." This mutation must write to `model-registry.yaml`. But `fluxbench-drift.sh` (the new script listed in F4's key files) is a detection script. It writes to `fluxbench-results.jsonl` with the drift event. The registry write is not attributed. Neither `session-start.sh` (which does the version comparison) nor `fluxbench-drift.sh` is specified to own the `status: qualifying` write. This means the drift flag exists in the JSONL but the model continues dispatching at production status until someone reads the flag and updates the registry — which is nowhere described.

This is a boundary violation: the detection script and the registry mutation belong to the same state machine transition, but the PRD splits them across two artifacts without naming the bridge. In a system that produces evidence and earns authority from it, a detection event that doesn't change system behavior is observation without action — the Reflect step without Compound.

**ARCH-06 — Scheduled qualification agent bypasses flux-drive protocol.**

F5's weekly scheduled agent runs `discover-models.sh` and `fluxbench-qualify.sh` outside a user-initiated session. This is a new autonomous execution pattern: a cron-triggered agent that dispatches LLM calls, writes to JSONL, and promotes models. The flux-drive spec (v1.0.0, `docs/spec/`) defines three conformance levels, none of which describe autonomous scheduled qualification. The scheduled agent operates outside the three-phase triage/launch/synthesize lifecycle, has no budget constraint specified, no phase gate before auto-promotion, and no synthesis step. Auto-promoting a candidate to `qualified` based on automated scoring alone is a trust-level jump that the existing spec would consider a level-skip.

The PRD's safety hedge ("creates bead if any candidate qualifies for human awareness") is notification after the fact, not a gate before promotion. Given that PHILOSOPHY.md places the system at "Level 1-2" autonomy (human approves at phase gates / reviews evidence post-hoc), auto-promotion without a gate is above the current operating level.

Smallest fix: candidates that pass auto-qualification should be promoted to a new intermediate status (e.g., `auto-qualified`) pending human review via bead, not directly to `qualified`. The distinction is one field value, but it preserves the trust ladder.

---

### P2: Integration Seams and Hidden Dependencies

**ARCH-07 — Snapshot round-trip latency is invisible to F6.**

F3 → F6 is listed as a hard dependency: FluxBench data must exist in the snapshot before F6's TASK_DOMAIN_MAP can surface it. But the data path is: interflux JSONL → `fluxbench-sync.sh` git commit → AgMoDB build pipeline → new snapshot release → interrank snapshot refresh (default: 5-minute poll per interrank's `--refresh-ms` flag). The git commit to AgMoDB snapshot generation step has undefined latency — it depends on AgMoDB's CI/release cadence, which could be hours or days. During this window, FluxBench-scored models exist in the local registry but are invisible to interrank queries. F5's awareness hook ("surface new models not in registry") queries interrank and would miss locally-qualified models. The PRD's architecture diagram treats the AgMoDB commit as instantaneous; the latency window needs a degradation strategy.

**ARCH-08 — Challenger slot wires into SKILL.md, not the files listed.**

F7's key files are `agent-roles.yaml` (challenger tier) and `budget.yaml` (challenger config). But the triage logic that "allocates 1 slot to highest-FluxBench-scoring qualifying model" runs inside the flux-drive SKILL.md — specifically inside Step 1 (triage), which is a 30K instruction file. The PRD's listed key files do not include `SKILL.md` or `SKILL-compact.md`, creating a gap: an implementer following the key files list would modify the YAML configs but leave the triage step unchanged, and no slot would be allocated.

This is scope underspecification, not a design error — but it risks the feature being delivered in the YAML without being wired into the behavior.

**ARCH-09 — LLM-as-judge persona scoring cannot run in a script context.**

F1 specifies `persona-adherence` as a core gate metric using "LLM-as-judge (Haiku)" as the scoring method (confirmed in Non-goals: "Persona adherence heuristic proxy: LLM-as-judge (Haiku) is the scoring method. No cheaper heuristic for v1."). F5's auto-qualification runner (`fluxbench-qualify.sh`) calls `fluxbench-score.sh` to score candidates. This call happens from a scheduled cron-triggered agent. The Haiku LLM-as-judge call inside `fluxbench-score.sh` requires a Claude Code session context to dispatch an Agent tool call — a shell script cannot invoke an LLM judge directly. The scoring script either needs an explicit MCP or API call mechanism (which is not described), or `persona-adherence` cannot be computed in the auto-qualification path.

This is an integration seam failure: F1 and F5 are listed as dependent only in one direction (F5 depends on F1), but the execution context assumption of F1 (Claude Code session) conflicts with F5's execution context (scheduled script).

**ARCH-10 — Shadow-on-shadow: drift detection depends on a shadow-mode feature.**

F4 states it depends on "existing cross-model dispatch infrastructure." Examining `budget.yaml`, `cross_model_dispatch.mode` is currently set to `shadow` — meaning dispatch tier adjustments are logged but not applied. F4's sample-based drift detection proposes to "shadow-run 1 active non-Claude agent against Claude baseline" using this infrastructure. But if cross-model dispatch is in shadow mode, there are no active non-Claude agents in production to drift-detect. The PRD implicitly assumes cross-model dispatch will be moved out of shadow mode before F4 is useful, but this dependency is not stated and no feature in the delivery order captures it.

---

### P3: Low-Risk Issues Worth Noting

**ARCH-11 — model-registry.yaml is currently edit-only; no write tooling exists.**

The registry comment says fields are "populated automatically by scripts/discover-models.sh" and "editable manually." But `discover-models.sh` outputs MCP query specs, not registry writes — it explicitly says "outputs queries for the orchestrator to execute." The actual registry merges are done manually or by an unimplemented orchestrator step. F1 adding 6 new fields and F4 adding status mutations assumes write tooling that doesn't exist yet. This is not a blocker (yq writes are straightforward) but the registry write responsibility should be assigned to a specific script, not left implicit.

**ARCH-12 — TASK_DOMAIN_MAP boost creates a systematic advantage for fluxbench-scored models.**

Adding `"fluxbench"` to the affinity list for `"code review"`, `"agent"`, and `"automation"` means any benchmark with `category: "fluxbench"` receives a `DOMAIN_BOOST = 2` on top of token-overlap scoring. This boost applies regardless of the benchmark's actual score for the model — it rewards having FluxBench coverage, not having good FluxBench scores. A model with a passing FluxBench score (61% recall, just above the gate) would outscore a model with excellent non-FluxBench benchmarks for the same query. The intent is correct (surface FluxBench-relevant models), but the implementation should gate the boost on the benchmark score itself, not just category membership.

---

## Delivery Order Assessment

The PRD's Phase 1 (F2 → F1 → F3) is correctly sequenced. Phase 2 (F4 + F5 in parallel) has the ARCH-10 cross-model dispatch shadow dependency making F4 lower-value than stated. Phase 3 (F6 + F7) is correct in isolation but F6's value is gated on the AgMoDB snapshot round-trip (ARCH-07).

The highest-risk delivery gap: F1 and F2 are listed as having no mutual dependency ("F2 can start independently"), but F2's calibration script calls F1's scorer, and F1's input schema must exist before F2 can be written. Treat these as a coupled unit, not independent parallel tracks.

---

## Must-Fix vs Optional

**Must-fix before implementation:**
- ARCH-01: Name the caller that triggers `fluxbench-score.sh` in the qualification path (F1 acceptance criteria)
- ARCH-02: Define the input schema for `fluxbench-score.sh` — needed for both F1 and F2 to proceed independently
- ARCH-05: Assign ownership of the registry status mutation on drift detection (F4)
- ARCH-06: Add an `auto-qualified` intermediate status to preserve the trust ladder before full `qualified` promotion

**Should-fix before F5/F7:**
- ARCH-09: Resolve LLM-as-judge execution context for scheduled auto-qualification
- ARCH-08: Add SKILL.md to F7's key files list so triage step wiring is not missed

**Optional / can defer:**
- ARCH-03: Make thresholds configurable defaults (correct direction; deferrable if thresholds are treated as v1 starting points with explicit calibration bead)
- ARCH-04: Document sync failure and concurrent-write behavior (needed before production use, not before implementation)
- ARCH-07: Add degradation strategy for snapshot latency window (needed before F5 awareness hook ships)
- ARCH-10: Acknowledge cross-model dispatch shadow-mode as a prerequisite for F4 real utility
- ARCH-11: Assign registry write ownership to a specific script
- ARCH-12: Gate TASK_DOMAIN_MAP boost on benchmark score threshold, not category membership alone

<!-- flux-drive:complete -->
