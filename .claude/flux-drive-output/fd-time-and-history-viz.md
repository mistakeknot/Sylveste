---
agent: fd-time-and-history-viz
mode: research
target: meadowsyn-frontier-research
timestamp: 2026-03-21
---

# Temporal Data Visualization for Meadowsyn: Frontier Research

Deep research into six domains of temporal visualization, assessed for applicability to Meadowsyn -- a public-facing web visualization frontend for an AI agent factory running dozens of simultaneous autonomous software development agents.

---

## 1. Git History Visualizers

### Gource

- **Source**: https://gource.io/ | https://github.com/acaudwell/Gource
- **Technique**: Animated tree layout where the root directory sits at center, directories appear as branches, and files as leaves. Contributors appear as avatars working on the tree at their contribution timestamps. Time scrubs forward automatically; users can pause, resume, and inspect.
- **Multi-repo support**: Multiple repositories can be combined into a single visualization by adding a sed-based parent directory prefix to file paths per repo, plus `--hide-root` to visually separate project trees. This is directly analogous to showing multiple agents working on distinct repositories simultaneously.
- **Meadowsyn mapping**: Gource's animation model -- entities (agents) moving between resources (files) over time -- maps directly to "which agent touched which files when." The camera-tracking mode (toggle with middle mouse) auto-focuses on activity hotspots, which could translate to auto-focusing on the busiest agent in the factory. Limitation: Gource is a native OpenGL application, not embeddable in a browser. Would need either (a) pre-rendered video export or (b) a WebGL reimplementation of the particle-tree metaphor.

### GitGraph.js

- **Source**: https://github.com/nicoespeon/gitgraph.js | npm `@gitgraph/js`, `@gitgraph/react`
- **Technique**: Programmatic JavaScript library to draw git-style DAG (directed acyclic graph) diagrams. Defines `commit()`, `branch()`, `merge()` operations that render as colored swim-lane lines with commit nodes. Supports commit messages in tooltips, branch styling, fast-forward merge options, and click callbacks on commits.
- **Architecture**: Modular -- `@gitgraph/core` contains the rendering-agnostic logic; rendering libraries wrap it for vanilla JS, React, or SVG/canvas targets. Custom DOM diff minimizes redraws.
- **Meadowsyn mapping**: Directly applicable for rendering agent work lineage as a git-style graph. Each agent's work stream becomes a branch; merge events represent integration points. The React wrapper (`@gitgraph/react`) fits Meadowsyn's likely React/Next.js stack. The programmatic API means data can be driven from Demarch's event log rather than a real git repo.
- **Limitation**: The original project is archived. The core library is stable but unmaintained. Consider forking or using the rendering-agnostic core with a custom renderer.

### GitHub Network Graph

- **Source**: https://github.blog/2008-04-10-say-hello-to-the-network-graph-visualizer/ | GitHub Docs
- **Technique**: Horizontal timeline with each user/fork as a row. The original repo's main branch is a horizontal line; forks appear as lines branching off. Commits are dots; merge points connect lines. Up to 100 most recently pushed branches displayed.
- **Meadowsyn mapping**: The "fork = agent, main = integration branch" metaphor works well. The horizontal swim-lane per agent model is the most natural layout for Meadowsyn's "factory floor" view. GitHub's implementation is closed-source but the interaction pattern (horizontal scroll through time, vertical scan across actors) is the gold standard for parallel-stream temporal visualization.

### VisFork (Research)

- **Source**: Chen et al., "Use the Forks, Look! Visualizations for Exploring Fork Ecosystems" (2024) | https://jacobkrueger.github.io/assets/papers/Chen2024ForkVis.pdf
- **Technique**: Interactive date slider that animates the collaboration network over time. Nodes represent contributors (gray) and forks (green); edges represent contributions. Play button auto-advances the date to show evolution. Commit history visualization tracks fork divergence chronologically.
- **Meadowsyn mapping**: The date-slider-driven network animation is the exact interaction model Meadowsyn needs for "what the factory did today." The collaboration-network view (which agents touched which repos, and when) translates directly. User study found it superior to GitHub's network graph for understanding temporal dynamics.

### git-of-theseus

