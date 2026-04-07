# Track D — Frontier Domain Review: Summary

**Verdict:** risky

**Input:** `/home/mk/projects/Sylveste/docs/research/flux-review/interflux-insight-efficiency-openrouter/input.md`
**Topic:** Making Interflux Better — Insight Quality and Token Efficiency
**Track:** D — Frontier Patterns from Maximally Unexpected Domains
**Agents:** fd-javanese-gamelan-colotomic-interlocking, fd-persian-qanat-gradient-cascade, fd-tswana-kgotla-consensus-synthesis
**Reviewed:** 2026-04-06

---

## Key Findings

### P0 — Critical Issues (2)

- **No gradient calibration between prompt complexity and model capability** (1/3 agents: fd-persian-qanat-gradient-cascade)
  PQG-1 — Before OpenRouter integration is production-ready, a gradient check must gate each non-Claude dispatch. Without it, structural tasks dispatched to coverage-optimized models produce hallucinated findings that poison synthesis. The qanat erodes.

- **Synthesis reads agent outputs incrementally — verdict formed before all voices are heard** (1/3 agents: fd-tswana-kgotla-consensus-synthesis)
  TKC-1 — The synthesis barrier semantics are undocumented. If the orchestrator processes findings as agents complete (streaming), fast OpenRouter models will frame the synthesis before Claude Opus structural analysis arrives. High-confidence finding from the muqanni: the synthesis spec says "collect" but does not say "collect all before processing."

### P1 — Important Issues (5)

- **All agents run at uniform model tier — colotomic density structure absent** (1/3 agents: fd-javanese-gamelan-colotomic-interlocking)
  JGC-1 — The gong, saron, and gambang must play at their natural densities for the gamelan to function. An agent roster where all agents play at the same depth produces redundant coverage, not complementary coverage. Before routing to OpenRouter, define the three density layers.

- **Irama tier shift is partial — cross-family coordination missing under budget pressure** (1/3 agents: fd-javanese-gamelan-colotomic-interlocking)
  JGC-2 — Budget-pressure tier demotion operates within the Claude family. With OpenRouter added, demotion of Claude saron-layer agents without coordinated adjustment to DeepSeek gambang-layer agents breaks the colotomic structure. Density layers must shift as a coordinated unit.

- **Mother well has no physical weirs — one model family can drain the entire token budget** (1/3 agents: fd-persian-qanat-gradient-cascade)
  PQG-2 — The current per-type budget tracking has no partition between model families. Under cost pressure, greedy routing to OpenRouter (cheap) will drain the budget reserved for Claude structural analysis. Hard minimum reservations (weirs) required.

- **Synthesis dedup Rule 1 silences cross-model minority findings without inline attribution** (1/3 agents: fd-tswana-kgotla-consensus-synthesis)
  TKC-2 — Claude P1 vs. DeepSeek P3 on the same finding is recorded in `severity_conflict` in findings.json but appears in summary.md only in the buried "Conflicts" section. Cross-family disagreements are the highest-signal findings in multi-model reviews. They need inline attribution, not footnotes.

- **Reading order is fast-model-first — fast models frame synthesis before senior architectural judgment arrives** (1/3 agents: fd-tswana-kgotla-consensus-synthesis)
  TKC-3 — No reading order policy exists in synthesis.md. Completing agents (DeepSeek, Haiku) arrive first and establish the synthesis frame before Opus structural findings arrive. The kgotla principle requires the inverse: read structural (senior) findings first to establish the frame, then integrate coverage (junior) findings against that frame.

### P2 — Quality and Design Issues (5)

- **Balungan dispatched identically to all agents — no garap differentiation by density layer** (JGC-3)
- **Kotekan principle is named but not operationalized — cross-family divergence not treated as higher-signal than within-family convergence** (JGC-4)
- **Irreversible flow not acknowledged — OpenRouter token spend has different retry semantics than Claude Code agent dispatches** (PQG-4)
- **Multi-aquifer sourcing unspecified — DeepSeek R1, Qwen-Coder, Yi treated as interchangeable when they have distinct capability profiles** (PQG-5)
- **Verdict computation applies unanimity not consensus — single gambang-layer P0 produces "risky" without legitimacy bar** (TKC-4)

### P3 — Improvements (2)

- **No density-layer taxonomy in agent frontmatter** (JGC-5)
- **Reaction round creates asymmetric sycophancy pressure toward Claude Opus findings from cheaper models** (TKC-5)

---

## Issues to Address

- [ ] **P0** | Add gradient check before each non-Claude dispatch (PQG-1) — `skills/flux-drive/phases/launch.md`
- [ ] **P0** | Document and enforce synthesis barrier semantics: collect all outputs before processing any (TKC-1) — `docs/spec/core/synthesis.md`
- [ ] **P1** | Define 3-layer density taxonomy in `config/flux-drive/budget.yaml` (JGC-1)
- [ ] **P1** | Add family budget partitions with min_reserved weirs (PQG-2) — `config/flux-drive/budget.yaml`
- [ ] **P1** | Inline cross-family severity conflicts in summary.md (TKC-2) — `docs/spec/core/synthesis.md`
- [ ] **P1** | Add reading order policy to synthesis.md: expensive/structural models read first (TKC-3)
- [ ] **P1** | Add density_lock field to budget_pressure config to enforce coordinated irama shifts (JGC-2)

