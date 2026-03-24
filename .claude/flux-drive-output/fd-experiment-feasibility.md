---
agent: fd-experiment-feasibility
mode: review
target: docs/plans/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# Feasibility Review: Meadowsyn Experiment Suite

## Cross-Cutting: ES Module Imports Under `file://` Protocol

**Severity: P0 -- Blocks All Experiments**

ES module imports (`import ... from '../data-static/data-pipe.js'`) are **blocked by CORS under `file://` protocol** in all modern browsers. The browser assigns origin `null` to file:// URLs and refuses cross-origin module fetches, even for sibling directories on the same filesystem. The error is:

> Access to script at 'file:///...' from origin 'null' has been blocked by CORS policy

This affects every experiment in Batch 2 (F2-F7) that imports from `../mock-data/` or `../data-static/`. The plan says F8 "Works with `file://` (via imported mock data)" -- this is false for ES module imports.

**Mitigations (choose one):**
1. **Require a local server** -- add a one-liner to each experiment's README: `npx serve .` or `python3 -m http.server`. This is the simplest fix. F9 (SSE pipe) already provides a server, so once F9 exists this resolves naturally.
2. **Inline mock data** -- each experiment bundles its own copy of mock data as a `<script>` tag (global var, not module import). Eliminates cross-file imports entirely. Duplicates data but keeps experiments truly standalone.
3. **Use importmap with `esm.sh`** -- wrap local modules behind an import map that maps bare specifiers to `esm.sh` URLs. Only works online.

**Recommendation:** Option 1. Add a root-level `serve.sh` that starts a static server from `apps/Meadowsyn/experiments/`. Document that `file://` is unsupported. This is a 5-minute fix but must be decided before any experiment is built.

---

## F3: Hydra Ambient Field

**Severity: P2 -- Minor Adjustment**

### CDN Availability
hydra-synth v1.4.0 is available on both jsDelivr and unpkg:
- UMD: `https://cdn.jsdelivr.net/npm/hydra-synth/dist/hydra-synth.js`
- ESM: `https://cdn.jsdelivr.net/npm/hydra-synth/+esm`

The UMD bundle works with a plain `<script>` tag (no bundler needed). It exposes a global `Hydra` constructor. The ESM build via jsDelivr's `+esm` suffix should also work for `<script type="module">` imports.

### ES Module Without Bundler
Yes, this works. The documented pattern is:
```html
<script src="https://cdn.jsdelivr.net/npm/hydra-synth/dist/hydra-synth.js"></script>
<script>
  var hydra = new Hydra({ detectAudio: false, canvas: myCanvas })
  osc(4, 0.1, 1.2).out()
</script>
```
The UMD script tag approach is simplest and avoids any bundler dependency. If ES module imports are needed (e.g., for the composition shell), the `+esm` CDN suffix provides that.

### AudioContext / User Gesture
Hydra uses WebGL for rendering (not WebAudio), so **no user gesture is required for visual output**. Audio detection is optional and disabled with `detectAudio: false`. The plan already specifies no audio/sonification (listed as non-goal). No gesture gate needed.

### WebGL Requirement
Hydra compiles shaders to WebGL. This is fine for desktop Chrome/Firefox/Edge but worth noting in docs. The PRD acceptance criterion "Runs at 60fps on a 2020-era laptop" is achievable -- Hydra is designed for real-time livecoding on modest hardware.

### Canvas Auto-Creation
If no canvas element is passed, Hydra auto-creates a full-screen canvas. The plan's "Initialize Hydra on a full-screen `<canvas>`" is the default behavior. Pass `{ canvas: el }` to target a specific element for the composition shell.

**Verdict:** No blockers. Use UMD script tag. Set `detectAudio: false`. Note WebGL requirement in experiment README.

---

## F4: Cytoscape fCoSE

**Severity: P1 -- Significant Rework Needed for Ring Layout**

