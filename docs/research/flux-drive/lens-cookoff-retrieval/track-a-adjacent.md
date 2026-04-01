---
artifact_type: flux-drive-findings
track: adjacent
target: "apps/Auraken/ — lens cookoff embedding retrieval pipeline"
date: 2026-03-31
agents: [fd-information-retrieval-architecture, fd-embedding-model-evaluation, fd-recommender-system-recall-optimization, fd-vector-search-production-systems, fd-evaluation-benchmark-methodology]
---

# Lens Cookoff Retrieval Pipeline -- Adjacent Domain Findings

Five agents from information retrieval, embedding evaluation, recommender recall, vector search operations, and benchmark methodology reviewed the proposed embedding retrieval pipeline for narrowing 291 lenses to top-K candidates across 1,360 dilemmas in a 12-model cookoff.

---

## Finding IR-1: Embedding the Wrong Unit -- Lens Fields Are Not Semantically Homogeneous

**Severity:** P1
**Agent:** fd-information-retrieval-architecture

**Description:** The design proposes embedding "name + when_to_apply + forces" for each lens. Examining the actual lens schema reveals these fields carry fundamentally different semantic types. `name` is a label ("Situation-Behavior-Impact"), `context` (the actual field name, not "when_to_apply") is a paragraph of situational description, and `forces` is a list of tension pairs ("individual excellence vs. collective performance"). Concatenating these into a single embedding vector averages heterogeneous semantic signals, diluting the most retrieval-relevant field.

**Evidence:** Lens `lens_11_weekly_situation-behavior-impact` has name "Situation-Behavior-Impact" (3 tokens of label), context field of 62 words describing feedback situations, and forces of 3 tension pairs. Lens `lens_12_weekly_explore_vs._exploit` has a 4-token name, 89-word context paragraph, and 3 force pairs. The context field carries the strongest semantic signal for matching against a dilemma description, but when concatenated with the name and forces, the embedding model must compress three distinct semantic types into one vector. The forces field uses a distinctive "X vs. Y" grammatical structure that will dominate certain embedding dimensions without contributing to dilemma-matching.

**Failure scenario:** A dilemma about team dynamics when hiring high performers should retrieve "The Disappointing Super-Chicken" lens. The dilemma text will be semantically close to the context field ("When teams of high performers underperform...") but the concatenated embedding is diluted by the name (which is metaphorical, not descriptive) and forces (which use abstract tension-pair grammar). A lens with a weaker context match but a name that happens to share vocabulary with the dilemma ("Team Performance Framework") could rank higher because its name contributes retrieval-relevant tokens that the embedding averages in.

**Recommendation:** Embed the `context` field alone as the primary retrieval vector. Use `forces` as a secondary re-ranking signal (embed separately, compute a weighted combination at retrieval time). The `name` field should not be embedded for retrieval -- it is useful as a display label, not a semantic key. Test this multi-field approach against single-concatenated-field on a validation set of 50 manually-annotated dilemma-lens pairs before committing to either approach for the full cookoff.

---

## Finding IR-2: No Validation Set -- Cannot Measure Retrieval Quality Before Running the Cookoff

**Severity:** P0
**Agent:** fd-evaluation-benchmark-methodology

**Description:** The design assumes embedding retrieval will surface the right lenses, but provides no mechanism to verify this assumption before spending tokens on the 12-model cookoff. Without a validation set of known-good dilemma-to-lens mappings, you cannot measure recall@10, precision@10, or NDCG for any embedding model or field combination. You are proposing to run a $500+ experiment on an unvalidated retrieval layer.

**Evidence:** The design lists six open questions, five of which require empirical answers (embedding model choice, top-K value, missed retrieval handling, hybrid approaches, field selection). None can be answered without ground truth labels. The cookoff itself is designed to compare model judgment, but if the retrieval layer silently filters out the best lens before any model sees it, the cookoff results measure model preferences within a biased candidate set, not model quality.

**Failure scenario:** You run the full cookoff with top-10 retrieval using nomic-embed-text. Post-hoc analysis reveals that for 23% of dilemmas, the lens that 8/12 models would have selected was ranked #14 by the embedding and never entered any model's candidate set. The entire cookoff measured model preferences within a truncated candidate set. You cannot retroactively determine what models would have selected from the full 291 because you never ran that comparison. The experiment must be partially re-run.

**Recommendation:** Before the cookoff, create a validation set of 50-100 dilemmas with manually annotated "gold" lens selections (3-5 lenses per dilemma, annotated by someone who knows the library). Use this to: (1) compare embedding models on recall@K for K=5,10,15,20, (2) determine the minimum K that achieves >95% recall of gold lenses, (3) validate field selection (context-only vs. concatenated). This validation set costs 2-4 hours of human annotation and saves potentially thousands of dollars in wasted cookoff runs.

---

## Finding IR-3: Top-10 Is Not a Principled Cutoff -- Use Score-Gap Adaptive Cutoff

**Severity:** P2
**Agent:** fd-vector-search-production-systems

