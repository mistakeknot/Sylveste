---
artifact_type: brainstorm
bead: Sylveste-jpum
stage: discover
---

# Brainstorm: Meadowsyn Entity Relationship Model

## What We're Building

A visualization layer that models the relationships between agents, projects, beads, themes, terminals, and sessions for the Meadowsyn ops room. The current prototype uses a flat agent→bead graph with per-node ambient glow. The real system has 42 projects, 61 agents, 500+ beads, 9 terminal types, 3 agent types, and planned thematic lanes.

## Design Decisions

1. **Primary grouping: Project-centric** — Projects are visual clusters/regions. Agents and beads live inside their project. Cross-project agents show as bridges between clusters. Tab-to-switch changes color encoding, not spatial position.

2. **Themes: Derive now, upgrade later** — Parse module tags from bead titles (e.g., `[interflux]`, `[clavain]`) and label prefixes. Design data model to swap cleanly to real lanes when they ship.

3. **Ambient: Per-node + project aura** — Individual node glows PLUS a large faint background aura per project. Project aura encodes one variable only: aggregate health (% blocked).

4. **Scale: Semantic zoom, not show-everything-flat** — LOD 0: 42 ambient auras. LOD 1: agent nodes on zoom. LOD 2: beads + dep edges on deeper zoom. Everything is *accessible*, not simultaneously *rendered*.

5. **Approach: D' (Gravity + Ambient Canvas + Fixed Stars)** — Selected via 5-agent review across Appleton (spatial cognition), Tufte (encoding), Victor (explorable), Matuschak (tools-for-thought), and graph engineering perspectives. See review docs in `.claude/flux-drive-output/fd-*.md`.

## Why This Approach

