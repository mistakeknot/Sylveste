# Architecture Review: Factory Substrate (iv-ho3)

**Reviewer:** fd-architecture (Flux-drive Architecture & Design Reviewer)
**Date:** 2026-03-05
**PRD:** `docs/prds/2026-03-05-factory-substrate.md`
**Brainstorm:** `docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md`
**Scope:** Module boundaries, coupling risks, pkg/cxdb/ abstraction adequacy, new command integration with existing sprint/gate/checkpoint infrastructure, L1/L2/L3 layer separation.

---

## Summary

The PRD is architecturally sound on its most important decision — keeping all substrate intelligence in Clavain (L2) and treating Autarch (L3) as a pure consumer. The layer separation is correctly argued, and the CXDB adoption rationale aligns with documented philosophy. Four structural concerns below require resolution before implementation begins. None are blockers that require a redesign; they are integration seams that will become costly if left ambiguous.

---

## Finding 1: pkg/cxdb/ is a flat wrapper, not an abstraction

**Priority:** Must-fix

**Finding:**
The PRD specifies a `pkg/cxdb/` package with seven functions: `Connect`, `SprintContext`, `RecordPhase`, `RecordDispatch`, `ForkSprint`, `RecordScenario`, `QueryByType`. The package is described as ~300 lines. However, the clavain-cli codebase has no `pkg/` directory at all today. All commands live as top-level `.go` files in `cmd/clavain-cli/` with no internal packages. The naming `pkg/cxdb/` implies a subdirectory package, which requires a module path change or a new `package cxdb` compilation unit that the `main` package imports.

The more substantive problem: the proposed API signature `SprintContext(beadID string) uint64` encodes both a side effect (get-or-create a CXDB context) and a lookup in a single call. If the CXDB server is unavailable at the moment this runs, the caller has no way to distinguish "server down" from "no context exists yet." The existing fail-open pattern in clavain-cli (ic unavailable → skip, bd unavailable → skip) is not replicated in the `pkg/cxdb/` API design — `Connect()` returning `(*cxdb.Client, error)` will propagate errors into every call site.

**Evidence:**
- `os/clavain/cmd/clavain-cli/go.mod` — single dependency, no `pkg/` subdirectory exists
- `exec.go:83-97` — `bdAvailable()` / `icAvailable()` pattern: both are fail-open, errors become no-ops
- `phase.go:263-267` — `enforce-gate` resolves run ID and logs "skipped — no ic run" rather than erroring
- PRD F1 states CXDB is "required infrastructure, not optional," but PRD F2 shows code that runs unconditionally on `sprint-advance`

**Recommendation:**
Resolve the required-vs-fail-open tension explicitly before writing the package. Two coherent positions:

1. CXDB is truly required (like Dolt): `Connect()` errors are fatal, `sprint-advance` fails if CXDB is down. This is the cleaner model and matches the stated philosophy, but it makes every sprint abort if the CXDB server crashes mid-run. Add a health recovery path (auto-restart on failure) to make this safe.

2. CXDB is durable-on-best-effort: `Connect()` errors are logged to stderr, the sprint continues, and a reconciliation job replays missed turns from the ic event log. This is operationally safer but requires the reconciliation logic that the PRD currently omits.

Either way, `SprintContext()` should return `(uint64, error)`, not just `uint64`. The "required" stance does not eliminate error returns — it changes what callers do with them.

---

## Finding 2: Dual recording creates a divergence seam between ic state and CXDB

**Priority:** Must-fix

**Finding:**
The existing sprint infrastructure already records phase transitions and agent dispatches in Intercore (`ic run advance`, `ic run agent add`). The PRD adds parallel recording of the same events into CXDB (`clavain.phase.v1`, `clavain.dispatch.v1`). This creates two canonical sources for sprint history that will drift.

Concretely: `sprint-advance` in `phase.go:102-192` calls `runIC("run", "advance", runID)`, which is the authoritative state transition. The PRD adds a CXDB write alongside it. If the ic write succeeds and the CXDB write fails (or vice versa), the two stores disagree on what happened. `cmdRecordPhase` (`phase.go:352-358`) currently is a no-op beyond cache invalidation because ic records the event itself. Adding CXDB recording here introduces a second write that has no reconciliation path if it lags or fails.

