---
status: complete
priority: p2
issue_id: "001"
bead: iv-reedh
tags: [interwatch, drift-detection, signals]
dependencies: []
---

# interwatch: bead-reference validation signal

## Problem Statement

Watched docs (vision, roadmap) contain bead ID references (iv-XXXXX) that go stale when beads are closed, deferred, or deleted. The existing `bead_closed` signal only counts total closes since last scan — it doesn't correlate with specific IDs mentioned in doc text. This was the #1 source of drift found in iv-ey5wb.

## Proposed Solutions

New signal type `bead_reference_stale` in `interwatch-scan.py`:
1. Scan doc text for `iv-[a-z0-9]+` patterns
2. For each match, run `bd show <id>` and check status
3. Count references to closed/deferred/missing beads
4. Return count (capped) as signal value

## Acceptance Criteria

- [x] New `bead_reference_stale` signal type in SIGNAL_EVALUATORS
- [x] Regex extraction of iv-XXXXX patterns from doc text
- [x] bd show check for each extracted ID (with caching via set dedup)
- [x] Signal fires when doc references closed/deferred/missing beads
- [x] Added to roadmap and vision signal templates in watchables.yaml
- [x] Weight: 3 (deterministic — the reference is provably stale)

## Work Log

### 2026-03-06 - Created

**By:** Claude Code

**Actions:**
- Created bead iv-reedh and this todo from drift gap analysis (iv-ey5wb retrospective)

### 2026-03-06 - Implemented

**By:** Claude Code

**Actions:**
- Added `eval_bead_reference_stale()` to `interwatch-scan.py` (scans for iv-[a-z0-9]+ patterns, checks via bd show, counts closed/deferred/missing)
- Registered in SIGNAL_EVALUATORS dict
- Added to deterministic signals list (produces Certain confidence)
- Added to roadmap and vision default watchables + signal templates in watchables.yaml
- Added to signals.md reference doc
- Smoke tested: found 5 stale refs in demarch-vision.md, 10 in demarch-roadmap.md