5 specialized review agents evaluated approaches A-D. D won 3-of-5, and the engineering agent confirmed compound nodes (A/C) are technically unviable at scale (single-parent constraint breaks multi-project agents, cose-bilkent takes 3-6s at 500 nodes, re-parenting for tab-switch requires remove+re-add). The fused design (D') incorporates the best insights from all 5 perspectives.

## Key Design Principles

### From Appleton (spatial cognition)
- **Deterministic macro, organic micro.** 42 project positions are fixed coordinates based on architectural layers (L1 bottom, L2 middle, L3 top, Interverse periphery). Agents cluster organically within.
- **Healthy = invisible.** Executing agents glow at near-zero intensity (~0.03). Only anomalies (blocked/gated) punch through. The ASM "going gray" principle.
- **Color is cheap, position is expensive.** Tab-switch changes hue encoding (status/theme/agent-type/priority), never moves nodes.

### From Tufte (information density)
- **Free redundant encodings.** Current glow hue duplicates node fill, glow radius duplicates shape. Reassign freed channels to: agent type (shape), terminal type (border), staleness (opacity).
- **Project aura = one variable.** Aggregate health only. Multiplexing count/util/errors exceeds human decomposition ability.
- **Position must carry data.** Deterministic project grid with y-axis encoding (priority or layer) makes x,y informative, not wasted on layout artifacts.

### From Bret Victor (explorable)
- **Causal chain traversal.** Click blocked bead → trace backward through assignment → dispatch → dependency. Use Cytoscape's `successors()`/`predecessors()` on the graph data, even without compound containers.
- **Loopy signals = overlay, not separate tab.** Toggle with `L` key. CLD and graph are macro/micro views of the same system.
- **Tab crossfade.** 800ms transition where both groupings are simultaneously visible — the dual-visibility moment reveals hidden structure.

### From Matuschak (tools-for-thought)
- **Activity-first, not org-chart-first.** Newcomers ask "what's alive?" before "how is it organized?" Default view leads with activity, projects emerge as spatial clusters.
- **Delta-awareness layer.** localStorage timestamp. On return, changed nodes get a fading halo. Single highest-impact feature for returning viewers.
- **Beads are first-class entities.** Permanent visual addresses, not transient decorations on agents. Sized by priority, not diminished.

### From Engineering (graph topology)
- **fCoSE, not cose.** Fix CDN load-order race (bundle or enforce script order). fCoSE with `fixedNodeConstraint` for project anchors converges in ~800ms at 500 nodes.
- **`randomize: false` after initial layout.** Use `numIter: 100` for incremental updates (~200-400ms). Seed new nodes near their anchor.
- **Position persistence.** Save to localStorage on `layoutstop`/`dragfree` (~22KB). Restore on reload. 50% staleness threshold triggers re-layout.
- **Ambient canvas optimization.** Cull idle glows (<0.08 intensity), render at 0.5x resolution, pre-render 6 gradient textures as stamps via `drawImage`. Target: 3-5ms/frame at 500 nodes.

## Entity Model

### Entities

| Entity | Source | Count | Visual |
|--------|--------|-------|--------|
| Project | ideagui.json + beads | 42 | Fixed-position anchor with aggregate aura |
| Agent (fleet) | factory-status tmux sessions | 61 | Circle node, status=glow intensity, type=shape |
| Bead (work item) | bd list | 500+ | Rounded rect, sized by priority (LOD 2 only) |
| Theme/Lane | Derived from title tags / labels | ~10-15 | Color encoding (tab-switch), not spatial |
| Terminal type | ideagui.json | 9 | Agent node border style |
| Agent type | claude/codex/gemini | 3 | Agent node shape variant |
| Dispatch (event) | factory-status | recent | Particle animation on edges (LOD 2) |
| WIP (live work) | factory-status | ~4-8 | Agent→bead edge, brighter than idle |

### Relationships

- Agent → Project (primary membership, spatial clustering)
- Agent → Bead (WIP assignment, active work edge)
- Bead → Project (ownership, spatial containment)
- Bead → Bead (dependency, arcing cross-cluster edges at LOD 2)
- Bead → Theme (derived tag, color encoding on tab-switch)
- Agent → Terminal type (border decoration)
- Agent → Agent type (shape variant)

### LOD Tiers

| Tier | Zoom | Elements | Purpose |
|------|------|----------|---------|
| LOD 0 | Default | 42 project auras + labels | Calm dashboard, peripheral awareness |
| LOD 1 | Medium | + agent nodes within clusters | "What's alive, what's stuck?" |
| LOD 2 | Deep | + bead nodes + dep edges + particles | Full detail, causal traversal |

### View Modes (Tab = Color Switch)

Tab cycles the hue encoding without moving any node:

1. **Status** (default): idle=dim gray, executing=faint green, blocked=bright red, gated=amber
2. **Theme**: hue maps to derived theme/lane tag
3. **Agent type**: claude=blue, codex=green, gemini=amber
4. **Priority**: P0=red, P1=amber, P2=blue, P3=gray

## Experiment Roadmap

These are the next experiments to build, extending the existing F1-F10 suite:

### F11: Fixed Stars Layout
Location: `apps/Meadowsyn/experiments/fixed-stars/`
- Deterministic project positions based on architectural layer model
- fCoSE with `fixedNodeConstraint` for invisible anchor nodes
- Position persistence via localStorage
- Incremental updates (`randomize: false`, `numIter: 100`)

### F12: Semantic Zoom (3 LOD Tiers)
Location: `apps/Meadowsyn/experiments/semantic-zoom/`
- LOD 0: 42 project auras only (zoom out = calm)
- LOD 1: agent nodes appear on zoom-in
- LOD 2: bead nodes + dep edges on deeper zoom
- Cytoscape zoom events drive LOD transitions
- Smooth show/hide with opacity fade per tier

### F13: Ambient Canvas v2 (Optimized)
Location: `apps/Meadowsyn/experiments/ambient-v2/`
- Pre-rendered gradient texture stamps (6 status variants)
- 0.5x resolution rendering with upscale
- Idle glow culling (<0.08 intensity threshold)
- Healthy=invisible (executing at 0.03 intensity)
- Project-level aggregate aura (single variable: % blocked)
- Target: 3-5ms/frame at 500 nodes

### F14: Color-Switch Tab Cycling
Location: `apps/Meadowsyn/experiments/color-switch/`
- Tab key cycles hue encoding: status → theme → agent-type → priority
- No position changes — spatial memory preserved
- 400ms crossfade animation between color schemes
- Status bar indicator showing current encoding mode

### F15: Delta-Awareness Layer
Location: `apps/Meadowsyn/experiments/delta-layer/`
- localStorage timestamp of last visit
- Fading halos on nodes that changed since last visit
- "New since last visit" count in HUD
- Halo intensity decays over time (bright=just changed, dim=changed hours ago)
- Works across all LOD tiers

### F16: Causal Chain Traversal
Location: `apps/Meadowsyn/experiments/causal-chain/`
- Click any node → highlight full causal chain (predecessors + successors)
- Blocked bead → trace back through: assignment → dispatch → blocking dep
- Breadcrumb trail with animated particle flow showing direction
- Info panel showing the chain as a list with timestamps

### F17: Loopy Signals Overlay
Location: `apps/Meadowsyn/experiments/loopy-overlay/`
- `L` key toggles CLD overlay on top of graph view
- Loopy signals nodes map to graph regions (backlog=left, shipped=right)
- Particle rate on CLD edges driven by actual graph edge throughput
- Dual view: macro (CLD) + micro (graph) of same system

### F18: Real Data Integration
Location: `apps/Meadowsyn/experiments/real-data/`
- Replace mock generator with live `clavain-cli factory-status --json`
- IdeaGUI roster enrichment via ideagui-pipe
- Bead data from `bd list --format=json`
- Theme derivation from bead title module tags
- Unified DataPipe that merges all three sources into one snapshot

## Open Questions

1. Should the architectural layer grid be horizontal (L1 left → L3 right) or vertical (L1 bottom → L3 top)?
2. What shape variants best distinguish claude/codex/gemini — circle/diamond/hexagon?
3. Should the delta-awareness layer show deltas per LOD tier or accumulate across all tiers?
4. How should the loopy overlay interact with LOD tiers — always visible or LOD 0 only?
