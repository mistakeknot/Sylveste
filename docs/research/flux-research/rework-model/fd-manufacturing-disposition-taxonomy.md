# Manufacturing Disposition Taxonomy for AI Agent Output Failures

> Flux-drive research: mapping MES/MRB/CAPA nonconformance disposition workflows onto AI agent output failure modes.

## 1. Source Domain: Manufacturing Nonconformance Management

### 1.1 The NCR-MRB-CAPA Pipeline

Manufacturing quality systems follow a three-stage pipeline for handling nonconforming output:

1. **Detection & Quarantine** -- An operator or automated inspection station flags a unit that deviates from specification. The unit is quarantined (physically segregated or logically held in MES) to prevent it from progressing downstream. An NCR (Nonconformance Report) is opened with: report ID, date of detection, description, affected product/lot, severity classification, and reference to the violated requirement.

2. **Disposition by MRB** -- The Material Review Board convenes cross-functional authority (Quality, Engineering, Manufacturing, and optionally the customer) to evaluate the NCR and assign a disposition. MRB decisions must be **unanimous** or the matter escalates to the sponsoring Project Office for adjudication. Possible dispositions:

   | Disposition | Definition | Authority Required |
   |---|---|---|
   | **Use-As-Is** | Accept the unit despite deviation; engineering analysis confirms no impact on form/fit/function/safety | Engineering + Quality sign-off; customer approval if contractual |
   | **Rework** | Bring the unit back into conformance through an approved rework procedure | Quality approval of rework instruction |
   | **Repair** | Restore the unit to a usable state that may not fully meet original spec (requires waiver) | Engineering analysis + customer waiver |
   | **Scrap** | Destroy or dispose of the unit; no economical path to conformance | Quality authority; cost charge-back to originating process |
   | **Return to Vendor (RTV)** | Nonconformance originated in supplied material; return for credit/replacement | Supplier Quality + Procurement |
   | **Downgrade/Regrade** | Accept for a lower-specification application | Engineering + business approval |

3. **CAPA Escalation** -- When nonconformances are systemic, recurring, safety-critical, or exceed threshold metrics, a Corrective and Preventive Action is triggered. CAPA demands root cause analysis (5-Why, fishbone, fault tree), containment actions, systemic corrective action, and effectiveness verification. ISO 9001:2015 Clause 10.2 requires organizations to eliminate the causes of nonconformities and prevent recurrence.

### 1.2 Severity Classification

Manufacturing uses a three-tier severity model that drives escalation speed and authority requirements:

- **Critical** -- Safety risk, regulatory impact, potential recall. Immediate containment. MRB + customer + regulatory notification.
- **Major** -- Significant quality or compliance impact. Formal investigation, root cause analysis, CAPA mandatory. MRB disposition required.
- **Minor** -- Isolated, low-risk, no direct safety/performance impact. May be dispositioned by Quality Engineer without full MRB convening.

### 1.3 Cost of Quality (PAF Model)

The Prevention-Appraisal-Failure model provides the cost accounting framework:

| Category | Manufacturing | AI Agent Equivalent |
|---|---|---|
| **Prevention** | Process design, training, SPC, FMEA | Prompt engineering, guardrails, model selection, context design |
| **Appraisal** | Inspection, testing, audit | Output validation, eval suites, code review, CI checks |
| **Internal Failure** | Scrap, rework, re-inspection, downtime | Rework loops, token waste on retries, failed generations discarded pre-delivery |
| **External Failure** | Warranty, recalls, liability, reputation | User-facing bugs, incorrect answers shipped, trust erosion, rollback cost |

Key insight: the PAF model predicts that investment in prevention and appraisal reduces total cost, because internal failures are cheaper than external failures by 4-10x. This maps directly to the economics of catching AI agent errors before vs. after delivery.

### 1.4 First-Pass Yield

FPY = (Good Units / Total Units Entering Process) x 100

World-class manufacturing targets 95%+ FPY. For AI agents:

- **Agent FPY** = (Tasks completed correctly on first attempt) / (Total tasks attempted)
- **Rolled Throughput Yield (RTY)** = Product of FPY across sequential process steps -- relevant for multi-step agentic pipelines where each step can introduce defects
- A 90% FPY across 5 sequential agent steps yields RTY of 0.9^5 = 59% -- meaning 41% of multi-step workflows require at least one rework intervention

### 1.5 Quarantine Workflow

MES enforces hard-gated quarantine:

