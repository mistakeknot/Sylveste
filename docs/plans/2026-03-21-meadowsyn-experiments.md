---
artifact_type: plan
bead: Demarch-jpum
prd: docs/prds/2026-03-21-meadowsyn-experiments.md
stage: plan-reviewed
review_findings: .claude/flux-drive-output/fd-{experiment-feasibility,dependency-ordering,tech-stack-viability,scope-containment,acceptance-criteria-quality,composition-architecture}.md
---

# Plan: Meadowsyn Experiment Suite (v2 — post-review)

## Changes from v1

Incorporated findings from 6 review agents (4 P0, 11 P1):
- **P0-1**: Added `serve.sh` — `file://` blocks ES module imports
- **P0-2**: Added F0 (shared contracts) — plugin interface must exist before Batch 2
- **P0-3**: Fixed dependency graph — F8 and F9 are parallel, not sequential
- **P0-4**: DataPipe separates transport from history — switching transport preserves state
- **P1**: Dropped PM4JS (use D3), dropped EventDrops (use vis-timeline), trimmed F6/F7/F4/F10/F2/F9 scope, flagged hydra-synth AGPL, added JSON Schema extraction, fixed F10 websocket contradiction

## Dependency Graph (corrected)

```
F0 (Shared Contracts) ← F1 (Mock Data)
                      ← F8 (Static JSON Pipe)
                      ← F9 (SSE Pipe)          [F8 and F9 are PARALLEL]

F0 + F1 + F8 ← F2 (Split-Flap)
             ← F3 (Hydra Ambient)
             ← F4 (Cytoscape Graph)
             ← F5 (Raster Heatmap)
             ← F6 (Loopy Signals)
             ← F7 (Process Replay)

F0 + any 2 visuals + any 1 data pipe ← F10 (Composition Shell)
```

F0 is the new critical path (~30 min). F1, F8, F9 depend only on F0 and are parallel. All visuals depend on F0+F1+F8. F10 depends on F0 + working examples.

## Dev Server Requirement

`file://` blocks ES module cross-directory imports (CORS null origin). All experiments require a local HTTP server.

```
apps/Meadowsyn/serve.sh:
  #!/bin/bash
  # One-liner dev server for all experiments
  cd "$(dirname "$0")" && npx serve -l 3000 -s .
```

Document in README: `./serve.sh` then open `http://localhost:3000/experiments/<name>/`.

## Execution Sequence

### Batch 0: Shared Contracts (~30 min)

**F0: Shared Contracts** (no bead — part of Demarch-jpum)

Location: `apps/Meadowsyn/shared/`

```
shared/
  plugin.js         # Plugin interface contract
  data-pipe.js      # DataPipe base class with transport/history separation
  constants.js      # Colors, status vocabulary, formatters
  schema/
    factory-status.schema.json  # Extracted from clavain-cli Go structs
```

Implementation:

1. **Plugin interface contract** (addresses P0-2, P1-8):
   ```js
   // Every visual experiment exports this shape
   export default {
     name: 'split-flap',
     // Phase 1: create internal state, don't render yet
     init(container, dataPipe, options) { return instance },
     // Phase 2: start rendering (container dimensions are settled)
     activate(instance) {},
     // Pause rendering (rAF loops, timers) without destroying state
     deactivate(instance) {},
     // Container resized
     resize(instance, { width, height }) {},
     // Tear down completely
     destroy(instance) {},
   }
   ```

2. **DataPipe with transport/history separation** (addresses P0-4):
   ```js
   class DataPipe {
     constructor({ transport, bufferSize = 720 }) // transport is pluggable
     subscribe(callback) / unsubscribe(callback)
     getHistory()   // returns ring buffer (preserved across transport swaps)
     getLatest()
     isStale()
     setTransport(newTransport)  // swap without clearing history
   }
   // Transport implementations:
   class FetchTransport { constructor(url, interval) }
   class SSETransport { constructor(url) }
   class MockTransport { constructor(options) }
   ```

3. **Shared constants** (addresses P1-scope):
   ```js
   export const STATUS_COLORS = {
     idle: '#808080', executing: '#4caf50', dispatching: '#2196f3',
     blocked: '#f44336', gated: '#ff9800',
   }
   export const STATUS_ORDER = ['blocked','gated','executing','dispatching','idle']
   export function formatAgentName(name, maxLen = 12) { ... }
   export function formatDuration(seconds) { ... }
   ```

4. **JSON Schema** extracted from `clavain-cli factory-status --json` output (addresses SC1).

### Batch 1: Foundation (~1 hour, parallel after F0)

**F1: Mock Data Generator** (Demarch-ef08)

Location: `apps/Meadowsyn/experiments/mock-data/`

