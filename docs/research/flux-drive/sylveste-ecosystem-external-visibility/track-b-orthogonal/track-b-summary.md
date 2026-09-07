# Track B — Orthogonal-Discipline Summary

> Four parallel-field lenses on Sylveste's external-visibility pathway. Date: 2026-04-16.
> Agents: scholarly-publishing, devtool-GTM, OSS-foundation, thinktank-policy.

## Cross-Agent Convergence

All four agents independently flagged three issues as P0/P1:

### Convergent P0/P1 #1 — The $2.93/landable-change stat is orphaned

- **Scholarly lens:** Not reproducible from a clean clone. No frozen dataset, no `reproduce-293.sh`, no method-of-measurement doc. Fails ACM/NeurIPS artifact-evaluation bar.
- **Devtool-GTM lens:** Not surfaced above the fold in README. Not part of the hero demo. Practitioner developers never encounter it.
- **OSS-foundation lens:** Not backed by a named external adopter. A solo-measured stat lacks the downstream validation CNCF incubation requires.
- **Thinktank-policy lens:** Not framed as a comparative stat. "$2.93" without "compared to what" cannot travel through principal conversations.

**Joint recommendation:** The stat needs all four fixes in parallel — frozen cohort + reproducible harness (scholarly), above-fold hero placement (devtool), external-adopter-validated replication (foundation), comparative reframing (policy). The stat is the single highest-leverage artifact in the project; right now it is doing none of the work four disciplines would demand.

### Convergent P0/P1 #2 — No top-level packaged artifact exists

Every lens observes the same absence with a different name:
- **Scholarly:** no `CITATION.cff`, no Zenodo-archived release, no landmark technical report.
- **Devtool-GTM:** no docs site, no hero demo, no public changelog.
- **OSS-foundation:** no `GOVERNANCE.md`, `MAINTAINERS.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`.
- **Thinktank-policy:** no 2-page executive brief, no press kit, no talk-circuit strategy.

The project has world-class internal substance (`PHILOSOPHY.md`, `docs/canon/`, Vision v5.0, 58 working plugins, 785-session baseline) but zero external packaging of any kind. This is not a content problem — it is a packaging-and-placement problem. Every missing artifact is 1-5 days of work to produce.

### Convergent P0/P1 #3 — Brand trinity (Sylveste / Garden Salon / Meadowsyn) fragments every narrative

- **Scholarly:** fragments citation graph across three strings.
- **Devtool-GTM:** three brands is a 10-second explainer problem for cold practitioners.
- **OSS-foundation:** multiple brands complicate foundation-governance scope boundaries.
- **Thinktank-policy:** Meadowsyn's Rosling/Gapminder potential is squandered by scoping it as a standalone app instead of as the canonical chart.

**Joint recommendation:** Collapse to "Sylveste" as the single umbrella for at least the next 12 months. Garden Salon and Meadowsyn become scoped sub-brands ("Sylveste Workspace", "Sylveste Dashboard/Meadowsyn visualizations") or stay as experimental / coming-soon surfaces. Three concurrent brands is premature at pre-1.0 with zero external adopters.

## Divergent Findings (where lenses disagree or flag unique issues)

- **Scholarly** uniquely flags the 6-pillar adoption cliff — labs need a single reference implementation. The devtool lens agrees at a different grain (needs a single hero demo). Foundation and policy lenses are pillar-agnostic.
- **Devtool-GTM** uniquely flags the 15-minute-aha precondition chain (Claude Code dependency, project-onboard gating). Scholarly and policy lenses care about artifact-readiness, not time-to-first-value.
- **OSS-foundation** uniquely flags the contributor-ladder and SIG-structure absence. The other lenses treat this as implicit "solo project" signal.
- **Thinktank-policy** uniquely elevates Meadowsyn's role — as the chart that travels, not just a product surface. The other three lenses either ignore Meadowsyn or treat it as pre-M1 optional.

## Layer-for-Stage-2 Consensus

The four agents recommend different Stage-2 layers — but the distribution is illuminating:

