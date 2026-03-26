# Gate Type Typology for CUJ Signal Classification

> **Research question:** How do acceptance testing, manufacturing inspection, and certification frameworks classify gate types by verifiability — and which model best maps to CUJ signal types (measurable/observable/qualitative) for an AI agent software factory?

## 1. Software Acceptance Testing: Executable vs. Judgment-Based Criteria

### ATDD/BDD/Cucumber classification

The ATDD → BDD → automation pipeline assumes a three-stage lifecycle for acceptance criteria: **discovery** (collaborative specification), **formulation** (Gherkin scenarios), and **automation** (executable step definitions). Crucially, the pipeline has no formal tier for "observable but not automatable." Criteria either graduate to executable tests or remain informal prose that lives outside the test harness.

In practice, teams handle the gap with two ad-hoc mechanisms:

| Mechanism | How it works | Weakness |
|-----------|-------------|----------|
| **Manual verification tags** | Scenarios tagged `@manual` or `@exploratory` skip CI but appear in test plans for human execution | No enforcement — tags rot when nobody runs the manual pass |
| **Non-functional requirement scenarios** | BDD scenarios for NFRs (performance, UX feel) expressed in Gherkin but backed by subjective human review rather than assertions | Cucumber reports them as "pending" or "undefined," conflating unimplemented with unjudgeable |

**Key insight for CUJ mapping:** BDD frameworks treat verifiability as binary (automated or not). They have no concept of *partially automatable* — e.g., "the diff looks correct" where structure is checkable but semantic correctness requires judgment. This is the gap a CUJ gate model must fill.

### Relevant taxonomy

From the software testing literature, acceptance criteria decompose into:

1. **Deterministic/executable** — binary pass/fail, fully automatable (unit tests, integration assertions)
2. **Measurable/threshold** — numeric value compared against a bound (performance benchmarks, coverage %)
3. **Observable/heuristic** — a human can see it and judge, but no algorithm captures the judgment (UX quality, code readability, "does this diff make sense")
4. **Subjective/stakeholder** — depends on context, taste, or domain expertise with no stable heuristic (product-market fit, architectural elegance)

BDD collapses tiers 1-2 into "automated" and tiers 3-4 into "not yet automated," losing the distinction between *could be automated with more work* and *fundamentally requires judgment*.

## 2. Manufacturing Inspection: Attribute vs. Variable Gates

### IPC-A-610 and AIAG APQP control plan model

Manufacturing inspection distinguishes two fundamentally different measurement types:

**Variable inspection** measures a continuous quantity (dimension, weight, voltage) and compares it against specification limits. The result is a number with a tolerance band. Variable data supports SPC, capability indices (Cp/Cpk), and trend detection.

**Attribute inspection** classifies a unit as conforming/nonconforming against a defined criterion. The result is binary (pass/fail, go/no-go). Attribute data supports acceptance sampling (ISO 2859) and defect rate tracking, but cannot detect gradual drift.

IPC-A-610 defines three classes (1/2/3) of increasing rigor for electronics assembly acceptability. Within each class, every criterion is classified as:

- **Target** — the ideal condition
- **Acceptable** — meets requirements even if not ideal
- **Defect** — does not meet requirements (process indicator at lower classes, reject at higher classes)
- **Process Indicator** — not a defect at this class, but flagged for process improvement

The **process indicator** category is the manufacturing analog of an "observable but non-blocking" signal — the system records it, tracks trends, but does not gate the unit. This maps directly to CUJ signals that should accumulate evidence without blocking.

### APQP Control Plan gate logic

AIAG's control plan template requires each characteristic to specify:

| Field | Purpose |
|-------|---------|
| **Evaluation/Measurement Technique** | How measured (caliper, go/no-go gauge, visual, CMM) |
| **Sample Size/Frequency** | How often inspected |
| **Control Method** | What happens on failure (SPC chart, 100% sort, containment) |
| **Reaction Plan** | Escalation path when control method triggers |

When only attribute checks are available (visual inspection, go/no-go), the control plan compensates by:
1. Increasing sample frequency (up to 100% inspection)
2. Requiring operator certification/training records
3. Adding process indicators that accumulate into trend reviews
4. Mandating periodic variable-method audits (e.g., quarterly CMM validation of what is daily-checked by visual)

