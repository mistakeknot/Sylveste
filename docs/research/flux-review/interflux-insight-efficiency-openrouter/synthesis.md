---
artifact_type: review-synthesis
method: flux-review
target: "docs/research/flux-review/interflux-insight-efficiency-openrouter/input.md"
target_description: "Improving interflux multi-agent review: insight quality and token efficiency via OpenRouter"
tracks: 4
track_a_agents: [fd-openrouter-dispatch-integration, fd-heterogeneous-fleet-cost-routing, fd-model-divergence-signal-extraction, fd-prompt-portability-across-families, fd-api-resilience-and-observability, fd-systems, fd-decisions, fd-resilience]
track_b_agents: [fd-trading-desk-order-routing, fd-supply-chain-multi-sourcing, fd-broadcast-signal-routing, fd-news-desk-source-triage, fd-systems]
track_c_agents: [fd-murano-furnace-workshop-allocation, fd-javanese-gamelan-tuning-interference, fd-korean-onggi-microbial-terroir, fd-assay-master-multi-method-verification]
track_d_agents: [fd-javanese-gamelan-colotomic-interlocking, fd-persian-qanat-gradient-cascade, fd-tswana-kgotla-consensus-synthesis]
date: 2026-04-06
---

# Cross-Track Synthesis: Interflux Insight Quality & Token Efficiency via OpenRouter

**Verdict:** needs-changes (consensus across all tracks; Track D escalated to risky)

**Total findings:** 79 across 21 agents, 4 tracks
- P0: 6 (Track A: 1, Track B: 3, Track C: 0, Track D: 2)
- P1: 31
- P2: 30
- P3: 12

---

## Critical Findings (P0/P1)

### P0-1: DeepSeek R1 reasoning traces break Findings Index parsing

**Surfaced by:** fd-prompt-portability (Track A, PP-1), fd-openrouter-dispatch-integration (Track A, OD-3)

DeepSeek R1 produces `<think>...</think>` preamble before structured output. The synthesis parser checks whether the first non-empty line starts with `### Findings Index` -- reasoning traces cause classification as malformed, losing all structured finding data. OpenRouter may substitute R1 for V3 during capacity constraints unless model IDs are pinned exactly.

**Fix:** Strip `<think>` blocks from OpenRouter responses before `.md.partial` write. Pin exact model IDs in provider config (`deepseek/deepseek-chat` not `deepseek/deepseek-reasoner`).

### P0-2: Silent partial review -- provider outage is invisible to the user

**Surfaced by:** fd-supply-chain-multi-sourcing (Track B, SCM-01), fd-broadcast-signal-routing (Track B, BSR-01)

Two complementary failure modes: (a) provider outage causes agents to silently drop -- the review completes with fewer agents but looks identical to a full review; (b) provider degradation causes shallow output that passes format validation -- a cheap model producing 2 findings where Claude would produce 7 is indistinguishable from a clean codebase. The user cannot detect either condition.

**Fix:** Explicit fallback routing on outage (re-dispatch to Claude haiku, surface `provider_fallback` warning). Findings density monitoring in synthesis: flag cheap-model agents producing >50% fewer findings than historical baseline for that agent type.

### P0-3: Single-source P0 findings from cheap models enter synthesis without verification

**Surfaced by:** fd-news-desk-source-triage (Track B, NDT-01)

A cheap model may hallucinate a P0 finding that no other agent corroborates. Synthesis includes all P0 findings regardless of convergence. The user invests hours investigating a phantom issue. Trust in interflux erodes.

**Fix:** Flag any P0/P1 finding that is single-source AND from a provider below top quality tier with `verification_recommended: true`. Optionally auto-escalate to a Claude verification agent via the existing expansion mechanism.

### P0-4: Synthesis barrier semantics undocumented -- verdict may form before all voices are heard

**Surfaced by:** fd-tswana-kgotla-consensus-synthesis (Track D, TKC-1), fd-persian-qanat-gradient-cascade (Track D, PQG-3 corroborating)

The synthesis spec says "collect" but does not say "collect all before processing." If the orchestrator processes findings as agents complete (streaming), fast OpenRouter models frame the synthesis before Claude Opus structural analysis arrives. This is the highest-signal Track D finding because it identifies a structural bias that compounds with every other multi-model concern.

