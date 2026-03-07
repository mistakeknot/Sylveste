---
artifact_type: research
bead: iv-wie5i.2
stage: research
---

# Evaluation Plan: Discovery Ranking Precision and Source-Trust Calibration

**Bead:** iv-wie5i.2
**Date:** 2026-03-07
**Parent:** iv-wie5i (Discovery OS integration)

## Problem

Interject auto-creates beads from ambient scans across arXiv, GitHub, HackerNews, and other sources. The old pipeline created 130 P3 beads (all open, none acted on). The new kernel-integrated pipeline adds tier-gated creation (high=P2, medium=P4+pending_triage, low=kernel-only). Without evaluation, we can't distinguish signal from noise — the system might promote irrelevant items or suppress valuable ones.

The core question: **is automated discovery creating work worth doing, or elegant spam?**

## Current State

### What exists

| Component | Status | Data |
|-----------|--------|------|
| Scoring engine | Implemented | Cosine similarity + source weight + keyword boost + recency + gap bonus |
| Tier thresholds | Hardcoded defaults | high >= 0.8, medium >= 0.5, low >= 0.2, discard < 0.2 |
| Adaptive thresholds | Implemented | `adapt_thresholds()` adjusts +/- 0.02 based on promotion rate |
| Source weight learning | Implemented | `update_source_weights_from_feedback()` adjusts per-source multiplier |
| Profile learning | Implemented | `learn_promotion()` / `learn_dismissal()` shift profile vector |
| Kernel records | Wired (F1) | `ic discovery submit` for all tiers |
| Kernel promotion | Wired (F3) | `ic discovery promote` links bead to kernel record |
| Feedback signals | Schema exists | `feedback_signals` table, `FeedbackCollector` class |
| Dedup | Source+source_id unique | SQLite constraint + kernel dedup |
| Production data | **Empty** | 0 discoveries, 0 promotions, 0 scans in current DB |
| Legacy beads | 130 open | All P3, `[interject]` prefix, created by old pipeline |

### What's missing

1. **No ground truth.** No labeled dataset of "this discovery was valuable" vs "this was noise."
2. **No conversion tracking.** We don't know which promoted discoveries led to shipped code.
3. **No precision/recall measurement.** Thresholds are tuned by heuristic, not data.
4. **No dedupe quality metrics.** We assume source+source_id dedup works; untested cross-source.
5. **No threshold calibration feedback loop.** `adapt_thresholds()` exists but needs a target.

## Evaluation Framework

### E1: Gold-Set Sampling

**Purpose:** Create labeled ground truth for precision/recall measurement.

**Method:**
1. After the next 3 scan cycles (accumulating ~100-300 discoveries), sample 50 items stratified by tier:
   - 15 high-tier, 15 medium-tier, 10 low-tier, 10 discard
2. Present each to a human reviewer with: title, source, URL, summary, score, tier
3. Reviewer labels each: `relevant` (would act on), `maybe` (worth knowing), `noise` (ignore)
4. Store labels in a new `gold_labels` table:
   ```sql
   CREATE TABLE gold_labels (
       discovery_id TEXT PRIMARY KEY REFERENCES discoveries(id),
       label TEXT NOT NULL CHECK (label IN ('relevant', 'maybe', 'noise')),
       reviewer TEXT NOT NULL,
       labeled_at TEXT NOT NULL DEFAULT (datetime('now')),
       notes TEXT
   );
   ```

**Frequency:** Re-sample every 500 new discoveries (or monthly, whichever comes first). Each round refreshes ~20% of the gold set to track drift.

**Automation:** Add `/interject:eval-label` skill that presents batches of 10 items for labeling (similar to `/interject:triage` but writes to `gold_labels` instead of closing beads).

### E2: Precision and Recall Metrics

**Definitions (relative to gold labels):**

| Metric | Formula | Target |
|--------|---------|--------|
| **Precision@high** | `relevant` in high-tier / total high-tier | >= 0.7 |
| **Precision@medium** | (`relevant` + `maybe`) in medium-tier / total medium-tier | >= 0.5 |
| **Noise rate** | `noise` in (high + medium) / total (high + medium) | <= 0.3 |
| **Recall** | `relevant` items in (high + medium) / all `relevant` items across all tiers | >= 0.8 |
| **False suppress** | `relevant` items in low + discard / all `relevant` items | <= 0.1 |

**Why these targets:**
- Precision@high >= 0.7: At least 7 out of 10 auto-created P2 beads should be worth pursuing. Below this, the backlog fills with noise.
- Recall >= 0.8: We'd rather over-surface than miss valuable items. Medium-tier (pending_triage) provides a safety net for borderline items.
- False suppress <= 0.1: Critical. If good items are being discarded, the whole pipeline is worse than no pipeline.