The existing handoff contract validation already demonstrates this risk: `checkHandoffContracts()` in `handoff.go:645-689` calls `runICJSON` to get the artifact list, then reads files from disk. These are already two data sources. Adding CXDB as a third recording layer multiplies the consistency surface.

**Evidence:**
- `phase.go:184-191` — `sprint-advance` success path: invalidate caches, record phase tokens, print transition. No error return from either side-effect call.
- `phase.go:351-358` — `cmdRecordPhase` is currently a one-liner (invalidate caches). CXDB recording bolted here doubles its responsibility.
- `sprint.go:387-418` — `sprint-track-agent` writes to ic. CXDB dispatch recording is proposed alongside this same call point.
- PRD F2 AC: "Any sprint is reconstructable from its CXDB context" — but this is false if ic is the source of truth for phase transitions and CXDB only records what it successfully receives.

**Recommendation:**
Define a single canonical source for sprint history and derive the other. Two options:

1. CXDB is derived from ic: Add a background reconciliation job that replays `ic run events` into CXDB on session start. CXDB becomes a queryable projection of ic state, not a write peer. This is safe because ic already has durable storage; CXDB adds indexing and forking.

2. CXDB is primary, ic is derived: Sprint advance calls CXDB first (appending the turn), then calls ic as a sync operation. If ic fails, the sprint rolls back. This flips the current dependency but requires the CXDB → ic sync path.

Option 1 is the lower-risk migration path. It lets CXDB adoption be incremental — a replay job can backfill historical sprints — and keeps the existing ic gate infrastructure as the single gating authority. Option 2 is architecturally cleaner long-term but requires a full ic dependency inversion.

If dual-write is chosen anyway (not recommended), the implementation MUST include a write ordering contract (ic first, CXDB second, CXDB failure is non-fatal) and a discrepancy detection query.

---

## Finding 3: Satisfaction gate lacks a fallback path for the closed-loop calibration requirement

**Priority:** Must-fix

**Finding:**
F4 adds a gate rule: "sprint cannot advance to Ship unless holdout satisfaction >= configurable threshold (default: 0.7)." PHILOSOPHY.md's "Closed-loop by default" section explicitly requires four stages for any system that makes judgments: hardcoded defaults → collect actuals → calibrate from history → defaults become fallback. The PRD ships stages 1 and 2 (hardcoded 0.7, satisfaction scores recorded) but not stages 3 and 4. PHILOSOPHY.md explicitly states: "If you ship stages 1-2 without 3-4, you've built a constant masquerading as intelligence."

The satisfaction threshold is exactly the type of judgment PHILOSOPHY.md cites in the gate threshold row of its calibration table: "Gate thresholds → phase gate hardness → false-positive/negative rates → threshold tuning from outcomes." Stage 3 (reading past scores to calibrate the threshold) and stage 4 (0.7 becoming the fallback when history is absent) are missing from the PRD's acceptance criteria.

The Open Questions section acknowledges this: "Default 0.7 — should this follow the closed-loop pattern?" The answer from PHILOSOPHY.md is unambiguous: yes, it must. This is not optional cleanup.

**Evidence:**
- `PHILOSOPHY.md:58-76` — closed-loop by default, four stages, gate thresholds row in the calibration table
- PRD F4 AC — no calibration command, no "calibrate-satisfaction-threshold" analogous to `calibrate-phase-costs`
- `budget.go` (inferred from `main.go:47`) — `calibrate-phase-costs` is the existing existence proof for this pattern

**Recommendation:**
Add a fifth acceptance criterion to F4: `clavain-cli scenario-calibrate` reads historical satisfaction run results from `.clavain/scenarios/satisfaction/`, computes the p50 pass rate, and writes a calibrated threshold to `.clavain/config/satisfaction.yaml` (or the equivalent config path). The gate reads from this file, falling back to 0.7 when the file is absent or has fewer than N runs (same threshold the phase cost calibration uses for its minimum-run guard). This is roughly 80 lines of Go — a calibrate-phase-costs sibling. It is not scope creep; it is completing the pattern the PRD already partially implements.

---

## Finding 4: Policy enforcement is not integrated with the existing gate machinery

**Priority:** Should-fix