**Fix:** Add explicit barrier requirement to synthesis spec: collect all agent outputs completely before beginning findings processing. One behavioral change, no architectural rewrite.

### P0-5: No gradient calibration between prompt complexity and model capability

**Surfaced by:** fd-persian-qanat-gradient-cascade (Track D, PQG-1)

Structural tasks dispatched to coverage-optimized models produce hallucinated findings that poison synthesis. The routing heuristic uses expansion score and budget pressure -- signals about finding volume, not cognitive task complexity. An fd-architecture review of a multi-service plan dispatched to DeepSeek V3 will produce confident-sounding but architecturally incoherent findings.

**Fix:** Gradient check before each non-Claude dispatch: if task is structural/judgment-critical and model tier is coverage, route to Claude. Requires the task-criticality taxonomy (see P1 findings below).

### P1-1: Safety floor enforcement must extend across providers

**Surfaced by:** fd-heterogeneous-fleet-cost-routing (Track A, FC-1), fd-openrouter-dispatch-integration (Track A, OD-5), fd-systems Track A (SYS-1)

`agent-roles.yaml` defines `min_model: sonnet` and `budget.yaml` lists `exempt_agents: [fd-safety, fd-correctness]`. These floors only operate within Claude tiers. DeepSeek's safety training covers different threat models than Claude's.

**Fix:** Add `provider_floor: claude` to exempt_agents. The routing logic checks: if agent in exempt_agents and resolved_provider != "claude", override to claude.

### P1-2: Bash-tool dispatch is architecturally wrong -- use an MCP server

**Surfaced by:** fd-openrouter-dispatch-integration (Track A, OD-1), fd-api-resilience-and-observability (Track A, AR-1, AR-2), fd-korean-onggi-microbial-terroir (Track C, ONG-1)

Bash tool returns response content into the orchestrator's context window. Dispatching 4 agents via curl dumps ~48K tokens of raw response into the host context, defeating the token efficiency goal. Additionally, Bash dispatch has no failure isolation: a 60-second DeepSeek API timeout blocks the orchestrator, stalling flux-watch.sh.

**Fix:** Build an `openrouter-dispatch` MCP server that accepts prompt + output path, writes response using the `.md.partial` protocol, returns only status. This gets Claude Code's MCP client error handling, timeout management, and tool-level retry.

### P1-3: Token accounting has no provider dimension

**Surfaced by:** fd-openrouter-dispatch-integration (Track A, OD-2), fd-api-resilience-and-observability (Track A, AR-3), fd-heterogeneous-fleet-cost-routing (Track A, FC-2)

`budget.yaml` cost_basis, `token-count.py`, and interstat recording all assume Claude JSONL format. OpenRouter returns OpenAI-compatible usage JSON with different fields and fundamentally different cost-per-token rates.

**Fix:** Add `provider_costs` section to budget.yaml. Extend token-count.py to parse OpenRouter response JSON. Include per-provider rates in the synthesis cost report.

### P1-4: Prompt template breaks on non-Claude models in 3 specific ways

**Surfaced by:** fd-prompt-portability (Track A, PP-2, PP-3), fd-javanese-gamelan-tuning-interference (Track C, GAM-3), fd-korean-onggi-microbial-terroir (Track C, ONG-2), fd-javanese-gamelan-colotomic-interlocking (Track D, JGC-3)

XML tags lose semantic meaning (treated as literal text), system prompt messages get deprioritized or ignored, and persona instructions degrade to flavor text. Sending Claude-designed prompts to all models creates prompt monoculture, suppressing the analytical diversity that justifies multi-model dispatch.

**Fix:** Create per-model-family prompt variants: XML to markdown, system+user flattened, explicit format examples. Preserve identical output format requirements across variants; vary only analytical framing.

### P1-5: No task-criticality taxonomy protects judgment-critical agents from cost-driven reassignment

**Surfaced by:** fd-murano-furnace-workshop-allocation (Track C, MUR-1, MUR-2), fd-javanese-gamelan-colotomic-interlocking (Track D, JGC-1, JGC-5)

Current cross-model dispatch routes by expansion_score and budget_pressure -- signals about finding volume, not the nature of the cognitive work. fd-decisions requires nuanced organizational reasoning; fd-quality requires pattern scanning. Routing both based on budget pressure treats them as equivalent.

