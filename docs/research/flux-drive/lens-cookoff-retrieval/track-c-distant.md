---
artifact_type: flux-drive-findings
track: distant
target: "apps/Auraken/ — lens cookoff embedding retrieval pipeline"
date: 2026-03-31
agents: [fd-sommelier-wine-pairing-selection, fd-traditional-chinese-medicine-pattern-diagnosis, fd-museum-curation-exhibition-design]
---

# Lens Cookoff Retrieval Pipeline -- Track C (Distant Domain) Findings

Structural isomorphisms from three distant knowledge domains applied to the problem of selecting the right conceptual framework (lens) for a given ethical dilemma. Each domain has solved a version of the same problem: matching a complex, multidimensional input to the right item from a large repertoire, where the "right" answer depends on context, subjectivity, and expertise.

---

## Agent: fd-sommelier-wine-pairing-selection

### Finding SW-1: Embedding Retrieval Is Varietal Matching -- It Misses the Sommelier's Contextual Read

**Severity:** P1
**Type:** Opens a new question

**Source domain mechanism:** A novice wine selector matches by varietal: red meat gets red wine, fish gets white wine. A sommelier matches by contextual read: the weight of the sauce, the cooking method, the season, the diner's mood, the progression of courses, what was drunk before. The varietal match (Cabernet with steak) is a reasonable default that is correct 60% of the time, but the sommelier's contextual read is what produces the "how did you know?" moments. Critically, the sommelier sometimes picks a wine that violates the varietal rule (a light red with fish, a full-bodied white with steak) because the contextual factors override the category match.

**Mapping to Auraken:** Embedding retrieval is varietal matching -- it finds lenses whose description is semantically similar to the dilemma's description. This captures the surface match (management dilemma gets management lens) but misses the contextual read. A dilemma about a startup founder's hiring decision might semantically match "hiring best practices" lenses, but a sommelier-equivalent selection would recognize that the real tension is the founder's fear of losing control, and select a lens about identity-attachment or ego-threat from psychology -- a category violation that produces insight.

**Failure scenario:** The embedding retrieval pipeline consistently surfaces same-category lenses. The cookoff measures model judgment within same-category candidates. The resulting "best" lens selections are reasonable but unsurprising -- they are the varietal matches. The cross-disciplinary insight that is Auraken's core value proposition ("see problems differently") is architecturally excluded by the retrieval layer.

**Agent:** fd-sommelier-wine-pairing-selection

**Recommendation:** Add a "sommelier slot" to the candidate set: 2-3 candidates selected not by embedding similarity but by a lightweight reasoning step. For each dilemma, ask a fast model: "What is the underlying tension in this dilemma, independent of its surface domain? Name the tension in abstract terms." Then embed this abstract tension description and retrieve lenses whose `forces` field matches. This two-hop retrieval (dilemma -> abstract tension -> lens forces) is the computational analog of the sommelier's contextual read.

---

### Finding SW-2: The Cookoff Measures Selection, Not Pairing -- Selection Without Context Is Incomplete

**Severity:** P2
**Type:** Reframes the problem

**Source domain mechanism:** A sommelier does not just select a wine -- they explain the pairing rationale. "This Gruner Veltliner has enough acidity to cut through the butter sauce, and the white pepper notes will echo the seasoning." The explanation is part of the value; it teaches the diner to think about food-wine interactions. Two sommeliers might select the same wine for different reasons, and the reasons reveal different levels of expertise.

**Mapping to Auraken:** The cookoff measures which lens each model selects (0-3 from 10 candidates), but not why. Two models selecting the same lens for different reasons represent different quality of lens application. Claude might select "Explore vs. Exploit" because the dilemma involves resource allocation under uncertainty (deep structural match). GPT-4o might select it because the dilemma mentions "trying new things vs. sticking with what works" (surface lexical match). The selections are identical; the quality of insight they would produce is not.

**Agent:** fd-sommelier-wine-pairing-selection

**Recommendation:** Require each model to provide a 1-2 sentence rationale for each lens selection. In the analysis phase, classify rationales as surface-match (restates the dilemma in lens vocabulary), structural-match (identifies the underlying tension the lens addresses), or insight-match (explains what the lens reveals that is not obvious from the dilemma). Use rationale quality as a secondary signal alongside selection agreement. This costs ~50 additional tokens per selection but produces dramatically richer comparison data.

---

## Agent: fd-traditional-chinese-medicine-pattern-diagnosis

### Finding TCM-1: Pattern Diagnosis Cannot Be Decomposed Into Symptom-Matching -- The Gestalt Matters