**Key insight for CUJ mapping:** Manufacturing explicitly handles the case where a gate can only do attribute (pass/fail) checking by wrapping it in higher-frequency sampling and trend accumulation. A CUJ gate for "observable" signals should follow this pattern — check more often, log every observation, and escalate when the trend, not any single check, signals a problem.

## 3. Aviation and Medical Device V&V: Verification vs. Validation Separation

### DO-178C (aviation software)

DO-178C defines verification as "the evaluation of the outputs of a process to ensure correctness and consistency with respect to the inputs and standards provided to that process." It explicitly distinguishes three verification methods:

1. **Review** — qualitative examination by a person (or persons), potentially aided by checklists. Inherently judgment-based.
2. **Analysis** — examination using methods such as algorithms, equations, or models. Semi-automatable — the method is formal but may require interpretation.
3. **Test** — execution of software with defined inputs and expected outputs. Fully automatable.

The standard specifies **71 objectives** across Tables A-1 through A-10, each assigned to one or more of these methods. Critically, many objectives at DAL A (highest criticality) require **review with independence** — a human who did not author the artifact must examine it. This cannot be automated away even in principle; the standard explicitly requires human judgment for certain gate types.

**Tool qualification** provides a mechanism for partial automation: if a tool performs an activity that would otherwise require human review, the tool itself must be qualified (TQL-1 through TQL-5). This is an "evidence accumulation" pattern — the tool's qualification evidence substitutes for per-instance human judgment. But DO-178C never allows tool qualification to fully replace review for high-criticality objectives; the tool must be re-qualified periodically, and certain objectives always require human independence.

### IEC 62304 (medical device software)

IEC 62304 classifies software into three safety classes (A/B/C) and scales lifecycle activities accordingly:

| Activity | Class A | Class B | Class C |
|----------|---------|---------|---------|
| Requirements documentation | Required | Required | Required |
| Architecture documentation | Not required | Required | Required |
| Detailed design | Not required | Not required | Required |
| Unit verification | Not required | Required | Required |
| Integration testing | Not required | Required | Required |

The standard distinguishes **verification** (did we build the thing right — automatable) from **validation** (did we build the right thing — requires user/clinical context). Validation is explicitly deferred to later milestones: software verification can complete before system validation. This creates a formal "deferred validation gate" pattern where:

1. The build pipeline gates on verification (automated tests pass)
2. Validation evidence accumulates in parallel (usability studies, clinical trials)
3. A later milestone (design transfer) gates on accumulated validation evidence

**Key insight for CUJ mapping:** Safety-critical standards model exactly the three CUJ signal types: **test** (measurable/automated), **analysis** (observable/semi-automated), and **review** (qualitative/human). They also provide a formal mechanism for deferred gates — proceed now, but evidence must accumulate and pass review at a defined future checkpoint.

## 4. FDA Design Controls: Evidence Accumulation Gates

### The waterfall-with-feedback model (21 CFR 820.30)

FDA design controls define seven phases with associated review gates:

```
Planning → Input → Output → Review → Verification → Validation → Transfer
     ↑_____________________________________________↓ (feedback loops)
```

Each **design review** is a gate where cross-functional reviewers examine evidence and produce one of:

- **Approve** — proceed to next phase
- **Approve with action items** — proceed, but specific items must be resolved and documented before the *next* gate (not this one)
- **Return for rework** — do not proceed; address findings first

The "approve with action items" pattern is the canonical **evidence accumulation gate**: the project is not blocked, but open items are logged, assigned owners, given due dates, and tracked. At the next design review, accumulated evidence (closed action items + new evidence) is reviewed as a package.

### Design History File as evidence ledger

The Design History File (DHF) serves as the evidence accumulation ledger. It does not gate individual activities but must demonstrate at final review that:
- Every design input has a traceable verification/validation record
- Every design review action item was resolved
- Every design change was evaluated for impact

This is not a pass/fail gate but a **completeness audit** — the question is "is the evidence package sufficient?" rather than "did this specific test pass?"

**Key insight for CUJ mapping:** The FDA model provides two gate patterns missing from software CI:
1. **Conditional proceed** — pass the gate now, but log items that must be resolved by a future gate
2. **Evidence package review** — the gate evaluates accumulated evidence rather than a single binary signal

These map to CUJ scenarios where an agent proceeds past a qualitative check (e.g., "this refactor looks reasonable") but the system logs the decision for later human review of the accumulated set.

