---
agent: fd-acceptance-criteria-quality
mode: review
target: docs/prds/2026-03-21-meadowsyn-experiments.md
timestamp: 2026-03-21
---

# Acceptance Criteria Quality Review: Meadowsyn Experiment Suite

## 1. Subjective Criteria

### S1: F2 "Legible at 3m viewing distance"

**Criterion text:** `Legible at 3m viewing distance (test: screenshot at 25% zoom)`

**Problem:** "Legible" is subjective. The proposed proxy test (screenshot at 25% zoom) is creative but unspecified -- 25% zoom of what resolution? On what monitor? A 4K screenshot at 25% is 960px wide; a 1080p screenshot at 25% is 480px wide. These produce very different results. The criterion also doesn't define what "legible" means -- can you read the agent name? The status? The bead ID?

**Replacement:**
```
- [ ] Status column text renders at >= 14px effective height at 1920x1080 viewport
- [ ] Agent name and status fields are distinguishable in a 480x270 screenshot
      (1080p at 25%) -- verified by reading all status values correctly
```

### S2: F3 "Smooth transitions when data updates"

**Criterion text:** `Smooth transitions when data updates (no jarring jumps)`

**Problem:** "Smooth" and "jarring" are subjective. No frame budget, transition duration, or measurement method specified.

**Replacement:**
```
- [ ] Metric-to-visual parameter transitions use linear interpolation over >= 1s
      (no discontinuous jumps between data updates)
- [ ] No single-frame delta exceeds 20% of the parameter's full range
```

### S3: F3 "Visually distinct states"

**Criterion text:** `Visually distinct states for: healthy factory, degraded, paused, critical`

**Problem:** "Visually distinct" has no measurable threshold. Two shades of blue could be called "visually distinct" by the developer but fail for a colorblind user.

**Replacement:**
```
- [ ] Each of the 4 factory states (healthy, degraded, paused, critical) uses a
      different dominant hue (measured: >60 degrees apart in HSL color space)
- [ ] States are distinguishable via oscillation speed alone (without relying on
      color) for accessibility
```

### S4: F4 "Agent nodes and bead nodes visually distinct"

**Criterion text:** `Agent nodes and bead nodes visually distinct (shape + color)`

**Problem:** Same as S3 -- "visually distinct" is subjective, though the parenthetical (shape + color) partially mitigates this.

**Replacement:**
```
- [ ] Agent nodes use circle shape; bead nodes use rounded-rectangle shape
- [ ] Agent and bead nodes use different hue families (>90 degrees apart in HSL)
```

---

## 2. Missing Criteria (plan spec behaviors with no PRD acceptance criterion)

### M1: F1 -- State machine transitions

**Plan spec (line 48):** `State machine per agent: idle -> dispatching -> executing -> (gated -> shipped | reworked -> idle)`

**Problem:** The PRD says "agent states change" but doesn't validate that state transitions follow a legal sequence. An implementation could randomly assign states and still pass.

**Add:**
```
- [ ] Agent state transitions follow the defined state machine
      (idle->dispatching->executing->gated->{shipped,reworked}->idle);
      no illegal transitions appear in stream output
```

### M2: F1 -- Realistic distributions

**Plan spec (line 49):** `Realistic distributions: 60% idle, 15% dispatching, 20% executing, 5% blocked`

**Problem:** No PRD criterion validates the distribution. "Realistic" is undefined.

**Add:**
```
- [ ] In a 60-second stream sample (N=60 snapshots, 20 agents), state
      distribution approximates: idle 50-70%, dispatching 10-20%,
      executing 15-25%, blocked 2-10% (chi-squared p > 0.05)
```

### M3: F1 -- ES module export

**Plan spec (line 51):** `Export as ES module too: import { generateSnapshot, createStream } from './index.js'`

**Problem:** No criterion requires the dual CLI/module interface. An implementation could be CLI-only and pass all PRD criteria.

**Add:**
```
- [ ] Exports generateSnapshot() and createStream() as named ES module
      exports, importable from other experiments
```

### M4: F2 -- Sort order

**Plan spec (line 88):** `Sort: executing first, then dispatching, then idle`