**Description:** A fixed top-K=10 cutoff assumes the relevance distribution is uniform across all dilemmas. In practice, some dilemmas have 2-3 highly relevant lenses with a sharp score drop-off, while others have 15-20 moderately relevant lenses with a gradual decline. A fixed cutoff either includes noise (low-similarity lenses that waste model context) or excludes signal (relevant lenses that fall just outside the cutoff).

**Evidence:** The 291 lenses span disciplines from management science to psychology to design thinking to organizational psychology. A dilemma about feedback quality will cluster tightly with 3-5 feedback-related lenses and have a large cosine similarity gap before the next cluster. A dilemma about organizational change will have moderate similarity with 20+ lenses across systems thinking, management, psychology, and design thinking. The fixed K=10 overfits the first case and underfits the second.

**Failure scenario:** For a dilemma about team leadership, lenses ranked 8-12 all have cosine similarity 0.72-0.74 (effectively tied). The K=10 cutoff arbitrarily includes ranks 8-10 and excludes 11-12, which happen to include a relevant lens from a non-obvious discipline. The model never sees it. Meanwhile, for a simple feedback dilemma, ranks 4-10 have similarity 0.45-0.55 (noise), wasting 6 of 10 candidate slots on irrelevant lenses that consume model context tokens.

**Recommendation:** Implement a score-gap adaptive cutoff: compute cosine similarity for all 291 lenses, sort descending, and find the largest score gap (drop) in the top 20. Set the cutoff at the gap, with a floor of 5 and ceiling of 15. This ensures the candidate set captures the natural relevance cluster for each dilemma. For the cookoff specifically, also log the similarity scores for all 291 lenses per dilemma to enable post-hoc analysis of what the cutoff excluded.

---

## Finding IR-4: Embedding Model Selection Should Be Part of the Experiment, Not a Precondition

**Severity:** P2
**Agent:** fd-embedding-model-evaluation

**Description:** The design asks "what embedding model should we use?" as a decision to make before the cookoff. But embedding model quality on this specific task (matching dilemma text to lens context descriptions) is itself an empirical question that should be measured. The lens library is a highly specialized corpus -- general-purpose embedding benchmarks (MTEB) do not predict performance on domain-specific retrieval of conceptual frameworks.

**Evidence:** The available models span significant architectural differences: OpenAI text-embedding-3-large (3072 dims, strong on semantic textual similarity), nomic-embed-text (768 dims, local, trained with contrastive learning on diverse corpora), and OpenRouter-accessible models like voyage-3-large (1024 dims, optimized for retrieval). MTEB rankings show these models differ by 2-5% on academic benchmarks, but on specialized domains the gap can be 15-20% because training data distributions differ.

**Failure scenario:** You choose nomic-embed-text because it is local and fast. It performs adequately on your informal spot-checks. But nomic's training data skewed toward code and technical documentation, and it systematically underperforms on the psychology/philosophy-heavy lenses that constitute 40% of the library. OpenAI's model, trained on broader web text, would have retrieved those lenses correctly. You discover this only after running the full cookoff and doing a post-hoc audit.

**Recommendation:** Run a 3-way embedding model comparison on the validation set (Finding IR-2) before the cookoff: (1) OpenAI text-embedding-3-large, (2) nomic-embed-text via Ollama, (3) voyage-3-large via OpenRouter. Measure recall@10 and recall@15 for each. The total cost is approximately $0.50 for OpenAI embeddings (291 lenses + 100 dilemmas at ~500 tokens each) and negligible for nomic (local). Choose the model with the highest recall on the validation set.

---

## Finding IR-5: The Retrieval Layer Itself Generates Valuable Signal -- Log Everything

**Severity:** P2
**Agent:** fd-information-retrieval-architecture

**Description:** The design correctly notes that "the embedding retrieval itself is a signal -- which lenses cluster near which problem types." But the current design discards this signal by only passing the top-K to the model. The full similarity ranking for all 291 lenses per dilemma is a rich dataset for understanding lens library structure: which lenses are never retrieved (dead lenses), which are always retrieved (overly generic lenses), which cluster together (candidates for merging or hierarchical organization), and which dilemma types have sparse coverage (gaps in the library).

**Evidence:** The 291 lenses come from multiple flux-review episodes (source fields like "flux-review-ep11", "flux-review-ep13", "flux-review-ep14") and span disciplines including management science, psychology, organizational psychology, and design thinking. Community IDs (0, 3, etc.) suggest graph-based clustering has already been applied. Embedding-space clustering will either validate or challenge these community assignments, providing an independent structural view of the library.

**Recommendation:** For every dilemma, log the full 291-element similarity vector (not just top-K). After the cookoff, analyze: (1) lens retrieval frequency distribution (power law? uniform?), (2) lens-lens co-retrieval matrix (which lenses always appear together?), (3) dilemma coverage gaps (dilemmas where the top-1 similarity is below 0.5, suggesting no lens fits well), (4) comparison of embedding clusters vs. existing community_id assignments. This analysis is free -- it requires no additional API calls, just logging what you already compute.

