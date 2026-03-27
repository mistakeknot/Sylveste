# Brainstorm: Vision / Philosophy / Roadmap Alignment

**Bead:** iv-ey5wb (P0, decision)
**Date:** 2026-03-07
**Sources:** `docs/sylveste-vision.md` (v3.2), `docs/sylveste-roadmap.md`, `PHILOSOPHY.md`, `bd stats`, `bd list --priority=0`

---

## Context

Sylveste has three strategic documents that should form a coherent stack:
- **PHILOSOPHY.md** — why these tradeoffs
- **sylveste-vision.md** — what we're building and where we are
- **sylveste-roadmap.md** — what's next, in priority order

The bead description identified 7 gaps. This brainstorm validates each against current source data, assesses severity, and proposes fixes.

---

## Gap Analysis

### Gap 1: Roadmap overload
**Claim:** roadmap.json contains 230 items (48 now, 132 next, 50 later). Too much for a top-level roadmap.
**Verdict: CONFIRMED.** The roadmap doc lists 8 Now items, ~100+ Next (P2) items across 12 categories, and ~20 Later (P3) items. The JSON parse failed in the previous session so exact counts are unverified, but the markdown itself is 437 lines with extensive P2 inventory. A top-level roadmap with 100+ P2 items reads as a backlog dump, not a strategic program.
**Severity: HIGH.** This dilutes the signal of what actually matters. The 8 Now items are sharp and well-justified. Everything after them is noise at the roadmap level.
**Fix direction:** Compress root roadmap to Now (8 items) + a curated "Next 5" strategic themes. Move detailed P2/P3 inventory to `docs/backlog.md` or module-local roadmaps. The `interpath:propagate` skill already exists for pushing items to subrepo roadmaps.

### Gap 2: North-star metric drift
**Claim:** Vision says north-star never measured, but baseline exists from 2026-02-28.
**Verdict: ALREADY FIXED.** Vision v3.2 (dated 2026-03-06) now says: "The cost-per-landable-change baseline was established on 2026-02-28 (iv-b46xi, closed). After 2,567 closed beads, the system now measures this number..." The drift existed in an earlier version but has been corrected.
**Severity: NONE (resolved).** No action needed.

### Gap 3: Priority misalignment (iv-ho3)
**Claim:** Vision calls iv-ho3 a P0; roadmap places it in P2; live bead is priority 2.
**Verdict: ALREADY FIXED.** Vision v3.2 explicitly notes: "*Note: iv-ho3 (StrongDM Factory Substrate) is tracked at P2, not P0.*" The vision was updated to match reality. Live bead confirms P2.
**Severity: NONE (resolved).** The vision was corrected. But this is a *class* of problem — priority drift can recur. Worth adding a periodic check.
**Fix direction:** Add a "priority parity check" to interwatch that compares bead priorities against vision/roadmap doc mentions. Flag when a doc says "P0" but the bead says otherwise.

### Gap 4: Autonomy contradiction
**Claim:** "Never pushes code without human confirmation" contradicts L4 auto-ship.
**Verdict: NUANCED, NOT A CONTRADICTION.** Vision v3.2 now includes an explicit autonomy ladder for shipping:
- L0-L2 (current): Per-change human confirmation before each push.
- L3: Human sets shipping policy; agent pushes when policy conditions are met.
- L4: Human approves the policy itself; agent pushes autonomously within policy bounds.

This is well-articulated. "Human confirmation" evolves from per-change to per-policy. However, the phrase "never pushes code to a remote repository without human confirmation" (line 158) still appears as an absolute statement before the ladder clarifies it. The tension is rhetorical, not architectural.
**Severity: LOW.** The content is correct but the prose ordering creates a false absolute before qualifying it.
**Fix direction:** Rephrase line 158 to: "The system gates code pushes on human confirmation, where the scope of 'confirmation' evolves with the autonomy ladder:" followed by the ladder. Removes the initial absolute.

### Gap 5: Measurement substrate provisional
**Claim:** Philosophy says "receipts, not narratives" but measurement is still explicitly provisional.
**Verdict: CONFIRMED — AND CORRECTLY DISCLOSED.** The vision doc includes multiple explicit caveats:
- "The current north-star baseline is still provisional rather than canonical" (line 82)
- "Current-state caveat: this is the design rule, not a claim that every attribution path has fully reached it today" (line 98)
- "Some measurement plumbing still uses temp-file bridges and heuristic joins" (line 98)

The philosophy is aspirational; the vision honestly discloses where reality falls short. This is the *right* relationship between philosophy and status — the philosophy sets the bar, the vision reports progress against it.
**Severity: MEDIUM.** Not because there's a contradiction (there isn't), but because the gap between aspiration and implementation is the core technical risk. The roadmap should make measurement hardening more prominent.
**Fix direction:** Ensure the roadmap's Now section includes the measurement hardening chain: iv-fo0rx (canonical landed-change entity) → iv-057uu (measurement read model) → iv-544dn (event validity). Currently iv-fo0rx is in Now (good), but the dependency chain could be called out more explicitly as "the path to making the north star canonical."

