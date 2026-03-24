---
agent: fd-scope-containment
mode: review
target: docs/plans/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# Scope Containment Review: Meadowsyn Experiment Suite

Reviewed: plan (`docs/plans/2026-03-21-meadowsyn-experiments.md`) and PRD (`docs/prds/2026-03-21-meadowsyn-experiments.md`).

## F7 (Process Replay): SPLIT

**Diagnosis: This is three experiments wearing a trenchcoat.**

The plan specifies three distinct technical problems stitched into one experiment:

1. **Event log accumulation** (plan item 9): "accumulate factory-status snapshots into event log, detect state transitions (if bead was in-progress last snapshot, now closed -> shipped)." This is a data-layer concern -- it derives a new data structure (event log) from the raw snapshot stream. It belongs in F8/F9 as a `HistoryAccumulator` module, since both the static and SSE pipes already have ring buffers. F5 (Raster Heatmap) also needs accumulated history (plan item 10: "Accumulate history from data-pipe ring buffer"). Having two experiments independently solve history accumulation is a duplication signal.

2. **Process diagram with token animation** (items 1-6): The actual visual experiment -- swim lanes, colored dots moving through stages. This is the concept being tested.

3. **Playback controls with scrub/play/pause** (items 3, 7): A temporal navigation UI. The scrub bar, speed multiplier (1x/2x/5x/10x), and current-time indicator together form a reusable timeline control that F5 could also use.

4. **SVG/Canvas hybrid rendering** (item 10): A rendering architecture decision ("SVG for lanes/labels, Canvas for token animation (performance)") that adds integration surface area beyond what is needed to validate the process-replay concept.

**Recommendation:**
- **SPLIT** event log accumulation into F8 as a `HistoryAccumulator` class that both F5 and F7 consume.
- **TRIM** the SVG/Canvas hybrid to just SVG. The token count at experiment scale (20 agents, ~50 beads) does not justify a hybrid renderer. If SVG cannot handle it, that is a finding.
- **KEEP** playback controls within F7, but scope them to play/pause and a speed dropdown (1x/2x/5x). Cut the scrub bar -- scrubbing requires random-access into the event log, which is a second interaction paradigm on top of playback. Add scrubbing as a follow-up if the base replay proves valuable.

**Net reduction:** Remove ~30% of F7 implementation surface (event accumulation, scrub bar, hybrid renderer). Event accumulation moves to F8 where it serves F5 and F7 simultaneously.


## F6 (Loopy Signals): TRIM

**Diagnosis: Perturbation mode is a second experiment grafted onto a visualization.**

The core experiment (items 1-6, 8-10) is already substantial: an SVG causal loop diagram with animated particles whose rate is proportional to real throughput data. This alone tests whether feedback-loop visualization communicates factory dynamics.

Item 7 (perturbation mode) introduces a fundamentally different interaction: the user injects synthetic signals and watches propagation with transit-time delays. This requires:
- A simulation model (edge transit times, propagation rules)
- Synthetic signal injection separate from real data
- Visual distinction between real particles and injected pulses
- Timing logic for pulse propagation that may conflict with data-driven particle rates

This is not "double the scope" -- it is closer to 40% additional implementation -- but the simulation model is architecturally different from the data-driven visualization. The perturbation mode tests a different hypothesis (can users reason about causal propagation?) versus the base visualization (does the loop diagram communicate factory state?).

**Recommendation:**
- **TRIM** perturbation mode (item 7) from F6. The base visualization with data-driven particles, reinforcing/balancing loop indicators, and live node counts is a complete experiment.
- Record perturbation as a follow-up experiment (F6b) that layers onto a working F6. This also makes F6b a natural candidate for the composition shell -- users could toggle perturbation mode on/off.

**Net reduction:** Remove the simulation model and pulse injection, preserving the data-driven causal diagram.


## F4 (Cytoscape Graph): TRIM

**Diagnosis: The interaction layer is specified at polished-feature level, not prototype level.**

The visual experiment (items 1-5) is well-scoped: Cytoscape.js, fCoSE layout, two node types, color/size encoding. This is a graph visualization prototype.