- **Source**: https://github.com/erikbern/git-of-theseus | Erik Bernhardsson's blog
- **Technique**: Produces stacked area charts showing code age cohorts over time (how much code from each year survives), author contribution percentages, and survival curves (what % of lines from a commit survive after N years). Uses Python + matplotlib.
- **Meadowsyn mapping**: The "code survival" visualization answers "how much of each agent's work persists vs. gets replaced by other agents?" This is a powerful narrative for Meadowsyn: showing that the factory's code evolves through continuous agent iteration, not just accretion. The cohort stacked-area chart could be adapted to show "code contributed by agent X still in codebase."

### Hercules (src-d)

- **Source**: https://github.com/src-d/hercules
- **Technique**: Fast Go-based git history analyzer producing burndown charts (lines surviving over time), developer coupling matrices, and file coupling graphs. Uses a DAG of analysis tasks over full commit history. Output visualized via Python `labours` script.
- **Meadowsyn mapping**: Burndown analysis per agent would show which agents write durable code vs. churn-heavy code. The coupling analysis reveals which agents' work overlaps, useful for showing factory coordination patterns. Performance is excellent (Go + go-git), suitable for real-time analysis of active repos.

---

## 2. Financial Terminal Temporal Displays

### Bloomberg Terminal Charting

- **Source**: https://www.bloomberg.com/professional/products/bloomberg-terminal/charts/
- **Technique**: Candlestick charts with multiple overlay studies at different granularities. Key patterns: (a) Multi-timeframe confirmation -- a bullish pattern on a daily chart gains weight if confirmed on hourly charts. (b) Event markers overlaid on price series (news, earnings). (c) Adjustable time range with presets (1D, 1M, YTD, custom). (d) Coloring and thickness encoding for volume/significance.
- **Anti-overplotting**: Bloomberg handles multiple simultaneous time-series by: separate panes with synchronized x-axis (time), selective overlay toggling, and granularity auto-adjustment (axis labels change from minutes to hours to days as you zoom).
- **Meadowsyn mapping**: Agent metrics (tokens/minute, cost/hour, commits/hour) are continuous time series analogous to stock prices. The multi-pane synchronized view (agents in separate swim lanes but sharing a time axis) with event markers (deployments, failures, bead state changes) is the core Meadowsyn interaction model. Bloomberg's XR exploration (viewing 3D data to escape 2D overplotting) hints at future directions.

### TradingView Lightweight Charts

- **Source**: https://github.com/tradingview/lightweight-charts | Apache 2.0 license
- **Technique**: HTML5 canvas-based financial charting in 35KB gzipped. Renders candlestick, line, area, bar series. Supports custom plugins for volume profiles, order book heatmaps, and indicator overlays. Touch-optimized for mobile.
- **Multi-timeframe handling**: TradingView's ecosystem has extensive multi-timeframe overlay indicators: HTF Candle Stack (non-overlapping higher-timeframe boxes on lower-timeframe charts), Moving Average stacking across 1m/5m/1h/1d/1w/1m, and Volume Zones Multi-Timeframe overlays.
- **Performance**: Stays responsive with thousands of bars and multiple updates per second. Canvas rendering avoids DOM overhead.
- **Meadowsyn mapping**: This is the strongest candidate for Meadowsyn's metric panels. Apache 2.0 license, tiny footprint, excellent performance. Agent cost-per-minute as a candlestick series, token consumption as area charts, with custom plugins for "agent activity" overlays. The multi-timeframe pattern (show today's detail with this week's context) is exactly what a factory dashboard needs.

### OpenBB

- **Source**: https://openbb.co/ | open-source financial analysis platform
- **Technique**: Open-source Bloomberg alternative with custom dashboard widgets, chart generation from raw data, modular API-first architecture. Combines real-time data fetching with interactive visualization.
- **Meadowsyn mapping**: OpenBB's dashboard-building approach (drag-and-drop widget placement, flexible data source integration) is a design reference for Meadowsyn's customizable factory views. The "Open Data Platform" concept (connect once, use everywhere) parallels Meadowsyn consuming Demarch's event streams.

### Sparklines and Small Multiples (Tufte)

- **Source**: Edward Tufte, "Beautiful Evidence" (2006) | https://www.edwardtufte.com/notebook/sparkline-theory-and-practice-edward-tufte/
- **Technique**: Word-sized, context-free time series ("datawords") embedded inline with text. Maximize data density, minimize non-data ink, exploit the shrink principle. Small multiples: postage-stamp-sized identical charts indexed by category, sequenced over time like movie frames.
- **Meadowsyn mapping**: The agent roster sidebar could use sparklines to show each agent's activity trend at a glance -- 32 agents, each with a tiny line showing tokens/hour over the last 24h, all scannable in one view. Small multiples would work for comparative agent performance: identical chart template, one per agent, arranged in a grid. This is the anti-overplotting answer for 32+ simultaneous agents.

