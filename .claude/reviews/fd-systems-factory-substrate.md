---
artifact_type: review
reviewer: fd-systems
bead: iv-ho3
date: 2026-03-05
documents_reviewed:
  - docs/prds/2026-03-05-factory-substrate.md
  - docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md
  - PHILOSOPHY.md
---

# Systems Thinking Review: Factory Substrate PRD (iv-ho3)

## Scope

This review evaluates whether the PRD and brainstorm adequately consider feedback loops, emergence, causal chains, and systems dynamics. Implementation correctness, code style, performance, and security are outside scope and handled by domain-specific reviewers.

All findings are grounded in project terms from PHILOSOPHY.md and AGENTS.md. The OODARC model (Observe, Orient, Decide, Act, Reflect, Compound) and the closed-loop calibration pattern (defaults → collect → calibrate → fallback) are treated as authoritative standards because PHILOSOPHY.md explicitly mandates them for any system that makes predictions or judgments.

---

## Findings

---

### Finding 1 — P1 (Blind Spot): The Satisfaction Scoring Loop Is Open at the Calibration Stage

**Section:** PRD F4 "Satisfaction Scoring + Gate Integration"; Brainstorm "Satisfaction scoring"

**Lens:** Closed-loop by default (PHILOSOPHY.md); Causal Graph; BOTG

**Observation:**

PHILOSOPHY.md defines a mandatory four-stage pattern for any system that makes judgments:
1. Hardcoded defaults
2. Collect actuals
3. Calibrate from history
4. Defaults become fallback

The satisfaction scoring design ships stage 1 (default threshold of 0.7) and stage 2 (scores written to `satisfaction/run-<id>.json` and as CXDB turns of type `clavain.satisfaction.v1`). Stages 3 and 4 are absent. The PRD's Open Questions section acknowledges the calibration gap in question 5 — "should this follow the closed-loop pattern?" — and defers it without committing to it.

This means the 0.7 threshold is a constant masquerading as intelligence. PHILOSOPHY.md is explicit: "If you ship stages 1-2 without 3-4, you've built a constant masquerading as intelligence." The scores accumulate in CXDB but nothing reads them back to adjust the gate. There is no mechanism by which observed pass/fail rates feed back to recalibrate the threshold or the rubric weights.

The causal chain as designed is unidirectional: sprint runs → scenario scores → gate passes/fails → sprint ships. Without calibration, the loop never closes: sprint outcomes do not feed back into threshold or rubric. The system accumulates history it cannot use.

**Recommendation:**

Commit to the four-stage pattern explicitly, even if stages 3-4 are deferred to a follow-on bead. At minimum:
- The PRD should name a calibration mechanism (e.g., `clavain-cli scenario-calibrate` reads historical satisfaction scores and proposes threshold adjustments), even as future work
- The CXDB schema for `clavain.satisfaction.v1` should be designed now to include the fields calibration will need (actual sprint outcome post-merge, defect rate, regression count) — retrofitting schema is costly
- Open Question 5 should be converted from a question to a committed answer with a deferral bead, not left open

---

### Finding 2 — P1 (Blind Spot): Goodhart Pressure on Scenario Scores Is Unaddressed Despite Active Scenario Authoring Loop

**Section:** PRD F3 "Scenario Bank"; F5 "Evidence Pipeline"; Brainstorm "What This Enables"

**Lens:** Goodhart optimization (PHILOSOPHY.md anti-patterns); Reinforcing Feedback Loop; Emergence

**Observation:**

PHILOSOPHY.md explicitly flags this risk: "Gate pass rates are gameable. Post-merge defect rates are not." and mandates "Rotate and diversify. No single metric stays dominant. Diverse evaluation resists Goodhart pressure." It states "Goodhart pressure exists from day one."

The PRD creates a direct reinforcing loop that accelerates Goodhart pressure:

1. Sprint fails holdout gate → F5 auto-generates a new scenario from the failure
2. New scenario enters the bank (dev or holdout, depending on policy)
3. Future sprints optimize against the growing scenario set
4. Scenario bank increasingly reflects past sprint behaviors, not abstract correctness

This is not a theoretical risk — it is a structural property of the design. The scenario bank grows from sprint failures (F5), and those same scenarios gate future sprints (F4). Agents that run repeatedly across the scenario bank will, over time, develop implicit representations of what satisfies it. The scenarios are not a static holdout; they are a co-evolving target.

