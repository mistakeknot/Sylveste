---
bead: sylveste-rsj.4
title: "Brainstorm: Domain-general north star metric"
date: 2026-03-30
---

# Brainstorm: Domain-General North Star Metric

## Problem

Cost-per-landable-change ($2.93 baseline) is software-dev-specific. It assumes:
- Work units are "commits" or "merged PRs"
- Quality = "tests pass + review approved"
- Value = binary (landed/not-landed)

For document reviews, brainstorms, research sessions, and creative work, none of these apply. We need a metric that works across all work types.

## Candidates

### 1. Cost Per Verified Outcome (CPVO)

Generalizes "landable change" to any verified outcome:
- **Software:** merged PR (current baseline)
- **Document review:** synthesis with ≥2 confirmed findings
- **Research:** report with ≥3 sourced claims
- **Brainstorm:** PRD produced and approved

`CPVO = total_cost / count(verified_outcomes)`

**Pros:** Direct generalization of current metric. Easy to compute.
**Cons:** Binary (outcome exists or not). Doesn't measure quality of the outcome.

### 2. Superadditive Capability Score (SCS)

Measures whether multi-agent collaboration produces more than the sum of parts:
`SCS = quality_of_ensemble / sum(quality_of_individual_agents)`

Where quality comes from: convergence ratio, diversity of perspectives, reaction confirmation rate.

**Pros:** Measures the *value of collaboration*, not just output.
**Cons:** Requires a quality function per domain. Hard to compute for novel domains.

### 3. Diversity-Weighted Signal Quality (DWSQ)

From QDAIF: quality × diversity. High-quality homogeneous output scores lower than moderate-quality diverse output.

`DWSQ = mean_finding_quality * (1 + perspective_diversity_bonus)`

Where:
- `mean_finding_quality` = weighted average of finding severity (P0=1.0, P1=0.7, P2=0.3, P3=0.1)
- `perspective_diversity_bonus` = count(distinct_perspectives) / count(agents) from QDAIF diversity archive

**Pros:** Directly uses the infrastructure we just built (diversity archive + sycophancy scoring).
**Cons:** Only applies to multi-agent reviews. Single-agent work gets diversity=0.

### 4. Novelty Injection Rate (NIR)

Measures how much new information agents produce per token spent:
`NIR = count(novel_findings) / total_tokens * 1M`

Novel = not found by any other agent (unique). High NIR = agents are adding value, not repeating each other.

**Pros:** Token-efficient. Directly penalizes redundancy.
**Cons:** Rewards contrarianism. An agent that always disagrees has high NIR but may be wrong.

## Decision

**Ship CPVO as the primary metric** — it's the direct generalization of cost-per-landable-change and works immediately across all domains. Then add **DWSQ as a quality modifier** for multi-agent reviews, since we already have the diversity archive + sycophancy scoring infrastructure.

Formula: `CPVO` for reporting, `CPVO * DWSQ` for quality-adjusted cost efficiency.

SCS and NIR are future experiments (need more data to calibrate).

## Scoped Implementation

1. Define verified outcome types in `core/intercore/config/metrics.yaml` (new file)
2. Add `baseline-general` subcommand to `interverse/interstat/scripts/cost-query.sh`
3. Add DWSQ computation to synthesis output (intersynth already has the data)
