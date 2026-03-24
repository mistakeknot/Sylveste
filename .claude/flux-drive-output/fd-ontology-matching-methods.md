# fd-ontology-matching-methods

**Scope:** Fitness and correctness of Khouri's ontology matching layer; SOTA alternatives.
**Sources reviewed:** shadow-work plan Task 5 (ontology_matching.py), Task 3 (adapter/OntologySchema), khouri-prd.md.
**Date:** 2026-03-20

---

## Summary

Khouri's current ontology matching (Task 5 in the shadow-work plan) is a **single-pass pure-LLM matcher**: it sends all extracted concepts and the full ontology schema to Claude Sonnet in one prompt and parses the JSON response. There are no embeddings, no structural constraints, no threshold calibration, no caching, and no evaluation harness. The architecture brief describes an "embeddings-first, LLM-for-disambiguation" hybrid, but the implementation plan delivers neither the embedding layer nor the hybrid fallback. For the small ontology sizes involved (12 pressure types, 8 institution types, 18 issue types = 38 target entities), pure LLM matching is defensible as an MVP, but it leaves precision/recall unverified, coalition matches underspecified, and cost scaling poor.

---

## Findings

### F1. No embedding layer exists — pure LLM matching only [Severity: HIGH]

The plan's `match_forecast_to_ontology()` sends a flat list of concepts and a flat list of ontology entities to a single LLM call. The architecture brief specified "embedding similarity for candidates, LLM for disambiguation," but the implementation skips the embedding stage entirely.

**Impact:** Without an embedding pre-filter, every matching invocation pays full LLM cost (~4K output tokens). For repeated runs against the same ontology, this is wasteful. More critically, the LLM has no graded similarity signal — it must intuit similarity from prompt context alone, which is unreliable for domain-specific jargon (e.g., "radical hospitality" vs. "legitimacy_crisis" requires understanding that hospitality-as-governance-model challenges legitimacy frameworks).

**Evidence:** `ontology_matching.py` lines 739-789 — the entire matching logic is a single `client.messages.create()` call with no embedding computation.

### F2. No structural or relational constraints during matching [Severity: MEDIUM]

The `OntologySchema` includes `cascade_edges` (a directed graph of pressure-type relationships), but the matching stage ignores them entirely. The `schema_desc` string sent to the LLM contains only flat lists of entity names — no edges, no graph structure.

**Impact:** Graph-aware matching exploits the constraint that if concept A maps to pressure X, and A causally relates to B, then B should preferentially map to entities reachable from X in the cascade graph. Without this, the LLM may produce structurally inconsistent mappings (e.g., mapping two causally linked forecast concepts to entities that have no cascade path between them).

**Evidence:** `ontology_matching.py` line 755-758 — `schema_desc` omits `schema.cascade_edges`. The cascade edges are defined in `OntologySchema` (adapter.py line 323) but never referenced in matching.

### F3. Matching threshold calibration is absent [Severity: HIGH]

The LLM returns categorical confidence labels (`high/medium/low/none`) rather than continuous similarity scores. There is no calibration of what these labels mean in practice, no threshold for "accept vs. reject," and no mechanism to validate that the LLM's confidence correlates with actual match quality.

**Impact:** Downstream gap synthesis treats `target_entity=None` as unmapped and `confidence=LOW` as mapped-but-suspicious, but there is no empirical basis for these boundaries. A concept marked `high` by the LLM might be a false positive; one marked `none` might have a valid coalition match the LLM missed.

**Evidence:** `ontology_matching.py` returns `MappingConfidence` enum directly from LLM output; `gap_synthesis.py` lines 916-917 filter on these labels without validation.

### F4. One-to-many and coalition matching is underspecified [Severity: HIGH]

The matching prompt says "A single concept can require multiple mappings if it spans types," but the data model (`OntologyMapping`) maps one `source_concept` to one `target_entity`. Coalition matches — where a destination concept maps to a *set* of current-world institutions acting together — are not representable.