**Fix:** Add `config/flux-drive/agent-tiers.yaml` with explicit categories: `judgment_critical` (fd-safety, fd-correctness, fd-decisions -- never non-Claude), `standard_analytical` (fd-architecture, fd-systems, fd-resilience -- sonnet or strong non-Claude), `mechanical_procedural` (fd-quality, fd-perception -- haiku or cheap non-Claude acceptable).

### P1-6: Synthesis destroys model provenance -- cross-model corroboration signal lost

**Surfaced by:** fd-model-divergence-signal-extraction (Track A, MD-1), fd-javanese-gamelan-tuning-interference (Track C, GAM-1), fd-assay-master-multi-method-verification (Track C, ASY-3), fd-news-desk-source-triage (Track B, NDT-02), fd-broadcast-signal-routing (Track B, BSR-04), fd-javanese-gamelan-colotomic-interlocking (Track D, JGC-4)

The deduplication algorithm treats all findings as equivalent regardless of source model. Cross-provider agreement is stronger evidence than same-provider agreement (different training biases produce independent assessments). But the findings schema has no `model_family` field, making this signal invisible.

**Fix:** Add `model_family` to findings schema and `cross_family_convergence` count. Weight cross-family agreement at 1.5x within-family agreement in convergence scoring.

### P1-7: Gateway lock-in -- OpenRouter not evaluated against alternatives

**Surfaced by:** fd-decisions (Track A, DEC-1, DEC-3)

Four alternatives exist: OpenRouter (managed gateway, markup), LiteLLM (self-hosted, no markup), direct provider APIs (lowest cost), local inference (zero API cost). The document treats gateway selection as decided. The starter option is direct DeepSeek API calls for 2 agents, not full OpenRouter integration.

**Fix:** Evaluate at least 2 alternatives. The minimum viable experiment ($0.10, 30 minutes) should precede any engineering investment.

### P1-8: No feedback loop from routing outcomes to routing decisions

**Surfaced by:** fd-systems Track A (SYS-1), fd-systems Track B (SYS-01), fd-trading-desk-order-routing (Track B, TCA-01, TCA-02)

The routing logic assigns model tiers once. There is no mechanism for finding acceptance rates, severity accuracy, or cost-per-finding data to feed back into routing decisions. Without feedback, the system either drifts into a local optimum or degrades without signal.

**Fix:** Add `routing_report` block to synthesis output: per-provider `{model, tokens, cost, findings_count, severity_distribution}`. Even a manual weekly reporting cycle closes the calibration loop.

### P1-9: Budget has no hard partitioning between model families

**Surfaced by:** fd-persian-qanat-gradient-cascade (Track D, PQG-2), fd-javanese-gamelan-colotomic-interlocking (Track D, JGC-2)

Under cost pressure, greedy routing to OpenRouter (cheap) will drain the budget reserved for Claude structural analysis. No physical weir prevents one model family from consuming the entire token budget.

**Fix:** Add family budget partitions to budget.yaml: `claude.min_reserved: 60000` (physical weir that cannot be overridden by downstream pressure), `openrouter.max_allocation: 80000`.

---

## Cross-Track Convergence

These findings appeared independently in 2+ tracks. They are the highest-confidence signals in the review because different analytical traditions reached the same conclusion from different starting points.

### 1. Model provenance must be tracked through synthesis (4/4 tracks)

- **Track A:** fd-model-divergence-signal-extraction (MD-1) frames it as "the synthesis has no provider attribution -- model diversity signal is lost." The fix is a `provider:` metadata field in Findings Index.
- **Track B:** fd-news-desk-source-triage (NDT-02) frames it as "cross-source validation treats all providers equally regardless of reliability history." The fix is provider-weighted convergence scoring. fd-broadcast-signal-routing (BSR-04) frames it as "multi-feed aggregation missing."
- **Track C:** fd-javanese-gamelan-tuning-interference (GAM-1) frames it as "synthesis dedup treats all sources as equivalent -- productive ombak destroyed." fd-assay-master-multi-method-verification (ASY-3) frames it as "within-family corroboration weighted equally to cross-family corroboration."
- **Track D:** fd-javanese-gamelan-colotomic-interlocking (JGC-4) frames it as "kotekan principle named but not operationalized." fd-tswana-kgotla-consensus-synthesis (TKC-2) frames it as "dedup Rule 1 silences minority findings without attribution."

