# Plan: F19 Unified Compose

**Bead:** Sylveste-jpum.12
**Date:** 2026-03-25
**PRD:** docs/prds/2026-03-25-f19-unified-compose.md
**Brainstorm:** docs/brainstorms/2026-03-25-f19-unified-compose-brainstorm.md

## Approach

Single-file composition. Start from F12 (semantic-zoom) as the base — it already has the LOD system, ambient glow, Cytoscape, and DataPipe integration. Layer in F11's expanded project list + Interverse ring, F13's perf optimizations, and F14's color mode system.

## Steps

### Phase 1: Scaffold (new file, base structure)
1. Create `apps/Meadowsyn/experiments/unified-compose/index.html`
2. Copy F12's HTML structure as starting skeleton
3. Replace title with "OPS ROOM" and update HUD layout to include all indicators

### Phase 2: Project Constellation (from F11)
4. Replace F12's 9-project list with F11's full 19 pillars + 53 Interverse plugins
5. Port F11's `computeInterversePositions()` elliptical ring function
6. Port F11's `getAllProjects()` merger function
7. Use F11's project label DOM rendering (with LOD-aware sizing from F12)

### Phase 3: Ambient Glow (from F13)
8. Use F13's optimized glow engine: pre-rendered stamps, 0.5x resolution, idle culling
9. Add F13's perf stats tracking (`perfStats` object with sync/draw/total/rendered/culled)
10. Add perf overlay HTML (hidden by default, toggled with P key)
11. Integrate LOD-aware aura intensity: LOD 0 base=0.04, LOD 1+=0.015

### Phase 4: Color Mode System (from F14)
12. Port F14's `COLOR_MODES` array (4 modes with agent/bead/glow color maps + legends)
13. Port mode indicator pips HTML + CSS
14. Port color crossfade logic (400ms transition, `prevColors`/`targetColors` maps)
15. Port auto-fading legend HTML + CSS
16. Wire Tab key handler with `e.preventDefault()`

### Phase 5: LOD System (from F12)
17. Port LOD threshold system and `computeLOD()` function
18. Port LOD indicator bar HTML + CSS (3 bars + label)
19. Wire zoom event to LOD transitions with opacity animation
20. Make glow intensity LOD-aware (auras prominent at LOD 0, node glows scale with LOD transition)

### Phase 6: Graph + Data Integration
21. Single Cytoscape instance with combined styles from F11 (node shapes, sizes) + F12 (LOD opacity) + F14 (color data binding)
22. Mock data generator: 30 agents (Culture ship names), 40 beads, 13 deps, all assigned to projects
23. Single `applySnapshot()` that creates/updates nodes+edges, triggers incremental layout
24. fCoSE layout with `fixedNodeConstraint` for all project anchors

### Phase 7: Animation Loop
25. Single `requestAnimationFrame` chain: compute LOD transitions → sync glow positions → draw glow → update perf stats
26. Color transitions update in same loop (lerp between prev/target colors)

### Phase 8: Polish + Gallery
27. localStorage: save color mode preference, restore on load
28. Add unified-compose to selector.html experiment list
29. Keyboard help: `?` shows/hides hint overlay listing all shortcuts

## File Changes

| File | Action |
|------|--------|
| `apps/Meadowsyn/experiments/unified-compose/index.html` | **Create** — the main deliverable |
| `apps/Meadowsyn/experiments/split-flap/public/selector.html` | **Edit** — add F19 to gallery |

## Risks & Mitigations

- **172 Cytoscape nodes on first layout:** Use `numIter: 300` for first render, `numIter: 80` for incremental. Fit only on first render.
- **Tab key browser conflict:** `e.preventDefault()` only when `e.target === document.body` (don't steal from inputs).
- **LOD + color mode interaction:** Color transitions should respect LOD opacity — don't show a bright color crossfade on hidden nodes.

## Estimated Effort

~800 lines of HTML/CSS/JS. Most code exists across the 4 experiments; work is primarily integration and deduplication.
