---
bead: sylveste-q4o
date: 2026-03-28
type: plan
complexity: C3
---

# Plan: Per-Model Cost Attribution for Interstat

## Problem

Shadow logging writes `local_cost_usd = 0.0` and uses a hardcoded default
cloud model. Sprint cost summaries can't answer "how much would this have
cost per model tier?" or "what's the ROI of local inference?"

## Tasks

### Task 1: Cloud model tier mapping (shadow_log.py)

Add a model-tier mapping that infers which cloud model would handle a request
based on the local model's capability tier:

| Local Model Size | Cloud Equivalent | Rationale |
|-----------------|-----------------|-----------|
| < 15B params | haiku | Simple tasks |
| 15-100B params | sonnet | Medium tasks |
| > 100B params | opus | Complex tasks |

Implementation: `infer_cloud_model(local_model: str) -> str` function that
pattern-matches model names (e.g., "9b" → haiku, "35b" → sonnet, "397b" → opus).
Used as default when caller doesn't specify `cloud_model`.

### Task 2: Load pricing from costs.yaml (shadow_log.py)

Replace hardcoded `_PRICING` dict with a loader that reads from
`core/intercore/config/costs.yaml` (with hardcoded fallback).

### Task 3: Per-model breakdown query (cost-query.sh)

Add `shadow-by-model` mode to cost-query.sh that groups shadow savings
by local_model and cloud_model:

```sql
SELECT local_model, cloud_model,
       COUNT(*) as decisions,
       SUM(hypothetical_savings_usd) as savings_usd,
       SUM(local_tokens) as local_tokens,
       SUM(cloud_tokens_est) as cloud_tokens_est
FROM local_routing_shadow
GROUP BY local_model, cloud_model
```

### Task 4: ROI summary query (cost-query.sh)

Add `shadow-roi` mode that computes overall ROI:

```
total_cloud_cost / total_local_cost = ROI multiplier
(where local_cost accounts for amortized hardware cost)
```

For now, local cost stays at $0 (hardware is sunk cost), so ROI = infinity.
Add a `--local-rate` flag for future use when we want to model amortized cost.

### Task 5: Tests

- Test `infer_cloud_model` mapping
- Test pricing loader with and without costs.yaml
- Test per-model breakdown query
- Update existing shadow log tests for new mapping

## File Change Summary

| File | Change |
|------|--------|
| `server/shadow_log.py` | Add infer_cloud_model, costs.yaml loader |
| `interstat/scripts/cost-query.sh` | Add shadow-by-model and shadow-roi modes |
| `tests/test_shadow_log.py` | Add tests for model mapping and pricing |
