---
agent: fd-composition-architecture
mode: review
target: docs/plans/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# F10 Composition Shell: Architectural Risk Review

## 1. Plugin Interface Insufficiency

**Severity: P1**

The proposed interface `{ name, mount(container, dataPipe), unmount() }` passes a DOM element and a data source. This is necessary but not sufficient for three of the six visuals:

- **Hydra (F3)** needs a `<canvas>` element it fully owns, sized to its container, and expects to control the WebGL context. If the shell creates a `<div>` and passes it, Hydra must create its own canvas inside it. That works, but Hydra also calls `requestAnimationFrame` in a loop -- the shell has no way to signal "pause rendering" without calling `unmount()`, which destroys state.
- **Cytoscape (F4)** requires its container to have explicit CSS dimensions at mount time (not `auto`, not `0x0`). If the shell fades in the container with `opacity: 0` or `display: none` before transitioning, Cytoscape computes a zero-size bounding box and the layout collapses. This is a well-known Cytoscape footgun.
- **Canvas heatmap (F5)** needs to know pixel dimensions to set `canvas.width`/`canvas.height` (not CSS size -- actual pixel backing). Requires a resize observer callback.

**Missing from interface:**
- No lifecycle signal between "container is in DOM" and "container has final dimensions." Mount is ambiguous.
- No `resize(width, height)` callback. The shell handles window resize, but plugins cannot react.
- No `pause()` / `resume()` for animation-heavy plugins (Hydra, F6 particles, F7 replay).

**Proposed fix:** Extend the plugin interface to a two-phase mount with resize and visibility signals:

```js
{
  name: 'hydra',
  // Phase 1: container is in DOM but may not have final size
  init(container, dataPipe) -> cleanup,
  // Phase 2: container has settled dimensions (called after transition)
  activate(rect: DOMRect),
  // Called on window/container resize
  resize(rect: DOMRect),
  // Pause rendering without destroying state
  deactivate(),
  // Destroy everything
  destroy(),
  thumbnail: '...'
}
```

This adds ~20 lines to each plugin adapter but eliminates the class of bugs where mount races with layout.


## 2. Lazy Loading vs. Self-Contained HTML

**Severity: P1**

The plan says "each visual is a separate JS file, loaded on route change." But the plan also says each experiment in Batch 2 is "a standalone `index.html` that imports mock data and data-pipe from Batch 1." These two statements describe different architectures:

- **Standalone HTML**: Each experiment has its own `<html>`, `<head>`, `<style>`, `<script>` blocks, its own CDN imports (`hydra-synth`, `cytoscape`, `d3`), and its own inline initialization code (`document.addEventListener('DOMContentLoaded', ...)` or top-level IIFE).
- **Mountable plugin JS**: A single ES module that exports the plugin interface, assumes a host page already has a container, and does not include `<html>`/`<head>`.

Every experiment needs refactoring from (A) to (B) before F10 can consume it. The refactoring per experiment:

| Experiment | CDN deps to externalize | Init code to wrap | Estimated effort |
|---|---|---|---|
| F2 Split-Flap | None (CSS-only) | Moderate: header row, sort logic, DOM construction | 30 min |
| F3 Hydra | `hydra-synth` (~200KB) | Heavy: canvas creation, WebGL context, rAF loop | 1 hr |
| F4 Cytoscape | `cytoscape` + `cytoscape-fcose` (~400KB) | Moderate: graph init, layout config, event handlers | 45 min |
| F5 Heatmap | None (canvas API) | Moderate: canvas setup, accumulator state | 30 min |
| F6 Loopy | `d3` (~250KB) or none | Light: SVG creation, particle system | 30 min |
| F7 Replay | `d3` or `pm4js` | Heavy: playback state machine, scrub bar, SVG+canvas hybrid | 1 hr |

**Total: ~4 hours of adapter work** not accounted for in the plan's "Batch 4" estimate. If each experiment is built as standalone HTML first (correct for Batch 2, since they need to be independently testable), the adapter layer is a second pass.

