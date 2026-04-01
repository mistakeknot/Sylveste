# Encoding Efficiency Review: Meadowsyn Entity Model

Reviewer lens: Tufte (data-ink ratio, graphical integrity), Cleveland & McGill (encoding hierarchy), Bertin (visual variables at density).

Source: `docs/brainstorms/2026-03-24-meadowsyn-entity-model-brainstorm.md`
Prototype: `apps/Meadowsyn/experiments/hydra-graph/index.html`

---

## 1. Visual Variable Audit

The current prototype and brainstorm collectively propose this encoding table:

| Visual variable | What it encodes | Channel rank (C&M) | Notes |
|---|---|---|---|
| **Position x,y** | Nothing (force-layout artifact) | #1 (most accurate) | WASTED — see section 3 |
| **Hue** (node fill) | Agent status OR bead status | #6 | Two separate palettes (AGENT_COLORS, BEAD_COLORS) for two different status enums. Reasonable. |
| **Size** (node width) | Bead priority (P0=38, P1=28, P2=20) OR agent activity (idle=18, active=28) | #3 | Double-duty: size means priority on beads but activity on agents. Ambiguous without legend. |
| **Shape** | Entity type (ellipse=agent, round-rect=bead) | #7 | Good — categorical distinction. Brainstorm adds terminal type and agent type as further shape variants, which risks exhausting discriminability at 500+ nodes. |
| **Glow hue** | Agent status (same as node fill hue) | N/A | **REDUNDANT** — exactly mirrors node fill color. See section 2. |
| **Glow intensity** | Agent urgency (blocked=0.35, idle=0.06) | N/A | Carries independent information (salience weighting). Partially useful. |
| **Glow radius** | Entity type (agent=140px, bead=84px) | N/A | **REDUNDANT** — duplicates the shape channel. |
| **Edge style** | Relationship type (solid=works-on, dashed=depends-on) | N/A | Fine. |
| **Edge color** | Relationship type (white=works-on, blue=depends-on) | N/A | **REDUNDANT** with edge style. Pick one. |
| **Animation** (proposed) | Dispatch events | N/A | Not yet implemented. Motion is strong preattentive channel; use sparingly. |
| **Project aura** (proposed) | Aggregate health — possibly multi-encoded | N/A | See section 5. |

**Redundancy count: 3 wasted encodings.** Glow hue duplicates node fill. Glow radius duplicates shape. Edge color duplicates edge style. These channels could encode additional variables (agent type, terminal type, time-since-last-activity) instead of repeating what is already shown.

**Unencoded variables with no channel assigned:**
- Agent type (claude/codex/gemini) — mentioned in brainstorm, no encoding chosen
- Terminal type (9 types) — mentioned, no encoding chosen
- Bead age or staleness
- Cross-project membership (agents spanning projects)
- WIP count per agent

---

## 2. Ambient Glow as Chartjunk?

Apply the erasure test: remove the glow canvas entirely and ask what information is lost.

**What glow hue communicates:** The same status already shown by the node's fill color. A green dot with a green glow says "executing" twice. At the prototype's current scale (16 agents, 12 beads), the glow is purely decorative — the nodes are easily distinguishable by fill color alone.

**What glow intensity communicates:** A salience gradient — blocked nodes are visually louder than idle ones. This is the one independently decodable dimension. But it could be achieved more cheaply with node border width or node opacity, both of which are higher-ranked in Cleveland & McGill's hierarchy than luminance-area (which is what a radial gradient effectively is).

**The glow radius** encodes entity type (agent vs bead), but shape already does this. Pure redundancy.

**Performance cost:** The glow canvas runs `requestAnimationFrame` continuously, compositing 500+ radial gradients per frame. At the target density of 500+ nodes this is a significant GPU burden for information that is either redundant or achievable through cheaper channels.

**Verdict:** At 16 nodes, the glow is atmospheric and harmless. At 500+ nodes, it becomes expensive chartjunk. The overlapping gradients will create a muddy interfernce pattern that is less readable than the discrete node colors beneath them. The single useful dimension (salience/intensity) should migrate to node opacity or border weight.

