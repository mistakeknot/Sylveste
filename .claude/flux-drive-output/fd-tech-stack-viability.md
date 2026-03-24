---
agent: fd-tech-stack-viability
mode: review
target: docs/plans/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# Tech Stack Viability Review: Meadowsyn Experiments

Review of every browser library referenced in the Meadowsyn experiment plan.
Verdict per library: VIABLE, VIABLE WITH CAVEATS, or REPLACE.

---

## 1. hydra-synth (F3: Hydra Ambient Field)

**Verdict: VIABLE WITH CAVEATS**

| Attribute | Value |
|---|---|
| CDN URL | `https://unpkg.com/hydra-synth` or `https://cdn.jsdelivr.net/npm/hydra-synth` |
| npm version | 1.3.29 (latest) |
| Unpacked size | ~383 kB (npm); no official minified CDN build |
| License | AGPL-3.0 |
| Browser compat | All modern browsers with WebGL support. No IE11. |

### API: REPL-first, but programmatic is supported

Hydra was designed as a livecoding REPL (hydra.ojack.xyz). The npm package exposes a programmatic API:

```js
import Hydra from 'hydra-synth'
const hydra = new Hydra({ canvas: myCanvas, detectAudio: false, makeGlobal: false })
hydra.synth.osc(4, 0.1, 1.2).out()
```

**Critical for F3**: Parameters accept arrow functions as dynamic values. Hydra evaluates the function every frame and uses the return value. This is the bridge for data-driven visuals:

```js
// Factory metrics drive shader parameters
hydra.synth.osc(() => throughput * 0.5, 0.1, 1.2)
  .color(() => 1.0 - errorRate, () => 0.5 + utilization * 0.5, 0.3)
  .noise(() => queuePressure * 3)
  .out()
```

### Gotchas

1. **AGPL-3.0 license** -- This is copyleft. If Meadowsyn is distributed (even as a web app served to users), the entire source must be made available. For an internal/experimental tool this is fine. For a product, evaluate carefully.
2. **WebGL required** -- Renders to a WebGL canvas. Falls back to nothing if WebGL is unavailable (headless CI, some SSH tunnels). Plan test harnesses accordingly.
3. **No AudioContext by default** -- Set `detectAudio: false` to avoid microphone permission prompts. The plan already implies no audio.
4. **Global namespace pollution** -- In global mode (default), Hydra attaches `osc`, `noise`, `src`, etc. to `window`. Use `makeGlobal: false` for non-global mode and prefix everything with `hydra.synth.`.
5. **Vite/bundler quirk** -- Requires `define: { global: {} }` in Vite config to avoid "global is not defined" runtime errors.
6. **No official minified CDN build** -- The unpkg URL serves the unminified bundle. For production, either use a bundler or serve your own minified copy.
7. **setFunction for custom GLSL** -- For the "four visual states" in the plan, you may need `setFunction()` to define custom shader snippets. This is well-supported but documented primarily via the REPL docs, not the npm readme.

### Recommendation

Use non-global mode (`makeGlobal: false`). Pass factory metrics via arrow-function parameters. The plan's F3 spec is achievable as written. Note the AGPL license for long-term planning.

---

## 2. Cytoscape.js + cytoscape-fcose (F4: Agent Graph)

**Verdict: VIABLE**

### cytoscape

| Attribute | Value |
|---|---|
| CDN URL | `https://cdn.jsdelivr.net/npm/cytoscape@3.30/dist/cytoscape.min.js` |
| npm version | 3.30+ (latest stable ~3.30.x-3.33.x) |
| Minified size | ~365 kB |
| Gzipped size | ~112 kB |
| License | MIT |
| Browser compat | All modern browsers. Canvas-based rendering. |

### cytoscape-fcose

| Attribute | Value |
|---|---|
| CDN URL | `https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2.0/cytoscape-fcose.js` |
| npm version | 2.2.0 |
| License | MIT |
| Gzipped size | ~15 kB (small; main cost is cytoscape itself) |

