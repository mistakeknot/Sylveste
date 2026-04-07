---
review_type: flux-drive
target: docs/plans/2026-04-07-auraken-skaffen-migration.md
reviewed_at: '2026-04-06'
agent_count: 16
agents_triaged: 12
agents_dispatched: 12
prior_reviews: 2 (brainstorm, PRD)
p0_count: 2
p1_count: 7
p2_count: 5
verdict: CONDITIONAL PASS — 2 P0s must be resolved before execution begins
---

# Flux-Drive Review: Auraken-to-Skaffen Migration Plan

## Review Parameters

- **Target:** 23 tasks across 4 phases (Phase 0: Prerequisites, Phase 1: Go Packages, Phase 2: Skaffen Integration, Phase 3: Transport Migration, Phase 4: Decommission)
- **Focus:** Task decomposition, dependency correctness, acceptance criteria completeness, risk gaps, phase gate feasibility
- **Prior reviews:** Brainstorm (flux-review, all P0s resolved), PRD (flux-drive, all P0s resolved)
- **Agent pool:** 16 project-specific agents from 4 distance bands (adjacent: 5, orthogonal: 4, distant: 4, esoteric: 3)
- **Agents triaged in:** 12 of 16 (4 excluded as out-of-scope for plan-level review: fd-muisca-tumbaga-depletion-gilding, fd-noh-kata-hana-emergence overlaps with fd-orgelbau; fd-ethiopian-gult-tenure-layering overlaps with fd-data-migration-identity; fd-thangka-iconometric-proportion overlaps with fd-python-go-migration-fidelity)

## P0 Findings (Must Fix Before Execution)

### P0-1: Schema Column Names Mismatch Source (fd-data-migration-identity, fd-archival-records-schema-migration)

Task 3.2 specifies `valid_to TIMESTAMPTZ` and `expired_at TIMESTAMPTZ` for the `preference_entities` target schema. The actual Auraken source schema (`apps/Auraken/src/auraken/models.py`, line 143) uses `valid_until` — not `valid_to`. There is no `expired_at` column in Auraken's schema at all. The plan invents columns that don't exist in the source.

**Impact:** Migration script (Task 3.3) built against the wrong column names will either fail silently (NULL columns) or require rework. Bi-temporal semantics depend on these columns being mapped correctly.

**Fix:** Update Task 3.2 to reference the actual Auraken column names (`valid_from`, `valid_until`) and decide whether to add `expired_at` as a new Intercom-only column (with migration logic to derive it) or mirror the source schema.

### P0-2: Missing Tables in Migration Scope (fd-data-migration-identity, fd-clinical-trial-site-transfer)

Task 3.2 lists 6 target tables: `users`, `transport_identities`, `preference_entities`, `profile_episodes`, `working_profiles`, `style_fingerprints`. The actual Auraken schema has 9 tables (8 listed in models.py docstring + `lens_usage`):

- **`core_profiles`** — contains `style_fingerprint` as JSONB and `structured_prefs`. Plan mentions `style_fingerprints` as a separate table but Auraken stores fingerprints inside `core_profiles.style_fingerprint` (JSONB). These need extraction, not direct copy.
- **`sessions`** — conversation history with JSONB messages. Not mentioned in migration scope.
- **`lens_usage`** — lens selection and engagement events for adaptive evolution (EMA effectiveness). Not mentioned anywhere in the plan.
- **`profile_embeddings`** — mentioned only as "check pgvector availability; if not available, omit" but no explicit migration step.

**Impact:** Missing `lens_usage` means the Go lens selector starts with zero effectiveness history — the adaptive evolution system resets to cold-start for all users. Missing `sessions` means conversation history is lost. Missing `core_profiles` extraction means style fingerprints need to be rebuilt from scratch.

**Fix:** Add explicit migration decisions for each table: migrate, derive, or intentionally reset with documented rationale. At minimum, `lens_usage` and `core_profiles.style_fingerprint` need migration tasks.

## P1 Findings (Fix Before Phase Start)

### P1-1: Task 2.1 Scope Exceeds 1-3 Hour Budget (fd-persona-prompt-architecture, fd-orgelbau-tonal-transplantation)

Task 2.1 "Implement context provider interface in Skaffen" requires 7 steps including: designing a new interface, implementing a provider registry, implementing a caching layer with invalidation, implementing token budgeting with overflow, and implementing a composition step with dependency declaration. The current Skaffen `agent.go` has no ContextProvider concept — `Session.SystemPrompt()` returns a static string. This task is designing and building a new subsystem from scratch.