**Finding:**
F6 adds `policy-check <agent> <action>` as a standalone command and states "Policy enforcement integrated into `enforce-gate`." However, `enforce-gate` in `phase.go:225-280` has a clear call chain: CLAVAIN_SKIP_GATE check → handoff contracts (load-agency-spec, check-handoff-contracts) → ic gate check. The PRD does not specify where in this sequence policy enforcement is inserted, what the error semantics are (does a policy violation block the gate or just log?), or how policy violations interact with the existing `CLAVAIN_SKIP_GATE` escape hatch.

The PRD states "Policy violations recorded as CXDB turns (`clavain.policy_violation.v1`) for audit" but the scenario where `CLAVAIN_SKIP_GATE` is set is unaddressed. If SKIP_GATE bypasses policy checks, it becomes a vector for policy evasion. If SKIP_GATE does not bypass policy, then the existing code path at `phase.go:233-235` must be updated to not return early before the policy check runs.

Additionally, the holdout enforcement mechanism is described as "clavain-cli policy-check that gates tool dispatch" but tool dispatch in Clavain happens through agent invocations (ic agency, flux-drive), not through a centralized dispatch point that clavain-cli controls. The policy check would need to be called by each dispatching hook rather than at a single enforcement point. There is currently no centralized agent dispatch layer in clavain-cli that could intercept all dispatches.

**Evidence:**
- `phase.go:225-280` — `cmdEnforceGate` has no policy check call; no hook point for policy insertion is defined
- `phase.go:233-235` — `CLAVAIN_SKIP_GATE` returns early before any other checks run, policy check would be silently bypassed
- `sprint.go:387-417` — `sprint-track-agent` records dispatches after the fact; no pre-dispatch policy gate exists
- PRD F6 AC: "Implementation agents blocked from reading `.clavain/scenarios/holdout/` during Build phase" — agents can read any file they can access; clavain-cli has no capability to intercept file reads at the OS level

**Recommendation:**
Scope F6 more narrowly in v1. The filesystem-level holdout enforcement ("agents cannot read holdout/") is not achievable via a clavain-cli `policy-check` command alone — that requires either OS-level sandboxing (outside scope) or trust that agents honor the policy prompt injection. Rename the enforcement model from "blocked from reading" to "holdout directory excluded from context injection" (i.e., the SessionStart hook does not include holdout scenarios in the additionalContext). This is achievable today, does not require `policy-check`, and is honest about the actual enforcement boundary.

The `policy-check` command remains useful for audit and soft enforcement: dispatchers call it, log violations to CXDB, and continue unless a hard policy flag is set. Define the `enforce-gate` integration point explicitly: policy check runs after the handoff contract check, before the ic gate check, and CLAVAIN_SKIP_GATE is renamed to CLAVAIN_SKIP_GATE to include policy (or policy has its own CLAVAIN_SKIP_POLICY escape that is audited separately).

---

## Finding 5: CXDB binary distribution is an unresolved infrastructure dependency with build coupling risk

**Priority:** Should-fix

**Finding:**
The PRD identifies in Open Questions that StrongDM does not publish pre-built CXDB binaries. The proposed solution is to build from source and cache the binary. This means the Clavain setup flow gains a dependency on a Rust toolchain that no existing part of clavain-cli setup requires. The existing Dolt binary is distributed as a pre-built binary from DoltHub; users do not need a Go toolchain to use it. Requiring Rust compilation during setup is a qualitatively different user-facing requirement.

If StrongDM publishes releases before this ships, the problem goes away. If they do not, the setup flow must either vendor a compiled binary (per-platform: linux/amd64, linux/arm64, darwin/arm64 minimum) or add a `cargo build` step that will fail on machines without Rust.

**Evidence:**
- PRD Open Question 1: "StrongDM doesn't publish GitHub releases yet. May need to build and cache."
- Brainstorm: "Pre-built binary distribution (not compiled from source by users)" — stated as a design property, contradicted by reality
- PRD F1 AC: "Pre-built `cxdb-server` binary distributed via Clavain setup flow" — the mechanism for this is undefined

**Recommendation:**
Gate F1 on binary availability before writing the setup integration. Three ordered options:
1. Contribute a GitHub Actions release workflow to the CXDB repo (brainstorm Open Question 1). If StrongDM merges it, the problem is solved upstream.
2. Build and vendor platform-specific binaries in the Clavain repo under `.clavain/cxdb/bin/<os>_<arch>/`. This is auditable and reproducible without Rust toolchain on user machines.
3. Add a one-time `clavain setup` step that calls `cargo install cxdb-server` if the binary is absent. Make this explicit in the setup output, not silent.