### Constraint-based positioning: YES

fCoSE supports exactly the constraint types the plan needs:

- **Fixed position constraints**: Pin specific nodes to exact coordinates
- **Alignment constraints**: Align nodes vertically or horizontally (agent ring)
- **Relative placement constraints**: `{ top: 'n1', bottom: 'n2', gap: 100 }` etc.
- **Incremental constraints**: Can add constraints to an existing layout without full recompute

The plan's spec ("agent nodes in outer ring, bead nodes center") maps directly to alignment + relative placement constraints.

### CDN usage

```html
<script src="https://cdn.jsdelivr.net/npm/cytoscape@3.30/dist/cytoscape.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2.0/cytoscape-fcose.js"></script>
<script>
  cytoscape.use(cytoscapeFcose);
</script>
```

### Gotchas

1. **Layout recomputation cost** -- fCoSE layout on 20 agents + beads (plan spec) is fast (~50ms). At 200+ nodes, layout can take 200-500ms. For live updates every 5s, diff the graph (add/remove/style changes) rather than re-running layout on every update.
2. **Canvas rendering** -- Cytoscape renders to canvas, not SVG. This means you cannot style nodes with CSS pseudo-elements. All styling goes through Cytoscape's style API.
3. **Combined bundle ~127 kB gzipped** -- Acceptable for a standalone experiment.

### Recommendation

Fully viable. Use incremental layout updates (only re-layout when topology changes, not on every style update). Pin the CDN versions.

---

## 3. PM4JS (F7: Process Replay)

**Verdict: VIABLE WITH CAVEATS -- consider whether you actually need it**

| Attribute | Value |
|---|---|
| CDN URL | `https://cdn.jsdelivr.net/npm/pm4js/dist/pm4js_latest.js` |
| npm version | latest on npm |
| License | Apache-2.0 (pm4js-core repo) |
| Browser compat | Modern browsers (Chrome confirmed). Single portable JS file. |
| Last commit | Aug 2023 (pm4js-core) |
| Stars | 38 |

### Browser build: YES

PM4JS provides `dist/pm4js_latest.js` as a single file for browser inclusion. No Node.js required. The library operates entirely client-side: load CSV/XES event logs in browser memory, apply process mining algorithms (Inductive Miner, Alpha Miner), render process trees as SVG.

### But does F7 actually need PM4JS?

Re-reading the F7 spec: it describes a **playback visualization** of bead state transitions through swim lanes, not process mining (discovery, conformance checking). F7 needs:
- A timeline scrub bar
- Token animation through lanes
- State transition detection from snapshots

This is a custom D3/Canvas animation, not process mining. PM4JS would be useful if you want to:
- Discover the actual process model from event logs (Inductive Miner)
- Check conformance of observed behavior against an expected model
- Generate directly-follows graphs

### Gotchas

1. **Bundle size unknown but likely large** -- The library bundles XES/CSV parsers, multiple mining algorithms, Petri net support, BPMN, OCEL. For F7's needs, this is massive overkill.
2. **Low community adoption** -- 38 GitHub stars, last commit Aug 2023. Not abandoned but not actively developed.
3. **No CDN-hosted minified build** -- The `dist/pm4js_latest.js` is the full unminified library.

### Alternatives if you DO want process mining later

- **D3 + custom code**: For the F7 spec as written, D3 force layouts or vanilla Canvas animation is sufficient and much lighter.
- **yFiles for HTML**: Commercial ($$$), but the most complete graph/process visualization library for JS.

### Recommendation

**Skip PM4JS for F7.** The process replay experiment is a custom animation, not process mining. Build it with D3 + Canvas as the plan already suggests ("SVG/Canvas hybrid: SVG for lanes/labels, Canvas for token animation"). If you later want to add actual process discovery, PM4JS can be added then.

---

## 4. D3.js: v7 vs v6