## 5. SPC Run Rules: Trend-Based Signals (Not Pass/Fail)

### Control limits vs. specification limits

SPC makes a fundamental distinction that most software CI ignores:

| Concept | Source | Question answered |
|---------|--------|-------------------|
| **Specification limits** (USL/LSL) | Customer/requirements | Is this unit acceptable? |
| **Control limits** (UCL/LCL) | Process data (±3σ) | Is the process stable? |

A unit can be **in spec but out of control** (the process is drifting, but hasn't produced defects yet) or **in control but out of spec** (the process is stable but not capable enough). These are different problems requiring different responses.

### Nelson/Western Electric run rules

The Western Electric rules (1956) and Nelson rules (1984) detect process instability through pattern recognition on control charts:

| Rule | Pattern | What it detects |
|------|---------|-----------------|
| 1 | 1 point > 3σ from mean | Outlier / special cause |
| 2 | 2 of 3 consecutive points > 2σ (same side) | Shift beginning |
| 3 | 4 of 5 consecutive points > 1σ (same side) | Persistent drift |
| 4 | 8+ consecutive points same side of mean | Sustained shift |
| 5 | 6+ consecutive points trending up or down | Trend / tool wear |
| 6 | 14+ consecutive points alternating up/down | Over-adjustment or two-stream mixing |
| 7 | 15+ consecutive points within 1σ of mean | Stratification / measurement resolution |
| 8 | 8+ consecutive points > 1σ from mean (both sides) | Mixture of two processes |

These rules distinguish **statistical significance** (the pattern is unlikely under normal variation) from **practical significance** (the unit is defective). A process can violate run rules while producing no defective units — the rules detect that the process is heading toward defects.

### Process capability as a meta-gate

Cp and Cpk indices measure whether a stable process is *capable* of meeting specifications:

- **Cpk ≥ 1.33**: Process is capable (standard threshold)
- **1.0 ≤ Cpk < 1.33**: Process is marginal — technically meeting spec but with insufficient safety margin
- **Cpk < 1.0**: Process is not capable — some units will be out of spec even when in control

**Key insight for CUJ mapping:** SPC provides the model for CUJ signals that are trend-based rather than pass/fail:
- **Specification check** → "Is this output acceptable?" (measurable gate, binary)
- **Control chart check** → "Is the process producing this output stable?" (trend gate, pattern-based)
- **Capability check** → "Can this process reliably meet requirements?" (meta gate, statistical)

For an AI agent factory, this maps to:
- Individual CUJ pass/fail → specification check
- CUJ pass rate over N recent runs → control chart (apply run rules to detect drift)
- Long-term CUJ capability → Cpk analog (is this agent configuration reliable enough for this task class?)

## 6. Deviation Permits and Concessions: Bypass with Evidence

### ISO 9001 deviation/concession framework

ISO 9001:2015 (Clause 8.7) defines two mechanisms for proceeding past a failed quality gate:

**Deviation permit** (before production): Permission granted *in advance* to depart from specified requirements for a limited quantity or time period. The permit specifies:
- What requirement is being deviated from
- Justification for why deviation is acceptable
- Scope (quantity, duration, specific use)
- Approval authority (who can authorize)
- Monitoring requirements during the deviation period

**Concession** (after production): Permission to use or release a product that does not conform to specified requirements. The concession requires:
- Description of the nonconformity
- Assessment of impact (risk analysis)
- Customer notification/approval (if customer-facing)
- Disposition decision (use as-is, rework, scrap)
- Root cause investigation trigger

### CAPA (Corrective and Preventive Action) integration

When deviations or concessions form patterns, ISO 9001 requires escalation to CAPA:
1. Individual deviation → logged and monitored
2. Recurring deviation pattern → triggers investigation
3. Investigation → identifies root cause
4. Corrective action → eliminates cause
5. Preventive action → prevents recurrence in similar processes

**Key insight for CUJ mapping:** The deviation/concession pattern provides the model for agent gate bypass:

| Scenario | Manufacturing analog | Agent factory pattern |
|----------|---------------------|----------------------|
| Agent knows a qualitative gate will fail but has good reason to proceed | **Deviation permit** | Agent requests bypass *before* acting, logs justification, scope-limited |
| Agent already produced output that fails a qualitative gate | **Concession** | System evaluates impact, may accept with evidence logging |
| Same gate bypassed repeatedly | **CAPA trigger** | System flags pattern, escalates for process change or gate recalibration |

## 7. Synthesis: Gate Type Taxonomy for CUJ Signals

Combining patterns from all six domains, the following taxonomy emerges:

### Gate types by verifiability

| Gate Type | Verifiability | Check Method | Failure Response | Examples |
|-----------|--------------|--------------|------------------|----------|
| **Deterministic** | Fully automatable | Assert output = expected | Block immediately | Tests pass, lint clean, types check |
| **Threshold** | Measurable, automatable | Compare metric against bound | Block if below/above | Coverage ≥ 80%, latency < 200ms, Cpk ≥ 1.33 |
| **Trend** | Measurable over time, automatable | Apply run rules to metric series | Alert on pattern, block on sustained violation | Pass rate drift, token cost trend, error rate shift |
| **Heuristic** | Observable, semi-automatable | Structured checklist + human/LLM review | Log finding, proceed with evidence | "Diff looks correct," "approach is reasonable," code review |
| **Judgment** | Not automatable | Expert review against context-dependent criteria | Accumulate evidence, review at milestone | Architecture fitness, UX quality, product-market alignment |

### Gate response patterns

| Response Pattern | Source Framework | When to use |
|------------------|-----------------|-------------|
| **Hard block** | All frameworks (test failures) | Deterministic and threshold gates with high confidence |
| **Conditional proceed** | FDA design review "approve with action items" | Heuristic gate with logged finding; must resolve by next milestone |
| **Deviation permit** | ISO 9001 deviation/concession | Agent requests pre-authorization to bypass a gate with justification |
| **Evidence accumulation** | FDA DHF, DO-178C tool qualification | Judgment gates where individual checks are logged and the *package* is reviewed later |
| **Process indicator** | IPC-A-610 process indicator classification | Signal logged for trend analysis but not gating at current maturity level |
| **Trend alert** | SPC run rules (Western Electric/Nelson) | Metric series violates run rules; no single point is out of spec but the pattern is |
| **CAPA escalation** | ISO 9001 CAPA | Recurring bypass/deviation pattern triggers root cause investigation |

### Mapping to CUJ signal types

| CUJ Signal Type | Gate Types | Response Patterns |
|-----------------|------------|-------------------|
| **Measurable** | Deterministic, Threshold | Hard block, Trend alert |
| **Observable** | Heuristic, Trend | Conditional proceed, Process indicator, Evidence accumulation |
| **Qualitative** | Judgment | Evidence accumulation, Deviation permit, CAPA escalation |

### Decision flow for an AI agent factory

```
Signal received from CUJ check
  │
  ├─ Is the check deterministic (binary pass/fail)?
  │   YES → Hard block on failure. No bypass mechanism.
  │
  ├─ Is the check threshold-based (metric vs. bound)?
  │   YES → Hard block if out of spec.
  │         Also feed to trend tracker (SPC control chart).
  │         If run rule violation but in spec → trend alert (non-blocking).
  │
  ├─ Is the check observable (structured heuristic)?
  │   YES → Run heuristic (LLM-as-judge or checklist).
  │         If PASS → proceed, log evidence.
  │         If FAIL → conditional proceed:
  │           - Log finding with severity
  │           - Check deviation budget (how many open findings for this CUJ?)
  │           - If budget exceeded → block until findings reviewed
  │           - If within budget → proceed, evidence accumulates
  │
  └─ Is the check qualitative (expert judgment)?
      YES → Log as process indicator.
            Do not gate individual runs.
            At milestone review:
              - Package all accumulated indicators
              - Human reviews package
              - Approve / require changes / recalibrate gate
            If same qualitative signal triggers repeatedly:
              - CAPA escalation → investigate whether gate should be
                upgraded to heuristic or threshold type
```

## 8. Implications for Implementation

1. **Every CUJ signal needs a declared gate type.** The taxonomy above provides five types. When defining a CUJ, the author declares which type applies. This is analogous to APQP control plan's "evaluation method" field.

2. **Observable/heuristic gates need deviation budgets.** Borrowing from ISO 9001, each heuristic gate should have a maximum number of open "conditional proceed" findings before it escalates to a hard block. This prevents unbounded accumulation of deferred risk.

3. **Trend tracking applies to all measurable gates.** Even gates that currently pass should feed SPC-style trend tracking. Apply Nelson/Western Electric rules to detect drift before it causes failures.

4. **Qualitative gates should mature.** The CAPA pattern suggests that qualitative gates that trigger frequently should be investigated for upgrade — can the judgment be captured as a heuristic? Can the heuristic be captured as a threshold? This is analogous to manufacturing's progression from visual inspection to go/no-go gauging to CMM measurement.

5. **Evidence accumulation is the missing CI primitive.** Current CI is almost entirely hard-block (tests pass or pipeline fails). The FDA/DO-178C evidence accumulation pattern — log findings now, review the package at a defined milestone — is the key abstraction needed for qualitative CUJ signals in an agent factory.

## Sources

- [TDD vs BDD vs ATDD Key Differences — BrowserStack](https://www.browserstack.com/guide/tdd-vs-bdd-vs-atdd)
- [How to Start with ATDD using BDD — PMI](https://www.pmi.org/disciplined-agile/how-to-start-with-acceptance-test-driven-development)
- [Attribute & Variable Sampling Plans — ASQ](https://asq.org/quality-resources/sampling/attributes-variables-sampling)
- [Inspection by Variables versus Attributes (PDF)](https://ijirem.org/DOC/22-inspection-by-variables-versus-attributes.pdf)
- [IPC-A-610 Standard: Ultimate Guide — NextPCB](https://www.nextpcb.com/blog/ipc-a-610)
- [IPC-A-610 Standard Explained — PCBSync](https://pcbsync.com/ipc-a-610/)
- [Complete Verification and Validation for DO-178C (PDF) — Vector](https://cdn.vector.com/cms/content/know-how/aerospace/Documents/Complete_Verification_and_Validation_for_DO-178C.pdf)
- [A Fresh Take on DO-178C Software Reviews — AdaCore](https://blog.adacore.com/a-fresh-take-on-do-178c-software-reviews)
- [DO-178C — Wikipedia](https://en.wikipedia.org/wiki/DO-178C)
- [IEC 62304 — Wikipedia](https://en.wikipedia.org/wiki/IEC_62304)
- [How to Apply IEC 62304 Requirements — Greenlight Guru](https://www.greenlight.guru/blog/iec-62304)
- [Design Controls FDA Guidance (PDF)](https://www.fda.gov/files/drugs/published/Design-Controls---Devices.pdf)
- [21 CFR 820.30 — eCFR](https://www.law.cornell.edu/cfr/text/21/820.30)
- [How to Create a Design History File — Ketryx](https://www.ketryx.com/blog/how-to-create-a-design-history-file-dhf-for-medical-devices)
- [Structure of Gates in a Phase Gate Process — GenSight](https://gensight.com/structure-of-gates-in-a-phase-gate-process/)
- [Stage Gate Process — TCGen](https://www.tcgen.com/product-development/stage-gate-process/)
- [Nelson vs. Western Electric Rules — Parsec](https://www.parsec-corp.com/blog/nelson-vs-western-electric)
- [Nelson Rules and Western Electric Rules for Control Charts — Quality Gurus](https://www.qualitygurus.com/nelson-rules-and-western-electric-rules-for-control-charts/)
- [Control Limits vs. Specification Limits — Lean 6 Sigma Hub](https://lean6sigmahub.com/control-limits-vs-specification-limits-understanding-the-critical-difference-in-quality-management/)
- [Process Capability Cp Cpk — Six Sigma Study Guide](https://sixsigmastudyguide.com/process-capability-cp-cpk/)
- [Concession vs. Deviation — Elsmar](https://elsmar.com/elsmarqualityforum/threads/when-to-use-a-concession-over-a-deviation-concession-vs-deviation.32058/)
- [ISO 9001 Deviation Control — QHSEAlert](https://qhsealert.com/iso-9001-deviation-control-for-quality-compliance/)
- [The Importance of a Formal Concession Process — The Auditor](https://www.theauditoronline.com/the-importance-of-introducing-a-formal-concession-process/)
- [Guide to NC, CC, CAPA, and TDA in ISO-Based QMS — Bananaz](https://www.bananaz.ai/blog/your-complete-guide-to-nc-cc-capa-and-tda-in-iso-based-qms)

<!-- flux-research:complete -->
