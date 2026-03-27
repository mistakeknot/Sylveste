---
artifact_type: brainstorm
bead: Sylveste-fqb
stage: discover
---

# Interrank Power-Up: Task-Based Model Recommendation

**Bead:** Sylveste-fqb

## What We're Building

Three new capabilities for interrank, plus an AgMoDB enrichment pipeline:

### 1. `recommend_model` Tool (New)
Given a natural-language task description (e.g., "code review agent for Go"), return ranked model recommendations with reasoning. Workflow:
- Accept `task` (required), `budget` constraint (optional: "low"/"medium"/"high"), `provider` filter (optional), `limit`
- Internally: call existing `recommend_benchmarks` scoring to find relevant benchmarks
- Compute weighted model ranking across those benchmarks (weights proportional to benchmark relevance score)
- Return: ranked models with per-model reasoning ("Strong on coding benchmarks, top-5 in agentic tasks, mid-tier pricing")
- Include: predicted vs observed flags, confidence indicator (how many relevant benchmarks have data for each model)

### 2. `cost_leaderboard` Tool (New)
Rank models by cost-efficiency for a given benchmark or domain:
- Accept `metricKey` or `domain`, `costMetric` (default: "blendedPricePerM"), `limit`
- Compute efficiency ratio: benchmark_score / cost_per_million_tokens
- Return: ranked by efficiency with raw score, raw cost, and efficiency ratio
- Handles: models missing pricing data (excluded with note), zero-cost edge cases

### 3. Enriched Benchmark Metadata (Enhancement)
Surface richer metadata in existing `list_benchmarks` and `recommend_benchmarks` responses:
- `contaminationRisk`: "low"/"medium"/"high"/"unknown" — how likely models trained on test data
- `freshnessType`: "static"/"versioned"/"continuous" — does the benchmark get new questions?
- `scoreInterpretation`: human-readable guide ("0-100 scale, higher = better code generation")
- `metadataStatus`: "complete"/"partial"/"stub" — data quality flag
- These fields already exist in the TypeScript schema but many benchmarks have them as null/undefined in the snapshot

### 4. AgMoDB Enrichment Pipeline
- Add `inputPricePerMTok` and `outputPricePerMTok` fields to AgMoDB model schema
- Build pricing data ingestion: scrape/manual entry for major providers (OpenAI, Anthropic, Google, Meta, Mistral, Cohere, xAI)
- Enrich benchmark metadata records: fill `contaminationRisk`, `freshnessType`, `scoreInterpretation` for all benchmarks
- Update snapshot export to include new fields
- CI validation: snapshot schema check ensures new fields are present

## Why This Approach

**Interrank-first, AgMoDB follows.** Rationale:

1. interrank's `recommend_model` can be built and tested today using existing `metricValues` and `blendedPricePerM` data in the snapshot
2. `cost_leaderboard` works immediately with `blendedPricePerM` (already in snapshot); dedicated input/output pricing enhances it later
3. Benchmark metadata enrichment is a data quality task in AgMoDB — interrank just surfaces what's there
4. This avoids blocking interrank development on AgMoDB schema changes

**The existing snapshot already has `blendedPricePerM`** as a metric key — cost-aware tools work from day one, with richer per-token pricing coming later via AgMoDB.

## Key Decisions

- **New `recommend_model` tool** rather than bolting task-awareness onto existing tools — cleaner API, purpose-built for the "what model for X?" workflow
- **Pricing from AgMoDB snapshot** (not local YAML) — single source of truth, updates with snapshot refresh, no drift risk
- **`blendedPricePerM` as interim cost metric** — already available, gets us 80% of the value while dedicated pricing fields are added to AgMoDB
- **Weighted benchmark scoring for model recommendation** — reuses existing `recommend_benchmarks` relevance scores as benchmark weights when ranking models
- **Confidence indicator** — models with data on 8/10 relevant benchmarks rank higher than models with data on 2/10, all else being equal

## Open Questions

1. **Benchmark weight normalization** — when recommend_model aggregates across benchmarks, should weights be normalized so all categories contribute equally? Or should a task that maps strongly to "coding" give coding benchmarks disproportionate influence?
2. **Budget tiers** — what price thresholds define "low"/"medium"/"high"? Should these be configurable or hardcoded?
3. **AgMoDB pricing ingestion** — manual curation vs automated scraping? Provider pricing pages change format frequently; manual may be more reliable for v1
4. **Predicted cell handling in recommend_model** — should BenchPress-predicted scores be weighted lower (e.g., 0.7x) vs observed scores in the final ranking?
5. **Scope of AgMoDB CI** — just schema validation, or also data completeness checks (e.g., "warn if >20% of models missing pricing")?
