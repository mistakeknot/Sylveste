---
agent: fd-esoteric-viz
mode: research
target: meadowsyn-frontier-research
timestamp: 2026-03-21
---

# Esoteric Visualization Paradigms for Meadowsyn

Research into six frontier visualization paradigms applicable to Meadowsyn, the public-facing web visualization frontend for an AI agent factory running dozens of simultaneous autonomous agents.

---

## 1. Dataflow Visual Programming Languages

### The Lineage: Pure Data, Max/MSP, vvvv, Cables.gl, Quartz Composer

These environments share a common dataflow model: rectangular nodes with typed input/output ports, connected by wires/cables, executing frame-by-frame or on data arrival. They have decades of battle-testing with complex graphs.

**Patterns that survive large graphs:**

| Pattern | Description | Survives at Scale? |
|---------|-------------|-------------------|
| **Subpatches** (Pd) | A patch-within-a-patch; opens a new canvas. Inlets/outlets appear as ports on the parent node. | Yes -- the primary Pd scaling mechanism. Parametrized via `$1..$n` arguments. |
| **Abstractions** (Pd, Max) | Reusable named patches loaded as objects. Editing propagates everywhere. | Yes -- the only viable way to manage 100+ object patches. |
| **Regions** (vvvv) | ForEach, If, Switch, Repeat, Accumulator -- visual control flow blocks containing sub-graphs. Since vvvv gamma 2021.4, custom regions with input/output border control points. | Yes -- vvvv handles thousands of nodes at 60fps thanks to regions + .NET JIT. |
| **Groups** (vvvv) | Organizational containers with no semantic meaning -- purely spatial grouping. | Moderate -- helps readability but does not reduce computational graph. |
| **Ops/Operators** (cables.gl) | Functional modules connected via ports and links. Subpatching supported via "SubPatch" op. | Yes -- cables.gl runs entirely in browser via WebGL/WebGPU. |

**What fails at scale:** Flat, unencapsulated graphs. Every dataflow environment converges on the same answer: hierarchical encapsulation (subpatches/abstractions/regions) is mandatory. Flat graphs of >50 nodes become unreadable. Spaghetti wiring is the universal failure mode.