**Proposed fix:** Define the plugin interface contract in Batch 1 alongside F1/F8. Each Batch 2 experiment builds two entry points:
1. `index.html` -- standalone test harness (imports plugin, creates its own container and data pipe)
2. `plugin.js` -- ES module exporting the plugin interface

This way the adapter work happens during Batch 2 (when the developer has full context on the visual), not as a surprise in Batch 4.


## 3. State Loss on Data Pipe Switching

**Severity: P0**

F5 (heatmap) accumulates a 2-hour rolling history of per-agent status snapshots. F7 (replay) accumulates an event log derived from status transitions. When the user toggles "data source: mock -> sse" in the shell, the plan implies the dataPipe object is swapped. Two destructive paths:

**Path A -- unmount+remount the visual:** The visual loses all accumulated state. The heatmap goes blank. The replay timeline resets. The user waited 20 minutes for that history to build up.

**Path B -- swap dataPipe without unmounting:** The visual holds a reference to the old pipe's `subscribe` handle. New pipe starts emitting. Old pipe's history is orphaned. The visual's `getHistory()` calls now return data from the new pipe, which has no history yet. The heatmap's left 20 minutes of columns vanish; only the rightmost column has data.

Both paths are bad. This is the highest-severity issue because it silently destroys user-visible state with no recovery path.

**Proposed fix:** Separate transport from history. The `DataPipe` accumulates history in its ring buffer; the *transport* (mock/fetch/SSE) is a pluggable strategy beneath it:

```
DataPipe (owns ring buffer, owns subscriber list)
  +-- Transport (swappable: MockTransport / FetchTransport / SSETransport)
```

When the user toggles data source, the shell swaps the transport but keeps the same `DataPipe` instance. History is preserved. New data from the new transport appends to the existing buffer. The visual never sees the switch -- it keeps its subscription, `getHistory()` returns the full buffer spanning both transports.

The `DataPipe` constructor already takes `{ url, interval, bufferSize }`. Add a `setTransport(transport)` method that disconnects the old source and connects the new one without clearing the buffer.


## 4. Shared Header Collision with F2

**Severity: P2**

F2 (split-flap) defines its own header row: `MEADOWSYN FACTORY STATUS + timestamp + agent count + queue depth` (plan line 91). The composition shell also defines a shared header bar with: `factory status summary: agents active/total, queue depth by priority, uptime` (plan line 238).

When F2 is mounted inside the shell, the user sees two nearly-identical status bars stacked vertically -- the shell header and F2's built-in header. The information is redundant but not identical (shell header shows "by priority," F2 does not; F2 shows "agent count," shell shows "active/total"). This creates visual noise and wastes 40-60px of vertical space on a dashboard that prizes information density.

No other visual has this problem. F3-F7 are purely visual/interactive -- they don't embed their own chrome.

**Proposed fix:** F2's plugin adapter should accept an option `{ showHeader: boolean }`. In standalone mode (`index.html`), `showHeader = true`. When mounted in the shell, the shell passes `showHeader = false`, and F2 skips rendering its header row. F2's header content was always a subset of the shell header's, so nothing is lost.

Alternatively, define a plugin capability flag: `{ providesHeader: true }`. When the shell mounts a plugin with `providesHeader: true`, it hides its own header and lets the plugin's header take over. This is more flexible (F2's header is purpose-designed for a split-flap aesthetic), but adds complexity. The boolean option is simpler and sufficient.


## 5. URL Parameter Namespace Collision

**Severity: P2**

The plan shows: `/#/split-flap?data=sse&agents=20&speed=5`. These parameters have mixed ownership:

| Param | Owner | Used by |
|---|---|---|
| `data` | Shell | Data source selector |
| `agents` | Shell? F1? | Mock data generator agent count |
| `speed` | F7 only | Replay playback speed |

