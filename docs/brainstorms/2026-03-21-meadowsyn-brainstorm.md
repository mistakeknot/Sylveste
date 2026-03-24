---
artifact_type: brainstorm
bead: Demarch-jpum
stage: discover
---

# Meadowsyn: Web Visualization Frontend for the AI Factory

## What We're Building

Meadowsyn is a public-facing web visualization frontend for the Demarch AI factory — an autonomous software development system running dozens of simultaneous agents. Named after Donella Meadows (*Thinking in Systems*) + Cybersyn (Allende-era real-time economic ops room). Domain: meadowsyn.com.

**The niche:** Every existing tool (Grafana, Temporal, LangSmith, AgentOps) serves developers, operators, or evaluators. None serve a public audience watching an autonomous factory. The closest analog is Flightradar24, not any developer tool.

## Why This Approach

Rather than committing to one architecture upfront, we're running **parallel experiments** — 6 visual prototypes × 4 data layer approaches = 24 permutations to explore. This is justified because:

1. The domain is genuinely novel — no prior art for "public factory viewer"
2. The research surfaced radically different design paradigms (ambient generative art vs. industrial control room vs. biological dashboards) with no clear winner
3. Recursive permutation lets the experiments decide the architecture

## Research Foundation

8 parallel research agents surveyed 8 domains (3,639 lines of findings). Full reports at `apps/Meadowsyn/docs/research/`. Key synthesis at `apps/Meadowsyn/docs/research/synthesis.md`.

### Three-Layer Display Architecture (proposed)

| Layer | What | Inspiration |
|-------|------|-------------|
| L1: Ambient field | Generative WebGL background encoding factory health | Hydra (algorave), Weiser's calm tech |
| L2: Information ribbon | FIDS split-flap board — glanceable from across a room | Airport departure boards, EEMUA 191 |
| L3: Interactive detail | Click-to-drill panels: timeline, graph, trace viewer | Foxglove, ISA-101 hierarchy, Nextstrain |

### Top Interaction Patterns

1. Exception-driven attention (Cybersyn) — quiet when healthy, color only on anomaly
2. Loopy's animated signal propagation — perturbations rippling through the system
3. Progressive disclosure (StarCraft 2 esports, ISA-101) — L1→L4, max 2 clicks
4. FIDS split-flap board — airport departure aesthetic (proven legibility at distance)
5. Linked multi-panel views (Nextstrain) — interaction in any panel filters all others
6. Follow-one-show-all (game AI debugger) — highlight one agent, show fleet context
7. Pheromone gradient overlay — route preference with decay (structurally isomorphic)
8. Phylogenetic tree for task lineage (Nextstrain) — bead ancestry as evolutionary tree
9. Process mining replay (PM4JS) — reconstruct dispatch flows from event log
10. Braid-style time rewind (video game replay) — scrub back without losing live feed

### Deepest Cross-Domain Insights

- **Pheromone = routing priority** — same dynamical system (positive feedback + decay), not a metaphor
- **Sheaf consistency as health metric** — coboundary norm measures agent agreement on shared state
- **React components are parametrised lenses** (Cybercat Institute, Jan 2025) — drill-down is lens composition

## Key Decisions

### Decision 1: Experiment-First, Not Architecture-First

We're building 10 standalone prototypes before committing to any architecture. Each tests one concept from the research against real (or mock) factory data.

### Decision 2: Visual Experiments (6)

| # | Experiment | Concept | From Research |
|---|-----------|---------|---------------|
| 01 | split-flap | FIDS departure board aesthetic for agent status | Ops room UX, Spatial/ambient |
| 02 | hydra-ambient | WebGL generative background encoding factory health | Spatial/ambient (algorave) |
| 03 | cytoscape-graph | Force-directed agent-bead graph with fCoSE layout | Bio-ecological (Cytoscape.js) |
| 04 | raster-heatmap | Neural-style agent activity grid (agents-as-neurons) | Bio-ecological (Rastermap) |
| 05 | loopy-signals | Animated signal propagation through causal loops | Systems thinking (Loopy) |
| 06 | process-replay | Event log token animation on process flow diagram | Time/history (PM4JS, Disco) |

### Decision 3: Data Layer Experiments (4)

| # | Experiment | Approach | Tradeoff |
|---|-----------|----------|----------|
| A | static-json | `fetch()` snapshot on 5s timer | Simplest. No server needed. Latency = poll interval. |
| B | sse-stream | Server-Sent Events from lightweight server | Real-time push. One-directional. Works through proxies. |
| C | websocket | WebSocket bidirectional stream | Lowest latency. Requires persistent connection. |
| D | sqlite-wasm | SQL.js querying local SQLite DB | Richest queries. Offline-capable. Larger initial payload. |

### Decision 4: Recursive Permutation

After initial prototypes, combine: each visual × each data pipe = 24 combos. Let actual usage reveal which combinations work.

## Data Sources (Existing)

- `clavain-cli factory-status --json` — fleet (total/active/idle agents), queue (by priority), WIP (agent→bead mapping with age), recent dispatches, watchdog state, factory_paused flag
- `bd list --format=json` — full beads data (issues, deps, status, priority, assignee)
- `cass` — session history, token analytics, agent activity timelines
- `tmux list-sessions` — live agent session count and names

## Tech Stack Candidates (from research)

| Component | Library | Why |
|-----------|---------|-----|
| Metric sparklines | TradingView Lightweight Charts (35KB) | Financial-grade, Apache 2.0 |
| Agent timeline | vis-timeline or EventDrops (55+ FPS) | Battle-tested D3-based |
| Graph layout | Cytoscape.js fCoSE | Constraint-based, compound nodes, 2x faster |
| Node-wire | LiteGraph.js | Powers ComfyUI at scale |
| Process replay | PM4JS | Browser-native process discovery |
| Generative ambient | hydra-synth | WebGL shaders, npm embeddable |
| Audio (optional) | Tone.js | Eno overlapping-loop principle |
| System dynamics | SDEverywhere → WASM | En-ROADS architecture reference |

## Open Questions

1. **What framework for the app shell?** React (ecosystem), Svelte (performance, En-ROADS precedent), or vanilla JS (beads_viewer-pages precedent)?
2. **Should experiments be standalone HTML files or a monorepo app with routes?** Standalone is faster to iterate; monorepo enables shared components.
3. **How to handle time-series history?** Factory-status is point-in-time. Need to accumulate snapshots for sparklines, heatmaps, replay. Server-side append-only log vs. browser-side ring buffer?
4. **What's the deployment story?** Static hosting (GitHub Pages, Vercel) vs. always-on server (needed for SSE/WebSocket)?
5. **When to register meadowsyn.com?**