**Evidence:** `os/Skaffen/internal/agent/deps.go` line 42 shows `SystemPrompt(phase tool.Phase, budget int) string` — a simple string return with no provider pipeline. Task 2.1 needs to replace this with a multi-provider composition pipeline.

**Fix:** Split into two tasks: (a) Design + implement ContextProvider interface and registry (2h), (b) Implement caching, token budgeting, and composition (2h).

### P1-2: Task 2.2 Has 7 Context Providers — Should Be 2+ Tasks (fd-persona-prompt-architecture)

Task 2.2 implements 6 named context providers (Lens, Profile, Style, Steering, Feedback, Session) plus wiring and validation. Each provider requires reading the corresponding Auraken prompt section, implementing the Go provider, and testing parity. This is at minimum 6 distinct implementations plus integration work.

**Fix:** Split into: (a) Implement core providers (Lens, Profile, Style) with parity tests (2-3h), (b) Implement auxiliary providers (Steering, Feedback, Session) + wiring + validation (2-3h).

### P1-3: Phase 1 Parallelism Assumption Not Validated — Now Resolved (fd-togishi-sword-polishing-sequencing)

The plan states "Tasks within Phase 1 can run in parallel" with a note: "check if extraction depends on fingerprint's StyleProfile — if so, build fingerprint first." This review verified: `apps/Auraken/src/auraken/extraction.py` does NOT import or reference StyleProfile, style.py, or fingerprint. **The parallel assumption is correct.** However, the plan should remove the hedging note and state this definitively.

**Fix:** Remove the "Exception: check if extraction depends on fingerprint's StyleProfile" note from Phase 1 header and state: "Verified: extraction has no dependency on fingerprint. All Phase 1 packages are independently buildable."

### P1-4: Dependency Graph Shows 2.1-2.6 as Parallel But Text Says Sequential (fd-togishi-sword-polishing-sequencing)

The plan text says "Sequential: F5 (prompt builder) -> F6 (persona config) -> F7 (analysis mode)" but the ASCII dependency graph shows Tasks 2.1-2.6 all terminating at the same point with no intra-phase ordering. The graph contradicts the text.

**Evidence:** Lines 477-482 show all Phase 2 tasks as parallel branches, but line 189 says "Sequential."

**Fix:** Update the dependency graph to show: 2.1 -> 2.2 -> 2.3 -> 2.4, and 2.5 -> 2.6 (Inspector before /analysis). These two chains can be parallel with each other.

### P1-5: No Task for Skaffen `pkg/` Directory or `go.mod` Updates (fd-go-package-api-design)

Task 1.1 says "Create package directories under `os/Skaffen/pkg/`" but `os/Skaffen/pkg/` doesn't exist yet. The task also says "Update `os/Skaffen/go.mod` if needed" but the packages will need shared types (`Message`, `Entity`). The current `go.mod` module is `github.com/mistakeknot/Skaffen` — adding a `pkg/types/` package is a meaningful design decision (what goes in shared types vs. per-package types) that deserves explicit acceptance criteria.

**Fix:** Add acceptance criterion to Task 1.1: "Shared types package (`pkg/types/`) defined with `Message`, `Entity`, `StyleProfile`, `Delta` structs reviewed for minimal coupling."

### P1-6: Task 3.3 Migration Script Assumes Both Databases Are Postgres — No Connection Details (fd-clinical-trial-site-transfer)

Task 3.3 says "Connect to both Auraken Postgres and Intercom Postgres" but provides no details on connection handling. Auraken runs on sleeper-service (per Auraken CLAUDE.md deployment section), while Intercom's Go instance may run elsewhere. Cross-host database access needs firewall/network config.

**Fix:** Add a prerequisite step to Task 3.3: verify network connectivity between migration host and both Postgres instances. Document connection strings or environment variables needed.

### P1-7: Phase 3->4 Gate Has Unmeasurable "30 days" Criterion (fd-togishi-sword-polishing-sequencing, fd-broadcast-signal-migration)

The gate criterion "30 days Skaffen-only operation with <1% behavior regression" lacks measurement specification. What counts as "behavior regression"? How is it measured? Who decides? The plan mentions no monitoring, alerting, or comparison methodology.

**Fix:** Define behavior regression measurement: e.g., "lens selection top-3 agreement with Auraken baseline > 99% on daily sample of 10 conversations, measured by running both systems in shadow mode." Add monitoring task to Phase 3.

## P2 Findings (Improve Before Task Start)

### P2-1: Task 0.1 Fixture Count May Be Insufficient (fd-python-go-migration-fidelity)