### Gap 6: 26 modules without roadmaps
**Claim:** Roadmap lists 26 modules without roadmaps, including interspect which is central to the adaptive-routing thesis.
**Verdict: CONFIRMED.** The roadmap's "Modules Without Roadmaps" section lists 26 modules. Notable gaps:
- **interspect** — the adaptive profiler, central to the learning flywheel. Has a vision doc but no roadmap.
- **intersynth** — multi-agent synthesis, used by flux-drive.
- **interpeer** — cross-AI review.
- **intertrust** — agent trust scoring.
- **intercache** — cross-session semantic cache.

Many of these are "early" status modules where a roadmap would be premature. But interspect is not early — it's a pillar with shipped features and a complex multi-phase plan.
**Severity: MEDIUM.** Most of the 26 are genuinely early and don't need roadmaps yet. But interspect absolutely does. The others are fine as-is until they reach "active" status.
**Fix direction:** Create an interspect roadmap (it already has `docs/interspect-vision.md`; extract roadmap items from vision + existing beads). For the other 25, triage: which are active enough to warrant a roadmap? The rest can stay without one.

### Gap 7: Status count inconsistency
**Claim:** sylveste-roadmap.md says 719 open / 78 blocked, roadmap.json says 95 open / 0 blocked, bd stats says 699 open / 66 blocked.
**Verdict: PARTIALLY CONFIRMED.** Current state:
- `sylveste-roadmap.md` header says: "Open beads: 698 (per bd stats, 2026-03-06) | Blocked: 68"
- Live `bd stats` (2026-03-07): 701 open, 68 blocked, 2565 closed
- roadmap.json: not verified (JSON parse failed)

The roadmap doc now cites bd stats as its source and includes the date. The numbers are close (698 vs 701 is 3 new beads since the doc was updated, normal). The roadmap.json discrepancy (95 vs 700) likely reflects different scopes (roadmap.json may only track items explicitly placed in the roadmap, not all beads).
**Severity: LOW.** The roadmap doc now labels its source. The roadmap.json scope difference should be documented but isn't urgent.
**Fix direction:** Add a one-line note to the roadmap doc explaining that roadmap.json tracks only roadmap-placed items, while bd stats tracks all beads.

---

## Summary

| Gap | Status | Severity | Action |
|-----|--------|----------|--------|
| 1. Roadmap overload | Confirmed | HIGH | Compress to Now + 5 strategic themes, move P2/P3 inventory |
| 2. North-star drift | Already fixed | NONE | — |
| 3. Priority misalignment | Already fixed | NONE | Add interwatch priority parity check (future) |
| 4. Autonomy contradiction | Rhetorical only | LOW | Rephrase absolute statement in vision |
| 5. Measurement provisional | Correctly disclosed | MEDIUM | Make measurement hardening chain prominent in Now |
| 6. 26 modules without roadmaps | Confirmed | MEDIUM | Create interspect roadmap; triage rest |
| 7. Status count inconsistency | Mostly fixed | LOW | Document roadmap.json scope |

## Recommendations (ranked)

1. **Restructure the roadmap** (Gap 1) — The highest-impact change. The root roadmap should be a strategic program, not a backlog. Move the detailed inventory.
2. **Create interspect roadmap** (Gap 6) — The profiler is central to the learning thesis. It needs its own roadmap extracted from the vision doc and existing beads.
3. **Clarify measurement hardening path** (Gap 5) — Make the iv-fo0rx → iv-057uu → iv-544dn chain explicit as "the path to a canonical north star."
4. **Fix autonomy phrasing** (Gap 4) — Small prose edit, removes a misleading absolute.
5. **Document roadmap.json scope** (Gap 7) — One line explaining the count difference.

## Options

**Option A: Full alignment pass (all 5 fixes)**
Edit vision, roadmap, and create interspect roadmap in one sprint. Comprehensive but larger scope.

**Option B: Roadmap restructure only (Gap 1 + 5)**
Restructure the roadmap and clarify the measurement chain. Highest impact per effort. Leave the rest for follow-up beads.

**Option C: Doc edits only (Gap 4 + 7)**
Quick prose fixes to vision and roadmap. Low effort, low impact. Doesn't address the structural issues.

**Recommended: Option B** — the roadmap restructure is the highest-value change and naturally incorporates the measurement chain clarification. The interspect roadmap (Gap 6) can be a follow-up bead. The prose fixes (Gaps 4, 7) can be folded in as they're trivial.