The brainstorm notes "self-building validation: Demarch's own scenarios become the holdout set for its own development" as a feature. From a systems perspective, this is precisely the condition that produces Goodhart collapse: the evaluator is derived from the thing being evaluated.

There is no mention of scenario rotation, scenario retirement, injection of adversarial or out-of-distribution scenarios, or any mechanism for detecting when the scenario bank has drifted toward measuring agent behavior rather than correctness.

**Recommendation:**

- Add a scenario lifecycle policy: scenarios should have an explicit creation reason (human-authored, failure-derived, adversarial-injected) and a review cadence
- Failure-derived scenarios (F5 evidence pipeline) should feed only `dev/`, not `holdout/`, by default — holdout should require explicit human promotion to preserve its independence
- Add a "scenario diversity metric" (e.g., coverage of risk_tags, scenario age distribution) that Interspect can monitor as a system health signal
- The `fd-user-product` judge used for satisfaction scoring is a fixed evaluator; rotating judge prompts or using multiple judges with disagreement scoring would apply the "disagreement is signal" principle the PHILOSOPHY mandates

---

### Finding 3 — P1 (Blind Spot): Holdout Separation Is Policy-Enforced, Not Structural — The Enforcement Loop Has No Monitoring

**Section:** PRD F6 "Agent Capability Policies"; Brainstorm "Holdout separation"

**Lens:** Hysteresis; Crumple Zones; Causal Graph

**Observation:**

The brainstorm explicitly notes: "Enforcement via clavain-cli policy (not filesystem permissions — agents can read anything)." This means the holdout is a soft boundary enforced by the `policy-check` command being called before tool dispatch. The structural constraint does not exist — it is a convention maintained by process.

The causal chain for enforcement is: agent requests tool → `clavain-cli policy-check` → allow/deny. Policy violations are recorded as CXDB turns (`clavain.policy_violation.v1`). But there is no described mechanism by which accumulated violations feed back into anything. Violations are auditable but not acted upon. A persistent pattern of violations (e.g., an agent repeatedly attempting holdout access) produces no automated response — no escalation, no gate hardening, no alert.

This creates a hysteresis problem: the first time a violation occurs is cheap to detect but the audit trail accumulates silently. By the time violations are noticed, the holdout may already be contaminated. The system cannot return from "contaminated holdout" cheaply — any scenario that has been seen by an implementation agent during Build must be treated as compromised, which means retiring those scenarios and regenerating the holdout from scratch.

There is also a pace layer mismatch: violations accumulate at the speed of sprint execution, but review of the audit trail operates at the speed of human attention. The gap between these pace layers is where silent contamination occurs.

**Recommendation:**

- Add a monitoring loop: Interspect (or a dedicated hook) should watch the violation audit trail and trigger a gate warning if violation count crosses a threshold per sprint
- Holdout contamination should be treated as a failure mode with explicit recovery instructions (which holdout scenarios to retire, how to audit which sprints ran while contaminated)
- Consider making holdout path blocking structural at the filesystem level for high-trust scenarios, with policy-check as the secondary layer — defense in depth is stated as a PHILOSOPHY principle

---

### Finding 4 — P2 (Missed Lens): CXDB as Required Infrastructure Creates a Hard Dependency With No Graceful Degradation Analysis

**Section:** PRD F1 "CXDB Adoption"; F2 "Sprint Execution Recording"; Brainstorm "Why required, not optional"

**Lens:** Pace Layers; Bullwhip Effect; Systems Dynamics (T=0, T=6mo, T=2yr)

**Observation:**

The brainstorm makes the case for CXDB being required rather than optional, and the reasoning is sound for normal operation. However, the systems dynamics of making it required are not analyzed.

