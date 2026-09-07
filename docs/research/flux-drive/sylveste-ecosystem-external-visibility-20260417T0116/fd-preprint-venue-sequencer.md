---
agent: fd-preprint-venue-sequencer
tier: generated
category: project
model: sonnet
lens: ML publication strategist — venue sequencing and credential accrual
---

# Review — Preprint Venue Sequencer

## Findings Index

- P0-PREPRINT-1: No preprint exists; any HN submission first would be an unreceipted burn
- P1-PREPRINT-1: All 12 distinctive claims carry equal weight in PHILOSOPHY.md without receipts
- P1-PREPRINT-2: Cost-calibration pipeline ($2.93/change) has the table and the method but no methods-paper packaging
- P2-PREPRINT-1: Zollman-sparse-topology and "disagreement is highest-value signal" claims are prose-only and workshop-ready IF measured
- P2-PREPRINT-2: No canonical citable identifier (DOI / arXiv / Zenodo) for any primitive
- P3-PREPRINT-1: FluxBench / Factory Substrate measurement story is ambitious but M0 — premature for any venue

## Verdict

**One preprint, one claim, one table — before any HN post.** The cost-calibration pipeline is the only claim with a defensible receipt. Package it as a 6-page methods preprint, get a Zenodo DOI, and pin that URL as the anchor of every subsequent public move. Cut the other 11 distinctive claims from PHILOSOPHY.md until each has a companion receipt.

## Summary

The target brief lists 12 distinctive claims. Eleven of them are intellectually interesting but currently empirically unfalsifiable as stated — they are manifesto bullets, not methods papers. The technically-serious reader (ML researcher, framework maintainer, senior practitioner) uses preprints as the unit of credential accrual: a short, reproducible, citable methods document earns more citation-weight than twenty blog posts. A project that front-pages HN without a citable anchor is legible as vaporware — and the HN burn is one-shot.

The cost-calibration pipeline is the one exception. It has: a concrete pipeline (`estimate-costs.sh`), a real database (interstat), a measured baseline ($2.93/landable change, 785 sessions, March 2026), and a replicable methodology (defaults → actuals → calibration → defaults-as-fallback). This is workshop-submittable today. Everything else needs the harness before it needs the preprint.

## Issues Found

### P0-PREPRINT-1: HN-without-preprint is a one-shot credential burn

- **File:** target-brief § "Current Public Surface" lines 116-124 (no preprint exists)
- **Failure scenario:** The user has one HN submission slot per target brief constraints (line 152). If it fires before a citable preprint URL exists, commenters have nothing to point to except the monorepo. Serious readers follow the discussion expecting a receipt, find prose-only claims, and file Sylveste as "interesting manifesto, no rigor." When a preprint later appears, it cannot re-earn the attention — the first impression is locked. This is a 3am-wake-up scenario: the HN post must be sequenced AFTER the preprint URL exists, not before.
- **Smallest viable fix:** Freeze HN submission. Draft the methods preprint this week. Publish to arXiv (cs.SE or cs.AI) or Zenodo for a DOI. Only then draft the HN post with "[preprint]" in the title.

### P1-PREPRINT-1: 12 claims at equal weight reads as manifesto

