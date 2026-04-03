### Findings Index
- P1 | BS-01 | "Key Decisions §2 / Open Questions §1" | No fairness floor on theme weights — low-budget themes are perpetually starved by multiplicative interaction with raw scores
- P1 | BS-02 | "Key Decisions §2 / Key Decisions §1" | Cross-theme bead dependencies are invisible to Ockham — independent theme budgets dispatch beads whose dependencies have not completed
- P2 | BS-03 | "Key Decisions §3" | Tier 3 BYPASS recovery restores operation but not policy — factory resumes with pre-crisis weights
- P3 | BS-04 | "What already works §6" | Ockham weight multipliers are the only coordination mechanism — no way to express "these themes must advance together"
- P3 | BS-05 | "Open Questions §1 / Key Decisions §4" | intent.yaml has no specified update cadence — set-and-forget budgets drift from factory reality over time

Verdict: needs-changes

### Summary

Ockham's architecture correctly separates policy computation (Ockham) from operational execution (Clavain), mirroring the subak temple's relationship with individual farmers: the temple computes the planting calendar, the farmer decides how to farm. This separation is the right structural bet. But the subak's resource allocation model reveals two gaps in the current design. First, the temple calendar includes fairness constraints that prevent upstream terraces from monopolizing water — a high-budget theme is the upstream terrace, and without a fairness floor, its multiplicative advantage compounds against low-budget themes' already-lower raw scores to produce effective starvation. Second, the subak's greatest insight is that all terraces must fallow simultaneously — pest synchronization requires coordination constraints that transcend individual terrace decisions. Ockham's weight multipliers are purely individual: they shape each bead's priority independently. There is no mechanism to express "theme A and theme B must advance together because they share a kernel dependency." The beads dependency system (`bd dep add`) operates below Ockham's visibility, meaning cross-theme dependency violations are possible and, under independent budget pressure, likely. A third gap mirrors the Jero Gede's recovery protocol: when the override ends, the subak does not resume the pre-crisis planting calendar — conditions have changed, and resuming stale policy would compound the crisis. Ockham's Tier 3 BYPASS recovery restores operation without triggering policy recomputation.

### Issues Found

1. **P1 — BS-01: No fairness floor on theme weights — low-budget themes face effective dispatch starvation**

   The vision specifies theme budgets as percentages (e.g., "auth 40%") and dispatch weights as multipliers applied to raw scores: `final_score = raw_score * ockham_weight` (§ "Key Decisions §2"). Open Question §1 asks about constraint composition but not about the floor behavior of normal budget allocation. The budget-to-weight mapping is unspecified. If the mapping is linear (5% budget → weight near 0.5), a 5% theme's beads produce a final_score that, combined with below-average raw scores for that theme's beads, places them permanently below the dispatch threshold in any cycle where higher-budget themes have active beads.

   Failure scenario: The principal allocates budgets as: feature work 70%, security hardening 5%, documentation 5%, dependency upgrades 20%. The feature theme has 15 active beads with average raw score 0.7 — final_score ~0.98. The security hardening theme has 3 beads with average raw score 0.5 — final_score ~0.25. Over 20 dispatch cycles, the feature theme claims all available dispatch slots. Security hardening beads are never dispatched. A known vulnerability ships in a release because the security theme was technically allocated 5% but received 0% of actual dispatch capacity. The principal expressed "lower priority than features" and Ockham's arithmetic interpreted it as "never."

   This is the downstream terrace problem: upstream terraces have first access to water, and without temple-imposed constraints, they take all of it. The temple's constraint is not "give downstream terraces some water at some point" — it is a guaranteed minimum allocation enforced in the schedule computation.

   Smallest fix: Define a `weight_floor` constant (e.g., 0.6) applied after budget-to-weight mapping, such that no bead receives a dispatch multiplier below `weight_floor` regardless of budget. Document this floor in the intent.yaml schema alongside the budget field. For themes below a configurable minimum budget threshold (e.g., 10%), apply a "minimum dispatch cadence" guarantee: at least 1 dispatch slot per N cycles regardless of raw score competition, implemented as a tie-breaking rule in lib-dispatch.sh's `dispatch_rescore()`.

2. **P1 — BS-02: Cross-theme bead dependencies are invisible to Ockham — independent budget allocation causes sequencing violations**

   Ockham computes per-bead weights based on theme membership (§ "Key Decisions §1"). The beads dependency system (`bd dep add`) records inter-bead dependencies. The vision does not specify whether Ockham reads bead dependency relationships when computing weights. If it does not — if Ockham treats each bead's theme membership as its sole relevant context — then it is possible, and under pressure likely, that independent theme budgets will dispatch a dependent bead before its upstream dependency is complete.

   Failure scenario: An auth feature bead (theme "auth", budget 40%, weight 1.4) depends on a core infrastructure bead (theme "core-infra", budget 15%, weight 0.9) that adds a required API endpoint. The auth bead's high weight causes it to win dispatch slots before the core-infra bead is complete. An agent begins working on the auth bead, discovers the API endpoint is missing, and either fails the bead or implements a workaround that creates technical debt. The dependency was recorded in beads, but Ockham's weight computation was blind to it.

   This is the subak's pest synchronization failure: two adjacent terraces with independent planting schedules, where one plants while the adjacent terrace has not fallowed, allowing pests to migrate across the border. The temple's insight is that the schedule must be computed globally, incorporating cross-terrace dependencies, not as independent per-terrace decisions.

   Smallest fix: When computing ockham_weight for a bead, check whether the bead has unresolved upstream dependencies. If so, apply a dependency-block modifier: `ockham_weight = min(ockham_weight, weight_floor)` for beads with incomplete dependencies. This does not require Ockham to understand what the dependencies are — only whether they are resolved. The check is: `bd deps <bead_id> --unresolved | wc -l > 0`. This is a small addition to the weight computation pipeline that prevents a large class of sequencing violations.