**Computation:**
```python
def compute_metrics(gold_labels: list[dict]) -> dict:
    high = [g for g in gold_labels if g["tier"] == "high"]
    medium = [g for g in gold_labels if g["tier"] == "medium"]
    low_discard = [g for g in gold_labels if g["tier"] in ("low", "discard")]

    precision_high = sum(1 for g in high if g["label"] == "relevant") / max(len(high), 1)
    precision_medium = sum(1 for g in medium if g["label"] in ("relevant", "maybe")) / max(len(medium), 1)

    all_relevant = sum(1 for g in gold_labels if g["label"] == "relevant")
    surfaced_relevant = sum(1 for g in high + medium if g["label"] == "relevant")
    recall = surfaced_relevant / max(all_relevant, 1)

    false_suppress = sum(1 for g in low_discard if g["label"] == "relevant") / max(all_relevant, 1)

    noise_surfaced = sum(1 for g in high + medium if g["label"] == "noise")
    noise_rate = noise_surfaced / max(len(high) + len(medium), 1)

    return {
        "precision_high": precision_high,
        "precision_medium": precision_medium,
        "noise_rate": noise_rate,
        "recall": recall,
        "false_suppress": false_suppress,
        "n_gold": len(gold_labels),
    }
```

### E3: Conversion Tracking (Discovery-to-Ship)

**Purpose:** Measure which promoted discoveries lead to actual shipped work.

**Pipeline:**
```
discovery created → bead created → bead claimed → bead closed → code shipped
         (submit)        (promote)      (in_progress)    (close)       (commit)
```

**Signals (already available):**
- `promotions` table: discovery_id → bead_id, promoted_at
- `feedback_signals` table: bead lifecycle events (bead_claimed, bead_closed, bead_shipped)
- `FeedbackCollector.scan_bead_updates()`: already scans bd for bead status changes

**New metric: conversion funnel**
```sql
-- Per-source conversion rates
SELECT
    d.source,
    COUNT(DISTINCT p.discovery_id) as promoted,
    COUNT(DISTINCT CASE WHEN f.signal_type = 'bead_claimed' THEN p.discovery_id END) as claimed,
    COUNT(DISTINCT CASE WHEN f.signal_type = 'bead_closed' THEN p.discovery_id END) as closed,
    COUNT(DISTINCT CASE WHEN f.signal_type = 'bead_shipped' THEN p.discovery_id END) as shipped
FROM promotions p
JOIN discoveries d ON d.id = p.discovery_id
LEFT JOIN feedback_signals f ON f.discovery_id = p.discovery_id
GROUP BY d.source;
```

**Target conversion rates:**
| Stage | Rate | Interpretation |
|-------|------|---------------|
| promoted → claimed | >= 0.3 | At least 30% of created beads get picked up |
| claimed → closed | >= 0.6 | Once someone looks, most are worth finishing |
| promoted → shipped | >= 0.15 | End-to-end: 15% of discoveries become code |

Rates below these suggest the scoring engine is promoting noise.

### E4: Source Trust Calibration

**Current mechanism:** `update_source_weights_from_feedback()` adjusts per-source multiplier (0.3 to 2.0) based on conversion rates. Baseline is 0.3 (30% of promoted items ship).

**Evaluation criteria:**

1. **Weight convergence:** After 100+ promotions per source, weights should stabilize (delta < 0.01 per cycle). If weights oscillate, the learning rate (0.1) is too high.

2. **Rank correlation:** Sort sources by weight. Sort sources by conversion rate. Compute Spearman correlation. Target >= 0.7 (weights track actual value).

3. **Cold-start handling:** New sources start at 1.0 (neutral). Track how many discoveries are needed before the weight meaningfully diverges from 1.0. If >50 discoveries per source needed, the learning rate is too conservative for bootstrapping.

4. **Floor/ceiling effects:** If a source consistently hits the floor (0.3) or ceiling (2.0), it's saturated. Consider widening the range or using a log scale.

**Recommended change:** Log source weights to a new table for auditing:
```sql
CREATE TABLE source_weight_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    weight REAL NOT NULL,
    promotion_count INTEGER NOT NULL,
    conversion_rate REAL,
    logged_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Insert a row after each `update_source_weights_from_feedback()` call. This provides the time series needed for convergence analysis.

### E5: Dedup Quality

**Current mechanism:** `UNIQUE(source, source_id)` in SQLite + kernel dedup in `ic discovery submit`.

**Known gaps:**
1. **Cross-source duplicates.** The same paper/repo can appear on arXiv AND GitHub AND HackerNews with different source_ids. No cross-source dedup exists.
2. **Near-duplicates.** Different versions of the same paper, forks of the same repo, or blog posts covering the same HN story.

**Evaluation method:**

1. **Exact cross-source dedup check:**
   ```python
   # After accumulating 200+ discoveries
   # Group by normalized URL (strip tracking params, protocol, www)
   # Any URL appearing in >1 source = missed cross-source dedup
   from urllib.parse import urlparse

   def normalize_url(url: str) -> str:
       parsed = urlparse(url)
       return f"{parsed.netloc.replace('www.','')}{parsed.path.rstrip('/')}"
   ```

2. **Near-duplicate check via embeddings:**
   ```python
   # Pairwise cosine similarity on all discovery embeddings
   # Any pair with similarity > 0.95 AND different source_ids = near-duplicate
   # Expected: <5% near-duplicate rate
   ```

3. **Dedup rate metric:**
   ```
   dedup_rate = duplicates_found / total_discoveries
   target: < 0.05 (5%)
   ```

**Recommended fix (if dedup rate > 5%):**
Add URL-based cross-source dedup check in `scanner.py` before `db.insert_discovery()`:
```python
normalized = normalize_url(raw.url)
if self.db.find_by_normalized_url(normalized):
    continue  # Cross-source duplicate