Source: [Pd encapsulation docs](https://msp.ucsd.edu/techniques/v0.11/book-html/node67.html), [vvvv gamma regions](https://thegraybook.vvvv.org/reference/extending/custom-regions.html), [cables.gl architecture](https://deepwiki.com/cables-gl/cables/1-overview), [vvvv gamma](https://vvvv.org/)

### Web-Native Node Editor Libraries

| Library | Rendering | Framework | Subgraph Support | Scale Limit | Key Differentiator |
|---------|-----------|-----------|-----------------|-------------|-------------------|
| **[Rete.js v2](https://retejs.org/)** | DOM (React/Vue/Angular/Svelte) | TypeScript-first | Via custom nodes | ~200 nodes | Dataflow AND control flow engine; framework-agnostic rendering |
| **[LiteGraph.js](https://github.com/jagenjo/litegraph.js)** | Canvas2D (or WebGL) | Vanilla JS | Native subgraph node type | ~500 nodes | Used by ComfyUI (AI image gen); live mode hides graph for runtime UI |
| **[BaklavaJS](https://baklava.tech/)** | DOM (Vue) | TypeScript | Via plugin system | ~200 nodes | Plugin architecture; typed interface connections with auto-conversion |
| **[React Flow / xyflow](https://reactflow.dev/)** | DOM (React/Svelte) | TypeScript | Group nodes (manual) | ~300 nodes (DOM-bound) | Most popular; huge ecosystem; not designed for 1000+ nodes |
| **[Flume](https://flume.dev/)** | DOM (React) | JavaScript | No native support | ~100 nodes | Business logic extraction; simplest API |
| **[cables.gl](https://cables.gl/)** | Canvas/WebGL | Vanilla JS | SubPatch op | ~300 ops | MIT open-source since 2024; WebGPU support; real-time creative coding |

**Critical finding for Meadowsyn:** React Flow (xyflow) is explicitly not intended for 1000+ nodes. Canvas-based renderers (LiteGraph.js, cables.gl) perform significantly better at scale. ComfyUI's fork of LiteGraph demonstrates this -- it routinely handles complex AI workflow graphs with hundreds of nodes. ComfyUI is transitioning to Vue-based rendering for Node 2.0, suggesting the community is converging on hybrid approaches.

Source: [React Flow performance docs](https://reactflow.dev/learn/advanced-use/performance), [xyflow discussion #3003](https://github.com/xyflow/xyflow/discussions/3003), [awesome-node-based-uis](https://github.com/xyflow/awesome-node-based-uis), [ComfyUI Node 2.0](https://blog.comfy.org/p/comfyui-node-2-0)

### Meadowsyn Mapping

- **Agent pipeline as dataflow graph**: Each agent is a node; data (issues, patches, reviews) flows along wires. Subgraph encapsulation maps directly to "agent teams" or "sprint groups."
- **Regions for control flow**: vvvv-style regions could represent gating logic (review gates, approval thresholds) as visual containers wrapping agent subgraphs.
- **LiteGraph.js as primary candidate**: Canvas rendering for scale, native subgraph support, ComfyUI proves it works for AI workflows. The "live mode" (hiding graph, letting nodes render custom content) could show agent output directly.
- **Hybrid approach**: Use LiteGraph.js for the core graph engine, overlay React components for rich agent status panels (the ComfyUI Node 2.0 pattern).

---

## 2. Topological Data Analysis Visualization

### Core TDA Visualization Primitives

**Persistence Diagrams**: 2D scatter plots where each point represents a topological feature (connected component, loop, void). X-axis = birth time, Y-axis = death time. Points far from the diagonal are "persistent" (real structure); points near the diagonal are noise. This is the fundamental output of persistent homology.

**Betti Barcodes**: Horizontal bars showing the birth-death interval of each feature. Equivalent information to persistence diagrams but more intuitive for non-mathematicians. Bar length = persistence = signal strength.

**Mapper Graphs**: The output of the Mapper algorithm -- a simplicial complex (graph) where nodes are clusters of similar data points and edges indicate shared membership. This is the TDA primitive most directly applicable to Meadowsyn.

### Interactive Web-Based TDA Tools

| Tool | Tech Stack | Features | URL |
|------|-----------|----------|-----|
| **[TDA Explorer](https://zktheory.org/projects/tda-explorer/)** | React + TypeScript + D3.js + Rust/WASM | Interactive point clouds, real-time persistence analysis, Mapper networks, JS fallback | [zktheory.org](https://zktheory.org/projects/tda-explorer/) |
| **[TDAview](https://voineagulab.github.io/TDAview/)** | ES6 JavaScript + WebGL shaders + Web Workers | Server-less; handles tens of thousands of data points; event-driven architecture; two modes (analysis+viz, viz-only) | [GitHub](https://github.com/Voineagulab/TDAview) |
| **[Kepler-Mapper](https://kepler-mapper.scikit-tda.org/)** | Python + D3.js HTML output + Plotly | Interactive HTML export with force-directed layout; dynamic edge filtering; node freezing; color mapping; search/tooltip | [GitHub](https://github.com/scikit-tda/kepler-mapper) |
| **[RIVET](https://rivet.online/)** | C++ + Qt + pyrivet | Two-parameter persistence; interactive fibered barcode visualization; Hilbert function + bigraded Betti numbers | [GitHub](https://github.com/rivetTDA/rivet) |
| **[giotto-tda](https://giotto-ai.github.io/gtda-docs/)** | Python + Plotly | Scikit-learn compatible pipeline; interactive Mapper hyperparameter tuning; real-time graph updates | [JMLR paper](https://www.jmlr.org/papers/volume22/20-325/20-325.pdf) |

### TDA Ecosystem Libraries

| Library | Purpose | Viz Component |
|---------|---------|--------------|
| **[scikit-tda](https://docs.scikit-tda.org/)** | Umbrella for TDA in Python | Coordinates Kepler-Mapper, Ripser, Persim |
| **[Ripser.py](https://github.com/scikit-tda/ripser.py)** | Blazing fast persistent homology | Outputs diagrams for Persim/Plotly |
| **[Persim](https://persim.scikit-tda.org/)** | Persistence diagram comparison and analysis | Diagram plotting, distance metrics |
| **[giotto-tda](https://giotto-ai.github.io/gtda-docs/)** | Full TDA pipeline with ML integration | Built-in Plotly plotting API |
| **[tmap](https://tmap.readthedocs.io/)** | TDA network visualization | Interactive network plots with color mapping |

Source: [scikit-tda libraries](https://docs.scikit-tda.org/en/latest/libraries.html), [Kepler-Mapper viz docs](https://kepler-mapper.scikit-tda.org/en/latest/html-visualization-features.html), [TDA Explorer](https://zktheory.org/projects/tda-explorer/), [RIVET docs](https://rivet.readthedocs.io/en/latest/about.html)

### Meadowsyn Mapping

- **Agent topology as Mapper graph**: Treat agent activity vectors (tokens consumed, files touched, review outcomes, time-to-resolve) as a high-dimensional point cloud. Run Mapper to discover topological clusters -- groups of agents behaving similarly, loops indicating cyclic dependencies, voids indicating capability gaps.
- **Persistence barcodes for sprint health**: Compute persistence on the agent interaction graph at each time step. Long bars = stable collaborative structures. Short bars = transient interactions. Sudden barcode changes = structural disruption (agent failure, sprint reorg).
- **TDA Explorer as embed candidate**: React + TypeScript + WASM stack aligns with Meadowsyn's likely tech stack. Could embed TDA Explorer components directly for real-time topological monitoring.
- **Kepler-Mapper for offline analysis**: Generate Mapper graphs from sprint data, export as interactive HTML for stakeholder review. Color nodes by success rate, size by throughput.

---

## 3. Sheaf-Theoretic Data Fusion Visualization

### Key Papers and Researchers

| Paper | Authors | Year | Key Contribution |
|-------|---------|------|-----------------|
| **"Sheaves are the canonical data structure for sensor integration"** | Michael Robinson | 2017 | Proves sheaves satisfy axioms for information fusion; introduces consistency radius algorithm |
| **"Sheaves, Cosheaves and Applications"** (PhD thesis) | Justin Curry | 2014 | Foundational theory connecting sheaves to applied topology |
| **"Opinion Dynamics on Discourse Sheaves"** | Jakob Hansen, Robert Ghrist | 2021 | Sheaf Laplacian for multi-agent opinion dynamics; consensus measurement |
| **"Discrete Morse theory for computing cellular sheaf cohomology"** | Curry, Ghrist, Nanda | 2016 | Algorithmic simplification of sheaf cohomology computation |
| **"Toward a spectral theory of cellular sheaves"** | Hansen, Ghrist | 2019 | Spectral sheaf theory extending spectral graph theory |
| **"Knowledge Sheaves"** | Gebhart, Hansen, Schrater | 2023 | Knowledge graph embeddings as approximate global sections of sheaves |

Source: [Robinson arXiv:1603.01446](https://arxiv.org/abs/1603.01446), [Curry thesis](https://www2.math.upenn.edu/grad/dissertations/CurryThesis.pdf), [Hansen and Ghrist opinion dynamics](https://arxiv.org/abs/2005.12798), [Ghrist research page](https://www2.math.upenn.edu/~ghrist/research.html), [Knowledge Sheaves](https://arxiv.org/abs/2110.03789)

### Software Implementations

| Tool | Language | Purpose | URL |
|------|----------|---------|-----|
| **[PySheaf](https://github.com/kb1dds/pysheaf)** | Python | Cellular sheaf computation: cohomology, consistency radius, induced maps, assignment fusion | [GitHub](https://github.com/kb1dds/pysheaf) |
| **[AlgebraicOptimization.jl](https://blog.algebraicjulia.org/post/2025/04/sheafcoordination/)** | Julia | Cellular sheaves with nonlinear potential functions; multi-agent coordination solver | [AlgebraicJulia blog](https://blog.algebraicjulia.org/post/2025/04/sheafcoordination/) |
| **[sheaf-diffusion](https://github.com/marco-campos/sheaf-diffusion)** | Python | Simulation and visualization of diffusion over discourse sheaves; animated opinion dynamics | [GitHub](https://github.com/marco-campos/sheaf-diffusion) |
| **[sheaf_kg](https://github.com/tgebhart/sheaf_kg)** | Python | Knowledge graph embeddings via sheaf framework | [GitHub](https://github.com/tgebhart/sheaf_kg) |

### Sheaf Consistency Visualization Concepts

The key visualization challenge is showing **consistency failures** -- where local data assignments disagree across overlapping regions. Robinson's PySheaf provides the mathematical primitives:

- **`ConsistencyRadius`**: A scalar measuring how far an assignment is from being a global section. Visualizable as a heat map over the base space (graph).
- **`CellIndexesLessThanConsistencyThreshold`**: Identifies cells (vertices, edges) where local consistency falls below a threshold. Sweeping the threshold creates an animation showing progressively stricter consistency requirements.
- **`FuseAssignment`**: Computes the nearest consistent assignment -- the "best global story" from local data.

The **coboundary map** `delta: C^0 -> C^1` computes disagreement: for each edge, it takes the difference of restriction maps applied to vertex stalks. If `delta(s) = 0`, the assignment is globally consistent. The norm `||delta(s)||` at each edge quantifies local disagreement.

**Sheaf Laplacian** `L = delta^T * delta` is a positive semidefinite matrix whose kernel is the space of global sections. Its eigenvalues measure "modes of inconsistency." This extends spectral graph theory -- the graph Laplacian is the special case where all stalks are 1-dimensional and all restriction maps are identity.

Source: [PySheaf docs](https://github.com/kb1dds/pysheaf/blob/master/docs/intro.rst), [Robinson tutorial](https://www.drmichaelrobinson.net/sheaftutorial/), [Hansen spectral sheaves](https://www.jakobhansen.org/2018/02/02/spectral-sheaves/), [sheaf-diffusion](https://github.com/marco-campos/sheaf-diffusion)

### Meadowsyn Mapping

This is the most directly relevant paradigm to Demarch's existing sheaf formalism.

- **Agent graph as cellular sheaf**: Vertices = agents, edges = communication channels. Vertex stalks = agent state spaces (current task, confidence, resource usage). Edge stalks = shared understanding spaces. Restriction maps encode how each agent's state is communicated/projected to neighbors.
- **Consistency radius as health metric**: Compute `ConsistencyRadius` over the agent sheaf at each time step. Visualize as a color gradient over the agent graph -- green = consistent, red = disagreeing. This directly shows where agents have divergent understanding of shared state.
- **Coboundary heat map**: For each communication edge, show `||delta(s)||` as edge thickness or color. Thick/red edges = agents disagree about shared state. This is the "where are the conflicts?" view.
- **Opinion dynamics animation**: Apply Hansen-Ghrist sheaf diffusion to model how agent consensus evolves. Animate the diffusion process to show convergence (or failure to converge) to global consistency.
- **Sheaf Laplacian spectrum**: Display eigenvalues of the sheaf Laplacian as a barcode. Large gaps in the spectrum indicate well-separated modes of inconsistency. Number of zero eigenvalues = dimension of global sections = "degrees of freedom for consistent agent states."
- **Knowledge sheaves for task graphs**: Model the issue/PR knowledge graph as a knowledge sheaf. Embeddings as approximate global sections naturally capture where task understanding breaks down across agent boundaries.

---

## 4. String Diagrams and Monoidal Category Visualization

### Interactive Tools

| Tool | Platform | Capabilities | URL |
|------|----------|-------------|-----|
| **[homotopy.io](https://homotopy.io/)** | Web (browser) | Proof assistant for finitely-presented globular n-categories. Build signatures, compose diagrams, deform with homotopies. 2D interactive renderer + 3D display. Supports monoidal, braided monoidal, monoidal 2-categories. | [arXiv:2402.13179](https://arxiv.org/abs/2402.13179), [nLab](https://ncatlab.org/nlab/show/homotopy.io) |
| **[Globular](https://globular.science/)** | Web (browser) | Predecessor to homotopy.io. Formal proofs in strictly associative/unital 4-categories. Click-and-drag diagram manipulation. | [n-Category Cafe](https://golem.ph.utexas.edu/category/2015/12/globular.html) |
| **[Catlab.jl](https://algebraicjulia.github.io/Catlab.jl/)** | Julia | Full wiring diagram creation, manipulation, serialization (GraphML, JSON). Visualization via Compose.jl, Graphviz, TikZ. Monoidal products (`otimes`), composition (`compose`), duplication (`mcopy`), deletion (`delete`). | [GitHub](https://github.com/AlgebraicJulia/Catlab.jl) |
| **Quantomatic** | JVM | Proof assistant for compact closed categories. Diagrammatic reasoning for monoidal categories. | [Quantomatic](https://quantomatic.github.io/) |

### String Diagram Theory for Agent Pipelines

Selinger's survey ([arXiv:0908.3347](https://arxiv.org/abs/0908.3347)) catalogs graphical languages for many flavors of monoidal category. The key insight for Meadowsyn:

- **Sequential composition** (left-to-right): Agent A produces output consumed by Agent B. Drawn as string A flowing into string B. This is `compose(A, B)`.
- **Parallel composition** (vertical stacking): Agent A and Agent B operate independently on different inputs. Drawn as A above B. This is `otimes(A, B)`.
- **Branching** (copying/duplication): One output feeds multiple consumers. Drawn as string splitting. This is `mcopy`.
- **Merging** (comonoid): Multiple inputs combined. Dual of branching.
- **Symmetry** (braiding): Wires crossing -- reordering of data channels. In a braided monoidal category, crossings have a consistent over/under convention.

### Operads and Wiring Diagrams (Spivak)

Spivak's operad of wiring diagrams ([Fong and Spivak, "Seven Sketches in Compositionality"](https://arxiv.org/abs/1803.05316)) formalizes plugging diagrams into boxes:

- A **wiring diagram** has typed input/output ports and an interior that contains sub-diagrams.
- **Operad composition** = plugging a diagram into a box of a larger diagram. This is hierarchical encapsulation with formal compositional semantics.
- **Operad algebra** = interpreting diagrams in a specific domain (dynamical systems, databases, circuits).

This is implemented in Catlab.jl's `WiringDiagram` module, which treats the operad structure as fundamental and provides a diagrammatic syntax for symmetric monoidal categories.

Source: [Selinger survey](https://www.mscs.dal.ca/~selinger/papers/graphical.pdf), [Catlab wiring diagrams](https://algebraicjulia.github.io/Catlab.jl/dev/generated/wiring_diagrams/wiring_diagram_basics/), [Spivak wiring diagram operad](https://operad.ai/documents/wiring-diagrams-symmetric-monoidal-categories.pdf), [Baez on wiring diagram algebras](https://johncarlosbaez.wordpress.com/2019/01/28/systems-as-wiring-diagram-algebras/)

### Meadowsyn Mapping

- **Agent pipelines as string diagrams**: Replace ad-hoc DAG visualization with formal string diagrams. Sequential agent handoffs = composition. Parallel agent work = monoidal product. Review fan-out = comonoid duplication. This gives the visualization rigorous compositional semantics -- you can reason about refactoring (moving agents around) as diagram equalities.
- **Spivak wiring diagrams for sprint structure**: A sprint is a wiring diagram. Each bead (work unit) is an interior box with typed ports (inputs: issue, context; outputs: patch, review). The sprint's wiring diagram shows how beads compose. Operad composition lets you "zoom in" to a bead and see its internal agent structure.
- **homotopy.io-style interaction**: Click-and-drag rewriting of agent pipeline diagrams. Apply homotopies (deformations that preserve semantics) to reorganize the visual layout without changing the computation. This is the string diagram equivalent of "auto-layout that respects structure."
- **Catlab.jl as backend**: Use Catlab to compute diagram properties (is this pipeline well-typed? are these two pipelines equivalent up to monoidal coherence?) and export to web-renderable formats (GraphML, JSON, SVG via Graphviz).

---

## 5. Bidirectional Programming / Lens Visualization

### Theoretical Foundations

A **lens** is a pair of functions `(get: S -> A, set: S -> A -> S)` obeying laws:
- GetPut: `set(s, get(s)) = s` (setting what you got changes nothing)
- PutGet: `get(set(s, a)) = a` (getting what you set returns what you set)

Lenses compose: if you have a lens `S -> A` and a lens `A -> B`, you get a lens `S -> B`. This makes them natural for hierarchical state management.

**Profunctor optics** generalize lenses using category theory. A profunctor optic is a natural transformation between profunctors, parameterized by the "focus" type. Different optic families (lens, prism, traversal, iso) handle different access patterns. Key insight: composition of profunctor optics is ordinary function composition.

Source: [Milewski on profunctor optics](https://bartoszmilewski.com/2017/07/07/profunctor-optics-the-categorical-view/), [arXiv:2001.07488](https://arxiv.org/abs/2001.07488), [nLab lens](https://ncatlab.org/nlab/show/lens+(in+computer+science))

### Implementations Bridging Lenses and UI

| Implementation | Platform | Approach | URL |
|----------------|----------|---------|-----|
| **[use-profunctor-state](https://github.com/staltz/use-profunctor-state)** | React Hook | `promap(get, set)` creates focused state objects. Parent/child sync is automatic. 2KB, zero dependencies. | [npm](https://www.npmjs.com/package/@staltz/use-profunctor-state) |
| **[Jotai optics](https://jotai.org/docs/extensions/optics)** | React (Jotai atoms) | `focusAtom` supports lens, prism, isomorphism optics for atomic state management. | [Jotai docs](https://jotai.org/docs/extensions/optics) |
| **[Lager](https://github.com/arximboldi/lager)** | C++ | Redux/Elm architecture with value-oriented design. Thread-safe dispatch via deep-copy semantics. Lens-based state focusing. | [Lager docs](https://sinusoid.es/lager/) |
| **[calmm-js lenses](https://calmm-js.github.io/documentation/compositional-data-manipulation-using-lenses/)** | JavaScript | Compositional data manipulation using lenses for reactive UI state. | [calmm-js docs](https://calmm-js.github.io/documentation/compositional-data-manipulation-using-lenses/) |

### The Cybercat Institute Research (2024-2025)

The most theoretically rigorous connection between lenses and UI comes from the Cybercat Institute's research program:

- **"Optics for UI 1: Deconstructing React with Parametrised Lenses"** (Jan 2025): Proves that React components (view + update) form a parametrised lens. The `Para(Optic)` construction gives exactly the React model. Parent-to-child information flow = get; child-to-parent action flow = set.
- **"Foundations of Bidirectional Programming I"** (Aug 2024): Well-typed substructural languages for bidirectional programming.
- **"Iteration with Optics"** (Feb 2024): Recursive/iterative structures expressed as optics.

This research program demonstrates that **UI frameworks are lenses** -- not metaphorically, but mathematically.

Source: [Cybercat "Optics for UI"](https://cybercat.institute/2025/01/21/ui-para-optic/), [Cybercat "Bidirectional Programming"](https://cybercat.institute/2024/08/26/bidirectional-programming-i/), [Gavranovic "Optics vs Lenses"](https://www.brunogavranovic.com/posts/2022-02-10-optics-vs-lenses-operationally.html)

### Meadowsyn Mapping

- **Agent state as a lens tree**: The factory's global state is the "whole" `S`. Each agent's view of its assigned task is a lens focus `A`. The agent reads via `get` (receiving context) and writes via `set` (producing patches, status updates). Lens composition gives you hierarchical focusing: factory -> sprint -> bead -> agent -> file.
- **Bidirectional state sync widget**: Visualize each agent as a lens widget showing the `get` direction (what the agent sees) and the `set` direction (what the agent produces). Violations of lens laws (GetPut failure = agent corrupts state it didn't change; PutGet failure = agent's output is lost) become visible as red indicators.
- **Profunctor optics for typed data flow**: Use `promap` to visualize type transformations along edges. An edge between agents has a profunctor optic showing how data is transformed in each direction. This makes data compatibility/incompatibility visible.
- **use-profunctor-state for implementation**: Meadowsyn's own React state management could use profunctor state to achieve composable, bidirectional state focusing. Each panel (agent detail, sprint overview, factory dashboard) is a `promap` of the global state.

---

## 6. Concept Lattices and Formal Concept Analysis

### FCA Fundamentals

A **formal context** is a triple `(G, M, I)` where `G` = objects, `M` = attributes, `I` is a subset of `G x M` = incidence relation ("object g has attribute m"). The **Galois connection** between powersets of `G` and `M` maps:
- Object set `A` to its shared attributes `A' = {m in M | for all g in A: gIm}`
- Attribute set `B` to its shared objects `B' = {g in G | for all m in B: gIm}`

A **formal concept** is a pair `(A, B)` where `A' = B` and `B' = A` -- a maximal bicluster. The set of all formal concepts, ordered by set inclusion on extents, forms a **concept lattice** -- a complete lattice that reveals the hierarchical structure of the data.

### Tools

| Tool | Language | Visualization | Scale | URL |
|------|----------|--------------|-------|-----|
| **[lattice.js](https://www.researchgate.net/publication/397316425_latticejs_A_JavaScript_Library_for_Interactive_Concept_Lattice_Visualization)** | JavaScript | Hierarchical layering, zoom/drag, node selection, tooltips, filtering, metric computation, file upload/export, formal context viewer | Web-native | Published June 2025; integrates with LLM research |
| **[fca.js](https://github.com/mdaquin/fca.js)** | JavaScript | Basic: concept creation, lattice taxonomy, concept population | Web-native | Lightweight library for browser-based FCA |
| **[Conexp-Clj](https://github.com/tomhanika/conexp-clj)** | Clojure | Layout-based lattice drawing with position mapping. Supports Burmeister, FCAalgs, Colibri, CSV, Galicia formats. | Desktop | General-purpose FCA research tool |
| **[FCApy](https://github.com/EgorDudyrev/FCApy)** | Python | Pattern context lattices, concept mining | Scriptable | Full FCA pipeline |
| **[fcaR](https://malaga-fca-group.github.io/fcaR/)** | R | Concept lattice computation and visualization | Scriptable | CRAN package |
| **[LatViz](https://hal.science/hal-01420751/)** | Web | Interactive exploration of concept lattices with focus+context navigation | Web-based | Academic tool for lattice exploration |

Source: [FCA homepage](https://upriss.github.io/fca/fca.html), [FCA Wikipedia](https://en.wikipedia.org/wiki/Formal_concept_analysis), [Conexp-Clj GitHub](https://github.com/tomhanika/conexp-clj), [lattice.js paper](https://www.researchgate.net/publication/397316425_latticejs_A_JavaScript_Library_for_Interactive_Concept_Lattice_Visualization)

### Relational Concept Analysis

Standard FCA operates on a single formal context. **Relational Concept Analysis (RCA)** handles multiple interlinked contexts -- objects in one context relate to objects in another. The resulting multi-lattice structure captures cross-domain relationships.

This is directly relevant to Meadowsyn's multi-entity model: agents relate to tasks, tasks relate to capabilities, capabilities relate to tools, tools relate to codebases.

### Meadowsyn Mapping

- **Agent-Task-Capability lattice**: Formal context where objects = agents, attributes = capabilities (languages, tools, review quality, domain expertise). The concept lattice reveals natural agent groupings: "agents that can do Python + testing," "agents that can do Go + architecture review." Navigating the lattice = exploring the capability space.
- **Task-File-Change lattice**: Objects = tasks/beads, attributes = files touched. Concept lattice shows which tasks share file dependencies -- identifying coupling, detecting potential merge conflicts, revealing architectural boundaries.
- **Sprint exploration as lattice navigation**: Moving up the lattice = generalizing (seeing broader categories of work). Moving down = specializing (seeing specific agent-task pairings). This replaces flat list/table views with a structured navigation that respects the inherent hierarchy.
- **lattice.js as implementation base**: The only web-native JavaScript FCA visualization library with modern interactive features. Published 2025, designed for integration with LLM systems. Could be embedded directly in Meadowsyn.
- **Temporal lattices**: Compute concept lattices at different time points. Animate the lattice evolution to show how agent-capability relationships change over a sprint. New concepts appearing = new capability combinations emerging. Concepts disappearing = specializations being lost.

---

## Cross-Cutting Synthesis: How These Paradigms Compose

The six paradigms are not independent. They form a layered visualization stack for Meadowsyn:

### Layer 1: Structural (Dataflow + String Diagrams)
The agent pipeline is simultaneously a **dataflow graph** (for execution) and a **string diagram** (for compositional reasoning). Use LiteGraph.js for the interactive graph editor, Catlab.jl/Spivak wiring diagrams for the formal semantics. Sequential/parallel composition from string diagrams gives the layout algorithm its mathematical grounding.

### Layer 2: Topological (TDA + Sheaves)
Over the structural graph, compute **topological invariants**. Persistence barcodes summarize the multi-scale structure of agent interactions. The **sheaf** assigns state data to the structural graph and measures consistency via the coboundary/Laplacian. These are complementary: TDA finds the shape, sheaves assess the data flowing through that shape.

### Layer 3: Relational (FCA Lattices)
Orthogonal to the graph view, **concept lattices** provide a hierarchical browser for the agent-task-capability relationship space. This answers "what can we do?" rather than "what are we doing?" -- it is the capability/configuration view vs. the runtime/execution view.

### Layer 4: State (Lens/Optics)
The **lens abstraction** governs how each visualization layer connects to the global state. Each panel in Meadowsyn is a lens focus on the factory state. Bidirectional sync ensures user interactions (dragging nodes, filtering lattice, adjusting TDA parameters) propagate correctly.

### Concrete Architecture Proposal

```
Meadowsyn Frontend
+-- Graph Canvas (LiteGraph.js + hybrid React overlays)
|   +-- Agent nodes with real-time status
|   +-- Subgraph encapsulation for sprints/teams
|   +-- String diagram layout algorithm (via Catlab export)
|   +-- Edge decorations: sheaf coboundary magnitude
+-- Topology Panel (TDA Explorer components, WASM)
|   +-- Persistence barcode of agent interaction graph
|   +-- Mapper graph for behavioral clustering
|   +-- Betti number timeline
+-- Consistency Panel (custom, backed by PySheaf/wasm-port)
|   +-- Sheaf consistency heat map over agent graph
|   +-- Laplacian eigenvalue barcode
|   +-- Diffusion animation (opinion dynamics)
+-- Capability Lattice (lattice.js)
|   +-- Agent-capability concept lattice browser
|   +-- Task-file dependency lattice
|   +-- Temporal lattice animation
+-- State Layer (use-profunctor-state / Jotai optics)
    +-- Global factory state atom
    +-- Per-panel lens focuses
    +-- Bidirectional sync indicators
```

---

## Key Repositories and Resources Index

### Libraries to Evaluate for Integration

| Priority | Library | Why | License |
|----------|---------|-----|---------|
| **P0** | [LiteGraph.js](https://github.com/jagenjo/litegraph.js) | Canvas graph editor with subgraph support, proven at scale (ComfyUI) | MIT |
| **P0** | [lattice.js](https://www.researchgate.net/publication/397316425) | Only modern web-native FCA viz library | TBD |
| **P1** | [TDA Explorer](https://zktheory.org/projects/tda-explorer/) | React+WASM TDA viz, embeddable | TBD |
| **P1** | [use-profunctor-state](https://github.com/staltz/use-profunctor-state) | Lens-based React state management | MIT |
| **P1** | [Kepler-Mapper](https://github.com/scikit-tda/kepler-mapper) | Mapper algorithm with D3/Plotly export | MIT |
| **P2** | [PySheaf](https://github.com/kb1dds/pysheaf) | Sheaf computation backend (needs WASM port or API wrapper) | BSD |
| **P2** | [Catlab.jl](https://github.com/AlgebraicJulia/Catlab.jl) | Wiring diagram computation and export | MIT |
| **P2** | [sheaf-diffusion](https://github.com/marco-campos/sheaf-diffusion) | Reference implementation for opinion dynamics visualization | TBD |
| **P3** | [homotopy.io](https://homotopy.io/) | Reference for string diagram interaction patterns | BSD |
| **P3** | [Jotai optics](https://jotai.org/docs/extensions/optics) | Alternative to use-profunctor-state for atomic state | MIT |
| **P3** | [fca.js](https://github.com/mdaquin/fca.js) | Lightweight FCA computation in browser | MIT |

### Key Papers for Design Rationale

1. Robinson, "Sheaves are the canonical data structure for sensor integration" ([arXiv:1603.01446](https://arxiv.org/abs/1603.01446)) -- theoretical justification for sheaf-based agent state fusion
2. Hansen and Ghrist, "Opinion Dynamics on Discourse Sheaves" ([arXiv:2005.12798](https://arxiv.org/abs/2005.12798)) -- sheaf Laplacian for multi-agent consensus
3. Selinger, "A survey of graphical languages for monoidal categories" ([arXiv:0908.3347](https://arxiv.org/abs/0908.3347)) -- taxonomy of string diagram types
4. Fong and Spivak, "Seven Sketches in Compositionality" ([arXiv:1803.05316](https://arxiv.org/abs/1803.05316)) -- applied category theory for system composition
5. Cybercat Institute, "Optics for UI" ([blog post](https://cybercat.institute/2025/01/21/ui-para-optic/)) -- mathematical proof that React = parametrised lens
6. Gebhart et al., "Knowledge Sheaves" ([arXiv:2110.03789](https://arxiv.org/abs/2110.03789)) -- sheaf framework for knowledge graph embedding
