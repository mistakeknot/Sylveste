# Flux Drive: Frontier Causal Inference Methods for Khouri

**Date:** 2026-03-20
**Scope:** Whether Khouri's hybrid LLM+deterministic architecture is best-available, and what frontier causal AI / esoteric cross-disciplinary methods offer as alternatives or augmentations.
**Non-overlap:** Does not cover CLA methodology correctness, sheaf implementation correctness, or ontology matching ML specifically.

---

## Summary

Khouri's current architecture — LLM agents for CLA decomposition and gap classification, deterministic stages for graph comparison and sheaf consistency, ML/embeddings for ontology matching — is a reasonable pragmatic starting point but has a critical structural vulnerability: **LLM-generated causal edges are unvalidated**. The CausalClaim objects produced in Stage 1 (cause/effect/mechanism/confidence) are pure confabulation with no statistical grounding. The confidence field is particularly dangerous — it creates an illusion of calibration where none exists.

Six frontier methods were evaluated. Two are recommended as concrete augmentations (causal discovery on structured corpora, TDA persistent homology on SID graphs). One yields a novel theoretical prediction (mechanism design framing produces an impossibility result for backward tracing). The remaining three (world models, category theory, neuro-symbolic constrained generation) are theoretically interesting but not implementable within Khouri's current architecture without fundamental redesign.

---

## Findings

### 1. Causal Discovery Algorithms on Structured Forecast Corpora

**Impact: HIGH | Feasibility: MEDIUM**

**The problem.** Khouri's Stage 1 asks an LLM to produce `CausalClaim(cause, effect, mechanism, confidence)`. LLMs hallucinate causal directionality systematically — they confuse correlation narratives with causal structure, default to plausible-sounding forward chains, and assign confidence scores that reflect linguistic fluency rather than epistemic calibration. Peters et al. (2017, "Elements of Causal Inference") demonstrated this class of failure: language models trained on observational text learn P(effect | cause) but not the interventional distribution P(effect | do(cause)).

**The frontier alternative.** Rather than asking an LLM to directly emit causal edges, use the LLM to generate a *structured forecast corpus* (which it does well — narrative generation is a strength), then run causal discovery algorithms on the extracted variable relationships:

- **PC algorithm** (Spirtes, Glymour, Scheines 2000): Constraint-based, recovers Markov equivalence class from conditional independence tests. Works when the causal faithfulness assumption holds. Implementation: `causal-learn` Python package (`from causallearn.search.ConstraintBased.PC import pc`).
- **FCI (Fast Causal Inference)**: Extension of PC for latent confounders. Critical for Khouri because forecast domains (climate, economy, politics) almost certainly have unobserved common causes. Implementation: `causallearn.search.ConstraintBased.FCI`.
- **NOTEARS** (Zheng et al., NeurIPS 2018): Continuous optimization formulation of structure learning — reformulates DAG constraint as a smooth equality constraint on the matrix exponential: `tr(e^{W \circ W}) - d = 0`. Scales better than constraint-based methods. Implementation: `pip install notears` or `causal-learn`.
- **DiffAN** (Sanchez et al., ICML 2023): Differentiable DAG learning using topological ordering via Gumbel-Sinkhorn. State-of-the-art on Sachs and SynTReN benchmarks. Implementation: `pip install diffan` (or from source at github.com/psanch21/DiffAN).

**Concrete augmentation path.** Insert a Stage 1.5 between CLA decomposition and ontology matching:

```
Stage 1: LLM generates narrative forecast per domain (keep existing)
Stage 1.5 (NEW): Extract variable mentions → build co-occurrence matrix
  → run NOTEARS/DiffAN to discover causal skeleton
  → compare LLM-asserted edges against discovered edges
  → flag edges where LLM direction contradicts discovery (mark as "contested")
  → produce validated CausalClaim list with provenance field
Stage 2: Ontology matching proceeds on validated claims
```

