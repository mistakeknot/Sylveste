---
artifact_type: plan
bead: Demarch-r24y
brainstorm: docs/brainstorms/2026-03-22-split-flap-board-brainstorm.md
stage: planned
---

# Plan: F2 — Split-Flap Departure Board

## Overview

Single `index.html` at `apps/Meadowsyn/experiments/split-flap/` that renders AI factory status as a FIDS split-flap departure board. CSS-only flip animation, dark background, monospace font, color-on-anomaly only.

**Data flow:** F1 CLI (`ideagui-pipe`) generates `snapshot.json` → F2 fetches and polls it every 5s.

## Tasks

### Task 1: Directory + Static Snapshot Generation

Create `apps/Meadowsyn/experiments/split-flap/` directory structure.

Add a `generate.sh` script that calls F1 to produce a static snapshot. Must handle missing `clavain-cli` gracefully — use `--factory-only` flag or catch failure and fall back to generating roster-only output:
```bash
#!/bin/bash
cd "$(dirname "$0")"
node ../ideagui-pipe/cli.js --factory-only > snapshot.json 2>/dev/null || \
  echo '{"error":"clavain-cli unavailable, use mock-snapshot.json"}' > snapshot.json
```

Create `mock-snapshot.json` with hardcoded data (~12 agents in varied states) using realistic Culture ship names (Mistake Not..., Grey Area, Falling Outside The Normal Moral Constraints, etc.). Include agents in all states: idle, executing, dispatching, blocked, gated. Mock data must match F1's snapshot schema exactly:
- `fleet.agents[]` with `session_name`, `status`
- `wip[]` with `bead_id`, `project`, `status`, `age`
- `roster[]` with `session`, `project`, `terminal`, `agent`, `live`
- `queue[]` — define as open beads with no current claimant
- `meta` with `roster_total`, `live_sessions`, `fleet_total`
- Include ≥12 rows to establish the board's minimum visual density

Files: `generate.sh`, `mock-snapshot.json`

### Task 2: HTML Shell + CSS Foundation