The interaction layer (item 6) specifies three distinct click behaviors plus a reset gesture:
- Click agent -> highlight bead chain, dim others
- Click bead -> highlight agent + dependency path
- Double-click -> reset
- Mouse wheel zoom, pan (free from Cytoscape)

Item 7 adds live graph diffing with animated transitions on data updates: "diff graph on each data-pipe update (add/remove/update nodes, animate transitions)." This is the most expensive item -- graph diffing with animated node addition/removal against a force-directed layout is a known hard problem (layout stability, animation choreography, performance with concurrent add+remove).

The PRD acceptance criteria are more restrained: "Click agent -> highlight its bead + dependencies" and "Click bead -> highlight assigned agent + dep chain." No mention of animated transitions or live diffing.

**Recommendation:**
- **KEEP** single-click highlight (click agent -> highlight chain). This is native Cytoscape and trivial.
- **TRIM** the double-click reset gesture. A "Reset" button in the corner is cheaper and more discoverable.
- **TRIM** animated transitions on live update (plan item 7). Replace with: on data update, batch-update node attributes (color, size) in place. Defer layout-disrupting changes (node add/remove) to a manual "Refresh Layout" button. Animated layout transitions are a rabbit hole -- if the layout is stable on attribute-only updates, that is the finding.
- The PRD does not mention animated transitions. The plan added them. Follow the PRD.

**Net reduction:** Remove animated layout transitions and double-click reset. The experiment still validates the graph topology concept with live color/size updates and click-to-highlight.


## F10 (Composition Shell): TRIM

**Diagnosis: URL state management is production infrastructure, not an experiment.**

The core composition concept (items 1-4, 6) is the actual experiment: can the visuals be hot-swapped, do they share a data pipe cleanly, does the plugin interface (`mount/unmount`) work?

Item 5 is the scope concern: "URL state: `/#/split-flap?data=sse&agents=20&speed=5` (shareable)." This requires:
- Query parameter parsing and serialization
- Per-experiment state schema (what params does each visual accept?)
- History API integration for back/forward navigation
- State restoration on page load

The PRD says "URL-shareable state: `/#/split-flap?data=sse&agents=20`" -- so it does include this. But the plan goes further by specifying keyboard shortcuts (item 8: "1-6 for visuals, D for data toggle, F for fullscreen") and transition animations (item 7: "fade").

Query-param state serialization is production infrastructure. At the experiment stage, the hash route (`/#/split-flap`) is sufficient for navigation. The data source can be a dropdown whose value is not persisted in the URL. This avoids building a state serialization layer that will be thrown away or rebuilt when moving to a real framework.

**Recommendation:**
- **KEEP** hash-based routing (`/#/split-flap`). Minimal and sufficient.
- **KEEP** the plugin interface and data source selector.
- **TRIM** query parameter state (`?data=sse&agents=20`). The dropdown state does not need to survive a page reload at the experiment phase.
- **TRIM** keyboard shortcuts (item 8). These are polish, not experiment validation.
- **TRIM** transition animations (item 7). Fade between visuals is cosmetic -- hard-cut swap is fine for evaluating composition.

**Net reduction:** Remove URL query params, keyboard shortcuts, and transition animations. The shell still validates the composition hypothesis (mount/unmount, shared data pipe, route switching).


## F2 (Split-Flap Board): TRIM

**Diagnosis: Auto-sort and live-metrics header are shell-level concerns leaking into a visual experiment.**

The visual experiment is the split-flap animation itself: CSS-only character flip, dark background, monospace, "going gray" principle. This is the concept being tested.

Two items leak upward:

1. **Sort order** (plan item 6): "executing first, then dispatching, then idle." Sorting means rows move between renders, which interacts badly with the split-flap animation -- you get both character-flip and row-reorder simultaneously. This is a UX design decision, not a prototype concern. A static sort (alphabetical by agent name) lets the user build spatial memory. Dynamic sort is a second experiment on top of the visual.

