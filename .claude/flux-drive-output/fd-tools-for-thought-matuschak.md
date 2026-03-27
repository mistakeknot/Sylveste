# Tools for Thought Review: Meadowsyn Entity Model

**Reviewer lens:** Matuschak (evergreen notes, tools for thought, knowledge compounding), Nielsen (explorable explanations), Zettelkasten (networked knowledge).

**Source:** `docs/brainstorms/2026-03-24-meadowsyn-entity-model-brainstorm.md`

---

## 1. Conceptual Hierarchy Match

The brainstorm proposes **Project > Bead > Agent** as the default visual hierarchy. This is the _organizational_ truth but not the _perceptual_ truth.

Matuschak's core insight about tools for thought: the tool should match the user's evolving mental model, not the system's data model. A newcomer watching an AI factory for the first time asks three questions in order:

1. **"What's alive?"** — Which agents are doing something right now? (Agent-first)
2. **"What are they doing?"** — What work items are in flight? (Bead-second)
3. **"Where does this fit?"** — Which project does this belong to? (Project-third)

The brainstorm's default of Project > Bead > Agent inverts this. It answers the archivist's question ("how is work organized?") before the operator's question ("what's happening?"). The current hydra-graph prototype actually gets this more right — it shows agents as primary nodes with beads as attached work items, no project containers. The ambient glow draws the eye to activity, not to organizational structure.

**Recommendation:** Default to an activity-first presentation where agents with active status are perceptually dominant (size, glow, position). Projects should emerge as spatial clusters, not as containers the viewer must parse before seeing agents. The hierarchy the eye follows should be: **movement/glow (what changed) > agent (who's doing it) > bead (what's being done) > project (where it lives)**.

This matches Matuschak's principle that understanding compounds from concrete encounters upward to abstractions, not from taxonomy downward to instances.

## 2. Returning Viewer Experience (Delta-Awareness)

This is the sharpest differentiator between approaches and the brainstorm underweights it.

After 48 hours away, the viewer's primary need is: **"What's different since I last looked?"** None of the four approaches address this explicitly. Tab-switching views, container styling, ambient glow — all encode _current state_, not _change from last known state_.

Nielsen's explorable explanations work because they let the reader build a mental checkpoint and then see what happens when parameters change. The Meadowsyn equivalent is temporal anchoring: the viewer forms a mental image of the factory state, leaves, returns, and needs to see the delta.

**What each approach offers for delta-awareness:**

- **A (Cytoscape Compound):** Worst. Stable boxy structure makes everything look the same. A new bead inside a project container looks identical to one that's been there for a week.
- **B (Force-directed Gravity):** Poor. The layout is inherently unstable — positions shift between sessions, so the viewer can't even tell if a node moved meaningfully or if the physics just settled differently.
- **C (Hybrid Compound + Canvas):** Moderate. The ambient canvas could encode recency (new beads glow brighter for their first N hours), but the compound structure still buries change inside containers.
- **D (Gravity + Ambient Canvas):** Best potential, worst baseline. The ambient field _could_ encode temporal gradients (recently-changed regions pulse or shift hue), but without explicit delta signaling this is just as amnesiac as the others.

**Recommendation:** Regardless of approach chosen, add an explicit **recency layer**: nodes created or changed since the viewer's last visit get a temporal halo (a brief bright ring that fades over ~30 seconds of viewing). This converts "what's different?" from a search task into a perceptual task. Store a `lastViewedTimestamp` in localStorage. This is the single highest-impact feature for knowledge compounding — it turns every return visit into an incremental learning event rather than a cold restart.

## 3. Tab-Switching as Learning: Integration vs. Fragmentation

The brainstorm proposes cycling through 4 views (project / theme / agent / bead) via Tab. The question is whether this builds a richer mental model or creates four competing models that never integrate.

Matuschak's work on spaced repetition and incremental reading shows that **switching representations of the same underlying data is one of the most powerful learning techniques** — but only if the viewer can track identity across switches. The classic failure mode is PowerPoint slides where each slide is a different chart of the same data but nothing links them.

**The critical question is node identity persistence across view switches.** If I'm looking at agent "Grey Area" in agent-view, and I press Tab to project-view, does "Grey Area" animate smoothly to its new position inside a project cluster? Or does the whole screen re-render and I have to find it again?

If identity is preserved through animated transitions, tab-switching becomes a powerful mental model builder — the viewer literally sees the same entities reorganize under different conceptual lenses. This is what Bret Victor calls "seeing the same thing multiple ways."

If identity is not preserved (full re-layout, new positions), tab-switching creates the fragmentation problem: four disconnected snapshots with no felt connection between them.

