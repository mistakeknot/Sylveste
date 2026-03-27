# Explorable Explanation Review: Meadowsyn Entity Model

Evaluating approaches A-D from the entity model brainstorm through the lens of Bret Victor's explorable explanations, Nicky Case's Loopy, and ISA-101 progressive disclosure.

## 1. Causal Chain Traversal

**The test:** Click a blocked bead, trace backward through "what agent claimed this -> what dispatched it -> what dependency is blocked."

The hydra-graph experiment already has the skeleton for this. Its `node.neighborhood().add(node).merge(node.successors()).merge(node.predecessors())` highlight on tap is the right primitive -- it dims the irrelevant and lights up the causal chain. But it stops one hop short of being a true explorable explanation. Victor's principle is that **every value should be traceable to its cause.** A blocked bead's redness should be clickable, and that click should reveal *why* -- the dependency edge, the upstream bead, the agent that holds the lock.

**Approach ranking for this criterion:**

- **Approach A (Cytoscape compound)** and **C (hybrid)** win here. Cytoscape's `successors()` and `predecessors()` graph traversal is built-in. Compound node containment means the "which project owns this" question is answered spatially without any extra interaction. The chain `blocked bead -> depends-on edge -> upstream bead -> works-on edge -> agent -> project container` is navigable by successive clicks, each dimming everything outside the growing causal neighborhood.

- **Approach B and D (force/gravity)** make traversal harder because spatial proximity is emergent, not structural. A blocked bead's dependency might be in a distant cluster with no visual breadcrumb connecting them. You need explicit edge rendering to compensate, which defeats the organic aesthetic these approaches are designed for.

**Design principle:** Implement *progressive causal reveal*. First click: highlight the node + immediate edges. Hold click (or second click): expand to full predecessor/successor chains. This follows ISA-101's Level 1 (overview awareness) -> Level 2 (targeted investigation) pattern without requiring the viewer to build a mental model of the full graph upfront.

## 2. Time Dimension

**The test:** Scrub backward to see how the topology evolved. Does process-replay suggest an integration path?

The process-replay experiment is the most mature of the three prototypes for this. Its event-based architecture -- recording `{ time, beadId, fromLane, toLane }` events, then replaying them deterministically on scrub -- is exactly the right foundation. The scrub bar click handler that does `tokens.clear(); eventIdx = 0; while (eventIdx < events.length && events[eventIdx].time <= playheadTime) applyEvent(events[eventIdx++])` is a clean implementation of Victor's "time-travel debugging" pattern from Learnable Programming.

**Integration path:** The graph view (any approach) needs an event log analogous to process-replay's. Every state change -- agent status transition, bead claim, dependency resolution, dispatch -- becomes a timestamped event. The scrub bar controls a virtual clock. At each playhead position, the graph reconstructs its state by replaying events up to that point.

**Approach ranking:**

- **Approach A and C** handle this most naturally because re-parenting (the tab-switch mechanism) is already a discrete, reversible operation. Each re-parent is an event that can be recorded and replayed. The layout engine (cose-bilkent) can animate between states.

- **Approach B and D** are problematic for time-scrubbing because force-directed layouts are non-deterministic. Scrubbing back and then forward again produces a different spatial arrangement. This violates Victor's principle that **the same input should always produce the same visual output** -- the viewer loses their spatial memory. You would need to snapshot positions at each event and lerp between snapshots, which is expensive at 500+ nodes.

**Design principle:** Store topology snapshots at key events (not every frame). On scrub, interpolate node positions between the two nearest snapshots. Use the process-replay experiment's event sidebar as a companion to the graph view -- the event log grounds the abstract topology changes in concrete actions ("Agent Grey Area claimed Sylveste-abc1 at 14:32:07").

## 3. Perturbation

**The test:** Drag an agent from one project to another and see the simulation respond.

This is where Victor's Drawing Dynamic Visualizations principle is most relevant: the visualization should be a *model you can poke*, not just a picture. Nicky Case's Loopy makes this the core mechanic -- drag a connection, inject a signal, watch it propagate.

**Approach ranking:**

