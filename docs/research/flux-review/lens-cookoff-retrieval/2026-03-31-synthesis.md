---
artifact_type: review-synthesis
method: flux-review
target: "apps/Auraken/ — lens cookoff embedding retrieval pipeline"
target_description: "Design review of embedding-based lens retrieval pipeline for 12-model cookoff on 1,360 ethical dilemmas with 291 lenses"
tracks: 3
quality: balanced
track_a_agents: [fd-information-retrieval-architecture, fd-embedding-model-evaluation, fd-recommender-system-recall-optimization, fd-vector-search-production-systems, fd-evaluation-benchmark-methodology]
track_b_agents: [fd-clinical-trial-methodology, fd-library-science-faceted-classification, fd-psychometric-item-response-theory, fd-competitive-programming-search-optimization]
track_c_agents: [fd-sommelier-wine-pairing-selection, fd-traditional-chinese-medicine-pattern-diagnosis, fd-museum-curation-exhibition-design]
date: 2026-03-31
---

# Lens Cookoff Retrieval Pipeline -- Flux Review Synthesis

## Critical Findings (P0/P1)

### P0-1: No validation set -- cannot measure retrieval quality before spending cookoff tokens

**Tracks:** A
**Agent:** fd-evaluation-benchmark-methodology (Finding IR-2)

The entire cookoff depends on the retrieval layer surfacing the right lenses, but there is no mechanism to verify this before running the experiment. Without 50-100 manually-annotated dilemma-to-lens "gold" mappings, you cannot measure recall@K for any embedding model, field combination, or cutoff strategy. Running a $500+ experiment on an unvalidated retrieval layer risks producing results that measure model preferences within a biased candidate set, not actual model quality.

**Fix:** Create a validation set of 50-100 dilemmas with 3-5 gold lens annotations each (2-4 hours of human annotation). Use this to empirically compare embedding models, field combinations, and K values before the cookoff. This is the single highest-leverage pre-work.

---

### P1-1: Embedding the wrong unit -- lens fields are not semantically homogeneous

**Tracks:** A
**Agent:** fd-information-retrieval-architecture (Finding IR-1)

Concatenating name + context + forces into a single embedding averages three different semantic types (label, situational description, tension pairs). The `context` field carries the strongest retrieval signal but is diluted by the metaphorical name and the distinctive "X vs. Y" grammar of forces.

**Fix:** Embed the `context` field alone as the primary retrieval vector. Use `forces` as a secondary re-ranking signal (embed separately, compute weighted combination). Test context-only vs. concatenated on the validation set before committing.

---

### P1-2: Missed retrieval has a standard solution -- hybrid retrieval with BM25

**Tracks:** A, B
**Agents:** fd-recommender-system-recall-optimization (Finding IR-6), fd-competitive-programming-search-optimization (Finding CP-1)

Two independent tracks converge on the same recommendation: embedding-only retrieval has a known blind spot for lexical matches with strong semantic signal (domain-specific terms like "Cynefin," "OODARC," "RPD," explicit framework names in dilemmas). BM25 catches these at near-zero computational cost.

**Fix:** Implement reciprocal rank fusion (RRF) of embedding retrieval and BM25 over the `context` field. `score(lens) = 1/(60 + rank_embedding) + 1/(60 + rank_bm25)`. BM25 requires no API calls and runs in milliseconds -- it is free recall insurance.

---

### P1-3: Embedding retrieval is single-axis -- lenses are faceted objects requiring diversity constraints

**Tracks:** B, C
**Agents:** fd-library-science-faceted-classification (Finding LS-1), fd-museum-curation-exhibition-design (Finding MC-1), fd-sommelier-wine-pairing-selection (Finding SW-1)

Three independent agents from three tracks identify the same structural problem: embedding retrieval finds same-category matches and systematically excludes cross-disciplinary insights. The library science agent frames this as missing faceted search; the museum agent frames it as the candidate set being a gallery wall that primes model interpretation; the sommelier agent frames it as varietal matching that misses the contextual read. All three recommend diversity constraints.

**Fix:** After computing the top-15 by embedding similarity, enforce discipline diversity: no more than 50% of candidates from any single discipline. Replace excess same-discipline lenses with the highest-ranked lenses from other disciplines at positions 11-20. This ensures the candidate set invites cross-disciplinary thinking.

---

### P1-4: No pre-registration -- the cookoff is an experiment without a protocol

**Tracks:** B, C
**Agents:** fd-clinical-trial-methodology (Finding CT-1), fd-museum-curation-exhibition-design (Finding MC-2)