```

### E6: Threshold Tuning Protocol

**Current mechanism:** `adapt_thresholds()` adjusts +/- 0.02 based on overall promotion rate.

**Problems with current approach:**
1. Uses overall promotion rate (includes human-initiated promotions from triage)
2. Only adjusts in one direction per cycle — can't converge if rate oscillates around target
3. No target rate is defined — it moves thresholds based on arbitrary 0.1/0.3 bounds

**Recommended protocol:**

1. **Define target tier distribution:**
   - High: 5-15% of scored discoveries
   - Medium: 15-30% of scored discoveries
   - Low: 30-50% of scored discoveries
   - Discard: 20-40% of scored discoveries

2. **Calibrate from gold-set:**
   After E1/E2 produce precision/recall metrics:
   - If precision@high < 0.7: raise high_threshold by 0.05
   - If recall < 0.8: lower medium_threshold by 0.05
   - If false_suppress > 0.1: lower low_threshold by 0.05
   - If noise_rate > 0.3: raise both high and medium thresholds by 0.03

3. **Bounded grid search:**
   After 500+ labeled discoveries, run offline:
   ```python
   best_f1 = 0
   for high_t in np.arange(0.6, 0.95, 0.05):
       for med_t in np.arange(0.3, high_t, 0.05):
           precision, recall = simulate_tiers(gold_labels, high_t, med_t)
           f1 = 2 * precision * recall / (precision + recall + 1e-9)
           if f1 > best_f1:
               best_thresholds = (high_t, med_t)
   ```

4. **Guardrails:** Never auto-adjust thresholds by more than 0.1 in a single cycle. Log all adjustments.

## Implementation Sequence

| Phase | What | When | Depends on |
|-------|------|------|-----------|
| **Bootstrap** | Run 3 scan cycles to populate discovery DB | Now | Scan sources configured |
| **E1** | Gold-set labeling (50 items) | After 100+ discoveries | Bootstrap |
| **E2** | Precision/recall computation | After E1 | Gold labels |
| **E6** | First threshold calibration | After E2 | Precision/recall metrics |
| **E3** | Conversion funnel tracking | Ongoing (30+ days) | Beads created by new pipeline |
| **E4** | Source trust audit | After 100+ promotions | Conversion data |
| **E5** | Dedup quality check | After 200+ discoveries | Discovery embeddings |

### Immediate Actions (can do now)

1. **Add `gold_labels` table** to db.py schema (E1)
2. **Add `source_weight_log` table** to db.py schema (E4)
3. **Create `/interject:eval-label` skill** for gold-set labeling (E1)
4. **Add conversion funnel query** to feedback.py (E3)
5. **Run first scan** to start populating the discovery DB (Bootstrap)

### Deferred (need data first)

- Threshold grid search (E6) — needs 500+ labeled items
- Source trust convergence analysis (E4) — needs 100+ promotions per source
- Near-duplicate embedding analysis (E5) — needs 200+ embeddings
- Spearman rank correlation for source weights (E4) — needs weight log history

## Success Criteria for This Research Task

This evaluation plan is complete when:
- [x] Metrics are defined with concrete targets (E2)
- [x] Gold-set sampling methodology is specified (E1)
- [x] Conversion funnel is designed (E3)
- [x] Source trust calibration criteria are documented (E4)
- [x] Dedup quality measurement is specified (E5)
- [x] Threshold tuning protocol replaces ad-hoc `adapt_thresholds()` (E6)
- [x] Implementation sequence is ordered with dependencies
- [x] Schema changes are identified (gold_labels, source_weight_log)

## Open Questions

1. **Gold-set reviewer:** Who labels? Single reviewer (owner) introduces bias. Two reviewers with inter-rater agreement would be better but costly. **Recommendation:** Single reviewer for bootstrap, add second reviewer if precision metrics are borderline.

2. **Decay interaction:** Score decay (`apply_decay()`) reduces scores over time. Should gold-set labels reflect the score at time of labeling, or the original score? **Recommendation:** Label at original score — decay is a separate mechanism from relevance.

3. **Legacy bead cleanup:** 130 old P3 interject beads exist. Run `backlog-sweep.sh --apply` before or after first eval? **Recommendation:** Before. Clean baseline prevents old noise from confusing conversion tracking.
