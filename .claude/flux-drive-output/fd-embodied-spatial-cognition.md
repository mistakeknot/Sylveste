# Flux Drive: Embodied Spatial Cognition Review

**Reviewer lens:** Spatial cognition, calm computing (Weiser), digital gardens (Appleton), ambient displays (Pousman & Stasko 2006)

**Input:** `docs/brainstorms/2026-03-24-meadowsyn-entity-model-brainstorm.md`, hydra-graph prototype, selector.html

---

## 1. Spatial Memory Stability

**The central problem:** The current hydra-graph prototype uses `randomize: true` in its cose layout (line 400). Every page load, every data update that triggers `needsLayout`, every tab-to-switch — the entire topology scrambles. This is **fatal for spatial memory**.

Spatial cognition research (Hund & Minarik 2006, Montello 2005) shows that people form **survey knowledge** — a map-like mental model — through repeated exposure to stable spatial configurations. When Intercore is always top-left and Clavain always center-right, the operator builds an unconscious sense of "where things live." Randomized layouts destroy this. The operator must re-orient every session, which means the display can never become peripheral — it demands focal attention just to parse the layout.

**Approach scores:**
- **A (Cytoscape Compound):** Can use deterministic initial positions but cose-bilkent still jitters between loads. Better than random, but compound relayout on tab-switch destroys positions.
- **B (Force-directed Gravity):** Worst for stability. Gravity centers help, but emergent clustering is non-deterministic by nature. Two loads with identical data produce different layouts.
- **C (Hybrid Compound + Canvas):** Same compound instability as A, plus sync overhead.
- **D (Gravity + Canvas):** Same instability as B.

**None of the four approaches solve this.** The brainstorm treats layout as a rendering concern when it is actually a **data model concern**. Projects need **assigned, persistent coordinates** — either hand-placed or computed once and saved. The layout engine should only handle intra-cluster arrangement of agents/beads within a project's assigned region, not the global topology.

**Design principle:** *Deterministic macro, organic micro.* Project positions are fixed (like rooms in a building). Agent/bead positions within a project are force-directed (like furniture that shifts slightly). The building never moves; the furniture breathes.

---

## 2. Peripheral Attention vs. "Show Everything"

The brainstorm's decision #5 — "Show everything, 500+ nodes, rely on ambient glow to guide attention" — needs qualification through the Pousman & Stasko taxonomy of ambient displays.

Their framework distinguishes:
- **Notification level:** What demands attention? (Anomalies only vs. continuous status)
- **Representational fidelity:** Iconic (abstract) vs. indexical (data-mapped) vs. symbolic (literal)
- **Information capacity:** Low (1-3 data points) vs. high (N data points)

The current hydra-graph prototype gets the ambient layer right: radial gradients at low opacity create a **low-fidelity, high-capacity** ambient field. Your eye genuinely is drawn to red/bright zones without conscious effort. This is good calm technology.

But overlaying 500+ labeled, individually-clickable nodes on top of that ambient field **destroys the calm.** At 500 nodes, the graph layer becomes a dense mesh that demands focal parsing. The ambient glow layer — which is the actual calm-computing channel — gets occluded by the graph.

**The 80/20 split is correct but inverted in the brainstorm.** The ambient glow should be the 80% channel (always visible, always peripheral). The graph detail — individual nodes, labels, edges — should be the 20% channel, revealed through zoom or hover, not rendered at the default zoom level.

**Approach scores:**
- **A (Compound):** Boxy containers with labels at all zoom levels. High visual density. Poor peripheral use.
- **B (Force Gravity):** Organic clustering but still renders all 500 nodes. Overlapping clusters create visual noise.
- **C (Hybrid):** Best potential — the canvas layer can operate independently as the calm channel while the graph layer can be semantically zoomed. But the brainstorm doesn't describe this separation.
- **D (Gravity + Canvas):** The ambient canvas *is* the container, which is the right instinct. But without explicit LOD (level-of-detail), it still renders 500 nodes.

**Design principle:** *Semantic zoom, not geometric zoom.* At default zoom, show only the ambient field (42 project auras) with aggregate health encoding. No individual nodes. As the user zooms into a project region, agents fade in. Zoom further, beads appear. Labels appear last. This is Shneiderman's "overview first, zoom and filter, details on demand" — but the overview is an ambient field, not a miniature graph.

---