### Grafana Time Series + State Timeline

- **Source**: https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/time-series/ | https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/state-timeline/
- **Technique**: Time series panels with cross-panel linked dashboards, annotations as vertical event markers, and data links for drill-through. State Timeline renders discrete states as horizontal swim-lane bands -- each entity gets its own lane with color-coded state regions. Supports pagination for many series.
- **Anti-overplotting**: Separate synchronized panes, annotation tag filtering, and state timeline's inherently non-overlapping swim lanes.
- **Meadowsyn mapping**: Grafana's State Timeline is the exact visual for "agent status over time" -- each agent as a swim lane, colored by state (idle=gray, working=green, blocked=red, deploying=blue). Annotations mark factory-wide events. The dashboard linking pattern (click agent -> drill to agent detail) is the navigation model. However, embedding Grafana panels in a custom frontend requires Grafana's embedding API or recreating the visualization patterns.

---

## 3. Event Sourcing Replay UIs

### Redux DevTools Time Travel

- **Source**: https://github.com/reduxjs/redux-devtools
- **Technique**: Records every dispatched action and resulting state snapshot. Users click any action in a scrollable list to jump to that state. Can cancel/skip actions in the middle of the list; Redux rebuilds state from the remaining action sequence. Supports editing past actions to explore "what if" scenarios.
- **Interaction model**: Action list panel (left) + state inspector (right) + live UI preview. DockMonitor provides resizable/moveable dock. LogMonitor shows chronological state+action log. Users can "lock" the action list to prevent new actions from appearing during inspection.
- **Meadowsyn mapping**: The "action = agent event, state = factory state" analogy is direct. A sidebar showing chronological agent events (bead-claim, commit, test-pass, bead-close) with click-to-jump-to-state would let observers replay factory activity. The "skip action in the middle" pattern could support "what if agent X hadn't claimed this bead?" analysis.

### Temporal.io Workflow Replay Debugger

- **Source**: https://github.com/phuongdnguyen/temporal-workflow-replay-debugger | https://docs.temporal.io/web-ui
- **Technique**: Reconstructs workflow execution from event history. VS Code extension: enter Workflow ID, set breakpoints on code or history events, step through execution. Web UI provides Timeline View (flow of events in time), Compact View (linear progression of event groups), and detailed event inspection.
- **Interaction model**: The Timeline View shows event groups laid out temporally, with visual indicators for activity scheduling, execution, and completion. Clicking into events shows full payloads. The Compact View provides a left-to-right progression useful for quick scanning.
- **Meadowsyn mapping**: Temporal's workflow model closely mirrors Demarch's bead lifecycle (created -> claimed -> in_progress -> completed). The Timeline View's event-group rendering is directly applicable to visualizing bead state transitions. The "replay debugger" concept supports Meadowsyn's post-hoc analysis: replay what happened in a failed bead to understand why.

### EventStoreDB Admin UI / Kurrent Navigator

- **Source**: https://developers.eventstore.com/server/v24.10/features/admin-ui | http://localhost:2113
- **Technique**: Web-based stream browser showing recently created/changed event streams. Event details panel shows full payload. Projection management with start/stop/debug controls. Search with filterable columns, tag visualization, time-based filtering, and auto-composable queries.
- **Interaction model**: Browse streams -> drill into events -> inspect payloads. Dashboard shows active queues with statistics. The interface is transitioning to the "Event Store Navigator" app with improved usability.
- **Meadowsyn mapping**: The stream-browser metaphor maps to Meadowsyn's "per-agent event stream" view. The composable query interface (filter by event type, time range, tags) is exactly what an observer needs to drill into factory activity. However, the legacy UI is reaching end-of-life; the Navigator replacement should be monitored.

### Axon Server Dashboard

- **Source**: http://localhost:8024 | https://docs.axoniq.io
- **Technique**: Overview page with filtering/scaling, monitoring page with health info and logs, event store search with chronological browsing, tag visualization, and type/time filtering. Command and query monitoring pages show message flow through the system.
- **Meadowsyn mapping**: The event store search interface (chronological browsing + type filtering + tag visualization) is a practical reference for Meadowsyn's event explorer. The monitoring page's health/log integration shows how to combine time-series metrics with discrete event streams.

