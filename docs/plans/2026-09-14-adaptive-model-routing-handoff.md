---
artifact_type: plan
bead: Sylveste-grez
stage: handoff
requirements:
  - F1: adaptive model routing with quality-preserving feedback
  - F2: provider-neutral usage and outcome measurement
  - F3: reversible, evidence-gated promotion
---
# Adaptive model routing: Claude Code handoff plan

> **For Claude:** start in the isolated checkout named in the current-state section, read this file completely, then use `clavain:executing-plans` when available. This handoff is intended for a manually started Claude Code session while Astra capacity is unavailable. Do not spend attempts trying to restore Astra capacity.

**Bead:** `Sylveste-grez` (parent); current child tasks are `Sylveste-1ib6`, `Sylveste-mqo4`, and `Sylveste-k7dt`.

**Goal:** complete an evidence-backed feedback loop that can tune model, effort, delegation, and concurrency across supported hosts while preserving independent acceptance, reviewer independence, durable accounting, quality floors, reversible overlays, and explicit unknowns.

**Architecture:** Clavain owns declared routing policy and activates only validated, content-hashed Interspect overlays. Intercore owns durable routing decisions, strict contracts, task-tree identity, reservations, outboxes, and promotion state. Interstat supplies raw provider-neutral usage observations; Interspect evaluates accepted outcomes and proposes scoped overlays. Host probes and real fresh-session canaries establish observed enforcement; configuration alone never proves host behavior.

**Tech stack:** Go (Intercore and Clavain CLI), Bash/Python (Clavain and Interspect hooks), SQLite/Dolt-backed Intercore state, generated JSON Schemas, zklw scheduled jobs, GitHub source/reporting. No new SaaS, provider destination, purchased capacity, or GitHub Actions workflow.

**Prior learnings:** evidence is scoped authority; a completion message, commit, green status, or producer claim is not independent acceptance. Missing usage remains null with a reason. `threadUsage` is currently unavailable, so subscription allowance savings are unknown. Preserve failed, cancelled, partial, stale, and invalid receipts. The Fable quota fallback is `claude-opus-5`; authentication, permission, timeout, and capacity failures are operational blockers, not quota events.

## Must-haves

**Truths**

- A fresh session can resolve a model from static policy or a valid calibration artifact without silently weakening a safety/frontier floor.
- A complete task tree records coordination, production, delegation, reviews, retries, repairs, cancellations, abandonments, usage observations, acceptance evidence, defects, and user corrections with exact identity joins.
- A routing candidate is compared only with matching host/provider/task/risk/repository/environment cohorts and is promoted only after quality and efficiency evidence satisfies the declared thresholds.
- Every overlay, selection, fallback, pause, rollback, and blocked promotion is explainable and content-addressed.
- Unsupported or unverified host controls remain visible and use static routing; no configuration is presented as observed host enforcement.

**Artifacts**

- Clavain calibration consumer at `/tmp/adaptive-routing-20260912/landing/Clavain` (pushed commit `4d527551fdcfd72a168e2460dfbdc66bcd8030df`).
- Intercore calibration reader and `ic route dispatch --calibration` at `/tmp/adaptive-routing-20260912/landing/intercore` (pushed commit `3f4823a99ad39e727a9dcd878ccc59e37f59f697`).
- Interspect append-only calibration writer at `/tmp/adaptive-routing-20260912/landing/interspect` (pushed commit `ebded5227f0fdedf4f28098a45c60f4fee703c54`).
- The next additive Intercore `routingfeedback` reader and generated event schema, followed by durable outcome/usage integration.
- `scripts/routing-control.py` with `status`, `explain`, `pause`, `resume`, and `rollback`.
- Host capability matrix, qualification receipts, staged experiment records, and zklw job artifacts.

**Key links**

- `Clavain scripts/lib-routing.sh` and `cmd/clavain-cli/compose.go` must use the same strict calibration semantics as `Intercore internal/routing`.
- Outcome identity must join to existing Interstat observations by exact `execution_id`, `dispatch_request_id`, `attempt_id`, session row, native IDs, and content hashes; never infer aliases.
- Interspect candidate overlays must pass through Intercore eligibility and reservation checks before Clavain can activate them.
- Independent acceptance must remain separate from execution success and from the producer/integrator identity.
- Host qualification and canary evidence must precede any default change or allowance claim.

## Current state and boundaries

The canonical source repositories were not changed. Work was performed in isolated landing checkouts under `/tmp/adaptive-routing-20260912/`:

