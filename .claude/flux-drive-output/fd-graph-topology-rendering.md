# Flux Drive: Graph Topology & Rendering Feasibility

**Context:** Meadowsyn entity model brainstorm (Sylveste-jpum). Evaluating Cytoscape.js layout engines and rendering strategies for production scale: 61 agents + 500+ beads + cross-project edges across 42 projects.

**Prototypes evaluated:**
- `apps/Meadowsyn/experiments/hydra-graph/index.html` — cose layout, separate glow canvas, iframe-hosted
- `apps/Meadowsyn/experiments/cytoscape-graph/index.html` — fCoSE via CDN, standalone page

---

## 1. Layout Convergence at Scale

### cose (built-in)

The built-in `cose` layout is a simplified force-directed simulation. At the current prototype's 28 nodes (16 agents + 12 beads), it converges in ~200ms with `numIter: 300`. Scaling characteristics:

- **100 nodes:** ~400ms, acceptable
- **500 nodes:** ~2-4s with `numIter: 300`. The algorithm is O(n^2) per iteration (all-pairs repulsion). At 561 nodes (61 agents + 500 beads), expect 3-5s for initial layout.
- **1000+ nodes:** >8s. Unusable for live updates.

The hydra-graph prototype sets `randomize: true` on every topology change, which forces a full re-layout from scratch. This is the primary performance problem — not the algorithm itself.

### fCoSE (cytoscape-fcose)

fCoSE uses a multi-level coarsening strategy (Harel-Koren) that reduces the graph to a smaller proxy, solves the proxy, then uncoarsens. This gives dramatically better convergence:

- **500 nodes:** ~800ms-1.5s initial, ~200-400ms incremental (if `randomize: false`)
- **1000 nodes:** ~2-3s initial, still under 1s incremental

**The iframe failure is a known issue.** The CDN build of `cytoscape-fcose@2.2.0` calls `cytoscape.use(fcose)` on load, which requires `cytoscape` to be on `window` at script parse time. Inside an iframe, if `cytoscape` loads after `fcose` (race condition from CDN parallel fetch), the registration silently fails. The layout name `'fcose'` is never registered, Cytoscape falls back to `null` layout, and nodes stack at (0,0).

**Fix:** Either (a) use a bundler (Vite/esbuild) to control load order, or (b) add an explicit registration check after both scripts load:

```javascript
if (!cytoscape.extensions().layout.fcose) {
  cytoscape.use(cytoscapeFcose);
}
```

Or use `<script>` tags with `defer` in dependency order (cytoscape first, fcose second — not `async`).

### cose-bilkent

CoSE-Bilkent is the compound-node-aware variant. It handles parent/child containment natively but is the slowest of the three:

- **500 nodes (100 compound parents):** ~3-6s. The compound node constraint adds a containment force per parent that must converge alongside the inter-node repulsion.
- **1000 nodes:** >10s.

CoSE-Bilkent via CDN (`cytoscape-cose-bilkent@4.1.0`) has the same registration race as fCoSE. Same fix applies. The CDN build is also 95KB unminified — heavier than fCoSE (42KB).