2. **Header row with live metrics** (plan item 7): "MEADOWSYN FACTORY STATUS + timestamp + agent count + queue depth." This is a shell-level concern -- it is the same "factory status summary bar" specified in F10 item 4. Having both F2 and F10 independently implement a status header creates duplication and ambiguity about which is canonical.

**Recommendation:**
- **TRIM** dynamic sort. Use alphabetical sort. If dynamic sort proves important, it is a one-line change later.
- **TRIM** the header row with live metrics. The experiment is the split-flap animation, not the dashboard chrome. When F2 is mounted in the F10 shell, the shell provides the header. For standalone testing, a minimal `<h1>` with a timestamp is sufficient.

**Net reduction:** Minor -- removes sort animation interaction and deduplicates the status header. Keeps the experiment focused on whether split-flap animation communicates agent state changes effectively.


## F9 (SSE Server): TRIM

**Diagnosis: Static file serving from `../` creates a structural coupling.**

The PRD says: "Serves static files from `./public/`" (a contained directory). The plan says: "Serves static files from `../`" (the parent directory, meaning all of `experiments/`). These contradict each other.

Serving from `../` means:
- F9 must be started from a specific directory for paths to resolve
- All experiments must be siblings of `data-sse/` in the directory tree
- Any experiment directory restructuring breaks F9
- F9 becomes the de-facto dev server for the entire experiment suite, not a data pipe experiment

This couples F9's correctness to the directory layout of every other experiment.

Additionally, the plan specifies three HTTP endpoints beyond SSE:
- `GET /api/snapshot` -- current state
- `GET /api/history` -- last 720 snapshots as JSON array
- Heartbeat events every 15s

The history endpoint (720 snapshots = 1 hour) is server-side accumulation -- the same concern flagged in F7. This is appropriate for F9 (the server owns the data), but the 720-snapshot history duplicates the ring buffer in F8's DataPipe client. The experiment should test whether server-side history or client-side ring buffer is better, not ship both.

**Recommendation:**
- **TRIM** static file serving entirely. F9 is a data pipe experiment, not a dev server. Use `npx serve` or `python3 -m http.server` in the experiment root for static files. This removes the directory coupling.
- **KEEP** `/events` (SSE), `/api/snapshot`, and heartbeat -- these are the data pipe.
- **TRIM** `/api/history` endpoint. The client-side DataPipe already has a ring buffer (F8). If F9 adds server-side history, it should be a conscious follow-up experiment comparing client-side vs server-side accumulation, not bundled into the first SSE implementation.
- **Resolve PRD/plan contradiction:** Neither `./public/` nor `../`. No static serving.

**Net reduction:** Removes static file serving and server-side history endpoint. F9 becomes a focused SSE data pipe (~100 lines instead of ~200).


## Summary Table

| Experiment | Verdict | Items to Remove/Move | Estimated Scope Reduction |
|---|---|---|---|
| F7 (Process Replay) | SPLIT | Event accumulation -> F8. Cut scrub bar. Cut SVG/Canvas hybrid. | ~30% |
| F6 (Loopy Signals) | TRIM | Cut perturbation mode (-> F6b follow-up) | ~40% of interaction scope |
| F4 (Cytoscape Graph) | TRIM | Cut animated transitions, double-click reset. Follow PRD. | ~25% |
| F10 (Composition Shell) | TRIM | Cut query-param state, keyboard shortcuts, transition animation | ~30% |
| F2 (Split-Flap Board) | TRIM | Cut dynamic sort, live-metrics header (-> F10 shell) | ~15% |
| F9 (SSE Server) | TRIM | Cut static file serving, history endpoint | ~30% |

**Cross-cutting finding:** The plan consistently over-specifies relative to the PRD. The PRD acceptance criteria are reasonable experiment-scoped gates. The plan adds polish, interaction depth, and infrastructure that belong in a second iteration. Recommendation: treat PRD acceptance criteria as the implementation ceiling, not the plan's elaborated items.

**Structural finding:** Event log accumulation is needed by F5, F7, and F9 but owned by none. It should be a named module in F8 (`HistoryAccumulator`) that all consumers import. This avoids three independent implementations of snapshot-to-event-log derivation.