```text
/tmp/adaptive-routing-20260912/landing/Clavain     4d52755 (origin/main)
/tmp/adaptive-routing-20260912/landing/intercore   3f4823a (origin/main)
/tmp/adaptive-routing-20260912/landing/interspect  ebded52 (origin/main)
/tmp/adaptive-routing-20260912/landing/Clavain/config/routing.yaml
/tmp/adaptive-routing-20260912/landing/Clavain/scripts/dispatch.sh
/Users/sma/projects/.task-evidence/Sylveste-grez-20260912/status.json
```

The task-local policy and dispatcher hashes used for governed receipts are:

```text
routing.yaml  8148151129e30324c18147dec516223b5e672c82dd8cd0c99bd529bd3cc98fea
dispatch.sh   834e2f3f2b4a7d158db919b3ff9bdd1729decb92080b4b53c0a642bada5b15a9
```

The selected installed Clavain cache drifted to older policy/dispatcher hashes. Do not run the broad installer, overwrite the installation, or treat the installed cache as proof of this work. Use the task-local pinned files when reproducing governed receipts.

Completed source slices:

- Clavain calibration consumer: strict duplicate/trailing/type/numeric validation, schema 1 diagnostic-only behavior, schema 2/3 propagation eligibility, mode parity, static `ic` fast-path protection, symmetric aliases, and namespaced safety-floor enforcement. The independent Fable follow-up review is `consumer-followup-review.md`; its complete receipt and hash manifest are in `/tmp/adaptive-routing-20260912/`.
- Intercore calibration kernel: strict optional artifact reader, exact threshold comparisons, schema/mode diagnostics, static fallback, and `ic route dispatch --calibration` metadata. It intentionally does not perform admission, host qualification, or promotion.
- Interspect writer: append-only, locked, atomic, duplicate-safe calibration updates with strict JSON validation.

Verification already recorded:

- Clavain calibration and affected shell suites: 293/293 passing, zero skips; rebased next-goal suites: 53 passing.
- Clavain main Go package: passing after the follow-up fixes.
- Clavain full-suite baseline issue: intermittent `gatecal.TestDrainConcurrentSafe` `SQLITE_BUSY` during concurrent schema setup, reproduced 7/30 times on unchanged baseline. Do not attribute it to the routing change or record the full suite as clean.
- Intercore affected packages, race checks, vet, build, and real CLI calibration probes passed. The unrelated full-suite `TestSpawn_ForwardsRequestedBackend` schema-version failure remains recorded against the clean baseline.
- Interspect writer tests passed (new and existing shell/Python assertions); its pre-existing interlab idempotency baseline failure remains recorded.

The additive outcome-reader design received an independent Fable design review with `VERDICT: PASS` after corrections. The first design review was excluded because the reviewer used Bash after a Read denial. The implementation task `Sylveste-k7dt` is blocked: the governed Sol backend returned `Selected model is at capacity` before editing. Retry only after observed backend availability changes or an explicit retry request. Do not repeatedly diagnose unchanged capacity with stronger-model attempts.

Independently owned task `Sylveste-e1kh` contains the usage ledger/native foundation and remains unlanded. Do not edit, cherry-pick, or take over its work. Before an importer or producer binds usage references, re-read its landed contracts and perform a fresh compatibility review.

Adaptive routing is inactive. No host is qualified, no overlay is active, no live experiment is running, no promotion/rollback canary has passed, and no subscription allowance savings are known. Preserve those states.

## Manual Claude session bootstrap

Start Claude from the isolated Intercore checkout if it still exists:

```bash
cd /tmp/adaptive-routing-20260912/landing/intercore
git status --short --branch
git log --oneline -3
```

If the temporary checkout is gone, recreate it from the pushed commit without touching the canonical Sylveste checkout:

```bash
mkdir -p /tmp/adaptive-routing-20260912/landing
git clone https://github.com/mistakeknot/intercore.git /tmp/adaptive-routing-20260912/landing/intercore
git -C /tmp/adaptive-routing-20260912/landing/intercore fetch origin main
git -C /tmp/adaptive-routing-20260912/landing/intercore checkout 3f4823a99ad39e727a9dcd878ccc59e37f59f697
```

Read these files before editing:

```text
/Users/sma/projects/Sylveste/docs/plans/2026-09-14-adaptive-model-routing-handoff.md
/tmp/adaptive-routing-20260912/outcome-implementation-plan.md
/tmp/adaptive-routing-20260912/outcome-plan-v2-review.md
/tmp/adaptive-routing-20260912/outcome-execution-decision.json
/tmp/adaptive-routing-20260912/outcome-implementation.log
/tmp/adaptive-routing-20260912/landing/intercore/contracts/registry.go
/tmp/adaptive-routing-20260912/landing/intercore/contracts/generate.go
/tmp/adaptive-routing-20260912/landing/intercore/internal/receipt/canonical.go
```