**Problem:** No PRD criterion specifies row ordering.

**Add:**
```
- [ ] Rows sorted by status priority: executing > dispatching > idle
      (within same status, sort by duration descending)
```

### M5: F2 -- Header row

**Plan spec (line 89):** `Header row: MEADOWSYN FACTORY STATUS + timestamp + agent count + queue depth`

**Problem:** No PRD criterion requires a summary header.

**Add:**
```
- [ ] Header row displays: title, current UTC timestamp, total agent count,
      and queue depth -- updates on each data refresh
```

### M6: F3 -- Overlay metrics text

**Plan spec (line 112):** `Overlay: semi-transparent text showing key metrics on top of generative field`

**Problem:** No PRD criterion mentions the metrics overlay. This is a significant UX feature with no acceptance test.

**Add:**
```
- [ ] Semi-transparent overlay displays at least: throughput, error rate, and
      agent utilization as text on top of the generative canvas
```

### M7: F4 -- Double-click reset, mouse interactions

**Plan spec (lines 132-134):** `Double-click -> reset highlight`, `Mouse wheel zoom, pan`

**Problem:** PRD specifies click-to-highlight but no way to undo it, and no mention of zoom/pan.

**Add:**
```
- [ ] Double-click resets all highlighting to default view
- [ ] Mouse wheel zooms; click-and-drag pans the graph
```

### M8: F4 -- Live graph diffing

**Plan spec (line 134):** `diff graph on each data-pipe update (add/remove/update nodes, animate transitions)`

**Problem:** No PRD criterion tests that the graph updates live without full re-layout.

**Add:**
```
- [ ] Graph updates incrementally on data change (add/remove/recolor nodes)
      without triggering a full fCoSE re-layout
```

### M9: F5 -- Click row detail panel

**Plan spec (line 153):** `Click row: highlight agent, show detail panel`

**Problem:** PRD mentions click-cell tooltip but not click-row detail panel.

**Add:**
```
- [ ] Click agent row highlights the entire row and opens a detail panel
      showing full agent name, current bead, and recent status history
```

### M10: F6 -- Reinforcing and balancing loop indicators

**Plan spec (lines 179-180):** `Reinforcing loop indicator (R)`, `Balancing loop indicator (B)`

**Problem:** No PRD criterion requires labeling the feedback loops with R/B notation (a core systems dynamics convention).

**Add:**
```
- [ ] Reinforcing loops labeled "R" and balancing loops labeled "B" per systems
      dynamics convention, visible on the diagram
```

### M11: F7 -- 10x playback speed

**Plan spec (line 191):** `1x/2x/5x/10x speed`

**Problem:** PRD says `1x/2x/5x speed` -- plan adds 10x. These must agree.

**Resolution:** Either add 10x to PRD or remove from plan. Recommend adding:
```
- [ ] Playback speeds: 1x, 2x, 5x, 10x
```

### M12: F7 -- Token color and size encoding

**Plan spec (lines 193-194):** `Token color: by priority (P0=red, P1=amber, P2=blue)`, `Token size: by age`

**Problem:** PRD describes "tokens (dots) moving through process" but doesn't specify any visual encoding for priority or age.

**Add:**
```
- [ ] Tokens colored by priority: P0=red, P1=amber, P2=blue
- [ ] Token size scales with age (older beads render larger)
```

### M13: F7 -- Event log sidebar

**Plan spec (line 196):** `Event log: scrolling sidebar showing dispatch events at current playback time`

**Problem:** No PRD criterion mentions the event log sidebar.

**Add:**
```
- [ ] Scrolling sidebar displays dispatch events synchronized to current
      playback timestamp
```

### M14: F9 -- History endpoint

**Plan spec (line 215):** `GET /api/history -- last 720 snapshots (1 hour) as JSON array`

**Problem:** PRD doesn't mention the history endpoint. Only /events and /api/snapshot are in criteria.

**Add:**
```
- [ ] GET /api/history returns last 720 snapshots as a JSON array
```

### M15: F9 -- Heartbeat events

**Plan spec (line 213):** `Heartbeat: event: heartbeat every 15s`