**Convergence score: 4/4.** This is the single highest-confidence finding in the entire review. Every track, using completely independent analytical frameworks, identified the same structural gap: the synthesis pipeline must distinguish cross-family from within-family agreement, and the findings schema must carry model provenance.

### 2. Prompt templates must vary per model family (3/4 tracks)

- **Track A:** fd-prompt-portability (PP-1, PP-2, PP-3) identifies three specific breakage modes: reasoning traces, XML semantic loss, system prompt deprioritization.
- **Track C:** fd-javanese-gamelan-tuning-interference (GAM-3) frames it as "embat-destroying homogenization." fd-korean-onggi-microbial-terroir (ONG-2) frames it as "prompt monoculture suppresses multi-model analytical diversity."
- **Track D:** fd-javanese-gamelan-colotomic-interlocking (JGC-3) frames it as "identical balungan dispatched without garap differentiation."

**Convergence score: 3/4.** Track B did not surface this because its operational disciplines (trading, supply chain, broadcast, newsroom) do not have a natural analog for prompt formatting. The three tracks that did surface it converge on the same fix: per-family prompt variants that preserve output format requirements while varying analytical framing.

### 3. Silent failure is the most dangerous failure mode (3/4 tracks)

- **Track A:** fd-api-resilience-and-observability (AR-4) identifies the undefined partial failure mode. fd-openrouter-dispatch-integration (OD-5) identifies the missing progressive enhancement gate.
- **Track B:** fd-supply-chain-multi-sourcing (SCM-01) frames it as "single-source critical agents with no fallback." fd-broadcast-signal-routing (BSR-01) frames it as "degraded cheap-model output passes through without detection." Both reach P0.
- **Track D:** fd-tswana-kgotla-consensus-synthesis (TKC-1) frames it as "synthesis reads incrementally -- the verdict forms before all voices finish." fd-persian-qanat-gradient-cascade (PQG-3) frames it as "no vertical shafts between dispatch and synthesis."

**Convergence score: 3/4.** Track C addressed infrastructure failure isolation (ONG-1) but framed it as a latency concern rather than a silent-failure concern. The three converging tracks agree: every failure must produce a visible signal, never silence.

### 4. Empirical testing must precede engineering (3/4 tracks)

- **Track A:** fd-decisions (DEC-1) argues for a $0.10 manual experiment before any engineering. fd-perception (PER-1) identifies map/territory confusion between benchmarks and review quality. fd-resilience (RES-2) proposes a staged rollout plan.
- **Track B:** fd-supply-chain-multi-sourcing (SCM-02) frames it as "no supplier qualification -- models added without calibration baseline." fd-systems Track B (SYS-01) frames it as "feedback loop entirely absent."
- **Track C:** fd-assay-master-multi-method-verification (ASY-2) frames it as "all tiers dispatched simultaneously -- no cost-ordered staging where cheap models inform expensive dispatch."

**Convergence score: 3/4.** Track D did not directly address sequencing but its gradient calibration finding (PQG-1) implies the same conclusion: you need empirical data about model capabilities before routing decisions.

### 5. Safety-critical agents must stay on Claude (3/4 tracks)

- **Track A:** fd-heterogeneous-fleet-cost-routing (FC-1) identifies that `exempt_agents` must extend to a `provider_floor: claude`. fd-systems Track A (SYS-1) identifies the cost-quality degradation loop.
- **Track C:** fd-murano-furnace-workshop-allocation (MUR-1) frames it as the maestro-vs-garzone distinction: some tasks require the maestro's hands regardless of cost.
- **Track D:** fd-persian-qanat-gradient-cascade (PQG-1) frames it as gradient calibration: structural tasks require structural models.

**Convergence score: 3/4.** Track B's supply chain agent (SCM-01) addressed fallback for all agents but did not specifically call out safety-critical agents. The three converging tracks agree: judgment-critical agents (fd-safety, fd-correctness, fd-decisions) never route to non-Claude models, regardless of cost savings.

### 6. Feedback loops must be designed from day one, not added later (3/4 tracks)

