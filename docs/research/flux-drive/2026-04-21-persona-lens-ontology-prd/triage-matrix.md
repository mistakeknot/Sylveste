---
artifact_type: flux-drive-triage
target: docs/prds/2026-04-21-persona-lens-ontology.md
date: 2026-04-21
bead: sylveste-b1ha
---

# Flux-Drive Triage — Persona/Lens Ontology PRD

## Context

Review target is the **PRD** (strategy-step output), not the brainstorm. The brainstorm review already ran with 10 agents / 61 findings / 9 P0s (synthesis at `docs/research/flux-review/persona-lens-ontology-brainstorm/2026-04-21-synthesis.md`). This pass focuses on six translation-fidelity and decomposition questions the brainstorm review did not cover:

1. Brainstorm → PRD gate translation fidelity (did any gate get lost or soften?)
2. Feature dependency graph correctness (F1→F2→F3→F4→F5→F6→F7 as spec'd)
3. Feature sizing (7 features for ~10-11 weeks — any that must split or merge?)
4. Epic DoD rigor (can the epic fail with all 7 features closed?)
5. Non-goals discipline (is scope creep hiding?)
6. Open-questions deferability (do any silently gate write-plan?)

## Triage Verdict — Agents Relevant to This PRD Pass

All 10 project agents generated for the brainstorm pass remain relevant. The 11-gate pressure has already been applied to the brainstorm; what matters here is whether the PRD is a **faithful vessel** for those gates, whether its **decomposition is correct**, and whether the **DoD has teeth**. Each agent re-applies its decision lens to these new questions.

| Agent | Relevance | Focus areas it owns | Dispatch |
|---|---|---|---|
| fd-ontology-schema-discipline | HIGH | #1 (gate translation for G3/G4/G6/G7/G8/G9 → F3), #2 (F3→F4 dependency), #3 (F3 sizing at 1.5 weeks) | RUN |
| fd-age-cypher-query-economics | HIGH | #1 (G1 → F1 fidelity, p95 thresholds), #2 (F1→F3 block ordering), #3 (F1 at 1 week) | RUN |
| fd-semantic-dedup-calibration | HIGH | #1 (G3 → F5), #2 (F4→F5→F6 ordering), #3 (F5 at 1.5 weeks), #4 (DoD #4 graph-health) | RUN |
| fd-triage-lift-measurement | HIGH | #1 (G10 → F6 pre-registration), #4 (DoD #1 — is review-coverage-per-diff measurable as spec'd?), #6 (open Q on Hermes gating) | RUN |
| fd-multi-store-ingestion-safety | HIGH | #1 (G2/G9 → F4), #2 (F3→F4→F5), #3 (F4 at 2 weeks), #4 (DoD #2 idempotent re-run) | RUN |
| fd-perfumery-base-accord-composition | MEDIUM | #5 (fixative-triad non-goal discipline), #1 (G4 bridges → F3) | RUN |
| fd-sibu-classification-fit-check | MEDIUM | #1 (G11 → F2 audit), #4 (DoD "collapsed Domain+Discipline per F2 verdict" — does F3 unblock if F2 recommends collapse?), #5 (Concept residual non-goal) | RUN |
| fd-isnad-chain-integrity | HIGH | #1 (G3/G7/G9 → F3/F4/F5), #4 (DoD #4 "every Lens has ≥ 1 derives-from chain to a Source"), #5 (jarh wa-ta'dil Lens-level non-goal) | RUN |
| fd-quipu-cord-typing-discipline | MEDIUM | #1 (G4 bridges + wields edge-discrimination → F3), #3 (F3 sizing — edge discipline adds work) | RUN |
| fd-noh-kata-canonical-form-drift | HIGH | #1 (G5 → F2/F6/F7 triad), #2 (F6→F7 vs F6∥F7 ordering), #4 (DoD #3 single-query-authority measurement), #5 (Hermes/catalog adapter non-goal) | RUN |

**All 10 dispatched.** No agents excluded. The PRD touches every surface the brainstorm touched.
