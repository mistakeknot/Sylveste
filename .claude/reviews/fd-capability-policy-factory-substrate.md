# Review: Capability Policy Design — Factory Substrate PRD

**Reviewer:** fd-capability-policy
**PRD:** docs/prds/2026-03-05-factory-substrate.md (F6: Agent Capability Policies)
**Brainstorm:** docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md
**Date:** 2026-03-05

---

## 1. Enforcement Point

**Priority:** P0 — Architectural gap

**Finding:** The PRD specifies `clavain-cli policy-check <agent> <action>` as the enforcement mechanism, and the brainstorm explicitly states "Enforcement via clavain-cli policy (not filesystem permissions -- agents can read anything)." This is a cooperative enforcement model: the system asks clavain-cli whether an action is allowed, but nothing prevents an agent from calling Read/Grep/Bash tools directly to access holdout scenarios without going through `policy-check` first. Claude Code plugins cannot intercept raw tool calls.

**Evidence:**
- PRD F6 AC: "Implementation agents blocked from reading `.clavain/scenarios/holdout/` during Build phase" — but the mechanism is `policy-check`, which is advisory.
- Brainstorm section "Holdout separation": "Enforcement via clavain-cli policy... The policy is a clavain-cli `policy-check` command that gates tool dispatch."
- Existing `spec_validate_dispatch()` in `os/clavain/hooks/lib-spec.sh` (line 200) is already shadow-only — warns to stderr, returns 0 always. `capability_mode: shadow` is the current default in `agency-spec.yaml`.
- No existing mechanism in the codebase intercepts tool-level reads at the Claude Code layer.

**Recommendation:** The PRD should explicitly acknowledge that policy enforcement is cooperative (prompt-mediated), not architectural (runtime-enforced). This is acceptable for the holdout separation use case — the threat is accidental leakage during implementation, not adversarial circumvention by the agent. But the PRD should:
1. State the trust model: "Policy enforcement relies on agent compliance via clavain-cli dispatch; it does not prevent direct tool access."
2. Add a compensating control: post-hoc audit via interspect that detects holdout path access in tool call logs and flags violations retroactively. The violation recording (CXDB turns) already covers this — make it explicit as the primary detection mechanism, not just an audit trail.
3. Classify the enforcement level: "cooperative enforcement with post-hoc detection" — distinct from Gridfire's future "architectural enforcement with unforgeable tokens."

---

## 2. Phase Definitions

**Priority:** P1 — Ambiguity risk

