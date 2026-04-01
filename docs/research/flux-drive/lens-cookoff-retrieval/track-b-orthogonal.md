---
artifact_type: flux-drive-findings
track: orthogonal
target: "apps/Auraken/ — lens cookoff embedding retrieval pipeline"
date: 2026-03-31
agents: [fd-clinical-trial-methodology, fd-library-science-faceted-classification, fd-psychometric-item-response-theory, fd-competitive-programming-search-optimization]
---

# Lens Cookoff Retrieval Pipeline -- Track B (Orthogonal Domain Review)

Four agents from clinical trial design, library science classification, psychometric measurement, and competitive programming search reviewed the proposed embedding retrieval pipeline. Each brings structural analogies from domains that solve candidate-selection-under-constraint problems with different assumptions than information retrieval.

---

## Agent: fd-clinical-trial-methodology

### Finding CT-1: The Cookoff Is a Clinical Trial Without a Protocol -- No Pre-Registration

**Severity:** P1

**Source discipline:** Clinical trial methodology -- pre-registration of hypotheses, endpoints, and analysis plans.

The lens cookoff proposes to run 12 models on 1,360 dilemmas and analyze the results for "consensus and disagreement." In clinical trial methodology, this is an unregistered exploratory trial -- no primary endpoint is defined, no hypothesis is stated, and no analysis plan is pre-specified. Without pre-registration, the analysis will be shaped by the results (HARKing -- Hypothesizing After Results are Known), making any conclusions unreliable.

The design should state its hypotheses before running: (H1) frontier models converge on the same lens selections for >60% of dilemmas, (H2) embedding retrieval with K=10 achieves >90% recall of model-preferred lenses, (H3) model disagreement clusters around specific dilemma types rather than being uniformly distributed. Pre-specifying these prevents post-hoc cherry-picking of interesting patterns.

**Failure scenario:** The cookoff runs. Results show models agree on 45% of dilemmas. Is that high consensus or low? Without a pre-specified threshold, the analyst can frame 45% as "strong agreement" (nearly half!) or "poor agreement" (less than half). The same data supports opposite conclusions depending on framing. Every interesting pattern found in the data is a candidate for HARKing.

**Agent:** fd-clinical-trial-methodology

