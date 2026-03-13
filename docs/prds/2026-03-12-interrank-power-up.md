---
artifact_type: prd
bead: Demarch-fqb
stage: design
---

# PRD: Interrank Power-Up — Task-Based Model Recommendation

## Problem

Interrank can rank models by individual benchmarks and recommend benchmarks for a task, but it can't answer the most common question: "What model should I use for X?" Users must manually chain recommend_benchmarks → leaderboard → compare_models to reach a decision. There's also no cost-efficiency ranking, and benchmark metadata (contamination risk, freshness) is present in the schema but empty in the snapshot data.

## Solution

Add a `recommend_model` tool for end-to-end task-to-model recommendation, a `cost_leaderboard` tool for price-performance ranking, enrich benchmark metadata in the AgMoDB snapshot, and add pricing fields to the model schema with an ingestion pipeline.

## Features

### F1: `recommend_model` Tool
**What:** New MCP tool that accepts a task description and returns ranked model recommendations with per-model reasoning.

**Acceptance criteria:**
- [ ] Tool accepts `task` (required string), `budget` (optional: "low"/"medium"/"high"), `provider` (optional filter), `limit` (1-50, default 5)
- [ ] Internally uses `scoreBenchmarks` to find relevant benchmarks, then computes weighted model scores across those benchmarks
- [ ] Each result includes: slug, name, provider, weightedScore, confidence (fraction of relevant benchmarks with data), matchReason (human-readable explanation)
- [ ] Budget filter excludes models above the cost threshold using `blendedPricePerM` metric (initially; `inputPricePerMTok`/`outputPricePerMTok` when available)
- [ ] Models with fewer than 2 relevant benchmark scores are excluded (low confidence)
- [ ] BenchPress-predicted scores weighted at 0.7x vs observed scores
- [ ] Unit tests covering: coding task, chatbot task, task with budget constraint, task with no matching benchmarks

### F2: `cost_leaderboard` Tool
**What:** New MCP tool that ranks models by cost-efficiency (benchmark performance per dollar).

**Acceptance criteria:**
- [ ] Tool accepts `metricKey` (optional), `domain` (optional enum, same as domain_leaderboard), `costMetric` (default: "blendedPricePerM"), `provider` (optional), `includePredicted` (default: true), `limit` (1-200, default 20)
- [ ] Exactly one of `metricKey` or `domain` required (mutual exclusion validated)
- [ ] Efficiency ratio computed as: `benchmark_score / cost_value` (normalized so higher = better for all metrics)
- [ ] Response includes: rank, slug, name, provider, benchmarkScore, costValue, efficiencyRatio, predicted flag
- [ ] Models missing cost data excluded with `excludedCount` in response metadata
- [ ] Unit tests covering: domain-based efficiency, metric-based efficiency, missing cost data handling

### F3: Enriched Benchmark Metadata Surfacing
**What:** Surface existing but unpopulated benchmark metadata fields in `list_benchmarks` and `recommend_benchmarks` responses.

**Acceptance criteria:**
- [ ] `list_benchmarks` response includes `contaminationRisk`, `freshnessType`, `scoreInterpretation`, `metadataStatus` for each benchmark
- [ ] `recommend_benchmarks` response includes the same fields
- [ ] Fields that are null/undefined in snapshot rendered as `"unknown"` (not omitted)
- [ ] No schema changes needed in interrank (fields already in types.ts) — this is a response-shape change only
- [ ] Tests verify metadata fields present in tool responses

### F4: AgMoDB Pricing Schema + Ingestion
**What:** Add per-token pricing fields to AgMoDB model records and build an ingestion pipeline for major providers.

**Acceptance criteria:**
- [ ] AgMoDB model schema gains: `inputPricePerMTok` (number, nullable), `outputPricePerMTok` (number, nullable)
- [ ] Pricing data curated for major providers: OpenAI (GPT-4o, o3, o4-mini), Anthropic (Claude 4.5/4.6 family), Google (Gemini 2.5), Meta (Llama 4), Mistral, Cohere, xAI
- [ ] Snapshot export includes new pricing fields
- [ ] interrank snapshot types updated to include `inputPricePerMTok` and `outputPricePerMTok` on SnapshotModel
- [ ] `recommend_model` budget filter and `cost_leaderboard` prefer dedicated pricing over `blendedPricePerM` when available

### F5: AgMoDB Benchmark Metadata Enrichment
**What:** Fill empty benchmark metadata fields with curated data for all benchmarks in AgMoDB.

**Acceptance criteria:**
- [ ] All benchmarks have non-null `contaminationRisk` (low/medium/high/unknown)
- [ ] All benchmarks have non-null `freshnessType` (static/versioned/continuous)
- [ ] All benchmarks with known scoring have `scoreInterpretation` filled
- [ ] `metadataStatus` updated to reflect completeness
- [ ] Changes committed to AgMoDB repo and reflected in next snapshot

### F6: Snapshot CI Validation
**What:** CI check that validates the snapshot schema includes required fields and data quality thresholds.

**Acceptance criteria:**
- [ ] CI validates: pricing fields present in schema, benchmark metadata fields present
- [ ] Warning (not failure) if >20% of models missing pricing data
- [ ] Warning if >30% of benchmarks have metadataStatus="stub"
- [ ] Runs on snapshot generation in AgMoDB CI pipeline

## Non-goals

- **Real-time pricing API integration** — v1 uses curated data, not live API calls
- **User-configurable benchmark weights** — recommend_model uses automatic weights from task relevance scoring
- **Multi-model portfolio optimization** — "use model A for coding, model B for writing" is a future feature
- **Benchmark contamination detection** — we surface the risk level but don't detect it ourselves

## Dependencies

- AgMoDB repo (`mistakeknot/agmodb`) for F4, F5, F6
- Existing interrank snapshot infrastructure for F1, F2, F3
- `blendedPricePerM` metric already in snapshot (interim pricing for F1/F2 before F4 lands)

## Open Questions

1. **Budget tier thresholds** — what $/MTok ranges define low/medium/high? Proposal: low < $1, medium < $10, high = unlimited
2. **Benchmark weight normalization** — should task relevance scores be category-normalized? Leaning toward proportional (a coding task should weight coding benchmarks heavily)
3. **AgMoDB pricing ingestion frequency** — monthly manual update? Quarterly? On major model release?