**Impact:** Futures-studies concepts frequently have no single equivalent. "Housing-as-right" might require a coalition of `treasury` + a missing `housing_authority` institution type + `social_unrest` pressure. The current model can only express this as multiple independent `OntologyMapping` objects with the same `source_concept`, losing the coalition semantics (these entities must *co-occur* to represent the concept, not independently).

**Evidence:** `models.py` line 209-214 — `OntologyMapping` has `target_entity: str | None`, singular. No `target_entities: list[str]` or `coalition` field.

### F5. No caching of ontology matching results [Severity: MEDIUM]

Each pipeline run re-matches all concepts against the ontology from scratch. For iterative scenario exploration (running multiple prompts against the same Shadow Work ontology), previously established high-confidence mappings are discarded.

**Impact:** Cost and latency scale linearly with number of prompts. Stable mappings (e.g., "sea level rise" -> "pressure:environmental_stress") should be cached and reused. The plan acknowledges this in "Known Limitations" (line 1495: "Consider caching ontology groundings across prompts in the same scenario family") but provides no implementation.

**Staleness risk:** If the ontology changes (new pressure types added), cached mappings become stale. Any caching layer needs an invalidation key tied to ontology schema version (the `metadata.version` field in `OntologySchema` could serve this purpose).

### F6. No gold-standard evaluation set [Severity: HIGH]

There is no reference alignment to measure precision/recall against. The test (`test_ontology_matching.py`) checks only that mappings are returned and that at least one is non-null — it does not verify *correctness* of specific mappings.

**Impact:** Without a gold standard, it is impossible to know whether the matcher is producing useful results or hallucinating plausible-looking but wrong alignments. This is the single largest quality risk.

**Evidence:** `test_ontology_matching.py` lines 668-675 — assertions check `len(mapped) > 0` but never check that specific concepts map to specific entities.

### F7. Concept extraction is naive [Severity: LOW]

`_extract_concepts()` splits CLA text on commas and periods with a length filter of >3 characters. This produces noisy, fragmentary phrases rather than semantically meaningful concept units.

**Impact:** The LLM matcher receives fragments like "atmospheric processors" alongside full phrases like "Climate adaptation as economic engine." Inconsistent granularity degrades matching quality. An LLM-based or NLP-based concept extraction step would produce cleaner inputs.

---

## Recommendations

### R1. Add an embedding pre-filter for candidate retrieval [Priority: HIGH]

Implement the originally specified architecture: compute embeddings for both source concepts and target ontology entities, retrieve top-k candidates by cosine similarity, then send only those candidates to the LLM for disambiguation.

**Model choice for domain fit:**

- **AVOID** general-purpose sentence-transformers (e.g., `all-MiniLM-L6-v2`). These are trained on web text and poorly calibrated for futures-studies and political science jargon.
- **RECOMMENDED:** `intfloat/e5-mistral-7b-instruct` or `BAAI/bge-en-icl` — instruction-tuned embedding models where you can prepend a task description like "Match this futures-studies concept to the most similar simulation ontology entity." Instruction-tuning significantly improves domain transfer.
- **ALTERNATIVE:** `Alibaba-NLP/gte-Qwen2-7B-instruct` — strong on specialized terminology, supports instruction prefixes.
- **LIGHTWEIGHT:** If latency matters, `BAAI/bge-small-en-v1.5` with a 2-3 sentence domain description prepended to each input is a reasonable tradeoff.
- **AVOID** OpenAI `text-embedding-3-*` for this use case — closed-source, no instruction-tuning control, and the domain gap is not addressable.

For 38 target entities, the embedding index fits in memory trivially. Retrieval adds <100ms per concept.

### R2. Incorporate graph structure into matching via cascade-aware re-ranking [Priority: MEDIUM]

After embedding retrieval produces candidates, re-rank them using cascade graph adjacency. If concept A maps to entity X with high confidence, and concept B is causally linked to A in the forecast, boost candidates for B that are reachable from X in `cascade_edges`.

**SOTA methods that exploit graph structure:**

