---
agent: fd-agent-swarm-viz
mode: research
target: meadowsyn-frontier-research
timestamp: 2026-03-21
---

# Multi-Agent & Swarm Visualization Research for Meadowsyn

Deep research into visualization paradigms from drone fleet management, robotics, game AI, swarm intelligence, esports production, and space mission planning — mapped to the Meadowsyn agent factory frontend.

---

## 1. QGroundControl and Mission Planner: Drone Fleet Ground Stations

### QGroundControl (QGC)

**Repo:** [github.com/mavlink/qgroundcontrol](https://github.com/mavlink/qgroundcontrol) (Qt/QML, C++, MPL-2.0)

**Architecture — MultiVehicleManager pattern:**
QGC's core abstraction is the `MultiVehicleManager` singleton (`src/Vehicle/MultiVehicleManager.h`). When a MAVLink HEARTBEAT arrives on any link from a previously-unseen system ID, it instantiates a new `Vehicle` object. The manager tracks all vehicles, handles switching the "active vehicle," and manages removal. Each `Vehicle` exposes telemetry via Qt Q_PROPERTY bindings (RSSI, link quality, TX buffer, noise) that flow directly into QML panels.

**Concrete interaction patterns:**

| Pattern | QGC Implementation | Meadowsyn Mapping |
|---|---|---|
| **Vehicle state aggregation** | `MultiVehicleManager` auto-discovers vehicles from heartbeats; each Vehicle has a fact-based parameter system | Agent registry auto-discovers from bead claims; each agent has status/telemetry properties |
| **Active/inactive distinction** | Active vehicle is opaque, inactive vehicles are semi-transparent on the map. Vehicle IDs shown below icons. | Active agent (currently viewed) is full-opacity; background agents are dimmed with agent-ID labels |
| **Multi-vehicle command** | Multi-Vehicle View appears only when >1 vehicle connected. Commands (Pause, Start Mission) broadcast to all. | Fleet-wide controls: pause all, cancel sprint, redistribute work |
| **Geofence visualization** | Multiple polygonal/circular inclusion/exclusion fences per MAVLink GeoFence protocol, rendered on map | Constraint boundaries: token budget limits, file-scope restrictions, time windows rendered as visual regions |
| **Telemetry streams** | Q_PROPERTY for telemetryRRSSI, telemetryLRSSI, telemetryRXErrors etc. with QML signal bindings | Agent health metrics: tokens/min, error rate, latency, cost — streamed via WebSocket to React panels |
| **Plugin extensibility** | QGCCorePlugin system for customizing UI/vehicle configs without touching core | Meadowsyn extension panels via plugin API |

**Key source files:**
- `src/Vehicle/MultiVehicleManager.h/.cc` — fleet management singleton
- `src/Vehicle/Vehicle.h/.cc` — individual vehicle abstraction with telemetry properties
- `src/QmlControls/QGroundControlQmlGlobal.h` — QML bridge
- Plan View supports GeoFence/Rally Point protocol

**Docs:** [docs.qgroundcontrol.com](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/fly_view.html)

### Mission Planner (ArduPilot)

**Docs:** [ardupilot.org/planner/docs/swarming.html](https://ardupilot.org/planner/docs/swarming.html)

**Swarming model:**
Mission Planner implements multi-vehicle control by opening multiple serial MAVLink connections simultaneously. A "leader" drone's GPS position is offset and sent to "followers" as dynamic Guided-mode waypoints. Access via Ctrl+F > "Swarm" (beta).

**Concrete interaction patterns:**

| Pattern | Mission Planner Implementation | Meadowsyn Mapping |
|---|---|---|
| **Vehicle switching** | Ctrl+X dropdown to select which drone to control/view telemetry from | Agent selector dropdown — click to focus on one agent's context |
| **Leader-follower topology** | Leader broadcasts adjusted position; followers trail at set X/Y/Z offsets | Sprint orchestrator (Clavain) dispatches; worker agents follow assigned beads |
| **Telemetry log replay** | Full log playback, analysis, conversion in dedicated Telemetry Logs section | Session replay: scrub through agent execution history for post-mortem |
| **Flight Data Screen** | All telemetry displayed in single pane with HUD, map, instrument strips | Agent dashboard: unified view with map (file tree), instruments (token gauge, cost), HUD (current action) |

### Commercial Fleet Dashboards (for comparison)

**FlytBase** ([docs.flytbase.com](https://docs.flytbase.com/in-flight-modules/how-to-manage-your-flight-operations/fleet-management)):
Centralized dashboard with real-time telemetry, operational status, and health metrics per device. Operators see all drones on a single map with per-drone drill-down.

**AirHub** ([airhub.app](https://www.airhub.app/)):
Fleet management + compliance + situational awareness. Secure live streaming, in-platform chat, AI image recognition, combined feeds.

**Meadowsyn takeaway:** The commercial drone world has converged on a pattern: map overview with entity dots + drill-down sidebar + fleet-wide command bar + per-entity telemetry strip. This is the baseline layout Meadowsyn should adopt.

---

## 2. ROS 2 rqt and Foxglove Studio: Robotics Process Visualization

### ROS 2 rqt

**Docs:** [roboticsbackend.com/rqt-graph-visualize-and-debug-your-ros-graph/](https://roboticsbackend.com/rqt-graph-visualize-and-debug-your-ros-graph/)

**Core concept:** rqt_graph renders the ROS computation graph — nodes (circles) connected to topics (rectangles) via publish/subscribe edges. It auto-hides debug infrastructure (logging, plotting nodes) to reduce noise.

**Concrete interaction patterns:**

| Pattern | rqt Implementation | Meadowsyn Mapping |
|---|---|---|
| **Node-topic graph** | Circular nodes connected to rectangular topics; auto-layout via graphviz | Agent-channel graph: agent nodes connected to shared resources (repos, beads, file locks) |
| **Hide debug nodes** | Debug nodes hidden by default; uncheck boxes to reveal | Hide infrastructure agents (heartbeat, metrics) by default; toggle to show |
| **Highlighting** | Click a node to highlight its connections in complex graphs | Click an agent to highlight its bead dependencies, file touches, inter-agent messages |
| **Plugin framework** | rqt is a plugin framework: topic monitor, node monitor, service caller, parameter setter | Meadowsyn panel system: agent monitor, bead tracker, sprint planner, cost meter |

### Foxglove Studio

**Repo:** [github.com/foxglove/studio](https://github.com/foxglove/studio) (TypeScript, MPL-2.0)
**Docs:** [docs.foxglove.dev](https://docs.foxglove.dev/)

**Architecture:** Foxglove is an encoding-agnostic visualization platform. Data arrives via WebSocket (live) or MCAP files (recorded). The playback loop delivers messages in log-time order to panels. Panels are modular React components arranged in configurable layouts.

**Built-in panels (20+):**

| Panel | Function | Meadowsyn Equivalent |
|---|---|---|
| **3D Scene** | Point clouds, transforms, markers | File/repo spatial map with agent positions |
| **Plot** | Y-values vs timestamps, synchronized zoom | Token usage, cost, throughput over time |
| **State Transitions** | Discrete state changes over time (synced with Plot zoom) | Agent lifecycle: idle -> claimed -> running -> blocked -> done |
| **Log** | Timestamped log messages | Agent output stream, tool calls, errors |
| **Diagnostics** | Node health status (ROS-native) | Agent health: heartbeat freshness, error rate, memory |
| **Raw Messages** | JSON tree view of any message | Raw bead state, agent config, sprint parameters |
| **Image** | Camera feeds | Screenshot/diff panels from agent file edits |

**Extension API — the pattern Meadowsyn should adopt:**

Foxglove extensions register custom panels via `registerPanel()`. The `initPanel` function receives a `PanelExtensionContext` with:
- `context.onRender(renderState, done)` — called on each playback tick
- `context.subscribe(["/agent/status"])` — topic subscription
- `context.layout.addPanel()` — spawn sibling panels programmatically
- Panel Settings API for user-configurable knobs matching host app styling

Panels are framework-agnostic: React, vanilla DOM, or any frontend framework.

**MCAP (Message Capture Archive Protocol):**
The recording format. McapWriter creates an McapSink that subscribes to channels and writes messages to files. Schema registration, channel mapping, and message sequencing are automatic. This is the pattern for Meadowsyn's session recording: each agent session produces an MCAP-like archive that can be replayed in the dashboard.

**Time scrubbing / replay:**
The playback loop loads messages from the data source, logs them to channels, broadcasts the current playback time, and sleeps to maintain playback speed. The PlaybackControl capability lets the UI control playback over WebSocket. Zoom state synchronization across Plot and State Transitions panels enables correlated analysis.

**Meadowsyn direct application:** Foxglove's panel architecture is the closest prior art to what Meadowsyn needs. Key adaptations:
1. Replace ROS topics with agent event streams (bead state changes, tool calls, file edits)
2. Replace MCAP with session JSONL archives
3. Replace 3D Scene with a 2D repo/file spatial map
4. Keep the extension API pattern for user-contributed panels

---

## 3. Game AI Behavior Tree Visualizers

### Unity Behavior Tree Visualizer

**Repo:** [github.com/Yecats/UnityBehaviorTreeVisualizer](https://github.com/Yecats/UnityBehaviorTreeVisualizer)

Scans for active behavior trees in the scene, groups them in a dropdown for selection, draws a graph where **nodes light up showing which part of the tree is currently running**. Debug messages are displayed directly on nodes.

**State coloring pattern:**
- Running: highlighted/lit
- Success: green
- Failure: red
- Inactive: gray/dim

**Meadowsyn mapping:** Each agent's task decomposition (bead -> sub-beads -> tool calls) forms a tree. Visualize with the same coloring: running beads lit, completed green, failed red, queued gray.

### Unity Behavior (Official Package)

**Docs:** [docs.unity3d.com/Packages/com.unity.behavior@1.0/manual/behavior-graph.html](https://docs.unity3d.com/Packages/com.unity.behavior@1.0/manual/behavior-graph.html)

Unity's official behavior graph tool flows top-to-bottom with plain-language node labels. Real-time debugging visualization during Play mode. Pre-built node library for movement, detection, decision-making.

**Key design decision:** Human-readable graphs with plain-language nodes. Meadowsyn should label nodes with bead titles and tool names, not internal IDs.

### Unreal Engine Gameplay Debugger + BehaviorTree

**Docs:** [dev.epicgames.com/documentation/en-us/unreal-engine/ai-debugging-in-unreal-engine](https://dev.epicgames.com/documentation/en-us/unreal-engine/ai-debugging-in-unreal-engine)

**Concrete interaction patterns:**

| Pattern | UE Implementation | Meadowsyn Mapping |
|---|---|---|
| **Viewport overlay** | Press apostrophe key to toggle AI debug overlay on game viewport | Press hotkey to overlay agent debug info on the main dashboard |
| **Category cycling** | Numpad keys toggle between BehaviorTree, EQS, Perception views | Tab keys cycle between: task tree, resource usage, inter-agent comms |
| **Multi-agent debug** | Select different AI pawns to inspect their individual trees | Click different agents to inspect their bead trees |
| **Network replication** | Debug data replicates to clients in networked games | Debug data streams to Meadowsyn via WebSocket from remote agents |
| **Centralized debug** | BehaviorTree + EQS + Perception all in same overlay | Task tree + cost analysis + file context all in same panel |

### Halo 2 Behavior Tree (GDC 2005)

**Source:** [gamedeveloper.com - Handling Complexity in Halo 2 AI](https://www.gamedeveloper.com/programming/gdc-2005-proceeding-handling-complexity-in-the-i-halo-2-i-ai)

Damian Isla's seminal GDC 2005 talk introduced behavior trees to the games industry. The Halo 2 AI core behavior DAG contains ~50 behaviors. Key debug feature: `ai_render_emotions 1` console command renders an AI's perceived danger level above the character.

### The Division (GDC 2016)

**Source:** [gdcvault.com - AI Behavior Editing and Debugging in The Division](https://gdcvault.com/play/1023382/AI-Behavior-Editing-and-Debugging)
**PDF:** [Gillberg_Jonas_AI_Behavior_Editing.pdf](https://ubm-twvideo01.s3.amazonaws.com/o1/vault/gdc2016/Presentations/Gillberg_Jonas_AI_Behavior_Editing.pdf)

Jonas Gillberg (Massive/Ubisoft) demonstrated the Snowdrop engine's AI debug toolchain for managing complex NPC behaviors. Key innovation: **timeline rollback** — local servers simulate live instances, and developers can scrub backward through the behavior timeline to understand when/where issues arose. Shared tool for both programmers and designers.

**Meadowsyn critical takeaway:** Timeline rollback for agent sessions. When an agent fails, scrub back through its decision history to find the root cause. This is the session replay feature.

### AI Arborist (GDC 2017)

**Source:** [gdcvault.com - AI Arborist](https://www.gdcvault.com/play/1024218/AI-Arborist-Proper-Cultivation-and)
**PDF:** [Vehkala_AI Arborist.pdf](https://media.gdcvault.com/gdc2017/Presentations/Vehkala_AI%20Arborist.pdf)

Covers node decorators, interruptions, tree splitting, behavior prioritization, daemon behaviors, message passing, behavior locking, retry mechanisms, and debugging strategies. The talk addresses the "great splintering of variations" in BT implementations over 10+ years.

### Out of Sight, Out of Mind (GDC 2014)

**Source:** [gdcvault.com - Out of Sight, Out of Mind](https://www.gdcvault.com/play/1020590/Out-of-Sight-Out-of)

Three approaches to AI visualization:
1. **Turtle Rock Studios (Evolve):** Timeline-like view of AI state history
2. **Maxis (The Sims 4):** HTTP-based Game State Inspector — web dashboard querying game state remotely
3. **Guerrilla (Killzone: Shadow Fall):** ReView system for debugging multiplayer bot behavior

**Meadowsyn critical takeaway:** The Sims 4 Game State Inspector pattern (HTTP-based, web dashboard, remote query) is exactly the architecture Meadowsyn should use. The game engine exposes state via HTTP; the visualization is a separate web app.

### Web-Based Behavior Tree Tools

**Adobe Behavior Tree Visual Editor:**
- **Web app:** [opensource.adobe.com/behavior_tree_editor/](https://opensource.adobe.com/behavior_tree_editor/)
- **Repo:** [github.com/adobe/behavior_tree_editor](https://github.com/adobe/behavior_tree_editor)
- Browser-based, drag-and-drop node editor. Import/export JSON. Manual and automatic layout. Custom action nodes.

**Behavior3 Editor:**
- **Repo:** [github.com/behavior3/behavior3editor](https://github.com/behavior3/behavior3editor)
- Online visual editor for behavior trees. JSON serialization. [behaviortrees.com](https://www.behaviortrees.com/)

**Groot2 (BehaviorTree.CPP):**
- **Site:** [behaviortree.dev/groot/](https://www.behaviortree.dev/groot/)
- **Repo:** [github.com/BehaviorTree/Groot](https://github.com/BehaviorTree/Groot)
- Connects to running BT.CPP executor via IPC. Visualizes tree state in real-time. Records transitions for offline replay. PRO: blackboard visualization, breakpoints, fault injection. Most widely used BT library in the ROS2 ecosystem.

**Mistreevous (TypeScript):**
- **Repo:** [github.com/nikkorn/mistreevous](https://github.com/nikkorn/mistreevous)
- Lightweight TypeScript behaviour tree library for Node and browser. In-browser editor and tree visualiser. Can retrieve current state of every node — ideal for debugging running trees.

**Hierplane (Allen AI):**
- **Site:** [allenai.github.io/hierplane/](https://allenai.github.io/hierplane/)
- React tree visualization component. Import `Tree` component and pass tree data. Originally built for NLP parse trees but generalizes.

**Reagraph (WebGL):**
- **Repo:** [github.com/reaviz/reagraph](https://github.com/reaviz/reagraph)
- High-performance WebGL graph visualization for React. Tree layouts, force-directed layouts. Handles large graphs.

---

## 4. Swarm Intelligence Visualization

### Ant Colony Optimization (ACO) Interactive Demos

**Visualize It — ACO:**
- **URL:** [visualize-it.github.io/ant_colony_optimization/simulation.html](https://visualize-it.github.io/ant_colony_optimization/simulation.html)
- Browser simulation of ACO for TSP. Sliders for evaporation factor, pheromone influence, a priori influence. Stops after 200 iterations showing shortest path. Real-time parameter manipulation affects solution convergence.

**Visual ACO:**
- **URL:** [poolik.github.io/visual-aco/](https://poolik.github.io/visual-aco/)
- Web-based visualization of the ACO algorithm.

**Ant Colony RL:**
- **Repo:** [github.com/jeffasante/ant-colony-rl](https://github.com/jeffasante/ant-colony-rl)
- JavaScript simulation combining ant colonies with Q-learning. Real-time rendering of foraging, pheromone trails, and emergent swarm intelligence.

**RoboPol ACO Visualization:**
- **URL:** [robopol.sk/blog/aco-vizualizacia-tsp.html](http://www.robopol.sk/blog/aco-vizualizacia-tsp.html)
- Interactive visualization built with React/TypeScript + Rust compiled to WASM for near-native ACO computation speed.

**Meadowsyn mapping:** Pheromone trails map to "successful paths" through code. When multiple agents solve similar problems, visualize which file paths, tool sequences, and strategies accumulated the most "pheromone" (success signal). This creates an emergent visualization of which approaches the factory converges on.

### Particle Swarm Optimization (PSO) Demos

**pso-js:**
- **Repo:** [github.com/adamstirtan/pso-js](https://github.com/adamstirtan/pso-js)
- Interactive demo: drag mouse to set objective, sliders for Inertia, C1, C2 hyperparameters.

**psoViz (D3.js):**
- **Repo:** [github.com/MarcGumowski/psoViz](https://github.com/MarcGumowski/psoViz)
- D3.js visualization of particle behavior in PSO. Shows particles converging toward optima.

**PSO-visualization:**
- **Repo:** [github.com/brianshourd/PSO-visualization](https://github.com/brianshourd/PSO-visualization)
- JavaScript PSO visualization with function landscape rendering.

**Meadowsyn mapping:** Agents as particles in a solution space. Visualize agents exploring different approaches to a problem, with "velocity vectors" showing their current direction. Global best (factory consensus) and personal best (individual agent history) rendered as attractors.

### NetLogo Models

**NetLogo Ants:**
- **URL:** [ccl.northwestern.edu/netlogo/models/Ants](https://ccl.northwestern.edu/netlogo/models/Ants)
- Classic foraging model: ants follow simple rules, colony exhibits sophisticated collective behavior. Pheromone decay, trail reinforcement, food source depletion.

**NetLogo + GPT-4o (2025 paper):**
- **Repo:** [github.com/crjimene/swarm_gpt](https://github.com/crjimene/swarm_gpt)
- **Paper:** [arxiv.org/abs/2503.03800](https://arxiv.org/abs/2503.03800) — "Multi-Agent Systems Powered by Large Language Models: Applications in Swarm Intelligence"
- Integrates LLMs with NetLogo via Python extension. GPT-4o drives ant colony foraging and bird flocking simulations. Prompt-driven behavior generation enables adaptive agent responses.

**Meadowsyn mapping:** This is directly relevant — LLM-powered agents exhibiting swarm intelligence. The paper demonstrates that LLM agents can produce emergent coordination patterns. Meadowsyn could visualize similar emergence: agents independently choosing which beads to claim, but collectively covering the sprint backlog efficiently.

### SwarmJS

**Repo:** [github.com/m-abdulhak/SwarmJS](https://github.com/m-abdulhak/SwarmJS)
**Demo:** [m-abdulhak.github.io/SwarmJS](https://m-abdulhak.github.io/SwarmJS)
**Paper:** [ieeexplore.ieee.org/document/10416791/](https://ieeexplore.ieee.org/document/10416791/) — "SwarmJS: Swarm Robotics Simulation on the Web" (IEEE 2024)

Interactive 2D swarm robotics simulation platform using D3.js for rendering and React for UI. Users can modify control algorithms directly in the browser. Multiple scenes with configurable environment size, obstacles, robot count, sensors, actuators.

**Meadowsyn mapping:** The "modify controller in browser" pattern maps to Meadowsyn's routing configuration — adjust agent selection criteria, priority weights, and dispatch rules live and see how the swarm responds.

---

## 5. StarCraft 2 / OpenAI Five / Esports Spectator Interfaces

### StarCraft 2 Observer UI

**1217 Design SC2 Observer:**
- **URL:** [1217design.com/ui/](http://1217design.com/ui/)
- Key design insight: **the bottom third of the screen is wasted in tournaments.** Their streamlined interface shows information only when needed, creating an unobstructed view. Supply is the most important stat and is displayed next to player names; minerals/gas are hidden by default since spectators rarely check them except when casters call attention.

**Galaxy Observer UI Toolset:**
- **Repo:** [github.com/Ahli/Galaxy-Observer-UI](https://github.com/Ahli/Galaxy-Observer-UI)
- Toolset for creating Observer Interface files for StarCraft II / Heroes of the Storm.

**AhliObs SC2 Mod (GameHeart successor):**
- **Repo:** [github.com/Ahli/AhliObs-SC2-Mod](https://github.com/Ahli/AhliObs-SC2-Mod)
- Extension mod implementing WCS GameHeart with bug fixes and performance improvements. Production labels integrated into building status bars for observer control over display timing. Shows newest unit type built as a "tech level snapshot." Army value metrics preferred over supply counts for revealing advantage.

**Concrete interaction patterns:**

| Pattern | SC2 Observer | Meadowsyn Mapping |
|---|---|---|
| **Progressive disclosure** | Bottom third hidden; supply always visible; minerals/gas on-demand | Agent list always visible; detailed metrics on-demand per agent |
| **Production tab** | Toggle (D key) shows what each player is building | "Work in progress" panel shows what each agent is currently doing |
| **Tech snapshot icon** | Icon of newest unit type = quick tech level indicator | Icon of latest tool used = quick capability indicator per agent |
| **Army value > supply** | Army value metric more informative than supply count | "Impact score" (landed changes) more informative than "lines written" |
| **Fight recap** | Post-teamfight statistics panel | Post-sprint retrospective panel showing agent contributions |
| **Player color coding** | Consistent color per player across all views | Consistent color per agent across timeline, map, and metrics |

### MIT Overseer Project

**URL:** [cms.mit.edu/mit-overseer-observer-mod-starcraft-2/](https://cms.mit.edu/mit-overseer-observer-mod-starcraft-2/)
**Forum:** [tl.net/forum/sc2-maps/432781-mit-overseer-observer-mod](https://tl.net/forum/sc2-maps/432781-mit-overseer-observer-mod)

MIT Game Lab research project. Design goal: provide casters with real-time graphics that show past events and anticipate near-future outcomes.

**Key design decisions:**
- Large fonts for legibility on low-bitrate video streams
- Minimal textures, rounded corners, transparency — optimized for compression
- Unit Infopanel hidden when graphs are called up (mutual exclusion to reduce clutter)
- When any upgrade has <30 seconds to completion: large icon + text description + numerical countdown + progress bar appears

**Meadowsyn mapping:** When an agent is close to completing a bead (e.g., tests passing, PR ready), show a prominent completion countdown. Mutual exclusion between detail panels prevents cognitive overload.

### Dota 2 Spectator System

**Docs:** [liquipedia.net/dota2/Spectating](https://liquipedia.net/dota2/Spectating)

**Camera modes for different viewer needs:**
- **Directed Camera:** Automatically follows important events — Meadowsyn equivalent: auto-focus on failing agents, blocking dependencies, sprint milestones
- **Free Camera:** Full manual control — Meadowsyn: manual agent/file navigation
- **Player Perspective:** See from one player's viewpoint — Meadowsyn: see the agent's context window, tool calls, reasoning
- **Hero Chase:** Follow one hero — Meadowsyn: lock view to one agent across all panels

**Information layers:**
- **Fight Recap:** Post-teamfight stats popup
- **Experience/Gold Graph:** Disparity between teams over time
- **Item progression notifications:** Alert when players buy notable items
- **Broadcaster selection:** Choose from 6 commentators

**DotaTV:** Observer client with full game visibility but no participation.

### OpenAI Five

**Paper:** [arxiv.org/abs/1912.06680](https://arxiv.org/abs/1912.06680) — "Dota 2 with Large Scale Deep Reinforcement Learning"
**Blog:** [openai.com/index/openai-five/](https://openai.com/index/openai-five/)

Each timestep, OpenAI Five receives ~20,000 floating-point numbers representing the full game state. The system plays 180 years of games per day via self-play.

**Visualization relevance:** The challenge of presenting 20,000 state dimensions to human viewers was solved by Dota 2's existing spectator interface — the game already had the visual language. For Meadowsyn, the lesson is: **build the visual language first** (what does an agent look like? what does a bead look like? what does a dependency edge look like?) and then the telemetry maps into it naturally.

### Esports Spectator Research

**Chalmers Thesis — "Designing Spectator Interfaces for Competitive Video Games":**
- **PDF:** [publications.lib.chalmers.se/records/fulltext/224247/224247.pdf](https://publications.lib.chalmers.se/records/fulltext/224247/224247.pdf)
- Analyzes SC2, Hearthstone, Dota 2, CS:GO spectator interfaces. Produces redesigns for each. Comparative evaluation of abstract vs detailed visualizations finds no single best approach — different tasks require different abstraction levels.

**ggViz — Large-Scale Esports Analysis:**
- **Paper:** [arxiv.org/abs/2107.06495](https://arxiv.org/abs/2107.06495)
- Visual analytics system for querying esports datasets through "game state sketches." Fast retrieval over 10M+ game states in seconds. Uses navigation mesh tokenization for spatial state encoding. Includes win probability charts, round icons, heatmap summarization.
- **Meadowsyn mapping:** "Agent state sketches" — draw a pattern (e.g., "agent stuck in retry loop on test file") and find similar historical states across all sessions.

**Real-Time Dashboards for Esports Spectating (CHI PLAY 2018):**
- **DOI:** [dl.acm.org/doi/10.1145/3242671.3242680](https://dl.acm.org/doi/10.1145/3242671.3242680)
- Dashboards for League of Legends and CS:GO improve spectator insight but require careful cognitive load management.

**Key research finding:** There is no single visualization that is equally useful for all analysis tasks. Meadowsyn must support multiple views (overview, detailed, timeline, spatial) and let users switch fluidly.

---

## 6. NASA JPL MSLICE / PLEXIL / ASPEN / EUROPA / RSVP

### MSLICE (Mars Science Laboratory InterfaCE)

**Paper:** [ntrs.nasa.gov/citations/20090032136](https://ntrs.nasa.gov/citations/20090032136) — "MSLICE Science Activity Planner for the Mars Science Laboratory Mission"

Tool for scientists and engineers on the MSL/Curiosity mission to collaboratively plan activities and visualize returned data.

**Concrete interaction patterns:**

| Pattern | MSLICE | Meadowsyn Mapping |
|---|---|---|
| **Constraint modeling** | Power, data volume, duration modeled per activity; violations reported | Token budget, time budget, file-lock conflicts modeled per bead |
| **Collaborative targeting** | Scientists name features on Mars surface; targets convey instrument-pointing | Developers tag files/functions of interest; tags convey agent focus areas |
| **Timeline planning** | Users develop a plan for a given Sol (Martian day); input constraints between activities | Sprint planning: develop bead assignments for a sprint; input dependency constraints |
| **Violation reporting** | Engineering and science constraints checked; violations surfaced | Budget overruns, dependency cycles, scope conflicts surfaced |

### RSVP (Robot Sequencing and Visualization Platform)

**URL:** [www-robotics.jpl.nasa.gov - RSVP Mars 2020](https://www-robotics.jpl.nasa.gov/what-we-do/flight-projects/mars-2020-rover/rsvp-mars-2020/)

Primary tool for operating Mars 2020 Perseverance. The RSVP suite includes:
- **RoSE (Rover Sequence Editor):** GUI for all commands in the mission command dictionary + simulation for resource computation and sequence validation
- **HyperDrive:** 3D graphics interface for stereo images and terrain models; plans driving and arm motions
- **ArmSketch/MobSketch:** Auto-generate command sequences from higher-level intent
- **SSim (Surface Simulation):** Uses flight software to predict rover response to commands in simulated Mars

**5-hour timeline requirement:** The tools are designed for rapid turnaround — a Sol's worth of commands must be authored, validated, and transmitted within 5 hours.

**Meadowsyn mapping:**
- RoSE -> Sprint command editor (bead creation, assignment, dependency specification)
- SSim -> Sprint simulation (predict agent behavior, estimate costs, detect conflicts before dispatch)
- 5-hour timeline -> Sprint cadence constraint (plan, validate, dispatch within the sprint window)

### PLEXIL (Plan Execution Interchange Language)

**GitHub:** [github.com/nasa/PLEXIL5](https://github.com/nasa/PLEXIL5) (NASA open source)
**Wiki:** [plexil.sourceforge.net](https://plexil.sourceforge.net/wiki/index.php/Main_Page)
**Wikipedia:** [en.wikipedia.org/wiki/PLEXIL](https://en.wikipedia.org/wiki/PLEXIL)

Synchronous language for commanding and monitoring autonomous systems. Used on: NASA K10 rover, Mars Curiosity drill, Deep Space Habitat, LADEE, ISS Autonomy Operating System.

**PLEXIL5 Visualization:**
Java-based GUI using model-view-controller pattern. The model represents hierarchical plan structure, execution behavior, and external environment. The view renders tree-like plan structures. Features:
- Formula editing and counterexample visualization (model checking)
- Interactive simulation at different granularity levels
- Random initialization of external environment variables for testing

**Concrete interaction patterns:**

| Pattern | PLEXIL | Meadowsyn Mapping |
|---|---|---|
| **Hierarchical plan tree** | Plans are trees of nodes with states (Waiting, Executing, Finished, Failed) | Bead hierarchy: epic -> story -> task with states (queued, claimed, running, done, failed) |
| **Node state machine** | Each node transitions through well-defined states with guards | Each bead transitions through lifecycle states with constraint guards |
| **Constraint guards** | Pre/post conditions, invariant conditions on each node | Entry criteria (dependencies met), exit criteria (tests pass), invariants (budget remaining) |
| **Formal verification** | Model-checking plans for safety properties before execution | Sprint validation: check for deadlocks, dependency cycles, budget violations before dispatch |
| **Multi-granularity simulation** | Step through plan at macro or micro level | Step through sprint at bead level or tool-call level |

### ASPEN (Automated Scheduling Planning Environment)

**URL:** [ai.jpl.nasa.gov/public/projects/aspen/](https://ai.jpl.nasa.gov/public/projects/aspen/)
**Paper:** [researchgate.net - ASPEN](https://www.researchgate.net/publication/2431151_ASPEN_-_Automated_Planning_and_Scheduling_for_Space_Mission_Operations)

Timeline-based scheduling framework with modular, reconfigurable components: expressive modeling language, resource management system, temporal reasoning system, graphical interface. Used on DS-1, EO-1 satellites, and for coordinated multi-rover planning.

**Key capability:** Operations, spacecraft, science, and other constraints incorporated in a unified automated scheduling environment. Supports surface rover planning, ground antenna scheduling, and **coordinated multiple rover planning**.

**Meadowsyn mapping:** ASPEN's timeline-based view with resource tracks (power, data volume, time) maps directly to a sprint timeline with resource tracks (token budget, time budget, file locks, model availability).

### EUROPA (Extensible Universal Remote Operations Planning Architecture)

**GitHub:** [github.com/nasa/europa](https://github.com/nasa/europa)
**Wiki:** [github.com/nasa/europa/wiki](https://github.com/nasa/europa/wiki/What-Is-Europa)

Constraint-based temporal planning framework. The Plan Database integrates representations for actions, states, objects, and constraints with algorithms for automated reasoning, propagation, querying, and manipulation.

**Concrete features:**
- Timeline representation of plans
- Constraint propagation and conflict resolution
- Debugger for instrumentation and visualization
- Flaw detection and resolution

**Meadowsyn mapping:** EUROPA's constraint propagation is the model for Meadowsyn's dependency resolution. When Agent A claims a file that Agent B needs, the constraint system detects the conflict and the visualization highlights it — exactly like EUROPA's flaw detection.

### Copilot + Crosscheck (Mars 2020)

**URL:** [ai.jpl.nasa.gov/public/projects/m2020-scheduler/](https://ai.jpl.nasa.gov/public/projects/m2020-scheduler/)

Copilot auto-schedules preheat and maintenance activities. When activities fail to schedule, **Crosscheck** shows the user which constraints would be violated, giving insight into how to modify inputs.

**Meadowsyn critical takeaway:** When the dispatcher cannot assign a bead (all agents busy, dependencies unmet, budget exhausted), show the user exactly which constraints blocked it — the Crosscheck pattern. This is the "why can't this work start?" explainer.

---

## Synthesis: Meadowsyn Architecture Recommendations

### Primary Layout (from drone fleet convergence)

```
+------------------------------------------------------------------+
|  Fleet Command Bar (pause all, sprint controls, global metrics)  |
+------------------+-----------------------------------------------+
|                  |                                                 |
|  Agent List      |  Main View (switchable)                        |
|  (sidebar)       |    - Spatial map (file/repo topology)          |
|                  |    - Timeline (Gantt-like sprint view)         |
|  Per-agent:      |    - Task tree (behavior tree of current bead) |
|  - Status dot    |    - Session replay (time-scrubbing)           |
|  - Current bead  |                                                 |
|  - Token gauge   |                                                 |
|  - Health        |                                                 |
|                  +-----------------------------------------------+
|                  |  Telemetry Strip (bottom, toggleable)           |
|                  |    - Token usage plot (synced zoom)             |
|                  |    - State transitions (synced zoom)            |
|                  |    - Cost accumulation                          |
+------------------+-----------------------------------------------+
```

### Key Interaction Patterns to Implement

1. **Auto-discovery** (QGC MultiVehicleManager): Agents appear when they heartbeat; disappear when they go silent.

2. **Camera modes** (Dota 2): Directed (auto-focus on interesting events), Free (manual navigation), Agent Perspective (see what the agent sees), Agent Chase (lock all panels to one agent).

3. **Progressive disclosure** (SC2 Observer): Show only agent names + status dots by default. Drill down on click. Hide infrastructure noise.

4. **Behavior tree overlay** (Unreal/Unity): Visualize bead decomposition as a tree with running/done/failed coloring.

5. **Timeline rollback** (The Division): Scrub backward through agent decision history. "Why did it do that?"

6. **Constraint explanation** (NASA Crosscheck): When work is blocked, explain exactly which constraints prevent progress.

7. **Synchronized time-series** (Foxglove): Plot + State Transitions panels share zoom state for correlated analysis.

8. **Extension API** (Foxglove): Let users build custom panels with `registerPanel({ initPanel: (context) => ... })`.

9. **Pheromone trails** (ACO): Visualize which code paths and strategies the swarm converges on over time.

10. **Swarm parameter tuning** (SwarmJS/PSO): Live sliders for routing weights, priority functions, dispatch rules.

### Technology Stack Alignment

| Component | Prior Art | Meadowsyn Tech |
|---|---|---|
| Panel system | Foxglove Extension API | React + custom PanelContext |
| Graph rendering | Reagraph (WebGL), rqt_graph | Reagraph or react-flow |
| Tree visualization | Hierplane, Groot, Mistreevous | Hierplane or custom D3 tree |
| Time-series plots | Foxglove Plot panel | uPlot or Recharts (synced zoom) |
| Spatial map | QGC map view, SwarmJS | react-flow or custom canvas |
| Data transport | Foxglove WebSocket protocol | WebSocket + JSONL |
| Session recording | MCAP format | JSONL archives (existing) |
| Constraint solver | NASA EUROPA | Custom constraint propagation |

### Open Source Libraries to Evaluate

| Library | Repo | Use Case |
|---|---|---|
| Foxglove Studio | [github.com/foxglove/studio](https://github.com/foxglove/studio) | Panel architecture reference, possibly fork |
| Reagraph | [github.com/reaviz/reagraph](https://github.com/reaviz/reagraph) | WebGL graph rendering for agent topology |
| Hierplane | [allenai.github.io/hierplane/](https://allenai.github.io/hierplane/) | Tree visualization for bead decomposition |
| Mistreevous | [github.com/nikkorn/mistreevous](https://github.com/nikkorn/mistreevous) | BT library with built-in browser visualizer |
| Adobe BT Editor | [github.com/adobe/behavior_tree_editor](https://github.com/adobe/behavior_tree_editor) | Visual tree editor pattern |
| Behavior3 Editor | [github.com/behavior3/behavior3editor](https://github.com/behavior3/behavior3editor) | Online visual BT editor |
| SwarmJS | [github.com/m-abdulhak/SwarmJS](https://github.com/m-abdulhak/SwarmJS) | Swarm simulation interaction patterns |
| Galaxy Observer UI | [github.com/Ahli/Galaxy-Observer-UI](https://github.com/Ahli/Galaxy-Observer-UI) | SC2 observer interface toolset |
| NASA EUROPA | [github.com/nasa/europa](https://github.com/nasa/europa) | Constraint-based planning reference |
| NASA PLEXIL5 | [github.com/nasa/PLEXIL5](https://github.com/nasa/PLEXIL5) | Plan execution visualization reference |

### Research Papers to Reference

| Paper | Citation | Relevance |
|---|---|---|
| Designing Spectator Interfaces | Carlsson & Pelling, Chalmers 2015 | Information hierarchy for non-expert viewers |
| ggViz | Xenopoulos et al., CHI PLAY 2022 | Sketch-based game state retrieval at scale |
| Real-Time Dashboards for Esports | CHI PLAY 2018 | Cognitive load management in dashboards |
| Multi-Agent Systems + LLMs + Swarm | arxiv 2503.03800, 2025 | LLM agents exhibiting swarm intelligence |
| SwarmJS | IEEE IROS 2024 | Browser-based swarm simulation platform |
| Handling Complexity in Halo 2 AI | Isla, GDC 2005 | Foundational behavior tree architecture |
| AI in The Division | Gillberg, GDC 2016 | Timeline rollback for AI debugging |
| AI Arborist | Vehkala et al., GDC 2017 | BT best practices and debugging |
| ASPEN | JPL/NASA | Timeline-based multi-mission scheduling |
| EUROPA | NASA Ames | Constraint-based temporal planning |

### Bonus: Modern AI Agent Observability (2024-2025)

The multi-agent AI world is building its own observability layer in parallel:

**LangSmith + LangGraph:** Full trace visibility of multi-agent execution. Every node, LLM call, tool result captured. Custom dashboards track token usage, latency (P50, P99), error rates, cost breakdowns. A single request can trigger 10-30 LLM calls across multiple agents.

**CrewAI:** Centralized dashboard with real-time tracing of every step: task interpretation, tool calls, validation, final output.

**Key pattern from this space:** Prometheus metrics per agent pod (latency, cost, tokens) + Kafka/RabbitMQ for inter-agent event passing + trace visualization as the primary debugging interface. Meadowsyn should expose these same three layers: metrics, events, traces.