Single `index.html` with:
- `<meta viewport>` for responsiveness
- Google Fonts import: JetBrains Mono (with `font-display: swap` and `<link rel="preconnect">`)
- Full-viewport dark background (#0a0a0a)
- CSS custom properties for the color palette:
  - `--color-idle: #666` (gray)
  - `--color-exec: #e0e0e0` (near-white)
  - `--color-disp: #999` (dim white)
  - `--color-fail: #e74c3c` (red — anomaly)
  - `--color-gate: #f39c12` (amber — anomaly)
  - `--color-stale: #f39c12` (amber — reuse gate color for staleness, keeps palette tight)
  - `--color-bg: #0a0a0a`
  - `--color-bg-alert: #1a0000` (header background when anomaly count > 50% of rows)
  - `--color-text: #ccc`
- Header section: `MEADOWSYN FACTORY STATUS` left-aligned, timestamp + stats right-aligned
  - Header background shifts to `--color-bg-alert` when anomaly count exceeds threshold
- Board container with CSS grid for rows
- Minimum 12 visible rows — pad with empty dash-filled placeholder rows to maintain grid structure
- Footer: data source indicator + stale warning (uses `--color-stale`)

Files: `index.html` (HTML + CSS in single file)

### Task 3: Split-Flap CSS Animation

The core visual effect. Each cell is a `.flap-cell` containing individual `.flap-char` elements.

**Performance-critical:** `perspective` must be on the `.flap-cell` container (not per `.flap-char`) with `transform-style: preserve-3d`. Per-element perspective creates isolated 3D contexts that prevent GPU batching.

Per character:
- Container is `position: relative` with `overflow: hidden` and fixed `width` (ch-based for monospace)
- Uses two data attributes: `data-char` (current) and `data-char-old` (previous) to support flip transition
- `::before` = top half (shows old char via `attr(data-char-old)`), `::after` = bottom half (shows new char via `attr(data-char)`)
- On value change, add class `.flipping` which triggers:
  1. Top half rotates down (`rotateX(-90deg)`) over 150ms
  2. Bottom half rotates up from behind over 150ms (delayed 150ms)
  3. After 300ms total, copy `data-char` to `data-char-old` and remove `.flipping`
- `transform-origin: bottom` for top half, `top` for bottom half
- Stagger: each character gets `animation-delay: calc(var(--char-index) * 30ms)` for cascade

**Layer promotion:** Only promote during animation to avoid 3200 idle layers:
```css
.flap-cell {
  perspective: 800px;
  transform-style: preserve-3d;
}
.flap-char.flipping::before,
.flap-char.flipping::after {
  will-change: transform;
}
```

**First-render stagger:** Add `--row-index` CSS variable to each row, offset row start by `calc(var(--row-index) * 50ms)` to spread initial burst across ~1s.

Animation fires only when a character value actually changes (not on every refresh).

Files: CSS within `index.html`

### Task 4: Data Fetch + Rendering Logic

JavaScript module (inline `<script type="module">`) that:

1. **Fetch layer:** Tries `snapshot.json` first, falls back to `mock-snapshot.json`. Polls every 5s. Tracks `isStale` (last success > 15s ago).

2. **Data mapping:** Extract rows from snapshot:
   - Primary source: `fleet.agents[]` — each agent is a row
   - Enrich from `wip[]` — match by project/session to get bead_id, title, age
   - Enrich from `roster[]` — match for liveness
   - If fleet is empty, fall back to roster entries

3. **Row model:**
   ```js
   { status, agentName, beadId, taskTitle, duration, statusColor }
   ```
   - `status`: 4-char abbreviation — `IDLE`, `EXEC`, `DISP`, `FAIL`, `GATE`
   - `agentName`: parsed session name or roster session (padded to 24 chars)
   - `beadId`: from WIP match (padded to 12 chars) or `────`
   - `taskTitle`: from WIP match (truncated to 32 chars) or `··················`
   - `duration`: from WIP age, formatted as `MM:SS` (under 1h) or `HH:MM` (over 1h), or `──:──`

4. **Sort order:** FAIL/GATE first (anomalies), then EXEC, then DISP, then IDLE.

5. **Row padding:** Always render `max(rows.length, 12)` rows. Pad short lists with blank placeholder rows (all dashes, IDLE color).

6. **Render loop — batch reads then writes:**
   - Phase 1 (read): Read all current `data-char` values from DOM into a plain JS array
   - Phase 2 (diff): Compare against new data entirely in JS memory
   - Phase 3 (write): Write all changed `data-char`/`data-char-old` attributes and add `.flipping` classes in a single pass
   - This prevents style-recalculation thrash from interleaved reads/writes

7. **Header row:**
   ```
   MEADOWSYN FACTORY STATUS          22 MAR 2026  14:32:07  │  AGENTS: 12/20  │  QUEUE: 33
   ```
   QUEUE = count of open beads with no current claimant (from `queue[]` in snapshot).

Files: JS within `index.html`

### Task 5: Polish + Verification

- Responsive: min-width ~900px, horizontal scroll below that
- Gentle row separator lines (1px #1a1a1a)
- Status column: fixed-width, colored per status, slight glow on FAIL/GATE (`text-shadow`)
- Test with mock data: verify flip animation, sort order, color discipline
- Test with real data: run `generate.sh`, open in browser, confirm data renders
- Verify "going gray" — only FAIL, GATE, and stale-warning should have noticeable color
- Verify all-failing edge case: header shifts to alert background
- Verify empty/idle edge case: board maintains 12-row minimum with placeholder rows

Files: refinements to `index.html`

## Verification Criteria

1. Opens in browser with no build step (just `open index.html`)
2. Split-flap animation fires on character changes with staggered cascade
3. Rows sorted: anomalies first, then by activity
4. Color only on FAIL (red) and GATE (amber) — everything else is grayscale (stale warning reuses amber)
5. Header shows factory name, timestamp, agent count, queue depth
6. Works with both mock-snapshot.json and real snapshot.json from F1
7. Dark background, JetBrains Mono, no visual clutter
8. Board maintains minimum 12 rows with placeholder padding
9. Header background shifts when majority of rows are in anomaly state
