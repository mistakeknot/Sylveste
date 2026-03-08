# Plan: Vision / Roadmap Alignment

**Bead:** iv-ey5wb | **PRD:** [docs/prds/2026-03-07-vision-roadmap-alignment.md](../prds/2026-03-07-vision-roadmap-alignment.md)

---

## Tasks

### Task 1: Create backlog.md from P2/P3 inventory
**File:** `docs/backlog.md` (new)
**Action:** Extract the full P2 (Next) and P3 (Later) item lists from `docs/demarch-roadmap.md` into a new `docs/backlog.md`. Include the category headers. Add a header noting this is the detailed inventory companion to the roadmap.

### Task 2: Restructure roadmap Next section
**File:** `docs/demarch-roadmap.md`
**Action:** Replace the detailed P2 inventory (lines ~127-268) with 5 strategic themes:
1. **Agency Architecture (Track C)** — C1 agency specs, C2 fleet registry, C3 budget-constrained composition
2. **Adaptive Routing (Track B)** — Interspect Phase 2, evidence-driven selection, canary monitoring
3. **Measurement Hardening** — Canonical landed-change entity, measurement read model, event validity
4. **Multi-Runtime Dispatch** — Codex-first routing, Intercom cutover, multi-agent coordination
5. **Developer Experience** — First-stranger experience, intermap code mapping, plugin ecosystem maturity

Each theme gets 2-3 representative items and a link to backlog.md for the full list.

### Task 3: Restructure roadmap Later section
**File:** `docs/demarch-roadmap.md`
**Action:** Replace the detailed P3 item list with theme-level descriptions only (no individual items). Link to backlog.md.

### Task 4: Add measurement chain callout to Now section
**File:** `docs/demarch-roadmap.md`
**Action:** After the Now items list, add a "Critical Path" callout:
```
**Measurement hardening chain:** iv-fo0rx → iv-057uu → iv-544dn
The path to making the north-star metric canonical rather than provisional.
```

### Task 5: Fix autonomy phrasing in vision
**File:** `docs/demarch-vision.md`
**Action:** Rephrase the "never pushes" absolute (around line 158) to lead with the graduated model. Change from:
> "The system never pushes code to a remote repository without human confirmation."
To:
> "The system gates code pushes on human confirmation, where the scope of confirmation evolves with the autonomy ladder:"

### Task 6: Add roadmap.json scope note
**File:** `docs/demarch-roadmap.md`
**Action:** After the header stats line, add: "Note: roadmap.json tracks only items explicitly placed in the roadmap. `bd stats` tracks all beads across the project."

## Sequence

Tasks 1-4 are sequential (1 creates backlog.md, 2-3 restructure roadmap referencing it, 4 adds to Now).
Task 5 and Task 6 are independent of 1-4 and each other.

## Verification

- [x] `docs/backlog.md` contains all P2/P3 items from the original roadmap
- [x] `docs/demarch-roadmap.md` Now section unchanged (3 frontier + detailed inventory)
- [x] `docs/demarch-roadmap.md` Next section has 5 themes, not 100+ items
- [x] Measurement chain explicitly called out
- [x] Vision autonomy phrasing is graduated, not absolute
- [x] No items lost (backlog.md has everything that was removed from roadmap)
