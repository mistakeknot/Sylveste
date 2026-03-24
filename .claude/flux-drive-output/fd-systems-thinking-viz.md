---
agent: fd-systems-thinking-viz
mode: research
target: meadowsyn-frontier-research
timestamp: 2026-03-21
---

# Systems Dynamics Visualization Research for Meadowsyn

Frontier research on systems thinking visualization tools, techniques, and academic findings, mapped to Meadowsyn -- a public-facing web visualization frontend for an AI agent factory (autonomous software development with dozens of simultaneous agents).

---

## 1. Vensim, Stella Architect, Insight Maker: CLD and SFD Rendering Comparison

### Vensim

**Rendering approach.** Vensim uses a freeform canvas where users manually place nodes and draw causal links. It is uniquely flexible in allowing mixed stock-and-flow (SFD) and causal loop (CLD) elements on the same diagram. Variables appear as plain text labels (no enclosing shapes for auxiliaries), stocks render as rectangles, and flows use valve/pipe notation. Arrow polarity (`+`/`-`) and loop labels (`R`/`B`) are first-class diagram elements.

**What works for comprehension.** Vensim's killer feature is **Causal Tracing** -- double-clicking any variable instantly shows strip graphs for all its causal inputs, letting you trace behavior backwards through the model in seconds. This turns a static diagram into an interactive analytical tool. The Causes Tree and Uses Tree show two-hop causal neighborhoods. This approach works because it provides *local* comprehension of a *global* diagram -- you never need to mentally parse the entire structure at once.