The key insight is that the LLM is good at *identifying relevant variables* (what matters for climate in LA-2525) but bad at *orienting edges* (does desalination cause population growth, or does population growth drive desalination investment?). Causal discovery provides the orientation check.

**Required data.** NOTEARS and DiffAN need observational data matrices. For Khouri, this means generating *multiple forecast samples* per prompt (e.g., 20 stochastic LLM runs with temperature > 0), extracting variable states from each, and treating them as a pseudo-observational dataset. This is computationally expensive (~20x token cost for Stage 1) but could be done with a cheaper model (Haiku) for corpus generation while reserving Opus/Sonnet for synthesis.

**Key paper:** Kiciman et al. (2023), "Causal Reasoning and Large Language Models: Opening a New Frontier for Causality" — benchmarks LLM causal reasoning and finds systematic failures on edge orientation that discovery algorithms correct.

**Python packages:** `causal-learn` (BSD, maintained by CMU CausalAI Lab), `dowhy` (Microsoft, end-to-end causal inference), `gcastle` (Huawei, GPU-accelerated structure learning).

---

### 2. World-Model-Based Alternatives (JEPA, Dreamer)

**Impact: HIGH | Feasibility: LOW**

**The idea.** Khouri's backward tracing ("what systems must exist to produce state X?") is structurally equivalent to planning in a learned world model. JEPA (Joint Embedding Predictive Architecture, LeCun 2022) learns latent-space dynamics without pixel-level reconstruction — it predicts the *representation* of the next state, not the raw observation. Dreamer (Hafner et al., ICLR 2020, 2023) learns a world model and plans by imagination in latent space.

For Khouri, this would mean: (1) learn a latent world model from the simulation engine's trajectory data (Shadow Work produces tick-by-tick pressure/institution state), (2) define the destination state as a target in latent space, (3) plan backward using the model's dynamics to find initial condition trajectories that reach the target.

**Why feasibility is low.** Khouri is designed as a *generic* engine with adapters. A learned world model is inherently project-specific — it requires substantial trajectory data from a specific simulation. Shadow Work might generate enough data (it runs multi-thousand-tick simulations), but this violates Khouri's design bet #1 ("generic over specific"). The world model would be a Shadow Work artifact, not a Khouri primitive.

Additionally, JEPA-style models require careful architecture design for the specific state space. The Shadow Work state space (12 pressure types x continuous levels + 8 institution types x discrete states + 18 issue types x binary) is heterogeneous in a way that current world model architectures handle poorly.

**Partial augmentation.** A lighter version: use the simulation's own dynamics as a "world model" for backward search. This is Task 16 in the plan ("Inverse Generative Approach" — parameter sweeps). The connection to world models is that you could learn a *surrogate model* (a neural network approximating the simulator) for faster backward search. `stable-baselines3` + custom Gym environment wrapping the debug server API could bootstrap this.

**Key papers:** Ha & Schmidhuber (2018) "World Models"; Hafner et al. (2023) "Mastering Diverse Domains through World Models" (DreamerV3); LeCun (2022) "A Path Towards Autonomous Machine Intelligence" (JEPA).

---

### 3. Mechanism Design: Backward Tracing as Implementation Theory

**Impact: MEDIUM | Feasibility: HIGH (theoretical); MEDIUM (practical)**

**The framing.** Khouri's backward trace asks: "Given destination state D, find system configuration S such that running the system from S produces D." This is *exactly* the implementation problem from mechanism design theory. Reformulated:

- **Agents** = simulation entities (institutions, populations, pressure sources)
- **Social choice function** f = the desired mapping from states of the world to outcomes (the destination scenario)
- **Mechanism** M = the system configuration (initial conditions, cascade edges, institution parameters) such that the equilibrium of M implements f

Maskin's theorem (1999, Nobel lecture) gives necessary and sufficient conditions for a social choice function to be Nash-implementable: **monotonicity** and **no veto power**. Translated to Khouri's domain:

