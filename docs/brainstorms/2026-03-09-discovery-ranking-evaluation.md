---
artifact_type: brainstorm
bead: iv-wie5i.2
stage: discover
---

# Discovery Ranking Precision and Source-Trust Calibration

**Date:** 2026-03-09
**Bead:** iv-wie5i.2 (P1 research, child of iv-wie5i)
**Status:** Research complete
**Depends on:** Interject discovery pipeline (engine.py, db.py, outputs.py, feedback.py)

## Executive Summary

Interject's scoring pipeline is 70% embedding-based (cosine similarity to learned profile vector) with 30% learned adaptation (source weights, recency, gap bonus). The current thresholds (high=0.8, medium=0.5, low=0.2) were set by intuition. This document defines how to evaluate whether those thresholds are correct, whether the ranking is precise enough for automated backlog creation, and how source trust should adapt.

## Current Pipeline (Reference)

```
Source Adapters → Raw Discoveries → Embedding → Score = cosine_sim * source_weight * recency + gap_bonus
                                                   ↓
                                          Tier: high (≥0.8) → P2 bead + brainstorm
                                                medium (0.5-0.8) → P4 bead
                                                low (0.2-0.5) → kernel only
                                                discard (<0.2) → dropped
```

Feedback loop: promote/dismiss → profile vector EMA update (0.9/0.1) + source weight ±0.05.

## Evaluation Plan

### E1: Gold-Set Sampling

**Goal:** Build a labeled dataset of discoveries to measure scoring precision.

**Method:**
1. Export all discoveries with `status IN ('promoted', 'dismissed', 'decayed', 'new')` — at least 100 items needed for statistical significance
2. For each, record: `relevance_score`, `confidence_tier`, `source`, `status`, `discovered_at`
3. Label ground truth:
   - `promoted` + `bead_shipped` feedback → **true positive** (relevant AND valuable)
   - `promoted` + no shipped signal → **true positive, unconfirmed** (relevant but unproven)
   - `dismissed` → **true negative** (irrelevant)
   - `decayed` → **ambiguous** (never reviewed — exclude from precision, include in recall)
   - `new` → **unlabeled** (use for threshold calibration only)

**Sampling strategy:**
- Stratified by source (ensure each adapter has ≥10 labeled items)
- Stratified by tier (ensure each tier has ≥15 labeled items)
- Over-sample from the medium tier (0.5-0.8) — this is where threshold precision matters most

**Cold-start handling:** If <100 labeled items exist, run `/interject:inbox` review sessions to build the gold set. Target: 20 promote + 20 dismiss minimum before evaluating.

### E2: Precision and Recall Metrics

**Definitions aligned to the pipeline:**

| Metric | Formula | What it measures |
|--------|---------|------------------|
| **Tier precision** | `promoted_in_tier / total_in_tier` | Are high-tier items actually promoted? |
| **Tier recall** | `promoted_in_tier / total_promoted` | Do promoted items land in the right tier? |
| **Shipped rate** | `shipped / promoted` per source | Downstream value — did the bead lead to work? |
| **False positive rate** | `dismissed / (promoted + dismissed)` | User satisfaction with ranking |
| **Decay coverage** | `decayed / (decayed + dismissed)` | Does natural decay handle cleanup? |
| **Score calibration** | `mean(score | promoted) - mean(score | dismissed)` | Score separation between good/bad |

**Targets:**
- High-tier precision ≥ 70% (7 of 10 high-tier items should be promotable)
- Medium-tier false positive rate ≤ 50% (half or fewer should be dismissed)
- Score separation ≥ 0.3 (promoted items should average 0.3 higher than dismissed)
- Shipped rate ≥ 20% overall (1 in 5 promoted items leads to completed work)

**Diagnostic queries (run against interject.db):**