## 3. Tab-to-Switch and Spatial Anchors

The brainstorm proposes Tab to cycle between project/theme/agent/bead views by "re-parenting/re-grouping the same nodes." This means 42 project clusters dissolve and reform as 10-15 theme clusters. Every node moves.

This is **catastrophic for spatial memory.** It is the equivalent of rearranging every room in a building when the user asks "show me by department instead of by floor." The operator loses all spatial anchors simultaneously.

Research on multiple coordinated views (Roberts 2007) shows that **linked highlighting across stable views** outperforms **view-switching that reorganizes a single view.** The operator should be able to see the project layout AND the theme grouping simultaneously, or at minimum, nodes should animate smoothly to their new positions with clear trajectory trails so the eye can track "where did Intercore go?"

**Better alternatives:**
1. **Overlay coloring, not repositioning.** Keep project positions fixed. Tab changes the *color encoding* — in theme mode, nodes are colored by theme instead of by status. Spatial positions don't move. The operator learns "the interflux beads are the blue ones scattered across these three projects."
2. **Split-screen.** Project view on left, theme view on right. Hover on one highlights the corresponding nodes in the other. Both views are always spatially stable.
3. **If positions must change,** animate with 800ms+ transitions and draw ghost trails from old to new positions. Fade the old layout out slowly (200ms) before snapping to the new one. But this is strictly inferior to option 1.

**Design principle:** *Color is cheap, position is expensive.* Change color encoding freely (status, theme, priority, agent type). Never move nodes to change the view mode. Position encodes project membership — the one thing that rarely changes.

---

## 4. Going Gray / Quiet Baseline with Anomaly Salience

Weiser's calm computing requires that the display is **informative when glanced at, ignorable when not needed.** The "going gray" principle: the default state should be so visually quiet that it functionally disappears into the environment. Anomalies — blocked agents, error spikes, stale dispatches — should be the *only* thing that pulls the display out of the peripheral.

The current prototype's intensity map is good:
```
idle: 0.06, dispatching: 0.22, executing: 0.25,
blocked: 0.35, gated: 0.28, shipped: 0.15
```

But it doesn't go far enough. A healthy factory with 40 executing agents produces a bright green field across the entire canvas. That is not "going gray" — it is "going green," which is still visually demanding.

**Approach scores:**
- **A (Compound):** Explicit box containers with labels are inherently high-visual-presence. Cannot go gray.
- **B (Force):** Nodes are always visible. Can dim but cannot disappear.
- **C (Hybrid):** The canvas layer can go fully gray (near-black ambient with no glow nodes). Best potential.
- **D (Gravity + Canvas):** Same potential as C. The ambient field can flatten to near-zero when healthy.

**Design principle:** *Healthy means invisible.* The baseline glow for "executing normally" should be barely perceptible — intensity 0.02-0.03, not 0.25. The operator should see a mostly-dark field with faint warm undertones when the factory is healthy. Only deviations from normal illuminate: a newly blocked agent flares red, a queue backup brightens a project aura. The display earns attention through contrast against silence, not through continuous ambient light.

Concrete intensity curve:
```
idle: 0.01, executing: 0.03, dispatching: 0.06,
shipped: 0.04, gated: 0.18, blocked: 0.35, error: 0.50
```

The gap between executing (0.03) and blocked (0.35) is the entire perceptual design. Healthy work is invisible. Problems glow.

---

## 5. Entry Path: Building the Mental Map

A first-time viewer sees 42 project auras on a dark field. How do they build a mental model?

The brainstorm's open question #2 — "deterministic grid or force-directed based on dependencies?" — is the wrong framing. Neither serves spatial learning. A grid is memorable but semantically empty (alphabetical order encodes nothing). Force-directed is semantically rich but unstable.

**The right answer is a hand-curated topology that encodes architectural meaning.** The 6 pillars map to spatial regions:

```
              +---------------------------------------------+
              |                  L3 APPS                     |
              |          Autarch        Interspect            |
              +---------------+-----------------------------+
              |   L2 OS       |        L2 OS                 |
              |   Clavain     |   Skaffen    Zaka    Ockham   |
              +---------------+-----------------------------+
              |              L1 KERNEL                       |
              |     Intercore         Intermute               |
              +---------------------------------------------+
              |              INTERVERSE (ring/periphery)      |
```