**Verdict: Standardize on D3 v7 (v7.9.0)**

| Attribute | Value |
|---|---|
| CDN URL | `https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js` |
| Latest version | 7.9.0 |
| Minified size | ~280 kB |
| Gzipped size | ~85 kB |
| License | ISC |

### Why v7, not v6

1. **v7 is the current stable** -- v7.9.0 is the latest release. There is no v8. v6 is two major versions behind the community.
2. **ES modules** -- v7 ships as pure ESM. For CDN `<script>` usage, the UMD build at `d3.min.js` still works. But if you ever move to a bundler, v7 is ready.
3. **Event handling is the same as v6** -- The major event-handling change happened in v5->v6 (removing `d3.event` global, passing events as first arg to listeners). v6->v7 did NOT change event handling. So there is zero migration cost.

### Breaking changes v6 -> v7 (minor for this project)

| Change | Impact on Meadowsyn |
|---|---|
| ESM-only source (UMD still provided for CDN) | None -- using CDN UMD build |
| `d3.bin` ignores nulls | None -- not using histograms |
| `d3.ascending`/`d3.descending` reject null | Low -- clean mock data |
| InternMap for ordinal domains | None -- no ordinal scales in plan |
| Requires Node 12+ | None -- browser-only |

### Event handling pattern (same in v6 and v7)

```js
selection.on('click', (event, d) => {
  console.log(event.target, d);
});
```

This is the pattern for F6 (Loopy Signals) click-to-perturb and F5 (heatmap) hover tooltips.

### Recommendation

All experiments should use `<script src="https://cdn.jsdelivr.net/npm/d3@7/dist/d3.min.js"></script>`. No reason to use v6.

---

## 5. TradingView Lightweight Charts

**Verdict: VIABLE (not in current plan, but noted for future)**

| Attribute | Value |
|---|---|
| CDN URL (standalone) | `https://unpkg.com/lightweight-charts/dist/lightweight-charts.standalone.production.js` |
| CDN URL (jsDelivr) | `https://cdn.jsdelivr.net/npm/lightweight-charts/dist/lightweight-charts.standalone.production.js` |
| Latest version | 5.1.x |
| Standalone size | ~35 kB gzipped (v5), ~45 kB (v4) |
| License | Apache-2.0 (with attribution requirement) |
| Browser compat | All modern browsers. Canvas-based. |

### Standalone embedding: YES, no React needed

```html
<script src="https://unpkg.com/lightweight-charts/dist/lightweight-charts.standalone.production.js"></script>
<script>
  const chart = LightweightCharts.createChart(document.getElementById('chart'));
  const lineSeries = chart.addSeries(LightweightCharts.LineSeries);
  lineSeries.setData([{ time: '2026-03-21', value: 42 }]);
</script>
```

The standalone script adds `LightweightCharts` as a global variable. No build tools required.

### Gotchas

1. **Attribution required** -- License requires "specifying TradingView as the product creator." Must display TradingView branding.
2. **v4 -> v5 breaking changes** -- API changed significantly (series creation, watermark API). Pin your version.
3. **Financial-chart-oriented** -- Time axis is date-based, not arbitrary. Works well for throughput-over-time but awkward for non-temporal data.

### Recommendation

Not referenced in the current plan but would be excellent for a "throughput over time" sparkline in the composition shell header. Pin to v5.x if used.

---

## 6. vis-timeline vs EventDrops

**Verdict: vis-timeline VIABLE; EventDrops REPLACE**

### vis-timeline

| Attribute | Value |
|---|---|
| CDN URL (standalone UMD) | `https://unpkg.com/vis-timeline@latest/standalone/umd/vis-timeline-graph2d.min.js` |
| CDN URL (jsDelivr) | `https://cdn.jsdelivr.net/npm/vis-timeline/standalone/umd/vis-timeline-graph2d.min.js` |
| Latest version | 7.7.x |
| Gzipped size | ~186 kB (standalone, includes all deps) |
| License | MIT or Apache-2.0 |
| Last updated | Mar 2026 (actively maintained) |
| Browser compat | All modern browsers. DOM-based rendering. |

