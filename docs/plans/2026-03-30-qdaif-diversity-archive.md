---
bead: sylveste-rsj.5
title: "Plan: QDAIF diversity archive in synthesis"
date: 2026-03-30
type: plan
---

# Plan: Diverse Perspectives in Synthesis

## Summary

Add a "Diverse Perspectives" section to synthesis output that preserves distinct agent viewpoints as coherent mini-narratives alongside merged findings. ~50 lines added to synthesize-review.md.

## Tasks

### Task 1: Add Step 6.5 (Perspective Extraction) to synthesis agent
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Add new step between Step 6 (Deduplicate) and Step 7 (Categorize)
**Description:**
1. For each agent with NEEDS_ATTENTION verdict (from Step 4), read their Summary section
2. Build a per-agent mini-narrative: agent name + domain focus + 2-4 sentence summary of their unique framing
3. Compare narratives for distinctness: skip if agent's perspective is fully captured by the merged findings (all their key findings merged without unique framing)
4. Keep at most 3 most distinct perspectives, ranked by quality_score
5. Quality score formula:
   - Base: 0.5 (every agent starts here)
   - +0.2 if agent has confirmed findings (convergence > 1)
   - +0.2 if agent has high independence (from sycophancy scoring, independent_rate > 0.5)
   - +0.1 if agent has unique findings (findings not found by any other agent)
   - -0.2 if agent was flagged for sycophancy
**Depends on:** Nothing

### Task 2: Add "Diverse Perspectives" output section
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Add section to Step 8 (Write outputs) synthesis.md template
**Description:**
After "### Sycophancy Analysis" and before "### Conflicts", add:
```markdown
### Diverse Perspectives
[Top 2-3 distinct agent viewpoints as mini-narratives. Each includes agent name,
domain focus, and 2-4 sentence framing. Only include if perspectives differ
materially from the merged findings. Omit if fewer than 2 agents or all perspectives
are identical.]
```
**Depends on:** Task 1

### Task 3: Add "perspectives" to findings.json schema
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Extend findings.json schema
**Description:**
Add `perspectives` array to findings.json:
```json
"perspectives": [
  {"agent": "...", "domain": "...", "narrative": "...", "key_findings": [], "quality_score": 0.0}
]
```
**Depends on:** Task 1

## Execution Order

Task 1 first, then Tasks 2 and 3 in parallel.

```
[Task 1]
    ↓
Parallel: [Task 2] [Task 3]
```

## Testing

- Verify: synthesis with 3+ agents includes Diverse Perspectives section
- Verify: perspectives are distinct (not copies of merged findings)
- Verify: max 3 perspectives kept
- Verify: findings.json includes perspectives array
- Verify: agents with identical perspectives get deduplicated
- Verify: single-agent reviews omit the section