**Exception:** The *project-level aura* (a single large gradient per project cluster, not per node) survives the erasure test if it encodes aggregate health — it is the only visual signal for project-level state. Keep that. Kill per-node glow.

---

## 3. Position Waste

Position is the highest-ranked visual variable in every perceptual study (Cleveland & McGill 1984, Mackinlay 1986). Force-directed layout assigns x,y based on graph topology — which edges happen to connect which nodes. The resulting positions encode nothing the viewer can decode: "this agent is to the left of that one" carries no meaning.

**What position could encode instead:**

| Axis strategy | X encodes | Y encodes | Trade-off |
|---|---|---|---|
| **Priority strip** | Project (categorical) | Bead priority (P0 top, P2 bottom) | Loses topology, gains scannable priority ranking |
| **Time axis** | Time (bead creation or last activity) | Project or priority | Good for staleness detection; factory is temporal |
| **Utilization map** | Agent utilization (busy right, idle left) | Error rate (high top, low bottom) | Instant quadrant reading: top-right = hot zone |
| **Deterministic grid** | Project column (alphabetical or by size) | Entity type row (agents top, beads bottom) | Boring but maximally stable; no layout jitter |

The brainstorm's "deterministic grid" idea (open question #2) is the right instinct. Tufte's principle: "use the position channel to answer the question the viewer actually has." For an ops room, the viewer asks "what needs attention?" — position should encode urgency or health, not arbitrary graph forces.

**Recommendation:** Use a deterministic project-column layout. Within each column, y-position encodes priority (P0 top) or status (blocked top, idle bottom). This makes position meaningful and eliminates the layout instability that force-directed graphs suffer from on data refresh.

---

## 4. 500+ Node Density

Bertin's threshold for point symbols on a single plane is roughly 200-300 before the display becomes unsortable. At 500+ beads plus 61 agents, a flat rendering will produce an undifferentiated field regardless of approach.

**What Tufte and Bertin recommend at this density:**

1. **Small multiples (Tufte).** One small panel per project. 42 projects in a 7x6 grid, each showing its agents and beads at a comfortable density of ~15 nodes. The viewer compares across panels using the same scale. This is the single most powerful technique for high-density categorical data.

2. **Aggregation (Bertin).** Do not render 500 individual beads when 400 of them are idle/open. Show aggregate counts with a single glyph per project: a stacked bar or a small pie (project health). Only expand to individual nodes on click/zoom.

3. **Level-of-detail (compromise).** At overview zoom, each project is a single composite glyph (size=bead count, color=aggregate health, small sparkline or bar for status distribution). Zoom into a project to see individual nodes. This is what geographic maps do — it works.

**The brainstorm's "show everything" decision (#5) directly contradicts density best practice.** Rendering 500+ glowing nodes will produce a galaxy aesthetic that looks impressive in screenshots but fails the core task: helping an operator identify which project needs intervention. The glow interfernce at that density means the ambient layer actively degrades readability.