### Phoenix LiveView Event Sourcing Visualization (Casavo)

- **Source**: https://medium.com/casavo/supercharging-our-event-sourcing-capabilities-with-phoenix-liveview-c4a9d1d4ab99
- **Technique**: LiveView-powered GUI that draws aggregate/command/event/handler graphs with EventStorming-inspired color coding. Shows event handler processing status with color indicators for stuck/slow handlers. Real-time updates via WebSocket.
- **Meadowsyn mapping**: The EventStorming color-coding convention (commands=blue, events=orange, aggregates=yellow) could be adapted for Meadowsyn's event types (bead-claim=blue, commit=green, test-fail=red). LiveView's real-time WebSocket model is the right architecture for a live factory dashboard.

### Replay.io (Browser Time-Travel Debugger)

- **Source**: https://www.replay.io/ | MCP integration
- **Technique**: Records full browser runtime -- every DOM change, network request, state update -- into a deterministic replay. Supports retroactive console.log insertion at any point in the recording. Comments on the timeline serve as breadcrumbs. MCP integration delivers root cause analysis to coding agents.
- **Meadowsyn mapping**: The "recording as artifact" concept applies to Meadowsyn: each agent session could produce a replay-like artifact showing what the agent did, viewable post-hoc. The retroactive-instrumentation pattern (add logging to past execution) is a powerful debugging metaphor for understanding agent behavior.

### rrweb (Session Replay)

- **Source**: https://github.com/rrweb-io/rrweb | MIT license
- **Technique**: Records DOM mutations as JSON events (full snapshot + incremental deltas). Player UI (`rrweb-player`) provides timeline scrubbing, speed controls, and skip-inactivity. Uses d3, fakesmil, svg-pan-zoom internally. Compact: does not record video, reconstructs from events.
- **Meadowsyn mapping**: The incremental-snapshot architecture (full state + deltas) is the right data model for Meadowsyn's factory state: take periodic full snapshots, stream deltas between them, enable scrubbing to any point. If agents have web-based UIs or produce HTML artifacts, rrweb could record their "screen" for later replay.

---

## 4. TimelineJS and Journalistic Timeline Tools

### TimelineJS (Knight Lab)

- **Source**: https://timeline.knightlab.com/ | https://github.com/NUKnightLab/TimelineJS3 | npm `@knight-lab/timelinejs`
- **Technique**: Interactive storytelling timeline driven by Google Sheets or JSON. Each slide has a date, headline, text, and media (YouTube, Flickr, SoundCloud, Wikipedia, Google Maps, etc). Navigation via horizontal timeline bar with zoom. Group property clusters events into labeled rows.
- **Limitation**: "Does not work well for stories that need to jump around in the timeline" -- strictly linear/chronological navigation.
- **Meadowsyn mapping**: Best suited for Meadowsyn's "daily narrative" view: "Today the factory completed 12 beads, deployed 3 features, and resolved 2 incidents." Each event becomes a slide with rich media (diff screenshots, test output, agent logs). The group property maps events to agents. The Google Sheets integration enables non-technical content curation. However, the linear-only navigation is a real limitation for exploring branching agent work.

### Full Knight Lab Suite

- **Source**: https://knightlab.northwestern.edu/projects/
- **StoryMapJS**: Location-based narrative -- each slide tied to a map point. Could visualize "agent working on repo X (located at service Y)" if the factory has a spatial metaphor.
- **JuxtaposeJS**: Before/after comparison slider. Directly applicable: "codebase before vs. after this sprint" as a visual diff.
- **SoundciteJS**: Inline audio embeds. Could embed agent log audio summaries (TTS) in narrative timelines.

### vis-timeline (vis.js)

- **Source**: https://github.com/visjs/vis-timeline | https://visjs.github.io/vis-timeline/
- **Technique**: Interactive timeline visualization with drag-and-drop, zoom (milliseconds to years), groups (swim lanes), and editable items. Items can be points or ranges. Rendered with regular HTML DOM for CSS-based styling. Supports nested groups, cluster mode for dense events, and custom time markers.
- **Meadowsyn mapping**: Strong candidate for Meadowsyn's primary timeline component. Groups = agents (swim lanes), items = bead work periods (ranges) or events (points). The millisecond-to-years zoom range handles both "last 5 minutes" and "last 3 months" views. HTML DOM rendering means items can contain rich content (agent avatars, status badges, commit counts). The editable-items feature is not needed for read-only Meadowsyn, but the customization flexibility is valuable.