**Severity:** P1
**Type:** Challenges core assumption

**Source domain mechanism:** In traditional Chinese medicine pattern diagnosis (zheng), a practitioner does not match individual symptoms to conditions. Instead, they perceive a pattern across multiple dimensions simultaneously: pulse quality, tongue appearance, emotional state, season, time of day, patient constitution. The same symptom (headache) maps to entirely different patterns depending on what it co-occurs with. A headache with irritability and a wiry pulse is liver qi stagnation; a headache with fatigue and a weak pulse is qi deficiency. Symptom-matching would retrieve both patterns equally; pattern diagnosis selects one definitively.

**Mapping to Auraken:** Embedding retrieval treats the dilemma as a bag of semantic features and matches against lens descriptions as bags of semantic features. This is symptom-matching. But the "right" lens for a dilemma depends on the gestalt -- the way multiple elements interact, not their individual semantic content. A dilemma about a leader who must choose between two qualified candidates (surface: hiring decision) where one candidate is the leader's former mentor (depth: authority inversion, identity) and the choice will be announced publicly (context: reputation stakes) has a gestalt that points to a specific lens. The embedding captures each element but not their interaction.

**Failure scenario:** The embedding retrieval surfaces "hiring best practices," "decision-making under uncertainty," and "leadership frameworks" -- all reasonable single-symptom matches. The gestalt-appropriate lens ("authority anxiety," "status reversal dynamics," or "face-saving under scrutiny") is ranked low because no single element of the dilemma strongly matches those lens descriptions. The interaction between elements creates the meaning, and embeddings cannot represent interactions.

**Agent:** fd-traditional-chinese-medicine-pattern-diagnosis

**Recommendation:** Add a gestalt extraction step before retrieval. For each dilemma, use a fast model to extract: (1) the surface problem type, (2) the relational dynamics between actors, (3) the contextual pressures (visibility, stakes, time), (4) the emotional undertone. Construct a retrieval query from elements (2)+(3)+(4) rather than (1), biasing retrieval toward lenses that address the non-obvious dimensions. This is computationally cheap (one short LLM call per dilemma, cacheable) and targets exactly the signal that embedding similarity misses.

---

### Finding TCM-2: Constitution Matters -- The Same Dilemma Needs Different Lenses for Different People

**Severity:** P2
**Type:** Opens a new question

**Source domain mechanism:** In TCM, two patients with identical symptoms may receive different treatments because they have different constitutions (ti zhi). A cold-constitution patient with a headache gets warming herbs; a hot-constitution patient with the same headache gets cooling herbs. The symptom is the same; the treatment depends on the patient. Constitution is assessed over time through the full clinical relationship, not from a single visit.

**Mapping to Auraken:** The cookoff sends the same dilemma to 12 models and compares their lens selections, treating disagreement as noise to be resolved through consensus. But in the full Auraken system, lens selection depends on the user's cognitive profile -- their thinking patterns, blind spots, and framework familiarity. The "right" lens for a given dilemma varies by user. The cookoff's consensus analysis assumes there is a single best lens per dilemma, which contradicts Auraken's core thesis that lens selection should be personalized.

**Agent:** fd-traditional-chinese-medicine-pattern-diagnosis