1. **Detection** -- Inspection result or process parameter out of spec triggers automatic hold
2. **Segregation** -- Lot/unit moved to quarantine status; MES blocks downstream operations
3. **Pending Evidence** -- Awaiting measurement data, operator notes, engineering analysis
4. **Disposition Decision** -- MRB assigns one of the six dispositions
5. **Execution** -- Rework instruction issued, scrap order created, or hold released
6. **Verification** -- Re-inspection confirms rework was effective; lot released from quarantine

## 2. Target Domain: AI Agent Output Failure Modes

### 2.1 Agent Output Failure Taxonomy

Mapping manufacturing defect categories to AI agent outputs:

| Manufacturing Defect Type | AI Agent Failure Mode | Severity | Detection Method |
|---|---|---|---|
| Dimensional out-of-tolerance | Output structurally malformed (wrong format, missing fields, schema violation) | Minor-Major | Schema validation, type checking |
| Material defect (wrong alloy) | Fundamentally wrong approach or technology choice | Major-Critical | Expert review, eval suite |
| Surface finish defect | Cosmetic issues (style, formatting, naming conventions) | Minor | Linting, style checks |
| Functional failure | Code that doesn't work, incorrect logic, broken tests | Major | CI/CD, test execution |
| Safety-critical defect | Security vulnerability, data leak, destructive operation | Critical | Security scanning, guardrail checks |
| Assembly error | Integration failure -- component works alone but breaks in context | Major | Integration tests, staging environment |
| Contamination | Hallucinated content, training data leakage, PII exposure | Major-Critical | Fact-checking, content filtering |
| Wrong part installed | Correct code but applied to wrong file/location | Major | Diff review, context validation |
| Documentation mismatch | Code-comment divergence, stale docs | Minor | Doc-drift detection |
| Intermittent/latent defect | Non-deterministic failures, race conditions introduced | Critical | Stress testing, fuzzing, extended eval |

### 2.2 Disposition Mapping

How each MRB disposition translates to AI agent output handling:

#### Use-As-Is (Accept with Deviation)
**Manufacturing:** Part is out-of-spec but engineering confirms no functional impact.
**AI Agent:** Output has known imperfections but meets the practical intent. Examples:
- Code works but doesn't follow preferred style conventions
- Answer is correct but verbose
- Implementation uses a different algorithm than requested but produces correct results

**Authority:** Requester or automated policy (deviation within defined tolerance band). No rework loop triggered.

**Analog in Skaffen/Sylveste:** A `quality: acceptable` verdict with logged deviation. The output ships but the deviation is recorded for trend analysis. If deviations of this type accumulate past a threshold, CAPA triggers.

#### Rework
**Manufacturing:** Unit is brought back into full conformance through an approved procedure.
**AI Agent:** Output is fed back through the agent with specific correction instructions. Examples:
- "Fix the failing test" loop
- "Apply the requested style changes"
- "The function signature doesn't match the interface -- correct it"

**Authority:** Automated (CI failure triggers rework loop) or reviewer (human sends back with comments).

**Cost accounting:** Each rework iteration consumes tokens, latency, and compute. Rework rate is a primary quality metric. Bounded by max-retry policy (analogous to max rework attempts before MRB escalation in manufacturing).

#### Repair (Accept with Waiver)
**Manufacturing:** Unit restored to usable but not fully original-spec state.
**AI Agent:** Human patches the output manually rather than re-running the agent. Examples:
- Developer fixes a few lines in an otherwise correct PR
- User edits an AI-generated document to correct factual errors
- Reviewer applies a manual fix rather than requesting another agent iteration

**Authority:** Human reviewer makes the repair decision. This is an explicit signal that the agent failed but the output was close enough to salvage.

**Cost accounting:** Human labor cost replaces compute cost. High repair rates indicate the agent is producing "almost right" output that wastes human review time.

#### Scrap
**Manufacturing:** Unit destroyed; no economical recovery path.
**AI Agent:** Output is completely discarded; task is restarted from scratch or reassigned. Examples:
- Agent went completely off-track (wrong file, wrong repo, misunderstood task)
- Output contains fundamental architectural errors that can't be incrementally fixed
- Hallucination-contaminated output where correction would require full rewrite

**Authority:** Reviewer or automated eval (score below minimum threshold).

**Cost accounting:** Total loss of tokens/compute spent. Scrap rate is the harshest quality signal.

#### Return to Vendor (RTV)
**Manufacturing:** Defect originated in supplied material.
**AI Agent:** Failure attributed to upstream input quality, not agent capability. Examples:
- Ambiguous or contradictory task specification
- Context window filled with irrelevant/stale information
- Tool/API returned incorrect data that the agent faithfully processed
- Model API returned degraded output (rate limiting, capacity issues)

