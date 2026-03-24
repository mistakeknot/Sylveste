---
agent: fd-bio-ecological
mode: research
target: meadowsyn-frontier-research
timestamp: 2026-03-21
---

# Biological and Ecological Monitoring: Frontier Research for Meadowsyn

Deep research into six domains of biological/ecological visualization, with structural mappings to AI agent factory monitoring. Each finding includes the biological technique, a specific implementation reference, and a causal structure match (not mere visual metaphor) to agent factory state.

---

## 1. Neural Population Activity Visualization

### 1.1 Raster Plots and Spike Train Visualization

**RasterVis** (https://github.com/NeurophysVis/RasterVis)
- D3.js-based web application for interactive electrophysiological spike raster analysis
- Key interaction model: align rasters to trial events, group by experimental factors, mouse-over for per-trial metadata, Gaussian-smoothed peristimulus time kernel density overlays
- Runs in-browser with JSON data format; supports arbitrary grouping dimensions

**Structural mapping to agent factory**: Each neuron is an agent. Each spike is a discrete work event (commit, test pass, bead transition). Trial alignment maps to aligning agent activity to shared events (e.g., "time since issue claimed," "time since PR opened"). Grouping by experimental factor maps directly to grouping agents by model, task type, or routing tier. The peristimulus time histogram (PSTH) overlay computes the expected event rate around a trigger -- this is structurally identical to computing agent response latency distributions around task assignment events.

**Rastermap** (https://github.com/MouseLand/rastermap) -- Stringer & Pachitariu, Nature Neuroscience 2024
- Sorts neurons along a 1D manifold to reveal sequential activation patterns in population recordings
- Key innovation: global optimization of neuron ordering using asymmetric similarity matrices
- Tested on tens of thousands of neurons from mouse cortex, zebrafish whole-brain, rat hippocampus, monkey frontal cortex, and artificial neural networks

**Structural mapping**: Agent ordering by behavioral similarity. Rastermap's 1D manifold sorting would order agents by the similarity of their work patterns (what files they touch, what tasks they prefer, when they are active). Sequential activation patterns in the sorted raster directly correspond to task propagation chains -- Agent A completes review, Agent B picks up implementation, Agent C runs tests. The "single-trial visualization" capability (no need to average over experiments) maps to monitoring a single sprint or work session without requiring historical aggregation.

### 1.2 Firing Rate Heatmaps

**Mesmerize** (https://www.nature.com/articles/s41467-021-26550-y)
- Platform for calcium imaging analysis with built-in heatmaps, spacemaps, scatterplots
- Encapsulates entire analysis pipeline from raw data to interactive visualization
- Heatmap of pairwise correlation shows network synchrony via Synchronicity Index (0-1)

**Structural mapping**: A firing rate heatmap where rows = agents, columns = time bins, and color intensity = work throughput (tokens/min, commits/hr, or bead state transitions) is a direct isomorphism, not a metaphor. The pairwise correlation heatmap maps to agent coordination detection -- when two agents have correlated activity bursts, they are likely working on related tasks or experiencing the same blocking event. The Synchronicity Index directly measures fleet coordination quality.

### 1.3 Dimensionality-Reduced Trajectory Visualization

**CEBRA** (https://cebra.ai/) -- Schneider, Lee & Mathis, Nature 2023
- Self-supervised contrastive learning for consistent embeddings of high-dimensional recordings
- Combines nonlinear ICA with contrastive learning, conditioned on behavior and/or time
- Interactive 3D web visualization of latent embeddings on cebra.ai
- Validated across calcium imaging, electrophysiology, sensory and motor tasks, multiple species

**Structural mapping**: CEBRA's joint behavioral-neural embedding is structurally ideal for agent factory state. The "neural recording" is the high-dimensional agent telemetry vector (token usage, tool calls, file operations, test results, timing). The "behavioral variable" is the task metadata (issue type, difficulty, priority, codebase region). CEBRA would embed agent sessions into a latent space where structurally similar work patterns cluster regardless of surface differences. The time-contrastive mode (CEBRA-Time) would reveal temporal dynamics of the fleet -- how the collective agent state evolves through a sprint. The behavior-contrastive mode (CEBRA-Behavior) would reveal which task properties predict agent state trajectories.

**umap-js** (https://github.com/PAIR-code/umap-js) -- Google PAIR
- Pure JavaScript UMAP implementation, runs in browser
- Provides `initializeFit()` / `step()` / `getEmbedding()` for progressive embedding
- Practical for datasets up to ~1000 points in real-time browser rendering
- Can combine with three.js for GPU-accelerated point cloud rendering

**Structural mapping**: The `step()` API enables live embedding updates as new agent sessions arrive. Each point in the UMAP space represents an agent session characterized by its telemetry vector. Clusters reveal emergent specialization (agents that have converged on similar strategies). Trajectories through the space over time show agent adaptation. The JavaScript-native implementation means this can run client-side in Meadowsyn without server-round-trips.

**NWB Explorer** (https://github.com/MetaCell/nwb-explorer)
- Web application built on Geppetto platform for NWB:N 2 file visualization
- Supports spike rasters, calcium traces, time series, and multi-panel views
- Available as standalone web app at nwbexplorer.opensourcebrain.org
- Lazy loading for large datasets

**Structural mapping**: NWB Explorer's data model -- a hierarchical container (NWB file) with heterogeneous time-aligned data streams (spikes, LFP, behavior, stimuli) -- maps directly to an agent session archive containing heterogeneous event streams (tool calls, file edits, test results, cost events). The Geppetto rendering engine's ability to synchronize multiple visualization panels on a shared time axis is the exact interaction pattern needed for correlated agent activity inspection.

---

## 2. EEG/fMRI Analysis UIs: Time-Synchronized Multi-Channel Data

### 2.1 MNE-Python Raw Browser

**MNE-Python** (https://mne.tools/) -- v1.11+
- Interactive raw data browser with scrolling multi-channel display
- Annotation mode (press 'a'): click-drag to mark temporal spans with typed labels
- Colored spans in scroll bar for rapid navigation to annotated regions
- Channel color-coding by type (MEG blue shades, EEG black)
- PageUp/PageDown for temporal zoom; Home/End for amplitude scaling
- Events extracted from annotations via `events_from_annotations()`

**Structural mapping**: The multi-channel scrolling display where each channel is a separate signal trace maps to each agent being a channel, with its activity trace (token throughput, state transitions, or tool invocations) scrolling horizontally in time. Annotation mode maps directly to human operator labeling of agent behavior spans -- marking "agent stuck in loop," "productive burst," "waiting for CI." The scroll bar colored spans provide the same rapid navigation pattern Meadowsyn needs: seeing at a glance where interesting fleet events occurred across a long time window. Channel type color-coding maps to agent tier/model color-coding.

### 2.2 NiiVue / FreeBrowse: Synchronized Multi-Panel Spatial+Temporal

**NiiVue** (https://github.com/niivue/niivue) -- v0.67.0
- WebGL2 medical image viewer, pure JavaScript, no three.js dependency
- Simultaneous display of voxels, meshes, tractography streamlines, statistical maps, connectomes
- Multiplanar views (axial, coronal, sagittal) + 3D rendering, all synchronized
- Screen refresh only on state change (efficient for monitoring dashboards)
- 30+ volume formats, mesh formats including FreeSurfer surfaces

**FreeBrowse** (https://github.com/freesurfer/freebrowse) -- built on NiiVue
- Full-stack web-based neuroimaging viewer and editor
- Browser-based version of FreeSurfer's FreeView
- Multi-panel synchronized navigation across 3D volumes

**Structural mapping**: NiiVue's multiplanar synchronized views are structurally isomorphic to viewing agent factory state from multiple orthogonal projections simultaneously. The "axial view" could be agent-vs-time (which agents are active when). The "coronal view" could be task-vs-agent (which agents work on which tasks). The "sagittal view" could be codebase-vs-time (which files are being modified when). Navigation in any panel updates all others -- clicking on an agent in the agent-time view highlights their tasks and the files they touch. NiiVue's WebGL2 rendering without three.js overhead is a strong technical choice for Meadowsyn's performance requirements. The "refresh only on change" pattern is ideal for a monitoring dashboard that must stay responsive while displaying dense data.

### 2.3 FSLeyes: Flexible Layout System

**FSLeyes** (https://open.win.ox.ac.uk/pages/fsl/fsleyes/fsleyes/userdoc/overview.html)
- Replacement for FSLView with flexible panel layout
- Multiple views open simultaneously, rearrangeable by drag-and-drop
- View panels can be configured independently while sharing a spatial context
- Supports 3D and 4D neuroimaging data

**Structural mapping**: FSLeyes' flexible layout system -- where users can arrange multiple synchronized panels in any configuration -- is the exact UI pattern Meadowsyn needs for operator customization. Different operators (sprint manager, cost analyst, quality reviewer) need different panel arrangements while sharing the same underlying fleet state. The drag-and-drop panel rearrangement and independent panel configuration (different data types, different zoom levels, same spatial context) maps to Meadowsyn dashboard customization.

### 2.4 SortingView: Web-Based Electrophysiology Curation

**SortingView** (https://github.com/magland/sortingview) + **Figurl**
- Web app for viewing, curating, and sharing spike sorting results
- Integration with SpikeInterface for full analysis pipeline
- Generates shareable links viewable from any device
- Interactive unit merging, labeling, and quality assessment
- Supports raw traces, drift maps, motion estimation visualization

**Structural mapping**: SortingView's curation workflow -- where an expert reviews automated sorting results, merges/splits units, and labels quality -- maps directly to human oversight of agent work products. The "shareable link" model (Figurl generates a URL containing the full visualization state) is ideal for Meadowsyn's collaboration needs: a sprint manager can share a specific fleet state view with a colleague. The drift map visualization (showing how signal quality changes over recording time) maps to monitoring agent performance degradation or improvement over a sprint.

### 2.5 Neuroscout and LORIS: Platform-Scale Data Management

**Neuroscout** (https://neuroscout.org/) -- Elife 2022
- End-to-end platform: model specification, estimation, and result dissemination
- Web-based analysis builder for building statistical models in browser
- Automated feature extraction using machine learning on stimuli
- Hundreds of pre-extracted predictors; supports custom user-uploaded predictors

**LORIS** (https://loris.ca/)
- Web-based longitudinal data management for multi-center neuroimaging studies
- Three sections: Behavioral Database, Imaging Browser, Data Querying GUI
- Extensive error-checking and quality control procedures
- Manages heterogeneous data acquisition across multiple sites and time points

**Structural mapping**: Neuroscout's pipeline from automated feature extraction through statistical modeling to result dissemination maps to agent factory analytics: automated extraction of work features (code complexity, test coverage change, review turnaround) through statistical modeling (which factors predict success?) to dashboarding. LORIS's multi-center longitudinal design maps to multi-sprint, multi-team agent tracking where data formats evolve over time and consistency must be maintained across heterogeneous sources.

---

## 3. Ant Colony and Stigmergic Process Visualization

### 3.1 Interactive Ant Colony Simulations

**Ant Colony RL** (https://github.com/jeffasante/ant-colony-rl)
- Interactive JavaScript simulation combining ant colonies with reinforcement learning (Q-learning)
- Real-time visualization of foraging, pheromone trails, and emergent swarm intelligence
- Shows pheromone gradient formation and decay as color intensity fields
- Demonstrates how individual decisions produce complex group-wide behavior without centralized control

**Visualize-It ACO** (https://visualize-it.github.io/ant_colony_optimization/simulation.html)
- Browser-based Ant Colony Optimization simulation
- Adjustable parameters during simulation: evaporation factor, pheromone influence, a priori influence
- Visual demonstration of path convergence and exploration-exploitation balance

**NetLogo Ants** (https://ccl.northwestern.edu/netlogo/models/Ants)
- Classic agent-based model: colony forages for food with simple per-ant rules
- Pheromone deposit on return trip, decay over time, gradient-following for outbound trips
- Demonstrates stigmergy: indirect coordination via environmental modification

### 3.2 Stigmergic Pheromone Dynamics

**Core dynamics** (from Scholarpedia: http://www.scholarpedia.org/article/Ant_colony_optimization):
- Pheromone deposit: agent completing work on path P deposits quantity proportional to solution quality
- Pheromone evaporation: exponential decay with rate rho, preventing premature convergence
- Path selection: probability of choosing path proportional to pheromone^alpha * heuristic^beta
- Without evaporation, system converges to (often wrong) solutions

**Structural mapping -- this is a genuine causal structure match, not metaphor**:

The pheromone trail system maps to agent routing preference accumulation in a factory:

| Ant Colony Concept | Agent Factory Equivalent | Causal Mechanism |
|---|---|---|
| Pheromone deposit on path | Success signal on task-routing pathway | Agent completes task via route R; positive outcome strengthens R's weight |
| Pheromone evaporation | Routing weight decay over time | Old success signals fade, preventing lock-in to stale strategies |
| Path selection probability | Routing dispatch probability | New tasks assigned proportionally to accumulated success weight |
| Multiple pheromone types | Multiple quality signals (speed, correctness, cost) | Different signal types for different optimization objectives |
| Food source depletion | Task queue exhaustion | Trails to completed work areas fade as no new rewards arrive |
| Exploration vs exploitation | Model diversity vs proven routing | Evaporation rate controls exploration; low decay = exploitation-heavy |

The key structural insight is that **pheromone concentration is not a metaphor for routing preference -- it IS the same dynamical system**. Both are positive-feedback loops with decay, where agents modify a shared environment (pheromone field / routing weight table) that subsequently modifies agent behavior. The evaporation rate is the single most important tuning parameter in both systems: too high and the system cannot learn (no memory); too low and the system cannot adapt (locked into first success).

**Visualization implication for Meadowsyn**: Display routing weights as a pheromone gradient field overlaid on the task graph. Color intensity on edges = accumulated success signal strength. Animate decay in real time. Show individual agent "trails" (the sequence of routing decisions an agent made) as paths through the field. This is not decoration -- it is a direct visualization of the actual routing dynamics.

### 3.3 Manufacturing Stigmergy (ACO for Task Allocation)

**Heterogeneous multi-agent task allocation via ACO** (https://www.oaepublish.com/articles/ir.2023.33)
- Graph neural network combined with ACO for heterogeneous agent task allocation
- Three ant types in manufacturing: feasibility ants (propagate feasible routes), exploring ants (explore routes), intention ants (propagate preferences)
- Pheromone concentration adjusts based on path quality; agents choose based on concentration

**Structural mapping**: The three ant types map to three phases of agent factory dispatch: (1) capability checking (can this model handle this task type?), (2) cost/quality estimation (what would this routing cost?), (3) commitment (assign and begin). The graph neural network enhancement maps to using embeddings of task descriptions and agent capabilities to initialize pheromone values, rather than starting from uniform priors.

---

## 4. Ecological Sensor Network Dashboards

### 4.1 NEON Data Portal

**NEON** (https://data.neonscience.org/)
- 81 field sites across 20 ecoclimatic domains (US, Alaska, Hawaii, Puerto Rico)
- 180+ data products from automated instruments, field technicians, airborne remote sensing
- Millions of data points daily from thousands of automated sensors

**Data quality architecture**:
- Raw measurement frequencies: 40 Hz to once per 5 minutes
- Aggregation intervals: typically 1-minute and 30-minute windows
- Quality flags: alpha metric (proportion failing any test), beta metric (proportion indeterminate)
- Final quality flag computed from thresholds on alpha and beta
- Expanded data package includes per-test pass/fail/indeterminate proportions

**Structural mapping**: NEON's quality flag architecture maps directly to agent output quality assessment:

| NEON Concept | Agent Factory Equivalent |
|---|---|
| Raw sensor measurement (40Hz) | Individual agent tool calls / token events |
| 1-minute aggregation | Per-task summary metrics |
| 30-minute aggregation | Per-sprint summary metrics |
| Alpha quality metric (% failing any test) | Agent error rate across quality checks |
| Beta quality metric (% indeterminate) | Agent output requiring human review |
| Final quality flag (threshold on alpha+beta) | Automated accept/review/reject decision |
| Quality test per measurement | Lint, type-check, test-pass per code change |
| Heterogeneous sensor types | Heterogeneous agent models (Claude, GPT, etc.) |

The critical architectural lesson from NEON is the **two-tier quality metric system** (alpha = definitely bad, beta = uncertain). This maps to agent factory QA where some outputs are detectably wrong (test failures) and others are uncertain (require human judgment). Meadowsyn should display both tiers distinctly.

### 4.2 Ocean Observatories Initiative (OOI)

**InteractiveOceans Data Portal** (https://interactiveoceans.washington.edu/data-portal/)
- Interface for OOI Regional Cabled Array data
- Datashader decimation for large time-series while preserving meaningful structure
- Cross-comparison of multiple instruments from anywhere on the array
- Real-time telemetered data from deployed instruments

**Datashader decimation** (https://interactiveoceans.washington.edu/glossary/data-shading/):
- Renders large datasets by binning data points into pixels
- Preserves the meaningful structure of time series at any zoom level
- Avoids overplotting that would hide patterns in dense data

**Structural mapping**: The Datashader approach is directly applicable to Meadowsyn. Agent telemetry at full resolution (every token, every tool call) is far too dense for human interpretation. Datashader-style decimation would render agent activity at the pixel level: each pixel column represents a time bin, pixel color represents the dominant activity state, and zooming in reveals finer-grained detail without requiring the full dataset to be loaded. The cross-instrument comparison (plotting salinity + temperature + CO2 + O2 from different sensors on the same time axis) maps exactly to cross-agent comparison (plotting throughput + error rate + cost + latency from different agents on the same time axis).

### 4.3 Sparse Heterogeneous Sensor Fusion

**Adaptive Distance Attention** (https://www.cambridge.org/core/journals/environmental-data-science/article/data-fusion-of-sparse-heterogeneous-and-mobile-sensor-devices-using-adaptive-distance-attention/14F5F461955D8FCBBAF0EEA3D29E45D2)
- Fuses measurements from sparse, heterogeneous, and mobile sensors
- Predicts values at locations with no previous measurement
- Handles non-overlapping multiple sources with different characteristics
- Addresses prediction of complex phenomena from sparse data

**Structural mapping**: Agent factory monitoring is inherently sparse and heterogeneous. Different agents report different metrics at different frequencies. Some agents are "mobile" (reassigned between task types). Adaptive distance attention could fuse these heterogeneous signals to produce a coherent fleet state estimate, including predicting the state of agents that haven't reported recently. This is particularly relevant for agents in long-running tasks that produce sparse output.

### 4.4 Digital Twins for Ecological Monitoring

**Digital twins for ecology** (https://www.sciencedirect.com/science/article/pii/S0169534723000903) -- Trends in Ecology & Evolution 2023
- Dynamic model-data fusion: continuously aligning computational models with real-world observations
- Combines sensor data, computational models, and domain knowledge
- Spatio-temporal alignment: data is synchronous in time and in the same coordinate system in space
- Knowledge graphs for representing understanding, carriers, and interactions

**Structural mapping**: The digital twin paradigm maps to Meadowsyn's core mission. The "physical system" is the agent fleet. The "digital twin" is Meadowsyn's internal model of fleet state. Continuous alignment means Meadowsyn should not just display data but maintain a model of fleet dynamics that is continuously updated with observations. Deviations between model predictions and observations are the interesting events that need human attention. The spatio-temporal alignment requirement maps to ensuring all agent telemetry is in a common time reference and a common task-space reference.

---

## 5. Protein Interaction Network Visualization

### 5.1 Cytoscape.js

**Cytoscape.js** (https://js.cytoscape.org/) -- 2023 update: Bioinformatics 39(1)
- Open-source JavaScript graph library, pure JS (no plugins), 67+ extensions
- Desktop and mobile browser support with built-in gestures (pinch-to-zoom, panning, box selection)
- Comfortably renders thousands of graph elements on average hardware

**Layout algorithms** (https://blog.js.cytoscape.org/2020/05/11/layouts/):
- **fCoSE** (Fast Compound Spring Embedder): best quality + fastest for compound graphs; 2x faster than CoSE with comparable aesthetics; supports constraints (fixed position, alignment, relative placement)
- **CoSE-Bilkent**: more sophisticated than basic CoSE, better defaults, more expensive
- **CoSE**: integrated into core library, fast but lacks enhancements
- **Euler**: physics simulation force-directed layout
- All three CoSE variants support compound (nested) graphs

**Compound nodes**: embed nodes within other nodes -- represent biological complexes and subunits. Parent-child relationship is normally immutable once established.

**Edge handling**: heterogeneous interaction types via styling system; edge bundling for highly-connected regions; opacity control for density management.

**Structural mapping**:

| Cytoscape.js Feature | Agent Factory Application |
|---|---|
| Compound nodes | Agent groups within sprint/team; tasks within epics; files within modules |
| Heterogeneous edge types | Different relationship types: "depends-on," "blocks," "reviews," "modifies-same-file" |
| fCoSE layout with constraints | Fix positions of key nodes (active sprint, current epic) while letting related nodes organize around them |
| Edge bundling | Bundle parallel dependency edges between modules to reduce visual noise |
| Box selection + filtering | Select a sprint's agents, filter to show only their interactions |
| 1000s of elements | Sufficient for agent factory graphs (dozens of agents, hundreds of tasks, thousands of edges) |

The fCoSE constraint system is particularly valuable: fixing the position of the current sprint node while allowing task and agent nodes to arrange themselves creates a stable spatial reference for operators while adapting to changing graph structure.

### 5.2 STRING Database Viewer

**STRING** (https://string-db.org/) -- STRING 12.5, Nucleic Acids Research 2025
- Protein association networks for 2000+ organisms
- Three distinct network types: functional, physical, regulatory -- viewable separately
- Interactive dot plot for enrichment analysis
- Web interface intended for small network inspection; Cytoscape integration (stringApp) for large networks

**Structural mapping**: STRING's three network types map to three views of agent factory relationships: (1) functional (agents that contribute to the same outcome), (2) physical (agents that share resources -- same codebase, same CI pipeline), (3) regulatory (agents whose output gates other agents' work). The ability to view these separately or overlaid is critical -- a sprint manager needs the functional view, an infrastructure operator needs the physical view, a quality reviewer needs the regulatory view.

### 5.3 BioGRID Network Viewer

**BioGRID** (https://thebiogrid.org/) -- v5.0.255
- 2.9M+ protein and genetic interactions, 31K+ chemical interactions
- Embedded Cytoscape.js viewer in every search result page
- Network layout: distance from center proportional to connectivity
- SVG export via BioGRID WebGraph for scalable graphics

**Structural mapping**: BioGRID's center-distance-by-connectivity layout is directly useful for agent factory visualization. The most-connected agent (the one involved in the most task dependencies, code review relationships, and shared file modifications) should be nearest the center. Peripheral agents are those with few connections -- potentially underutilized or working on isolated tasks. This layout immediately reveals the fleet's connectivity structure.

---

## 6. Epidemiological Dashboards

### 6.1 Nextstrain / Auspice

**Nextstrain** (https://nextstrain.org/) -- Hadfield et al., Bioinformatics 2018
- Real-time tracking of pathogen evolution via phylogenetic analysis + geographic mapping
- Open source: JavaScript (Auspice) + Python (Augur), GitHub: nextstrain/auspice

**Auspice architecture** (https://github.com/nextstrain/auspice):
- React + D3.js frontend with linked panels: phylogenetic tree, geographic map, genetic diversity
- `phylotree.change()` API: combines multiple visual changes into single D3 call per element class (efficient batch updates)
- Temporal slider: animates tree through time, showing evolution and geographic spread
- Streamtree rendering: transforms ribbons from weight-space to display-order space to pixel space
- Zooming in one panel updates all others (linked views)
- Performance: ~185ms for color changes on Ebola-scale trees, ~30ms animation ticks

**Key visualization features**:
- Rectangular and radial tree layouts
- Clock layout: divergence (y-axis) vs sampling date (x-axis) for temporal analysis
- Ancestral state reconstruction: inferred probability distributions at internal nodes
- Geographic transmission animation: arcs on map showing probable transmission events
- Confidence visualization: color gradients indicating uncertainty in ancestral state estimates

**Structural mapping -- task ancestry / agent lineage (genuine causal structure)**:

Nextstrain's phylogenetic tree is causally isomorphic to task lineage in an agent factory:

| Phylogenetic Concept | Agent Factory Equivalent | Causal Mechanism |
|---|---|---|
| Organism/isolate (leaf node) | Completed task / code change | The observable output |
| Internal node | Intermediate decision point (issue decomposition, PR split) | Inferred common ancestor of related work |
| Branch length (divergence) | Effort/complexity distance between related tasks | Longer branches = more divergent work |
| Clock layout (time on x-axis) | Task timeline (when work was done) | Temporal ordering of lineage |
| Clade (subtree) | Epic / work stream | All tasks descending from a common decomposition |
| Ancestral state reconstruction | Inferring the design decision that led to a work branch | Probabilistic reconstruction of "why this branch exists" |
| Geographic transmission | Task migration between agents / teams | Which agent "transmitted" a task pattern to another |
| Temporal slider animation | Sprint replay | Animate how the work tree grew over a sprint |
| Confidence intervals on nodes | Uncertainty about task relationships | Not all task lineages are clear; some are inferred |

The Auspice linked-panel pattern (tree + map + diversity) maps to Meadowsyn showing task lineage tree + agent assignment map + code diff diversity simultaneously. Interaction in any panel filters the others. The temporal slider animation is directly implementable: animate the growth of the task tree over a sprint, showing when tasks were created, claimed, completed, and how they relate.

**Streamtrees** (https://docs.nextstrain.org/projects/auspice/en/latest/advanced-functionality/streamtrees.html):
- Ribbon-based rendering showing population flow through a tree
- Weight-space to display-order space transformation
- Avoids branch crossings via careful rendering order

**Structural mapping**: Streamtrees could visualize workload flow through the task tree -- ribbon width proportional to effort (tokens, time, cost) flowing through each branch. This would instantly show which branches of work consume the most resources, and where effort is concentrated vs distributed.

### 6.2 HealthMap

**HealthMap** (https://www.healthmap.org/) -- Freifeld et al., JAMIA 2008
- Real-time disease surveillance aggregating news media, expert reports, official alerts
- Google Maps overlay with interactive filtering by source, disease, country
- Automated text mining and natural language interpretation for event classification
- Color-coded markers by event "noteworthiness" (composite of disease importance + news volume)
- Used by ECDC, CDC, WHO as complement to official surveillance

**Structural mapping**: HealthMap's real-time event aggregation from heterogeneous sources maps to Meadowsyn's need to aggregate signals from heterogeneous agent telemetry streams. The "noteworthiness" scoring (combining inherent severity with signal volume) maps directly to alert prioritization: an agent error in a critical path (high inherent severity) with multiple correlated signals (high volume) should be more prominent than an isolated low-severity anomaly. The text mining pipeline that classifies unstructured disease reports maps to classifying unstructured agent log output into structured event categories.

### 6.3 CDC Social Vulnerability Index (SVI)

**CDC SVI** (https://svi.cdc.gov/map.html)
- Place-based index quantifying community social vulnerability
- 16 Census variables grouped into 4 themes, combined into single overall score
- Interactive choropleth maps at census tract level within counties
- Percentile ranking: tracts ranked relative to peers in same year
- Temporal series: databases for 2000, 2010, 2014, 2016, 2018, 2020, 2022

**Structural mapping**: The SVI's composite index architecture -- multiple variables grouped into themes, themes combined into overall score -- maps to agent health scoring. Four "vulnerability themes" for agents could be: (1) performance (throughput, latency), (2) quality (error rate, test pass rate), (3) efficiency (cost per output, token waste), (4) coordination (blocking time, review turnaround). Each theme is a composite of multiple variables. The overall agent vulnerability score identifies which agents are most at risk of failure or degradation. Percentile ranking against peers (other agents of the same model/tier) avoids comparing unlike agents. The temporal series aspect enables tracking whether agent vulnerability is improving or worsening across sprints.

---

## Cross-Cutting Architectural Patterns

### Pattern 1: Linked Multi-Panel Views (from Auspice, NiiVue, FSLeyes, MNE)
Every mature biological visualization tool uses linked panels where interaction in one view filters/highlights all others. This is not optional for Meadowsyn -- it is the primary interaction pattern for exploring high-dimensional system state. Implementation: shared state store (React context or Redux) with bidirectional selection propagation.

### Pattern 2: Temporal Slider with Animation (from Auspice, MNE)
Temporal animation over a data dimension is the single most effective tool for understanding process dynamics. Auspice's temporal slider (with ~30ms animation tick) shows how a tree grew over time. MNE's scrolling browser shows how signals evolve. Meadowsyn needs both: a sprint replay slider (animate task tree growth) and a real-time scrolling view (monitor live agent activity).

### Pattern 3: Quality Flag Architecture (from NEON)
The two-tier quality system (alpha = definitely bad, beta = uncertain, final flag = threshold) is more sophisticated than binary pass/fail. Meadowsyn should adopt this: each agent output gets per-check results, aggregated into an alpha metric (% failing) and beta metric (% uncertain), with configurable thresholds for the final quality flag.

### Pattern 4: Datashader Decimation (from OOI InteractiveOceans)
For dense time-series data (agent telemetry at token granularity), render at pixel resolution using Datashader-style algorithms that preserve meaningful structure while avoiding overplotting. This is essential for the "system-wide activity heatmap" view.

### Pattern 5: Stigmergic Routing Display (from ant colony research)
Display routing weights as a continuously decaying gradient field overlaid on the task/agent graph. This is not metaphor -- the routing system IS a pheromone-like positive-feedback-with-decay system. Visualizing it as such reveals dynamics (exploration vs exploitation, convergence vs stagnation) that are invisible in tabular routing weight displays.

### Pattern 6: Compound Graph Layout (from Cytoscape.js fCoSE)
Use compound nodes (tasks within epics, agents within teams) with constraint-based force-directed layout. Fix positions of anchor nodes (current sprint, active epic) for spatial stability while allowing dependent nodes to self-organize. The fCoSE algorithm is the current best-in-class for this.

### Pattern 7: Phylogenetic Lineage Animation (from Nextstrain)
Task ancestry is a tree that grows over time. Animate its growth with Nextstrain-style temporal animation. Use streamtree ribbons to show effort flow. Use ancestral state reconstruction to infer decision points. This transforms the static task graph into a dynamic narrative of how work evolved.

---

## Recommended Technology Stack for Meadowsyn Bio-Viz Layer

| Component | Technology | Source Domain |
|---|---|---|
| Multi-channel time series | D3.js scrolling traces (MNE-style) | EEG analysis |
| Raster/heatmap view | RasterVis pattern (D3.js) | Neural population |
| Dimensionality reduction | umap-js (client-side) | Neural manifold |
| Graph layout | Cytoscape.js with fCoSE | Protein interaction |
| Tree visualization | Auspice phylotree (React + D3) | Epidemiology |
| Large time-series decimation | Datashader pattern (server-side) | Ocean observatory |
| Quality flags | NEON two-tier alpha/beta architecture | Ecological sensing |
| Routing dynamics | Pheromone gradient field (Canvas/WebGL) | Ant colony |
| Linked panels | React shared state + bidirectional selection | Neuroimaging |
| 3D embeddings | three.js point clouds | Neural trajectory |

---

## Key Sources

### Neural Population Activity
- [RasterVis](https://github.com/NeurophysVis/RasterVis) -- D3 raster plot web app
- [Rastermap](https://github.com/MouseLand/rastermap) -- Stringer & Pachitariu, Nature Neuroscience 2024
- [CEBRA](https://cebra.ai/) -- Schneider et al., Nature 2023
- [umap-js](https://github.com/PAIR-code/umap-js) -- Google PAIR JavaScript UMAP
- [NWB Explorer](https://github.com/MetaCell/nwb-explorer) -- Geppetto-based NWB viewer
- [Mesmerize](https://www.nature.com/articles/s41467-021-26550-y) -- calcium imaging platform
- [SpikeInterface](https://spikeinterface.readthedocs.io/) -- unified spike sorting framework
- [SortingView](https://github.com/magland/sortingview) -- web spike sorting curation

### EEG/fMRI Analysis
- [MNE-Python](https://mne.tools/) -- MEG/EEG analysis with interactive browser
- [NiiVue](https://github.com/niivue/niivue) -- WebGL2 neuroimaging viewer
- [FreeBrowse](https://github.com/freesurfer/freebrowse) -- web FreeView on NiiVue
- [FSLeyes](https://open.win.ox.ac.uk/pages/fsl/fsleyes/fsleyes/userdoc/overview.html) -- flexible panel neuroimaging viewer
- [Neuroscout](https://neuroscout.org/) -- fMRI analysis platform (Elife 2022)
- [LORIS](https://loris.ca/) -- longitudinal neuroinformatics web platform

### Ant Colony / Stigmergy
- [Ant Colony RL](https://github.com/jeffasante/ant-colony-rl) -- JavaScript ACO + Q-learning
- [Visualize-It ACO](https://visualize-it.github.io/ant_colony_optimization/simulation.html) -- browser ACO sim
- [NetLogo Ants](https://ccl.northwestern.edu/netlogo/models/Ants) -- classic stigmergy model
- [ACO Scholarpedia](http://www.scholarpedia.org/article/Ant_colony_optimization) -- formal reference
- [Heterogeneous ACO task allocation](https://www.oaepublish.com/articles/ir.2023.33) -- GNN + ACO
- [Stigmergy Wikipedia](https://en.wikipedia.org/wiki/Stigmergy) -- overview with software applications

### Ecological Sensor Networks
- [NEON Data Portal](https://data.neonscience.org/) -- 81-site ecological observatory
- [NEON Data Quality](http://data.neonscience.org/data-quality) -- quality flag architecture
- [InteractiveOceans](https://interactiveoceans.washington.edu/data-portal/) -- OOI Datashader portal
- [OOI Data Shading](https://interactiveoceans.washington.edu/glossary/data-shading/) -- decimation technique
- [Adaptive Distance Attention](https://www.cambridge.org/core/journals/environmental-data-science/article/data-fusion-of-sparse-heterogeneous-and-mobile-sensor-devices-using-adaptive-distance-attention/14F5F461955D8FCBBAF0EEA3D29E45D2) -- sparse sensor fusion
- [Digital Twins for Ecology](https://www.sciencedirect.com/science/article/pii/S0169534723000903) -- TREE 2023

### Protein Interaction Networks
- [Cytoscape.js](https://js.cytoscape.org/) -- graph library (Bioinformatics 2023 update)
- [fCoSE](https://github.com/iVis-at-Bilkent/cytoscape.js-fcose) -- fast compound spring embedder
- [Cytoscape.js layouts guide](https://blog.js.cytoscape.org/2020/05/11/layouts/) -- algorithm comparison
- [STRING 12.5](https://academic.oup.com/nar/article/53/D1/D730/7903368) -- NAR 2025
- [BioGRID](https://thebiogrid.org/) -- interaction database with Cytoscape.js viewer

### Epidemiological Dashboards
- [Nextstrain](https://nextstrain.org/) -- Hadfield et al., Bioinformatics 2018
- [Auspice](https://github.com/nextstrain/auspice) -- React+D3 phylogenetic visualization
- [Auspice Streamtrees](https://docs.nextstrain.org/projects/auspice/en/latest/advanced-functionality/streamtrees.html) -- ribbon rendering
- [HealthMap](https://www.healthmap.org/) -- real-time disease surveillance
- [CDC SVI](https://svi.cdc.gov/map.html) -- composite vulnerability index with temporal series