**Verdict:** fCoSE is the right layout engine. CoSE-Bilkent is too slow at scale and only needed if compound nodes are used for containment (see below for why they shouldn't be).

---

## 2. Compound Nodes & Cross-Compound Edges

Cytoscape.js compound nodes have a fundamental constraint: **a node can have exactly one parent**. For the Meadowsyn model:

- An agent that works across 3 projects can only be a child of one project compound node.
- A bead dependency edge from Project A's bead to Project B's bead creates a cross-compound edge. Cytoscape renders this correctly, but CoSE-Bilkent's containment forces fight the edge's attraction, causing oscillation or convergence to a local minimum where one cluster is distorted.

**Cross-compound edge behavior:**
- Rendering: works. Edges draw across compound boundaries.
- Layout: problematic. CoSE-Bilkent treats compound boundaries as hard constraints. A strong dependency chain across 3 compounds will stretch the layout or cause one compound to balloon to accommodate the edge routing.
- Interaction: `node.parent()` returns the single compound parent. Multi-project agents would need a secondary data model (`node.data('projects')`) and manual visual bridges.

**Re-parenting for tab-switch views** (the brainstorm's Approach A) requires removing nodes from one parent and adding to another. Cytoscape.js does not support re-parenting in-place — you must `cy.remove(node)` then `cy.add()` with a new `parent` field. For 500+ nodes switching from project-view to theme-view, this means removing and re-adding every node, which triggers a full re-layout.

**Verdict:** Compound nodes are the wrong abstraction for this use case. The multi-membership problem (agents across projects), the cross-compound layout instability, and the re-parenting cost all argue against Approaches A and C.

---

## 3. Gravity Clustering Without a Plugin

The brainstorm's Approach B/D proposes gravity centers per project. Two implementation paths:

### Option 1: Invisible Anchor Nodes with Strong Edges (Cytoscape-native)

Create one invisible node per project. Add high-weight edges from each agent/bead to its project's anchor. Use fCoSE with `fixedNodeConstraint` to pin anchor positions or let them settle naturally.

```javascript
// Per project: invisible anchor
{ data: { id: 'anchor-interflux', type: 'anchor' }, style: { visibility: 'hidden', width: 1, height: 1 } }
// Per member: strong edge to anchor
{ data: { source: 'agent-sleeper', target: 'anchor-interflux', weight: 5 } }
```

fCoSE supports `alignmentConstraint` and `relativePlacementConstraint` which can pin anchors to a grid. Combined with high `idealEdgeLength` for inter-cluster edges and short lengths for intra-cluster edges, this produces reliable clusters.

**Strengths:**
- No extra library. Pure Cytoscape.js + fCoSE.
- fCoSE's constraint system is specifically designed for this — `fixedNodeConstraint` pins anchors, `alignmentConstraint` keeps rows/columns.
- Tab-switch re-grouping: just change which anchor each node connects to, then re-run layout. No re-parenting needed.

**Weaknesses:**
- Anchor edges inflate edge count (500 extra edges for 500 beads). fCoSE handles this fine — edges are cheap, it's nodes that are expensive.
- Cluster boundaries are soft (overlap possible), not hard boxes.

### Option 2: D3-force Hybrid

Use D3-force for layout, Cytoscape.js only for rendering. D3-force's `forceX`/`forceY` with per-group centers gives cleaner gravity clustering. But this means abandoning Cytoscape's layout engine entirely — you'd compute positions in D3 and set them via `node.position()`.

**Not recommended.** It doubles the complexity (two layout engines), loses Cytoscape's incremental layout, and D3-force at 500+ nodes is similarly O(n log n) per tick with Barnes-Hut, giving no speed advantage.

**Verdict:** Option 1 (invisible anchors + fCoSE constraints) is the right approach. It stays within one layout engine, supports incremental updates, and handles tab-switch re-grouping cleanly.

---

## 4. Ambient Canvas Compositing at Scale

The hydra-graph prototype creates one radial gradient per node per frame:

```javascript
glowNodes.forEach(function(g) {
  var grad = glowCtx.createRadialGradient(g.x, g.y, 0, g.x, g.y, g.radius);
  // 3 color stops
  glowCtx.fillStyle = grad;
  glowCtx.fillRect(/* bounding box */);
});
```

### Performance Analysis

Each `createRadialGradient` + `fillRect` is a GPU-composited operation. Cost per node:
- Gradient creation: ~0.01ms
- Fill with gradient: ~0.02-0.05ms (depends on radius; 140px radius = ~61K pixels)

At 500 nodes: ~15-25ms per frame. At 60fps budget of 16.6ms, this is already over budget. At 561 nodes with 140px radius glows, many overlapping, the GPU fill rate becomes the bottleneck.

### Optimization Strategy

**Tier 1: Cull invisible glows.** Idle nodes have `intensity: 0.06`. At 60% idle rate, ~340 nodes can be skipped with a threshold check (`if (g.intensity < 0.08) return`). This cuts the render set to ~220 active glows.

**Tier 2: Reduce glow resolution.** Render the glow canvas at 0.5x resolution (half the DPR). Glow is inherently blurry — half resolution is visually indistinguishable. This cuts fill rate by 4x.

```javascript
glowCanvas.width = W * dpr * 0.5;
glowCanvas.height = H * dpr * 0.5;
glowCtx.setTransform(dpr * 0.5, 0, 0, dpr * 0.5, 0, 0);
```

**Tier 3: Pre-render gradient textures.** Instead of creating a new `RadialGradient` per node per frame, pre-render 6 gradient textures (one per status color) to offscreen canvases at initialization. Then use `drawImage` with alpha to stamp them:

```javascript
// Init: one offscreen canvas per status
const glowTextures = {};
for (const [status, color] of Object.entries(GLOW_COLORS)) {
  const off = new OffscreenCanvas(GLOW_RADIUS * 2, GLOW_RADIUS * 2);
  const ctx = off.getContext('2d');
  const grad = ctx.createRadialGradient(GLOW_RADIUS, GLOW_RADIUS, 0,
    GLOW_RADIUS, GLOW_RADIUS, GLOW_RADIUS);
  grad.addColorStop(0, `rgba(${color.r},${color.g},${color.b},1)`);
  grad.addColorStop(0.4, `rgba(${color.r},${color.g},${color.b},0.4)`);
  grad.addColorStop(1, `rgba(${color.r},${color.g},${color.b},0)`);
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, GLOW_RADIUS * 2, GLOW_RADIUS * 2);
  glowTextures[status] = off;
}

// Per frame: drawImage with globalAlpha
glowCtx.globalAlpha = g.intensity;
glowCtx.drawImage(glowTextures[status],
  g.x - g.radius, g.y - g.radius, g.radius * 2, g.radius * 2);
glowCtx.globalAlpha = 1;
```

`drawImage` from an offscreen canvas is a single GPU blit — 5-10x faster than creating + filling a gradient.

**Tier 4: Project aura as separate pass.** Don't compute project aura per-frame from node positions. Instead, update project aura positions every 500ms (projects don't move fast) and render them as large, very low-alpha blits before the per-node pass.

**Combined effect:** Tiers 1-3 together bring 500-node glow rendering from ~25ms to ~3-5ms per frame. Well within 60fps budget.

**OffscreenCanvas + Worker:** Not recommended yet. The synchronization overhead of posting positions to a worker and receiving back an ImageBitmap adds latency. Only worth it if Tier 1-3 aren't enough (they will be).

---

## 5. Incremental Updates Without Full Re-layout

The hydra-graph prototype's critical mistake: `needsLayout = true` on any node add/remove, followed by `randomize: true` in the layout config. This throws away all spatial memory on every topology change.

### fCoSE Incremental Strategy

fCoSE supports `randomize: false`, which uses current node positions as the starting point. Combined with the invisible anchor pattern:

```javascript
function incrementalLayout(addedNodes, removedNodeIds) {
  // Position new nodes near their anchor
  for (const node of addedNodes) {
    const anchor = cy.getElementById(`anchor-${node.data('project')}`);
    if (anchor.length) {
      const pos = anchor.position();
      node.position({
        x: pos.x + (Math.random() - 0.5) * 100,
        y: pos.y + (Math.random() - 0.5) * 100,
      });
    }
  }

  // Run layout with existing positions as starting point
  cy.layout({
    name: 'fcose',
    randomize: false,          // KEY: use current positions
    animate: true,
    animationDuration: 400,
    quality: 'default',        // not 'proof' — faster convergence
    nodeRepulsion: 4500,
    idealEdgeLength: 80,
    numIter: 100,              // fewer iterations for incremental
  }).run();
}
```

### Tick Budget

With `randomize: false` and `numIter: 100`, fCoSE at 500 nodes converges in ~200-400ms. At a 5-second update interval, this uses <10% of the available time. The layout runs asynchronously (Cytoscape's layout API is non-blocking with `animate: true`), so the UI thread is not blocked.

### Data-only Updates (No Topology Change)

When a tick only changes node colors/statuses (no adds/removes), skip layout entirely. The current prototype already tracks `needsLayout` — just ensure it's only set on actual topology changes, not data updates.

```javascript
// Only trigger layout if nodes were added or removed
if (addedNodes.length > 0 || removedNodeIds.length > 0) {
  incrementalLayout(addedNodes, removedNodeIds);
}
// Status/color updates: just mutate data, no layout
```

---

## 6. Position Persistence (Spatial Memory)

Straightforward with Cytoscape.js:

### Save

```javascript
function savePositions() {
  const positions = {};
  cy.nodes().forEach(node => {
    positions[node.id()] = node.position();
  });
  localStorage.setItem('meadowsyn-positions', JSON.stringify(positions));
}

// Save on layout stop + debounced on drag
cy.on('layoutstop', savePositions);
cy.on('dragfree', 'node', debounce(savePositions, 1000));
```

### Restore

```javascript
function restorePositions() {
  const saved = JSON.parse(localStorage.getItem('meadowsyn-positions') || '{}');
  let restored = 0;
  cy.nodes().forEach(node => {
    if (saved[node.id()]) {
      node.position(saved[node.id()]);
      restored++;
    }
  });
  return restored;
}

// On init: restore if available, otherwise run full layout
const restoredCount = restorePositions();
if (restoredCount < cy.nodes().length * 0.5) {
  // Too many new nodes — run full layout but seed from saved positions
  runFullLayout();
} else {
  cy.fit();
}
```

### Staleness

Positions become stale when many nodes are added/removed between sessions. The 50% threshold above handles this — if fewer than half the current nodes have saved positions, fall back to a full layout. Anchor positions should also be saved so the overall project topology is preserved even when individual nodes churn.

### Storage Budget

At 561 nodes, each position is ~40 bytes JSON (`{"x":123.45,"y":678.90}`). Total: ~22KB. Well within localStorage limits (5-10MB).

---

## Approach Evaluation Summary

| Criterion | A: Compound | B: Gravity | C: Hybrid | D: Gravity+Canvas |
|-----------|:-----------:|:----------:|:---------:|:-----------------:|
| Layout speed at 500 nodes | Slow (cose-bilkent 3-6s) | Fast (fCoSE 800ms) | Slow (cose-bilkent) | Fast (fCoSE 800ms) |
| Cross-project edges | Broken (oscillation) | Clean | Broken | Clean |
| Tab-switch re-grouping | Expensive (re-parent) | Cheap (swap anchors) | Expensive | Cheap |
| Incremental updates | Poor (compound constraints) | Good | Poor | Good |
| Ambient integration | N/A (no canvas) | Needs canvas | Two systems | Native |
| Implementation complexity | Medium | Medium | High | Low-Medium |

---

## Recommendation

**Use Approach D: Gravity + Ambient Canvas**, implemented as:

1. **Layout engine: fCoSE** with invisible anchor nodes per project. Pin anchors using `fixedNodeConstraint` on a hex grid (avoids the regular-grid look while maximizing space). Load via bundler (Vite), not CDN, to eliminate the registration race condition.

2. **Clustering: Invisible anchor pattern.** One hidden anchor node per project. Strong short edges from members to their anchor. Weak long edges for cross-project bead dependencies. Tab-switch re-grouping swaps anchor connections and re-runs `randomize: false` layout (~300ms).

3. **Ambient rendering: Pre-rendered gradient textures** stamped via `drawImage` at 0.5x resolution. Project aura as large pre-computed blits updated every 500ms. Per-node glow culled below threshold. Target: <5ms per frame at 500 nodes.

4. **Incremental updates:** New nodes positioned near their anchor, then `randomize: false` layout with `numIter: 100`. Data-only changes (status/color) skip layout entirely. 5-second tick budget is ample.

5. **Position persistence:** Save to localStorage on `layoutstop` and `dragfree`. Restore on load with 50% staleness threshold. Save anchor positions separately for stable project topology.

6. **Project aura (visual boundaries):** Compute convex hull of each project's nodes every 500ms. Render as a large, low-alpha gaussian blob on the glow canvas (not a Cytoscape element). This makes the ambient field the container, not boxes — matching the Cybersyn aesthetic.

### Migration Path from Current Prototype

The hydra-graph prototype is 80% reusable. Changes needed:
- Replace `cose` with `fcose` via bundler import
- Add anchor node generation from project data
- Change `randomize: true` to `randomize: false` after initial layout
- Add gradient texture pre-rendering (6 textures at init)
- Add `0.5x` resolution scaling to glow canvas
- Add localStorage position save/restore
- Add convex hull computation for project aura (simple Graham scan — 42 projects, <1ms total)