### EventDrops (marmelab)

- **Source**: https://github.com/marmelab/EventDrops
- **Technique**: D3-based event series visualization with multiple parallel lanes. Each row shows a named event stream as dots on a timeline. Drag and zoom to navigate. Hover for details. Performance optimized to 55+ FPS even during zoom/pan (v1.0 rewrite).
- **Meadowsyn mapping**: The most direct fit for "all agent events on one screen." Each lane = one agent, dots = events (color-coded by type). The performance optimization story (letting D3 compute minimal updates rather than full redraws) is instructive for Meadowsyn's implementation. The patternfly-timeline fork adds zoom slider/buttons and current-time marker.

### patternfly-timeline

- **Source**: https://github.com/patternfly/patternfly-timeline
- **Technique**: Fork of EventDrops with added zoom slider, current-time marker, and PatternFly design system integration. Event click callbacks, customizable event line colors (including functions of event data), and marker display under mouse pointer.
- **Meadowsyn mapping**: The zoom slider + marker additions make this more immediately usable than raw EventDrops. PatternFly design tokens provide a polished enterprise look. If Meadowsyn uses PatternFly or a similar design system, this slots in directly.

### Apache ECharts Timeline Component

- **Source**: https://echarts.apache.org/ | https://github.com/apache/echarts
- **Technique**: Timeline component presents data across time dimensions. Comprehensive animation system: entry/update/leave animations triggered by data diffs via `setOption()`. ECharts 5 added morphing transitions between chart types and universal transitions across series. The system is declarative -- developers update data and ECharts computes appropriate animations.
- **Meadowsyn mapping**: ECharts' animation-first philosophy is well-suited for Meadowsyn's real-time factory view. Smooth transitions as agents start/stop work, beads change state, and metrics update. The universal-transition feature enables view morphing (switch from timeline view to graph view with animated transition). Mature library with extensive documentation.

---

## 5. Video Game Replay Systems

### StarCraft 2 Replay System

- **Source**: https://github.com/GraylinKim/sc2reader | Liquipedia StarCraft II | https://github.com/Blizzard/s2protocol
- **Technique**: Replay files store initial game context + chronological event list. The game engine replays events deterministically to reconstruct state at any point. Users can speed up/slow down playback and rewind (jump backward), but cannot jump forward (must replay sequentially). sc2reader (Python) extracts events: unit commands, camera movements, selections, hotkeys, unit creation/death times.
- **Key constraint**: Rewinding was "especially hard to code" (Blizzard) because the engine is a forward-only state machine. Jumping backward requires replaying from the beginning or from a cached snapshot.
- **Meadowsyn mapping**: The "initial state + event stream = deterministic replay" model is exactly how Demarch's event log works. The forward-only constraint with snapshot-based rewind is the practical architecture for Meadowsyn's scrubber: periodically snapshot factory state, replay events forward from the nearest snapshot. The sc2reader library demonstrates how to extract structured events from replay files for analysis, analogous to parsing Demarch's event log.

### Overwatch Replay Technology (GDC 2017)

- **Source**: GDC Vault -- "Replay Technology in Overwatch: Kill Cam, Gameplay, and Highlights" by Philip Orwig | https://www.gdcvault.com/play/1024053/
- **Technique**: Replay system developed in parallel with network model. Kill cam requires generating and transferring replay "reels" within hard respawn deadlines. Client architecture refactored to support interruptible kill cam (replay can be interrupted mid-playback to return to live view).
- **Overwatch ECS Architecture** (Timothy Ford, GDC 2017): Entity Component System enables layered gameplay where networked simulation leverages determinism for responsiveness. ECS makes replay possible because game state is fully described by component data.
- **Meadowsyn mapping**: The "interruptible replay" pattern is valuable: a Meadowsyn user watching a replay of yesterday's factory run should be able to instantly switch to the live view when something interesting happens now. The ECS-as-serializable-state concept maps to Meadowsyn's factory state being a collection of agent states + bead states + repo states, each independently serializable.

### Rewindable Instant Replay for Temporal Debugging (GDC 2013)