**Standalone build notes**: The standalone build bundles all dependencies (moment.js, vis-data, vis-util) -- great for prototypes, but ~186 kB gzipped is heavy. The "peer build" is lighter (~80 kB) but requires separate vis-data inclusion.

**Gotchas**:
1. **Moment.js bundled in standalone** -- Adds weight. If you only need the timeline (not Graph2D), there is no separate timeline-only standalone.
2. **DOM-based rendering** -- Items are actual DOM elements, which means CSS styling is easy but performance degrades above ~1000 concurrent items.
3. **CSS required** -- Must also load `vis-timeline-graph2d.min.css` or the timeline renders without styling.

### EventDrops

| Attribute | Value |
|---|---|
| CDN URL | `https://unpkg.com/event-drops` (available but outdated) |
| npm version | 1.3.0 |
| Last published | ~7 years ago |
| D3 dependency | d3 ~4.7.0 (peerDependency) |
| License | MIT |
| Status | **UNMAINTAINED** |

**Critical problem**: EventDrops depends on D3 v4.x. The plan standardizes on D3 v7. The D3 v4 -> v7 gap includes two major breaking changes in event handling (v5 removed `d3.event`, v7 added ESM). There is an open PR for D3 v6 compatibility that was never merged. No fork exists with D3 v7 support.

### Recommendation

**Use vis-timeline for standalone timeline prototypes.** It is actively maintained, has a CDN standalone build, and works without a bundler.

**Do not use EventDrops.** It is unmaintained and locked to D3 v4 which conflicts with the D3 v7 standard. If you need an event-drops-style visualization (dots on a timeline), build it with D3 v7 directly -- it is ~50 lines of code for basic event dots on a time axis.

---

## Summary Table

| Library | Experiment | CDN? | Gzipped | License | Verdict |
|---|---|---|---|---|---|
| hydra-synth | F3 Ambient | Yes (unpkg, jsdelivr) | ~150-200 kB est. | AGPL-3.0 | VIABLE WITH CAVEATS |
| cytoscape | F4 Graph | Yes (jsdelivr, cdnjs, unpkg) | ~112 kB | MIT | VIABLE |
| cytoscape-fcose | F4 Graph | Yes (jsdelivr) | ~15 kB | MIT | VIABLE |
| PM4JS | F7 Replay | Yes (jsdelivr) | Unknown (large) | Apache-2.0 | SKIP (not needed) |
| D3 v7 | F5, F6, F7 | Yes (jsdelivr, cdnjs, unpkg) | ~85 kB | ISC | VIABLE (standardize on v7) |
| lightweight-charts | (future) | Yes (unpkg, jsdelivr) | ~35 kB | Apache-2.0 | VIABLE |
| vis-timeline | (future) | Yes (unpkg, jsdelivr, cdnjs) | ~186 kB standalone | MIT/Apache-2.0 | VIABLE |
| EventDrops | (future) | Technically | ~20 kB | MIT | REPLACE (unmaintained, D3 v4 only) |

## Action Items for Plan Author

1. **Add `makeGlobal: false` and `detectAudio: false`** to the F3 hydra-synth spec. Note the AGPL license.
2. **Pin CDN versions** in all experiments (e.g., `cytoscape@3.30.4`, not `@latest`). Reproducibility matters.
3. **Remove PM4JS from F7 scope.** F7 is a custom animation, not process mining. D3 + Canvas is correct.
4. **Standardize D3 v7.9.0** across F5, F6, F7. Add to F1/F8 if any data formatting uses D3 utilities.
5. **Note total payload**: If the composition shell (F10) loads all experiments, the combined JS payload is ~550-600 kB gzipped (hydra + cytoscape + fcose + D3 + experiment code). Lazy loading per the plan is essential.