The clinical trial agent identifies the lack of pre-registered hypotheses and analysis plan (HARKing risk). The museum agent identifies the lack of a "curatorial thesis" -- the cookoff tries to answer at least four different questions simultaneously. Without declaring which question is primary, the analysis will be shaped by whatever patterns look interesting in the results.

**Fix:** Write a one-page pre-registration: (1) primary hypothesis with success threshold, (2) analysis plan (statistical method for computing consensus -- Fleiss' kappa or similar), (3) exclusion criteria. Declare whether the primary thesis is retrieval sufficiency, model convergence, model bias characterization, or library coverage.

---

### P1-5: Presentation order creates anchoring bias -- randomize candidate order per call

**Tracks:** B
**Agent:** fd-clinical-trial-methodology (Finding CT-2)

LLM position bias (primacy/recency) means items presented first or last in a list are selected 15-40% more often than items in the middle. If the embedding model's top-1 lens is always presented first, consensus on that lens is partially a position bias artifact.

**Fix:** Randomize the order of the 10 candidate lenses independently for each model-dilemma pair. Log presentation order. In post-hoc analysis, check for position-selection correlation.

---

### P1-6: Pattern diagnosis requires gestalt, not symptom-matching -- add a tension extraction step

**Tracks:** C
**Agents:** fd-traditional-chinese-medicine-pattern-diagnosis (Finding TCM-1), fd-sommelier-wine-pairing-selection (Finding SW-1)

Two distant-domain agents converge: embedding retrieval matches surface features (symptoms, varietal), but the right lens often depends on the interaction between elements (the gestalt, the contextual read). A dilemma about a hiring decision where the candidate is the leader's former mentor needs a lens about authority inversion, not a lens about hiring best practices. The interaction creates the meaning.

**Fix:** Add a gestalt/tension extraction step before retrieval. For each dilemma, use a fast model to extract the underlying tension in abstract terms (one LLM call, cacheable). Embed this abstract tension and retrieve additional candidates from `forces` fields. This "two-hop" retrieval (dilemma -> abstract tension -> lens forces) targets exactly the signal embedding similarity misses.

---

## Cross-Track Convergence Analysis

### Convergence 1: Discipline Diversity Constraint (3 tracks, 3 agents)

The strongest cross-track signal. Library science (faceted classification), museum curation (gallery wall composition), and sommelier selection (contextual read vs. varietal match) all independently identify that single-axis embedding retrieval produces same-category echo chambers. All three recommend enforcing cross-disciplinary representation in the candidate set. The convergence from three completely unrelated domains validates this as a structural property of the problem, not a domain-specific concern.

**Unified fix:** Enforce a discipline-diversity constraint: no more than 50% of candidates from any single `discipline` value. Additionally, reserve 2-3 "sommelier slots" for candidates retrieved via abstract tension matching (see P1-6) rather than direct embedding similarity.

### Convergence 2: Two-Stage Retrieval with Reasoning (2 tracks, 3 agents)

The sommelier's "contextual read," TCM's "pattern diagnosis," and the IR agent's "query expansion" all describe the same mechanism: a lightweight reasoning step between the raw input and the retrieval query that extracts non-obvious features. All three recommend a fast LLM call to reframe the dilemma before embedding it.

**Unified fix:** Add a preprocessing step: for each dilemma, call a fast model with "What is the underlying tension in this dilemma? Name it in abstract terms (e.g., 'authority vs. expertise,' 'short-term relief vs. long-term capability')." Embed this output and use it as an additional retrieval query, taking the union of standard and tension-based top-K results.

### Convergence 3: Experimental Rigor (2 tracks, 2 agents)

Clinical trial methodology and evaluation benchmark methodology both flag the same gap: the cookoff is an expensive experiment designed without experimental discipline. Pre-registration, null hypothesis baselines, and stratified sampling are standard in both fields.

**Unified fix:** Write a pre-registration document. Compute the null-hypothesis agreement baseline. Pilot with 2-3 models to classify dilemma difficulty and stratify-sample the full cookoff.

---

## Recommended Architecture

Based on the synthesis of 21 findings across 12 agents and 3 tracks, the recommended retrieval pipeline is:

### Phase 0: Validation (before cookoff)
1. Manually annotate 50-100 dilemmas with 3-5 gold lens selections each
2. Write a one-page pre-registration with primary hypothesis and analysis plan

### Phase 1: Embedding + Preprocessing (one-time)
3. Embed all 291 lens `context` fields with 3 embedding models (OpenAI, nomic, voyage)
4. Embed all 291 lens `forces` fields separately
5. Build BM25 index over lens `context` fields
6. For each of 1,360 dilemmas: extract abstract tension via fast LLM call (cacheable)
7. Embed all dilemmas and their tension extractions
8. Compute the full 1360x291 similarity matrix (all combinations) and store
9. Compare embedding models on recall@K using the validation set; select best model

### Phase 2: Retrieval (per-dilemma)
10. For each dilemma, retrieve via reciprocal rank fusion:
    - Embedding similarity (context query -> context vectors)
    - BM25 (dilemma text -> context index)
    - Tension embedding (abstract tension -> forces vectors)
11. Apply adaptive score-gap cutoff (floor=5, ceiling=15) on the fused ranking
12. Enforce discipline diversity: max 50% from any single discipline
13. Randomize presentation order for each model-dilemma pair

### Phase 3: Model Judgment
14. Send compressed lens metadata (name + context + forces only, ~90 tokens/lens)
15. Require 1-2 sentence rationale per selection
16. Log full provenance: retrieval rank, score, presentation position, model selection, rationale

### Phase 4: Analysis
17. Compute consensus with null-hypothesis baseline (permutation test)
18. Classify dilemmas by difficulty (IRT-informed) -- report results stratified by difficulty
19. Track retrieval provenance: which consensus lenses were highly-ranked vs. barely-in-top-K
20. Analyze lens retrieval frequency distribution, co-retrieval matrix, and coverage gaps

### Cost Estimate
- Validation set annotation: 2-4 hours human time
- Embedding costs: ~$1 (291 lenses + 1,360 dilemmas + tensions, all models)
- Tension extraction: ~$5 (1,360 short LLM calls)
- Cookoff model calls: ~$400-600 (1,360 dilemmas x 12 models, compressed prompts)
- Total overhead for retrieval rigor: ~$6 + 3 hours annotation
- Token savings from compressed metadata (name+context+forces vs. full): ~30M tokens

---

## Secondary Findings Worth Tracking

| ID | Finding | Track | Severity | Key Insight |
|----|---------|-------|----------|-------------|
| IR-3 | Adaptive score-gap cutoff | A | P2 | Fixed K=10 overfits easy dilemmas, underfits hard ones |
| IR-4 | Embedding model as experiment variable | A | P2 | Compare 3 models on validation set, ~$0.50 cost |
| IR-5 | Log full similarity vectors | A | P2 | Free library structure analysis |
| IR-7 | Compress prompt metadata | A | P2 | 3x token savings by omitting solution/questions/examples |
| IR-8 | Consensus needs null baseline | A | P2 | Random selection produces non-trivial overlap |
| LS-2 | Synonym collapse in lens names | B | P2 | Add `search_terms` field for retrieval |
| IRT-1 | Stratified sampling by dilemma difficulty | B | P2 | Pilot with 2-3 models, save 50%+ tokens on full run |
| IRT-2 | Model-domain ability interaction | B | P2 | Weight model votes by domain expertise, not equally |
| CP-2 | Precompute full similarity matrix | B | P2 | 100ms computation enables unlimited strategy experiments |
| SW-2 | Capture selection rationales | C | P2 | 50 extra tokens per selection, dramatically richer data |
| TCM-2 | Personalization signal in disagreement | C | P2 | Model disagreement may be personalization signal, not noise |
| MC-3 | Provenance tracking per consensus lens | C | P2 | Distinguish retrieval-driven vs. model-driven consensus |

---

## Open Questions Raised by the Review

1. **Is the cookoff testing retrieval or model judgment?** The pre-registration must declare this. If retrieval, the validation set and recall measurement are the primary outputs. If model judgment, the retrieval layer must be validated first to ensure it is not confounding the results.

2. **Should the cookoff discover "universally best" lenses or "conditionally best" lenses?** TCM-2 identifies that model disagreement may reflect genuine user-dependent variation, not noise. The analysis plan should distinguish these cases.

3. **What does the lens library structure look like in embedding space?** The full similarity matrix (CP-2) plus lens retrieval frequency distribution (IR-5) will reveal dead lenses (never retrieved), generic lenses (always retrieved), and redundant lenses (always co-retrieved). This is a free byproduct of the cookoff infrastructure that directly informs library curation.

4. **Is the forces field a better retrieval axis than the context field?** Forces encode abstract tensions ("individual excellence vs. collective performance") that may match dilemmas at a deeper level than context descriptions. The validation set can test forces-only vs. context-only vs. fusion.