### CDN Availability
Both packages are on jsDelivr:
- Cytoscape.js: `https://cdn.jsdelivr.net/npm/cytoscape/dist/cytoscape.min.js`
- cytoscape-fcose v2.2.0: `https://cdn.jsdelivr.net/npm/cytoscape-fcose/cytoscape-fcose.js`

Both work as UMD script tags without a bundler.

### Constraint API
fCoSE supports three constraint types:
1. **`fixedNodeConstraint`** -- pin nodes to exact `{x, y}` positions
2. **`alignmentConstraint`** -- align nodes vertically/horizontally
3. **`relativePlacementConstraint`** -- constrain relative positions (e.g., "n1 above n2 by 100px")

### Ring Layout Problem
The plan says "fCoSE layout with constraints: agent nodes in outer ring, bead nodes center." **fCoSE has no built-in ring/circular constraint.** There is no "region constraint" or "ring constraint" in the API. You cannot say "put these nodes in a ring."

**Workaround:** Pre-calculate ring positions using trigonometry and pass them as `fixedNodeConstraint` entries. fCoSE then optimizes the remaining (bead) nodes via force-directed layout while respecting the fixed agent positions:

```js
const agentPositions = agents.map((a, i) => ({
  nodeId: a.id,
  position: {
    x: centerX + radius * Math.cos(2 * Math.PI * i / agents.length),
    y: centerY + radius * Math.sin(2 * Math.PI * i / agents.length)
  }
}));
// Pass as: layout: { name: 'fcose', fixedNodeConstraint: agentPositions }
```

This works but means:
- Agent positions are static (no force-directed movement for agents)
- Radius must be recalculated when agent count changes
- The "ring" is manually computed, not emergent from the layout

**Alternative:** Cytoscape's built-in `circle` layout for agents, then run fCoSE only on bead nodes. Or use `cytoscape-cise` (Circular Spring Embedder) which natively supports clusters arranged in circles. However, cise is less maintained than fcose.

**Verdict:** Feasible with manual ring calculation via `fixedNodeConstraint`. Add ~30 lines of ring geometry code. Not a blocker but the plan should note this is manual positioning, not a constraint-driven ring.

---

## F7: PM4JS Process Replay

**Severity: P1 -- Significant Rework; D3 Fallback Recommended**

### Browser Build
PM4JS (v0.0.38, last published Oct 2023) does provide a browser dist file: `dist/pm4js_latest.js`. It is available on jsDelivr. However:

1. **Stale maintenance** -- v0.0.38, no updates in 2+ years. Pre-1.0 quality.
2. **Visualization requires Graphviz** -- PM4JS generates Graphviz DOT notation for Petri nets and process trees. Rendering requires Viz.js (a WebAssembly port of Graphviz). This adds ~3MB of WASM payload.
3. **No built-in process flow rendering** -- PM4JS is a process mining *analysis* library (conformance checking, discovery algorithms), not a visualization library. It computes models but delegates rendering to external tools.
4. **BPMN layout missing** -- The docs explicitly state "The automatic layouting of the BPMN diagrams is still missing from the library."
5. **API surface mismatch** -- The plan needs animated tokens flowing through swim lanes with scrub controls. PM4JS provides process model discovery from event logs. These are different problems.

### Realistic D3 Fallback
The D3 fallback is not just realistic -- it is the **better choice** for F7's requirements:

- **Swim lanes**: SVG `<rect>` groups with D3 scales for lane boundaries
- **Tokens**: SVG `<circle>` elements animated with `d3.transition()` or `requestAnimationFrame`
- **Scrub bar**: HTML `<input type="range">` controlling a playback clock
- **Path animation**: D3's `path.getTotalLength()` + `path.getPointAtLength(t)` for smooth token movement along edges
- **Token count**: F7 needs maybe 20-50 tokens max (one per active bead), well within SVG performance limits