Implementation:
1. Node.js script outputting factory-status JSON to stdout
2. **Also reads `transfer/ideagui.json`** as seed data for realistic agent names, project names, and session patterns (84 sessions, 42 projects, 9 terminals)
3. `--agents N` flag (default 20), `--stream` flag (one JSON/sec)
4. State machine per agent: idle -> dispatching -> executing -> (gated -> shipped | reworked -> idle)
5. Distributions: 60% idle, 15% dispatching, 20% executing, 5% blocked
6. Validates output against `shared/schema/factory-status.schema.json`
7. ES module export: `import { generateSnapshot, createStream } from './index.js'`

**F8: Static JSON Data Pipe** (Demarch-lavt)

Location: `apps/Meadowsyn/experiments/data-static/`

Implementation:
1. Thin wrapper: `new FetchTransport(url, interval)` implementing the transport interface from F0
2. Test harness (`index.html`): raw JSON display + stale indicator + snapshot counter
3. Imports `DataPipe` + `FetchTransport` from `../../shared/data-pipe.js`

**F9: SSE Data Pipe** (Demarch-p83z) — **parallel with F8, not sequential**

Location: `apps/Meadowsyn/experiments/data-sse/`

Implementation:
1. Node.js server (bare http), < 150 lines
2. Polls `clavain-cli factory-status --json` every 5s (uses `execFile`, not `exec`)
3. `GET /events` — SSE endpoint: full snapshot on connect, diffs on update, heartbeat every 15s
4. `GET /api/snapshot` — current state as JSON
5. **No static file serving** (removed — not in scope for data pipe)
6. **No `/api/history` endpoint** (removed — history lives in client-side ring buffer)
7. Client: `new SSETransport(url)` implementing the transport interface from F0

### Batch 2: Visual Experiments (~1.5 hours each, all parallel)

All six run in parallel. Each has **dual entry points**: `index.html` (standalone) + `plugin.js` (exports F0 plugin interface). Import shared constants and DataPipe from `../../shared/`.

**F2: Split-Flap Board** (Demarch-r24y)

Location: `apps/Meadowsyn/experiments/split-flap/`

Implementation:
1. CSS-only split-flap animation
   - `@keyframes flip` with `transform: rotateX()` only (no layout-triggering properties)
   - **Selective `will-change`**: apply `.flipping` class only during active animation, remove after (addresses P1-7: 3,600 DOM nodes)