Today with 3 params, collisions are unlikely. But as experiments mature:
- F4 (graph) may want `layout=fcose` or `filter=active`
- F5 (heatmap) may want `window=2h` or `sort=activity`
- F6 (loopy) may want `speed` for particle rate -- colliding with F7's `speed`

The shell cannot distinguish `?speed=5` intended for F7 from `?speed=5` intended for F6 if both plugins read the same URL search params.

**Proposed fix:** Namespace experiment params with a prefix. Shell-level params remain bare; experiment params are prefixed with the experiment slug:

```
/#/replay?data=sse&replay.speed=5&replay.t=1200
/#/loopy?data=sse&loopy.speed=3&loopy.perturb=backlog
```

The shell strips the prefix when passing params to the plugin: F7 receives `{ speed: '5', t: '1200' }`. This prevents cross-experiment collisions and makes URLs self-documenting.

Implementation: ~15 lines in the shell's URL parser. No changes needed in plugins -- they receive a clean params object, unaware of the prefix.


## 6. Thumbnail Strip for Generative/Animated Content

**Severity: P2**

The shell's visual selector is a "thumbnail strip of all experiments." For F2 (split-flap text), F4 (graph layout), and F5 (heatmap grid), static PNG thumbnails are reasonable -- the visual is recognizable from a still frame.

For three experiments, static thumbnails are misleading or uninformative:

- **F3 (Hydra):** The entire point is continuous generative motion. A still frame looks like a random color gradient -- it does not convey "ambient field that responds to factory health." Every session produces different visuals depending on factory state, so no single screenshot is representative.
- **F6 (Loopy):** The value is in the animated particles flowing along edges. A still frame shows a static diagram with dots frozen mid-path -- it looks like a flowchart, losing the "signal propagation" concept.
- **F7 (Replay):** A still frame shows tokens at arbitrary positions. Without the scrub bar moving and tokens flowing, it looks identical to F6 or a generic process diagram.

**Proposed fix -- tiered approach:**

1. **Short animated thumbnails (preferred):** Record 3-second loops as WebP/APNG or short `<video>` clips. These autoplay on hover in the thumbnail strip and show the first frame at rest. This is the approach used by Shadertoy's gallery and CodePen's preview cards. File size: 50-150KB per animation at thumbnail resolution (160x90).

2. **Live mini-renders (ambitious):** Mount a scaled-down instance of the visual in the thumbnail slot. This is what Hydra's own editor does (small preview canvas). Performance cost: running 6 simultaneous visuals, even at thumbnail size, is likely too heavy -- especially Hydra's WebGL context. Reserve this for a "featured" preview of the active-1 experiment only.

3. **Annotated stills (fallback):** Use a representative still frame but overlay a small animated icon (pulsing ring for Hydra, flowing dots for Loopy, play button for Replay) to signal "this is dynamic content." Cheapest to implement, least impressive.

Recommendation: Start with (3) for initial F10 implementation, upgrade to (1) once the visuals stabilize and a canonical "interesting state" can be captured. Budget 1 hour for the thumbnail capture pass.


## Summary

| # | Issue | Severity | Fix effort |
|---|---|---|---|
| 1 | Plugin interface missing lifecycle/resize signals | P1 | Define extended interface in Batch 1 (~1 hr) |
| 2 | Standalone HTML to mountable plugin refactor unbudgeted | P1 | Build dual entry points during Batch 2 (~4 hr total) |
| 3 | Data pipe switching destroys accumulated visual state | P0 | Transport/buffer separation in DataPipe (~2 hr) |
| 4 | F2 header collides with shell header | P2 | `showHeader` option in F2 adapter (~15 min) |
| 5 | URL params will collide across experiments | P2 | Prefix-based namespacing in shell router (~30 min) |
| 6 | Static thumbnails for animated visuals | P2 | Annotated stills now, animated captures later (~1 hr) |

**Critical path impact:** Issues 1-3 should be resolved before Batch 2 begins implementation, since they affect the plugin contract that all six visuals must conform to. Issues 4-6 can be deferred to Batch 4 without blocking parallel work.