- **Source**: Mark Wesley, 2K Marin | https://gdcvault.com/play/1018138/ | https://archive.org/details/GDC2013Wesley
- **Technique**: Circular buffer of N frames (e.g., 900 frames at 30fps = 30 seconds). Each frame stores transforms and debug-draw commands for all entities. During playback: pause simulation, render stored frame data, support scrub/rewind/fast-forward. Sub-frame blending via Slerp (quaternions) and Lerp (vectors) between neighboring frames.
- **Key insight**: "A rewindable replay system is far superior for debugging and tuning than a deterministic replay system" because it captures actual state rather than requiring perfect determinism.
- **Meadowsyn mapping**: The circular-buffer approach works for Meadowsyn's "last N minutes" live replay. Store periodic factory state snapshots in a ring buffer; interpolate between snapshots for smooth scrubbing. The "superior to deterministic replay" point is crucial: Meadowsyn should snapshot actual factory state rather than trying to make the event replay perfectly deterministic.

### Braid Time Rewind (GDC 2010)

- **Source**: Jonathan Blow | https://gdcvault.com/play/1012210/ | https://www.gamedeveloper.com/design/video-jonathan-blow-explains-i-braid-s-i-rewind-mechanic-at-gdc-2010
- **Technique**: Does NOT generate a 1:1 event record. Instead: generates rough records based on frequently gathered data from active game objects. Entries reference current frame for easy overwriting. Recall decompresses stored data and interpolates between current position and recorded positions. "The rewind mechanic does not really rewind at all but generates new states from data that is distinct from the previously experienced game-states."
- **Design philosophy**: "What happens if I gave the player the chance to rewind time in an unlimited way?" Blow had a curator role, cleaning up emergent answers.
- **Meadowsyn mapping**: Braid's lossy-but-smooth approach is instructive: Meadowsyn doesn't need perfect fidelity in replay. Approximating past states from sampled data (periodic snapshots + interpolation) is sufficient for narrative understanding. The "unlimited rewind" philosophy matches Meadowsyn's public audience: observers should be able to freely explore any time period without resource constraints.

### Chess Analysis Board (Lichess/Chess.com)

- **Source**: https://github.com/lichess-org/lila | https://github.com/lichess-org/chessground (10KB gzipped, no dependencies)
- **Technique**: Move tree as a data structure with bitemporal nodes that branch infinitely. Base branch = actual game; alternate moves create hypothetical branches. Navigation: right/left arrows traverse main line, up/down enter/exit variations. Blue = main line, red = alternatives. Engine evaluation overlaid on each position.
- **Lichess Chessground**: Custom DOM-diff chess board UI, minimal footprint, no dependencies. Designed for instant responsiveness. Stockfish compiled to WebAssembly for client-side analysis.
- **Meadowsyn mapping**: The branching move tree is the most sophisticated consumer UI for "what if" temporal analysis. Map to Meadowsyn: "the factory chose to assign bead X to agent A (main line); what if it had gone to agent B? (variation)." The arrow-key navigation pattern (forward/backward through events, up/down through alternatives) is immediately learnable. Chessground's architecture (10KB, no deps, custom DOM diff) sets a performance standard.

### Ballchasing.com (Rocket League)

- **Source**: https://ballchasing.com/
- **Technique**: 3D replay viewer in browser. Comprehensive per-player statistics: boost consumption, positioning heatmaps, ball possession timelines. 117M+ replay repository. Replay groups for comparative analysis.
- **Meadowsyn mapping**: The statistical dashboard per agent (boost = tokens, positioning = file activity, ball possession = bead ownership) is a direct parallel. The replay-group concept (compare multiple factory runs) enables sprint-over-sprint comparison. The community repository model (share and discuss replays) could make Meadowsyn a public showcase.

---

## 6. Process Mining Visualization

### PM4JS (Process Mining for JavaScript)

- **Source**: https://www.pm4js.org/ | npm `pm4js`
- **Technique**: Full process mining library in JavaScript. Parses CSV/XES event logs in the browser. Implements Inductive Miner algorithm for process discovery. Visualizes Petri nets using Viz.js (Graphviz compiled to JS). Runs in modern browsers and Node.js.
- **Meadowsyn mapping**: THE KEY FINDING. PM4JS can ingest Demarch's event log (CSV or JXES format), discover the actual process model (how beads flow through states, which paths agents take), and render it as an interactive Petri net -- all in the browser, no backend required. This enables Meadowsyn to show "here's the actual process the factory follows" derived from data rather than prescribed.

### PM4Py (Python)