| Agent | Recommended Layer | Why |
|-------|-------------------|-----|
| Scholarly | Observability (Interspect + FluxBench + interstat) | Closest to artifact-evaluation readiness; owns the quotable stat |
| Devtool-GTM | Orchestration / L2 (Clavain + companion plugins) | Demo-ready narrative shape, 15-minute-aha primitive in `/clavain:project-onboard` |
| OSS-foundation | Plugin-substrate (Interverse spec + 58-plugin conformance) | Governance-extractable without kernel refactor; candidate lock-in artifact |
| Thinktank-policy | Evidence layer (Interspect + FluxBench + measurement chain) | Produces the principal-readable stats; anchors the landmark report |

**Track B consensus:** **The OBSERVABILITY / EVIDENCE layer** — specifically `Interspect + FluxBench + interstat` + the `cost-query.sh` pipeline.

Two of four agents (scholarly, policy) recommend it directly. The devtool agent's choice (Clavain) depends on the evidence layer to measure aha-moment conversion. The foundation agent's choice (plugin substrate) is orthogonal — it is the governance scope, not the visibility scope.

The evidence layer wins because:
1. **It is the only operational (M2) cross-cutting system** per the Capability Mesh — stage 2 must work with what already works, not extract from what is still being built.
2. **It owns every externally useful number** — `$2.93/landable-change`, gate pass rates, routing-calibration trajectory, model cost ratios. No other layer produces outputs that matter to labs, researchers, or policymakers.
3. **It has the clearest single-thesis framing** — "closed-loop calibration compounds evidence into earned trust" — which is the Sylveste thesis in publishable form.
4. **FluxBench (3,515 LOC Go, ~80% implemented) is 2-4 weeks from being a public runnable benchmark harness** — the highest-leverage single polish target in the project.
5. **The Rosling/Gapminder visualizations (Meadowsyn Tier 1) all draw from the evidence layer** — fixing Stage 2 here enables the chart-that-travels.

The OSS-foundation lens's plugin-substrate focus is important but sequentially secondary: governance is how the project scales to contributor #2 through #10, but external visibility has to produce a citable artifact first. Without F1 from each lens shipped, even a perfectly-governed project will fail to reach labs, researchers, or practitioners.

## Track B Recommended Sequencing (6-week view)

Rather than 4 parallel tracks competing for the same cycles:

**Week 1** — Foundation package (1-2 days) ships the governance-artifact bundle (`GOVERNANCE.md`, `MAINTAINERS.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `CITATION.cff`). This unblocks every other lens's work by removing disqualifiers.

**Week 2-3** — Scholarly package: freeze the baseline cohort, ship `scripts/reproduce-landable-change-cost.sh`, extract `benchmarks/closed-loop-routing-bench/` from FluxBench. Produces the reproducible citable artifact.

**Week 2-4 (parallel)** — Devtool package: stand up `sylveste.dev`, record Clavain hero demo GIF, bootstrap `CHANGELOG.md` + monthly release cadence. Opens the practitioner-developer funnel.

**Week 4-6** — Thinktank package: produce 2-page executive brief + 5-page "evidence earns authority" policy brief + landmark-report v1 draft. Pitch 3 talk-circuit targets (Latent Space, Changelog, NeurIPS workshop). Re-scope Meadowsyn Tier 1 as canonical-chart surface.

**Ongoing** — OSS-foundation ladder: publish 3-rung contributor ladder + `docs/sigs/sig-plugins.md` as first SIG charter. Promote `docs/canon/plugin-standard.md` to `docs/specs/interverse-plugin-spec-v1.md` with conformance tests. This is the 12-month path to CNCF Sandbox.

## The Ruthless-Prioritization Cut

If only ONE thing ships from Track B in the next 14 days: **`CITATION.cff` + frozen v0.7.0 tag + `scripts/reproduce-landable-change-cost.sh`**. This trio unblocks every other downstream lens: scholarly citation becomes possible, devtool-GTM gains a concrete claim to lead with, foundation reviewers clear the first procurement gate, and policy briefs gain a reproducible stat to anchor on. All other Track B findings amplify value only after this foundation exists.