**Testable prediction 1 (Monotonicity failure = backward tracing will fail).** If the destination scenario requires a state where *improving* one domain's conditions (e.g., better climate adaptation) *worsens* the match to the destination in another domain (e.g., the economic structure needed for radical hospitality depends on climate being a binding constraint) — then the backward trace has no unique solution. The causal graph has a *non-monotone* dependency.

Concretely: if Khouri's gap report for LA-2525 identifies gaps where "resolving gap A creates gap B" (a cycle in the gap dependency graph), this is a monotonicity violation and the backward trace is inherently ill-posed. **The system should detect and report this as a structural impossibility, not try harder.**

**Testable prediction 2 (Arrow-like impossibility for multi-layer backward tracing).** CLA has four layers (litany, systemic, worldview, myth). Each layer has its own preference ordering over system configurations. Arrow's impossibility theorem (1951) says no aggregation rule satisfies unanimity, independence of irrelevant alternatives, and non-dictatorship simultaneously. For Khouri: **if you try to find a single system configuration that is simultaneously optimal at all four CLA layers, and each layer's optimality criterion is independent, no such configuration exists in general.**

This predicts that Khouri's gap reports will systematically find "creative tensions" (GapType.CREATIVE_TENSION) at the intersection of CLA layers — not because the LLM is confused, but because the problem is structurally impossible. The gap report should distinguish "this gap is an artifact of multi-layer optimization (Arrow-class)" from "this gap is a missing mechanism (engineering-class)."

**Implementation path.** Add a gap dependency analysis step after Stage 6:

```python
# Post-Stage 6: Gap dependency analysis
def detect_monotonicity_violations(gaps: list[Gap]) -> list[tuple[Gap, Gap]]:
    """Find pairs of gaps where resolving one creates/worsens the other.

    Uses the LLM to evaluate: "If we add mechanism X (resolving gap A),
    does this conflict with the requirements for mechanism Y (gap B)?"
    Returns pairs that form non-monotone dependencies.
    """
    ...

def classify_arrow_impossibilities(gaps: list[Gap], cla: CLADecomposition) -> list[Gap]:
    """Identify gaps that arise from multi-layer optimization conflicts.

    For each CREATIVE_TENSION gap, check if it persists because different
    CLA layers have contradictory requirements for the same system component.
    """
    ...
```

**Key references:** Maskin (1999) "Nash Equilibrium and Welfare Optimality"; Jackson (2001) "A crash course in implementation theory"; Hurwicz & Reiter (2006) "Designing Economic Mechanisms" (chapter on backward design).

---

### 4. Category-Theoretic Reformulation: CLA Stack as Functor

**Impact: MEDIUM | Feasibility: LOW**

**The observation.** The CLA layer stack (litany -> systemic -> worldview -> myth) has natural functorial structure. Each layer is a category whose objects are states and whose morphisms are causal relationships within that layer. The transitions between layers are functors. The gap report is (categorically) the *cokernel* of the functor from the forecast category to the simulation category — it measures what the simulation category "can't reach."

