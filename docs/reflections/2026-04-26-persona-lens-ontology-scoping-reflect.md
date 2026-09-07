---
artifact_type: reflection
bead: sylveste-b1ha
stage: reflect
sprint_type: scoping
deliverable: scoped-epic
artifacts:
  brainstorm: docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md
  prd: docs/prds/2026-04-21-persona-lens-ontology.md
  plan: docs/plans/2026-04-21-persona-lens-ontology-epic-execution.md
  prior_art: docs/research/assess-ontology-stores-2026-04-21.md
  brainstorm_review: docs/research/flux-review/persona-lens-ontology-brainstorm/2026-04-21-synthesis.md
  prd_review: docs/research/flux-drive/2026-04-21-persona-lens-ontology-prd/2026-04-21-synthesis.md
children: [sylveste-j5vi, sylveste-r3jf, sylveste-dsbl, sylveste-t2cs, sylveste-71nz, sylveste-2n8i, sylveste-g939, sylveste-1j30]
---

# Reflection — Persona/Lens Ontology Scoping Sprint

A scoping sprint that produced a scoped epic, not running code. Eight feature beads filed (F1-F7 with F6 split into F6a/F6b), eleven gates committed, three review rounds, two PRD revisions. Worth pausing on what worked and what didn't.

## What worked

### Distant-track agents earned their cost on one finding

The 2-track flux-review used Track A (5 adjacent domain-experts) + Track C (5 distant-domain agents from perfumery, Qing cataloging, Islamic hadith authentication, Inka quipu, Noh theatre). The honest accounting: Track C delivered ~3 of 31 findings with qualitatively different insight, ~15 that reframed adjacent findings usefully but non-additively, and ~13 that were either redundant or weaker expressions of adjacent findings.

But one of those three — **tier laundering via `same-as` when source-independence isn't distinguished from content similarity** — was genuinely load-bearing. Three Track C agents (isnad, perfumery, sibu) independently arrived at the same structural defect from Persian, French, and Qing traditions; Track A's dedup-calibration agent supplied the mechanical precursor. The convergence pattern (4 agents from completely different framings hitting the same structural gap) was unmistakable signal. No single track would have produced it: adjacent-only stayed at threshold-calibration vibes, any single distant-only would have been dismissible as vocabulary transfer.

The lesson is not "always run distant tracks" — they're cost-noisy. The lesson is **distant tracks pay off on schema/ontology work specifically**, where structural isomorphisms from pre-modern knowledge systems map directly to typed-relationship design. For a code-review on a migration, distant tracks would mostly waste tokens.

### "Aspirational language → committed gates" was the discipline that mattered

The original brainstorm used phrases like "idempotent", "embedding-based", "measurable lift", "bi-temporal" without specifying the implementation commitments those words imply. The flux-review surfaced 9 P0s, every one of them a gap between aspiration and commitment.

Converting each P0 into a numbered gate (G1-G11) before the strategy step produced two compounding effects:
1. The PRD wrote itself — each gate maps 1:1 to a feature acceptance criterion, no ambiguity about scope
2. The PRD review focused on translation fidelity rather than re-debating decisions that the brainstorm review already settled

Without the gate-naming discipline, the strategy step would have re-litigated the same P0s under different framing, and the plan would have inherited unresolved aspirations. **The act of writing "G3" or "G7" on a decision is what makes it durable across the brainstorm → PRD → plan handoff** — names anchor commitments that prose lets drift.

### F6 split was a PRD-review-only discovery

The original F6 ("flux-drive triage MVP") was a 2.5-week feature combining pre-registration, corpus building, backend swap, A/B execution, and ship decision. The brainstorm + brainstorm review missed this. The PRD review caught it via fd-triage-lift-measurement: pre-registration discipline mechanically requires the pre-reg doc to be committed *before* any backend code, and a single 2.5-week bead with all that work makes that ordering optional rather than enforced.

Splitting F6 → F6a (pre-reg + corpus, 1w) + F6b (backend + A/B + decision, 1.5w) made the ordering structural: F6b depends on F6a in the bead graph; F6b cannot start with F6a unsigned-off. **The split also unlocked F7 parallelization** — F7 (interlens MCP adapter) only depends on F2+F5, not F6. The "F7 depends on F6" edge in the original DAG was incidental, not necessary.

This is the kind of finding that single-author plans miss because the author lives in their own framing. PRD review by a fresh agent caught it immediately. Worth the ~100k tokens.

## What didn't work as well

### Six review rounds for a scoping sprint was over-budget

