---
artifact_type: prd
bead: Demarch-jpum
stage: design
---

# PRD: Meadowsyn Experiment Suite

## Problem

No existing tool visualizes an autonomous AI agent factory for a public audience. The 8-agent research survey confirmed this is a genuinely unaddressed niche (closest analog: Flightradar24). We have rich design inspiration from 8 domains but no empirical signal on which concepts work in practice.

## Solution

Build 10 standalone experiments — 6 visual prototypes and 4 data layer approaches — then compose them via recursive permutation. Each experiment is a self-contained HTML/JS artifact that can be evaluated independently and combined with any data pipe.

## Features

### F1: Mock Data Generator
**What:** CLI/script that outputs `clavain-cli factory-status --json` shaped data with realistic fake agent names, bead IDs, queue depths, and temporal variation (simulated activity patterns).
**Acceptance criteria:**
- [ ] Outputs valid JSON matching factory-status schema
- [ ] Supports `--agents N` flag to scale fleet size (5-100)
- [ ] Generates time-varying data when called repeatedly (agent states change, queue depth fluctuates)
- [ ] Can emit a stream (one JSON per line per second) for SSE/WS testing

### F2: Split-Flap Board
**What:** FIDS-style airport departure board showing per-agent status rows with split-flap animation on state changes.
**Acceptance criteria:**
- [ ] Each agent gets a row: name, current bead, status (dispatching/executing/idle), duration
- [ ] State changes trigger split-flap character animation (CSS only, no canvas)
- [ ] Reads from mock data generator or static JSON
- [ ] Legible at 3m viewing distance (test: screenshot at 25% zoom)
- [ ] Dark background, monospace, "going gray" principle (color only on anomaly)

### F3: Hydra Ambient Field
**What:** WebGL generative background that encodes factory health as visual texture — oscillation frequency maps to throughput, color temperature maps to error rate, turbulence maps to queue pressure.
**Acceptance criteria:**
- [ ] Uses hydra-synth npm package embedded in a React/vanilla wrapper
- [ ] At least 3 factory metrics mapped to distinct visual parameters
- [ ] Smooth transitions when data updates (no jarring jumps)
- [ ] Runs at 60fps on a 2020-era laptop
- [ ] Visually distinct states for: healthy factory, degraded, paused, critical

### F4: Cytoscape Agent Graph
**What:** Force-directed graph showing agents (nodes) connected to beads (nodes) they're working on, with dependency edges between beads.
**Acceptance criteria:**
- [ ] Uses Cytoscape.js with fCoSE layout
- [ ] Agent nodes and bead nodes visually distinct (shape + color)
- [ ] Click agent → highlight its bead + dependencies
- [ ] Click bead → highlight assigned agent + dep chain
- [ ] Priority mapped to node size, status mapped to node color
- [ ] Handles 50+ nodes without layout thrashing

### F5: Raster Heatmap
**What:** Neural-style activity grid: X-axis = time (5-min buckets), Y-axis = agents, color = activity level (idle/dispatching/executing/blocked).
**Acceptance criteria:**
- [ ] Canvas-rendered for performance (not DOM elements)
- [ ] Scrolling time window (last 2 hours) with live tail
- [ ] Click cell → tooltip with agent name, bead, timestamp
- [ ] Color scheme: dark gray (idle), blue (dispatching), green (executing), red (blocked/error)
- [ ] Sorted by agent activity level (most active at top)

### F6: Loopy Signal Propagation
**What:** Animated causal loop diagram showing factory feedback loops (dispatch → execution → quality gate → rework/ship → queue drain → dispatch).
**Acceptance criteria:**
- [ ] Nodes for: backlog, dispatch, execution, quality gates, ship, rework
- [ ] Animated particles flowing along edges proportional to throughput
- [ ] Feedback loops visible: rework loop (quality fail → back to backlog), success loop (ship → reduced queue)
- [ ] Perturbation mode: click a node to inject a signal, watch it propagate
- [ ] SVG-based with D3 or vanilla

### F7: Process Replay
**What:** Event log replay showing factory dispatch events as tokens flowing through a process diagram, with scrub/play/pause controls.
**Acceptance criteria:**
- [ ] Reads event log (JSONL or factory-status history)
- [ ] Process diagram: backlog → claimed → dispatched → executing → gated → shipped/reworked
- [ ] Animated tokens (dots) moving through the process on playback
- [ ] Scrub bar for time navigation, play/pause, 1x/2x/5x speed
- [ ] Uses PM4JS or D3 for rendering

### F8: Static JSON Data Pipe
**What:** Minimal data layer: fetch() polling a JSON endpoint/file on a configurable interval with client-side ring buffer for history.
**Acceptance criteria:**
- [ ] Configurable poll interval (default 5s)
- [ ] Ring buffer stores last N snapshots (default 720 = 1 hour at 5s)
- [ ] Exposes `subscribe(callback)` API for visual components
- [ ] Works from `file://` (local dev) and `https://` (deployed)
- [ ] Graceful handling of fetch failures (retry with backoff, stale indicator)

### F9: SSE Data Pipe
**What:** Lightweight server that polls factory-status and streams updates to browsers via Server-Sent Events.
**Acceptance criteria:**
- [ ] Server in Go or Node.js, < 200 lines
- [ ] Polls `clavain-cli factory-status --json` every 5s
- [ ] Streams diffs (not full snapshots) when only WIP/queue changes
- [ ] `GET /events` SSE endpoint, `GET /api/snapshot` for current state
- [ ] Serves static files from `./public/`
- [ ] Client library: `EventSource` wrapper with reconnect + ring buffer

### F10: Composition Shell
**What:** App shell that can dynamically mount any visual experiment with any data pipe — the permutation engine.
**Acceptance criteria:**
- [ ] Route-based: `/#/split-flap`, `/#/hydra`, `/#/graph`, etc.
- [ ] Data source toggle: static-json / sse / websocket / mock
- [ ] Each visual registers as a plugin: `{ name, mount(el, dataSource), unmount() }`
- [ ] Shared header: factory status summary bar (agent count, queue depth, uptime)
- [ ] URL-shareable state: `/#/split-flap?data=sse&agents=20`

## Non-goals

- Authentication or multi-tenancy (public read-only)
- Mobile-responsive layout (desktop-first, large screen)
- Production deployment infrastructure (experiments only)
- WebSocket data pipe (defer — SSE covers real-time push, simpler)
- Ambient audio / sonification (defer to post-experiment phase)

## Dependencies

- `clavain-cli factory-status --json` (exists, working)
- `bd list --format=json` (exists)
- Node.js or Go runtime for SSE server
- npm packages: hydra-synth, cytoscape, lightweight-charts (to be evaluated)

## Open Questions

1. **Framework for composition shell:** React (ecosystem) vs Svelte (performance, En-ROADS precedent) vs vanilla JS (simplest)?
2. **Where to accumulate history?** Server-side append-only log vs browser ring buffer vs both?
3. **When to register meadowsyn.com?** Before or after experiments converge?
