---
bead: sylveste-rsj.4
title: "Plan: Domain-general north star metric (CPVO + DWSQ)"
date: 2026-03-30
type: plan
---

# Plan: Domain-General North Star Metric

## Summary

Add CPVO (Cost Per Verified Outcome) as a domain-general metric alongside the existing cost-per-landable-change. Add DWSQ (Diversity-Weighted Signal Quality) as a quality modifier for multi-agent reviews. 3 files created/modified.

## Tasks

### Task 1: Create metrics config
**File:** `core/intercore/config/metrics.yaml` (new)
**Action:** Define verified outcome types and DWSQ formula
**Description:**
```yaml
north_star:
  primary: cpvo  # cost per verified outcome
  quality_modifier: dwsq  # diversity-weighted signal quality

verified_outcomes:
  software:
    definition: "Merged PR or committed change with passing tests"
    source: "git log + bd list --status=closed"
  review:
    definition: "Synthesis with ≥2 confirmed P0/P1 findings"
    source: "findings.json with convergence > 1"
  research:
    definition: "Report with ≥3 sourced claims"
    source: "interdeep compile_report output"
  brainstorm:
    definition: "PRD produced from brainstorm"
    source: "bd get-artifact brainstorm + bd get-artifact prd"
  document:
    definition: "Document generated or refreshed"
    source: "interpath artifact with drift score"

dwsq:
  finding_weights:
    P0: 1.0
    P1: 0.7
    P2: 0.3
    P3: 0.1
    IMP: 0.05
  diversity_bonus_max: 0.5  # cap at 50% bonus
```
**Depends on:** Nothing

### Task 2: Add baseline-general subcommand to cost-query.sh
**File:** `interverse/interstat/scripts/cost-query.sh`
**Action:** Add `baseline-general` mode
**Description:**
New mode that computes CPVO across all outcome types:
1. Count verified outcomes per type (query interstat DB + git log + beads)
2. Sum total cost from `cost-usd` mode
3. Compute CPVO = total_cost / total_verified_outcomes
4. Output JSON with per-type breakdown and overall CPVO
5. Falls back to software-only (existing baseline) if other outcome types have no data
**Depends on:** Task 1 (reads metrics.yaml for outcome definitions)

### Task 3: Add DWSQ to synthesis findings.json
**File:** `interverse/intersynth/agents/synthesize-review.md`
**Action:** Compute DWSQ in Step 6.5 and add to findings.json
**Description:**
After perspective extraction (Step 6.5), compute:
- `mean_finding_quality` = weighted avg of all P0-P3 findings using weights from metrics.yaml
- `perspective_diversity_bonus` = min(distinct_perspectives / total_agents, dwsq.diversity_bonus_max)
- `dwsq = mean_finding_quality * (1 + perspective_diversity_bonus)`
Add to findings.json: `"dwsq": {"score": 0.0, "mean_quality": 0.0, "diversity_bonus": 0.0}`
**Depends on:** Task 1 (reads finding_weights from metrics.yaml)

## Execution Order

Task 1 first (config), then Tasks 2 and 3 in parallel.

## Testing

- Verify: `cost-query.sh baseline-general` outputs valid JSON
- Verify: CPVO computes correctly for software outcomes (matches existing baseline)
- Verify: findings.json includes dwsq object after multi-agent review
- Verify: single-agent review has diversity_bonus = 0