Do not write the service lifecycle commands (F1 AC: cxdb-start, cxdb-stop) until the binary acquisition path is resolved — the lifecycle commands are meaningless without a binary to manage.

---

## Finding 6: Evidence pipeline wiring couples Interspect, Interject, and Interstat through clavain-cli

**Priority:** Low risk, track

**Finding:**
F5 wires Interspect profiler events, Interject scan findings, and Interstat token data into CXDB through clavain-cli commands. This adds new dependency edges: clavain-cli now knows about three companion plugin data formats. Today, clavain-cli depends only on `ic` and `bd` as external processes (no plugin-specific knowledge). Adding `evidence-to-scenario` that understands Interject finding schemas and `interspect-to-cxdb` that understands Interspect event schemas pulls plugin internals into the clavain-cli codebase.

This is not a current violation of the stated dependency direction (Clavain depends on plugins, not vice versa), but it is a coupling risk: every time Interject or Interspect changes their data schema, clavain-cli evidence commands must be updated in sync.

**Evidence:**
- PRD F5: "Interject scan findings convertible to scenario steps via `clavain-cli evidence-to-scenario <finding-id>`"
- `agents/architecture.md` dependency chains: `Clavain → interject` is already listed; the direction is correct but today it's via MCP/tool calls, not schema coupling in clavain-cli Go code

**Recommendation:**
Keep the evidence pipeline integration in the plugin layer rather than in clavain-cli Go code. Interject should own `interject scenario-export <finding-id>` that outputs a scenario YAML; clavain-cli `evidence-to-scenario` just invokes it and saves the output to `.clavain/scenarios/dev/`. This keeps clavain-cli as a coordinator rather than a schema translator. Same pattern for Interspect: define a `clavain.evidence.v1` schema once in a shared spec, and have Interspect write CXDB turns directly via the same Go SDK rather than routing through clavain-cli.

---

## Layer Separation Assessment

The L1/L2/L3 boundary is correctly maintained throughout the PRD.

- L1 (Intercore): ic gate check remains the authoritative gate mechanism. The PRD adds a satisfaction gate rule via the existing `enforce-gate` command, which calls `ic gate check`. No direct ic modifications are proposed.
- L2 (Clavain): All new intelligence — scenario bank, satisfaction scoring, CXDB recording, policy enforcement — lives here. The brainstorm's explicit "Autarch is a pure UI consumer" decision is architecturally correct and grounded in the Autarch vision doc.
- L3 (Autarch): Named in non-goals with correct framing ("Autarch consuming CXDB/scenario data is future work"). No L3 code is proposed.

The brainstorm's "No daemon reframed" section correctly identifies that the Intercore "no daemon" constraint is Intercore-specific, not system-wide. The system already runs Dolt, intermute, intercomd, and multiple MCP servers. Adding CXDB follows the existing infrastructure pattern.

---

## Verdict

**Proceed with implementation, addressing Findings 1-3 before code is written.**

The architecture is coherent and the layer boundaries are sound. The key risks are operational (Finding 1: required-vs-fail-open), consistency (Finding 2: dual recording divergence), and philosophical compliance (Finding 3: incomplete closed-loop calibration). All three have defined resolution paths that are smaller than the features they affect.

Suggested implementation order given the risk profile:
1. Resolve Finding 1 (fail-open vs required contract) and Finding 5 (binary distribution) before writing any CXDB code — these are preconditions for F1.
2. Implement F1 (CXDB service lifecycle) using option 1 from Finding 2 (CXDB as derived from ic) to avoid dual-write complexity in the initial release.
3. Implement F3 (scenario bank) as filesystem-only first, wiring CXDB recording after F1 is stable.
4. Add Finding 3's calibration command as part of F4 before the satisfaction gate ships — do not ship F4 without it.
5. Scope F6 (policy enforcement) per Finding 4's recommendation: context exclusion rather than capability blocking in v1.

The scenario bank + satisfaction scoring (F3 + F4) remains the right primary deliverable. Everything else enables it or follows from it.