**Problem:** No PRD criterion for SSE keepalive. This is critical for proxy compatibility.

**Add:**
```
- [ ] SSE stream emits event: heartbeat every 15s to maintain connection
      through HTTP proxies
```

### M16: F9 -- Fallback from SSE to polling

**Plan spec (line 221):** `Falls back to polling if SSE fails`

**Problem:** No criterion tests graceful degradation.

**Add:**
```
- [ ] Client automatically falls back to polling /api/snapshot if
      EventSource connection fails after 3 retries
```

### M17: F10 -- Lazy loading

**Plan spec (line 240):** `Lazy loading: each visual is a separate JS file, loaded on route change`

**Problem:** No criterion requires lazy loading. All visuals could be bundled in one file.

**Add:**
```
- [ ] Each visual experiment loads as a separate JS module on route change
      (network tab shows distinct fetch per visual)
```

### M18: F10 -- Keyboard shortcuts

**Plan spec (line 243):** `Keyboard shortcuts: 1-6 for visuals, D for data toggle, F for fullscreen`

**Problem:** No PRD criterion for keyboard navigation.

**Add:**
```
- [ ] Keyboard shortcuts: 1-6 switch visuals, D toggles data source, F toggles
      fullscreen
```

### M19: F10 -- Transition animation

**Plan spec (line 242):** `Transition animation between visuals (fade)`

**Problem:** No criterion specifies visual transitions.

**Add:**
```
- [ ] Visual switches use a fade transition (opacity 1->0->1, duration >= 200ms)
```

---

## 3. Untestable Criteria

### U1: F3 "Uses hydra-synth npm package embedded in a React/vanilla wrapper"

**Criterion text:** `Uses hydra-synth npm package embedded in a React/vanilla wrapper`

**Problem:** This is an implementation constraint, not an acceptance criterion. You cannot verify "uses hydra-synth" from the user-facing behavior -- it requires source code inspection. Acceptance criteria should describe observable outcomes.

**Recommendation:** Move to implementation notes. Replace with:
```
- [ ] Generative visuals render on a full-screen canvas element and respond to
      factory metric changes within 3s of data update
```

### U2: F4 "Uses Cytoscape.js with fCoSE layout"

**Criterion text:** `Uses Cytoscape.js with fCoSE layout`

**Problem:** Same as U1 -- technology choice, not testable behavior.

**Recommendation:** Move to implementation notes. The behavioral criteria (graph layout, click interactions) are already testable.

### U3: F7 "Uses PM4JS or D3 for rendering"

**Criterion text:** `Uses PM4JS or D3 for rendering`

**Problem:** Same pattern -- implementation constraint stated as acceptance criterion.

**Recommendation:** Remove from acceptance criteria. Move to implementation notes.

### U4: F6 "SVG-based with D3 or vanilla"

**Criterion text:** `SVG-based with D3 or vanilla`

**Problem:** Implementation choice, not testable from behavior.

**Recommendation:** Move to implementation notes. The behavioral criteria (nodes, particles, perturbation) are already testable.

### U5: F9 "Server in Go or Node.js, < 200 lines"

**Criterion text:** `Server in Go or Node.js, < 200 lines`

**Problem:** Line count is not a functional acceptance criterion. It's a complexity budget useful for planning but unmeasurable as a pass/fail gate (does it count comments? blank lines? imports?).

**Recommendation:** Move "< 200 lines" to implementation notes. Keep language choice if it matters for deployment.

---

## 4. Contradictions

### C1: F10 websocket in data source toggle vs. non-goal

**Criterion text (F10, line 105):** `Data source toggle: static-json / sse / websocket / mock`

**Non-goal (line 115):** `WebSocket data pipe (defer -- SSE covers real-time push, simpler)`

**Problem:** The F10 acceptance criterion requires a websocket data source option, but websocket is explicitly listed as a non-goal. These directly contradict. An implementer cannot satisfy both.

**Fix:** Remove websocket from the F10 data source toggle:
```
- [ ] Data source toggle: mock / static-json / sse
```

### C2: F10 data source list vs. plan implementation

**Plan F10 (line 231):** `Data source selector (dropdown): mock | static-json | sse`

