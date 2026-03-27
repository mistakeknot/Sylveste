# F19: Unified Compose — Brainstorm

**Bead:** Sylveste-jpum.12
**Date:** 2026-03-25
**Parent:** Sylveste-jpum (Meadowsyn)

## Problem

Four standalone experiments (F11 fixed-stars, F12 semantic-zoom, F13 ambient-v2, F14 color-switch) each work independently but share ~60% duplicated code: project constellation definitions, glow canvas setup, Cytoscape initialization, mock data generators, and DataPipe wiring. The "biggest Ops Room" needs all four composed into a single unified visualization — the canonical Meadowsyn view.

## What Each Experiment Contributes

| Experiment | Concern | Key Abstraction |
|-----------|---------|-----------------|
| F11 Fixed Stars | **Spatial layout** — deterministic project positions by architectural layer, Interverse ring, fCoSE with fixedNodeConstraint | `ProjectConstellation` + `projectPosition()` |
| F12 Semantic Zoom | **Visibility** — LOD 0/1/2 driven by zoom level, opacity transitions for agent/bead tiers | `LODController` with zoom thresholds |
| F13 Ambient v2 | **Glow rendering** — pre-rendered gradient stamps, 0.5x resolution, idle culling, project aggregate auras, perf overlay | `AmbientGlow` engine |
| F14 Color-Switch | **Hue encoding** — Tab cycles status/theme/agent-type/priority, 400ms crossfade, auto-legend | `ColorMode` system |

## Composition Architecture

### Layer Stack (same as individual experiments)
- **L0:** Canvas `#glow` — ambient glow (F13)
- **L1:** Cytoscape `#cy` — graph with F11 layout, F12 LOD visibility, F14 color encoding
- **L2:** DOM HUD — metrics, state label, LOD indicator, mode indicator, legend, perf overlay

### Integration Points

1. **Data flow:** Single `DataPipe` instance feeds one `applySnapshot()` function
2. **Project definitions:** One canonical `PILLAR_PROJECTS` + `INTERVERSE_PLUGINS` list (from F11, most complete — 19 pillars + 53 plugins)
3. **Cytoscape instance:** One `cy` shared by all systems. F12 controls opacity, F14 controls color, F11 controls position
4. **Animation loop:** One `requestAnimationFrame` chain: LOD transitions (F12) → glow sync+draw (F13) → color transitions (F14)
5. **Keyboard:** Tab = color mode cycle (F14), scroll = zoom/LOD (F12), click = trace, dblclick = reset

### What's New in F19 (beyond merge)

1. **Unified HUD** — top bar shows: title, projects/agents/beads counts, LOD indicator, color mode indicator. Bottom bar shows: state label, hint text, perf stats (toggle with `P`)
2. **Legend integration** — color-switch legend appears on mode change, auto-fades after 3s
3. **LOD-aware ambient** — F13's glow intensity scales with F12's LOD transitions (at LOD 0, auras are more prominent; at LOD 2, per-node glows dominate)
4. **Position persistence** — localStorage saves pan/zoom state and color mode preference

## Data Sources

For now: mock generator (same as individual experiments).
F18 (real-data) integration is a separate concern — F19 should accept any DataPipe configuration.

## Scope Boundary

**In scope:** Composing F11+F12+F13+F14 into one `index.html` in `apps/Meadowsyn/experiments/unified-compose/`
**Out of scope:** F15 (delta layer), F16 (causal chain), F17 (loopy overlay), F18 (real data), Next.js shell integration, production deployment

## Key Decisions Needed

1. **Project list:** Use F11's expanded list (19 pillars + 53 Interverse) or F14's mid-size list (15 pillars, no Interverse ring)?
   - Recommendation: F11's full list — the Ops Room should show everything
2. **Node count for mock:** F13's 500-node stress test or F12's ~70 nodes?
   - Recommendation: ~100 (30 agents + 40 beads + 30 deps) — enough to exercise LOD without overwhelming
3. **Single file or modular?** One big `index.html` or extract shared modules?
   - Recommendation: Single file — experiments are self-contained by convention. Extract later when shell integrates.

## Risk

- **Performance at full scale:** 19 anchors + 53 plugin anchors + 100 entity nodes = ~172 Cytoscape nodes. fCoSE layout may be slow on first render. Mitigation: use F13's culling and F12's LOD to limit visible nodes.
- **Keyboard conflicts:** Tab (color mode) vs Tab (browser focus). Mitigation: `e.preventDefault()` only when graph has focus.

## Success Criteria

1. Opens to calm LOD 0 view with all project auras visible
2. Zoom in smoothly transitions through LOD 1 (agents) and LOD 2 (beads + deps)
3. Tab cycles color encoding with visible crossfade and legend
4. Glow canvas runs at <5ms/frame with perf overlay showing budget
5. Click-to-trace and dblclick-reset work across all LOD tiers
6. Added to selector.html experiment gallery