- **Track A:** fd-systems Track A (SYS-1) identifies the reinforcing cost-quality degradation loop.
- **Track B:** fd-trading-desk-order-routing (TCA-01) frames it as "no post-trade analysis." fd-systems Track B (SYS-01) frames it as "quality feedback loop entirely absent." Both conclude the same thing: a routing system without feedback is a one-time configuration, not a routing system.
- **Track C:** fd-murano-furnace-workshop-allocation (MUR-4) frames it as "no calibration feedback to detect when cheap models underperformed."

**Convergence score: 3/4.** Track D's qanat agent (PQG-3) touched this indirectly with intermediate quality shafts but did not frame it as a feedback loop. The three converging tracks agree: instrument the routing decision and its outcome from day one, even if analysis is initially manual.

---

## Domain-Expert Insights (Track A)

Track A's 9 agents on Opus produced the most technically precise findings. The highest-value insights not already captured in cross-track convergence:

**Cost-quality degradation loop (fd-systems, SYS-1).** Cheaper models produce lower-quality findings, reducing interspect trust scores, downweighting those agents in synthesis, making cheap dispatch self-defeating. Over 50+ reviews, cheap-model agents could become zombie participants -- running and costing tokens but contributing nothing. Fix: trust score floor during model experimentation periods.

**Emergent monoculture through cost pressure (fd-systems, SYS-3).** Cost optimization will push most agents to the single cheapest model, defeating the model diversity goal. If 5/9 agents run on DeepSeek V3, same-provider agreement dynamics return through a different door. Fix: `max_provider_share: 0.5` constraint.

**Benchmarks do not predict review quality (fd-perception, PER-1).** No benchmark measures "can this model produce a structured Findings Index with accurate severity ratings from a domain-specific cognitive lens?" The implicit logic "DeepSeek scores well on benchmarks, therefore it will produce good review findings" is map/territory confusion. The only valid evidence is A/B testing with actual interflux agent prompts.

**Refusal surface differs by model family (fd-prompt-portability, PP-4).** Chinese model families have refusal surfaces around geopolitical content that Claude does not. An fd-safety agent reviewing code that handles government data might get unexpected refusals from a Chinese model, producing an error stub instead of findings.

**Complexity tax is permanent (fd-decisions, DEC-3).** Prompt variants, response validation, reasoning trace stripping, XML-to-markdown conversion -- this complexity persists even if OpenRouter integration is later abandoned. The design should quantify this maintenance burden before committing.

---

## Parallel-Discipline Insights (Track B)

Track B's 5 agents on Sonnet translated operational patterns from trading desks, supply chains, broadcast engineering, and newsrooms. Their convergent meta-lesson for interflux:

**Monitoring before optimization.** All four disciplines monitor source/venue/signal quality continuously before optimizing allocation. Interflux is proposing to optimize allocation before building monitoring. The order should be reversed.

**Fallback as a design requirement, not an afterthought.** In all four disciplines, the cheap source always has an expensive fallback. The fallback is what makes the cheap source safe to use -- without it, the cheap source is a liability, not an asset.

**Source reliability history accumulates over time.** Wire desks have agency reliability scores. Supply chains have supplier scorecards. Trading desks have venue fill quality databases. All four disciplines recognize that source reliability is not known a priori -- it is learned from history. Interflux needs to design for this accumulation from the first run.

**Cheap-source agreement is weaker than cross-source agreement.** Three regional stringers reporting the same story is not as strong as Reuters + AP. Three OpenRouter agents converging may share training biases -- this is corroborated confirmation, not independent confirmation.

**Transaction Cost Analysis equivalent (fd-trading-desk-order-routing, TCA-01).** Six months after shipping, someone will ask "is this actually cheaper?" Without a routing report in synthesis output, the answer requires manual data archaeology. Add `{model, tokens, cost, findings_count, severity_distribution}` per provider to synthesis output.

**Total cost of ownership includes hidden costs (fd-supply-chain-multi-sourcing, SCM-03).** The 10-50x headline cost reduction ignores retry costs (format compliance failures), validation overhead, heterogeneous synthesis overhead, integration maintenance cost, and quality rework cost (bugs that ship because a cheap model missed them). Effective savings are likely 10-20x, still substantial but not the headline number.

---

## Structural Insights (Track C)

Track C's 4 distant-domain agents surfaced a single meta-pattern invisible from within the AI domain:

