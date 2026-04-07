---
artifact_type: prd
bead: sylveste-uais
stage: design
---

# PRD: Progressive Discrimination Curriculum

## Problem

Auraken has 291 lenses but no systematic way to help users develop their own ability to recognize problem structure. Forge Mode calibration produced 454 contested lens pairs and 30 enriched distinguishing questions, but these are currently unused — neither routing lens selection nor training user discrimination. Users remain dependent on Auraken's selection rather than building independent pattern recognition.

## Solution

Operationalize Forge calibration findings as a progressive user-facing curriculum: present distinguishing questions as Socratic dialogue, track discrimination ability, graduate through difficulty tiers, and use a three-depth disclosure model (wax-and-gold) calibrated per user. Lens stacks become reference-frame inversions with explicit problem redefinition between phases.

## Features

### F1: Difficulty Ladder

**What:** Order the 30 enriched near-miss pairs by discrimination difficulty into easy/medium/hard tiers using Forge stress test resolution rates as signal.

**Acceptance criteria:**
- [ ] All 30 pairs assigned a difficulty tier (easy: RESOLVED in stress test with high-contrast definitions, medium: RESOLVED but requires nuanced reading, hard: PARTIAL in stress tests or lens-stack scenarios)
- [ ] Output JSON at `data/calibration/difficulty_ladder.json` with tier, pair, DQ, and ordering rationale
- [ ] Difficulty ordering validated: at least 3 pairs per tier
- [ ] Script to regenerate ladder when new stress test data arrives

### F2: Judicial Holdings Format

**What:** Restructure all 30 DQs from natural-language questions into a structured operative-condition / rationale / scope format that makes them durable and independently revisable.

**Acceptance criteria:**
- [ ] All 30 DQs restructured with three fields: `operative_condition` (when this DQ applies), `rationale` (why this distinction matters), `scope` (which lens to prefer given the answer)
- [ ] Updated `near_miss_forge_ready.json` with holdings-format DQs
- [ ] Each holding references the specific Forge stress test that validated it
- [ ] Holdings parseable by Auraken's lens selector at runtime

### F3: Conversation Integration Spec

**What:** Design how Auraken presents DQs in live conversations using the three-depth wax-and-gold model, including when to ask the user vs route silently, and how to handle wrong answers gracefully.

**Acceptance criteria:**
- [ ] Spec doc with concrete conversation examples at each depth (deep gold, shallow gold, wax)
- [ ] Decision tree: when to present DQ to user vs use internally for routing
- [ ] Graceful wrong-answer handling: how Auraken responds when user's DQ answer points to the less-appropriate lens
- [ ] Integration points with OODARC (DQ presentation maps to Orient phase)
- [ ] Spec reviewed against PHILOSOPHY.md principles (camera-not-engine, preserve-cognitive-struggle)

### F4: User Discrimination Tracker

**What:** Extend Auraken's cognitive profile to track which DQs a user can resolve independently, which they need help with, and when to advance difficulty tier.

**Acceptance criteria:**
- [ ] Profile schema addition: `discrimination_history` with per-DQ resolution records
- [ ] Advancement logic: user resolves N DQs at current tier → advance to next
- [ ] Regression detection: user suddenly fails DQs they previously resolved → investigate, don't demote
- [ ] Privacy: discrimination history follows same GDPR controls as existing profile
- [ ] Compensatory pattern detection: flag when user consistently avoids certain problem types

### F5: Lens Stack Transition Model

**What:** Implement reference-frame inversion for multi-lens sequences — make problem redefinition explicit between phases with annealing pauses.

**Acceptance criteria:**
- [ ] Stack orchestration: each phase outputs a problem redefinition, not just an analysis
- [ ] Explicit transition language: "Your answer just changed what this problem is about"
- [ ] Annealing support: configurable pause between phases (within-conversation or between-session)
- [ ] At least 3 named stack patterns documented (e.g., "Boundary Protocol": Approach/Avoid → Microboundaries → SBI)
- [ ] Stack transitions respect wax-and-gold depth (don't name lenses at deep-gold level)

## Non-goals

- **Automated lens library updates**: Forge findings inform the curriculum but don't auto-modify lens definitions. Lens library changes go through manual Forge Mode review.
- **Explicit testing UI**: No quizzes or flashcard-style DQ drills. Discrimination training happens organically within real conversations.
- **Multi-user curriculum**: Each user has their own difficulty ladder position. No shared progress or leaderboards.
- **External dataset pipeline expansion**: This PRD covers operationalizing existing Forge findings. New dataset acquisition (AITA, Reddit) is tracked in parent epic sylveste-2l1.

## Dependencies

- `apps/Auraken/data/calibration/near_miss_analysis.json` (30 enriched pairs)
- `apps/Auraken/data/calibration/near_miss_forge_ready.json` (DistinguishingFeature records)
- `apps/Auraken/data/calibration/forge_stress_test_log.jsonl` (16 stress tests)
- Auraken's existing lens selector (`src/auraken/lenses.py`)
- Auraken's cognitive profile system
- OODARC conversation model

## Open Questions

1. **Advancement threshold**: How many DQs must a user resolve at current tier before graduating? The sommelier parallel suggests 3-5 correct discriminations, but we need to validate.
2. **Silent vs presented DQ ratio**: What percentage of lens selections should present a DQ to the user vs route silently? Too many DQs feels like a quiz; too few loses the training effect.
3. **Near-miss composition**: Should F5 support deliberate co-application of near-miss pairs? Deferred pending more stress testing — tracked as open question, not a feature.
