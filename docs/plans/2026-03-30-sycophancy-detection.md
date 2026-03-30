---
bead: sylveste-rsj.6
title: "Plan: Runtime sycophancy detection in synthesis"
date: 2026-03-30
type: plan
---

# Plan: Runtime Sycophancy Detection

## Summary

Add sycophancy scoring to the synthesis agent. Computes per-agent agreement rate, independence rate, and novel finding rate from reaction round data. Reports in synthesis.md and findings.json. ~40 lines added to synthesize-review.md, ~10 lines to reaction.yaml.

## Tasks

### Task 1: Add sycophancy config to reaction.yaml
**File:** `interverse/interflux/config/flux-drive/reaction.yaml`
**Action:** Append sycophancy_detection section
**Description:**
```yaml
sycophancy_detection:
  enabled: true
  agreement_threshold: 0.8
  independence_threshold: 0.3
  contrarian_threshold: 0.2
```
**Depends on:** Nothing

### Task 2: Add sycophancy scoring to synthesis agent
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Add Step 3.8 after Step 3.7 (reaction ingestion)
**Description:**
1. After parsing all `.reactions.md` files in Step 3.7, compute per-agent metrics:
   - `agreement_rate = count(stance in [agree, partially-agree]) / total_reactions`
   - `independent_rate = count(independent_coverage == yes) / total_reactions`
   - `novel_finding_rate = count(reactive_additions) / total_reactions`
2. Flag agents:
   - `sycophancy`: agreement_rate > threshold AND independent_rate < independence_threshold
   - `contrarian`: agreement_rate < contrarian_threshold
3. Compute `overall_conformity = mean(agreement_rate) across all reacting agents`
4. If `overall_conformity > 0.9`, add warning: "High overall conformity — consider adding adversarial agents or increasing agent diversity"
**Depends on:** Nothing (extends existing Step 3.7 data)

### Task 3: Add Sycophancy Analysis output section
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Add output section to Step 8 (Write outputs)
**Description:**
1. After "### Reaction Analysis" section, add "### Sycophancy Analysis" with per-agent table:
   ```
   | Agent | Reactions | Agreement | Independence | Novel | Flag |
   ```
2. Add `sycophancy_analysis` object to findings.json schema
3. If no reactions exist (reaction round was skipped/disabled), omit this section entirely
**Depends on:** Task 2

### Task 4: Add sycophancy flags to return value
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Extend the compact return value
**Description:** Add line to return value:
```
Sycophancy: [N flagged agents] | Conformity: [overall_conformity]
```
Only include if reaction data exists.
**Depends on:** Task 2

## Execution Order

Tasks 1 and 2 are independent — execute in parallel.
Task 3 depends on Task 2.
Task 4 depends on Task 2.

```
Parallel: [Task 1] [Task 2]
    ↓
Sequential: [Task 3] [Task 4]
```

## Testing

- Verify: synthesis with reaction data includes Sycophancy Analysis section
- Verify: agent with 100% agree + 0% independent gets flagged
- Verify: synthesis without reactions omits sycophancy section
- Verify: findings.json includes sycophancy_analysis object
- Verify: config toggle `sycophancy_detection.enabled: false` skips scoring
