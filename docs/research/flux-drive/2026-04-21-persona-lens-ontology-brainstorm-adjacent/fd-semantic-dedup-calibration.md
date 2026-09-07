### Findings Index
- P1 | SDC-01 | "Epic shape #3 + Open Questions: dedup threshold" | No embedding model, no threshold, no calibration corpus — dedup ships as vibes-based merge-and-hope
- P1 | SDC-02 | "D7. Dedup before unification is a non-goal + D6 same-as" | `same-as` confidence is introduced without downstream consumers specifying how they use it — hard filter? weighted? both?
- P2 | SDC-03 | "Epic shape #3: manual review of top-100 canonicals" | "Top 100 canonicals" is undefined (centrality? flagged pairs? random sample?) and misses the long-tail failure mode
- P2 | SDC-04 | "Cross-store asymmetry" | fd-agents carry rich task_context that Auraken lenses lack; embedding will be distracted by generation-artifact text, producing asymmetric similarity
- P2 | SDC-05 | "Epic shape #3 one-week estimate" | 1 week is aggressive for calibrate-model-threshold-label-100-pairs-review-audit; label work alone is 2-4 days
- P3 | SDC-06 | "D6 same-as {confidence, method}" | `method` field is introduced without a vocabulary — which methods will be accepted values?
Verdict: needs-changes

## Summary

Dedup is the pass where ontology quality is made or lost. The brainstorm commits to the `same-as {confidence, method}` schema shape, which is right, but leaves every calibration decision deferred: no embedding model named, no threshold, no labeled set. Ship this as-is and the graph inherits silent false-positive merges that corrupt every downstream view. The fix is mechanical — a calibration-first sub-phase before the "Semantic dedup pass" child — but it has to be written into the plan, not assumed.

## Issues Found

### 1. [P1] No embedding model, no threshold, no calibration corpus — SDC-01

**File:** `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`, Epic shape #3 line 92, Open Questions §"Dedup threshold" line 103.

The brainstorm says "Embedding-based nearest-neighbor over all entries, populate `same-as` relationships with confidence. Manual review of top-100 canonicals." Every word in that sentence hides a decision:

- **Which embedding model?** OpenAI `text-embedding-3-small` (1536d, $0.02/1M, good general quality)? `text-embedding-3-large` (3072d, pricier, better long-tail)? Local BGE-m3 / Qwen3-Embedding (free, requires GPU/CPU budget, different calibration)? The three stores have different text densities — fd-agents have 100-500 words of task_context per entry, Auraken lenses have 50-200 words of forces/solution/questions, interlens lenses are terse. Model choice interacts with these.

- **What threshold?** Cosine 0.85 on `text-embedding-3-small` is not the same semantic distance as cosine 0.85 on BGE-m3. The threshold only has meaning relative to a specific model + corpus.

- **What labeled set?** The open question acknowledges "likely needs a calibration run on a labeled set." This is the whole game. Without 30-50 manually-labeled pairs spanning "clear same-as," "clear distinct," and "ambiguous" — you cannot compute precision/recall at any threshold. Confidence scores without a calibration corpus are arbitrary numbers.

**Failure scenario:** Dedup ships at, say, cosine 0.8 for OpenAI embeddings (a popular default). After the pass, 200+ `same-as` edges exist. Of those, an unknown fraction are false positives — genuinely different lenses conflated because the embedding model latched onto stylistic similarity rather than semantic equivalence. Downstream triage reads `same-as` as equivalence; false-positive merges cause wrong-persona selection. The errors are invisible because nobody audits them — the top-100 review sampled the *obviously-correct* merges (highest cosine), not the borderline ones where the errors live.

**Smallest fix:** Split "Semantic dedup pass" into two sub-phases:
- **3a. Calibration** (3-4 days): Pick an embedding model. Sample 50 pairs spanning the cosine distribution (10 at 0.95+, 10 at 0.85-0.95, 10 at 0.75-0.85, 10 at 0.6-0.75, 10 at <0.6). Manually label each as same-as / similar / different. Compute precision at candidate thresholds. Pick threshold with >=95% precision on labeled set; record recall at that threshold as an honest estimate.
- **3b. Dedup run** (2-3 days): Execute at the calibrated threshold. Audit not just "top-100 canonicals" but a stratified random sample across the threshold band (see SDC-03).

Total: still a week, but the week is honest.

### 2. [P1] `same-as` consumer contract is undefined — SDC-02

**File:** same brainstorm, D6 line 75, D7 line 77-78.

D6 declares `same-as {confidence, method}` as an edge property. D7 says "A Persian-medicine-assay lens and an Akan-goldweight-metrology lens might be 'same-as' at 0.8 confidence but stay as distinct entries." Good — dedup doesn't collapse. But the question is: how do *queries* use the confidence?

- Flux-drive triage: does it treat `same-as` as equivalence (substitute one for the other in matching)? Weight by confidence (count `same-as > 0.9` as full match, 0.8 as half)? Ignore below some threshold?
- Hermes conversational view: surfacing "similar lenses" — does confidence rank them?
- Catalog browse: shows `same-as` as an explicit link ("see also") or silently merges display?

Different consumers imply different thresholds and different confidence-interpretation policies. The dedup pass cannot calibrate a threshold without knowing what the consumers need.