- **Source**: https://pm4py.fit.fraunhofer.de/ | PyPI `pm4py`
- **Technique**: Comprehensive Python process mining library. Process discovery (Inductive Miner, Alpha Miner, Heuristics Miner), conformance checking (token-based replay, alignments), performance analysis. Visualization via Graphviz (SVG/PNG export). Supports Petri nets, directly-follows graphs, BPMN, process trees.
- **DFG rendering**: `pm4py.visualization.dfg` renders directly-follows graphs with frequency or performance decoration. Edges show count or average time between activities. Exportable as SVG for web embedding.
- **Meadowsyn mapping**: PM4Py serves as the analysis backend. Generate DFGs and Petri nets server-side, export as SVG/JSON, render in Meadowsyn. The DFG is especially powerful: edges labeled with "average time from bead-claim to first-commit" or "95th percentile test-to-deploy" give observers immediate process intelligence.

### ProcessanimateR (bupaR suite)

- **Source**: https://github.com/bupaverse/processanimateR | MIT license
- **Technique**: Token replay animation on process maps. Each case (trace) becomes a token that travels through the process model according to activity waiting/processing times. Built with D3 + SVG animations (SMIL). Token size, color, and shape customizable based on trace/event attributes. Uses viz.js for process map layout, D3 for animation, svg-pan-zoom for navigation.
- **Technology stack**: R package producing htmlwidgets (self-contained HTML+JS). Internal JS: d3, fakesmil, svg-pan-zoom, viz.
- **Meadowsyn mapping**: The token-animation metaphor is immediately compelling: watch beads flow through the factory's process model in real time. Each bead is a token moving from "created" through "claimed" to "completed," with speed reflecting actual processing time. The htmlwidget output can be embedded directly in a web page. The bupaR ecosystem provides the full process mining pipeline (import -> discover -> animate) in a single toolchain.

### Disco (Fluxicon)

- **Source**: https://fluxicon.com/disco/
- **Technique**: Commercial process mining tool. Automated process discovery with fluid animation of process maps. Activity coloring by frequency/performance. Path thickness encoding for volume. Overlay popovers for detailed statistics. Timestamp-driven animation playback.
- **Meadowsyn mapping**: Disco's animation style (tokens flowing through an animated process map with statistical overlays) is the gold standard for process mining visualization. While Disco itself is not embeddable, its interaction patterns (color = frequency, thickness = volume, animation = time progression, popover = details) should be replicated in Meadowsyn using open-source components.

### Celonis Process Intelligence API

- **Source**: https://developer.celonis.com/process-intelligence-apis/ | Embedding: iframe component in Views
- **Technique**: REST API that programmatically exports process intelligence (KPIs, context, recommended actions) to third-party platforms. iframe embedding of Celonis Views into external applications. Extended at Celonis:Next 2025 for AI agent integration (Copilot Studio, Bedrock, Agentforce).
- **Object-Centric Process Mining (OCPM)**: Analyzes how multiple business objects (orders, invoices, deliveries) interact over time -- not just single-case process flows.
- **Meadowsyn mapping**: OCPM is the right formalism for Demarch's factory. Beads, agents, repos, and PRs are interacting objects, not independent cases. Celonis's API-first approach (generate API endpoint from selected KPIs) is a design reference for Meadowsyn's data layer. However, Celonis is proprietary and enterprise-priced; the open-source stack (PM4JS + PM4Py + processanimateR) provides equivalent functionality for Meadowsyn's needs.

### Smyrida

- **Source**: https://github.com/smpi-islab-uniwa/Smyrida | University of West Attica
- **Technique**: Modular web application with open APIs for process mining and interactive visualization. Shows trace variants with frequency, performs conformance checking. Built on ProM framework. Designed for users without advanced process mining skills.
- **Meadowsyn mapping**: Smyrida's "open API" design philosophy matches Meadowsyn's need for a composable visualization layer. The "designed for non-experts" goal aligns with Meadowsyn's public audience. However, maturity and maintenance status should be verified before adoption.

### Apromore Community Edition

- **Source**: https://github.com/apromore/ApromoreCore | Apache 2.0
- **Technique**: Web-based process mining platform. Process discovery, comparison, conformance checking. Visual process model editor (BPMN). Overlay statistics (frequency, duration) on process maps. Graphical ETL tools for data loading.
- **Meadowsyn mapping**: Apromore's web-native architecture and overlay-statistics pattern are directly applicable. The BPMN editor could be repurposed as a "factory process designer" for configuring expected workflows that Meadowsyn then monitors against actual behavior. Community Edition's Apache 2.0 license is permissive enough for integration.