**The diversity-capture problem.** The value of heterogeneous participants is only realized if the system is explicitly designed to preserve and amplify the heterogeneity, rather than standardizing inputs (prompt monoculture -- Onggi, Gamelan), aggregating outputs without provenance (synthesis without model tracking -- Assay, Gamelan), or routing by the wrong signal (volume pressure instead of task nature -- Murano).

The Venetian maestro who insists on identical techniques from all workers gets consistent but shallow glass. The gamelan tuned to unison sounds dead. The onggi with uniform porosity produces flat fermentation. The Wardein who averages test results without knowing which test measures what hallmarks debased metal.

**Applied to interflux:** the multi-model fleet will be valuable only if the architecture explicitly captures, preserves, and integrates the provenance of heterogeneous outputs. Without model_family tracking, provenance-aware dedup, model-adapted prompts, and judgment-stamped synthesis, the heterogeneous fleet is operationally equivalent to a same-family fleet with higher complexity and lower reliability.

Track C's most distinctive findings:

**Synthesis must make judgment calls on cross-model conflicts (fd-assay-master, ASY-1).** Rule 5 ("Conflicting recommendations -- preserve both with attribution") is correct for same-family conflicts but wrong for cross-model conflicts where one model has a known capability gap. The synthesis must state which assessment it accepts and why, not merely present both.

**Model blind-spot profiles (fd-assay-master, ASY-4; fd-javanese-gamelan, GAM-4).** Accumulate per-model-family empirical profiles of systematic over-flag/under-flag tendencies by finding domain. A DeepSeek P1 performance finding in a known over-flag category carries a prior. Start data collection immediately by logging every cross-family disagreement with domain and severity delta.

**Finding density tracking (fd-murano, MUR-4).** Track `finding_density = findings_count / output_tokens` per agent per model tier. Flag agents where cheap-model density is significantly below baseline -- may indicate the cheap model did less work (short output), not that it found less (clean code).

---

## Frontier Patterns (Track D)

Track D's 3 esoteric-domain agents produced the most structurally novel insights. Their convergent architectural principle:

**Multi-family orchestration requires heterogeneous structural design at all three phases: dispatch, flow control, and synthesis.** The input document treats this as a cost optimization question. The frontier domains reveal it is primarily a structural coherence question.

- **Dispatch (gamelan, JGC-1):** Heterogeneous models require heterogeneous density layers, not just heterogeneous cost tiers. The colotomic principle: richness comes from layers playing different roles at different densities, not from layers playing the same role at different prices. A 3-layer taxonomy (gong/saron/gambang mapped to opus/sonnet/cheap) assigns agents by their natural cognitive density.

- **Flow control (qanat, PQG-2):** Token budgets need hard partitioning between model families (weirs), gradient calibration between task complexity and model capability, and intermediate quality checkpoints for non-Claude output (vertical shafts). Flow management is a first-class concern.

- **Synthesis (kgotla, TKC-1, TKC-2, TKC-3):** Multi-family synthesis requires barrier semantics (all voices before verdict), inline dissent attribution (minority findings get standing), graduated reading order (senior judgment establishes the frame), and consensus rather than unanimity verdict computation.

**Surprising Track D findings not anticipated by inner tracks:**

**Reading order bias (fd-tswana-kgotla, TKC-3).** In multi-model reviews, fast/cheap models complete first. If the orchestrator reads findings in completion order, cheap models establish the synthesis frame before expensive structural analysis arrives. The kgotla principle requires the inverse: read structural (senior) findings first to establish the frame, then integrate coverage (junior) findings. Fix: explicit reading order policy -- reverse cost order (cheapest/fastest last).

**Coordinated density layer shifts (fd-javanese-gamelan, JGC-2).** Budget-pressure tier demotion operates on individual agents. With multi-family dispatch, demoting Claude saron-layer agents without adjusting DeepSeek gambang-layer agents breaks the colotomic structure. Density layers must shift as a coordinated unit, not individually.

**Irreversible flow semantics (fd-persian-qanat, PQG-4).** Unlike Claude Code Agent tool subagents (which operate within the session context and can be retried), OpenRouter HTTP calls are irreversible token spend. The retry policy must differ: fail-fast or preflight validation, not retry-with-better-context.

