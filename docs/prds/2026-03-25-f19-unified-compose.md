# PRD: F19 Unified Compose

**Bead:** Demarch-jpum.12
**Date:** 2026-03-25
**Status:** Draft

## Overview

Compose four Meadowsyn experiments (F11 fixed-stars, F12 semantic-zoom, F13 ambient-v2, F14 color-switch) into a single unified Ops Room visualization. This is the canonical Meadowsyn view — the "biggest" display that shows the full Demarch factory.

## User Stories

1. **As an operator**, I want to open one page and see the entire factory at a calm, zoomed-out view showing project auras by architectural layer.
2. **As an operator**, I want to zoom in progressively to see agents (LOD 1) and then beads with dependencies (LOD 2) without switching views.
3. **As an operator**, I want to press Tab to cycle color encoding between status, theme, agent type, and priority to answer different questions about the same topology.
4. **As an operator**, I want the glow canvas to indicate system health at a glance — blocked projects glow red, healthy ones are nearly invisible.

## Requirements

### P0 (Must Have)
- Single `index.html` at `apps/Meadowsyn/experiments/unified-compose/`
- Fixed-stars layout with all 19 pillar projects + 53 Interverse plugins in peripheral ring
- 3-tier semantic zoom (LOD 0: auras, LOD 1: agents, LOD 2: beads+deps)
- Optimized ambient glow canvas (pre-rendered stamps, 0.5x res, idle culling)
- Tab-cycle color encoding with 4 modes and auto-fading legend
- Click-to-trace, dblclick-reset interaction
- Mock data generator (~30 agents, ~40 beads)

### P1 (Should Have)
- Performance overlay toggle (P key)
- LOD indicator bar (top center)
- Color mode indicator pips (top center, below LOD)
- localStorage: save zoom level, pan position, color mode preference
- Added to selector.html gallery

### P2 (Nice to Have)
- LOD-aware ambient intensity (auras more prominent at LOD 0)
- Keyboard shortcut help (? key)

## Non-Requirements
- Real data integration (F18 handles that)
- Delta awareness (F15)
- Causal chain traversal (F16)
- Loopy overlay (F17)
- Next.js integration or production build

## Success Metrics
- Glow frame budget: <5ms at 100 nodes
- Smooth LOD transitions: no visible pop-in
- Works in Chrome, Firefox, Safari (modern)

## Dependencies
- `data-static/data-pipe.js` (DataPipe module)
- Cytoscape.js 3.30.4 + cytoscape-fcose 2.2.0 (CDN)
- JetBrains Mono font (Google Fonts CDN)