The hybrid approach (SVG for lanes/labels, Canvas for token animation) mentioned in the plan is overkill for this scale. Pure SVG with D3 will handle 50 tokens at 60fps without issue.

**Verdict:** Drop PM4JS. Use D3.js for F7 entirely. The PRD acceptance criterion "Uses PM4JS or D3 for rendering" already allows this. PM4JS adds complexity and a 3MB WASM dependency for capabilities F7 does not need.

---

## F6: Loopy Signal Propagation -- SVG Particle Performance

**Severity: P2 -- Minor Adjustment**

### 20+ Particles at 60fps in SVG
**Yes, this is easily achievable.** The performance concern threshold for SVG is around 2,000+ nodes. F6 specifies a fixed topology with ~6-8 nodes, ~8-10 edges, and animated particles proportional to throughput. Even at peak throughput, this means 20-50 particles.

Key performance data points:
- SVG handles hundreds of animated circles smoothly with `requestAnimationFrame`
- D3 `transition()` on SVG circles is GPU-composited (transform/opacity only)
- The critical technique: **reuse particle elements** rather than creating/destroying them. Maintain a particle pool, reposition with `transform: translate()`.
- `path.getPointAtLength(t)` is the standard technique for particles along SVG paths; well-supported and fast.

### Potential Gotcha
If particle animation uses `d3.timer()` or `requestAnimationFrame` to update `cx`/`cy` attributes directly (rather than CSS transforms), each update triggers a repaint. For 20-50 particles this is negligible, but prefer `transform` attribute over `cx`/`cy` for animation.

**Verdict:** No blockers. SVG + D3 with requestAnimationFrame handles this scale trivially. Use a particle pool pattern and animate via transforms.

---

## F5: Raster Heatmap -- Canvas Hover

**Severity: P2 -- Minor Adjustment**

### Pixel-to-Cell Mapping
The standard approach works well:
```js
canvas.addEventListener('mousemove', (e) => {
  const rect = canvas.getBoundingClientRect();
  const x = e.clientX - rect.left;
  const y = e.clientY - rect.top;
  const col = Math.floor(x / cellWidth);
  const row = Math.floor(y / cellHeight);
  showTooltip(row, col, e.clientX, e.clientY);
});
```

### Known Gotchas

1. **DPI scaling** -- On HiDPI displays, canvas CSS size and pixel buffer size differ. If `canvas.width` is set to `2 * canvas.clientWidth` for crisp rendering, mouse coordinates must be scaled accordingly. Fix: always use `getBoundingClientRect()` for mouse math, not `canvas.width`.

2. **Tooltip positioning** -- The tooltip must be a DOM element positioned over the canvas (not drawn on canvas), otherwise it gets erased on next canvas redraw. Use `position: fixed` with mouse coordinates.

3. **Redraw frequency** -- Re-sorting rows every 30s (per plan) means the row-to-agent mapping changes. The hover handler must reference the current sort order, not a stale mapping. Keep a `rowToAgent[]` array that updates on re-sort.

4. **Performance at scale** -- 20 agents x 24 columns = 480 cells. Canvas handles this trivially. Even 100 agents x 100 columns (10,000 cells) is fine. The grid in F5 is small enough that `getImageData` is unnecessary; simple coordinate math suffices.

5. **Mousemove throttling** -- Not strictly needed at 480 cells, but `requestAnimationFrame`-gated tooltip updates prevent unnecessary DOM thrashing on fast mouse movement.

**Verdict:** No blockers. Standard canvas coordinate math works. Document the DPI scaling gotcha. Keep tooltip as a DOM overlay.

---

## F2: Split-Flap Board -- CSS Animation at Scale

**Severity: P1 -- Needs Careful Implementation**

### Scale Analysis
20 agents x 60 characters = 1,200 `<span>` elements, each with `::before` and `::after` pseudo-elements = **3,600 DOM nodes** involved in animation. Not all animate simultaneously (only changed characters flip), but the DOM tree is large.

