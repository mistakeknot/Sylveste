---
artifact_type: plan
bead: Sylveste-uboy
stage: planned
---
# Plan: Interflux Pipeline Hardening

**Bead:** Sylveste-uboy
**Scope:** 3 actionable tasks (uboy.1, uboy.5, uboy.6), 3 deferred (uboy.2-4)
**All files are in:** `interverse/interflux/` (own git repo)

## Task 1: Sync SKILL-compact.md (Sylveste-uboy.1, P1)

**File:** `skills/flux-drive/SKILL-compact.md`

### 1a: Fix domain boost (line 142)
```
Before: "domain_boost: +2 if agent has >=3 injection criteria for detected domain, +1 for 1-2"
After:  "domain_boost: +2 if agent has injection criteria section in domain profile, +0 otherwise (binary)"
```

### 1b: Remove generated_slots from ceiling (line 149-150)
```
Before:
total = 4(base) + scope(file:0, small-diff:1, large-diff:2, repo:3) + domain(0:0, 1:1, 2+:2) + generated(flux-gen:2, none:0)
hard_max = 12

After:
total = 4(base) + scope(file:0, small-diff:1, large-diff:2, repo:3) + domain(0:0, 1:1, 2+:2)
hard_max = 10
```

### 1c: Fix selection rule (line 144)
```
Before: "Selection: all >=3 included, >=2 if slots remain, >=1 only for thin sections"
After:  "Selection: base_score determines inclusion (>=3 always, >=2 if slots, >=1 for thin). Bonuses affect ranking/staging only."
```

### 1d: Add dedup clarification (after line 144)
Add after selection rule:
```
- Deduplication: exact name match → prefer Project Agent. Partial domain overlap → keep both (Plugin in Stage 2).
```

### 1e: Add incremental expansion reference (line 278, between 2.2a.5 and 2.2b-c)
```
Before: "- Step 2.2b-c: Staged expansion decision"
After:
- Step 2.2a.6: Incremental expansion — speculative Stage 2 launch (max 2) as Stage 1 results arrive
- Step 2.2b-c: Staged expansion decision (excludes already-launched speculative agents)
```

### 1f: Fix polling reference
The compact file doesn't explicitly mention polling interval, but launch.md does. No change needed in compact — it references `phases/launch.md` for details.

## Task 2: Fix scoring-examples.md (Sylveste-uboy.5, P2)

**File:** `skills/flux-drive/references/scoring-examples.md`

### 2a: Fix domain boost values to binary
All `+1 (N items)` entries become `+2 (has criteria)`. This changes totals:

**Example 1 (Go API):**
- fd-safety: +1→+2, total 5→6
- fd-quality: +1→+2, total 4→5
- fd-performance: +1→+2, total 3→4

**Example 2 (Python CLI):**
- fd-quality: +1→+2, total 5→6
- fd-architecture: +1→+2, total 3→4

**Example 3 (PRD onboarding):**
- fd-safety: +1→+2, total 3→4

**Example 4 (Game project):**
- Remove `+ 2 (flux-gen)` from ceiling: 7→5 slots. Stage 1: 2 (not 3).
- fd-architecture: +1→+2, total 5→6
- fd-performance: +1→+2, total 4→5
- fd-quality: +1→+2, total 4→5
- fd-safety: +1→+2, total 3→4
- Stage assignment changes with 5 slots.

## Task 3: Validate incremental expansion (Sylveste-uboy.6, P2)

Not a file edit — run `/interflux:flux-drive` on a real 400+ line doc and verify Step 2.2a.6 fires. Defer to a separate session (requires interactive flux-drive run).

## Deferred

- **uboy.2** (JSONL tokens): Needs interstat integration + data accumulation. Create when 10+ runs exist.
- **uboy.3** (Dropout recall): Blocked on uboy.2.
- **uboy.4** (inotifywait): Pure optimization, lowest priority.

## Build Sequence

1. Task 1 (SKILL-compact.md) — ~10 min
2. Task 2 (scoring-examples.md) — ~10 min
3. Commit + publish
4. Task 3 deferred to separate interactive session

## Verification

- [ ] SKILL-compact.md domain boost is binary (+0/+2)
- [ ] SKILL-compact.md ceiling has no generated_slots; hard_max = 10
- [ ] SKILL-compact.md selection mentions base_score for inclusion
- [ ] SKILL-compact.md has dedup rule (exact match vs partial overlap)
- [ ] SKILL-compact.md references incremental expansion step
- [ ] scoring-examples.md all boost values are +2 (has criteria) not +1
- [ ] scoring-examples.md game example has no generated_slots, ceiling = 5
- [ ] Both files consistent with SKILL.md and scoring.md