**Sycophancy pressure is asymmetric in the reaction round (fd-tswana-kgotla, TKC-5).** Cheaper models in the reaction round receive Claude Opus's preliminary findings as context. DeepSeek's training may include patterns that favor deferring to authoritative-sounding prior art. The reaction round should be stratified by density layer to prevent cross-layer sycophancy.

---

## Recommended Action Sequence

Ordered by leverage/cost ratio, starting with the highest-leverage lowest-cost action.

### Phase 0: Validate the hypothesis ($0.10, 30 minutes)

1. **Manual experiment.** Copy 3 recent flux-drive agent prompts, call DeepSeek V3 via curl, compare output quality and format compliance against Claude baseline. This answers "do non-Claude models produce usable findings?" before any engineering. (Track A: DEC-1, RES-2; Track B: SCM-02)

### Phase 1: Instrumentation prerequisites (1-2 days)

2. **Define expand/contract/abandon signposts.** Write pre-committed criteria: expand after 20 shadow reviews with >80% finding recall, contract if false positive rate >2x Claude baseline, abandon if maintenance cost exceeds token savings over 3 months. Pin to the bead. (Track A: DEC-4, RES-2)

3. **Add model provenance to findings schema.** Add `model_family` and `provider` fields to `findings.json` and Findings Index contract. No synthesis changes yet -- collect data first. (Track A: MD-1; Track B: NDT-02, BSR-04; Track C: GAM-1, ASY-3; Track D: JGC-4, TKC-2. 4/4 track convergence.)

4. **Add routing report to synthesis output.** Per-provider `{model, tokens, cost, findings_count, severity_distribution}` block. The data already flows through synthesis -- this is one additional output block. (Track B: TCA-01; Track A: OD-2, FC-2)

### Phase 2: Safety and structural prerequisites (2-3 days)

5. **Define task-criticality taxonomy.** Create `config/flux-drive/agent-tiers.yaml` with `judgment_critical`, `standard_analytical`, `mechanical_procedural` categories. The cross-model dispatch safety floor must consult this taxonomy before any tier adjustment. (Track C: MUR-1, MUR-2; Track D: JGC-1, JGC-5, PQG-1)

6. **Extend safety floors across providers.** Add `provider_floor: claude` to exempt_agents and judgment_critical agents. The routing logic overrides to Claude when these agents would otherwise route to non-Claude. (Track A: FC-1; Track C: MUR-1; Track D: PQG-1)

7. **Document and enforce synthesis barrier semantics.** Explicit requirement: collect all agent outputs completely before beginning findings processing. Never process any agent's findings before all agents have completed or timed out. (Track D: TKC-1)

8. **Create per-model-family prompt variants.** XML to markdown, system+user flattened, explicit format instructions, reasoning trace stripping. Core output format stays identical across variants. (Track A: PP-1, PP-2, PP-3; Track C: GAM-3, ONG-2; Track D: JGC-3)

### Phase 3: Dispatch infrastructure (1-2 weeks)

9. **Build `openrouter-dispatch` MCP server.** Accepts prompt + output path + model, writes response using `.md.partial` protocol, handles retry/backoff/timeout, returns only status. Include: per-agent timeout with immediate error-stub writing on failure, rate limit backoff (1s/2s/4s, max 3 retries), circuit breaker (3 consecutive failures marks provider as down for remainder of review). (Track A: OD-1, AR-1, AR-2, AR-5; Track C: ONG-1)

10. **Add family budget partitions.** `claude.min_reserved` (physical weir), `openrouter.max_allocation`, `max_provider_share: 0.5`. (Track D: PQG-2, JGC-2; Track A: SYS-3)

11. **Add format normalization layer.** Post-processing step before synthesis ingestion: map severity label variants (`CRITICAL`->`P0`, `HIGH`->`P1`), strip reasoning traces, validate Findings Index structure. (Track B: BSR-03; Track A: OD-3, PP-1)

### Phase 4: Shadow mode (2-4 weeks)

12. **Shadow dispatch for checker-role agents.** Route fd-perception, fd-resilience, fd-decisions, fd-people to DeepSeek V3 in shadow mode. Run both Claude and OpenRouter, compare finding recall and format compliance. 20+ reviews minimum. (Track A: FC-I1; Track B: SCM-02; Track C: ASY-2)