3. **P2 — BS-03: Tier 3 BYPASS recovery restores operation but not policy — factory resumes with pre-crisis weights**

   The vision specifies Tier 3 BYPASS recovery: "Recovery requires explicit principal re-enable" via `factory-paused.json` deletion (§ "Key Decisions §3" and § "What already works"). The recovery mechanism restores factory operation. It does not specify whether recovery triggers Ockham weight recomputation. If it does not, the factory resumes with the same dispatch weights that were active when the crisis triggered BYPASS.

   The Jero Gede's override ends with a new planting calendar, not a restoration of the old one. The override was triggered because the old calendar produced a crisis; resuming the old calendar resumes the conditions that produced it. After a factory halt, the pre-halt Ockham weights are stale: the anomaly state that caused BYPASS may have been resolved, the intent.yaml may have been updated, and agent authority tiers may have changed during the halt period.

   Failure scenario: The factory halts (Tier 3 BYPASS) because three Tier 2 CONSTRAIN signals fired simultaneously in the `core/**` domain. During the halt, the principal resolves two of the three anomalies and updates intent.yaml to reduce the core budget. The principal re-enables the factory. Ockham has not recomputed weights — the core beads still carry the pre-halt weight configuration. One resolved anomaly was a circuit breaker trip that Ockham's INFORM tier had been compensating for with elevated weights. The compensation weights are still active even though the circuit breaker has cleared. The factory resumes with an over-weighted domain that the principal just de-prioritized.

   Smallest fix: Define a `ockham resume` step as part of the Tier 3 recovery sequence, documented in the vision's "What already works" section. The step runs Ockham's weight computation against the current intent.yaml, current authority state, and current anomaly state, then writes fresh ockham_weights before lib-dispatch.sh resumes. This is not a new subsystem — it is the existing weight computation invoked explicitly rather than on a background cadence.

4. **P3 — BS-04: No mechanism to express coordination constraints across themes**

   Ockham's weight multipliers are per-bead and derived from per-theme budget allocation (§ "Key Decisions §1"). The subak model's deepest insight is that coordinated fallow — simultaneous investment in synchronization across adjacent units — cannot be expressed as individual unit weights. A "synchronize themes A and B" policy cannot be computed as "raise A's weight and raise B's weight independently," because independent weighting does not enforce simultaneous advancement — it only biases toward individual advancement.

   The open questions do not mention cross-theme coordination constraints. This is a gap at the intent.yaml schema level: the schema currently allows per-theme budget allocation but not cross-theme coupling constraints. A constraint like "advance `auth` and `core-infra` together because they share a kernel interface change" cannot currently be expressed.

   Suggested improvement: Add an optional `coupling` field to intent.yaml schema that allows two themes to be declared as coupled: `coupling: [{themes: [auth, core-infra], mode: synchronized}]`. In synchronized mode, Ockham's weight computation ensures that neither theme advances more than K beads ahead of the other. This requires a small counter in the weight computation but no changes to lib-dispatch.sh.

5. **P3 — BS-05: intent.yaml has no specified update cadence — set-and-forget budgets drift from factory reality**

   The vision describes intent arriving via `ockham intent --theme auth --budget 40%` stored in `intent.yaml`, read by both Ockham and Meadowsyn (§ "CLI-first with YAML backing"). It does not specify how often intent.yaml should be reviewed or updated, or what conditions should trigger a review. The temple calendar is computed annually against observed conditions — not fixed for all time and not updated on every daily fluctuation.

   Over time, factory conditions change: agent capabilities improve, theme backlogs grow and shrink, strategic priorities shift. A 40% auth budget specified in February may be misaligned with April's workload composition. If intent.yaml is treated as a set-and-forget configuration, Ockham computes weights from stale intent indefinitely.

   This is a governance question, not a technical flaw — but it should be answered in the vision before implementation, because the answer shapes the design of the `ockham intent` command and the Meadowsyn UI.

   Suggested improvement: Define a review cadence recommendation (e.g., "intent.yaml should be reviewed at the start of each sprint, or after any Tier 3 BYPASS event"). Add a `last_reviewed` timestamp to intent.yaml and have `ockham status` emit a warning if the file has not been reviewed in more than N days. This is a lightweight governance nudge, not an enforcement mechanism.

### Improvements

1. Specify the budget-to-weight mapping function explicitly, including a weight floor constant (default 0.6) and a minimum dispatch cadence for themes below a minimum budget threshold. Document both in the intent.yaml schema.

2. Add dependency-awareness to the weight computation: beads with unresolved upstream dependencies receive `min(computed_weight, weight_floor)` regardless of theme budget, preventing high-priority theme beads from racing ahead of their unresolved dependencies.

3. Define `ockham resume` as an explicit step in the Tier 3 BYPASS recovery sequence. The step recomputes all weights from current intent.yaml and current system state before lib-dispatch.sh resumes. Document it in the "What already works" section alongside the other recovery primitives.

4. Add an optional `coupling` field to the intent.yaml schema for expressing synchronized advancement constraints between paired themes. This closes the coordination constraint gap that per-bead individual weighting cannot express.

5. Add a `last_reviewed` timestamp to intent.yaml and emit a staleness warning in `ockham status` after a configurable inactivity period, creating a governance nudge for regular budget review without making it a hard enforcement gate.