Use a fresh Claude session as the implementation producer. Keep the producer identity in the handoff receipt. After implementation, use a separate independent Claude review session or the configured Fable/Opus review seat; the implementation producer must not review its own output. Existing standing authorization covers task-relevant source and review material at the configured destinations. Do not send credentials, private prompts, source bodies, or unrelated files.

Suggested opening prompt:

```text
Read /Users/sma/projects/Sylveste/docs/plans/2026-09-14-adaptive-model-routing-handoff.md and the outcome implementation plan/review files under /tmp/adaptive-routing-20260912. Continue only Task 1 (the additive Intercore routingfeedback reader) in /tmp/adaptive-routing-20260912/landing/intercore. The previous Sol attempt was blocked before edits by capacity; preserve that failed receipt. Do not access or edit the separately owned e1kh checkout. Use TDD: add red tests, implement the strict reader, run package and schema checks, and stop before durable storage/producers. Do not modify policy, host settings, installations, or unrelated files. Do not commit or push until the parent independently reviews the frozen source. Record exact commands and failures. End with a scoped PASS/FAIL and list any unresolved gates.
```

## Ordered implementation tasks

### Task 1: Add the strict versioned outcome reader (currently blocked)

**Files:**

- Create in `/tmp/adaptive-routing-20260912/landing/intercore/internal/routingfeedback/`: typed V1 envelope, nullable wrappers, strict decoder, structural validator, canonical writer/hash, and tests. Use a package name that does not imply acceptance or authorization.
- Modify `/tmp/adaptive-routing-20260912/landing/intercore/contracts/registry.go` with one event-contract entry.
- Generate only the new `contracts/events/<outcome-name>.json`; first generate into a temporary directory and verify no unrelated schema drift.

Implement the reviewed corrections precisely:

- `DecodeOutcome(io.Reader)` must enforce a 1 MiB limit-plus-one, validate raw UTF-8, reject unpaired surrogate escapes, duplicate keys, unknown/missing fields, trailing JSON, unsupported versions, nonfinite values, quoted numbers, fractions, exponents, signs, negative zero, and integer overflow. It must invoke structural validation before returning a usable value.
- Keep ordinary missing reasons separate from parent-relationship reasons; `root` is legal only on parent fields. Nullable wrappers enforce exactly one of `value` or `missing_reason`.
- Use bounded opaque ASCII identifiers (`[A-Za-z0-9][A-Za-z0-9._:-]{0,127}`), lowercase 64-hex hashes, explicit array limits, and e1kh’s nonblank/max-256-byte external usage-observation ID exception. Never accept paths, URLs, credentials, prompts, transcripts, or free prose in references.
- Preserve distinct `execution_id`, `dispatch_request_id`, `attempt_id`, `invocation_id`, `run_id`, session row ID, native session/thread/turn/request IDs, requested vs observed provider/model/effort, host/repository/environment/checkout/configuration fingerprints, policy/profile/overlay/experiment/cohort/arm/assignment IDs, task class, and risk.
- Enforce the event-kind field matrix from `outcome-implementation-plan.md`: execution, acceptance, defect, and correction have distinct required/permitted/forbidden fields. Use `acceptance_claimed` and `validator_relationship`; do not call any field “verified”, “eligible”, “accepted”, or “authorized”.
- Keep `producer_manifest` in one dedicated nullable acceptance reference, not in the generic artifact-kind set. `supersedes` carries event ID plus SHA and is required only for correction; reject self-links and duplicate predecessors.
- Canonicalize deterministic typed UTF-8 JSON in declared struct order with minimal escaping and meaningful array order; hash exact lexical timestamps and raw external IDs. Do not claim RFC 8785 or reuse e1kh’s HTML-safe `encoding/json` canonicalizer.

**Red/green checks:**

```bash
cd /tmp/adaptive-routing-20260912/landing/intercore
go test ./internal/routingfeedback -run TestNameOfNewInvariant -count=1
go test ./internal/routingfeedback -count=1
go test ./contracts -count=1
go test ./... -count=1
go vet ./...
go test -race ./internal/routingfeedback ./contracts
```

Expected: new focused tests fail before implementation and pass afterward; the package and contract checks exit 0. If unrelated baseline tests fail, reproduce them on the pre-change commit and retain both logs. Do not call an excluded suite a pass.

Before landing, freeze the source, record a SHA-256 manifest, obtain an independent source review, verify the reviewer is not the producer, rerun tests on the frozen bytes, then commit and push directly to Intercore `main` as authorized. A remote message about PR policy is evidence to record; do not alter branch-protection settings.