**Authority:** Root cause analysis determines upstream origin. Remediation targets the input pipeline, not the agent.

#### Downgrade/Regrade
**Manufacturing:** Accept for a lower-specification application.
**AI Agent:** Output used for a reduced purpose. Examples:
- Code intended as production implementation used instead as a prototype/reference
- Research answer used as "starting point" rather than authoritative source
- Generated test used as a smoke test rather than comprehensive coverage

**Authority:** Requester decides to accept reduced value rather than invest in rework.

## 3. MRB Authority Structure for AI Agents

### 3.1 Board Composition Mapping

| MRB Role | AI Agent Equivalent | Responsibility |
|---|---|---|
| Quality Engineer | Eval/validation system | Measures conformance to specification |
| Design Engineer | System architect / prompt designer | Determines if deviation affects function |
| Manufacturing Engineer | Agent runtime / orchestrator | Assesses rework feasibility and cost |
| Customer Representative | End user / product owner | Accepts or rejects use-as-is dispositions |
| Supplier Quality | Upstream pipeline owner | Investigates RTV dispositions |

### 3.2 Authority Levels

Tiered disposition authority, mirroring manufacturing practice:

**Level 0 -- Automated (No Human):**
- Schema validation pass/fail
- Test suite pass/fail
- Linter/formatter compliance
- Token budget compliance
- Dispositions available: Rework (auto-retry), Scrap (below threshold)

**Level 1 -- Agent Self-Review:**
- Evaluator/critic model reviews output
- Confidence scoring and self-assessment
- Dispositions available: Rework (with self-correction), Use-As-Is (within tolerance)

**Level 2 -- Single Reviewer:**
- Human reviewer or senior eval model
- Dispositions available: All except safety-critical overrides
- Typical for Major severity NCRs

**Level 3 -- Full MRB (Cross-Functional):**
- Multiple stakeholders: architect + user + quality system
- Required for Critical severity or high-cost dispositions
- Required for Use-As-Is on safety-adjacent outputs
- Unanimous decision or escalation

### 3.3 Escalation Triggers (NC to CAPA)

An individual nonconformance becomes a systemic CAPA when any of these conditions are met:

| Trigger | Manufacturing | AI Agent |
|---|---|---|
| **Recurrence** | Same defect code on 3+ NCRs within period | Same failure mode across 3+ tasks (e.g., agent consistently mishandles a specific pattern) |
| **Trend breach** | Control chart out-of-control signal | FPY drops below threshold for a task category or model version |
| **Severity escalation** | Any Critical NCR | Any safety-critical failure (data loss, security vulnerability, destructive action) |
| **Customer complaint** | End-user reports field failure | User reports agent output caused downstream problem |
| **Audit finding** | External auditor identifies systemic gap | Eval suite reveals systematic blind spot |
| **Cost threshold** | Cumulative rework/scrap cost exceeds budget | Token/compute waste on rework exceeds cost threshold per task category |

CAPA resolution requires:
1. **Containment** -- Immediately quarantine similar in-progress work
2. **Root Cause Analysis** -- 5-Why or equivalent (was it the prompt? the model? the context? the tools?)
3. **Corrective Action** -- Fix the specific instance
4. **Preventive Action** -- Change the system so this class of failure cannot recur (prompt update, guardrail addition, model switch, context pipeline fix)
5. **Effectiveness Verification** -- Run targeted evals to confirm the fix works

## 4. Metrics Framework

### 4.1 Primary Quality Metrics

| Metric | Formula | Target | Interpretation |
|---|---|---|---|
| **First-Pass Yield (FPY)** | Good outputs / Total attempts | >85% | Core quality signal; measures agent reliability |
| **Rework Rate** | Rework dispositions / Total dispositions | <10% | Efficiency of initial generation |
| **Scrap Rate** | Scrap dispositions / Total dispositions | <3% | Severity of failures; high scrap = fundamental capability gap |
| **Repair Rate** | Human-patched outputs / Total outputs | <5% | "Almost right" frequency; human labor cost signal |
| **Use-As-Is Rate** | Accepted-with-deviation / Total outputs | Track, no target | Tolerance calibration signal; too high = specs too tight or agent under-performing |
| **CAPA Rate** | CAPAs opened / NCRs opened | <5% | Systemic vs. isolated failure ratio |
| **Rolled Throughput Yield** | Product of FPY across pipeline stages | >70% | End-to-end quality of multi-step workflows |
| **Mean Time to Disposition** | Avg time from detection to disposition | Minimize | Measures review bottleneck / quarantine dwell time |
| **Cost of Poor Quality (COPQ)** | (Internal failure + External failure costs) / Total cost | <15% | Economic impact of quality failures |