**PRD F10 (line 105):** `Data source toggle: static-json / sse / websocket / mock`

**Problem:** Plan correctly excludes websocket but PRD still includes it. Also, ordering differs (plan puts mock first, PRD puts static-json first). The plan is correct; the PRD needs updating.

### C3: F5 tooltip -- "click cell" vs. plan "hover"

**PRD F5 (line 60):** `Click cell -> tooltip with agent name, bead, timestamp`

**Plan F5 (line 152):** `Hover: tooltip with agent name, bead, exact timestamp, status`

**Problem:** PRD says click triggers tooltip; plan says hover triggers tooltip. These are different interaction patterns. Hover is the more conventional choice for heatmap tooltips.

**Fix:** Align on hover:
```
- [ ] Hover cell -> tooltip with agent name, bead, exact timestamp, and status
```

### C4: F5 color scheme discrepancy

**PRD F5 (line 61):** `Color scheme: dark gray (idle), blue (dispatching), green (executing), red (blocked/error)`

**Plan F5 (lines 145-149):** Adds a 5th state: `Quality gate: #4a3a1a (dark amber)`

**Problem:** PRD specifies 4 states; plan specifies 5. Quality gate is a distinct status in the factory state machine (F1 spec line 48) but missing from the PRD color scheme.

**Fix:** Add quality gate to PRD:
```
- [ ] Color scheme: near-black (idle), dark blue (dispatching), dark green
      (executing), dark red (blocked/error), dark amber (quality gate)
```

---

## 5. Schema References

### SC1: F1 "matching factory-status schema"

**Criterion text:** `Outputs valid JSON matching factory-status schema`

**Problem:** No formal JSON Schema file exists. The schema is defined implicitly by Go struct tags in `os/Clavain/cmd/clavain-cli/factory_status.go` (lines 13-61). The struct defines:

```
factoryStatus {
  timestamp, fleet{total_agents, active_agents, idle_agents},
  queue{total, by_priority[{priority, count}], blocked},
  wip[{agent, bead_id, title, age, age_seconds}],
  recent_dispatches[{timestamp, bead_id, agent, outcome, score}],
  watchdog{last_sweep, stale_found_last, actions_last, quarantined_total},
  factory_paused
}
```

The mock data generator must produce JSON matching this exact structure -- but there is no factory-status.schema.json file to validate against programmatically.

**Recommendations:**

1. Extract a JSON Schema file from the Go structs:
   `apps/Meadowsyn/schemas/factory-status.schema.json`
2. Update the F1 criterion to reference it:
   ```
   - [ ] Outputs valid JSON conforming to apps/Meadowsyn/schemas/factory-status.schema.json
   - [ ] Schema derived from os/Clavain/cmd/clavain-cli/factory_status.go struct definitions
   ```
3. Add a validation test: `ajv validate -s factory-status.schema.json -d <(node mock-data/index.js)`

### SC2: F1 -- Schema gaps for mock data

The factory-status schema includes fields the mock generator may struggle with:
- `watchdog.last_sweep` -- requires plausible timestamps
- `recent_dispatches[].score` -- dispatch scoring semantics undefined for mock
- `factory_paused` -- boolean, but no PRD criterion tests the paused state in mock data

**Add:**
```
- [ ] Mock data includes all top-level schema fields (fleet, queue, wip,
      recent_dispatches, watchdog, factory_paused) -- no fields omitted
- [ ] Supports --paused flag to simulate factory-paused state
```

---

## 6. Performance Criteria

### P1: F3 "60fps on a 2020-era laptop"

**Criterion text:** `Runs at 60fps on a 2020-era laptop`

**Problems:**

1. **No measurement method specified.** How do you measure fps? Chrome DevTools performance panel? requestAnimationFrame timestamp deltas logged to console? The stats.js overlay? Each gives different results.

2. **"2020-era laptop" is undefined.** This spans from a Chromebook with Intel UHD 600 to a MacBook Pro 16" with AMD Radeon Pro 5600M. A 2020 Dell XPS 13 with Intel Iris Plus G7 is ~10x less capable in WebGL than a 2020 MacBook Pro with discrete GPU.