**Finding:** The PRD says "Implementation agents blocked from reading `.clavain/scenarios/holdout/` during Build phase" and "Validation agents granted full access during quality-gates phase." These references use two different phase taxonomies without reconciling them. The existing phase system in `os/clavain/cmd/clavain-cli/phase.go` defines: brainstorm, brainstorm-reviewed, strategized, planned, plan-reviewed, executing, shipping, reflect, done. The agency-spec uses stage names: discover, design, build, ship, reflect. The PRD mixes "Build phase" (stage) and "quality-gates phase" (neither a phase nor a stage — it's a step within the ship stage).

**Evidence:**
- `phase.go` lines 16-36: phases are {brainstorm, brainstorm-reviewed, strategized, planned, plan-reviewed, executing, shipping, reflect, done}.
- `agency-spec.yaml`: stages are {discover, design, build, ship, reflect}; "executing" phase maps to "build" stage.
- PRD F6: uses "Build phase" and "quality-gates phase" without mapping to existing taxonomy.
- Nothing in the current codebase prevents an agent from self-declaring its phase. The phase is set via `sprint-advance` (which writes to intercore), but `policy-check` would need to read it — the agent itself doesn't set the phase it's checked against.

**Recommendation:**
1. Use the existing stage names from agency-spec.yaml (build, ship) in the policy schema, not ad-hoc phase names.
2. Specify that `policy-check` reads the current phase from intercore state (via `ic run` / sprint state), not from the agent's self-report. This is already how `enforce_gate` works in `lib-sprint.sh` — phase state is external to the agent.
3. Add a mapping table: which stages get which policy profiles.

---

## 3. Composition with Existing Mechanisms

**Priority:** P1 — Integration gap

**Finding:** The PRD introduces `policy.yml` as a new enforcement layer but doesn't specify how it composes with three existing overlapping mechanisms:

- **Interlock file reservations:** Already enforces per-agent file access at the path level. Policy path allowlists/denylists overlap with interlock's reserve/release model.
- **Agency-spec stage requirements:** Already declares per-stage tool requirements and capability requirements. `agency-spec.yaml` has `requires.tools` per stage and `capability_mode`.
- **Interspect profiler:** Already monitors agent behavior. Adding policy violations as a separate CXDB turn type creates a parallel audit stream.

**Evidence:**
- `agency-spec.yaml` lines 110-148: build stage already declares `requires.tools: [file_read, file_write, bash, codebase_search]` — this is an allowlist.
- `tool-composition.yaml`: already organizes tools into domains and curation groups.
- `spec_validate_dispatch()` in `lib-spec.sh` already checks agent roster against stage — this is the same concept as `policy-check`.
- Interlock's `reserve_files` / `check_conflicts` already gates file-level access.

**Recommendation:**
1. Specify whether `policy.yml` replaces, extends, or composes with agency-spec's `requires.tools` and `capability_mode`. The natural design is: agency-spec declares what a stage needs; policy.yml restricts what specific agents can do within that stage. State this explicitly.
2. Clarify the precedence: if agency-spec says build stage allows `file_read` but policy.yml denylists `holdout/**` paths, does the path restriction override the tool permission? (Yes, obviously, but it needs to be stated.)
3. Address interlock interaction: policy path denylists should be additive to interlock reservations, not a replacement. An agent could be allowed by policy but blocked by interlock (another agent holds the file), or denied by policy regardless of interlock state.

---

## 4. Schema Extensibility

**Priority:** P2 — Design gap

**Finding:** The PRD specifies `.clavain/policy.yml` with "per-agent file path allowlists/denylists and tool permissions" but provides no schema example, no versioning, and no per-project or per-scenario override mechanism. The brainstorm's scenario bank is filesystem-based with dev/holdout separation, but the policy that enforces this separation has no schema shown.

**Evidence:**
- PRD F6 AC: "`.clavain/policy.yml` schema defining per-agent file path allowlists/denylists and tool permissions" — schema mentioned but not specified.
- Brainstorm provides detailed YAML schema for scenarios but nothing for policies.
- Agency-spec already supports per-project override: "place `.clavain/agency-spec.yaml` in project root for per-project customization" (line 6). Policy should follow the same pattern.
- No mention of adding new tools or phases without code changes.

**Recommendation:**
1. Include a concrete policy.yml schema example in the PRD (even minimal). At minimum: version field, agent-level entries with path globs and tool names, phase/stage scoping.
2. Specify the override chain: default policy (shipped with clavain) -> project policy (`.clavain/policy.yml`) -> scenario-specific policy (inline in scenario YAML?).
3. Address extensibility: new tools should be deny-by-default or allow-by-default? The philosophy says "deny-by-default" is the Gridfire end state. For now, the pragmatic choice is allow-by-default with explicit denylists (matching the existing shadow-mode approach), graduating to deny-by-default as the system matures.

---

## 5. Granularity

**Priority:** P2 — Underspecified

**Finding:** The PRD says "file path allowlists/denylists and tool permissions" but doesn't address argument-level restrictions. The holdout separation use case requires path-level granularity (block reads of `holdout/**`), which is finer than tool-level (block all file reads) but coarser than argument-pattern restrictions (block writes to specific file patterns).

**Evidence:**
- PRD F6: "Implementation agents blocked from reading `.clavain/scenarios/holdout/`" — this is a path-glob restriction on the Read tool, not a blanket tool block.
- No mention of restricting specific Bash commands, specific Grep patterns, or Write targets.
- The existing `agency-spec.yaml` operates at tool-name granularity only (`file_read`, `file_write`, `bash`).

**Recommendation:**
1. Specify two granularity levels: tool-level (allow/deny entire tools) and path-level (allow/deny file paths for read/write tools). This is sufficient for the holdout use case.
2. Defer argument-pattern restrictions (e.g., blocking specific bash commands) to Gridfire's effects allowlists. The PRD should note this as a future capability, not a current requirement.
3. For path-level enforcement, specify the matching semantics: glob patterns, relative to project root, case-sensitive. Match the convention used by interlock's path patterns.

---

## 6. Violation Reporting

**Priority:** P1 — Incomplete specification

**Finding:** The PRD says "Policy violations recorded as CXDB turns (`clavain.policy_violation.v1`) for audit" but doesn't specify the agent-facing behavior when a violation occurs. Is the action silently blocked? Does the agent receive an error message? Is the human notified in real-time? The brainstorm is silent on this.

**Evidence:**
- PRD F6 AC: violations recorded to CXDB — audit only.
- Existing `spec_validate_dispatch()` warns to stderr but does not block (returns 0 always).
- `enforce_gate()` in `lib-sprint.sh` (line 802) returns 1 to block phase advancement — this is a blocking enforcement.
- No mention of real-time escalation to humans or notification via interject/intermux.

**Recommendation:**
1. Specify three violation responses, matching the `capability_mode` graduation (already in agency-spec):
   - `shadow`: Log violation to stderr + CXDB, do not block. (Current default.)
   - `enforce`: Log violation + return deny. Agent receives clear error: "Policy violation: agent X denied access to path Y during stage Z."
   - `escalate`: Log + block + notify human via interject inbox or intermux broadcast.
2. Default should be `shadow` initially, consistent with the existing `capability_mode: shadow` in agency-spec.yaml.
3. Specify that violation CXDB turns include: agent identity, requested action, denied resource, current phase/stage, policy rule that triggered, timestamp. This is the evidence needed for the "evidence earns authority" loop.

---

## 7. Philosophy Alignment: Structural vs. Moral Safety

**Priority:** P1 — Partial misalignment

**Finding:** PHILOSOPHY.md states: "Sylveste enforces structural constraints (bounded blast radius, auditable decisions, revocable authority) through architecture, not ethical reasoning." The PRD's capability policy is enforced by prompting (cooperative compliance) rather than architecture (runtime interception). This is acknowledged in the brainstorm ("not filesystem permissions — agents can read anything") but not reconciled with the philosophy.

**Evidence:**
- PHILOSOPHY.md, Earned Authority section: "Structural, not moral. Sylveste enforces structural constraints... through architecture, not ethical reasoning."
- PHILOSOPHY.md, Security section: "The end state is capability-based, deny-by-default (Gridfire: unforgeable tokens with effects allowlists and resource bounds). Today it's pragmatic layered defense."
- PRD F6: enforcement is via `policy-check` command — cooperative, not structural.

**Recommendation:** The PRD should explicitly frame capability policies as the **pragmatic layered defense** that the philosophy already acknowledges as the current approach, with Gridfire as the architectural end state. Specifically:
1. Add a "Trust model" subsection to F6 explaining: "Capability policies are cooperative enforcement — the current pragmatic layer. Architectural enforcement (runtime tool interception) requires Gridfire's capability token system, which is future work."
2. Specify the compensating controls that make cooperative enforcement sufficient today: post-hoc audit via CXDB violation turns, interspect pattern detection, human review of violation reports.
3. Note that the holdout separation threat model is "prevent accidental leakage," not "prevent adversarial exfiltration" — cooperative enforcement is appropriate for the former.

---

## 8. Implementation Phasing Risk

**Priority:** P2 — Sequencing concern

**Finding:** The brainstorm puts Agent Policies as Phase 4 (last), after CXDB adoption, Scenario bank, and Evidence pipeline. But F6 is a dependency of F3 (scenario bank's holdout separation) — the scenario bank's value proposition depends on implementation agents not seeing holdout scenarios during build. If policies ship after the scenario bank, holdout scenarios are unprotected during the gap.

**Evidence:**
- Brainstorm "Implementation Priority": Phase 2 (Scenario bank) includes "Holdout separation via policy-check," but Phase 4 is when "`.clavain/policy.yml` schema" and "`policy-check` command" ship.
- PRD F3 AC: "Scenario run results written to `.clavain/scenarios/satisfaction/run-<id>.json`" — no mention of holdout protection.
- PRD F6 AC: "Implementation agents blocked from reading `.clavain/scenarios/holdout/` during Build phase" — this is the protection.

**Recommendation:**
1. Move minimal holdout path enforcement into Phase 2 (alongside the scenario bank). A hardcoded `policy-check` that denies `holdout/**` reads during `executing` phase is sufficient — no full policy schema needed yet.
2. Phase 4 then becomes policy generalization: the full `.clavain/policy.yml` schema, per-agent customization, per-project overrides.
3. This follows the philosophy's "hardcoded defaults -> collect actuals -> calibrate from history -> defaults become fallback" pattern: start with a hardcoded holdout rule, then generalize.

---

## Summary

| # | Area | Priority | Status |
|---|------|----------|--------|
| 1 | Enforcement point — cooperative, not architectural | P0 | Must acknowledge trust model |
| 2 | Phase definitions — mixed taxonomy | P1 | Must map to existing stages |
| 3 | Composition with interlock/agency-spec/interspect | P1 | Must specify precedence |
| 4 | Schema extensibility — no example, no override chain | P2 | Should include minimal schema |
| 5 | Granularity — tool vs. path vs. argument | P2 | Should specify two levels |
| 6 | Violation reporting — agent-facing behavior unspecified | P1 | Must specify shadow/enforce/escalate |
| 7 | Philosophy alignment — cooperative vs. structural | P1 | Must frame as pragmatic layer |
| 8 | Implementation phasing — holdout unprotected in gap | P2 | Should ship minimal enforcement in Phase 2 |

**P0 count:** 1 (enforcement trust model)
**P1 count:** 4 (phase taxonomy, composition, violation reporting, philosophy alignment)
**P2 count:** 3 (schema, granularity, phasing)

---

## Verdict: SHIP_WITH_FIXES

The capability policy design is directionally correct and well-motivated by the philosophy. The cooperative enforcement model is the right pragmatic choice given that Gridfire (architectural enforcement) is future work. However, the PRD needs fixes before implementation:

**Must fix (blocking):**
- Explicitly state the trust model: cooperative enforcement, not architectural. Acknowledge the bypass path and name the compensating controls.
- Map policy to existing phase/stage taxonomy (agency-spec stages, not ad-hoc names).
- Specify violation response modes (shadow/enforce/escalate) aligned with existing `capability_mode`.
- Specify composition precedence with agency-spec and interlock.

**Should fix (non-blocking):**
- Include a minimal policy.yml schema example.
- Move holdout enforcement into Phase 2 alongside the scenario bank.
- Specify path-glob matching semantics for holdout denylists.

None of the issues require rearchitecting. The core design (policy.yml + policy-check + CXDB violation recording) is sound. The gaps are in specification completeness, not in the approach.