At T=0: CXDB is a single binary that must be built from Rust source (no pre-built releases from StrongDM exist per the PRD's own dependencies section). Every sprint requires CXDB to be running. SessionStart auto-starts it. The blast radius of CXDB being unavailable is every sprint failing to advance.

At T=6mo: CXDB data directory has grown across dozens or hundreds of sprints. There is no defined retention policy (Open Question 3 defers this). Storage growth is unbounded and unmonitored. The brainstorm says "Interspect benefits from history" but does not model what happens when the data directory becomes large enough to affect CXDB performance, or what happens when a user's machine runs out of disk.

At T=2yr: If StrongDM deprecates or breaks CXDB (it is a 356-star open source project, not a stable dependency like SQLite), every sprint is blocked until a replacement is found. The migration path from CXDB to an alternative requires reading and replaying the entire Turn DAG into a new system. This is a hysteresis trap: once the system is deeply coupled to CXDB's data model, the cost of changing is very high.

The comparison to Dolt (beads) in the brainstorm is apt but incomplete. Dolt is maintained by DoltHub with commercial backing and stable binary releases. CXDB has no release binaries (the PRD explicitly notes this), is maintained by a team as an internal research project, and the Go SDK has limited adoption outside StrongDM.

The bullwhip effect is also present: CXDB unavailability (a small variance in a dependency) propagates upstream into sprint-wide unavailability (a large operational disruption). The amplification factor is high because CXDB is in the critical path for every sprint phase transition.

**Recommendation:**

- Define a CXDB health check circuit breaker: if CXDB is down at SessionStart, sprints should fail fast with a clear error and recovery instructions rather than silently degrading
- Define a retention policy now, even a simple one (e.g., keep last N sprints, archive older), rather than deferring — unbounded storage growth is a known failure mode
- Document the migration contract: what does the data look like, what would need to change to adopt an alternative, and what is the minimum viable replacement (even a SQLite fallback)
- Track CXDB upstream health as part of the project's dependency monitoring

---

### Finding 5 — P2 (Missed Lens): The Evidence Pipeline Runs One Direction — Failures Feed Scenarios, But Scenario Improvements Do Not Feed Agent Behavior

**Section:** PRD F5 "Evidence Pipeline"; Brainstorm "Evidence Pipeline" table

**Lens:** Reinforcing Feedback Loop vs Balancing Feedback Loop; Causal Graph; OODARC Compound phase

**Observation:**

The evidence pipeline (F5) maps five data sources into CXDB and the scenario bank. The table in the brainstorm shows flows running from plugins into CXDB and scenarios. What is absent is the return path: how does improved scenario coverage or accumulated satisfaction data change what agents do?

The OODARC model (PHILOSOPHY.md) requires the Compound phase to "persist the lesson in a form that changes future behavior." The evidence pipeline produces receipts but does not close the Compound loop. Specifically:

- Sprint failures auto-generate scenarios (F5) — this is a reinforcing loop: more failures → more scenarios → more gates
- But there is no balancing mechanism: if the scenario bank grows to cover a domain well, sprint routing or complexity classification does not adjust to reflect reduced risk in that domain
- Interspect is mentioned as a consumer of CXDB data ("Interspect learning" in the brainstorm's "What This Enables"), but the integration is described in aspirational terms without a concrete data flow specified in the PRD

The pipeline is a write-only system from the perspective of Interspect. CXDB accumulates turns. Interspect benefits are asserted. But the mechanism by which Interspect reads CXDB turns and produces routing overrides or calibration signals is not described — it is deferred to Interspect's own design.

This matters because the flywheel (PHILOSOPHY.md core bet #3: "More autonomy produces more outcome data. More data improves routing and review.") requires the evidence pipeline to actually complete a loop. As specified, it completes half a loop: data in, no data-driven change out.

**Recommendation:**

- Define the Interspect integration surface as a concrete acceptance criterion, even if minimal: what query does Interspect run against CXDB, what fields does it read, and what does it emit?
- The `QueryByType(ctx, typeID) []Turn` function in `pkg/cxdb/` is listed but has no consumer described — name the consumer (Interspect) and add an acceptance criterion for the Interspect-side integration point
- If the Interspect integration is genuinely deferred, say so explicitly and create a bead — the PRD currently implies the loop will close without defining when or how

---

### Finding 6 — P2 (Missed Lens): Sprint Forking as a Feature Has No Model for How Forks Are Selected, Compared, or Retired

**Section:** PRD F2 "Sprint Execution Recording" — `cxdb-fork` command; Brainstorm "Sprint forking"

**Lens:** Emergence; Complexity; Schelling Trap

**Observation:**

The PRD introduces O(1) sprint forking via `ForkContext(baseTurnID)` as a feature. The brainstorm frames it as enabling "what if we used a different plan?" exploration. Both documents treat forking as a capability to add.

Neither document models the systemic behavior that emerges when forking is available:

- Who decides which fork to pursue? The agent? The human? The gate system?
- How are competing forks compared? Satisfaction score on holdout scenarios is the obvious answer, but this is not stated
- How are losing forks retired? CXDB is immutable by design (Turn DAG). Losing forks accumulate in storage indefinitely
- What happens when the sprint-fork capability is used by automated remediation (L3)? An L3 agent that auto-forks on failure could generate exponential fork trees if not bounded

The Schelling trap here is that each individual fork is locally rational (try an alternative path) but the aggregate behavior (unbounded fork accumulation, comparison complexity, storage growth) is collectively problematic. This trap is invisible until the system is operating at scale.

The O(1) forking property (copies no data) addresses the computational cost but not the semantic cost: comparing, evaluating, and selecting among competing forks is not O(1). The complexity budget grows with fork count.

**Recommendation:**

- Define a fork lifecycle policy: maximum concurrent forks per sprint, comparison mechanism, retirement/archival process
- If L3 auto-remediation is expected to use forking, bound the fork fan-out explicitly (e.g., max 3 concurrent forks per failure, escalate to human if all fail)
- Consider whether satisfaction scoring across forks is the intended comparison mechanism, and if so, state it explicitly as an acceptance criterion for F4

---

### Finding 7 — P3 (Consider Also): The LLM-as-Judge Feedback Loop Is Susceptible to Judge Drift Over Model Versions

**Section:** PRD F4 "Satisfaction Scoring + Gate Integration"

**Lens:** Hysteresis; Pace Layers; Causal Graph

**Observation:**

The satisfaction scoring reuses existing flux-drive agents (`fd-user-product`, `fd-correctness`, `fd-safety`) as LLM judges. These judges are called at scoring time with the trajectory and rubric. As the underlying models powering these agents change (Claude Sonnet 4.6 today, newer models in future), the scoring calibration shifts even when the rubric does not change.

This is a hysteresis effect: scores from 2026-03-05 on Sonnet 4.6 are not directly comparable to scores from 2026-09 on a different model version. If the historical calibration data (stage 3 of the closed-loop pattern) mixes scores from different judge model versions without labeling them, the calibration will be polluted.

PHILOSOPHY.md notes "Rotate and diversify. No single metric stays dominant" but the concern here is not rotation — it is that a stable metric (satisfaction score) is actually unstable over time because its measurement mechanism (LLM judge) drifts.

This is a pace layer problem: sprint execution runs at the pace of development (days to weeks), but judge model updates happen at the pace of Anthropic releases (months). These layers interact invisibly because there is no version label on satisfaction scores that would reveal the drift when it occurs.

**Recommendation:**

- Record the judge model version (e.g., `claude-sonnet-4-6`) as a field in `satisfaction.json` and the CXDB `clavain.satisfaction.v1` turn
- When calibration (stage 3) is implemented, stratify historical scores by judge model version to avoid mixing incomparable generations
- This is a schema concern that is cheap to address now and expensive to retrofit after a year of unlabeled score accumulation

---

## Verdict

**Approve with required pre-ship conditions on two findings.**

The PRD is architecturally coherent and grounded in PHILOSOPHY.md principles. The CXDB adoption rationale is sound. The scenario bank design is a genuine attempt at the closed-loop pattern the philosophy mandates.

However, two systemic gaps need resolution before the design is locked:

**Pre-ship required (P1):**
- Finding 1: The satisfaction scoring loop must commit to stages 3-4 of the closed-loop pattern or explicitly defer via a named bead with a schema that supports future calibration. The current state (stage 1-2 only with Open Question 5 unanswered) is incomplete by the project's own standard.
- Finding 2: The Goodhart pressure from failure-derived scenarios feeding the holdout must be mitigated. At minimum: failure-derived scenarios go to `dev/` only; holdout requires human promotion; a scenario diversity metric is added as a health signal.

**Address before implementation (P2):**
- Finding 3: Holdout violation monitoring loop (violations feed back into gate hardening, not just audit trail).
- Finding 5: Interspect integration surface must be defined as a concrete acceptance criterion, not asserted as a future benefit.

**Low urgency but time-sensitive schema work (P3):**
- Finding 7: Add `judge_model_version` to `satisfaction.json` schema now. Zero cost at design time; high cost to retrofit after score accumulation begins.

Findings 4 (CXDB dependency dynamics) and 6 (fork lifecycle) are genuine systemic risks but do not block the design — they should be tracked as named operational concerns with mitigation plans rather than blocking gates.