### 4.2 Disposition Distribution Analysis

Track the distribution of dispositions over time as a quality management signal:

```
Healthy distribution:       Degrading distribution:
  Pass:       82%             Pass:       60%
  Use-As-Is:   8%             Use-As-Is:  12%
  Rework:      6%             Rework:     18%
  Repair:      2%             Repair:      5%
  Scrap:       1%             Scrap:       4%
  RTV:         1%             RTV:         1%
```

A shift from Pass toward Rework/Repair indicates the agent is producing lower-quality output that still partially meets requirements -- the most expensive failure mode because it consumes both compute and human time.

A shift toward Scrap indicates the agent is failing fundamentally -- cheaper per-incident (no rework cost) but signals a capability gap requiring CAPA.

## 5. Quarantine Workflow for AI Agent Outputs

### 5.1 Hard-Gated Pipeline

```
[Agent generates output]
        |
  [Automated inspection]
        |
   Pass? ----Yes----> [Release to consumer]
        |
       No
        |
  [Quarantine: output held]
        |
  [Severity classification]
        |
  +-----+------+--------+
  |            |         |
Minor       Major     Critical
  |            |         |
[L0/L1     [L2        [L3 Full
 auto-      review]    MRB review]
 disposition]   |         |
  |            |         |
  [Disposition decision]
  |     |     |     |     |
 UAI  Rework Repair Scrap RTV
  |     |     |     |     |
  |  [Re-run  | [Discard] |
  |   agent]  |           |
  |     |  [Human      [Fix
  |     |   patch]    upstream]
  |     |     |         |
  [Verify & release from quarantine]
        |
  [Record disposition + metrics]
        |
  [Check CAPA triggers]
```

### 5.2 Quarantine States

| State | Meaning | Allowed Transitions |
|---|---|---|
| **PENDING_INSPECTION** | Output generated, awaiting automated checks | -> RELEASED, QUARANTINED |
| **QUARANTINED** | Failed inspection, held for disposition | -> REWORK_IN_PROGRESS, RELEASED_WITH_DEVIATION, SCRAPPED, RTV |
| **REWORK_IN_PROGRESS** | Agent re-running with correction context | -> PENDING_REINSPECTION |
| **PENDING_REINSPECTION** | Reworked output awaiting re-check | -> RELEASED, QUARANTINED (re-quarantine on re-fail) |
| **RELEASED** | Output passed and delivered | Terminal |
| **RELEASED_WITH_DEVIATION** | Use-As-Is disposition, delivered with logged deviation | Terminal |
| **SCRAPPED** | Output discarded | Terminal |
| **RTV** | Failure attributed upstream, input pipeline notified | Terminal |

### 5.3 Rework Limits

Manufacturing imposes maximum rework attempts to prevent infinite loops and material degradation. The AI agent equivalent:

- **Max rework iterations per task:** 3 (configurable). After 3 failed rework attempts, force-escalate to human review (Level 2+) or scrap.
- **Rework budget ceiling:** If cumulative rework token cost exceeds 3x the original generation cost, auto-scrap and flag for CAPA.
- **Rework-on-rework detection:** If a rework attempt introduces new defects not present in the original, escalate severity by one tier.

## 6. Implementation Implications for Sylveste/Skaffen

### 6.1 Where This Maps in the Architecture

- **Interspect** (event pipeline) -- natural home for NCR event recording, severity classification, and CAPA trigger detection
- **Skaffen** (sovereign agent) -- implements the quarantine state machine and disposition authority levels
- **Intercore** (kernel) -- enforces hard gates between pipeline stages; manages rework budget limits
- **Interwatch** (monitoring) -- tracks FPY, rework rate, scrap rate, COPQ over time; surfaces trend breaches

### 6.2 Key Design Decisions Needed

1. **Severity classification model** -- Static rules vs. learned classifier for auto-classifying NCR severity
2. **MRB convening policy** -- When does a single-reviewer (L2) escalate to full cross-functional review (L3)?
3. **Use-As-Is tolerance bands** -- How much deviation from spec is acceptable per output category?
4. **CAPA threshold tuning** -- What recurrence count / trend slope triggers systemic investigation?
5. **Cost model calibration** -- How to weight token cost vs. latency cost vs. human review cost in COPQ?

### 6.3 What Manufacturing Gets Right That AI Systems Usually Don't

