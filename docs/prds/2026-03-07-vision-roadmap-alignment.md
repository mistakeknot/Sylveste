# PRD: Vision / Roadmap Alignment

**Bead:** iv-ey5wb (P0, decision)
**Date:** 2026-03-07
**Source:** [Brainstorm](../brainstorms/2026-03-07-vision-roadmap-alignment.md)
**Scope:** Option B — Roadmap restructure + measurement chain clarification

---

## Problem

The root roadmap (`docs/sylveste-roadmap.md`) contains 100+ P2 items making it read as a backlog dump rather than a strategic program. The measurement hardening chain (the path to making the north-star metric canonical) is buried in the detailed inventory rather than called out as a strategic priority.

## Non-Goals

- Creating module-local roadmaps for all 26 modules without them (follow-up bead)
- Rewriting the vision doc (only a minor phrasing fix for the autonomy section)
- Creating the interspect roadmap (follow-up bead)

## Success Criteria

1. Root roadmap has: Now (8 items), Next (5 strategic themes with 2-3 representative items each), Later (themes only), and a link to a detailed backlog
2. Measurement hardening chain is explicitly called out in Now section
3. Autonomy phrasing in vision is clarified (remove false absolute)
4. roadmap.json scope documented with one-line note

## Features

### F1: Roadmap restructure
**What:** Restructure `docs/sylveste-roadmap.md` to separate strategic roadmap from detailed inventory.
- Now section: keep the 8 items as-is (they're well-curated)
- Next section: collapse 100+ P2 items into 5 strategic themes with 2-3 representative items each
- Later section: themes only, no individual items
- Move full P2/P3 inventory to `docs/backlog.md` (new file)
- Keep the Ecosystem Snapshot table (it's useful reference)
- Keep Cross-Module Dependencies (useful for planning)
- Keep Modules Without Roadmaps (useful for coverage tracking)

### F2: Measurement chain callout
**What:** In the Now section, add explicit callout of the measurement hardening dependency chain:
```
iv-fo0rx (canonical landed-change entity)
  → iv-057uu (measurement read model)
    → iv-544dn (event validity)
```
Frame as: "The path to making the north-star metric ($1.17/landable change) canonical rather than provisional."

### F3: Autonomy phrasing fix
**What:** In `docs/sylveste-vision.md` line 158, change from absolute "never pushes" to graduated statement that leads into the autonomy ladder.

### F4: Scope documentation
**What:** Add one-line note to roadmap explaining that roadmap.json tracks roadmap-placed items only, while bd stats tracks all beads.

## Risks

- **LOW:** Restructuring may lose items. Mitigation: the full inventory moves to backlog.md, nothing is deleted.
- **LOW:** Strategic theme selection is subjective. Mitigation: themes derived from existing roadmap categories.

## Estimated Effort

Complexity 2/5 (simple). Four file edits, one new file. No code changes.