- **Approach D (gravity + ambient canvas)** is paradoxically the best for perturbation despite being worst for causal traversal. Because there are no structural containers, dragging a node *is* its re-assignment -- the node drifts toward its new gravity center, and the ambient field recolors smoothly. There's no "container membership" to update; the spatial clustering IS the assignment.

- **Approach B (force-directed)** shares this advantage but without the ambient canvas, the visual feedback of the re-assignment is less clear.

- **Approach A and C (compound nodes)** make perturbation awkward. Dragging a node out of a compound container requires explicitly re-parenting it, which is a graph mutation, not a physics interaction. It feels like editing a database, not poking a system.

**Design principle:** Perturbation should propagate. If you drag an agent to a new project, the simulation should show: (1) the agent's WIP edges snap, (2) the abandoned beads return to "unclaimed" state (glow shifts from green to blue), (3) the source project's aura dims (lost capacity), (4) the target project's aura brightens. This cascade -- visible within 1-2 seconds of the drag -- is what makes it an explorable explanation rather than a drag-and-drop editor.

**Critical caveat:** Perturbation in Meadowsyn is a *simulation*, not a command. Dragging an agent should show "what would happen if," not actually re-assign the agent. A small "SIMULATED" badge or dashed-outline mode makes this clear.

## 4. Loopy Signals Integration

**The test:** The loopy-signals experiment shows feedback loops with particle animation. How should the graph view expose the same causal structure?

The loopy-signals experiment models the *abstract process* (backlog -> dispatch -> execute -> gates -> ship/rework). The graph view models the *concrete topology* (specific agents, specific beads, specific projects). These are two levels of the same system.

**Integration approach:** The loopy CLD is the *macro lens*; the graph topology is the *micro lens*. They should be linked, not merged.

- **Overlay mode:** When viewing the graph, a semi-transparent CLD overlay positions its abstract nodes at the aggregate center-of-mass of the concrete nodes in that state. Particles flow along the CLD edges at rates derived from real throughput. The viewer sees both the forest and the trees.

- **Drill-through:** Click the "EXECUTE" node in the CLD overlay and the graph view filters to show only agents currently executing + their beads. This is ISA-101 Level 2 -> Level 3 transition.

- **Pulse injection from graph:** Click a concrete bead in the graph and watch a pulse propagate through the CLD overlay, showing which abstract stages it will traverse. This connects the loopy-signals experiment's pulse mechanic to actual work items.

**Approach ranking:** All four approaches can support this equally well because the CLD overlay is rendered on its own canvas layer (just as loopy-signals uses SVG). The choice of graph approach doesn't affect the overlay. However, **Approach C and D** (which already have an ambient canvas layer) make it architecturally simpler -- the CLD overlay shares the same rendering pipeline as the ambient glow.

**Design principle:** Never show abstract causal loops without grounding them in concrete instances. Every "R" (reinforcing) or "B" (balancing) loop label in the CLD should be annotatable with the specific agents and beads currently participating in that loop. Victor's core insight: **abstraction without connection to the concrete is not understanding.**

## 5. Tab-Switching as Exploration

**The test:** Does cycling views (project -> theme -> bead) reveal hidden structure, or is it disorienting?

Tab-switching is the brainstorm's proposed mechanism for re-grouping nodes by different dimensions. This is a high-risk interaction. Done poorly, it's the "shuffle the deck" anti-pattern -- everything moves, spatial memory is destroyed, the viewer has to rebuild their mental model from scratch. Done well, it's Bret Victor's "see the same thing from different angles" pattern.

**What makes it work vs. fail:**

- **Fail:** All nodes re-layout simultaneously. The viewer loses track of the node they were focused on. This is what `cy.layout({ randomize: true })` in the hydra-graph experiment would produce on every tab switch.

- **Work:** Animate the transition. The node the viewer is focused on stays spatially stable (anchored). Other nodes flow around it to form the new grouping. The viewer never loses their "I am here" anchor. This is the Loopy principle -- the viewer's locus of attention is sacred.

**Approach ranking:**

- **Approach A (compound nodes):** Tab-switch = re-parent + re-layout. Cytoscape can animate this if you use `animate: true` in the layout options. But compound node re-parenting is a structural mutation that triggers a full layout recalculation. With 500+ nodes, the animation can be janky.