1. **Mandatory quarantine** -- Manufacturing never lets a suspect unit proceed without explicit disposition. Most AI agent systems let outputs flow through with optional review.
2. **Disposition is not binary** -- The six-disposition model captures nuance that pass/fail misses. "Almost right" (repair) and "right enough" (use-as-is) are distinct from "needs another try" (rework).
3. **Cost visibility** -- PAF model makes quality costs explicit and traceable. AI agent systems rarely track the full cost of rework loops, human repair time, or downstream failure costs.
4. **Escalation from instance to system** -- The NC-to-CAPA escalation turns individual failures into systemic improvements. Most AI agent systems treat each failure independently.
5. **Authority structure prevents rubber-stamping** -- MRB requires cross-functional consensus. AI "self-review" loops lack genuine independence between generator and evaluator.

---

## Sources

- [Material Review Board: Deciding the Fate of Nonconforming Product -- Tulip](https://tulip.co/blog/material-review-board/)
- [Material Review Board (MRB) -- Nonconformance Disposition -- SG Systems](https://sgsystemsglobal.com/glossary/material-review-board-mrb/)
- [How A Material Review Board Works -- Agilian](https://www.agiliantech.com/blog/material-review-board-mrb/)
- [MRB -- WorkClout](https://www.workclout.com/glossary/material-review-board-mrb)
- [Northrop Grumman QOS 0043 Rev G (Aerospace MRB Procedure)](https://cdn.northropgrumman.com/-/media/Supplier-Documents/Quality-Documents/QOS-0043_Rev_G.pdf)
- [MIT MKI Nonconforming Material Reports](https://snebulos.mit.edu/projects/mki-old/file_cabinet/0/02004/02004_01_rA.pdf)
- [CAPA Requirements in ISO 9001 -- ComplianceQuest](https://www.compliancequest.com/bloglet/capa-iso-9001/)
- [CAPA vs. Nonconformance in ISO 13485 -- APEX Quality](https://apexqualityassurance.com/iso13485-capa-vs-nc/)
- [Deciding Which Events to Escalate into CAPA -- isoTracker](https://www.isotracker.com/blog/deciding-which-events-to-escalate-into-a-capa-system/)
- [Nonconformance Management -- Siemens](https://www.plm.automation.siemens.com/global/en/our-story/glossary/nonconformance-management/36138)
- [Nonconforming Product Control -- SG Systems](https://sgsystemsglobal.com/guides/nonconforming-product-control/)
- [Quarantine -- Quality Hold Status -- SG Systems](https://sgsystemsglobal.com/glossary/quarantine-quality-hold-status/)
- [Material Quarantine: Definition, Status Rules, and Release -- SG Systems](https://sgsystemsglobal.com/glossary/material-quarantine/)
- [First Pass Yield -- MachineMetrics](https://www.machinemetrics.com/blog/first-pass-yield)
- [First Pass Yield in Manufacturing -- 6Sigma.us](https://www.6sigma.us/manufacturing/first-pass-yield-fpy/)
- [Cost of Quality -- ASQ](https://asq.org/quality-resources/cost-of-quality)
- [Cost of Quality -- Tulip](https://tulip.co/blog/cost-of-quality/)
- [Cost of Poor Quality -- 6Sigma.us](https://www.6sigma.us/process-improvement/copq-cost-of-poor-quality/)
- [SWE-126 Waiver and Deviation Considerations -- NASA SWEHB](https://swehb.nasa.gov/display/SWEHBVB/SWE-126+-+Waiver+and+Deviation+Considerations)
- [Deviation vs. Waiver -- ASQ Forum](https://my.asq.org/discuss/viewtopic/99/120)
- [Nonconformance Report: Definition, Example, and Process -- SimplerQMS](https://simplerqms.com/non-conformance-report/)
- [NCR Guide -- NCR Software](https://www.ncr-software.com/what-is-non-conformance-reporting-ncr/)
- [Major vs. Minor Non-Conformities -- Qualityze](https://www.qualityze.com/blogs/major-minor-critical-non-conformities)
- [Agentic AI Coding Best Practice Patterns -- CodeScene](https://codescene.com/blog/agentic-ai-coding-best-practice-patterns-for-speed-with-quality)
- [Demystifying Evals for AI Agents -- Anthropic](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Background Coding Agents: Feedback Loops -- Spotify Engineering](https://engineering.atspotify.com/2025/12/feedback-loops-background-coding-agents-part-3)
- [Agentic AI Code Review: From Confidently Wrong to Evidence-Based](https://dev.to/alexandreamadocastro/agentic-ai-code-review-from-confidently-wrong-to-evidence-based-pne)

<!-- flux-research:complete -->