3. **60fps may be unrealistic for WebGL on integrated graphics.** Hydra-synth uses WebGL fragment shaders on a full-screen canvas. On Intel UHD/Iris integrated graphics (common in 2020 laptops), full-screen shader effects with multiple oscillators + noise typically achieve 30-45fps at 1080p. The hydra-synth library itself documents performance issues on integrated GPUs. 60fps is achievable on discrete GPUs or at reduced resolution.

4. **No resolution specified.** 60fps at 720p is very different from 60fps at 4K.

**Replacement:**
```
- [ ] Maintains >= 30fps sustained (measured via Chrome DevTools Performance
      panel, 10s recording) at 1920x1080 on Intel Iris Plus (or equivalent
      integrated GPU)
- [ ] Maintains >= 55fps sustained on discrete GPU (NVIDIA GTX 1650 / AMD
      RX 580 class or above) at 1920x1080
- [ ] If frame rate drops below 30fps, automatically reduces canvas resolution
      to maintain interactivity
```

**Rationale for 30fps floor:** Ambient visualization is a background element, not interactive UI. 30fps is perceptually smooth for slowly-evolving generative art. The original 60fps target on integrated graphics would likely force compromises (half-resolution canvas, simplified shaders) that undermine the visual quality goal.

### P2: F4 "Handles 50+ nodes without layout thrashing"

**Criterion text:** `Handles 50+ nodes without layout thrashing`

**Problem:** "Layout thrashing" is informal. Does it mean:
- The layout doesn't restart from scratch on each update?
- Nodes don't visibly jump positions?
- Layout converges within N seconds?
- Frame rate stays above some threshold?

**Replacement:**
```
- [ ] With 50 agent+bead nodes, initial fCoSE layout converges within 3s
- [ ] Incremental updates (add/remove 1-3 nodes) do not trigger full re-layout;
      existing nodes shift < 50px from their prior positions
- [ ] Interaction (click, zoom, pan) remains responsive (< 100ms input-to-paint)
      with 50+ nodes
```

### P3: F5 -- No performance criterion for canvas rendering

**Problem:** F5 specifies canvas for performance but sets no performance target. With 24 columns x 100 agents = 2400 cells, canvas should be fine, but there's no criterion.

**Add:**
```
- [ ] Canvas heatmap renders 100-agent x 24-column grid at >= 30fps during
      live-tail scroll updates
```

### P4: F8 -- Ring buffer memory bound

**Criterion text:** `Ring buffer stores last N snapshots (default 720 = 1 hour at 5s)`

**Problem:** 720 snapshots of factory-status JSON (with 100 agents) could be 50-100MB in browser memory. No memory budget is specified.

**Add:**
```
- [ ] Ring buffer memory usage with 720 snapshots x 100 agents stays under
      150MB (measured via Chrome DevTools Memory snapshot)
```

---

## Summary

| Category | Count | Critical |
|----------|-------|----------|
| Subjective criteria | 4 | S1, S3 |
| Missing criteria | 19 | M1, M3, M11 |
| Untestable criteria | 5 | U1 (pattern, not blocking) |
| Contradictions | 4 | C1 (websocket non-goal) |
| Schema references | 2 | SC1 (no schema file) |
| Performance criteria | 4 | P1 (60fps unrealistic) |
| **Total findings** | **38** | |

### Top 5 actions to prioritize:

1. **C1: Remove websocket from F10 data toggle** -- direct contradiction with non-goals, will confuse implementers.
2. **SC1: Extract factory-status JSON Schema** -- F1 (mock data) is the critical path; all visuals depend on it. Without a schema file, "matching factory-status schema" is unverifiable.
3. **P1: Revise 60fps to 30fps floor on integrated GPU** -- current target is likely unachievable without resolution hacks that defeat the purpose.
4. **M11: Align playback speeds between PRD and plan** -- PRD says 1x/2x/5x, plan says 1x/2x/5x/10x. Trivial to fix, but implementers will be confused by the mismatch.
5. **M1-M3: Add state machine and distribution criteria to F1** -- F1 is the foundation; weak criteria here cascade to all downstream experiments.