- **File:** `PHILOSOPHY.md` — target-brief lines 75-88 enumerates all 12
- **Failure scenario:** A reviewer peer-evaluating Sylveste on behalf of a serious community sees claims like "Wired or it doesn't exist" (a strong, falsifiable quality bar) adjacent to "Infrastructure unlocks autonomy, not model intelligence" (a broad thesis with no experimental support) adjacent to "Sparse topology in multi-agent collaboration (Zollman effect)" (an empirically-loaded claim with no harness). Equal presentation signals "we believe all of these with equal confidence" — which is the epistemic red flag the technically-serious audience is trained to detect. Over weeks, the project gets classified as ideology-first.
- **Smallest viable fix:** Tier PHILOSOPHY.md into three sections: **Evidenced** (claims with receipts — currently 1: cost-calibration), **Operationalized but unmeasured** (claims that have code but no measured result — 2-3 more: OODARC Compound, Wired-or-it-doesn't-exist as a gate), **Design bets** (everything else). Cut claims with neither operationalization nor evidence entirely until they earn one.

### P1-PREPRINT-2: Cost-calibration pipeline is workshop-ready but unpackaged

- **File:** `interverse/interstat/scripts/cost-query.sh`, `core/intercore/config/costs.yaml`, target-brief line 90 (4-stage Closed-Loop pattern)
- **Failure scenario:** The sharpest receipt Sylveste currently owns — an empirical cost baseline derived from a closed-loop calibration pipeline running on real agent sessions — is a shell script and a YAML file. No methods paper. No table in publishable form. No reproducibility package. If a senior practitioner asks "how did you measure $2.93," there is no artifact to send them. The opportunity is that the MLOps / AI-engineering workshop circuit (NeurIPS MLSys, ICML ES-FoMo, ICLR DL4C) has active interest in agent-cost measurement. Workshop acceptance carries more weight than a blog post by an order of magnitude.
- **Smallest viable fix:** Write a 6-8 page methods paper this month. Sections: (1) Problem — why hardcoded cost estimates drift, (2) 4-stage closed-loop method, (3) Implementation on Claude/Codex/GPT-5.2 agent sessions, (4) Table of baseline numbers over 785 sessions with per-phase breakdown, (5) Reproducibility — link to Zenodo release with the DB dump (anonymized), the scripts, and the config. Submit to the nearest AI-engineering workshop call. Post preprint to arXiv on submission day.

### P2-PREPRINT-1: Zollman / disagreement-as-signal claims need a harness

- **File:** `PHILOSOPHY.md` — target-brief lines 83-85 (claims 8 and 9)
- **Failure scenario:** These two claims are the most *interesting* to the ML research community — they map directly onto active research areas (social epistemology in multi-agent systems, debate/consensus methods). Stated as prose, they are dismissed. Measured with even a small experimental harness (Zollman's original model re-run with LLM agents, or a disagreement-detection ablation on an existing benchmark), they become workshop-submittable on their own merits. The degradation is slow: every month these claims stay unmeasured, the field moves past them.
- **Smallest viable fix:** Park as Q3 preprint candidates. Do not feature on the landing surface until the harness exists. Cut from the first PHILOSOPHY.md tier above.

### P2-PREPRINT-2: No canonical citable identifier for any primitive

- **File:** repo-wide absence — no DOI, no arXiv ID, no Zenodo release
- **Failure scenario:** When an adopter wants to credit "OODARC" or "the M0-M4 maturity ladder" in their own work, they have no citable handle. They cite the GitHub repo at a git SHA, which ages out. Reputation does not accrue. Every adopter reinvents the attribution.
- **Smallest viable fix:** Create a Zenodo release for the v0.6.229 snapshot today (Zenodo automates DOI minting from GitHub release events). Use the DOI in all subsequent cross-references. Repeat at v0.7, v1.0.

### P3-PREPRINT-1: FluxBench / Factory Substrate premature for venue submission

- **File:** target-brief line 62 ("planned")
- **Failure scenario:** None urgent. The risk is announcing the measurement framework before M2+ and having reviewers evaluate the promise instead of the delivery. Keep hidden from all external surfaces until there are publishable results.
- **Smallest viable fix:** Do not mention FluxBench in the forthcoming preprint, HN post, or blog cadence. Reveal at M2.

## Improvements

- After the first preprint lands, set up a Semantic Scholar author profile linking all Sylveste-related preprints into one identity — the credential-accrual compounds.
- Cold-email 3 specific researchers in agent-cost / AI-engineering space with the preprint PDF. One sentence: "We measured N=785, here's the table, would value your take on whether section 3.2 matches what you've seen." That is the venue after the venue.
- The `docs/canon/` directory (plugin-standard, doc-structure) is well-positioned to become a future preprint on agent-native plugin architecture, but only after the ecosystem has enough third-party plugins to be empirical rather than prescriptive.

## The Sequence

1. **This week**: Draft cost-calibration methods preprint. Identify target workshop (MLSys / ES-FoMo / DL4C — whichever deadline is next).
2. **Week 2**: Preprint on arXiv + Zenodo release with DOI. Pin DOI to README.
3. **Week 3**: Workshop submission + short blog post pointing to the preprint (blog is the social on-ramp, preprint is the receipt).
4. **Week 4-5**: Accept the workshop response; refine; tweet thread (only after preprint URL is live).
5. **Week 6**: HN submission with `[preprint]` in title, linking to the arXiv URL not the GitHub repo.

Cut from public surface until each has its own preprint: the Zollman claim, the disagreement-signal claim, the progressive-trust-ladder, the graduated-authority M-ladder (these need evidence-epoch data before the claim is falsifiable).

<!-- flux-drive:complete -->
