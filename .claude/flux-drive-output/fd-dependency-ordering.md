---
agent: fd-dependency-ordering
mode: review
target: docs/plans/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# Dependency Ordering Review: Meadowsyn Experiments

## Summary

The plan declares F1 as the critical path blocking all downstream work. This is overstated. The actual critical path is the DataPipe interface contract (defined in F8), not the mock data generator itself. Six findings below, three of which require plan amendments.

---

## Finding 1: F1 is not a true blocker for F2-F7 — P1 (hidden dependency not surfaced)

The dependency graph says F2-F7 all depend on F1. In practice, every visual experiment (F2-F7) needs two things:

1. **A JSON shape** — the factory-status schema (agent array, queue depth, bead objects).
2. **A delivery mechanism** — the DataPipe subscribe/getHistory/getLatest interface from F8.

F1 is a *convenience* for generating that JSON, but any hardcoded fixture file (fixture.json with 20 agents in various states) satisfies requirement (1). The visuals do not call the mock-data CLI — they call `dataPipe.getLatest()`. The plan already shows F8 in Batch 1 alongside F1, which is correct, but the dependency graph arrow `F1 <- F2..F7` overstates the coupling.

**Recommendation:** Add a 15-minute "F0: fixture.json" step (or inline it into F8's test harness which already has "raw JSON display"). Then F2-F7 can start as soon as F8 is done, even if F1's streaming/state-machine logic is still being refined. The graph should read `F8 <- F2..F7`, with F1 as a nice-to-have enhancement that upgrades fixture data to dynamic data.

**Impact if ignored:** No hard block, but the declared sequential dependency (Batch 1 must fully complete before Batch 2 starts) wastes ~30 min of wall-clock time because F1's streaming mode and state-machine tuning are not needed by any visual until composition testing.

---

## Finding 2: F8 vs F1 coupling is an interface contract, not a runtime import — P2 (minor optimization)

F8's DataPipe class fetches JSON from a URL or imports mock data for file:// mode (plan line: "Works with file:// (via imported mock data) and https:// (via fetch)"). This means F8 has an *optional* ES module import of F1's generateSnapshot. But the DataPipe class itself only needs to know the JSON shape, not F1's internal state machine.

F8 can develop against a stub:

```js
// stub for development
export function generateSnapshot() {
  return { agents: [...], queue: { depth: 5 }, timestamp: Date.now() };
}
```

The plan already co-locates F1 and F8 in Batch 1 which makes this moot in practice, but the dependency is an interface contract (JSON schema), not a runtime coupling. This is correctly handled.

**Recommendation:** No change needed. Documenting the JSON schema as a shared type (even just a JSDoc comment) would make the contract explicit.

---

## Finding 3: F9 does NOT depend on F8's client implementation — P0 (ordering is wrong)

The plan says `F8 <- F9` and "F9 extends F8's interface." But examining the specs:

- **F8** is a *client-side* class: DataPipe with subscribe(), polling via fetch(), ring buffer in the browser.
- **F9** is a *server* (Node.js, Express/bare http) that polls clavain-cli and serves SSE. It also includes a client library that "implements the same DataPipe interface."

These are two independent implementations of the same interface. F9's server has zero code dependency on F8. F9's client library reimplements the same API shape (subscribe, getHistory, getLatest, isStale) using EventSource instead of fetch.

The actual dependency is: **both F8 and F9 depend on the DataPipe interface contract** (method signatures + JSON schema). Neither depends on the other's implementation.

The plan puts F9 in Batch 3 ("after Batch 1, parallel with Batch 2") which is fine timing-wise, but the stated reason is wrong. F9 could start as soon as the DataPipe interface is defined (a 5-minute type spec), not after F8 is complete.

**Recommendation:** Change the dependency graph from `F8 <- F9` to `DataPipe interface <- F8, F9 (parallel)`. Move F9 into Batch 1 or make it parallel with F8. The SSE diff logic (computing JSON diffs server-side) has no relationship to F8's client-side fetch polling. The current Batch 3 placement delays F9 unnecessarily — if an implementer reaches Batch 3 and wants to test visuals with real SSE data, the server should already exist.

**Impact if ignored:** F9 is delayed by ~2 hours (all of Batch 2) for no technical reason. Any visual experiment wanting to test with live SSE data during Batch 2 development cannot.

---

## Finding 4: Batch 2 parallel work has implicit shared concerns — P1 (hidden dependency not surfaced)

Six experiments running in parallel with no shared utilities called out. The plan specifies per-experiment:

| Concern | F2 | F3 | F4 | F5 | F6 | F7 |
|---------|----|----|----|----|----|----|
| Color palette | gray/white/anomaly-color | Hydra uniforms | idle/exec/blocked colors | hex codes | green/red particles | priority colors |
| Dark background | #0a0a0a | fullscreen canvas | dark | dark | implied | implied |
| Font | Roboto Mono / JetBrains Mono | overlay text | hover labels | axis labels | - | sidebar text |
| DataPipe usage | subscribe() + 5s | subscribe() + 5s | subscribe() + diff | getHistory() + ring buffer | subscribe() + counts | getHistory() + events |

Shared concerns that will diverge without coordination:

1. **Color palette**: F2 uses named colors (gray, green, blue, red, amber). F5 uses hex codes (#1a1a1a, #1e3a5f, #1a4a2a, #5f1a1a, #4a3a1a). F4 says "idle (gray), executing (green), blocked (red)." F7 uses "priority colors" (P0=red, P1=amber, P2=blue). These will produce 6 incompatible palettes that look incoherent when composed in F10.

2. **Status-to-visual mapping**: F2 has 5 statuses (IDLE, EXEC, DISP, FAIL, GATE). F5 has 4 (idle, dispatching, executing, blocked). F6 models a different topology. When F10 composes them, inconsistent status vocabularies will confuse viewers.

3. **Timestamp formatting / duration display**: F2 shows [DURATION], F5 shows HH:MM on x-axis, F7 has a scrub bar. No shared formatter.

**Recommendation:** Add an "F0.5: shared constants" file before Batch 2 starts:
- `colors.js`: status-to-hex mapping, priority-to-hex mapping, background color
- `format.js`: duration formatter, timestamp formatter
- `schema.js`: JSDoc or TypeScript types for the factory-status JSON

This is 30 minutes of work that prevents 6 independent merge-conflict-prone color/format decisions. Without it, F10 (Composition Shell) will need to paper over inconsistencies or force a retroactive unification pass across all 6 visuals.

**Impact if ignored:** F10 composition will expose visual incoherence (different shades of "blocked red", different font choices, inconsistent status names). Fixing this retroactively across 6 experiments is more work than defining it up front.

---

## Finding 5: F10's plugin interface is not defined before visual experiments start — P0 (ordering is wrong)

The plan specifies F10's plugin interface:

```js
{ name: 'split-flap', mount(container, dataPipe), unmount(), thumbnail: '...' }
```

This interface dictates how every visual experiment must export itself. But F10 is in **Batch 4** — after all visuals are complete. The visuals (Batch 2) will each build their own initialization pattern:

- F2 might do `document.getElementById('root')` and `new DataPipe(...)` inline
- F3 might initialize Hydra on `document.querySelector('canvas')`
- F4 might do `cytoscape({ container: document.getElementById('cy') })`

None will implement `mount(container, dataPipe)` / `unmount()` because that contract does not exist yet. F10 will then need to either:
1. Wrap each experiment with an adapter (extra work, fragile), or
2. Retroactively refactor all 6 experiments to export the plugin interface (rework).

**Recommendation:** Extract the plugin interface definition into Batch 1 as a 10-minute task. Create `apps/Meadowsyn/experiments/plugin-interface.js`:

```js
/**
 * Every visual experiment must export:
 * @typedef {Object} VisualPlugin
 * @property {string} name
 * @property {function(HTMLElement, DataPipe): void} mount
 * @property {function(): void} unmount
 * @property {string} [thumbnail]
 */
```

Each Batch 2 experiment then implements this from the start. The plan should note: "Each experiment exports a default object matching the VisualPlugin interface, AND has a standalone index.html for independent testing."

**Impact if ignored:** All 6 visual experiments will need retrofitting in Batch 4. This is the single highest-risk ordering error in the plan.

---

## Finding 6: F10 can start before F9 completes — P2 (minor optimization)

The plan says Batch 4 requires "at least 2 visuals + 1 data pipe." F8 (static JSON pipe) is a data pipe completed in Batch 1. F9 (SSE pipe) is in Batch 3. So F10 can start as soon as 2 visuals from Batch 2 are done + F8, without waiting for F9.

The plan text already says this ("after at least 2 visuals + 1 data pipe work"), which is correct. The batch numbering (Batch 4 after Batch 3) implies sequential ordering that does not exist. F10 is gated on Batch 2 progress, not Batch 3 completion.

**Recommendation:** Clarify that Batch 3 and Batch 4 can overlap. F10 development starts with mock/static-json data sources. SSE support in F10 is added when F9 is ready, which could be concurrent.

**Impact if ignored:** Minor scheduling inefficiency. An implementer might wait for F9 to finish before starting F10, wasting time.

---

## Priority Summary

| # | Finding | Priority | Action |
|---|---------|----------|--------|
| 1 | F1 is not a true blocker for F2-F7 | P1 | Weaken dependency: F8 (not F1) is the real gate |
| 2 | F8/F1 coupling is interface-only | P2 | No action, correctly handled |
| 3 | F9 does not depend on F8's implementation | P0 | Fix graph: F8 and F9 are parallel, both depend on interface contract |
| 4 | No shared constants for Batch 2 parallelism | P1 | Add shared colors/format/schema before Batch 2 |
| 5 | Plugin interface not defined before visuals | P0 | Move plugin interface definition to Batch 1 |
| 6 | F10 can overlap with Batch 3 | P2 | Clarify in plan text |

## Corrected Dependency Graph

```
F0: Shared Constants (colors.js, format.js, schema types, plugin-interface.js)
  |
F1 (Mock Data) --- independent, enhances fixture data
F8 (Static JSON Pipe) --- depends on schema from F0
F9 (SSE Pipe) --- depends on schema from F0 (parallel with F8, not after it)
  | (F0 + F8 complete)
F2, F3, F4, F5, F6, F7 --- parallel, import DataPipe + shared constants,
                             export VisualPlugin interface
  | (any 2 visuals + F8 complete)
F10 (Composition Shell) --- can start during Batch 2/3, SSE added when F9 ready
```

Critical path: F0 (30 min) -> F8 (1 hr) -> first 2 visuals (2 hrs) -> F10 (2 hrs) = ~5.5 hrs.
Old critical path: F1+F8 (1 hr) -> all 6 visuals (2 hrs) -> F9 (1 hr) -> F10 (2 hrs) = ~6 hrs.
Savings: ~30 min wall-clock, plus elimination of rework risk from Findings 4 and 5.