---

## Improvements Suggested

- Cross-family convergence metric distinct from within-family convergence (JGC-4 / TKC-2)
- Model-family capability profiles in OpenRouter routing config (PQG-5 — aquifer mapping)
- Garap overlay injection at dispatch time for density-layer-specific agent instructions (JGC-3)
- Consensus-weighted verdict for coverage-layer P0 findings (TKC-4)
- Agent frontmatter `density_layer: gong|saron|gambang` field (JGC-5)
- Reaction round stratified by density layer to prevent cross-layer sycophancy (TKC-5)

---

## Cross-Agent Convergence

| Finding | JGC | PQG | TKC | Convergence |
|---------|-----|-----|-----|-------------|
| Synthesis processes incrementally, not with full barrier | — | ✓ (shaft) | ✓ (P0) | 2/3 medium |
| No cross-family signal differentiation in synthesis | ✓ (kotekan) | — | ✓ (dissent) | 2/3 medium |
| Budget has no hard partitioning between model families | ✓ (irama lock) | ✓ (weirs) | — | 2/3 medium |
| Gradient calibration absent | — | ✓ (P0) | — | 1/3 single-agent |
| Density layers not defined | ✓ (P1) | ✓ (aquifer) | — | 2/3 medium |

**Key convergence insight:** All three agents independently identified that the synthesis phase lacks structural protection for the multi-model case. The gamelan agent raised the irama coordination problem; the qanat agent raised the intermediate shaft problem; the kgotla agent raised the barrier and reading-order problem. These are three different aspects of the same underlying issue: the synthesis phase was designed for a homogeneous single-family agent pool and has no structural adaptations for heterogeneous multi-family output.

---

## Section Heat Map

| Area | Issues | Agents Reporting |
|------|--------|-----------------|
| Synthesis phase | 4 (TKC-1, TKC-2, TKC-3, TKC-4) | tswana-kgotla |
| Budget/dispatch config | 3 (PQG-2, JGC-1, JGC-2) | qanat + gamelan |
| Agent dispatch routing | 2 (PQG-1, JGC-3) | qanat + gamelan |
| Cross-model signal handling | 2 (JGC-4, TKC-2) | gamelan + kgotla |
| Model capability profiling | 2 (PQG-5, JGC-5) | qanat + gamelan |

---

## Agent Reports

- [fd-javanese-gamelan-colotomic-interlocking](./fd-javanese-gamelan-colotomic-interlocking.md) — 5 findings (2 P1, 2 P2, 1 P3)
- [fd-persian-qanat-gradient-cascade](./fd-persian-qanat-gradient-cascade.md) — 5 findings (1 P0, 2 P1, 2 P2)
- [fd-tswana-kgotla-consensus-synthesis](./fd-tswana-kgotla-consensus-synthesis.md) — 5 findings (1 P0, 2 P1, 1 P2, 1 P3)

---

## Conflicts

*No severity conflicts between agents on the same finding — the three agents operate on orthogonal aspects of the problem (dispatch density, gradient calibration, synthesis governance) and do not double-cover the same concern.*

---

## Synthesis Note: The Structural Principle These Domains Reveal

The three esoteric domains converge on a single architectural principle that the input document did not name:

**Multi-family orchestration requires heterogeneous structural design at all three phases: dispatch, flow control, and synthesis.** 

The input document treats the OpenRouter question as a cost optimization question ("same or better insights at lower cost"). The frontier domains reveal it is primarily a *structural coherence* question:

- **Dispatch (gamelan):** Heterogeneous models require heterogeneous density layers, not just heterogeneous cost tiers. The colotomic principle: richness comes from layers playing different roles at different densities, not from layers playing the same role at different prices.

- **Flow control (qanat):** Token budgets need hard partitioning between model families (weirs), gradient calibration between task complexity and model capability, and intermediate quality checkpoints for non-Claude output (vertical shafts). Flow management is a first-class concern, not an afterthought.

- **Synthesis (kgotla):** Multi-family synthesis requires structural legitimacy mechanisms — barrier semantics (all voices before verdict), inline dissent attribution (minority findings get standing), graduated reading order (senior judgment establishes the frame), and a consensus rather than unanimity verdict model. The synthesis phase designed for a homogeneous agent pool will produce illegitimate verdicts when the voices come from different training lineages.

These three structural requirements are additive, not competing. The integration path: density taxonomy → budget weirs → gradient check → synthesis barrier → inline dissent attribution → reading order policy. Each step is a configuration addition or behavioral constraint, not an architectural rewrite.
