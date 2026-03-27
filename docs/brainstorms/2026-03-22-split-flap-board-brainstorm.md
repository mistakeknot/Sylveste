---
artifact_type: brainstorm
bead: Sylveste-r24y
stage: discover
---

# F2: Split-Flap Departure Board

## What We're Building

A CSS-only split-flap departure board rendering live AI factory status in the FIDS (Flight Information Display System) aesthetic. One row per agent showing status, name, current bead, task title, and duration. This is the simplest visual experiment in the Meadowsyn suite and the first visible consumer of the F1 IdeaGUI DataPipe.

Parent brainstorm: `docs/brainstorms/2026-03-21-meadowsyn-brainstorm.md`
Parent plan: `docs/plans/2026-03-21-meadowsyn-experiments.md` (F2 section, lines 77-93)

## Why This Approach

Split-flap is the lowest-risk first visual because:
1. CSS-only — no WebGL, no Canvas, no heavy library dependencies
2. Exercises both data layers (fleet ops from factory-status, agent roster from IdeaGUI) plus liveness
3. The FIDS aesthetic is proven for glanceability at distance (airport departure boards, EEMUA 191)
4. "Going gray" principle from ASM research — color only on anomaly (FAIL, GATE), everything else white/gray

## Key Decisions

1. **CSS-only animation** — `::before`/`::after` pseudo-elements for top/bottom flap halves, `@keyframes flip` with staggered delay per character. No JavaScript animation libraries.

2. **Data consumption** — F1 (`ideagui-pipe`) is server-side Node.js. F8 (browser DataPipe) isn't built yet. F2 will use F1's CLI to generate static JSON, then fetch/poll it from the browser. This keeps F2 standalone while exercising the real data shape.

3. **Layout** — `[STATUS] [AGENT NAME........] [BEAD ID....] [TASK TITLE..............] [DURATION]` per row. Header: `MEADOWSYN FACTORY STATUS` + timestamp + agent count + queue depth.

4. **Color discipline** — Only FAIL (red) and GATE (amber) get color. IDLE (gray), EXEC (white), DISP (dim white). This follows the Cybersyn exception-driven attention pattern.

## Open Questions

1. How many characters per column? Need to balance readability vs. fitting 20+ agents on screen without scrolling.
2. Should the flip animation fire on every refresh (5s) or only when a value actually changes? (Change-only is more realistic and less distracting.)
