# CUJ Gate × Rework Disposition Integration

**Reviewer lens:** Quality systems architect thinking in signal tiers, threshold calibration, and decision theory.
**Research question:** How should the three-state CUJ gate (pass/marginal/fail) trigger and constrain rework disposition decisions?
**Grounded against:** CUJ gating model synthesis (`docs/research/flux-research/cuj-gating-model/synthesis.md`), authority tiers evidence thresholds (`docs/research/flux-research/authority-tiers/fd-evidence-thresholds.md`), dispatch integration (`docs/research/flux-research/authority-tiers/fd-dispatch-integration.md`), gate type typology (`docs/research/flux-research/cuj-gating-model/fd-gating-model-typology.md`).
**Anti-overlap:** fd-gating-model-typology covers gate classification. fd-evidence-thresholds covers promotion/demotion scoring. This document covers what happens *after* a gate fires — the disposition decision and rework verification loop.

---

## 1. Marginal State Semantics: Usable vs. Risky

### 1.1 The Problem with Binary Gates

Binary pass/fail gates force a false dichotomy. In manufacturing quality management, the Material Review Board (MRB) exists precisely because real outputs frequently land in a zone that is neither clearly conforming nor clearly nonconforming. MRB disposition options — use-as-is, rework, return to vendor, scrap — acknowledge this ambiguity structurally rather than forcing it through a binary filter ([Tulip MRB](https://tulip.co/blog/material-review-board/), [Agilian MRB](https://www.agiliantech.com/blog/material-review-board-mrb/)).

In IPC-A-610 electronics inspection, the **process indicator** category serves a similar function: a condition that is not a defect at the current acceptance class but is flagged for process improvement. It does not block the unit but creates a record that accumulates toward systemic review ([fd-gating-model-typology §2](../cuj-gating-model/fd-gating-model-typology.md)).

The CUJ gating model synthesis already recommends three-state gates (pass/marginal/fail). This document specifies the operational semantics of **marginal** — what it means, what it authorizes, and what it constrains.

### 1.2 Two Marginal Sub-States

Not all marginal results carry the same risk. The marginal zone decomposes into two operationally distinct conditions:

| Sub-State | Meaning | Disposition Authority | Example |
|---|---|---|---|
| **Marginal-Usable** | Output meets minimum functional requirements but fails preferred quality thresholds. Functionally correct, aesthetically or structurally suboptimal. | Agent may proceed with logged finding. No rework required, but finding enters accumulation ledger. | Tests pass but coverage dropped 3% below target. Diff is correct but introduces minor style inconsistency. |
| **Marginal-Risky** | Output is in the tolerance band but near the failure boundary. Functional correctness is probable but not confirmed to normal confidence. | Agent must quarantine output and escalate to disposition authority. Cannot self-release. | Tests pass on happy path but edge-case coverage is absent. LLM-as-judge scores 0.62 on a 0.60 threshold with high variance across judges. |

**The discrimination criterion:** Marginal-Usable means the output is *known to work* but *known to be suboptimal*. Marginal-Risky means the output *might work* but the evidence is insufficient to confirm it. The distinction is epistemic: certainty about a known deficiency vs. uncertainty about whether a deficiency exists.

### 1.3 Marginal Determination by Signal Tier

The signal tier (from the gating model synthesis) determines how marginal is assessed:

| Signal Tier | Marginal Criterion | Sub-State Assignment |
|---|---|---|
| **Deterministic** (binary pass/fail) | Cannot produce marginal — result is pass or fail by definition | N/A |
| **Threshold** (metric vs. bound) | Value is between the hard fail boundary and the target. E.g., coverage at 78% when target is 80% and hard floor is 70%. | Marginal-Usable if metric is stable and trending up. Marginal-Risky if metric is trending down or volatile. |
| **Trend** (run rules on time series) | Individual data point passes but control chart shows a pattern violation (Western Electric rules: 2 of 3 beyond 2σ, 4 of 5 beyond 1σ, 8 consecutive on one side). | Always Marginal-Risky — trend signals indicate process drift even when individual measurements conform. |
| **Heuristic** (LLM + checklist) | Score falls in the inconclusive band (e.g., 0.55–0.70 on a 0.50 fail / 0.75 pass scale). | Marginal-Usable if all sub-criteria pass individually (the aggregate drag is from low-weight items). Marginal-Risky if any high-weight sub-criterion is in the inconclusive band. |
| **Judgment** (LLM panel / expert) | Judge panel shows split decision (e.g., 2 pass, 1 fail out of 3 judges). | Always Marginal-Risky — judgment disagreement is irreducible uncertainty at the current measurement precision. |

---

## 2. Signal Tier × Disposition Authority Interaction

### 2.1 The Authority Matrix

Disposition authority — who decides what happens to a marginal or failed output — must be a function of both the signal tier that generated the finding and the Mycroft trust tier of the agent that produced the output. Higher-verifiability signals grant more local authority because the decision is less ambiguous. Higher trust tiers grant more local authority because the agent has demonstrated competence.

| Signal Tier | T0 (Observe) | T1 (Suggest) | T2 (Allowlist Auto) | T3 (Full Auto) |
|---|---|---|---|---|
| **Deterministic fail** | Log only | Log + notify human | Auto-reject, create rework bead | Auto-reject, create rework bead |
| **Threshold marginal** | Log only | Log + recommend disposition | Self-disposition if Marginal-Usable; escalate if Marginal-Risky | Self-disposition for both sub-states; log rationale |
| **Trend marginal** | Log only | Log + recommend review | Escalate all (trend signals require process-level decision) | Escalate all (trend decisions are process-scope, not unit-scope) |
| **Heuristic marginal** | Log only | Log + recommend disposition with evidence | Escalate all (insufficient verifiability for self-disposition) | Self-disposition if Marginal-Usable with ≥3 sub-criteria passing; escalate Marginal-Risky |
| **Judgment marginal** | Log only | Log + present panel votes | Escalate all | Escalate all |

**Key design rule:** Even T3 agents cannot self-disposition trend-tier or judgment-tier marginals. Trend signals indicate systemic process issues (not unit-level defects), and judgment disagreement means the measurement itself is inconclusive. Self-dispositioning in these cases would be an agent overriding its own uncertainty, which violates the asymmetric threshold principle from the authority-tiers research: "demotion triggers at lower threshold but acts faster."

### 2.2 Escalation Targets

When an agent must escalate, the target depends on the finding type:

| Finding Type | Escalation Target | Rationale |
|---|---|---|
| Deterministic/threshold fail | Rework queue (automated) | No ambiguity — the fix is to make the check pass |
| Threshold marginal | Bead owner or sprint lead | Requires cost/benefit judgment: fix now vs. accept and track |
| Trend marginal | Process owner (human) | Trend correction requires cross-unit perspective |
| Heuristic marginal | Bead owner with evidence package | Requires domain judgment informed by sub-criteria scores |
| Judgment marginal | Human review with full panel output | Requires human to break the tie or request more evidence |

---

## 3. CUJ Gate Output as Nonconformance Evidence

### 3.1 Evidence Record Structure

Every gate evaluation — pass, marginal, or fail — produces a structured evidence record. For marginal and fail outcomes, this record serves as the **nonconformance report (NCR)** in quality management terms ([SG Systems MRB](https://sgsystemsglobal.com/glossary/material-review-board-mrb/), [ISO 9001 Clause 8.7](https://www.iso.org/standard/62085.html)). The record must capture enough for disposition authority to decide without re-running the gate.

```yaml
gate_evaluation:
  bead_id: "Sylveste-XXXX"
  gate_id: "cuj:build-completes:coverage-threshold"
  signal_tier: "threshold"           # deterministic|threshold|trend|heuristic|judgment
  outcome: "marginal"                # pass|marginal|fail
  marginal_sub_state: "risky"        # usable|risky (only when outcome=marginal)

  measurement:
    value: 77.3                      # actual measured value
    target: 80.0                     # preferred threshold
    hard_floor: 70.0                 # fail boundary
    unit: "percent"
    trend_direction: "declining"     # stable|improving|declining|volatile
    trend_window: 5                  # number of recent observations in trend calc

  evidence:
    raw_output: "..."                # truncated test/check output
    sub_criteria:                    # for heuristic/judgment tiers
      - name: "structural_correctness"
        score: 0.85
        weight: 0.4
      - name: "style_consistency"
        score: 0.55
        weight: 0.2
    judge_votes: []                  # for judgment tier — individual panel decisions

  disposition:
    authority: "pending"             # self|bead_owner|sprint_lead|process_owner|human_review
    decision: null                   # accept|rework|scrap (set by authority)
    rationale: null                  # free text (set by authority)
    decided_at: null
    decided_by: null

  timestamps:
    evaluated_at: "2026-03-19T14:30:00Z"
    quarantined_at: "2026-03-19T14:30:01Z"  # when output entered quarantine
    sla_deadline: "2026-03-19T18:30:00Z"    # disposition must happen by this time
```

### 3.2 Evidence Sufficiency by Disposition Type

Different disposition decisions require different evidence thresholds:

| Disposition | Required Evidence | Who Can Decide |
|---|---|---|
| **Accept (pass-through)** | Gate outcome = pass. No additional evidence needed. | Automated |
| **Accept-with-finding** | Gate outcome = marginal-usable. Evidence record logged. Finding enters accumulation ledger. | Agent (T2+) or bead owner |
| **Rework** | Gate outcome = marginal-risky or fail. Evidence record identifies which check failed and why. Rework scope derived from failed sub-criteria. | Agent (T2+ for deterministic fails), bead owner (for marginal-risky), sprint lead (for trend-based) |
| **Scrap** | Multiple rework attempts failed (rework_attempt_count ≥ max_retries). Evidence chain shows each attempt and failure mode. | Sprint lead or process owner only — agents never self-scrap |

**Scrap authority restriction:** An agent should never decide to abandon its own output without human confirmation. This is the software analog of the manufacturing principle that scrap disposition requires MRB authorization — the cost of discarding work (and the signal that work was undoable) requires human judgment about whether the problem is the unit or the process ([Aligni Disposition](https://www.aligni.com/aligni-knowledge-center/what-is-disposition-in-quality-control-operations/)).

---

## 4. Rework Verification: Full Re-Run vs. Targeted

### 4.1 The Verification Scope Problem

After rework, how much do you re-verify? Full re-run is safe but expensive (the gating model synthesis documents a 1.5x context growth factor per retry, compounding with false-block rates). Targeted verification is efficient but risks missing regressions introduced by the rework itself.

The answer depends on two factors: **rework blast radius** (how much of the output changed during rework) and **gate coupling** (whether the failed gate shares inputs with other gates).

### 4.2 Verification Strategy Matrix

| Rework Blast Radius | Gate Coupling | Verification Strategy | Rationale |
|---|---|---|---|
| **Narrow** (single file, localized change) | **Low** (failed gate tests independent functionality) | Targeted: re-run failed gate + immediate neighbors | Change is contained, regression risk is low |
| **Narrow** | **High** (failed gate shares modules with other gates) | Targeted+: re-run failed gate + all gates sharing input modules | Coupling means rework could propagate |
| **Broad** (multi-file, structural change) | **Low** | Full deterministic + targeted threshold: re-run all deterministic gates (cheap), re-run only failed threshold/heuristic gates | Broad change could break anything deterministic, but expensive gates get targeted |
| **Broad** | **High** | Full re-run of all gates | No shortcut is safe; this is the "clean rebuild" case |

### 4.3 Blast Radius Estimation

Blast radius is computed from the rework diff, not the original diff:

```
blast_radius = classify(rework_diff):
  - narrow: ≤ 3 files changed, all in same module, ≤ 50 lines delta
  - broad:  > 3 files, or cross-module, or > 50 lines delta
```

Gate coupling is pre-declared in the CUJ-bead linkage (from `fd-cuj-bead-linkage-patterns`): each gate declares its input modules, and coupling is computed as the intersection of input sets between gates.

### 4.4 Retry Budget and Escalation

Rework attempts are budgeted per gate per bead:

| Attempt | Action |
|---|---|
| 1st rework | Agent re-attempts with gate feedback. Targeted verification per blast radius rules. |
| 2nd rework | Agent re-attempts with expanded context (include full gate evidence chain). Targeted+ verification minimum. |
| 3rd rework | Mandatory escalation. Agent cannot attempt further rework without human disposition. Full re-run required if human approves another attempt. |

**Why 3?** The false-block cost model shows that compound retry costs grow as `C_base * p^i * k^i`. At retry 3 with k=1.5, the cost multiplier is 3.375x base. Beyond this, the probability that the agent can self-correct without new information approaches zero — further retries are wasted tokens. The manufacturing analog: AS9100 rework procedures typically allow one rework attempt before MRB review; we allow three because AI agent rework is cheaper than physical rework but set the same structural limit ([AS9100 NCR Procedures](https://www.bizmanualz.com/business-procedures/aerospace-procedures/control-of-nonconforming-material-procedure-as9100), [Elsmar AS9100 Discussion](https://elsmar.com/elsmarqualityforum/threads/as9100-control-of-nonconforming-outputs-rework-dispositions.81874/)).

### 4.5 Rework Verification for Marginal-Usable (Accept-with-Finding)

When a marginal-usable output is accepted rather than reworked, no rework verification occurs — but the finding is tracked. The finding resolves in one of three ways:

1. **Naturally resolved:** A subsequent bead's work happens to fix the condition (e.g., coverage climbs back above target). The accumulation ledger marks the finding as resolved with the resolving bead ID.
2. **Explicitly addressed:** A dedicated improvement bead is created to address the accumulated findings. Standard rework verification applies.
3. **Threshold adjusted:** Process owner reviews accumulated findings and determines the threshold was miscalibrated. The threshold is adjusted and the finding is reclassified retroactively.

---

## 5. Marginal Accumulation and Systemic Review

### 5.1 The Accumulation Ledger

Every marginal-usable acceptance and every marginal-risky disposition creates an entry in the accumulation ledger. This is the software factory analog of SPC trend tracking — individual data points may conform, but the pattern reveals process drift.

The ledger tracks:

```yaml
accumulation_entry:
  finding_id: "uuid"
  bead_id: "Sylveste-XXXX"
  gate_id: "cuj:build-completes:coverage-threshold"
  signal_tier: "threshold"
  marginal_sub_state: "usable"
  measurement_value: 77.3
  measurement_target: 80.0
  timestamp: "2026-03-19T14:30:00Z"
  resolved: false
  resolved_by: null          # bead_id that resolved it, or "threshold_adjusted"
```

### 5.2 Accumulation Triggers for Systemic Review

Individual marginal findings are tolerable. Patterns of marginal findings indicate a systemic problem that unit-level rework cannot fix. The following triggers mandate process-level review:

| Trigger | Condition | Review Scope |
|---|---|---|
| **Frequency** | ≥ 3 marginal findings on the same gate within a rolling 7-day window | Gate calibration review: is the threshold correct? Is the signal decomposition adequate? |
| **Breadth** | ≥ 5 marginal findings across different gates within a rolling 7-day window | Process review: is agent capability declining? Is the work complexity increasing? Is the CUJ coverage adequate? |
| **Trend** | Same gate produces marginal findings with monotonically worsening measurements over ≥ 4 consecutive evaluations | Drift review: the process is moving toward failure. Investigate root cause before it crosses the hard floor. |
| **Concentration** | ≥ 3 marginal findings on beads in the same domain/module within a rolling 7-day window | Domain capability review: does the agent (or agent class) have adequate authority/capability for this domain? |
| **Rework rate** | > 30% of bead completions in a rolling window required at least one rework cycle | Systemic rework review: the gate configuration or agent-task matching is generating excessive rework. Cost analysis required. |

### 5.3 Review Actions

Systemic review can produce four outcomes:

1. **Threshold recalibration:** Adjust the marginal band (tighten or loosen). This is legitimate when evidence shows the threshold was set without adequate baseline data.
2. **Signal decomposition:** Break a coarse signal into finer sub-criteria to get better discrimination between usable and risky.
3. **Domain authority adjustment:** Restrict agent authority for the affected domain (maps to Mycroft tier demotion for domain-scoped work).
4. **Process change:** Modify the agent's approach (prompt engineering, tool configuration, context loading strategy) rather than the measurement.

**Ratchet constraint from gating model synthesis:** Thresholds should monotonically tighten as system maturity increases. Loosening is permitted only when the original threshold is demonstrated to be miscalibrated (set without adequate data), not when agents struggle to meet it. The distinction: "this threshold was wrong" justifies loosening; "this threshold is hard" does not.

---

## 6. Quarantine-to-Disposition SLA

### 6.1 Why SLA Matters

ISO 9001 Clause 8.7.1 requires that nonconforming outputs be identified and controlled to "prevent their unintended use or delivery" ([ISO 9001 Clause 8.7](https://www.iso.org/standard/62085.html)). In a software factory, the analog is that marginal-risky or failed outputs must not be merged, deployed, or used as inputs to downstream beads while awaiting disposition. Extended quarantine creates three costs:

1. **Blocking cost:** Downstream work that depends on the quarantined output is stalled.
2. **Context decay:** The agent that produced the output loses context as time passes, making rework more expensive.
3. **Confusion risk:** Quarantined outputs can be mistaken for accepted outputs if the quarantine period is long enough for participants to forget the status ([Advisera Timing Discussion](https://community.advisera.com/topic/timing-requirements-for-quarantine-areas-and-non-conforming-areas/)).

### 6.2 SLA by Signal Tier and Severity

| Outcome | Signal Tier | SLA | Rationale |
|---|---|---|---|
| **Fail** (deterministic) | Deterministic | Immediate (automated rework or reject) | No ambiguity, no human needed |
| **Fail** (threshold) | Threshold | 1 hour | Clear failure, but may need human to choose rework scope |
| **Fail** (heuristic/judgment) | Heuristic, Judgment | 4 hours | Requires human review of evidence package |
| **Marginal-Risky** | Any | 4 hours | Requires disposition decision before output can be used |
| **Marginal-Usable** | Any | No quarantine (immediate accept-with-finding) | Output is functional; finding is logged, not blocking |

### 6.3 SLA Breach Escalation

If disposition does not occur within the SLA window:

| Time Past SLA | Action |
|---|---|
| SLA + 0 | Alert to bead owner and sprint lead |
| SLA + 2 hours | Auto-escalate to process owner. Quarantined output highlighted in dashboard. |
| SLA + 8 hours | Auto-disposition: marginal-risky → rework (conservative default). Failed → scrap if no rework bead created. |

**The conservative default principle:** When no human makes a disposition decision within the SLA, the system defaults to the more conservative action. Marginal-risky outputs are reworked (not accepted), and unresolved failures are scrapped (not left in limbo). This prevents quarantine from becoming a permanent state — the manufacturing anti-pattern of "MRB backlog" where nonconforming material accumulates indefinitely because nobody wants to make the scrap decision.

### 6.4 Quarantine Implementation

Quarantine in the software factory is not physical segregation but state management:

1. **Bead state:** Quarantined beads have `status=in_progress` with a `quarantine=true` state flag. They cannot transition to `closed` until disposition completes.
2. **Merge blocking:** Quarantined beads' branches/changes are not eligible for merge to main.
3. **Dependency blocking:** Downstream beads that declared a dependency on the quarantined bead's output are flagged with `blocked_by=<bead_id>` and cannot start execution.
4. **Visibility:** Quarantined beads surface in `bd list --status=in_progress --filter=quarantined` and in any dashboard/oversight surface.

---

## 7. Integration Points with Existing Architecture

### 7.1 Bead Lifecycle Extension

The current bead lifecycle (`created → in_progress → closed`) needs a quarantine sub-state within `in_progress`:

```
created → in_progress → [gate evaluation]
                           ├─ pass → closed
                           ├─ marginal-usable → closed (with finding logged)
                           ├─ marginal-risky → quarantined → [disposition] → rework | closed
                           └─ fail → quarantined → [disposition] → rework | scrap

rework → in_progress (new attempt) → [gate evaluation] → ...
scrap → closed (status=scrapped, no merge)
```

### 7.2 Interspect Event Types

Gate evaluations produce Interspect events for the accumulation ledger and authority scoring:

| Event Type | Trigger | Consumed By |
|---|---|---|
| `gate_pass` | Gate outcome = pass | Authority scoring (+1x weight) |
| `gate_marginal_usable` | Gate outcome = marginal, sub-state = usable | Accumulation ledger, authority scoring (+0.5x weight) |
| `gate_marginal_risky` | Gate outcome = marginal, sub-state = risky | Accumulation ledger, quarantine system, authority scoring (+0x — neutral) |
| `gate_fail` | Gate outcome = fail | Quarantine system, authority scoring (-2x weight) |
| `disposition_accept` | Marginal-risky dispositioned as accept | Accumulation ledger |
| `disposition_rework` | Any output dispositioned as rework | Rework queue, retry budget tracker |
| `disposition_scrap` | Any output dispositioned as scrap | Authority scoring (-3x weight), process review trigger |
| `rework_verified` | Rework output passes verification | Authority scoring (+0.5x), retry budget reset |

### 7.3 Mycroft Dispatch Integration

Mycroft's dispatch decisions should incorporate rework history:

- **Pre-dispatch check:** Before assigning a bead to an agent, check the agent's recent rework rate for the bead's domain. If > 30%, prefer a different agent or escalate to human assignment.
- **Post-dispatch monitoring:** If an agent's quarantine rate (marginal-risky + fail / total evaluations) exceeds 40% over a rolling window, trigger domain authority review per §5.2 concentration trigger.
- **Rework assignment:** Rework beads are preferentially assigned to the original agent (context advantage) unless the rework is the 3rd+ attempt (indicating the agent cannot self-correct).

---

## 8. Design Decisions and Open Questions

### 8.1 Decided

1. **Three-state gate with marginal split.** Marginal decomposes into usable/risky based on epistemic certainty, not severity.
2. **Signal tier constrains disposition authority.** Low-verifiability signals (heuristic, judgment) require human disposition even for high-trust agents.
3. **Trend signals always escalate.** Process-level signals cannot be dispositioned at the unit level.
4. **Three-attempt rework budget.** After three failed attempts, mandatory human escalation.
5. **Conservative SLA default.** Expired quarantine auto-dispositions toward rework/scrap, never toward acceptance.

### 8.2 Open

1. **Marginal-usable accumulation threshold tuning.** The triggers in §5.2 (3 findings/7 days, etc.) are initial estimates. Real calibration requires production data.
2. **Authority scoring weight for marginal outcomes.** The +0.5x for marginal-usable and +0x for marginal-risky are proposals. The authority-tiers research should validate these weights against the evidence class taxonomy.
3. **Cross-bead marginal correlation.** If two beads produce marginal-risky on the same gate but for different root causes, should they count toward the same accumulation trigger? Probably not, but the correlation detection mechanism is undefined.
4. **SLA calibration for async human workflows.** The 4-hour SLA for heuristic/judgment failures assumes a human is available within that window. For overnight/weekend work, the SLA may need adjustment or the auto-disposition default becomes the de facto disposition mechanism.

---

## Sources

- [Material Review Board — Tulip](https://tulip.co/blog/material-review-board/)
- [How a Material Review Board Works — Agilian](https://www.agiliantech.com/blog/material-review-board-mrb/)
- [MRB Nonconformance Disposition — SG Systems](https://sgsystemsglobal.com/glossary/material-review-board-mrb/)
- [What Is Disposition in Quality Control — Aligni](https://www.aligni.com/aligni-knowledge-center/what-is-disposition-in-quality-control-operations/)
- [In-Process Quality Gates — SG Systems](https://sgsystemsglobal.com/glossary/in-process-quality-gates/)
- [AS9100 Control of Nonconforming Outputs — Elsmar Forum](https://elsmar.com/elsmarqualityforum/threads/as9100-control-of-nonconforming-outputs-rework-dispositions.81874/)
- [AS9100 Nonconforming Material Procedure — BizManualz](https://www.bizmanualz.com/business-procedures/aerospace-procedures/control-of-nonconforming-material-procedure-as9100)
- [ISO 9001 Clause 10.2 Nonconformity — Auditor Training Online](https://blog.auditortrainingonline.com/blog/iso-9001-clause-10.2-nonconformity-and-corrective-action)
- [Quarantine Timing Requirements — Advisera](https://community.advisera.com/topic/timing-requirements-for-quarantine-areas-and-non-conforming-areas/)
- [Pipeline Quality Gates — InfoQ](https://www.infoq.com/articles/pipeline-quality-gates/)
- [Quality Gates — LinearB](https://linearb.io/blog/quality-gates)
- [Signal Detection Theory — Wikipedia](https://en.wikipedia.org/wiki/Detection_theory)
- [Spinnaker Canary Analysis — fd-evidence-thresholds internal reference](../authority-tiers/fd-evidence-thresholds.md)
- [CUJ Gating Model Synthesis — internal](../cuj-gating-model/synthesis.md)

<!-- flux-research:complete -->