- **Approach B and D (force/gravity):** Tab-switch = change gravity centers. This produces the smoothest animation because the physics engine naturally interpolates. Nodes drift to their new attractors over 1-2 seconds. The viewer can watch the reorganization happen. This is the most "explorable" transition.

- **Approach C (hybrid):** Gets both -- structural re-parenting for correctness + canvas animation for visual smoothness.

**Design principle:** Implement *dimensional pivoting* rather than view switching. When the viewer hits Tab, the current grouping dimension fades out (containers dissolve) while the new one fades in. During the 800ms crossfade, both groupings are partially visible -- the viewer sees the same nodes belonging to two organizational structures simultaneously. This moment of dual-visibility is where hidden structure is revealed: "oh, these beads from three different projects are all in the same theme."

The crossfade should highlight *surprises* -- nodes whose group membership changes most dramatically between views. A bead that's in a healthy project but a troubled theme should pulse during the transition. This is the pedagogical payoff of tab-switching.

## Recommendation

**Approach C (Hybrid: Compound Structure + Ambient Canvas)** is the right choice, with specific modifications:

### Why C wins

It is the only approach that scores well on all five criteria:

| Criterion | A | B | C | D |
|-----------|---|---|---|---|
| Causal traversal | Strong | Weak | Strong | Weak |
| Time scrub | Good | Poor (non-deterministic layout) | Good | Poor |
| Perturbation | Awkward | Natural | Possible with escape hatch | Best |
| Loopy integration | Neutral | Neutral | Native (shared canvas) | Native |
| Tab-switching | Janky animation | Smooth but imprecise | Both | Smooth but imprecise |

Pure structure (A) sacrifices the organic feel that makes the ops room ambient and watchable. Pure force (B, D) sacrifices the deterministic spatial memory that makes causal traversal and time-scrubbing reliable. The hybrid gets both: structural truth from Cytoscape, atmospheric rendering from the canvas.

### Specific interaction design principles

1. **Click-to-trace, not hover-to-trace.** Hover is ephemeral; click commits the viewer to an investigation. First click: immediate neighborhood. Second click on an edge endpoint: extend the chain. Double-click background: reset. This matches the hydra-graph experiment's existing tap handler but extends it to be incremental.

2. **Scrub bar as shared control.** One scrub bar controls both the graph topology and the process-replay swim-lane view (if shown in a split pane). Moving the scrub bar on either view synchronizes both. The graph and the swim-lane are two projections of the same event stream.

3. **Perturbation via a "what-if" mode.** Press and hold `Shift` to enter simulation mode (border tints to indicate hypothetical). Drag agents, sever edges, inject "block this bead" events. Release `Shift` to snap back to reality. The delta between simulated and real state is the insight.

4. **CLD overlay as toggle, not separate view.** Press `L` to toggle the loopy CLD overlay on the graph. The CLD nodes are positioned at aggregate centers. Particles flow at real throughput rates. Click a CLD node to filter the graph to that stage's concrete members.

5. **Tab-switch crossfade with surprise highlighting.** 800ms animated transition between grouping dimensions. Nodes that change group membership most dramatically pulse during the crossfade. The crossfade moment is the primary "hidden structure" revelation mechanic.

6. **Anchor the viewer's focus during transitions.** Whatever node was last clicked (or is nearest screen center) stays spatially fixed during any re-layout. All other nodes reposition relative to this anchor. This preserves spatial memory across tab-switches and time-scrubs.

### What to build from the existing experiments

- **From hydra-graph:** Keep the three-layer architecture (glow canvas / Cytoscape / HUD). Extend the tap handler to multi-hop causal traversal. Add compound nodes for project containers.
- **From loopy-signals:** Extract the particle animation system and the CLD topology. Render as an optional overlay layer on the graph canvas.
- **From process-replay:** Extract the event recording / scrub-bar / deterministic replay system. Use it as the shared time control for the graph view.

The three experiments are not alternatives -- they are layers of the same explorable explanation, each revealing the factory at a different level of abstraction.