- **BERTMap** (He et al., ISWC 2022; https://github.com/KRR-Oxford/BERTMap): BERT-based ontology matching with structure-aware refinement. Uses sub-word semantics + logical constraints. Well-suited when ontologies have hierarchical or relational structure. Lightweight, pip-installable.
- **LogMap** (Jimenez-Ruiz & Grau, ISWC 2011; https://github.com/ernestojimenezruiz/logmap-matcher): Established ontology matching system using lexical indexing + structural repair. Handles large ontologies efficiently. Java-based but has a Python wrapper (`logmap-ml`).
- **PARIS** (Suchanek et al., VLDB 2012): Probabilistic alignment using both attribute and relational evidence. Good for entity resolution across knowledge bases. Less suitable here due to small ontology size.
- **GMN (Graph Matching Networks)** (Li et al., ICML 2019): GNN-based approach that learns node-to-node correspondences by message-passing across both graphs simultaneously. Overkill for 38-entity ontologies but relevant if the ontology grows to hundreds of entities.
- **Agent-OM** (PVLDB 2025, cited in the plan): LLM-agent ontology matching. The plan references it but doesn't implement its key insight — multi-round retrieval-augmented matching with verification. The current implementation is a single-shot prompt, not an agentic loop.

**Recommendation for Khouri's scale:** BERTMap's approach (embedding similarity + structural repair) is the best fit. The ontology is small enough that LogMap and PARIS are unnecessary. GMN is relevant only if ontology size grows 10x+.

### R3. Build a gold-standard evaluation set [Priority: HIGH]

Create a manually curated alignment file (`testdata/gold-standard-la2525.json`) with ~30-50 concept-to-entity mappings including:
- Direct matches (e.g., "sea level rise" -> "pressure:environmental_stress")
- Coalition matches (e.g., "housing-as-right" -> ["institution:treasury", "gap:missing_institution_type:housing_authority"])
- Intentional non-matches (e.g., "radical hospitality" -> null, with gap_type annotation)
- Asymmetric matches where multiple concepts map to the same entity

Use this to compute precision, recall, and F1 for the matcher. Run it as a regression test.

### R4. Extend OntologyMapping to support coalition matches [Priority: HIGH]

Replace `target_entity: str | None` with:

```python
class OntologyMapping(BaseModel):
    source_concept: str
    target_entities: list[str] = Field(default_factory=list)  # coalition
    confidence: MappingConfidence = MappingConfidence.NONE
    coalition_required: bool = False  # True if entities must co-occur
    rationale: str = ""
```

This lets the matcher express "housing-as-right requires treasury AND a new housing_authority institution type" as a single mapping with `coalition_required=True`.

### R5. Add an ontology-keyed matching cache [Priority: MEDIUM]

Cache high-confidence mappings keyed by `(concept_normalized, ontology_version)`. Use a simple JSON file or SQLite store. Invalidate when `OntologySchema.metadata.version` changes. For the MVP, even a session-scoped dict that persists across multiple prompts in the same `run_pipeline` invocation would help.

### R6. Replace naive concept extraction with LLM-based extraction [Priority: LOW]

Use a lightweight LLM call (or even a smaller model like Haiku) to extract semantically coherent concept units from CLA text, rather than comma-splitting. This produces cleaner inputs for both embedding and LLM matching.

### R7. Calibrate confidence via temperature-scaled logprobs [Priority: LOW]

If using the Anthropic API's logprobs feature (when available), calibrate the LLM's confidence labels against actual token-level certainty. Alternatively, run the matcher N times at temperature >0 and use agreement rate as a proxy for confidence.

---

## Assessment Against Success Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| Precision/recall on gold-standard set | NOT MET | No gold standard exists; no evaluation harness |
| Coalition match handling | NOT MET | Data model is singular `target_entity`; coalition semantics lost |
| Embedding-first architecture | NOT MET | Pure LLM matching; no embeddings |
| Graph-aware constraints | NOT MET | Cascade edges ignored during matching |
| Caching across runs | NOT MET | No caching layer |
| SOTA method comparison | REVIEWED | BERTMap recommended for scale; Agent-OM cited but not implemented |