**Recommendation:** Write a one-page pre-registration document before running the cookoff: (1) primary hypothesis with success threshold, (2) secondary hypotheses, (3) analysis plan (how consensus will be computed -- Fleiss' kappa, percentage agreement, something else), (4) exclusion criteria (dilemmas where retrieval recall <80% are excluded from consensus analysis), (5) power analysis (is 1,360 dilemmas sufficient to detect meaningful differences between models with planned statistical tests?).

---

### Finding CT-2: No Blinding -- Retrieval Order Creates Anchoring Bias in Model Judgment

**Severity:** P2

**Source discipline:** Clinical trial methodology -- blinding and randomization to prevent assessment bias.

The design sends 10 candidate lenses to each model. The order of presentation will influence model selection due to primacy/recency bias in LLM responses. If candidates are presented in similarity-rank order (most similar first), models will exhibit position bias toward top-ranked candidates -- the model's judgment will partially reflect the embedding's judgment rather than being independent.

**Evidence:** Published research on LLM position bias (lost-in-the-middle, primacy bias in list selection tasks) shows that items presented first or last in a list are selected 15-40% more often than items in the middle, independent of quality. If the embedding model's top-1 lens is always presented first to all 12 models, consensus on that lens is partially an artifact of shared position bias, not genuine agreement about lens quality.

**Failure scenario:** Across 1,360 dilemmas, the embedding's top-1 lens is selected by 9/12 models. This is interpreted as strong consensus validating the embedding model's judgment. In reality, 3 of those 9 models selected it due to position bias (it was first in every prompt). The actual consensus is 6/12, which falls below the significance threshold. But this is never discovered because presentation order is not varied.

**Agent:** fd-clinical-trial-methodology

**Recommendation:** Randomize the order of the 10 candidate lenses in each prompt, independently for each model-dilemma pair. Use the same set of 10 candidates (from the embedding retrieval), but shuffle order. Log the presentation order for each call. In post-hoc analysis, check whether selection probability correlates with position. If it does, apply a position-debiasing correction before computing consensus.

---

## Agent: fd-library-science-faceted-classification

### Finding LS-1: Embedding Retrieval Is a Single-Axis Search -- Lenses Are Faceted Objects

**Severity:** P1

**Source discipline:** Library science -- faceted classification (Ranganathan's colon classification, modern faceted search).

Embedding search maps both dilemmas and lenses into a single vector space, computing a single similarity score. But lenses are faceted objects with at least four independent classification axes: (1) discipline (management science, psychology, design thinking), (2) scale (micro, meso, macro), (3) problem type (the conceptual space of the dilemma), and (4) interaction pattern (the type of cognitive operation -- reframing, decomposition, tension-mapping, temporal shifting). A single embedding collapses these facets into one score, making it impossible to retrieve "the lens from a different discipline that addresses the same problem type at the same scale."

**Evidence:** The lens schema includes `scale` (micro/meso/macro) and `discipline` as explicit fields. These are facets that should be independently searchable. Consider a dilemma about individual self-talk (micro scale, psychology domain). Embedding similarity will favor psychology lenses at the micro scale. But the most valuable lens might be one from organizational psychology (meso scale) applied by analogy to internal dialogue -- like "The Disappointing Super-Chicken" applied to competing internal voices. A faceted search could retrieve "different discipline, same problem pattern" candidates that embedding similarity would rank low.

**Failure scenario:** The embedding consistently retrieves lenses from the same discipline as the dilemma's surface vocabulary. Management dilemmas get management lenses. Psychology dilemmas get psychology lenses. The cross-disciplinary insights -- which are exactly what Auraken claims as its value proposition -- are systematically filtered out by the retrieval layer before any model can consider them.

**Agent:** fd-library-science-faceted-classification

**Recommendation:** Augment embedding retrieval with faceted diversity enforcement. After computing the top-15 by embedding similarity, ensure the final candidate set includes at least 2 lenses from disciplines different from the dominant discipline in the top-5. Use the explicit `discipline` and `scale` fields in the lens schema for this diversity constraint. This is the library science equivalent of "see also" cross-references -- surfacing related works from adjacent classification branches.

---

### Finding LS-2: The Lens Library Has No Subject Authority Control -- Synonym Collapse Will Hurt Retrieval

**Severity:** P2

**Source discipline:** Library science -- controlled vocabularies and authority files (LCSH, MeSH).

Library science solved the vocabulary mismatch problem decades ago with controlled subject headings: every concept has one canonical term, and all synonyms are mapped to it. The lens library has no such control. "Explore vs. Exploit" and a potential lens about "exploitation-exploration tradeoff" would be two separate entries despite being the same concept. More critically for retrieval, a dilemma using the word "exploitation" (in the sense of "taking advantage of known resources") might retrieve lenses about labor exploitation or ethical exploitation rather than the intended explore-exploit framework.

**Evidence:** Lens names use inconsistent vocabulary: "Situation-Behavior-Impact" (acronym-style), "The Disappointing Super-Chicken" (metaphorical), "Explore vs. Exploit" (conceptual opposition), "What Would It Take to Succeed?" (question-format), "Cultivating Our Inner Dialogue" (gerund-metaphor). No thesaurus maps between these naming conventions and the conceptual vocabulary dilemmas use.

**Agent:** fd-library-science-faceted-classification

**Recommendation:** For the cookoff specifically, add a `search_terms` field to each lens containing 5-10 canonical retrieval terms that bridge between dilemma vocabulary and lens concepts. For "The Disappointing Super-Chicken": ["team performance", "high performers", "group dynamics", "competition", "collaboration failure", "talent selection"]. Embed these search terms as an additional retrieval pathway alongside the context field. This is a lightweight authority control that improves recall without restructuring the library.

---

## Agent: fd-psychometric-item-response-theory

### Finding IRT-1: Not All Dilemmas Are Equally Diagnostic -- Use Dilemma Difficulty for Stratified Sampling

**Severity:** P2

**Source discipline:** Psychometric measurement -- Item Response Theory (IRT) and item difficulty calibration.

In IRT, test items (questions) have a difficulty parameter that determines how well they discriminate between examinees of different ability levels. Easy items (everyone gets right) and hard items (nobody gets right) are uninformative -- they produce no variance. The most informative items are those at moderate difficulty where examinees diverge. The 1,360 dilemmas vary in "lens selection difficulty" -- some will have one obviously correct lens (easy), some will be ambiguous (hard), and some will have a clear best lens but require domain knowledge to identify it (moderate, most informative).

**Evidence:** A dilemma explicitly about sunk cost decisions will be trivially matched to a sunk-cost lens by all 12 models. A dilemma about an abstract philosophical paradox may have no clearly matching lens. Neither case produces useful model comparison data. The dilemmas that distinguish model quality are those where 2-3 lenses are plausibly relevant and the "best" selection requires nuanced judgment.

**Failure scenario:** You run all 1,360 dilemmas and find that 800 produce unanimous model agreement (easy items) and 200 produce near-random disagreement (too hard). Only 360 dilemmas produce the discriminating variance you need. You spent 4x more tokens than necessary by not identifying the informative dilemmas first.

**Agent:** fd-psychometric-item-response-theory

**Recommendation:** Run a pilot with 2-3 models on all 1,360 dilemmas first. Classify dilemmas by "difficulty": (1) easy (all models agree), (2) moderate (partial agreement), (3) hard (no agreement). For the full 12-model cookoff, stratified-sample: run all "moderate" dilemmas (most informative), a random 20% sample of "easy" dilemmas (confirmation), and all "hard" dilemmas (to determine whether they are genuinely ambiguous or just poorly served by retrieval). This could reduce the full cookoff to ~500-700 dilemmas, saving 50%+ of token costs.

---

### Finding IRT-2: Model "Ability" and Lens "Difficulty" Should Be Co-Estimated

**Severity:** P2

**Source discipline:** Psychometric measurement -- two-parameter IRT model (item difficulty + discrimination).

The cookoff implicitly treats all 12 models as interchangeable raters and computes consensus. But models have different "abilities" -- Claude may excel at identifying psychological lenses while GPT-4o may be better at systems-thinking lenses. IRT's two-parameter model estimates both item (dilemma) difficulty and person (model) ability simultaneously, producing calibrated estimates of both. Simple percentage agreement ignores these interaction effects.

**Evidence:** If Claude selects psychology-domain lenses 40% more often than Gemini, and Gemini selects systems-thinking lenses 30% more often than Claude, then "consensus" is an average over fundamentally different selection strategies. The consensus lenses are not necessarily the best -- they are the ones where different strategies happen to overlap. The most insightful lenses may be those selected by only one model class.

**Agent:** fd-psychometric-item-response-theory

**Recommendation:** After the cookoff, fit a multi-dimensional IRT model: dilemma difficulty (how many lenses are plausibly relevant), model ability (overall selection quality), and model-domain interaction (which models excel in which lens domains). Use this to produce calibrated "gold standard" selections that weight model judgments by their demonstrated ability in each domain, rather than treating all model votes equally.

---

## Agent: fd-competitive-programming-search-optimization

### Finding CP-1: BM25 as a Free Recall Booster -- Do Not Abandon Lexical Retrieval

**Severity:** P1

**Source discipline:** Competitive programming -- hybrid search strategies that combine algorithmic approaches for maximum coverage.

In competitive programming, pure algorithmic approaches (greedy, DP, divide-and-conquer) each have blind spots. The winning strategy is often a hybrid: use one algorithm for the common case and a different one for the edge cases the first misses. Embedding retrieval has a known blind spot: lexical matches that carry strong semantic signal but are not captured by embedding similarity because the terms are rare in training data. BM25 (term-frequency-based retrieval) catches exactly these cases at near-zero computational cost.

**Evidence:** The lens library contains domain-specific terms like "Cynefin," "OODARC," "RPD," and "SBI" that may appear directly in dilemma descriptions or contextual notes. These are rare tokens that embedding models may not have learned strong representations for, but they are exact matches that BM25 would rank highly. Additionally, dilemmas that use a framework name explicitly ("this feels like a sunk cost situation") should retrieve the sunk-cost lens with certainty -- embedding similarity may rank it highly but not guarantee it.

**Failure scenario:** A dilemma explicitly mentions "principal-agent dynamics" in its text. The embedding model, having seen this term infrequently in training, gives it moderate similarity (0.62) to the principal-agent lens (ranked #7). BM25 would give it a near-perfect score. The embedding-only approach retrieves it but wastes top-K slots on higher-similarity but less relevant lenses. Worse, for rare framework names like "Cynefin" that the embedding model has never seen, the embedding similarity could be near-random, and the lens could be missed entirely.

**Agent:** fd-competitive-programming-search-optimization

**Recommendation:** Implement reciprocal rank fusion (RRF) of embedding retrieval and BM25 retrieval. For each dilemma, compute both embedding similarity rankings and BM25 rankings over the `context` field. Combine using RRF: `score(lens) = 1/(k + rank_embedding) + 1/(k + rank_bm25)` with k=60 (standard). Take top-K from the fused ranking. BM25 requires no API calls, no model, and runs in milliseconds -- it is free recall insurance. In competitive programming terms, this is the "belt and suspenders" strategy that catches edge cases the primary algorithm misses.

---

### Finding CP-2: Precompute the Full 291x1360 Similarity Matrix -- It Is Computationally Trivial

**Severity:** P2

**Source discipline:** Competitive programming -- precomputation and memoization to separate computation from decision-making.

The design treats retrieval as a per-dilemma operation: embed dilemma, compute top-K, send to model. But the entire retrieval problem is a 291x1360 matrix multiplication that can be precomputed in seconds. Precomputing the full matrix separates the retrieval decision (what K? what cutoff? what fusion strategy?) from the computation, allowing you to experiment with different strategies instantly.

**Evidence:** 291 lens embeddings (say 1024 dims each) = 298K floats. 1,360 dilemma embeddings = 1.39M floats. The full cosine similarity matrix is a single matrix multiply: (1360, 1024) @ (1024, 291) = (1360, 291), which takes <100ms on a laptop CPU. Once computed, you can try K=5, K=10, K=15, adaptive cutoff, or any combination without re-embedding anything.

**Agent:** fd-competitive-programming-search-optimization

**Recommendation:** Embed all 291 lenses and all 1,360 dilemmas once. Compute the full 1360x291 similarity matrix. Store it as a numpy array or parquet file. All subsequent retrieval experiments (varying K, varying cutoff strategies, varying field combinations) operate on this precomputed matrix. This also directly enables Finding IR-5 (logging full similarity vectors for library structure analysis).
