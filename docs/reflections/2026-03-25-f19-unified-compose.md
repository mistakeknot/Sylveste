---
bead: Sylveste-jpum.12
date: 2026-03-25
type: reflection
---

# F19 Unified Compose — Reflection

## What Worked

The four experiments (F11-F14) were well-factored as standalone proofs of concept. Each owned one concern cleanly:
- F11: spatial layout (project positions, Interverse ring)
- F12: visibility control (LOD system)
- F13: rendering optimization (glow stamps, culling, perf tracking)
- F14: color encoding (mode switching, crossfade, legend)

This made composition straightforward — the interfaces between them were mostly about shared state (the Cytoscape instance, glow canvas, and animation loop).

## Key Integration Decision

The mock data adapter pattern (creating lightweight `{ data: fn }` objects in `applySnapshot` for `getNodeColor()`) avoided a chicken-and-egg problem. The color system needs to know the node's color before the node exists in Cytoscape. Rather than adding the node with a default color and then updating, we compute the color upfront and pass it in the creation data.

## What Would Be Different Next Time

The four experiments share ~60% of their code (project lists, glow textures, Cytoscape init). If more composition experiments follow (F15-F18 additions), extracting shared modules would pay off. For now, single-file is correct for the experiment convention, but the duplication is real.

## Metrics

- Final file: 906 lines (vs ~2,636 total across F11-F14 = 65% reduction)
- All P0 requirements met: fixed-stars layout, LOD zoom, ambient glow, color-switch, interactions
- All P1 requirements met: perf overlay, LOD indicator, mode indicator, localStorage, selector entry

## Next Steps

- F18 (real-data) integration: swap mock `generateSnapshot` for DataPipe URL polling
- Visual testing: open in browser, verify LOD transitions and color crossfade
- Performance profiling: verify <5ms glow budget with actual browser rendering