This maps directly to the architectural layer model: L1 at the bottom (foundation), L2 in the middle (OS), L3 at the top (user-facing). Interverse plugins orbit the periphery. The spatial layout *is* the architecture diagram. A new viewer learns the system topology by learning the display topology — they are the same thing.

Within each pillar region, projects are arranged by coupling (heavily-connected projects are spatially adjacent). This is computed once and persisted.

**Design principle:** *The map is the territory.* Spatial regions encode architectural layers. Learning the display = learning the system.

---

## Approach Evaluation Summary

| Criterion | A (Compound) | B (Force) | C (Hybrid) | D (Gravity+Canvas) |
|-----------|:---:|:---:|:---:|:---:|
| Spatial memory stability | Poor | Worst | Poor | Bad |
| Peripheral attention | Poor | Poor | Good potential | Good potential |
| Tab-switch safety | Destructive | Destructive | Destructive | Destructive |
| Going gray | Cannot | Partially | Best | Good |
| Entry path / mental map | Moderate | Poor | Moderate | Good |

**None of the four approaches, as described, solve the spatial memory problem.** All four treat layout as a per-render computation when it needs to be a persistent data property.

---

## Recommendation

**Approach D (Gravity + Ambient Canvas) is the best foundation, but it requires three modifications that the brainstorm does not describe:**

### 1. Persistent Macro Layout (the missing piece)

Compute project positions once using a layered/architectural topology (L1 bottom, L2 middle, L3 top, Interverse periphery). Save these coordinates. Never recompute them. The gravity-center for each project is a fixed point in world space. This transforms D from "organic but unstable" to "organic and anchored."

### 2. Semantic Zoom with Three LOD Tiers

- **LOD 0 (default / peripheral):** Ambient field only. 42 soft auras. No nodes, no labels, no edges. This is the calm-computing baseline. A wall display running this is informative at a glance and ignorable otherwise.
- **LOD 1 (project focus):** Zoom into a region. Agent nodes fade in as circles. Active beads appear as dots. Intra-project edges visible. Project label appears.
- **LOD 2 (detail):** Full bead labels, dependency edges, dispatch particles, priority sizing. This is the interactive investigation mode.

### 3. Color-Switch Instead of Position-Switch

Tab does not move nodes. Tab changes the color encoding:
- Default: status (green/red/yellow)
- Tab 1: theme (derived tag colors)
- Tab 2: agent type (claude/codex/gemini)
- Tab 3: priority (P0 hot, P2 cool)

A subtle legend in the HUD updates to show the current encoding. Positions are always project-anchored.

### Design Principles (to codify in the implementation)

1. **Deterministic macro, organic micro.** Project positions are fixed architectural coordinates. Intra-project layout breathes with gentle force simulation.
2. **Healthy means invisible.** Normal execution intensity: 0.03. The display earns attention through deviation, not presence.
3. **Color is cheap, position is expensive.** Change color encoding to switch analytical perspective. Never reorganize spatial layout.
4. **The map is the territory.** Spatial regions encode architectural layers. Learning the display = learning the system.
5. **Overview first, anomaly always.** Default view is ambient field. Blocked/error states punch through all LOD tiers — a blocked agent's red glow is visible at LOD 0 without zooming.
6. **Persistent coordinates are data, not rendering.** Project positions live in the data model (ideagui.json or a layout.json), not computed at render time.

### Answering the Open Questions

1. **Cross-project bead dependencies:** Particles/animations, not arcing edges. At 42 projects, cross-cluster edges create spaghetti. A subtle particle that arcs from source to target project aura (visible at LOD 0 as a brief flash between auras) is more calm.
2. **Initial project positions:** Hand-curated architectural topology, not alphabetical grid or force-directed. Computed once from the pillar/layer model.
3. **Idle agents:** Show at LOD 1+ as dim dots (intensity 0.01). At LOD 0, they contribute nothing to the ambient field. They exist but are invisible.
4. **500+ beads at scale:** Beads are invisible at LOD 0. At LOD 1, only active/blocked beads appear. At LOD 2, all beads in the focused project appear. Never render 500 beads simultaneously.
5. **Project aura encoding:** Brightness = anomaly rate (not utilization — utilization is normal, anomaly is notable). Size = stable (based on project's assigned region). Hue shifts slowly from cool-neutral (healthy) toward warm-red (degraded). Saturation increases with urgency.