**Failure scenario:** Dedup ships at cosine 0.8 because "that seemed safe." Triage treats `same-as > 0.7` as equivalence — noisy matches. Catalog shows every `same-as` — users see spurious "see also" links. Each consumer built its own policy post-hoc; the schema didn't force the conversation.

**Smallest fix:** Before the dedup pass, require each consumer (triage, Hermes, catalog) to specify its `same-as` policy. Simplest form: add a "Same-As Consumer Contract" section to the plan listing per-consumer threshold and semantics. Two sentences per consumer is enough.

### 3. [P2] "Top 100 canonicals" is undefined and misses the long tail — SDC-03

**File:** same brainstorm, Epic shape #3 line 92.

"Manual review of top-100 canonicals." This phrase has at least four plausible meanings:
- Top 100 by centrality in the `same-as` graph (most-linked nodes)
- Top 100 tightest clusters (connected components of `same-as` edges)
- Top 100 `same-as` candidates at threshold (pairs with highest cosine)
- Top 100 by use frequency (most-queried personas/lenses)

Each produces a different audit. More importantly, dedup failures do NOT cluster at the top. Top-cosine pairs are the *easy* ones — usually correct. The errors are at cosine 0.70-0.85, where some are same-as and some aren't.

**Failure scenario:** Audit happens, looks clean (because it sampled the easy cases), dedup ships, borderline errors go undetected and corrupt the graph silently.

**Smallest fix:** Replace "top-100 canonicals" with "stratified random sample of 150 pairs: 30 at each decile from 0.7 to 1.0." This sample is what lets you estimate precision/recall at your chosen threshold. If the calibration from SDC-01 is done, this is the validation set.

### 4. [P2] Cross-store asymmetric text density distorts embeddings — SDC-04

**File:** same brainstorm, §"Today's fragmentation" lines 20-23.

fd-agents have rich per-entry text: persona + task_context + review questions + domains + source_spec (100-500 words). Auraken lenses have forces/solution/questions/discipline (50-200 words). interlens lenses are terser. When you embed all of these into the same vector space, fd-agents will land clustered by task_context similarity (which includes generation-run artifacts like "review of persona-lens-ontology" shared by many agents generated in the same run). Auraken lenses lack that text, so they cluster by content. Cross-store `same-as` between an fd-agent and an Auraken lens will have systematically lower similarity than within-store — even when they're genuinely same-as.

**Failure scenario:** Dedup finds lots of within-store `same-as` (some real, some artifact-driven) and few cross-store `same-as` (including the real ones that unification was supposed to surface). The whole point of unifying the three stores — finding that the Persian-medicine-assay lens and the Akan-goldweight-metrology lens are talking about fuzzy-metrology — is undermined by the text-asymmetry.

**Smallest fix:** Before embedding, extract a canonical "essence text" per entry: for fd-agents, use persona + domains only (drop task_context). For Auraken, use forces + solution. For interlens, use the lens body. Normalize length (truncate/pad to similar token counts). Embed the essence, not the raw record. Keep the raw record for provenance on the entity, but don't feed it to the embedding model.

### 5. [P2] 1-week estimate is aggressive — SDC-05

**File:** same brainstorm, Epic shape #3 line 92 ("~1 week").

Real dedup-pass work at this scope:
- Calibration (model choice, labeled set, threshold): 3-4 days
- Embed all 1200 entries + quality checks: 0.5-1 day
- Run nearest-neighbor at threshold, generate candidate pairs: 0.5 day
- Stratified audit of 150 pairs: 1-2 days
- Load `same-as` edges with method+confidence: 0.5 day

Total: 6-9 days of focused work. One focused week is plausible if the calibration corpus pre-exists; two weeks if it's built from scratch.

**Smallest fix:** Update the Epic shape #3 estimate to "~1.5-2 weeks" or split calibration and dedup into separate children. Underestimating this forces either shortcuts (skipping calibration) or schedule drift (which compounds across the epic).

## Improvements

### 1. Define `method` vocabulary for same-as — SDC-06

D6 says `same-as {confidence, method}`. `method` is useful — it lets you distinguish "dedup-cosine-0.87" from "manual-merge" from "derived-from-bridge-score>=0.9". Write the accepted `method` values into the schema now: `cosine_<model>_<threshold>`, `manual`, `bridge_score_ge`, ... — not enumerated as an enum (too rigid for research iteration), but documented as conventions so downstream consumers can pattern-match.

### 2. Plan a dedup audit view up front

The graph will accumulate `same-as` edges over time (re-runs, new ingestion, manual additions). Design a simple SQL/Cypher view that lists same-as edges grouped by method and confidence band. This is the observability layer for dedup quality. 30 minutes of design now, months of value later.

### 3. Instrument per-store embedding-quality checks

After embedding, compute the distribution of intra-store cosine similarities. If fd-agent-to-fd-agent mean cosine is >0.9 and Auraken-to-Auraken is ~0.5, you have the text-asymmetry problem (SDC-04) before you dedup. Fail fast.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 2, P2: 3, P3: 1)
SUMMARY: Dedup ships blind without a calibration sub-phase and explicit consumer contracts for same-as confidence. Split the 1-week child into calibration (labeled set, threshold) then dedup run. Embed essence text, not raw records, to avoid cross-store asymmetry.
---
<!-- flux-drive:complete -->