**Recommendation:** The cookoff should explicitly distinguish between two signals: (1) which lenses are universally relevant to a dilemma (consensus = the dilemma's "syndrome"), and (2) which lens is best for a specific user (requires constitution/profile). The current design conflates these. Add a "for whom?" dimension to the analysis: when models disagree, classify whether the disagreement stems from different interpretations of the dilemma (retrieval problem) or different assumptions about the user (personalization signal). The latter is not noise -- it is information about which dilemmas benefit most from personalized selection.

---

## Agent: fd-museum-curation-exhibition-design

### Finding MC-1: The Candidate Set Is a Gallery Wall -- Adjacency Creates Meaning

**Severity:** P2
**Type:** Concrete improvement

**Source domain mechanism:** A museum curator does not just select individual artworks -- they compose the gallery wall. The meaning of a painting changes based on what is hung next to it. A Rothko next to a Mondrian creates a conversation about color fields and geometric abstraction. The same Rothko next to a Bacon creates a conversation about emotional intensity and the sublime. The curator's art is in the adjacency, not just the selection.

**Mapping to Auraken:** The design sends 10 candidate lenses to each model as an unstructured list. But the composition of the candidate set creates implicit framing. If 7 of 10 candidates are from psychology and 3 from systems thinking, the model is implicitly told "this is probably a psychology problem." The candidate set is a gallery wall, and its composition primes the model's interpretation. Two different top-10 sets for the same dilemma could lead the same model to different selections, not because the model changed its judgment, but because the framing changed.

**Evidence:** In the lens library, discipline distribution is uneven. If a dilemma has strong semantic overlap with psychology lenses, the top-10 by embedding similarity could be 8 psychology lenses and 2 from other fields. The model sees 8 psychology options and is primed to think psychologically about the dilemma. An alternative retrieval that surfaces 5 psychology, 3 systems thinking, and 2 design thinking candidates would produce different model behavior on the same dilemma.

**Agent:** fd-museum-curation-exhibition-design

**Recommendation:** After retrieval, apply a discipline-diversity constraint to the candidate set: no more than 50% of candidates from any single discipline. If embedding retrieval produces 8 psychology lenses in the top-10, replace the 3 lowest-ranked psychology lenses with the highest-ranked non-psychology lenses from positions 11-20. This ensures the candidate set is a curated gallery wall that invites cross-disciplinary thinking, not a disciplinary echo chamber.

---

### Finding MC-2: The Exhibition Needs a Thesis -- What Is the Cookoff Actually Testing?

**Severity:** P1
**Type:** Reframes the problem

**Source domain mechanism:** Every museum exhibition has a curatorial thesis -- a question or argument the exhibition is organized around. "How did post-war trauma reshape abstract expressionism?" "What happens when African and European textile traditions meet?" Without a thesis, a collection of artworks is storage, not an exhibition. The thesis determines what to include, what to exclude, and how to interpret what you see.

**Mapping to Auraken:** The cookoff proposes to run 12 models on 1,360 dilemmas and look for "consensus and disagreement." This is a collection without a thesis. What is the cookoff actually testing? Possible theses:

(A) "Frontier models converge on lens selection, proving there are objectively best lenses for given problem types" -- this thesis needs consensus to succeed.

(B) "Different model architectures have different lens selection biases, and the biases are systematic" -- this thesis needs disagreement to succeed.

(C) "Embedding retrieval is sufficient to narrow the candidate set without losing the best lenses" -- this thesis needs recall measurement to succeed.

(D) "The 291-lens library has good coverage of ethical dilemma space" -- this thesis needs coverage gap analysis to succeed.

These are four different exhibitions that share some artworks but are organized completely differently.

**Agent:** fd-museum-curation-exhibition-design

**Recommendation:** Declare a primary thesis and organize the cookoff around it. If the thesis is (C) -- retrieval sufficiency -- then the cookoff design should include a recall validation phase (see IR-2). If the thesis is (A) -- model convergence -- then the statistical analysis plan should test for convergence significance (see CT-1). If the thesis is (B) -- model biases -- then the analysis should cluster models by selection patterns and characterize each cluster. A cookoff that tries to answer all four questions will answer none of them well. Pick one as primary, design for it, and treat the others as secondary analyses.

---

### Finding MC-3: Provenance Tracking -- Which Findings Come From Retrieval vs. Model Judgment?

**Severity:** P2
**Type:** Concrete improvement

**Source domain mechanism:** Museum provenance tracking documents the chain of custody for every artwork: where it was made, who owned it, how it arrived at the museum. Without provenance, the museum cannot authenticate the work, assess its condition, or make informed decisions about its display. Provenance is not about the artwork itself -- it is about the reliability of everything the museum claims about the artwork.

**Mapping to Auraken:** The cookoff's final output will be a set of dilemma-lens pairings with consensus scores. But these pairings have two-stage provenance: the embedding retrieval selected the candidates, then the model selected from the candidates. If a lens appears in the consensus set, was it because (a) the embedding ranked it highly AND the models preferred it, (b) the embedding ranked it marginally (position 9-10) but the models strongly preferred it, or (c) the embedding ranked it highly but only some models selected it? Each provenance chain implies a different confidence level and a different interpretation.

**Agent:** fd-museum-curation-exhibition-design

**Recommendation:** For every consensus lens, log and report its retrieval provenance: (1) embedding rank (was it top-3 or barely-in-top-10?), (2) embedding score (how confident was the retrieval?), (3) model selection rate (what fraction of models chose it?), (4) was it selected despite being a low-ranked candidate (strong model signal overriding weak retrieval signal)? Cases where models consistently select low-ranked candidates are the most valuable signal -- they reveal where the embedding model's judgment diverges from frontier model judgment, and these are exactly the lenses where embedding retrieval is most likely to fail in production.