**Recommendation:** Tab-switching is excellent _if and only if_ transitions are animated with smooth node movement (300-500ms). The viewer must see agents physically travel from their agent-view position to their project-view position. The animation _is_ the learning. Without it, remove tab-switching entirely and use a single view with progressive disclosure instead.

Approaches B and D handle this best because force-directed layouts can smoothly re-target gravity centers. Approaches A and C require re-parenting compound nodes, which Cytoscape handles less smoothly — re-parenting triggers a full layout recalculation with a visual jump.

## 4. Bead Identity: First-Class Entity or Transient Decoration?

The Zettelkasten lens is directly relevant here. In a Zettelkasten, every note is a first-class citizen with a permanent address. You can always find it, link to it, and it accumulates connections over time. The power comes from this permanence — notes compound because they persist.

Are beads like Zettelkasten notes (permanent, accumulable, always findable) or like Slack messages (transient, contextual, disposable)?

The answer is clearly the former: beads have IDs (`Sylveste-jpum`), dependency chains, priorities, and long lifetimes. They are the atomic unit of work. But the brainstorm treats them as secondary to agents — beads are "rounded rects sized by priority" attached to agent nodes. In the bead-view (Tab 4), they become primary, but that's one of four views.

The current hydra-graph prototype makes this worse: beads are small rounded rectangles with dimmer glow (`targetIntensity * 0.5`) and smaller radius (`GLOW_RADIUS * 0.6`). They are visually subordinate to agents in every way.

**The problem:** If beads don't have persistent visual identity (stable position, recognizable appearance, always present), the viewer can't build a cumulative understanding of work state. Every visit is a fresh scan for "where is Sylveste-jpum now?" instead of "ah, Sylveste-jpum moved from Grey Area to Sleeper Service — that handoff happened."

**Recommendation:** Beads should have **spatially stable positions** in at least one view mode (bead-view). Their position in bead-view should be determined by dependency ordering and priority, not by physics — so that returning viewers find them in the same place. In other views, beads can be decorations on agents, but the viewer should be able to mentally map between "bead as decoration on an agent" and "bead as persistent entity in the dependency graph."

This is exactly Matuschak's distinction between transient notes and evergreen notes: beads should be evergreen in the visualization, always accessible at their permanent address, accumulating visual history (which agents touched them, how long they've been in each state).

## 5. Progressive Disclosure: Glance to Causality

The brainstorm's "show everything" decision (all 42 projects, all agents, all 500+ beads) works at the glanceable level because ambient glow naturally creates visual hierarchy. But progressive disclosure from "factory pulse" to "deep bead-level causality" is underspecified.

Nielsen's explorable explanations achieve progressive disclosure through direct manipulation: hover to see more, click to see even more, drag to restructure. The key principle is that **each level of detail is revealed by interacting with the previous level**, creating a smooth ramp rather than a mode switch.

The current hydra-graph prototype has one progressive disclosure step: click to highlight neighborhood. This is a good start but there's a gap between "glanceable factory pulse" and "why is this bead blocked?"

**Recommended disclosure ramp:**

1. **Peripheral vision (0 interaction):** Ambient glow shows factory health. Red zones draw attention. This works in all four approaches.
2. **Hover (minimal interaction):** Hovering an agent or bead shows a tooltip with ID, status, duration-in-state. No mode change. This is missing from the current prototype.
3. **Click (light interaction):** Neighborhood highlight (already implemented). But extend it: clicking a bead should also show its dependency chain ancestors and descendants, not just direct neighbors.
4. **Sustained focus (temporal interaction):** If the viewer hovers or clicks on a bead for more than 2 seconds, progressively reveal more detail: show the dependency chain, show which agents have previously worked on it, show time-in-state. This is Nielsen's "the more you look, the more you see" principle.
5. **Deep dive (explicit action):** Double-click or right-click opens a detail panel (L3 in the three-layer architecture). This is the only mode switch.

The critical insight: steps 1-4 should work without any mode switch. The viewer stays in the same spatial context while information density increases around their focus point.

## 6. Orientation Anchor: What's the Stable Landmark?

When a viewer returns after 48 hours, they need a landmark to re-orient. "Where am I? What am I looking at? Where was that thing I was tracking?"

**Approach A (Compound):** Projects are stable landmarks (always in the same grid position, always containing the same agents). But 42 project boxes is too many landmarks — landmark overload is as bad as no landmarks.

**Approach B (Force-directed):** No stable landmarks. Physics-based layouts shift between sessions. This is the approach's fatal flaw for returning viewers.