2. Row per agent: `[STATUS] [AGENT NAME........] [BEAD ID....] [TASK TITLE..............] [DURATION]`
3. Status column uses `STATUS_COLORS` from shared constants
4. Dark background (#0a0a0a), JetBrains Mono
5. Color only on anomaly (FAIL, GATE) — "going gray" principle
6. **Alphabetical sort** (removed dynamic sort — conflicts with split-flap animation, per scope review)
7. **Minimal header**: title + timestamp only (live metrics belong in F10 shell header)
8. Auto-refresh every 5s via DataPipe

**F3: Hydra Ambient Field** (Demarch-agi0)

Location: `apps/Meadowsyn/experiments/hydra-ambient/`

**License note: hydra-synth is AGPL-3.0.** If AGPL is unacceptable for Meadowsyn's public distribution, replace with raw WebGL shaders or Three.js. Decision needed before execution.

Implementation:
1. Import hydra-synth via `<script>` tag (UMD build from CDN), `makeGlobal: false`, `detectAudio: false`
2. Full-screen `<canvas>`
3. Bridge: factory metrics -> Hydra parameters via arrow-function bindings
   - throughput -> osc frequency, errorRate -> color temp, queuePressure -> noise, utilization -> brightness
4. Smooth lerp (current -> target over 2s)
5. Four states: healthy (blue-green), busy (warmer), degraded (amber noise), critical (red pulse)
6. **Target: 30fps floor** (not 60fps — integrated GPUs can't sustain 60fps WebGL at 1080p). Auto-reduce resolution if frame time > 33ms.
7. Overlay: semi-transparent key metrics text

**F4: Cytoscape Agent Graph** (Demarch-cjgj)

Location: `apps/Meadowsyn/experiments/cytoscape-graph/`

Implementation:
1. Import Cytoscape.js + cytoscape-fcose from CDN
2. Agent nodes (circles) + bead nodes (rounded rectangles) + edges
3. **Agent ring via manual trig + `fixedNodeConstraint`** (fCoSE has no native ring constraint — addresses P1-6):
   ```js
   agents.forEach((a, i) => {
     const angle = (2 * Math.PI * i) / agents.length
     constraints.push({ nodeId: a.id, position: { x: R*Math.cos(angle), y: R*Math.sin(angle) } })
   })
   ```
4. Node styling: agent color by status (shared constants), bead size by priority
5. Click agent -> highlight bead chain, dim others. Click bead -> highlight dep path.
6. **In-place attribute updates only** (removed animated layout transitions — graph diffing + force layout is a known hard problem, per scope review)
7. Dark background, labels on hover

**F5: Raster Heatmap** (Demarch-wwo9)

Location: `apps/Meadowsyn/experiments/raster-heatmap/`

Implementation:
1. HTML `<canvas>` rendering
2. Grid: 5-min buckets (24 columns = 2 hours) × N agents
3. Cell colors from `STATUS_COLORS` (shared constants), desaturated for dark background
4. Live tail: new column right, oldest scrolls left
5. Sort by total activity (most active top), re-sort every 30s
6. Hover tooltip: `mousemove` -> pixel-to-cell via `Math.floor(x/cellW)` with DPI scaling (`devicePixelRatio`)
7. History accumulated from DataPipe ring buffer (`getHistory()`)

**F6: Loopy Signal Propagation** (Demarch-no1e)

Location: `apps/Meadowsyn/experiments/loopy-signals/`

Implementation:
1. SVG-based causal loop diagram (D3 v7)
2. Fixed topology: Backlog -> Dispatch -> Execution -> Quality Gates -> Ship/Rework -> Backlog
3. Nodes show live counts from factory-status
4. Animated particles on edges (D3 transition + particle pool, ~20-50 particles)
5. Particle rate proportional to throughput, color: green (success) / red (rework)
6. R/B loop indicators
7. **Perturbation mode deferred to F6b** (removed — doubles interaction scope, per scope review)
8. Data-driven: node counts from factory-status

**F7: Process Replay** (Demarch-xhxp)

Location: `apps/Meadowsyn/experiments/process-replay/`

Implementation (trimmed — was 3 experiments in one):
1. Horizontal swim-lane: Backlog | Claimed | Executing | Gated | Shipped
2. Tokens (dots) per bead, moving through lanes. Color by priority, size by age.
3. Play/pause + 1x/2x/5x speed (removed scrub bar and 10x — scope trim)
4. **D3 + Canvas** for rendering (removed PM4JS — wrong tool, per P1-5. Removed SVG/Canvas hybrid — unnecessary complexity)
5. **Event accumulation uses DataPipe `getHistory()`** (removed custom accumulator — shared concern, per scope review)
6. State transitions detected by diffing consecutive snapshots

### Batch 3: Composition (after F0 + any 2 visuals + 1 data pipe)

**F10: Composition Shell** (Demarch-tr69)

Location: `apps/Meadowsyn/experiments/shell/`

Implementation:
1. Hash-based router: `/#/split-flap`, `/#/hydra`, `/#/graph`, `/#/raster`, `/#/loopy`, `/#/replay`
2. Data source selector (dropdown): **mock | static-json | sse** (removed websocket — it's a non-goal, addresses C1)
3. Uses F0 plugin interface: `init()` -> `activate()` -> `deactivate()` -> `destroy()`
4. **Transport swap via `dataPipe.setTransport()`** — preserves history (addresses P0-4)
5. Shared header bar: factory status summary + visual selector
6. Each visual loaded via `import()` from its `plugin.js`
7. **Visuals built with dual entry points in Batch 2** — no unbudgeted adapter work (addresses P1-9)
8. Removed: URL query-param serialization, keyboard shortcuts, fade transitions (scope trim)

## Library Versions (pinned)

| Library | Version | CDN | Size | License |
|---------|---------|-----|------|---------|
| D3 | 7.9.0 | jsDelivr | ~85kB gz | BSD |
| Cytoscape.js | 3.30.x | jsDelivr | ~100kB gz | MIT |
| cytoscape-fcose | 2.2.x | jsDelivr | ~27kB gz | MIT |
| hydra-synth | 1.3.x | unpkg | ~200kB gz | **AGPL-3.0** |
| TradingView LW Charts | 4.2.x | jsDelivr | ~35kB gz | Apache 2.0 |
| vis-timeline | 7.7.x | jsDelivr | ~186kB gz | MIT/Apache |

**Dropped**: PM4JS (wrong tool), EventDrops (unmaintained, D3 v4 lock-in), LiteGraph.js (unused).

## Verification

- **Batch 0**: Plugin contract TypeScript-style JSDoc types pass. DataPipe transport swap preserves history. Schema validates against real factory-status output.
- **Batch 1**: Mock data validates against schema. FetchTransport + SSETransport both deliver updates through DataPipe.
- **Batch 2**: Each visual renders with mock data via standalone `index.html`. Each `plugin.js` mounts/unmounts cleanly in a test harness.
- **Batch 3**: Shell loads all 6 visuals, swaps data sources without state loss.

## Commit Strategy

One commit per experiment. Push to `mistakeknot/meadowsyn` after each batch. F0 (shared contracts) commits first as the foundation.