### Task 2: Land usage compatibility and durable task-tree outcome storage

Do this only after `Sylveste-e1kh` lands or its exact contracts are otherwise available for fresh review. Read the landed observation and validity schemas, including their actual schema hashes; never invent an input schema version. Add append-only outcome observations, validity records, supersession, duplicate/out-of-order handling, task-tree closure, partial/cancelled/abandoned attempts, and explicit unknown reasons. Do not copy usage counters into outcomes.

Add authenticated, durable host outboxes and idempotent export/import over existing infrastructure. Transfer structured measurements and artifact references only; exclude credentials, prompts, source bodies, and transcripts. Test retries, duplicate deliveries, out-of-order sequences, overlapping sessions, stale observations, allowance resets, and invalid bindings.

### Task 3: Complete routing dispatch and explainability surfaces

Review the landed optional `--calibration` path against every existing caller. Add or finish `scripts/routing-control.py` with:

- `status`: active policy/overlay hash, measurement coverage, experiments, cohorts, quality/efficiency trends, budgets, reservations, and blocked promotions.
- `explain`: task/host/profile/overlay selection, candidate arm, exclusions, fallback reason, freshness, and unsupported controls.
- `pause`/`resume`: durable controller state with actor, reason, timestamp, and content hash.
- `rollback`: select the last valid overlay, preserve the incumbent comparison stream, and record the trigger and evidence.

All output needs human-readable and JSON forms. Static behavior must remain unchanged without a valid artifact. Test missing/stale/malformed artifacts, hash mismatch, policy drift, pause/resume/rollback idempotency, and unsupported role/host controls.

### Task 4: Add complete provider-neutral measurement and attribution

Extend Interstat integration to carry task, parent, dispatch, attempt, retry, invocation, host, requested/observed model, effort, policy, profile, overlay, experiment, cohort, and arm identities through every receipt. Measure the entire tree, including reviews, repairs, retries, coordination, and abandoned work. Keep separate execution success, independent acceptance, first-pass success, defects, required-behavior loss, user corrections, elapsed time, and usage.

Store raw input/output/cache/reasoning token categories and provider units without conversion. Store model-rate versions beside API-equivalent estimates. Missing data is null plus reason. Attribute subscription deltas only if account/window identity, freshness, overlap, and reset handling support the claim; otherwise tune on measured tokens and duration and report allowance savings as unknown.

Test malformed and partial receipts, duplicate assistant messages, cumulative/model usage reconciliation, cancellation, provider errors, missing usage, overlapping windows, and account resets. Preserve the existing e1kh parser failures and frozen candidate boundaries.

### Task 5: Build capability matrix and governed defaults

Probe Codex, Claude, Hermes, Gemini, Kimi, OpenCode, Cursor, and VS Code separately. For each host record whether model, effort, delegation, and concurrency are configurable/enforceable/observed, with version, identity, receipt, and unsupported/unverified reason. Do not claim a running parent changed models; qualify fresh sessions or explicit handoffs.

Add explicit Luna identities and governed profiles while preserving frontier classification, reviewer independence, two-strike capability escalation, and the Fable-to-Opus quota fallback. Qualify (without activating) these intended defaults:

| Work | Target default | Allowed candidate |
| --- | --- | --- |
| New Codex main | Sol high | Sol xhigh or protected frontier delegation |
| Reconnaissance | Luna medium | Luna high or Sol high |
| Bounded implementation | Luna high | Luna max or Sol high |
| Integration/consequential work | Sol high | Sol xhigh or required Astra |
| Independent Luna-output review | Sol high | existing independent validation profile |
| Frontier/unresolved complex work | Astra | preserve frontier minimum and independent review |

Start one worker. Permit direct, one-delegate, or independent parallel delegates; explore up to three only within host capacity and repository coordination rules. Never parallelize dependent mutations or remove required reviews.

### Task 6: Implement cohort experiments, admission, scoring, and reservations

Keep declared routing policy immutable. Interspect writes versioned, content-hashed overlays; Intercore validates eligibility and atomically records activation. Match host, provider, task class, risk, repository, and environment cohorts. Change one dimension at a time: model, effort, delegation, or concurrency. Keep synthetic benchmarks separate from ordinary task outcomes.

Require at least 30 completed observations per arm across five sessions plus sufficient statistical evidence. Promotion requires zero confirmed critical/high-severity candidate regressions, a one-sided 95% non-inferiority bound within one percentage point for accepted completion, and no independently confirmed loss of required behavior. Retain a seven-day delayed-defect window.