20 messages across 7 conversation modes means ~3 messages per mode. For property-based parity testing of a 291-lens selector, 20 fixtures may not exercise enough of the selection space. The lens graph has 7 communities — some may not be triggered.

**Fix:** Consider 5 messages per mode (35 total) with explicit community coverage requirement.

### P2-2: Task 1.2 Acceptance Criterion "Identical Top-3" May Be Overly Strict (fd-python-go-migration-fidelity, fd-orgelbau-tonal-transplantation)

The lens selector calls Haiku for structured output. LLM responses are inherently non-deterministic even with temperature=0. Requiring "identical top-3 for all 20 fixture messages" may produce false failures if the Go implementation routes to a different Haiku version or uses slightly different prompt formatting.

**Fix:** Distinguish between deterministic components (graph traversal, sort stability) and LLM-dependent components (Haiku selection). Test them separately. For Haiku-dependent selection, use recorded Haiku responses in fixtures rather than live calls.

### P2-3: No Rollback Task in Phase 3 (fd-broadcast-signal-migration, fd-clinical-trial-site-transfer)

Task 4.1 documents rollback triggers but there's no explicit task for building rollback capability. Rollback from Intercom transport back to Auraken requires: re-routing traffic, re-enabling Auraken write mode, replaying any Intercom-only data back. This is non-trivial and should be designed before migration starts.

**Fix:** Add Task 3.0 or extend Task 3.5: "Implement and test rollback procedure." Include a drill/dry-run of rollback.

### P2-4: Task 2.5 Inspector Scope Unclear Relative to Skaffen's Evidence System (fd-analysis-mode-design)

Skaffen already has an `evidence/` package, an `Emitter` interface, and an `evidenceDir` field on Agent. Task 2.5's Inspector needs to integrate with these existing systems, not create parallel ones. The task doesn't reference the existing evidence infrastructure.

**Fix:** Add step to Task 2.5: "Read `os/Skaffen/internal/evidence/` and integrate Inspector with existing evidence emission patterns."

### P2-5: Task 1.6 Integration Test May Not Catch Real Issues (fd-go-package-api-design)

Using a mock provider means the integration test never exercises the Haiku call path that three of four packages depend on (lens, extraction, profilegen). The test verifies package composition but not the critical LLM interaction path.

**Fix:** Add an optional integration test flag (`-integration`) that runs against a real Haiku endpoint for a small subset of fixtures.

## Risk Gaps — Tasks That Should Exist

### Missing: Monitoring and Observability Task (Phase 3)

No task covers setting up monitoring for the migration. The Phase 3->4 gate requires "30 days with <1% regression" but no task builds the measurement infrastructure. This should be a Phase 3 prerequisite.

### Missing: Shadow Mode / Dual-Run Task (Phase 2-3 Boundary)

The plan has no shadow-mode task where both Auraken and Skaffen-Auraken process the same messages for comparison. The fd-broadcast-signal-migration agent flagged this in the brainstorm review. The voicing session (Task 2.4) is manual and limited to 10 conversations — it doesn't provide ongoing automated comparison.

### Missing: `LensUsage` Migration or Cold-Start Strategy (Phase 3)

See P0-2. If lens_usage is intentionally not migrated, there should be a task documenting the cold-start strategy for the adaptive evolution system.

## Phase Gate Feasibility Assessment

| Gate | Measurable? | Feasible? | Notes |
|------|-------------|-----------|-------|
| Phase 1->2 | Yes | Yes | All criteria are concrete: parity tests, `go vet`, `staticcheck` |
| Phase 2->3 | Partially | Needs work | "behavior-parity responses in shadow mode" — no shadow mode exists. "Voicing session completed" is measurable but "documented adjustments" is vague |
| Phase 3->4 | No | Needs rework | "<1% behavior regression" has no measurement methodology. "30 days" is measurable as calendar time but the regression metric is undefined |

## Session Estimate Assessment

The plan estimates 12-19 sessions. Given the P1 findings about oversized tasks (2.1, 2.2) and missing tasks (monitoring, shadow mode, rollback), a more realistic estimate is **16-24 sessions**. Phase 2 in particular is underestimated: 6 nominally sequential tasks where two need splitting, plus the missing shadow-mode task, yields 8-10 sessions rather than 4-6.

## Summary

The plan is well-structured with clear phase sequencing, good task-level detail, and mostly correct dependencies. The two P0s are factual errors (schema column names, missing table scope) that would cause concrete implementation failures. The P1s are mostly about task scope (oversized tasks, missing acceptance criteria) and dependency graph accuracy. The plan is ready for execution after P0 resolution and P1 task splitting.