### Petri-JS

- **Source**: https://github.com/kyouko-taiga/petri-js
- **Technique**: JavaScript library to display and interact with Petri Nets. CommonJS module for Webpack/Browserify. Supports Place/Transition net semantics by default. Designed for simulation of Petri net firing.
- **Meadowsyn mapping**: Lightweight alternative to PM4JS for Petri net rendering only (no process discovery). Could be used if Meadowsyn defines the factory process model manually rather than discovering it from event logs.

### XES/JXES Standards

- **Source**: IEEE XES Standard | https://www.tf-pm.org/resources/xes-standard | JXES: https://blog.rwth-aachen.de/pads/2020/11/13/jxes-json-support-for-xes-event-logs/
- **Technique**: XES is the IEEE standard for event log interchange (XML-based). JXES provides JSON support for web-friendly transport. Standard extensions define attributes for concept names, timestamps, lifecycle transitions, and organizational info.
- **Meadowsyn mapping**: Demarch's event log should export to JXES format to plug into the entire process mining ecosystem. The lifecycle extension (start/complete transitions) maps to bead state changes. The organizational extension (resource, role, group) maps to agent identity and agent fleet structure. JXES over WebSocket enables real-time process mining.

---

## Cross-Cutting Patterns and Recommendations

### Primary Visualization Stack for Meadowsyn

| Layer | Recommended Tool | Rationale |
|-------|-----------------|-----------|
| **Metric panels** | TradingView Lightweight Charts | 35KB, Apache 2.0, canvas-based, plugin-extensible, battle-tested for real-time multi-series |
| **Agent timeline** | vis-timeline or EventDrops | Swim-lane per agent, zoom milliseconds-to-years, HTML DOM for rich items |
| **Process model** | PM4JS + D3 | Browser-native process discovery from event logs, Petri net/DFG rendering |
| **Token animation** | processanimateR concepts + D3 | Animate beads flowing through discovered process model |
| **Git lineage** | @gitgraph/core + custom renderer | Programmatic git-DAG rendering, data-driven from event log |
| **Narrative view** | TimelineJS or vis-timeline | Curated "daily story" with rich media slides |
| **Replay scrubber** | Custom (circular buffer + interpolation) | Braid/Wesley-inspired snapshot+interpolation for smooth rewind |
| **Detail inspection** | Redux DevTools interaction pattern | Click event to jump to state, skip/replay events |
| **Agent roster** | Tufte sparklines | Word-sized activity trends for 32+ agents at a glance |

### Key Temporal Interaction Patterns

1. **Focus+Context (d3-brush)**: Brush a time range in overview to zoom the detail view. Essential for navigating 24h of factory activity.
2. **Synchronized panes**: Multiple panels sharing a time axis (Bloomberg pattern). Hovering one panel shows crosshairs on all panels at the same timestamp.
3. **Sparklines in roster**: Tufte sparklines per agent in a sidebar for at-a-glance activity scanning across 32+ agents.
4. **Scrubber with snapshots**: Braid/Wesley-inspired circular buffer of factory state snapshots. Smooth interpolation between snapshots for scrub responsiveness. Forward replay from nearest snapshot for arbitrary time-jump.
5. **Date slider animation**: VisFork-style play/pause/scrub control that auto-advances time, showing factory evolution as an animation.
6. **Event-type color coding**: EventStorming-inspired colors (claims=blue, commits=green, tests=yellow, failures=red, completions=purple) consistent across all views.
7. **Branching what-if**: Chess analysis board pattern for exploring alternative factory decisions, navigable with arrow keys.
8. **Interruptible replay**: Overwatch-inspired instant switch from historical replay to live view when interesting activity occurs.

### Data Format Recommendation

Export Demarch's event log in JXES (JSON XES) format to enable plug-and-play integration with the process mining ecosystem (PM4JS, PM4Py, Apromore, Smyrida). Each bead lifecycle maps to a trace; each state transition maps to an event with timestamp, lifecycle transition, and organizational attributes.

### Performance Targets

- Canvas rendering (Lightweight Charts) for continuous time series: 10,000+ data points at 60 FPS
- D3 SVG for event timelines (EventDrops): 55+ FPS during zoom/pan with thousands of events
- Process model rendering (PM4JS/viz.js): sub-second for models with <500 nodes
- Snapshot-based replay: 100ms max latency for scrubbing to any point in 24h history
