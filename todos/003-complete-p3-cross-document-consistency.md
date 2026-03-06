---
status: complete
priority: p3
issue_id: "003"
bead: iv-4qpc5
tags: [interwatch, drift-detection, architecture]
dependencies: ["001", "002"]
---

# interwatch: cross-document consistency checking

## Problem Statement

Interwatch evaluates each watchable in isolation. When the vision says "P0: iv-wie5i, iv-t712t" and the roadmap's Now section lists a different set, nobody catches it. Cross-doc consistency requires reading multiple docs and comparing claims — architecturally harder than single-doc signals.

## Proposed Solutions

**Option A: Post-scan cross-correlation pass**
- After all watchables are scanned, run a second pass comparing related docs
- Define "consistency groups" in watchables.yaml (e.g., vision + roadmap)
- Compare bead ID sets, count claims, priority lists across group members
- Pro: Clean separation. Con: New concept in the scan pipeline.

**Option B: Sibling-aware signal type**
- New signal that takes a `sibling_path` parameter
- Reads both the watched doc and its sibling, compares key claims
- Pro: Fits existing signal architecture. Con: Signals currently don't read other docs.

**Option C: Audit-level check**
- Add cross-doc consistency to interwatch-audit.py (the expensive correctness checker)
- Ground truth gatherer reads all related docs, agent validates consistency
- Pro: Fits audit's "expensive correctness" mandate. Con: Won't run on every scan.

## Acceptance Criteria

- [x] Design decision on approach (A/B/C) — Option C (audit-level) approved
- [x] Implementation of chosen approach
- [x] Detects P0 list mismatch between vision and roadmap
- [x] Detects count claim mismatches across related docs
- [x] Test coverage for cross-doc scenarios (smoke tested against Demarch)

## Work Log

### 2026-03-06 - Created

**By:** Claude Code

**Actions:**
- Created bead iv-4qpc5 and this todo from drift gap analysis (iv-ey5wb retrospective)
- Depends on 001 and 002 — those signals inform what cross-doc checks are valuable

### 2026-03-06 - Implemented

**By:** Claude Code

**Actions:**
- Chose Option C (audit-level): added `gather_cross_doc_consistency()` to interwatch-audit.py
- Auto-discovers doc groups: vision+roadmap pairs via `docs/{module}-vision.md` + `docs/{module}-roadmap.md` naming
- Extracts bead ID sets, count claims (plain and bold markdown), and P0 bead lists from each doc
- Compares within groups: count mismatches + P0 set mismatches
- Feeds results into ground truth JSON so audit agent can flag cross-doc inconsistencies
- Updated audit prompt to reference `cross_doc_consistency` data explicitly
- Smoke tested: found 1 p0_set_mismatch (vision 4 P0s vs roadmap 22 Now items — expected asymmetry)