```sql
-- Tier precision: what % of high-tier items were promoted?
SELECT confidence_tier,
       COUNT(*) AS total,
       SUM(CASE WHEN status = 'promoted' THEN 1 ELSE 0 END) AS promoted,
       ROUND(100.0 * SUM(CASE WHEN status = 'promoted' THEN 1 ELSE 0 END) / COUNT(*), 1) AS precision_pct
FROM discoveries
WHERE status IN ('promoted', 'dismissed')
GROUP BY confidence_tier;

-- Score separation
SELECT status,
       ROUND(AVG(relevance_score), 3) AS avg_score,
       ROUND(MIN(relevance_score), 3) AS min_score,
       ROUND(MAX(relevance_score), 3) AS max_score,
       COUNT(*) AS n
FROM discoveries
WHERE status IN ('promoted', 'dismissed')
GROUP BY status;

-- Shipped rate per source
SELECT d.source,
       COUNT(DISTINCT p.id) AS promoted,
       COUNT(DISTINCT CASE WHEN f.signal_type = 'bead_shipped' THEN f.id END) AS shipped,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN f.signal_type = 'bead_shipped' THEN f.id END) /
             NULLIF(COUNT(DISTINCT p.id), 0), 1) AS ship_pct
FROM promotions p
JOIN discoveries d ON d.id = p.discovery_id
LEFT JOIN feedback_signals f ON f.discovery_id = p.discovery_id AND f.signal_type = 'bead_shipped'
GROUP BY d.source;

-- Decay effectiveness
SELECT COUNT(CASE WHEN status = 'decayed' THEN 1 END) AS decayed,
       COUNT(CASE WHEN status = 'dismissed' THEN 1 END) AS dismissed,
       ROUND(100.0 * COUNT(CASE WHEN status = 'decayed' THEN 1 END) /
             NULLIF(COUNT(CASE WHEN status IN ('decayed', 'dismissed') THEN 1 END), 0), 1) AS decay_coverage_pct
FROM discoveries;
```

### E3: Source-Trust Adjustment Rules

**Current mechanism:** Source weights adapt via `update_source_weights_from_feedback()`:
- `new_weight = current + 0.1 * (conversion_rate - 0.3)`, clamped [0.3, 2.0]
- Requires ≥3 promotions per source to trigger

**Evaluation:**
1. Query current source weights: `SELECT source_weights FROM interest_profile WHERE id = 1`
2. Compare to actual shipped rates per source (E2 query above)
3. Check: do sources with higher shipped rates have higher weights?