13. **Accumulate model blind-spot profiles.** Log every cross-family disagreement with domain, severity delta, and resolution. After 20+ reviews, compute baseline disagreement rates per model pair per domain. (Track C: GAM-4, ASY-4)

### Phase 5: Canary rollout (2-4 weeks)

14. **Route 2 checker-role agents to OpenRouter in 10% of reviews.** Measure finding recall, false positive rate, format compliance, and findings density against Claude baseline. (Track A: RES-2)

15. **Add cross-family convergence weighting to synthesis.** `cross_family_weight: 1.5x`. Inline cross-family severity conflicts in summary.md (not buried in Conflicts section). (Track C: GAM-1, ASY-3; Track D: TKC-2, JGC-4)

16. **Add synthesis judgment mandate for cross-model conflicts.** For conflicts where `model_family` differs, synthesis states which assessment it accepts and why, rather than presenting both. Initially: accept higher-trust model family's assessment, note discrepancy. (Track C: ASY-1)

### Phase 6: Stable operation (ongoing)

17. **Implement cost-ordered staging.** Cheap models run first with a 60-second wait window. Dispatch expensive models only if cheap found P0/P1 in that domain. (Track C: ASY-2; Track D: PQG-1)

18. **Add reading order policy.** Read agent outputs in reverse cost order (cheapest/fastest last) to preserve structural analysis independence. (Track D: TKC-3)

19. **Close the feedback loop.** Quality signal loop (finding acceptance rates per provider), cost signal loop (actual cost per finding per provider), calibration loop (severity accuracy), latency loop (response time per provider). Start manual, automate later. (Track A: SYS-1; Track B: SYS-01, TCA-01)

20. **Trust score floor during experimentation.** During first 20 reviews with a new provider, hold trust scores at pre-migration baseline to separate model quality signal from calibration noise. (Track A: SYS-1)

---

## Synthesis Assessment

### Overall quality of the proposal

The proposal correctly identifies the opportunity (10-50x cost reduction on non-judgment-critical agents) and the highest-value outcome (model diversity as an insight quality amplifier, not just a cost optimization). But it underestimates implementation complexity by treating the integration as a dispatch mechanism when it is actually a structural change to three phases (dispatch, flow control, synthesis). The proposal needs to become a 5-phase rollout plan with empirical validation gates, not a feature spec.

### Highest-leverage improvement

**Add `model_family` to the findings schema and implement cross-family convergence weighting in synthesis.** This is a 2-hour schema change and a 10-line modification to convergence scoring. It transforms model diversity from a hypothesized benefit into a measurable signal. It was identified independently by all 4 tracks (9+ agents), making it the single highest-confidence finding in the review. Without it, every other multi-model improvement is decorative.

### Surprising finding

**Reading order bias in synthesis (Track D, TKC-3).** No inner track anticipated that the order in which the orchestrator reads agent findings would matter. Track D's kgotla agent identified that in multi-model reviews, fast/cheap models complete first, establishing the synthesis frame before expensive structural analysis arrives. The fix (read structural findings first) is counterintuitive -- it reverses the natural completion order. This finding could only emerge from a domain (Tswana consensus governance) that has explicit protocols for managing how speaking order affects collective decision-making.

### Semantic distance value

The outer tracks (C and D) contributed qualitatively different insights that the inner tracks could not have produced.

**Track C** identified the diversity-capture problem as a meta-pattern: the architecture must be designed to preserve heterogeneity, not standardize it. This reframed the entire proposal from "which agents to route where" to "how to make heterogeneous outputs genuinely useful." The assay master's judgment mandate (ASY-1) -- synthesis must stamp the hallmark on cross-model conflicts, not defer -- is a structural requirement no inner-track agent identified.

**Track D** identified three structural requirements that no inner track surfaced: density-layer architecture (gamelan), hard budget partitioning (qanat weirs), and synthesis legitimacy governance (kgotla barrier semantics + reading order + inline dissent). These are not alternative framings of inner-track findings -- they are structurally novel requirements that only became visible at maximum semantic distance.

The semantic distance gradient worked as designed: Track A identified what breaks and what to fix. Track B identified how other disciplines solved the same problem. Track C identified the structural pattern underneath the specific problem. Track D identified the architectural principles that govern how the whole system must be redesigned. Each successive track added a layer of abstraction that the previous track could not reach.
