---
agent: fd-systems
tier: plugin-cognitive
model: haiku
input: interflux-insight-efficiency-openrouter/input.md
track: b (operational parallel disciplines — Stage 2 expansion)
expansion_reason: high-severity convergence from Stage 1 (3 P0 findings, feedback loop gaps identified)
---

# fd-systems — Findings

> Cognitive lens: feedback loops, emergence, causal reasoning, systems dynamics.
> Peer findings reviewed: SCM-01 (silent partial review), BSR-01 (quality monitoring gap), NDT-01 (unverified P0s), TCA-01 (no TCA), NDT-02 (convergence weighting).

## Findings Index

| Severity | ID | Section | Title |
|----------|-----|---------|-------|
| Blind Spot | SYS-01 | Architecture | Quality feedback loop entirely absent: system cannot learn from routing decisions |
| Blind Spot | SYS-02 | Cost Model | Efficiency gains and quality degradation are coupled loops — optimizing one destabilizes the other |
| Missed Lens | SYS-03 | Synthesis | Cross-provider convergence is an emergent property, not a design assumption |
| Consider Also | SYS-04 | Long-term | Provider diversity pressure: cheap model capability improves faster than routing logic can track |

---

## Detailed Findings

### Blind Spot — SYS-01: Quality Feedback Loop Entirely Absent

**Systems framing:** Every stable optimization system requires a feedback loop between outcomes and decisions. Without feedback, the system cannot self-correct — it either drifts into a local optimum and freezes there, or it degrades without signal.

**Gap in the design:** The input document describes routing logic (agent_type → model tier) and cost savings, but contains no description of how routing decisions are updated based on outcomes. This is not a P2 "nice to have" — it's a structural gap. A routing system without a feedback loop is not a routing system; it's a one-time configuration.

**Causal chain:**
1. Routing logic assigns cheap model to agent type X
2. Cheap model produces findings (good or bad)
3. Synthesis aggregates findings
4. User reviews output (accepts/dismisses findings)
5. **Nothing feeds back to step 1** — routing logic is unchanged

**The four missing feedback loops:**
- **Quality signal loop:** finding acceptance rates per provider → routing weight adjustment
- **Cost signal loop:** actual cost per finding per provider → budget.yaml updates
- **Calibration loop:** severity accuracy (hallucinated P0s) → provider trust score
- **Latency loop:** response time per provider → dispatch timeout and failover settings

**Fix (architectural):** The feedback loops don't need to be automatic to start. Even a manual reporting cycle closes the loop: `scripts/estimate-costs.sh` could include a `--routing-report` flag that outputs per-provider quality/cost metrics from interstat. A human reviewing this report weekly closes the calibration loop. Automatic rebalancing is iteration 2.

---

### Blind Spot — SYS-02: Cost and Quality are Coupled Optimization Targets

**Systems framing:** When two metrics are optimized simultaneously in a coupled system, reducing one often increases the other. The relationship between cost and quality in interflux routing is not independent — it's coupled through model capability and finding density.

**The coupling:** Cheap models → lower cost *and* lower finding density → lower convergence scores → lower insight quality. These are not separate effects — they're the same effect viewed from different metrics. Designing routing to "optimize cost without sacrificing quality" assumes the two can be decoupled. For some agent tasks they can; for others they cannot.

**Where the design assumes decoupling:** "Chinese models offer strong reasoning at 10-50x lower cost." This is true for general reasoning benchmarks. But interflux's output quality is measured by *finding density, severity calibration, and cross-agent convergence* — not general reasoning benchmarks. The cost-quality tradeoff for these specific metrics is unknown.

**Emergent risk:** If cheap models reduce finding density across the board, synthesis convergence scores drop. Low convergence triggers fewer Stage 2 expansions (which use cost as a gate). The system reaches a new equilibrium with lower cost *and* lower quality — but because the equilibrium is stable, nothing signals that quality has degraded. The system looks fine by its own metrics.

**Fix (framing):** The design document should explicitly acknowledge the coupling and define the break-even point: "We will route agent type X to cheap models if and only if historical finding density for that agent type on cheap models is within 80% of Claude baseline." Without this explicit threshold, the optimization has no stopping condition.

---

### Missed Lens — SYS-03: Cross-Provider Convergence is Emergent, Not Designed

**Systems framing:** Emergence occurs when system-level properties arise from component interactions in ways that were not explicitly designed. Cross-provider convergence (Claude and DeepSeek independently finding the same issue) is an emergent property of the multi-model system — it cannot be directly designed, only enabled.

**Current design assumption:** The input document assumes that routing different agent types to different models will produce diverse perspectives that improve insight quality. This assumes the diversity is *independent* — that Claude and DeepSeek will find different things and the union will be richer.

**The emergence question:** Will Claude and DeepSeek actually diverge on findings, or will they converge on the same issues (because the issues are real and both models are competent) while missing the same issues (because they share training data)?

**What needs to be designed for emergence:** For cross-provider convergence to be a useful signal, the models must be:
1. **Genuinely independent** on the finding in question (different enough training to not share hallucination patterns)
2. **Comparably sensitive** to the specific domain (cheap models may be excellent on style but weak on security)
3. **Running on the same input section** (if document slicing routes them to different sections, their convergence is meaningless)

None of these conditions are addressed in the design. The diversity benefit is assumed, not engineered.

**Fix:** Add a diversity validation step to qualification (extending SCM-02's calibration process): run Claude and each candidate cheap model on the same synthetic test cases and measure agreement/disagreement rates by finding type. If two models converge >90% on a finding type, they are not independent for that type — routing both to that type adds cost without diversity benefit.

---

### Consider Also — SYS-04: Provider Capability Improves Faster Than Routing Logic

**Systems framing:** In a dynamic system where component capabilities change faster than the system's adaptation rate, the system's behavior lags behind reality. Routing logic based on current model capabilities will be wrong the moment model capabilities change.

**The dynamic:** DeepSeek V3, Qwen 3, Yi, etc. are improving rapidly. A routing decision made today (DeepSeek V3 handles style review adequately but not security review) may be wrong in 6 months when DeepSeek V4 is released. Static routing configuration cannot track this.

**Risk:** The routing logic becomes a conservative governor that prevents cheaper models from being used for tasks they're now capable of, and the cost savings plateau. Alternatively, the routing logic doesn't update to reflect regressions in a model version update.

**Consider also:** The routing logic should have an explicit review cadence tied to major model releases. When DeepSeek R2 releases, the qualification tests (SCM-02 fix) should automatically re-run and the routing configuration should be updated with the new capability profile.

---

## Verdict

**needs-changes**

The systems lens confirms and deepens two of the P0 findings from Stage 1. SCM-01 (silent partial review) and BSR-01 (quality monitoring gap) are not independent problems — they're both symptoms of the same root cause: **no feedback loop from routing outcomes to routing decisions**. The system will inevitably drift without one.

The most important systems insight: **the design optimizes for the initial state, not for stable operation**. A routing system with no feedback loop is a routing system designed for a world where model capabilities don't change, provider reliability is constant, and finding quality is uniform. None of these assumptions hold. The feedback loop design is as important as the routing logic itself.

**Alignment:** Multi-model dispatch aligns with PHILOSOPHY.md's "adopt mature tools" principle — OpenRouter is a mature multi-model gateway. The feedback loop gap is a systems design concern, not a philosophy misalignment.

**Conflict/Risk:** The cost optimization pressure may create incentive to ship routing without feedback loops ("we'll add that later"). "Later" never comes for feedback mechanisms; they need to be designed in from the start.

<!-- flux-drive:complete -->