---

## Finding IR-6: Missed Retrieval Problem Has a Standard Solution -- Two-Stage Retrieval with Expansion

**Severity:** P1
**Agent:** fd-recommender-system-recall-optimization

**Description:** The design identifies the "missed retrieval" problem but frames it as unsolvable within the embedding paradigm. This is a well-studied problem in information retrieval with established solutions. The standard approach is two-stage retrieval: a high-recall first stage (embedding) followed by a precision-focused second stage (model judgment). The first stage's recall can be boosted through query expansion without abandoning the embedding approach.

**Evidence:** The 1,360 dilemmas are ethical dilemmas with specific vocabulary. The 291 lens context fields use different vocabulary to describe the same conceptual space. "Team conflict" in a dilemma might match "group dynamics" in a lens context only weakly because the surface forms differ. Query expansion -- adding synonyms, hypernyms, or LLM-generated paraphrases of the dilemma -- bridges this vocabulary gap. In standard IR, query expansion improves recall by 10-25% on domain-specific corpora.

**Failure scenario:** A dilemma about "whistleblowing in a corrupt organization" should retrieve lenses about moral courage, institutional pressure, and principal-agent dynamics. But the dilemma text uses narrative language ("Sarah discovered her manager was falsifying reports") while the lens context fields use conceptual language ("when institutional incentives diverge from individual ethical obligations"). The embedding similarity is moderate (0.55) because the semantic overlap is conceptual, not lexical. The lens ranks #16 and is excluded by top-10 cutoff.

**Recommendation:** Add a query expansion step before embedding retrieval. For each dilemma, use a fast local model (or a cached LLM call) to generate 2-3 concept-level paraphrases: "What abstract themes does this dilemma involve?" Embed the original dilemma plus the paraphrases, and use the max similarity across all query embeddings for each lens. This increases recall at minimal cost (one additional LLM call per dilemma, cacheable). Alternatively, use the lens `forces` field as a separate retrieval pathway: embed the forces of all lenses, embed the dilemma, and take the union of top-K from context-based and forces-based retrieval.

---

## Finding IR-7: Sending 10 Full Lens Metadata Objects Is Still Token-Heavy -- Compress the Prompt

**Severity:** P2
**Agent:** fd-vector-search-production-systems

**Description:** The design moves from 291 full lenses to 10 full lenses per call, but 10 lenses with full metadata (name, context, forces, solution, questions, examples) still amounts to approximately 2,000-3,000 tokens per call. Across 1,360 dilemmas times 12 models, that is 24-43M tokens just for lens metadata in the prompt. The design achieves a 29x reduction from the 291-lens approach but may be leaving another 2-3x on the table.

**Evidence:** A single lens entry like "Situation-Behavior-Impact" has: name (3 tokens), definition (52 tokens), context (62 tokens), forces (25 tokens), solution (55 tokens), questions (75 tokens), examples (25 tokens) -- approximately 300 tokens. Ten lenses = 3,000 tokens. Across 16,320 calls (1,360 x 12), that is 49M tokens of lens metadata alone. For selection purposes, the model likely needs only name, context, and forces (90 tokens per lens, 900 per call, 14.7M total) -- a 3.3x reduction.

**Recommendation:** For the selection prompt, include only `name`, `context`, and `forces` for each candidate lens. The model needs to understand what the lens is about and when it applies, not the full solution methodology or example applications. If you want to verify that compressed prompts do not degrade selection quality, run a 50-dilemma comparison (full metadata vs. compressed metadata) on one model before the full cookoff.

---

## Finding IR-8: Consensus Analysis Needs a Baseline -- What Does Random Selection Look Like?

**Severity:** P2
**Agent:** fd-evaluation-benchmark-methodology

**Description:** The design plans to compare selections across 12 models to find "consensus (anchors) and disagreement (near-misses)." But without a baseline for expected agreement rates, you cannot distinguish meaningful consensus from chance overlap. If models independently select from 10 candidates with a mean of 2 selections each, the expected overlap between any two models is non-trivial even with random selection.

**Evidence:** With 10 candidates and each model selecting 0-3 (mean ~2), the probability of two models both selecting the same lens by chance is approximately 2/10 * 2/10 = 4% per lens, or about 0.4 expected overlapping selections per pair. With 12 models, there are 66 pairwise comparisons. By chance alone, you expect some lenses to appear in 3-4 models' selections. A lens selected by 4/12 models could be a chance artifact, not a meaningful anchor.

**Recommendation:** Before interpreting cookoff results, compute the null-hypothesis baseline: given the observed selection rate per model (how many lenses each model typically selects from 10 candidates), what is the expected agreement rate under random selection? Use a permutation test or hypergeometric distribution. Only classify a lens as an "anchor" if its selection count exceeds the 95th percentile of the null distribution. Similarly, classify "near-misses" only when disagreement exceeds the expected variance.