**Approach C (Hybrid):** Same as A, plus the ambient canvas could provide a secondary orientation cue (the "red zone" in the upper-right is always the Clavain cluster).

**Approach D (Gravity + Ambient):** Gravity centers provide semi-stable positions, but clusters drift. The ambient field creates recognizable "neighborhoods" but not precise landmarks.

**Recommendation:** The orientation anchor should be **deterministic project placement**. The 42 projects should occupy fixed positions on a grid or hexagonal lattice, ordered by something stable (alphabetical, creation date, or pillar membership). This means the viewer always knows "Clavain is in the upper-left, Interflux is in the middle-right." The agents and beads within each project zone can use physics for local arrangement, but the project centers should be nailed down.

This is the Zettelkasten principle of stable addresses: every note has a permanent location. In spatial interfaces, location _is_ identity for returning viewers. Shuffling locations destroys the spatial memory that makes return visits efficient.

This design (fixed project positions + local physics) is compatible with Approaches B and D. It's incompatible with pure force-directed layout where project centers emerge from physics.

---

## Approach Evaluation Summary

| Criterion | A (Compound) | B (Force) | C (Hybrid) | D (Gravity+Canvas) |
|---|---|---|---|---|
| Conceptual hierarchy match | Poor (org-first) | Good (emergent) | Moderate | Good (emergent) |
| Delta-awareness | Poor | Poor | Moderate | Best potential |
| Tab-switching learning | Poor (re-parent jumps) | Good (smooth retarget) | Moderate | Good (smooth retarget) |
| Bead identity persistence | Moderate (container stability) | Poor (unstable positions) | Moderate | Poor without fixes |
| Progressive disclosure | Moderate | Good (organic zoom) | Good | Best (ambient + detail) |
| Orientation anchor | Good (box stability) | Poor (drift) | Moderate | Moderate with fixes |

---

## Recommendation

**Choose Approach D (Gravity + Ambient Canvas) with three structural amendments** that address its weaknesses while preserving its strengths:

### 1. Deterministic Project Anchors ("Fixed Stars")

Assign each of the 42 projects a fixed position on a hexagonal grid, ordered by pillar membership (L1 center, L2 ring, L3 outer). These positions never change between sessions. Agents and beads gravitate toward their project's fixed center but arrange themselves locally via physics. The ambient canvas draws project aura around these fixed centers.

This gives D the orientation stability of Approach A without the boxy containment artifacts. The viewer builds spatial memory: "Clavain is always upper-left" becomes an unconscious anchor within 2-3 visits.

### 2. Temporal Recency Layer ("What Changed")

Add a `lastViewedTimestamp` to localStorage. On return visit, any node whose state changed since last view gets a bright ring halo that fades over 30 seconds. This converts every return visit into a delta-learning event. The viewer's eye is drawn to change, not to searching for change.

Additionally, new beads created since last visit should enter with a brief "materialization" animation (expand from zero) rather than appearing instantly. This gives the viewer a temporal anchor: "that bead is new."

### 3. Animated View Transitions ("Same Entity, Different Lens")

When Tab switches between project/agent/theme/bead views, animate every node from its current position to its new position over 400ms. The viewer sees agents physically migrate between groupings. The animation _is_ the conceptual linking between views — it says "this is the same entity, reorganized under a different lens."

Without this animation, remove tab-switching entirely. Four static views with no visual continuity between them creates four competing mental models. One view with good progressive disclosure beats four views with no integration.

### Design Principles for Knowledge Compounding

1. **Stable addresses:** Every entity (project, agent, bead) should have a predictable spatial location that persists across sessions. Spatial memory is the cheapest form of recall.
2. **Change over state:** Encode temporal deltas (what changed), not just current state (what is). The returning viewer already knows the baseline; they need the diff.
3. **Identity through motion:** When the same entity appears in different contexts (different view modes, different zoom levels), animate the transition. The viewer must never wonder "is this the same thing I was looking at?"
4. **Disclose, don't switch:** Progressive disclosure within a single spatial context (hover, click, dwell) builds understanding incrementally. Mode switches (tabs, panels, pages) fragment it. Minimize mode switches.
5. **Beads are evergreen:** Beads accumulate history, connections, and state changes over their lifetime. The visualization should reflect this accumulation — a bead that has been worked on by 5 agents should look different from one that was just created. Visual patina encodes institutional memory.
6. **Ambient for peripheral, structure for focal:** Use the ambient canvas for peripheral awareness (factory health, project zones, recent activity). Use structured elements (nodes, edges, labels) for focal attention (specific agent status, bead dependencies). The two layers serve different cognitive modes and should not compete.