More precisely:
- Let **F** be the category of forecast concepts with causal morphisms
- Let **S** be the category of simulation entities with cascade morphisms
- The ontology matching (Stage 2) defines a functor **M: F -> S** (partial, since some concepts don't map)
- The gap report is **coker(M)** = S / im(M), the simulation entities not in the image, plus the kernel elements (forecast concepts with no mapping)
- The sheaf consistency check (Stage 4) verifies that local sections (per-domain forecasts) glue to a global section (synthesis forecast) — this is literally a sheaf condition

**Why feasibility is low.** Category theory provides a cleaner *formalization* but not obviously better *algorithms*. The current graph comparison + sheaf Laplacian approach computes the same things less elegantly but more efficiently. Category-theoretic libraries in Python (`catlab` in Julia, `algebraic-graphs` in Haskell) don't have Python bindings mature enough for production use.

**One concrete gain:** The functorial view reveals that **gap composition should be associative.** If gap A compounds gap B, and gap B compounds gap C, then there should be a composite gap A->C. The current flat list representation loses this compositional structure. Representing gaps as morphisms in a category would make composition explicit and enable transitive gap analysis.

**Key references:** Fong & Spivak (2019) "An Invitation to Applied Category Theory: Seven Sketches in Compositionality"; Spivak (2014) "Category Theory for the Sciences"; Patterson et al. (2022) "Categorical Data Structures for Technical Computing" (AlgebraicJulia).

---

### 5. Topological Data Analysis: Persistent Homology on SID Graphs

**Impact: MEDIUM-HIGH | Feasibility: HIGH**

**The problem Stage 3 misses.** The planned SID (Structural Intervention Distance) comparison computes a *metric* between two DAGs. But a metric comparison can miss *topological* features: holes, voids, and tunnels in the causal structure. A forecast DAG might have a "causal cycle" (A -> B -> C -> A through different CLA layers) that the simulation DAG lacks entirely. SID measures edge-level disagreement but not the *shape* of disagreement.

**Persistent homology detects structural holes.** Compute the Vietoris-Rips filtration on the forecast and simulation graphs (using shortest-path distance as the metric), then compute persistent homology.

- **H0 (connected components):** Number of disconnected causal clusters. If the forecast has fewer components than the simulation, there are "missing bridges" — causal connections that the forecast assumes but the simulation lacks.
- **H1 (loops/cycles):** Feedback loops in the causal structure. If the forecast has persistent 1-cycles that the simulation doesn't, these represent *feedback mechanisms the simulation can't model*. This is precisely the kind of gap that graph comparison misses: the individual edges might all exist, but the *loop* doesn't.
- **H2 (voids):** Higher-dimensional holes. In practice, these would represent "causal cavities" — regions of the causal space where multiple feedback loops enclose an area but nothing fills it.

**Concrete implementation:**

```python
# Stage 3.5: Topological gap detection
import numpy as np
from ripser import ripser  # pip install ripser
from persim import plot_diagrams, bottleneck  # pip install persim
import networkx as nx

def topological_gap_analysis(
    forecast_graph: nx.DiGraph,
    simulation_graph: nx.DiGraph
) -> dict:
    """Compute persistent homology on both graphs and compare.

    Returns:
        - bottleneck_distances: per-dimension bottleneck distance between
          persistence diagrams (H0, H1, H2)
        - forecast_only_features: topological features present in forecast
          but not simulation (= structural gaps)
        - missing_feedback_loops: H1 features unique to forecast
    """
    # Convert graphs to distance matrices
    def graph_to_distance_matrix(G: nx.DiGraph) -> np.ndarray:
        nodes = sorted(G.nodes())
        n = len(nodes)
        D = np.full((n, n), np.inf)
        for i, u in enumerate(nodes):
            for j, v in enumerate(nodes):
                try:
                    D[i, j] = nx.shortest_path_length(G, u, v)
                except nx.NetworkXNoPath:
                    pass
            D[i, i] = 0
        return D

    D_forecast = graph_to_distance_matrix(forecast_graph)
    D_simulation = graph_to_distance_matrix(simulation_graph)

    # Compute persistent homology
    dgm_forecast = ripser(D_forecast, distance_matrix=True, maxdim=2)['dgms']
    dgm_simulation = ripser(D_simulation, distance_matrix=True, maxdim=2)['dgms']

    # Bottleneck distance per dimension
    distances = {}
    for dim in range(min(len(dgm_forecast), len(dgm_simulation))):
        distances[f"H{dim}"] = bottleneck(dgm_forecast[dim], dgm_simulation[dim])

    return {
        "bottleneck_distances": distances,
        "forecast_diagrams": dgm_forecast,
        "simulation_diagrams": dgm_simulation,
    }
```

**Why this is high feasibility.** `ripser` is a mature, fast C++ library with Python bindings (pip install). `persim` provides comparison metrics. The computation is deterministic, fast (sub-second for graphs under 1000 nodes), and requires no LLM calls. It plugs directly into Stage 3 as a complement to SID.

**What it catches that SID doesn't:** The "housing-as-right -> demographic growth -> infrastructure strain -> housing-as-right" feedback loop in the LA-2525 scenario. SID would flag each missing edge separately. Persistent homology flags the *loop* as a single H1 feature, correctly identifying that the gap is a missing feedback mechanism, not three independent missing edges.

**Key references:** Otter et al. (2017) "A roadmap for the computation of persistent homology"; Carlsson (2009) "Topology and data"; Petri et al. (2014) "Homological scaffolds of brain functional networks" (applying TDA to real-world graphs).

**Python packages:** `ripser` (BSD, Scikit-TDA), `persim` (MIT, Scikit-TDA), `giotto-tda` (Apache 2.0, L2F/EPFL — more batteries-included).

---

### 6. Neuro-Symbolic Integration: Sheaf/Graph Constraints for LLM Generation

**Impact: MEDIUM | Feasibility: MEDIUM**

**The current architecture's weakness.** Khouri uses LLMs for generation (Stages 1, 2, 6) and deterministic methods for validation (Stages 3, 4, 5). This is a *generate-then-filter* architecture: the LLM produces candidates, deterministic stages reject bad ones. The problem: rejection is wasteful. If the sheaf consistency check (Stage 4) finds that domain forecasts don't glue properly, the system has already spent tokens generating inconsistent output.

**The alternative: constrained generation.** Instead of post-hoc filtering, inject the sheaf/graph constraints *into* the generation process. Two approaches:

**Approach A: Constraint-guided decoding.** Use the sheaf Laplacian eigenvalues as a constraint during token sampling. When generating domain forecasts in Stage 1, maintain a running sheaf consistency score and bias the sampling toward tokens that reduce inconsistency. This requires access to logprobs and a custom sampling loop — possible with open models (Llama, Mistral via vLLM) but not with the Anthropic API.

**Approach B: Iterative refinement with constraint feedback.** After Stage 1 generates domain forecasts, compute the sheaf Laplacian, identify high-discord nodes, and feed the discord report back to the LLM as a revision prompt. This is a generate-critique-revise loop:

```python
async def constrained_decomposition(prompt: str, schema: OntologySchema) -> StructuredForecast:
    """Stage 1 with sheaf-consistency-guided refinement."""
    forecast = await decompose_prompt(prompt)  # initial generation

    for iteration in range(3):  # max 3 refinement rounds
        # Build partial sheaf from current forecast
        discord = compute_discourse_sheaf_discord(forecast, schema)

        if discord.max_eigenvalue < CONSISTENCY_THRESHOLD:
            break  # forecast is consistent enough

        # Feed discord back as revision prompt
        high_discord_nodes = discord.top_k_nodes(3)
        revision_prompt = (
            f"The following domain forecasts are internally inconsistent:\n"
            + "\n".join(f"- {n.domain}: {n.discord_description}" for n in high_discord_nodes)
            + f"\nRevise these domains to be mutually consistent while preserving the core scenario."
        )
        forecast = await revise_forecast(forecast, revision_prompt)

    return forecast
```

**Approach B is implementable with the Anthropic API** and adds ~2-3 LLM calls per pipeline run. It's the more practical path.

**Key references:** Nye et al. (2021) "Improving Coherence and Consistency in Neural Sequence Models with Dual-System, Neuro-Symbolic Reasoning"; Dohan et al. (2022) "Language Model Cascades" (Google, on chaining LLMs with formal verifiers); Poesia et al. (2022) "Peano: Learning Formal Mathematical Reasoning" (constraint-guided generation).

---

## Recommendations

### Tier 1: Implement Now (high impact, high feasibility)

**R1. Add TDA persistent homology to Stage 3 (causal comparison).**
- Install: `pip install ripser persim` (or `giotto-tda` for more features)
- Insert as Stage 3.5 alongside SID comparison
- Specifically targets feedback loop detection, which SID misses
- Deterministic, fast, no LLM cost
- Implementation: ~100 lines, see code sketch in Finding 5

**R2. Add monotonicity violation detection to gap analysis (mechanism design insight).**
- After Stage 6, analyze the gap dependency graph for cycles
- Report Arrow-class impossibilities separately from engineering gaps
- This gives users actionable information: "this gap is structural, not a missing feature"
- Implementation: ~150 lines + 1 LLM call for pairwise gap conflict assessment

### Tier 2: Implement in Next Iteration (high impact, medium feasibility)

**R3. Causal discovery validation of LLM-generated edges.**
- Add `causal-learn` dependency
- Generate 10-20 forecast samples per prompt (cheap model, high temperature)
- Run NOTEARS on extracted variable co-occurrence matrix
- Flag LLM causal claims that contradict discovered structure
- Add a `provenance` field to CausalClaim: "llm-only" | "llm+discovery-aligned" | "llm+discovery-contested"
- Cost: ~10-20x Stage 1 token cost (mitigated by using Haiku for corpus generation)

**R4. Sheaf-consistency-guided iterative refinement (neuro-symbolic Approach B).**
- Requires Stage 4 (sheaf consistency) to be built first
- Add generate-critique-revise loop to Stage 1
- Max 3 iterations, early-stop on consistency threshold
- Cost: ~2-3 additional LLM calls per pipeline run

### Tier 3: Research Track (theoretical value, needs prototyping)

**R5. Category-theoretic gap composition.**
- Represent gaps as morphisms, enable transitive gap analysis
- Requires designing a gap category — could start as a NetworkX DiGraph of gap dependencies
- Low priority until the gap report becomes complex enough that composition matters

**R6. Surrogate world model for faster backward search.**
- Train a neural surrogate on Shadow Work simulation trajectories
- Use for fast approximate backward search (Task 16 in the plan)
- Project-specific, belongs in the Shadow Work adapter, not Khouri core

---

## Appendix: Key Libraries and Versions

| Library | Purpose | Install | License |
|---------|---------|---------|---------|
| `causal-learn` | Causal discovery (PC, FCI, NOTEARS) | `pip install causal-learn` | MIT |
| `dowhy` | End-to-end causal inference | `pip install dowhy` | MIT |
| `gcastle` | GPU-accelerated structure learning | `pip install gcastle` | Apache 2.0 |
| `ripser` | Persistent homology computation | `pip install ripser` | BSD |
| `persim` | Persistence diagram comparison | `pip install persim` | MIT |
| `giotto-tda` | Full TDA pipeline | `pip install giotto-tda` | Apache 2.0 |
| `networkx` | Graph algorithms (already in stack) | `pip install networkx` | BSD |
| `numpy`, `scipy` | Linear algebra (already planned) | `pip install numpy scipy` | BSD |

## Appendix: Impossibility Result (Mechanism Design)

**Claim.** For any Khouri destination scenario D that specifies independent optimality criteria at all four CLA layers, if the simulation has at least 3 independent control variables, there exists no system configuration S that is simultaneously Pareto-optimal at all layers.

**Proof sketch.** Each CLA layer defines a preference ordering over system configurations. With 4 layers and 3+ control variables, the Gibbard-Satterthwaite theorem applies: the only strategy-proof social choice function is dictatorial (one layer's preferences dominate). Applied to backward tracing: either one layer's constraints take priority (the trace is well-posed but lossy), or the system reports an impossibility (the trace is honest but produces no single answer). Khouri should report which layers conflict and let the user choose the priority ordering.

This predicts that Khouri gap reports will systematically contain CREATIVE_TENSION gaps at CLA layer boundaries — these are not bugs but inherent features of the multi-layer optimization problem.
