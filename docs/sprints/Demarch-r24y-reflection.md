---
artifact_type: reflection
bead: Demarch-r24y
stage: reflect
---

# Reflection: F2 Split-Flap Departure Board

## What shipped

Standalone `index.html` at `apps/Meadowsyn/experiments/split-flap/` — a FIDS airport departure board rendering AI factory agent status with CSS 3D split-flap animations. Consumes F1 IdeaGUI DataPipe snapshots via JSON polling. No build step, no dependencies beyond Google Fonts.

## What worked

1. **Plan review caught real bugs before code existed.** fd-performance identified the `perspective` per-element issue and DOM read/write batching — both would have been hard to debug in-browser. fd-user-product identified the `data-char-old`/`data-char` dual-attribute requirement, which is the kind of thing that only manifests when you try to animate.

2. **Quality gates caught a timing bug.** The FLIP_DURATION constant was disconnected from the actual CSS animation timing. fd-quality found it, and fd-correctness independently found the detached-node timeout issue. Both were one-line fixes but would have caused visible glitches.

3. **"Going gray" color discipline is powerful.** Only 2 of 5 statuses get color. This is the Cybersyn algedonic principle and it dramatically improves glanceability. Worth carrying forward to all Meadowsyn visuals.

## What to carry forward

- **Batch DOM reads before writes** — the three-phase render pattern (read all, diff in JS, write all) should be the standard for any Meadowsyn visual that updates DOM at polling frequency.
- **`perspective` on container, not per-element** — applies to any CSS 3D animation at scale.
- **Stable sort with secondary key** — any board that re-renders on poll needs deterministic ordering to prevent spurious visual noise.
- **`isConnected` guard on setTimeout callbacks** — standard pattern when DOM elements may be removed before timers fire.

## Open items for future experiments

- F8 (Static JSON DataPipe) would replace the inline fetch/poll loop with a proper `DataPipe` class
- The agent name / session identity deduplication relies on `wip[].agent === roster[].session` — needs a schema contract
- Duration format (MM:SS vs HH:MM) switchover could be configurable