Token tally for this sprint, approximately:
- Prior-art assessment agent (~30k)
- 2 design-track agents for flux-review fan-out (~80k combined)
- 2 review-track flux-drive runs (~190k combined)
- 1 synthesis agent (~90k)
- 1 PRD flux-drive review (~100k)
- 1 PRD re-review (~40k)
- 1 plan smoke-check (~40k)

Total review cost for a sprint that wrote 0 lines of code: ~570k tokens. Justifiable as scoping investment for a 2-4 month epic, but **the tier-aware sprint config treated this scoping sprint identically to an implementation sprint**. The discipline says "Tier 2 auto-approves brainstorm/strategy reviews if no P0/P1, else pause" — but for a scoping sprint, a single combined review covering brainstorm + PRD would have caught most of what the staged reviews caught at half the cost.

**Calibration note:** the sprint orchestrator should distinguish *scoping sprints* (deliverable = epic structure) from *implementation sprints* (deliverable = working code) and apply lighter review regimens to scoping. Default scoping-sprint review = 1 combined pass with 2-3 agents at strategy step, no separate brainstorm review unless explicitly requested.

### "Stop and plan an epic" decision was made well, but late

When the brainstorm phase asked "single sprint vs. epic", the right answer (epic) was clear from the moment we counted 660 + 291 + 288 = 1239 entries across three stores with disparate schemas. The brainstorm dialogue spent 4 questions narrowing scope before reaching the epic-vs-sprint question; in retrospect, that question should have been first or second, not fifth.

**Process note:** for any topic that mentions "unify multiple existing systems" with > 3 stores or > 1000 entries, the first brainstorm question should be "this looks like an epic, not a sprint — confirm or redirect?" Saves ~3 questions of narrowing on a scope that's predetermined.

### Steps 5-8 of the sprint orchestrator were no-ops we still ceremonially marked

The sprint orchestrator's 10-step flow assumes implementation. For scoping sprints, Steps 5 (Execute), 6 (Test), 7 (Quality Gates), 8 (Resolve) all degenerate into "nothing to do — proceed". The orchestrator should have a `--scoping` mode that:
- Runs Steps 1-4 (brainstorm → strategy → plan → review)
- Skips 5-8 with a single line each
- Runs Step 9 Reflect + Step 10 Ship as normal

Currently we did that informally via user choice; making it formal would prevent the "should we run Step 7?" friction that arose at the close.

## Useful framings for future ontology / unification work

1. **Three-stores-of-the-same-thing is a tell.** When you find three (or more) existing stores that latently encode the same entity types — like fd-agents, Auraken lenses, interlens — assume a unified ontology is latent in the data and give it a name before designing storage. The data already knows what it is; the schema discipline is just naming.
2. **Bridge-score and community_id are graph reasoning waiting for a graph.** Auraken had these fields without a graph DB underneath. interlens shipped `find_bridge_lenses` and `get_dialectic_triads` MCP tools without a graph DB. When you find graph-shaped operations executing on adjacency-list-or-application-layer-walks, that's the signal that the system has outgrown its storage.
3. **Same-as is dangerous unless source-independence is a first-class field.** Embedding similarity ≠ semantic equivalence. Two pre-modern non-Western metrology lenses may embed at 0.82 because they share genre, not because they're saying the same thing. The cheap fix (cosine threshold) silently corrupts tier signals downstream. The right fix borrows from Islamic hadith authentication: corroboration by independent transmitters is what distinguishes "true" from "vibes-similar".
4. **Iemoto-pattern selection authority.** When three view consumers will execute "find the right N for this task", they will drift into three implementations within 18 months unless one is designated canonical and the others are forced to be adapters. Naming the canonical reference (here: flux-drive triage view as iemoto, `ontology-queries` as the school-of-transmission module) is the structural intervention; documentation alone won't hold the line.

## Followups (file as beads in next-work pass)

- **Sprint orchestrator: add `--scoping` mode.** Skip Steps 5-8 when sprint deliverable is an epic structure rather than working code. (Estimated: small, P3.)
- **Brainstorm skill: epic-vs-sprint question first** for inputs mentioning "unify N stores" with N >= 3 or > 1000 entries. (P3 polish.)
- **Calibration: track scoping-sprint vs. implementation-sprint review costs separately** so the cost-per-finding rollups don't conflate them. (P3.)
- **The ontology epic itself** continues via `/route` on F1 (sylveste-j5vi) and F2 (sylveste-r3jf), which are both unblocked P1s ready for their own sprints.