### Layout Thrashing Risk
The plan specifies CSS-only animation with `@keyframes flip` rotating halves. The critical performance factors:

1. **Use `transform: rotateX()` only** -- If the flip animation uses `transform` and `opacity`, it stays on the compositor thread and avoids layout/paint. Never animate `height`, `top`, `clip`, or `clip-path` for the flip effect.

2. **`will-change: transform`** -- Each flipping character needs this to be promoted to its own compositing layer. BUT: promoting all 1,200 characters creates 1,200+ layers, which **will** exhaust GPU memory on modest hardware and cause *worse* performance than no promotion.

3. **Selective promotion** -- Only apply `will-change: transform` to characters that are *currently animating*. Add it via a CSS class when the flip starts, remove it when the animation ends. At any given moment, only ~20-60 characters flip (one state change per agent = ~10-30 chars per agent, but only changed agents flip).

4. **Stagger delay** -- The "cascade effect" stagger delay means characters animate sequentially, not all at once. This naturally limits concurrent animations and reduces compositing pressure.

5. **Batch DOM reads/writes** -- When updating the board, read all current values first, then write all new values. Never interleave reads and writes (classic layout thrashing pattern).

### Font Loading
Roboto Mono / JetBrains Mono from Google Fonts adds a network dependency. Use `font-display: swap` to avoid FOIT (flash of invisible text). For `file://` usage (if the local server mitigation is adopted), self-host the font or use a system monospace fallback.

### Realistic Assessment
1,200 characters with CSS 3D transforms is within browser capabilities if done correctly. The React split-flap libraries on npm (e.g., `react-split-flap-effect`) have been demonstrated at similar scales. The key constraint is disciplined layer management.

**Verdict:** Feasible but requires careful implementation. Do NOT blanket-apply `will-change`. Use a `.flipping` class that enables GPU compositing only during active animation. Animate only with `transform: rotateX()` and `opacity`. Test on a 2020-era laptop early (the PRD's 60fps criterion for F3 should also apply here informally).

---

## Summary Table

| Finding | Severity | Experiment(s) | Action Required |
|---------|----------|---------------|-----------------|
| `file://` blocks ES module imports | **P0** | All (F2-F10) | Add `serve.sh` local server; document requirement |
| fCoSE has no ring constraint | **P1** | F4 | Pre-calculate ring positions with trig; use `fixedNodeConstraint` |
| PM4JS is wrong tool for F7 | **P1** | F7 | Drop PM4JS; use D3.js (PRD already allows this) |
| Split-flap layer management | **P1** | F2 | Selective `will-change`, animate only via `transform` |
| Hydra-synth CDN/ESM fine | **P2** | F3 | Use UMD script tag; set `detectAudio: false` |
| SVG particles fine at 20-50 | **P2** | F6 | Use particle pool; animate via transform attribute |
| Canvas hover is standard | **P2** | F5 | Handle DPI scaling; tooltip as DOM overlay |

## Recommendations for Plan Update

1. **Add a "Local Server Required" section** to the plan preamble. All experiments need `http://localhost` to work. A one-line `npx serve ../experiments` or the F9 SSE server satisfies this.

2. **F7: Replace PM4JS with D3** in both plan and PRD. PM4JS is a process mining analysis library, not a visualization library. D3 handles swim-lane token animation directly and is already a dependency of F6.

3. **F4: Document the manual ring calculation** as a known workaround. Consider whether CiSE (circular spring embedder) extension would be a better fit than fCoSE for the agent-ring topology.

4. **F2: Add performance constraints** to the implementation section: "Animate only via `transform: rotateX()`. Apply `will-change: transform` only during active flip via `.flipping` class. Remove after `animationend` event."

5. **F8: Revise `file://` claim.** The data-pipe cannot work under `file://` with ES module imports. Change to: "Requires `http://` (local server or deployed). See serve.sh."
