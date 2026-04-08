---
artifact_type: flux-drive-findings
track: orthogonal
target: docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md
date: 2026-04-04
agents: [fd-clinical-triage-resource, fd-insurance-actuarial, fd-power-grid-dispatch, fd-news-editorial]
---

# Flux-Drive Findings: Cross-Model Dispatch — Track B (Orthogonal)

Target: `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
Focus: Operational patterns from parallel professional disciplines — emergency medicine triage, actuarial risk pricing, power grid economic dispatch, news editorial assignment — mapped to the brainstorm's resource allocation patterns.

---

## fd-clinical-triage-resource

### Finding 1: Four-Level Triage Is Medically Inadequate — The ESI Has Five Levels for a Reason

**Severity:** P2

**Description:** The brainstorm uses a 4-level expansion score (0–3) to drive model tier selection, with score 0 blocking dispatch entirely and scores 1–3 mapping to distinct treatment. Emergency medicine abandoned 3- and 4-level triage scales in favor of the 5-level Emergency Severity Index because coarser scales produced unacceptable over-triage and under-triage rates (Gilboy et al., ESI Implementation Handbook, 2012). The 4-level scale here collapses two clinically distinct populations into score 2: a P1 finding in a nearly adjacent domain (high urgency) and a P2 finding in a loosely related domain (moderate urgency) both get "keep model." In practice, these two populations have different optimal resource requirements. The current mapping of score 2 → "keep model" papers over a meaningful difference.

**Agent:** fd-clinical-triage-resource

**Recommendation:** Subdivide score 2 into 2a (P1 trigger, adjacent domain) and 2b (P2 trigger, adjacent domain) without changing the public 0–3 API. Inside `routing_adjust_expansion_tier()`, the `_routing_downgrade` call can be conditioned on the P-level of the triggering finding as well as the score, giving a soft 5-level mapping that matches clinical practice. One-line change at the score-2 case in the function sketch in the brainstorm.

---

### Finding 2: No Reassessment Protocol — Tier Is One-Shot with No Upgrade Path

**Severity:** P1

**Description:** Emergency triage mandates reassessment when patient condition changes — a score-3 patient who deteriorates mid-wait is re-triaged to score-1 before reaching a clinician. The brainstorm assigns tier once, at Step 2.2b, before Stage 2 dispatch. If a haiku-tier agent's partial findings — returned before all Stage 2 agents complete — indicate a domain is more critical than the expansion score suggested, there is no mechanism to upgrade that agent's tier or spawn a supplementary higher-tier agent. The current architecture treats tier assignment as irreversible, which is the triage equivalent of refusing to reassess a waiting patient. The risk is concentrated in exactly the scenario the brainstorm optimizes for: a score-1 expansion candidate that turns out to contain a cross-cutting P0.

**Agent:** fd-clinical-triage-resource

**Recommendation:** Add a reassessment hook to the synthesis layer (Step 2.3 or equivalent). After each batch of agent completions, compare the set of findings already returned against the tier assigned to still-running agents. If any finding's severity is two or more levels above the expansion score that drove the tier assignment, flag the corresponding running agents for a "tier escalation" note in the log. In the short term this is advisory; in future iterations it can trigger a supplemental agent at the higher tier. This does not require dynamic agent restart — only logging and a post-run escalation record.

---

### Finding 3: Under-Triage Risk Asymmetry Not Modeled

**Severity:** P1

**Description:** ED triage doctrine is asymmetric: over-triage (assigning too many resources to a low-acuity patient) wastes capacity but does not kill. Under-triage (assigning too few resources to a high-acuity patient) kills. The brainstorm's risk table (§Risk Assessment) acknowledges "finding quality degrades on haiku" as Medium likelihood / Medium impact, but frames the mitigation as monitoring via intertrust precision scores — a lagging indicator. There is no prospective asymmetric weighting applied at dispatch time. A domain where haiku under-performance is merely annoying (fd-game-design) is treated identically to one where it is genuinely dangerous (a checker agent whose domain borders fd-safety). The brainstorm's safety floors only protect the two explicitly named agents (fd-safety, fd-correctness). Every other agent is subject to symmetric risk treatment even when the asymmetry is significant.

**Agent:** fd-clinical-triage-resource

**Recommendation:** Add an `undertriage_risk` field to agent-roles.yaml (values: `low`, `moderate`, `high`). Agents whose findings, if missed, could mask P0s in adjacent domains receive `high`. The `routing_adjust_expansion_tier()` function should treat `undertriage_risk: high` as an implicit soft floor: score-1 agents with high undertriage risk get sonnet rather than haiku, even without a formal safety floor designation. This extends the safety floor concept without inflating the explicit floor list.

---

### Finding 4: Triage Nurse Competency — Who Validates Expansion Scoring?

**Severity:** P2

**Description:** In emergency medicine, the triage decision is only as good as the nurse making it. ESI research shows that triage accuracy varies significantly by nurse experience and domain familiarity, and that triage scores systematically drift under workload pressure. The brainstorm's expansion scoring (Step 2.2b) is algorithmic, but it depends on domain injection signals and Stage 1 finding severity — both of which carry their own uncertainty. The brainstorm asks in Open Question 3 whether tier adjustment data should feed into interspect for calibration, but defers it. Until calibration exists, there is no feedback loop validating that expansion scores are accurate enough to be trusted as tier-selection inputs. A triage system with uncalibrated nurses operating on high-acuity cases is a patient safety event waiting to happen.

**Agent:** fd-clinical-triage-resource

**Recommendation:** Promote Open Question 3 from deferred to in-scope for the first iteration. The minimum viable calibration is a log field: for each tier-adjusted dispatch, record `(agent, expansion_score, adjusted_tier, finding_severity_returned)`. After 20 runs, a simple correlation check answers whether score-1 agents dispatched at haiku are returning findings that would have been P1 or higher at sonnet. This is the triage audit — it does not require interspect integration immediately, just structured logging.

---

## fd-insurance-actuarial

### Finding 5: Expansion Score Is Not an Expected Value — It Conflates Probability and Severity

**Severity:** P1

**Description:** The brainstorm treats expansion score (0–3) as a sufficient proxy for the value of investing in a higher-tier agent. Actuarially, the correct investment signal is `P(finding) × severity(finding)`, not a composite score that blends adjacency (a proximity measure) with finding severity (an existing signal). A score-3 expansion from a distant domain with high domain injection confidence might have lower expected value than a score-2 expansion in an immediately adjacent domain with a confirmed P1 trigger. The current mapping collapses these into the same tier assignment. In insurance terms, the brainstorm is using exposure (proximity) as a proxy for expected loss — a known actuarial error that leads to systematic mispricing. The practical consequence is that some score-2 agents will be over-resourced and some score-3 agents under-resourced relative to their actual expected contribution.

**Agent:** fd-insurance-actuarial

**Recommendation:** Decompose expansion score into two explicit components at Step 2.2b: `trigger_confidence` (how certain are we this domain is relevant: 0.0–1.0) and `trigger_severity` (P-level of the triggering finding: 0–3). Use their product as the effective dispatch signal rather than a pre-baked composite. The existing scoring algorithm already computes precursors to both; this is an output format change, not a redesign. `routing_adjust_expansion_tier()` then takes two parameters instead of one score, enabling finer mapping.

---

### Finding 6: Correlated Downgrade Risk — Portfolio-Level P0 from Individual Haiku Decisions

**Severity:** P1

**Description:** Actuarial risk management distinguishes individual risk (one policy) from correlated risk (systemic failure across a portfolio). The brainstorm's budget-pressure mechanism can force all non-exempt Stage 2 agents to haiku simultaneously when `remaining_budget < 50%`. This treats each agent as an independent risk unit, but the agents' domains are deliberately structured to cover adjacent concerns. Three haiku-tier agents each missing one facet of a cross-cutting architectural issue — none of which individually rises to P0 in isolation — can compound into a P0 the synthesis layer would catch if any one of them had run at sonnet. The brainstorm's risk table does not mention correlated failure; it assesses "finding quality degrades on haiku" as per-agent, not portfolio-level.

**Agent:** fd-insurance-actuarial

**Recommendation:** Add a correlated-risk cap to the budget-pressure downgrade: when budget pressure is "high," limit the number of simultaneously downgraded agents to `floor(total_stage2_count / 2)`. Sort agents by expansion score descending and protect the top half at their original tier, downgrading only the lower half. This is reinsurance stop-loss logic: individual risk is shared, but catastrophic correlated loss is capped. The implementation is a sort-and-split before the budget-pressure override in `routing_adjust_expansion_tier()`.

---

### Finding 7: No Loss Experience Feedback — Calibration Data Not Collected

**Severity:** P2

**Description:** Insurance pricing requires continuous premium adjustment based on actual loss experience. The brainstorm's Open Question 3 defers calibration to interspect. Without loss experience data, the tier-to-outcome mapping is set once (score 1 → downgrade) and never updated, even if the mapping proves wrong. Actuaries call this "pricing to prior" — using historical rate tables rather than current claims data. After 50 runs of cross-model dispatch, the team will have no empirical basis for knowing whether score-1 haiku agents missed anything important, whether score-3 sonnet agents provided marginal value over haiku, or whether the 50% budget pressure threshold is correctly calibrated.

**Agent:** fd-insurance-actuarial

**Recommendation:** The minimum loss-experience record is three fields appended to the existing tier-adjustment log: `adjusted_tier`, `finding_count`, `highest_finding_severity`. These are available at run completion with no additional infrastructure. After 20 runs, a table of `(expansion_score, adjusted_tier, max_finding_severity)` provides the empirical basis for recalibrating the score → tier mapping. This is actuarial experience rating at its simplest — no exotic statistics required.

---

### Finding 8: Reserve Requirements — Are Safety Floors Set at the Right Level?

**Severity:** P2

**Description:** Statutory reserves in insurance are set based on actuarial analysis of tail risk, not convention. The brainstorm's safety floors (fd-safety and fd-correctness ≥ sonnet) are described as "non-negotiable" but their scope is justified by role designation, not by analysis of which agents are most likely to produce consequential misses at haiku tier. The agent-roles.yaml shows that fd-resilience, fd-decisions, and fd-people are all checker-tier (haiku) with no floor. For a codebase review, fd-resilience missing a cascading failure mode or fd-decisions missing a decision boundary error could be as consequential as fd-safety missing an XSS. The reserve list may be set too conservatively (only covering named safety roles) when actuarial analysis of actual miss rates by domain would extend it.

**Agent:** fd-insurance-actuarial

**Recommendation:** Before deploying cross-model dispatch, run a one-time retrospective on the last 10 flux-drive sessions: for each session, identify which agents produced the highest-severity findings. If any checker-tier agent produced P0 or P1 findings in more than 30% of runs, it is a candidate for an implicit soft floor (per Finding 3's `undertriage_risk: high` mechanism). This is the actuarial equivalent of re-underwriting high-loss accounts before rolling out a new pricing model.

---

## fd-power-grid-dispatch

### Finding 9: Merit Order Inversion — High-Confidence Agents Should Dispatch First, Not Simultaneously

**Severity:** P2

**Description:** Economic dispatch in power grids dispatches generating units in strict merit order: cheapest unit committed first, more expensive units added as demand increases. Cross-model dispatch inverts this: it assigns the most expensive resource (sonnet/opus) to the highest-confidence signal, which is correct in principle. However, the brainstorm does not specify the order in which `routing_adjust_expansion_tier()` is called across the Stage 2 agent pool. If agents are processed in arbitrary order (e.g., alphabetical by agent name), a high-confidence agent processed later may inherit a "high pressure" budget state caused by lower-confidence agents processed earlier consuming the budget estimate. In grid terms, a cheap baseload unit committed last due to processing order would be forced offline to make room for peakers committed first — the exact inversion merit order prevents.

**Agent:** fd-power-grid-dispatch

**Recommendation:** In the expansion.md step that iterates over Stage 2 candidates (§Changes to expansion.md), specify that agents must be processed in descending expansion score order before tier adjustment. High-score agents get first claim on the budget headroom; low-score agents are adjusted against whatever pressure state remains. Add a sort step before the `for each expansion candidate` loop. This is a two-line change that eliminates merit order inversion.

---

### Finding 10: No Reserve Capacity for Late-Arriving Speculative Launches

**Severity:** P1

**Description:** Grid operators maintain spinning reserves — committed generation capacity held back from active dispatch — specifically to handle N-1 contingency events and late load additions. The brainstorm computes `budget_pressure` as `remaining_budget / sum(stage2_estimates)` at the time of Stage 2 tier adjustment. Speculative launches (Step 2.2a.6) are characterized as "early Stage 2 agents" that "use the same logic," but they arrive after the main Stage 2 budget allocation has already been computed. A run that dispatches the full Stage 2 pool at computed tiers may leave insufficient headroom for a speculative launch that arrives mid-run, forcing it to haiku even if its expansion score is 3. There is no spinning reserve — capacity explicitly set aside for late contingency.

**Agent:** fd-power-grid-dispatch

**Recommendation:** When computing `budget_pressure` for Stage 2 dispatch, subtract a speculative launch reserve: `effective_budget = remaining_budget - (speculative_launch_count × avg_sonnet_cost_per_agent)`. The constant `speculative_launch_count` is the cap already established in Step 2.2a.6 (max 2). This reserve means budget pressure is computed against a slightly smaller available pool, but ensures speculative launches can run at sonnet when warranted. The reserve is only consumed if speculative launches actually trigger; if not triggered, the headroom is released to cost savings.

---

### Finding 11: Congestion Pricing vs. Hard Cutoff — Budget Pressure Should Be Continuous

**Severity:** P2

**Description:** The brainstorm defines budget pressure as three discrete states (low / medium / high) with "medium" producing no tier adjustment. In grid economics, congestion is priced continuously — the locational marginal price (LMP) rises smoothly as constraints tighten, and dispatch decisions reflect the marginal cost at each increment. The brainstorm's binary "medium has no effect" creates a cliff: a run at 51% remaining budget is treated identically to one at 79% remaining, while a run at 49% triggers a full downgrade of all non-exempt agents. A continuous pressure function — where the probability or scope of downgrade increases gradually — would produce better cost-quality trade-offs than a cliff-edged threshold.

**Agent:** fd-power-grid-dispatch

**Recommendation:** Replace the three-state pressure enum with a continuous `pressure_ratio` (0.0–1.0) passed to `routing_adjust_expansion_tier()`. The function can implement the threshold logic internally for now, but the API should accept a float so the thresholds can be tuned without changing callers. As a second step, replace the score-1-only downgrade at medium pressure with a probabilistic downgrade at medium: score-1 agents get haiku, score-2 agents get haiku with probability `(0.8 - pressure_ratio)`. This makes the budget degradation curve continuous rather than stepped.

---

### Finding 12: Ramping Constraint — Model Switching Has a Context-Loss Cost Not Modeled in Budget

**Severity:** P3

**Description:** Power grid units have ramping constraints — a gas turbine cannot go from 0 to full output instantly; the transition itself has a cost (fuel, wear, emissions). The brainstorm models model tier as a switching variable but does not account for the cost of running an agent at a different tier than its canonical role assignment. In practice, an agent designed and prompted as a sonnet-tier reviewer running at haiku tier may produce worse results than a native haiku agent because its prompt structure, expected output length, and reasoning depth assumptions were calibrated for sonnet. This is not a financial cost but a quality cost — a ramping constraint on effective capability rather than tokens.

**Agent:** fd-power-grid-dispatch

**Recommendation:** Note in the implementation spec that `routing_adjust_expansion_tier()` should preferentially select agents whose canonical model_tier matches the target tier over agents being downgraded into that tier. When two expansion candidates have identical expansion scores and one is natively haiku while the other is being downgraded from sonnet, prefer the native haiku agent. This is a tiebreaker rule, not a veto, and requires no architectural change — just a sort key addition in AgentDropout (Step 2.2a.5).

---

## fd-news-editorial

### Finding 13: No Escalation Path from Low-Tier to High-Tier on Material Discovery

**Severity:** P2

**Description:** Newsrooms have a stringer-to-staff escalation protocol: a stringer who calls the desk with credible evidence of a major story is reassigned to a senior reporter. The brainstorm has no equivalent. A haiku-tier agent (stringer) that returns findings suggesting the domain is more critical than the expansion score predicted has no path to escalate. Its output goes into the synthesis pool alongside sonnet findings, but the synthesis layer cannot re-dispatch the haiku agent at a higher tier or spawn a supplemental higher-tier agent to follow up on the haiku finding's lead. The fd-news-editorial agent's P2 scenario in its severity calibration identifies exactly this: "a haiku-tier 'stringer' agent produces a partial finding that hints at P0, but lacks capability to fully develop it." There is no protocol for escalation.

**Agent:** fd-news-editorial

**Recommendation:** Add an escalation signal to the agent output schema: a `capability_limited` flag that an agent can set when its finding suggests the domain warrants higher-tier investigation than was provided. This flag does not trigger automatic re-dispatch (that is out of scope per the brainstorm's constraints) but it is surfaced in the synthesis layer's output as an advisory: "fd-game-design flagged capability limitation — consider re-running at sonnet for this domain." The flag can be set by the agent's prompt instructions when it encounters findings that exceed its confidence threshold. This is the stringer calling the desk, not the desk pre-empting the stringer.

---

### Finding 14: AgentDropout Kill Is Irreversible — No Story Revival Path

**Severity:** P2

**Description:** Editorial kill decisions in newsrooms are reversible — a story killed for space reasons can be revived when news value increases. AgentDropout (Step 2.2a.5) prunes redundant Stage 2 candidates, and the brainstorm's constraints note "Budget enforcement remains a separate gate." But neither the AgentDropout design nor the brainstorm address what happens when a dropped domain becomes relevant after Stage 2 findings. If Stage 2 reveals an unexpected cross-cutting concern that touches a dropped agent's domain, there is no path to revive that agent within the current run. The story is killed; the reporters have moved on. In a multi-run workflow this is acceptable; in a single-run review this means a finding domain is permanently unexamined once dropped.

**Agent:** fd-news-editorial

**Recommendation:** Add a "parked" state to the AgentDropout output: agents dropped for redundancy (not budget) are marked `parked` rather than discarded. The synthesis layer checks parked agents' domains against the set of Stage 2 findings. If any finding's domain overlaps with a parked agent's domain, the synthesis notes the coverage gap. This is not automatic re-dispatch but it closes the observability gap: the reviewer knows a potentially relevant domain was dropped and can act on that information. Implementation requires no change to dispatch logic — only an output record change in AgentDropout.

---

### Finding 15: Editorial Judgment Bottleneck — Expansion Scoring Requires Calibrated Domain Knowledge

**Severity:** P2

**Description:** Senior editors make assignment decisions because they have calibrated domain knowledge: they know which sources are reliable, which story types have hidden complexity, and which desks are understaffed. The brainstorm's expansion scoring drives tier decisions algorithmically, but the scoring itself encodes domain judgments — which adjacencies are "P0" versus "P1," how to weight domain injection signals, what constitutes a "distant P2 adjacency signal." These judgments are currently embedded in the scoring algorithm's design and are not themselves subject to review. As the agent pool grows (more fd-* agents covering more domains), the expansion scoring algorithm's domain knowledge will age and drift from the actual capability distribution. The editor who is also making all the assignment decisions without supervision is a single point of failure.

**Agent:** fd-news-editorial

**Recommendation:** Document the expansion scoring algorithm's domain assumptions in a dedicated comment block in expansion.md: which adjacency relationships are considered P0-adjacent, and on what basis. This serves two purposes: it makes the editorial judgment visible and reviewable rather than implicit in code, and it creates a checklist for updating expansion scoring when new agents are added or domain relationships change. This is the editorial guidelines document — not a process change, just making the existing judgment explicit.

---

### Finding 16: Desk Assignment Is Missing — Only Reporter Seniority Changes, Not Domain Routing

**Severity:** P3

**Description:** Newsrooms assign stories to desks (domain specialization) AND seniority (capability). The brainstorm's cross-model dispatch adjusts only capability (model tier) while leaving domain routing unchanged. This is correct for the stated scope — domain routing is a separate concern. However, there is one case where tier adjustment and domain routing interact: when the triggering finding for a Stage 2 agent's expansion is in a subdomain that falls between two agents' coverage areas. A haiku-tier checker assigned to fd-resilience might be a poor match for a finding that actually concerns distributed systems consistency — a topic where fd-architecture at sonnet would provide better coverage. The two decisions (which agent, what tier) should at minimum log when they are suboptimal together.

**Agent:** fd-news-editorial

**Recommendation:** In the Stage 2 dispatch log, record the triggering finding's domain alongside the assigned agent and tier. When the triggering domain does not match the assigned agent's primary domain (as declared in agent-roles.yaml), add a `domain_mismatch: true` flag. This is advisory — no dispatch change — but it surfaces cases where both desk assignment and seniority are suboptimal simultaneously, which is the highest-risk editorial combination. Adds one field to the existing logging block in the brainstorm's §Logging section.

---

## Cross-Agent Synthesis

The four orthogonal disciplines converge on three gaps the brainstorm does not address:

**1. The escalation gap.** Neither emergency triage (reassessment), editorial practice (story escalation), nor grid dispatch (contingency reserve) treats initial resource assignment as final. The brainstorm's tier assignment is one-shot. The minimum viable addition is an escalation signal in the agent output schema (Finding 13) combined with a reassessment hook in the synthesis layer (Finding 2). These two changes together close the gap without requiring dynamic agent restart.

**2. The correlated failure gap.** Actuarial risk (Finding 6) and clinical triage (Finding 3) both identify that independent per-agent decisions can produce correlated systemic failures. The budget-pressure mechanism's simultaneous haiku downgrade is the primary risk vector. The cap on simultaneously downgraded agents (Finding 6) is the most direct mitigation.

**3. The calibration gap.** All four disciplines depend on feedback loops to maintain decision quality over time (loss experience in insurance, triage audit in emergency medicine, merit order updates in grid dispatch, source reliability tracking in editorial). The brainstorm defers calibration to interspect. The minimum viable feedback mechanism — structured logging of `(expansion_score, adjusted_tier, max_finding_severity)` per run — is buildable now and does not require interspect integration (Findings 4, 7).

**Highest-priority finding by discipline:**
- Clinical triage: P1 — no reassessment protocol for tier escalation mid-run (Finding 2)
- Actuarial: P1 — correlated downgrade risk during budget-pressure override (Finding 6)
- Power grid: P1 — no spinning reserve for speculative launches (Finding 10)
- Editorial: P2 — no escalation path from haiku finding to higher-tier followup (Finding 13)