Among eligible candidates require a statistically supported 10% improvement in attributable allowance per accepted task, or measured tokens when allowance is unavailable; reject p95 completion-time regressions over 10%. Use shadow, 10% canary, 50%, then full eligible traffic while retaining 10% incumbent traffic. Promote at most once per cohort every seven days.

Reservations must cap extra Codex experiments at 5% of each applicable allowance window across concurrent hosts. Suspend experiments when the cap cannot be enforced. Other providers use declared budgets only; never purchase capacity automatically. Test concurrent reservations, release/retry, stale windows, cap exhaustion, and process crashes.

### Task 7: Add automatic rollback, blocked states, and independent monitoring

Immediately roll back on authority violation, producer/reviewer-independence failure, or confirmed critical/high-severity regression. Freeze promotion on missing evidence or policy drift and revert to the last valid overlay or static defaults. Operational blockers become durable blocked states and retry only on observed prerequisite changes or explicit retry requests.

Run evaluation and monitoring through independently scheduled zklw jobs. The controller must not modify tests, acceptance criteria, credentials, publication rules, or its own thresholds. Preserve the CI campaign overlay and existing release gates. Do not transfer workflow classes until two successful exact-commit fresh-guest executions and applicable AI/release/deployment canaries exist.

### Task 8: Qualify hosts and run the end-to-end acceptance campaign

Verify each installed host separately. Required acceptance evidence is a real task traced from route decision through governed delegation, independent acceptance, complete usage observation, and task-tree closure; a supported fresh-session model change; an observed governed delegate; and a canary showing both promotion and automatic rollback. Fixture tests alone do not qualify host enforcement or subscription savings.

Keep unavailable hosts explicitly unverified and on static routing. Do not activate defaults, overlays, experiments, or allowance claims until all required evidence is present and independently reviewed.

## Review, commit, and tracker protocol

For every source task:

1. Inspect current branch, unrelated worktree changes, immutable repository identity, and `zklw-ci status --repo OWNER/REPO --json` before changing an owned repository. Do not claim a migration if the registry/service is unavailable.
2. Read the current task-local policy and decision context. Preserve `CLAVAIN_REQUIRE_USAGE=1`, exact producer/reviewer identities, model/effort, policy hash, profile, retries, usage receipts, and outcome records.
3. Use TDD red→green for new behavior. Run focused tests first, then affected package tests, race/vet/build checks, and the relevant full suite. Retain unchanged-baseline failures separately.
4. Freeze bytes and make a manifest before review. Reviewers read source only and cannot edit, delegate, or review their own producer output. Exclude all material producers, including an integrator who materially changed a delegate’s output.
5. Commit a logical unit directly to the repository’s authorized `main`, rebase if `main` advances, verify reviewed bytes after rebase, and push. Never install or activate from an unreviewed checkout.
6. Update the existing Beads task; do not create duplicate migration tasks. A capacity/authentication/permission failure is retained as blocked and is not “fixed” by changing model or destination.

Useful tracker commands from `/Users/sma/projects/Sylveste`:

```bash
bd show Sylveste-grez --json
bd show Sylveste-1ib6 --json
bd show Sylveste-k7dt --json
bd dep list Sylveste-grez
```

The current durable status is `/Users/sma/projects/.task-evidence/Sylveste-grez-20260912/status.json`. It records inactive routing, pushed source commits, baseline failures, the excluded initial review, the design-review PASS, the blocked Sol implementation attempt, and unknown allowance savings. Update it with new evidence; do not rewrite history or delete failed receipts.

## Escalation and stop conditions

Stop and record a durable blocker when the same operational prerequisite is unchanged: unavailable model capacity, authentication, permissions, missing tracker/service, missing usage identity, stale calibration, unsupported host control, or unenforceable budget cap. Retry only after a prerequisite change or explicit retry request.

Escalate frontier review when the implementation changes quality thresholds, authority boundaries, host defaults, task-tree semantics, or any unresolved foundational invariant. A manual Claude session can implement the already reviewed bounded reader without Astra, but it must not silently redesign those boundaries or activate routing. If the work needs a new provider/destination, paid budget, policy change, installation, deployment, publication, or human acceptance decision, stop with the concrete change and the missing authority.

## Completion definition for this handoff

This handoff is complete when the next Claude session has either:

- landed and independently reviewed Task 1 with passing frozen-byte evidence, or
- preserved a new operational blocker with exact receipt and no source mutation.

The overall adaptive-routing feature is complete only after Tasks 2–8 and the real-task acceptance campaign pass. Until then, report the feature as source slices plus inactive, unqualified routing; never report model savings, host enforcement, or automatic promotion as achieved.