**Recommendation:** Default view is small-multiples or aggregated project glyphs (one per project, ~42 glyphs, well within Bertin's threshold). Detail view on click/zoom expands a single project to show individual agents and beads. The brainstorm's tab-to-switch view modes is compatible with this — the "project view" just needs to start aggregated.

---

## 5. Project Aura Encoding

Open question #5 asks whether the project aura should encode one variable or multiple.

**One variable (aggregate health) is correct.** Reasons:

- A background aura is a low-precision channel. Bertin classifies area-color as suitable for only 4-7 discriminable steps. Trying to encode three variables (size=count, brightness=util, warmth=errors) in a single gradient asks the viewer to decompose a perceptual composite that humans cannot reliably factor.

- Tufte's principle of graphical integrity: "the number of information-carrying dimensions in the graphic should not exceed the number of dimensions in the data being represented." An aggregate health score is one dimension. Encode it as one dimension (a single color scale from green through amber to red, or a cool-to-warm ramp).

- If the operator needs to see utilization, error rate, and bead count separately, those should be separate visual marks (e.g., small bar charts within the project glyph), not multiplexed into a single gradient.

**Encoding rule:** Project aura = single-variable health score. Map to a sequential luminance scale (dark = healthy/quiet, bright-warm = needs attention). This leverages the ambient aesthetic while carrying exactly one decodable datum.

---

## Approach Evaluation Summary

| Criterion | A (Compound) | B (Force+Gravity) | C (Hybrid) | D (Gravity+Ambient) |
|---|---|---|---|---|
| Position semantics | Box layout is deterministic, but compound-cose still force-directed inside boxes | Force = wasted position | Compound outer + force inner | Fully wasted position |
| Density handling | Collapse/expand built-in | No aggregation support | Collapse/expand + ambient | No aggregation; relies on glow to "guide attention" (chartjunk at scale) |
| Project aura | Parent fill color — clean, one channel | Convex hull — expensive to compute, fragile | Dual-system sync overhead | Glow IS the container — fails erasure test when clusters overlap |
| Encoding efficiency | 5/5 — structure is explicit | 2/5 — structure is emergent and unreliable | 4/5 — structured + ambient aesthetic | 1/5 — ambient does double duty as structure AND data, neither well |
| Tab-to-regroup | Re-parent (clean API) | Recalculate gravity centers (unstable) | Re-parent | Full re-layout (slow, disorienting) |
| Implementation cost | Medium (cose-bilkent plugin) | High (custom gravity + hull rendering) | High (two renderers) | Medium but fragile |

---

## Recommendation

**Use Approach A (Cytoscape Compound Nodes) with the following encoding rules:**

1. **Kill per-node glow.** Replace with node opacity (idle=0.3, active=1.0) and node border-width (blocked=3px red, gated=2px amber, normal=0). This reclaims the salience function of glow intensity through higher-ranked perceptual channels and eliminates 500+ radial gradient composites per frame.

2. **Keep project-level aura as a single compound-node background fill.** Encode one variable: aggregate health score. Use a sequential luminance ramp (dark gray = healthy, warm amber = degraded, bright red = critical). Do not attempt to multiplex count/util/errors into a single gradient.

3. **Make position meaningful.** Lay out projects in a deterministic grid (e.g., by size or alphabetical). Within each project compound node, use a simple grid or force layout for internal nodes — but the project-level positions must be stable across refreshes. No global force-directed layout.

4. **Default to aggregated view.** At overview zoom, each project is a compact compound node showing: a health-colored background, an agent count badge, a status distribution micro-bar (stacked horizontal bar: green/amber/red proportions). Individual agent and bead nodes appear only when the user zooms into or clicks a project. This keeps the overview at ~42 visual elements, well within Bertin's discriminability threshold.

5. **Reclaim freed channels for unencoded variables:**
   - **Node shape** (currently: entity type) — extend to encode agent type: ellipse=claude, diamond=codex, triangle=gemini.
   - **Node border color** — encode terminal type (9 types, 9 hues). Since border color is lower-ranked than fill color, this puts secondary information in a secondary channel.
   - **Edge redundancy** — drop edge color; use dash pattern alone for relationship type. Use edge width to encode a useful variable (e.g., bead dependency criticality or WIP duration).

6. **Cross-project edges:** Use curved arcs between compound nodes, not particles. Particles are motion (strong preattentive channel) and should be reserved for the single most important transient event: active dispatches. Do not waste motion on static structural relationships.

7. **Idle agents (open question #3):** Show them, but at reduced opacity (0.2) and minimum size. Idle agents are 60% of the fleet — hiding them misrepresents capacity. Showing them at reduced salience communicates "available" without visual clutter. In aggregated view, they are just a count in the badge.

**Net effect:** The data-ink ratio improves from roughly 30% (current prototype with redundant glow, meaningless position, and no aggregation) to approximately 70% (every visual variable encodes a distinct factory metric, position is stable and meaningful, density is managed through aggregation).