**Recommended rules (formalize what's implicit):**

| Condition | Action | Rationale |
|-----------|--------|-----------|
| Source has 0 promotions after 50 scans | Reduce weight to 0.5 | Source isn't producing relevant content |
| Source has ≥5 promotions with 0 shipped | Reduce weight by 0.1 | Promotes but doesn't deliver value |
| Source has ≥3 shipped with ≥40% ship rate | Increase weight by 0.1 | High-value source |
| Source produces >50% of dismissed items | Cap weight at 1.0 | Noisy source |
| Source weight hits floor (0.3) for 30 days | Disable source scan | Save API calls |

**New rule — source probation:** If a source's false positive rate exceeds 70% over its last 20 items, temporarily raise its minimum score threshold by 0.1 (effectively requiring higher quality from that source). Re-evaluate after next 10 items.

### E4: Deduplication Quality

**Current gaps:**
1. **Cross-source deduplication is missing.** The same paper/tool can appear from arXiv, HN, and GitHub with different `source_id` values. The DB constraint `UNIQUE(source, source_id)` only prevents within-source dupes.
2. **Title-only matching is fragile.** Titles vary across sources ("GPT-5 paper" vs "Scaling Laws for..." vs the arxiv ID).

**Evaluation queries:**

```sql
-- Find potential cross-source duplicates (title similarity)
SELECT a.id, a.source, a.title, b.id, b.source, b.title
FROM discoveries a
JOIN discoveries b ON a.id < b.id
WHERE a.title = b.title
   OR (LENGTH(a.title) > 20 AND a.title LIKE '%' || SUBSTR(b.title, 1, 20) || '%');

-- Count items per URL (if URL field exists)
SELECT url, COUNT(*) AS cnt
FROM discoveries
WHERE url IS NOT NULL AND url != ''
GROUP BY url
HAVING cnt > 1;
```

**Recommended dedup strategy:**
1. **URL-based dedup** (high confidence): Before inserting, check if any existing discovery shares the same URL (after normalizing trailing slashes, query params, etc.)
2. **Embedding-based dedup** (medium confidence): If cosine similarity between new discovery embedding and any existing discovery > 0.95, flag as potential duplicate. Don't auto-reject — present in inbox with "possible duplicate of ij-xxx" annotation.
3. **Title fuzzy match** (low confidence, advisory): Levenshtein distance < 5 on lowercased titles. Advisory only — don't block insertion.

**Metrics:**
- `duplicate_clusters`: Count of discovery groups sharing URL or >0.95 embedding similarity
- `cross_source_duplicate_rate`: `duplicate_clusters / total_discoveries`
- Target: <5% cross-source duplicate rate after implementing URL dedup

### E5: Threshold Calibration

**Current thresholds:** high=0.8, medium=0.5, low=0.2

**Calibration method:**
1. Plot score distribution of promoted vs. dismissed items (histogram)
2. Find the score at which `P(promoted | score) = 0.5` — this is the natural medium/high boundary
3. Find the score at which `P(promoted | score) = 0.2` — this is the natural low/medium boundary
4. Compare to current thresholds

**Decision rules for threshold adjustment:**

| Finding | Action |
|---------|--------|
| High-tier has <50% precision | Lower high threshold (too permissive) |
| High-tier has >90% precision but <10 items | Lower high threshold (too restrictive) |
| Medium-tier has >40% promotion rate | It's producing good items — lower the high threshold to capture them |
| Low-tier has >20% promotion rate | Medium threshold is too high — lower it |
| Score separation < 0.2 | Scoring model is weak — investigate embedding quality |
| >30% of items cluster at score 0.45-0.55 | Model is uncertain — widen the medium band |

**Adaptive threshold algorithm evaluation:**
The existing `adapt_thresholds()` adjusts by ±0.02 when promotion rate drifts from 10-30%. This is sound but:
- **Too slow**: 0.02 per cycle means 25 cycles to move from 0.5 to 0.0 — effectively never reaches extremes
- **Only adjusts on promotion rate, not precision**: A source could have 25% promotion rate (in band) but 0% shipped rate (useless promotions)
- **Recommendation**: Add a secondary adaptation signal based on shipped rate. If `shipped_rate < 10%` for 20+ promotions, raise thresholds by 0.05 (the promotions are noise, not signal).

### E6: Recommended Thresholds for Automation Tiers

Based on the scoring architecture and risk analysis:

| Automation level | Score threshold | Action | Risk |
|-----------------|----------------|--------|------|
| **Full auto** (create bead, no review) | ≥ 0.85 | P2 bead + brainstorm doc | Low — only fires for strong matches |
| **Semi-auto** (create bead, flag for triage) | 0.55 - 0.85 | P4 bead + `pending_triage` label | Medium — human reviews before work starts |
| **Passive** (record, don't act) | 0.25 - 0.55 | Kernel event only | None — no bead noise |
| **Discard** | < 0.25 | Drop entirely | None |

These are deliberately more conservative than the current defaults (high=0.8, medium=0.5) because:
- Automated bead creation has a real cost (backlog noise, triage time)
- Better to miss a good discovery than to create 10 noisy beads
- The gap between "full auto" (0.85) and "semi-auto" (0.55) creates a review buffer

**Adjust after collecting data:** If the gold set (E1) shows that score=0.75 items are consistently promoted, lower full-auto to 0.75. Data trumps theory.

## Implementation Roadmap (Not In Scope)

These are follow-up beads, not part of this research:

1. **Build evaluation dashboard** — Run E2 queries, output report. Could be a `/interject:eval` skill.
2. **Implement URL-based cross-source dedup** — E4 recommendation. ~2hr task.
3. **Add embedding-based near-duplicate detection** — E4 recommendation. ~4hr task.
4. **Add shipped-rate adaptation signal** — E5 recommendation. Modify `adapt_thresholds()`. ~1hr task.
5. **Source probation** — E3 recommendation. ~2hr task.

## Open Questions

1. **How many labeled items exist today?** Need to query the live DB. If <50, the evaluation is premature — build the gold set first via inbox review sessions.

2. **Embedding model quality.** The pipeline uses nomic-embed-text-v1.5 (768d). If score separation is poor (E2), the fix might be a better embedding model rather than better thresholds. Worth benchmarking against a larger model if scores cluster around 0.5.

3. **Gap bonus magnitude.** The +0.3 gap bonus is massive relative to the [0, 1] score range. A mediocre discovery (0.5) with gap bonus (0.8) gets auto-promoted. Consider reducing to +0.15 or making it multiplicative (1.3x) instead of additive.