- Source: [Vensim Causal Tracing documentation](https://vensim.com/causal-tracing/)
- Source: [Vensim CLD documentation](https://www.vensim.com/documentation/usr04.html)

**What becomes spaghetti.** At ~20+ variables with cross-cutting feedback loops, Vensim CLDs become visually unmanageable. There is no automatic layout engine -- all placement is manual. Vensim provides no grouping, encapsulation, or progressive disclosure of subsystems. The IISD SAVI Academy guide explicitly recommends limiting CLD complexity and avoiding "spaghetti" diagrams where too many intertwined links make causality unreadable.

- Source: [IISD SAVI Academy CLD design guide](https://www.iisd.org/savi/wp-content/uploads/2020/03/savi-academy-clds-vensim-final.pdf)

**Meadowsyn mapping.** Vensim's Causal Tracing is a direct inspiration for Meadowsyn's "click any agent/queue to see what's driving its current behavior" interaction. The strip-graph trace pattern translates to: click an agent node -> see time-series for its input queue depth, token consumption, and upstream dependencies. Avoid Vensim's layout-less approach; Meadowsyn must auto-layout.

### Stella Architect (isee systems)

**Rendering approach.** Stella uses a four-primitive visual language: stocks (rectangles), flows (pipes with valves), converters (circles), and connectors (arrows). The rendering is clean and iconographic. Recent versions (2024-2025) add an AI Assistant that helps construct CLDs by suggesting link polarities.

**Web publishing.** Stella Architect publishes interactive models to the **isee Exchange** platform, where anyone with a browser can run them. Interfaces are built with drag-and-drop widgets (sliders, graphs, knobs). Models can include **SVG-based animations** with color, size, and rotation driven by simulation state. This is the closest existing analog to Meadowsyn's goal of animated, interactive system-state dashboards.

- Source: [Stella Architect feature updates](https://www.iseesystems.com/store/products/feature-updates.aspx)
- Source: [Stella Architect product page](https://www.iseesystems.com/store/products/stella-architect.aspx)

**XMILE standard.** Stella (v10+) outputs models in XMILE, the OASIS-standardized XML interchange format for system dynamics. XMILE separates model semantics (equations, variables) from presentation (diagram layout, styling). This is important for Meadowsyn: XMILE is a viable intermediate representation for system-dynamics model interchange.

- Source: [OASIS XMILE v1.0 specification](https://docs.oasis-open.org/xmile/xmile/v1.0/xmile-v1.0.html)
- Source: [XMILE open standard blog](https://blog.iseesystems.com/news-announcements/xmile-faq/)

**Meadowsyn mapping.** Stella's SVG animation layer (color/size/rotation driven by model state) is directly applicable. The isee Exchange publishing model proves that system-dynamics visualizations work as interactive web experiences. Meadowsyn should support XMILE import/export as a bridging format.

### Insight Maker

**Rendering approach.** Fully browser-based, built on the mxGraph diagramming library (the same engine behind draw.io). Supports System Dynamics (stock/flow), Agent-Based Modeling, and imperative programming in a unified framework. The simulator is pure client-side JavaScript (ECMAScript 5+), with a tiered architecture: Tier 0 (JS engine), Tier 1 (math/equation evaluator), Tier 2 (simulation runner), Tier 3 (UI/rendering).

- Source: [Insight Maker academic paper (Simulation Modelling Practice and Theory, 2014)](https://www.sciencedirect.com/science/article/pii/S1569190X14000513)
- Source: [Insight Maker GitHub (open source)](https://github.com/MunGell/insightmaker)
- Source: [scottfr/simulation -- standalone JS simulation engine](https://github.com/scottfr/simulation)

**Adoption and architecture.** 50,000+ registered users. The simulation engine has been extracted into a standalone npm-compatible library (`scottfr/simulation`) that supports System Dynamics, differential equations, and ABM in both Node.js and browser contexts. Accessibility is prioritized over performance.

**Meadowsyn mapping.** The `scottfr/simulation` library is a candidate for embedding system dynamics simulation directly in Meadowsyn's frontend, enabling client-side "what-if" exploration without server round-trips. The mxGraph rendering layer is dated; Meadowsyn should use a modern alternative (Cytoscape.js, React Flow, or custom Svelte components).

### Usability Research on CLD Comprehension

**Cognitive limits.** The human mind can typically grasp the dynamic behavior of 2-3 variables. Beyond 3-4 dynamically interacting variables, comprehension degrades sharply (Sterman, *Business Dynamics*). This sets a hard upper bound on what any single CLD view can communicate.

**Sequential presentation helps.** A 2025 study found that presenting CLDs sequentially (after textual explanation) significantly improved systems thinking and information utilization in complex problem analysis compared to presenting all information at once.

- Source: [Scientia Militaria study on CLD influence on systems thinking, 2025](https://www.sciencedirect.com/science/article/pii/S2451958825000284)

**Sterman bathtub studies.** Booth Sweeney and Sterman (2000) found that even MIT Sloan graduate students failed at basic stock-flow tasks -- fewer than half could correctly sketch the trajectory of water in a bathtub given simple inflow/outflow graphs. This demonstrates that stock-flow comprehension is *not* intuitive and requires explicit visual support.

- Source: [Bathtub Dynamics (Sterman, MIT)](http://web.mit.edu/jsterman/www/Bathtub.pdf)

**Meadowsyn mapping.** Critical implication: Meadowsyn must limit visible complexity to 3-5 simultaneously visible feedback loops. Use progressive disclosure (expand/collapse subsystems), and always pair diagrams with behavior-over-time graphs. Never show the full 50-agent system as one flat diagram.

---

## 2. Kumu and Loopy: Web-Native Causal Diagram Tools

### Kumu

**Overview.** Kumu (https://kumu.io) is a web-based relationship/systems mapping platform. Free for public/educational use, $9/month for private projects. Used by UNDP, peace-building organizations, and systems thinking practitioners.

**Interaction model.**
- Pan/zoom with standard web gestures
- Click elements to see profile panels with rich metadata
- Filter views based on data fields (show/hide elements, connections, loops)
- Presentation mode for step-by-step narrative walkthroughs of a system map

**Data-driven decorations.** Kumu's most powerful feature for Meadowsyn is its declarative styling system: rules that dynamically change element size, color, and connection thickness based on data fields. You can "Size by" a numeric field, "Color by" any categorical or numeric field, and apply threshold-based styling. All decorations are live and reactive -- they update as data changes.

- Source: [Kumu data-driven decorations](https://docs.kumu.io/guides/decorate/data-driven-decorations)

**Built-in network metrics.** Kumu computes: degree, closeness centrality, betweenness centrality, eigenvector centrality, indegree, outdegree, reach (2-step out), reach efficiency, and MICMAC influence-exposure mapping. These can drive decorations -- e.g., size elements by betweenness to visually highlight bottleneck nodes.

- Source: [Kumu metrics documentation](https://docs.kumu.io/guides/metrics)

**Embedding.** Maps are embeddable via iframe with configurable controls (search, zoom, settings). URL parameters provide some programmatic interaction, but there is no JavaScript SDK for deep integration. Cross-origin scripting is blocked.

- Source: [Kumu share and embed](https://docs.kumu.io/guides/share-and-embed)

**Community detection.** Kumu uses the SLPA algorithm for overlapping community detection, automatically identifying clusters in the network.

**Limitations for Meadowsyn.** No animation of edge weights or flow rates. No simulation capability. No open API beyond embed parameters. Purely a visualization/analysis tool, not a simulation engine. The iframe embedding model limits deep integration.

**Meadowsyn mapping.** Kumu's data-driven decoration system is the direct model for Meadowsyn's "style agents/queues by their current metrics" feature. Size by queue depth, color by health status, thickness by throughput. The centrality metrics (especially betweenness) directly identify bottleneck agents. Kumu's MICMAC influence-exposure mapping is a ready-made technique for the leverage-points overlay.

### Loopy (ncase/loopy)

**Overview.** Created by Nicky Case (2017), Loopy is a minimalist, hand-drawn-aesthetic CLD tool. Entirely open source (CC0 public domain). Users draw circles (nodes) and arrows (causal links) freehand on a canvas, assign positive/negative polarity, then "play" the simulation by injecting perturbations.

- Source: [LOOPY live tool](https://ncase.me/loopy/)
- Source: [GitHub: ncase/loopy](https://github.com/ncase/loopy)

**Technical stack.** JavaScript (75.5%), CSS (12.3%), HTML (12.2%). Uses HTML5 Canvas for rendering (not SVG, not WebGL). Dependencies: minpubsub (pub/sub events), balloon.css (tooltips). Extremely lightweight.

**Signal propagation model.** The core innovation is Loopy's **animated signal propagation**: you click a node to inject "more" or "less" of something, then watch colored signals flow along edges, accumulating and propagating through feedback loops. This provides immediate intuitive understanding of feedback dynamics without requiring equations or numerical simulation. Signals are visualized as colored dots moving along arrows.

**Loopy v2 (1000i100 fork).** The original project was maintained by Nicky Case through v1.1 (2017). Since ~2020, the user 1000i100 has maintained an extended v2 with additional features:
- Multiple signal modes: legacy, accumulator, alive-accumulator
- Extended drawing tools
- Available at https://1000i100.github.io/loopy/2/ and lo0p.it/2/

- Source: [GitHub: 1000i100/loopy](https://github.com/1000i100/loopy)
- Source: [LOOPY v2 PR on ncase/loopy](https://github.com/ncase/loopy/pull/20)

**MITRE Loopy2.** MITRE hosts a fork of Loopy at https://sjp.mitre.org/loopy2/ with pre-built models (including a wealth model), indicating institutional adoption for systems analysis.

**Schucan/CLD.** Another lightweight open-source web CLD tool. "A super light-weight web app to create causal loop diagrams online."

- Source: [GitHub: schucan/CLD](https://github.com/schucan/CLD)

**causal-loops.com.** A free online CLD creation tool based on a Loopy-like approach, with no login required.

- Source: [causal-loops.com](https://www.causal-loops.com/)

**Meadowsyn mapping.** Loopy's animated signal propagation is the single most important interaction pattern for Meadowsyn. When a user asks "what happens if agent throughput drops?", Meadowsyn should animate the impact rippling through the dependency graph -- queue backlogs accumulating, downstream agents starving, escalation loops activating. The Canvas-based rendering is appropriate for Meadowsyn's scale (~50-100 nodes). The pub/sub architecture (minpubsub) is clean but should be replaced with a reactive framework (Svelte stores or signals).

---

## 3. System Archetypes as UI Components

### The Core Archetypes

There are 8-12 canonical system archetypes identified by Senge, Kim, and others. The most relevant to an agent factory:

| Archetype | Structure | Agent Factory Pattern |
|---|---|---|
| **Limits to Growth** | Reinforcing loop hits a balancing constraint | Agent throughput scales linearly, then hits token budget ceiling or API rate limit |
| **Shifting the Burden** | Short-term fix weakens fundamental solution | Quick retry/restart masks root cause (bad prompt template, wrong model) |
| **Tragedy of the Commons** | Shared resource eroded by individual optimization | Multiple agents competing for shared API quota or context window |
| **Escalation** | Two competing balancing loops ratchet up | Two agent queues competing for priority, each escalating urgency signals |
| **Fixes that Fail** | Short-term fix creates delayed side effects | Aggressive parallelism reduces wall-clock time but increases cost and error rate |
| **Success to the Successful** | Winner-take-all reinforcing loop | Best-performing agent gets more work, crowding out specialization |
| **Growth and Underinvestment** | Growth outpaces capacity investment | Agent fleet scales but tooling/observability investment lags |
| **Eroding Goals** | Gap between goal and reality closes by lowering the goal | Quality bar drifts downward as "good enough" patches accumulate |

- Source: [Wikipedia: System archetype](https://en.wikipedia.org/wiki/System_archetype)
- Source: [Systems Archetypes I (The Systems Thinker)](https://thesystemsthinker.com/wp-content/uploads/2016/03/Systems-Archetypes-I-TRSA01_pk.pdf)
- Source: [Kim, Systems Archetypes Basics](https://thesystemsthinker.com/wp-content/uploads/2016/03/Systems-Archetypes-Basics-WB002E.pdf)
- Source: [12 recurring archetypes (Medium/Acaroglu)](https://medium.com/disruptive-design/tools-for-systems-thinkers-the-12-recurring-systems-archetypes-2e2c8ae8fc99)

### Existing Implementations as Reusable Components

**No existing library provides archetypes as reusable visual widgets.** The current state of practice is:

1. **Static templates.** The Systems Thinker publishes PDF workbooks with blank archetype templates (two-loop structures with fill-in labels). Miro, Creately, and Visual Paradigm offer CLD templates but these are static drawing aids, not interactive components.

2. **Kumu archetypes.** Users manually build archetype structures in Kumu with loop annotations. No pre-built archetype library exists.

3. **Insight Maker models.** Individual archetype simulations are shared on insightmaker.com, but as standalone models, not composable widgets.

4. **isee systems (Stella).** Publishes "Success to the Successful" and other archetype examples on their blog with interactive web simulations, but these are full Stella models, not embeddable components.

- Source: [isee Systems "Success to the Successful" interactive model](https://blog.iseesystems.com/stella-ithink/success-to-the-successful/)

5. **Systems & Us.** Provides archetype descriptions with CLD diagrams, including interactive explanations of Tragedy of the Commons, but as web articles rather than embeddable components.

- Source: [Systems & Us: Tragedy of the Commons archetype](https://systemsandus.com/archetypes/tragedy-of-the-commons/)

### The Opportunity for Meadowsyn

Meadowsyn can be the first system to provide **archetypes as pattern-matched, parameterized visual widgets**. The implementation approach:

1. **Define archetype graph templates.** Each archetype is a small directed graph (2-4 loops, 4-8 nodes) with typed node slots (stock, flow, auxiliary) and typed edge slots (reinforcing, balancing).

2. **Pattern detection.** Given the live agent-factory graph, run subgraph isomorphism matching to detect which archetypes are currently active. E.g., detect "Tragedy of the Commons" when multiple agents' throughput metrics are inversely correlated with a shared resource's availability.

3. **Archetype overlay.** When detected, render the archetype as a semi-transparent overlay on the relevant subgraph, with a tooltip explaining the pattern and suggested interventions ("Consider: increase API quota, or implement agent scheduling to prevent simultaneous access").

4. **Behavior-over-time widget.** Each archetype has a canonical behavior-over-time signature (e.g., Limits to Growth = initial exponential followed by plateau). Show the actual factory metrics overlaid on the expected archetype trajectory.

---

## 4. Animated Stock-and-Flow: Does Animation Aid or Hinder Comprehension?

### The Evidence: Nuanced, Not Uniformly Positive

**Pro-animation: The Eindhoven study (Aysolmaz & Reijers, 2021).** The most directly relevant study found that animation significantly improves process model comprehension, but with a U-shaped moderation by expertise. Low-expertise and high-expertise users benefit most; moderate-expertise users benefit least (they have internalized static-diagram reading strategies that animation disrupts).

- Source: [Aysolmaz & Reijers, "Animation as a dynamic visualization technique for improving process model comprehension," Information and Management, 2021](https://www.sciencedirect.com/science/article/pii/S0378720621000525)

**Anti-animation: Tversky, Morrison & Betrancourt (2002).** This influential meta-review found that animation is often no better than static diagrams, and sometimes worse. The key failure mode is the **transient information effect** -- animation presents information that disappears before it can be processed, overloading working memory. Their three principles for effective graphics:

- **Apprehension Principle:** The external representation must be readily and accurately perceived.
- **Congruence Principle:** The representation's structure should map naturally to the mental model being built.
- **Only use animation when the concept is inherently temporal.** Spatial relationships are better shown statically.

- Source: [Tversky et al., "Animation: can it facilitate?" (IJHCS, 2002)](https://hci.stanford.edu/courses/cs448b/papers/Tversky_AnimationFacilitate_IJHCS02.pdf)

**Pro-animation with constraints: "Principled animation design" (2016).** This study demonstrated that **compositional animation** (subdividing animation by semantic event units, not arbitrary time slices) significantly improved mental model quality compared to both conventional animation and static views.

- Source: ["Principled animation design improves comprehension of complex dynamics" (ScienceDirect, 2016)](https://www.sciencedirect.com/science/article/abs/pii/S0959475216300627)

**Cognitive load theory findings.** Two design strategies reliably mitigate animation's downsides:
1. **Pacing control.** Let users pause, rewind, and adjust speed. Reduces transient information effect.
2. **Segmenting.** Break animation into discrete, meaningful chunks rather than continuous flow.

- Source: [Cognitive Load Theory advances (Educational Psychology Review, 2010)](https://link.springer.com/article/10.1007/s10648-010-9145-4)

**DataParticles (CHI 2023).** A block-based authoring tool for animated unit visualizations that coordinates enter-animations with narrative sequence. The key finding: carefully coordinating animation sequence with story narrative ensures more effective visual comprehension. The tool was validated in a user study with 9 domain experts.

- Source: [DataParticles, CHI 2023](https://dl.acm.org/doi/full/10.1145/3544548.3581472)

**Flow visualization user studies.** Research on 3D flow visualization found that arrows are the most universally understood representation for direction and flow rate, but need to be made bright and semi-transparent for attractiveness. Particle-based flow visualization (small moving dots along paths) tested well for showing direction and magnitude but can become visually overwhelming at high densities.

- Source: ["Visualizing the invisible: User-centered design of a system" (HAL, 2022)](https://hal.science/hal-03653141v1/document)

### Synthesis for Meadowsyn

**Animate flow rates: Yes, but with strict constraints.**

1. **Use particle streams for throughput.** Small dots flowing along edges from queue to agent to output. Particle density encodes throughput (more particles = higher rate). This satisfies the Congruence Principle (flow is inherently temporal).

2. **Use fill-level animation for stocks.** Queue depth as a fill-gauge that rises/falls. This satisfies Apprehension (instantly graspable) and leverages the bathtub metaphor that Sterman showed is intuitive even when equations are not.

3. **Always provide pacing control.** Pause button, speed slider, and time scrubber. Never auto-play complex animations without user control.

4. **Segment by event, not by time.** When showing "what happened in this sprint," animate one agent event at a time (claim -> work -> output), not a continuous time-based replay.

5. **Keep particle density low.** Maximum ~5 simultaneous particle streams visible. Dim or hide inactive edges. Use progressive disclosure: show full animation only for the selected subgraph.

6. **Dual encoding.** Always pair animation with a static numeric readout. Animation shows trend/direction; numbers show magnitude.

---

## 5. Jay Forrester's Urban Dynamics: Modern Web Reinterpretations

### The Original Model

Jay Forrester published *Urban Dynamics* in 1969. It models three socioeconomic classes (underemployed, labor, managerial-professional), three housing types, and industrial sectors, simulating a 250-year urban lifecycle. The model controversially predicted that conventional urban renewal policies (subsidized housing, job programs) would worsen rather than improve urban decay -- because they attracted more population without increasing the industrial base, a classic "Limits to Growth" archetype.

- Source: [Forrester, *Urban Dynamics* (Internet Archive)](https://archive.org/details/urbandynamics0000forr)

### Modern Web Implementations

**Forio Simulate: Urban Dynamics.** Forio (founded by MIT Sloan alumni) hosts an interactive web version of the Urban Dynamics model. Users can copy and explore the model, adjusting parameters and observing 250-year trajectories. The interface provides graphs and parameter controls.

- Source: [Forio Urban Dynamics simulation](https://forio.com/simulate/mbean/urban-dynamics/overview/)

**Forio Epicenter platform.** Forio's commercial platform allows hosting server-side Vensim/Stella models with custom web/mobile frontends. Used for education, training, and forecasting applications. Models run server-side; the frontend is a web application. This is the most mature example of "classic SD model -> interactive web experience" in production.

- Source: [Forio Epicenter features](https://forio.com/products/epicenter/features/)

**En-ROADS (Climate Interactive + MIT Sloan).** The most sophisticated modern example of Forrester-lineage system dynamics as an interactive web tool. En-ROADS is a global climate policy simulator:
- **Model:** Built in Vensim, translated to WebAssembly via **SDEverywhere**
- **Frontend:** Svelte framework
- **Interaction:** Interactive sliders for policy levers (carbon tax, renewable subsidies, etc.) with immediate real-time graph updates
- **Performance:** Runs in a fraction of a second on an ordinary laptop
- **Scale:** Used in facilitated workshops worldwide, available in 12+ languages

- Source: [En-ROADS simulator](https://en-roads.climateinteractive.org/scenario.html)
- Source: [En-ROADS science documentation](https://www.climateinteractive.org/en-roads/en-roads-simulator-science/)
- Source: [Climate Interactive](https://www.climateinteractive.org/)

### Open-Source JS/WASM System Dynamics Engines

**SDEverywhere** (Climate Interactive). The production-grade toolchain for converting Vensim models to C/JavaScript/WebAssembly. MIT-licensed monorepo with modular packages:
- `@sdeverywhere/cli` -- command-line compiler
- `@sdeverywhere/runtime` / `runtime-async` -- JS/WASM execution engines
- `@sdeverywhere/plugin-wasm` -- WebAssembly compilation
- `@sdeverywhere/plugin-vite` -- Vite integration for web apps
- `@sdeverywhere/plugin-check` -- model validation testing
- Supports live development with real-time model updates

- Source: [GitHub: climateinteractive/SDEverywhere](https://github.com/climateinteractive/SDEverywhere)
- Source: [SDEverywhere website](https://sdeverywhere.org/)
- Source: [SDEverywhere npm](https://www.npmjs.com/package/sdeverywhere)

**Simlin** (Bobby Powers). Open-source web-first SD modeling editor and simulation engine:
- **Stack:** Rust (75.7%) compiled to WebAssembly for simulation, TypeScript/React frontend
- **Features:** Full model editing, Vensim/XMILE import, XMILE export, stock/flow/connector diagram editor, undo/redo
- **Architecture:** Polyglot monorepo (Rust + TypeScript + Python), Playwright integration tests

- Source: [GitHub: bpowers/simlin](https://github.com/bpowers/simlin)
- Source: [Simlin website](https://simlin.com/)

**Insight Maker Simulation Engine** (scottfr/simulation). Standalone JavaScript library extracted from Insight Maker:
- Supports System Dynamics, differential equations, and Agent-Based Modeling
- Runs in both Node.js and browser
- npm-compatible

- Source: [GitHub: scottfr/simulation](https://github.com/scottfr/simulation)

**PySD** (SDXorg). Python library that translates Vensim/XMILE models to Python. Not browser-native but relevant as a server-side simulation backend.

- Source: [GitHub: SDXorg/pysd](https://github.com/SDXorg/pysd)
- Source: [PySD documentation](https://pysd.readthedocs.io/en/master/)

**Simantics System Dynamics.** VTT/Semantum open-source desktop tool for system dynamics modeling, free to use.

- Source: [Simantics System Dynamics](https://sysdyn.simantics.org/)

### Meadowsyn Mapping

The **SDEverywhere + Svelte** stack (as proven by En-ROADS) is the reference architecture for Meadowsyn's simulation layer:

1. Define the agent-factory system dynamics model in Vensim or XMILE.
2. Compile to WebAssembly via SDEverywhere for client-side execution.
3. Build the Meadowsyn frontend in Svelte (or React + Svelte Flow).
4. Connect slider controls to model parameters, render output as animated graphs + the causal diagram.

This gives sub-second model execution in-browser with no server dependency. The En-ROADS precedent proves this works at production scale with millions of users.

---

## 6. Leverage Points (Meadows 1999) as a UI Metaphor

### The Framework

Donella Meadows' 1999 paper "Leverage Points: Places to Intervene in a System" identifies 12 places to intervene, ranked from least to most powerful:

12. **Constants, parameters, numbers** (subsidies, taxes, standards)
11. **Buffer sizes** (relative to flows through them)
10. **Structure of material stocks and flows** (transport, population networks)
9. **Length of delays** (relative to rate of change)
8. **Strength of negative feedback loops** (relative to impacts they correct)
7. **Gain around driving positive feedback loops**
6. **Structure of information flows** (who has access to what)
5. **Rules of the system** (incentives, punishments, constraints)
4. **Power to add/change/self-organize system structure**
3. **Goals of the system**
2. **Mindset/paradigm** out of which the system arises
1. **Power to transcend paradigms**

The key insight: 99% of attention goes to level 12 (tweaking parameters), which has the least leverage. The most powerful interventions change information structures, rules, goals, or paradigms.

- Source: [Meadows, "Leverage Points" (1999 original paper)](https://donellameadows.org/wp-content/userfiles/Leverage_Points.pdf)
- Source: [Twelve leverage points (Wikipedia)](https://en.wikipedia.org/wiki/Twelve_leverage_points)

### The Donella Meadows Project Visual Initiative

The Donella Meadows Project is actively translating the leverage points framework into "a broadly-understood visual language for approaching problems more systemically." The result so far is the animated video *"In a World of Systems"*, illustrated by David Macaulay (of *The Way Things Work* fame) and developed with Linda Booth Sweeney. The visual language uses:
- Zoomed-in views for stocks/flows/structure
- Zoomed-out views for interconnections and systemic patterns
- Feedback loop illustration through simple animal/resource examples
- Progressive revelation of hidden system layers

- Source: [Donella Meadows Project: Visual Approach to Leverage Points](https://donellameadows.org/a-visual-approach-to-leverage-points/)

### Network Analysis for Leverage Point Identification

**Centrality-based approaches.** Betweenness centrality and closeness centrality have been applied to CLDs to mathematically identify which variables are most likely leverage points. Kumu provides these metrics out-of-the-box and can size/color nodes by centrality scores.

**Critical limitation.** A 2023 Nature paper by Kupers et al. demonstrated that **using betweenness and closeness centrality to identify leverage points in CLDs leads to false inference**. The underlying assumption -- that causal power gradually diminishes along a causal chain -- does not hold in system dynamics models, where feedback loops amplify distant causes. The paper concludes this practice "is at best premature and at worst incorrect."

- Source: [Kupers et al., "Using network analysis to identify leverage points based on causal loop diagrams leads to false inference," Scientific Reports, 2023](https://www.nature.com/articles/s41598-023-46531-z)

**Alternative: simulation-based sensitivity analysis.** Rather than relying on graph topology alone, run Monte Carlo simulations or one-at-a-time parameter sweeps to measure actual sensitivity of system outputs to each variable. SDEverywhere's WASM runtime makes this feasible in-browser.

**Dangling Centrality (2025).** A novel metric that identifies critical nodes by evaluating the impact of their link removal on system dynamics (rather than their graph-theoretic centrality).

- Source: ["Dangling centrality highlights critical nodes" (Scientific Reports, 2025)](https://www.nature.com/articles/s41598-025-24930-8)

### Systems Oriented Design: Gigamapping and Leverage Points

The Oslo School of Architecture and Design (AHO) has developed **Systems Oriented Design (SOD)** with **Gigamapping** -- large-scale, multi-layer visualization that combines CLDs, stakeholder maps, timelines, and scenario explorations in a single visual space. SOD explicitly includes a "leverage point investigation" step where practitioners use the visual map to identify intervention opportunities.

- Source: [Systems Oriented Design: Leverage Points](https://systemsorienteddesign.net/leverage-points/)
- Source: [SOD at AHO](https://www.aho.no/english/studies/programmes/executive-master-of-systems-oriented-design/)

### Meta Causal Loop Diagrams (Pantaleon)

Miguel Pantaleon has developed **Meta CLDs** that integrate causal loop diagrams with social network analysis and graph database technology. The key advance: treating CLDs as networks and using graph query languages to navigate them, rather than requiring visual comprehension of the entire diagram.

Three limitations of traditional CLDs that Meta CLDs address:
1. Relationships prevent integrating people/stakeholders into the model
2. Navigation complexity increases exponentially with map size
3. Variables cannot store additional metadata

Meta CLDs use graph databases to enable natural-language querying of causal relationships, bypassing the visual spaghetti problem entirely.

- Source: [Pantaleon, "Beyond system mapping: Meta Causal Loop Diagrams"](https://medium.com/@MiguelPantaleon/beyond-system-mapping-meta-causal-loop-diagrams-92db58275c10)
- Source: [SCiO Meta Causal Loop Modelling resource](https://www.systemspractice.org/resources/meta-causal-loop-modelling)

### CLD Simplification Methods

The EEOR (Endogenisation, Encapsulation, Order-Oriented Reduction) technique from Buresaw et al. (2017) provides a systematic 7-step process for simplifying complex CLDs:
1. Identify duplicate variables
2. Define complexity levels
3. Identify exogenous variables
4. Eliminate exogenous variables (Endogenisation)
5. Eliminate single-input/single-output variables (Encapsulation)
6. Order-oriented reduction
7. Number loops

This provides the algorithmic basis for Meadowsyn's auto-simplification feature.

- Source: [EEOR method (Systems, MDPI, 2017)](https://www.mdpi.com/2079-8954/5/3/46)

### Meadowsyn UI Design for Leverage Points

**Primary pattern: Sensitivity heat-map overlay.**

1. Run background simulation sweeps (via SDEverywhere WASM) to compute partial derivatives: how much does each output metric change when each input varies by +/- 10%?
2. Map sensitivity magnitude to a color scale on the causal diagram. High-sensitivity nodes glow hot (red/orange); low-sensitivity nodes are cool (blue/gray).
3. Size nodes by Meadows' level (12-1). Constants are small; rules/goals are large. This creates a visual hierarchy where the most powerful intervention points are literally the biggest, most prominent elements.

**Secondary pattern: "What if?" propagation.**

When a user hovers over or clicks a node, animate the downstream impact cascade (Loopy-style signal propagation) with intensity proportional to the sensitivity coefficient. High-leverage nodes produce large, visible ripples; low-leverage nodes produce barely visible perturbations.

**Avoid betweenness centrality for leverage identification.** Per the Kupers et al. (2023) finding, do not use graph centrality as a proxy for leverage. Always use simulation-based sensitivity. Centrality metrics are still useful for *visualization* (sizing/coloring), but label them as "connectivity" not "leverage."

---

## Technology Stack Recommendations for Meadowsyn

Based on all findings, the recommended stack:

| Layer | Technology | Rationale |
|---|---|---|
| **Simulation engine** | SDEverywhere (Vensim -> WASM) or Simlin (Rust -> WASM) | Proven in En-ROADS; sub-second in-browser execution |
| **Frontend framework** | Svelte 5 (Runes) | Used by En-ROADS; lightweight, reactive, fast |
| **Graph rendering** | Cytoscape.js or Svelte Flow | Compound nodes, data-driven styling, layout algorithms |
| **Layout algorithms** | Dagre (DAG), ELK (force-directed), or custom | Cytoscape.js-dagre for hierarchical, cola.js for force-directed |
| **Animation** | Canvas 2D (particle streams) + SVG (node decorations) | Canvas for particle performance; SVG for crisp node rendering |
| **Metrics/centrality** | Cytoscape.js built-in or custom | Degree, betweenness, community detection |
| **Model interchange** | XMILE (XML) | OASIS standard; import/export with Vensim, Stella, Simlin |
| **Time-series graphs** | D3.js or Layercake (Svelte) | Behavior-over-time plots alongside causal diagrams |

### Key Open-Source Dependencies

| Repo | What it provides | License |
|---|---|---|
| [climateinteractive/SDEverywhere](https://github.com/climateinteractive/SDEverywhere) | Vensim -> JS/WASM compiler + runtime | MIT |
| [bpowers/simlin](https://github.com/bpowers/simlin) | Rust WASM SD engine + React editor | Apache-2.0 |
| [scottfr/simulation](https://github.com/scottfr/simulation) | JS SD/ABM simulation library | Insight Maker Public License |
| [ncase/loopy](https://github.com/ncase/loopy) | Signal propagation interaction pattern | CC0 (public domain) |
| [1000i100/loopy](https://github.com/1000i100/loopy) | Extended Loopy v2 with accumulator modes | CC0 (public domain) |
| [schucan/CLD](https://github.com/schucan/CLD) | Lightweight web CLD editor | Open source |
| [cytoscape/cytoscape.js](https://github.com/cytoscape/cytoscape.js) | Graph rendering + analysis | MIT |
| [SDXorg/pysd](https://github.com/SDXorg/pysd) | Python SD model runner (server-side) | MIT |

---

## Cross-Cutting Themes

### Progressive Disclosure is Non-Negotiable

Every source -- from Sterman's bathtub studies to the EEOR simplification method to Kumu's filtering -- converges on the same conclusion: system diagrams must be viewed at controlled complexity levels. The human cognitive limit of 3-4 dynamic variables means Meadowsyn must:

1. Show a 3-5 node summary view by default (archetype level)
2. Allow drill-down into subsystems (EEOR encapsulation)
3. Never render all 50+ agents as a flat graph

### Animation Must Be User-Controlled

The Tversky/Betrancourt research and the Eindhoven study agree: uncontrolled animation harms comprehension. Meadowsyn must provide pause, speed control, and segmented playback.

### Simulation Beats Graph Theory for Leverage

Betweenness centrality is *not* a reliable proxy for system leverage (Kupers 2023). Meadowsyn must use actual simulation-based sensitivity analysis, which is now feasible in-browser thanks to WASM runtimes.

### The En-ROADS Precedent

En-ROADS (SDEverywhere + Svelte + Vensim WASM) is the existence proof that Meadowsyn's architecture is viable. A full system dynamics model, running client-side in WebAssembly, with interactive sliders and real-time graph updates, serving millions of users worldwide. This is not speculative -- it is deployed infrastructure.

---

## Grafana Flow Panel: Operational Precedent

The Grafana **Flow Panel plugin** (andrewbmchugh-flow-panel) provides side-by-side metric visualization on SVG diagrams for distributed systems. It demonstrates that architecture-diagram overlays with live metrics are a proven pattern in production observability. The Diagram plugin additionally renders Mermaid.js-based flowcharts with live Prometheus data.

- Source: [Grafana Flow Panel plugin](https://grafana.com/grafana/plugins/andrewbmchugh-flow-panel/)
- Source: [Grafana Diagram Panel plugin](https://grafana.com/grafana/plugins/jdbranham-diagram-panel/)

This validates Meadowsyn's core premise: overlaying live system metrics onto structural diagrams is an established and effective pattern for operational comprehension. The key difference is that Meadowsyn adds systems-dynamics semantics (feedback loops, archetypes, leverage analysis) on top of the raw observability layer.
