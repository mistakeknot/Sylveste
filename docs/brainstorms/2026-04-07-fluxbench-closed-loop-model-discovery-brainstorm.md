---
artifact_type: brainstorm
bead: sylveste-s3z6
stage: discover
---

# FluxBench: Closed-Loop Model Discovery for Interflux

## What We're Building

A closed feedback loop between interflux's multi-model qualification pipeline and AgMoDB/interrank, centered on **FluxBench** — a custom benchmark suite measuring what generic benchmarks can't: whether a model produces useful structured review findings from domain-specific agent prompts.

Three capabilities:
1. **FluxBench write-back**: After shadow/qualification runs, interflux writes 8 benchmark scores per model to AgMoDB. interrank's `recommend_model` and `cost_leaderboard` natively include FluxBench data in scoring, so future model recommendations improve with every qualification cycle.
2. **Drift detection**: Continuous requalification via sample-based monitoring (1-in-N reviews) plus triggered requalification on model version changes. Detects both silent provider updates and explicit version bumps.
3. **Proactive surfacing**: SessionStart hook polls interrank for new models above FluxBench-relevant thresholds (immediate awareness). Weekly scheduled agent runs `discover-models.sh` and auto-qualifies candidates (autonomous action).

## Why This Approach

**Full AgMoDB loop over sidecar/local**: Qualification results belong in the same data store as public benchmarks so interrank's scoring algorithm weighs them natively. A local sidecar means maintaining a parallel scoring path. The `externalBenchmarkScores` table in AgMoDB already supports third-party data ingest from 34+ scrapers — FluxBench is just another source.

**AgMoDB API endpoint over direct DB or git**: Clean separation of concerns. interflux reports results, AgMoDB validates and stores them, export-snapshot includes them. No DB credentials in interflux's env.

**Both drift modes over sample-only or trigger-only**: Silent provider updates (weight tweaks, safety filter changes) are common and invisible to version-tracking. Sample-based catches these. But known version bumps warrant immediate full requalification rather than waiting for the sample to hit. Both signals combined with OR logic.

**Both surfacing modes**: SessionStart hook is zero-cost awareness (one MCP query). Weekly schedule is where actual qualification work happens. Separating awareness from action keeps sessions fast while maintaining autonomy.

## FluxBench: 8 Metrics

### Core (gate qualification)

| Metric | Key | Description | Threshold |
|--------|-----|-------------|-----------|
| Format compliance | `fluxbench-format-compliance` | Binary gate: ≥95% of runs produce valid Findings Index (header, pipe-delimited lines, Verdict) | ≥95% pass/fail |
| Finding recall (weighted) | `fluxbench-finding-recall` | Severity-weighted recall vs baseline (P0=4×, P1=2×, P2=1×, P3=0.5×). Missing a P0 fails regardless of overall score | ≥60% weighted to qualify |
| False positive rate | `fluxbench-false-positive-rate` | % of candidate findings not in baseline AND not independently validated as real issues | ≤20% to qualify |
| Severity accuracy | `fluxbench-severity-accuracy` | % of severity ratings (P0-P3) matching baseline ±1 level | ≥70% to qualify |
| Persona adherence | `fluxbench-persona-adherence` | Does the model stay in domain persona vs generic analysis (0-1 scale, LLM-judged) | ≥0.6 to qualify |

### Extended (inform routing, not gate)

| Metric | Key | Description | Use |
|--------|-----|-------------|-----|
| Instruction compliance | `fluxbench-instruction-compliance` | Follows multi-step prompt structure (output sections, peer findings protocol, focus area) | Route complex agents only to compliant models |
| Cross-family disagreement rate | `fluxbench-disagreement-rate` | % of findings unique to this model (not in Claude baseline) — measures diversity value | Higher = more valuable for cross-family convergence signal |
| Latency to first token | `fluxbench-latency-p50` | p50 response latency in ms | Calibrate flux-watch timeouts per model |
| Output token efficiency | `fluxbench-token-efficiency` | Findings per 1K output tokens | Inform budget estimates per model in cost report |

### AgMoDB Integration

Each FluxBench metric becomes a `benchmarkDefinition` row in AgMoDB with:
- `category: "fluxbench"`
- `source: "interflux-qualification"`
- `relevantUseCases: ["code review", "multi-agent review", "structured output", "agent"]`
- `freshnessType: "continuous"` (updated by every qualification cycle)
- `contaminationRisk: "low"` (task-specific, not memorizable)

interrank's `recommend_model` already matches on `relevantUseCases` and `category`. Queries for "code review agent" will naturally pick up FluxBench-scored models because the use cases overlap. The `TASK_DOMAIN_MAP` in `recommend.ts` maps "code review" → ["coding", "agents"] — adding "fluxbench" to the affinity map boosts FluxBench benchmarks for code-review-flavored queries.

## Write-Back Mechanism

**AgMoDB API endpoint**: `POST /api/fluxbench/report`

```json
{
  "model_slug": "deepseek/deepseek-chat",
  "qualification_run_id": "sylveste-s3z6-qual-001",
  "metrics": {
    "fluxbench-format-compliance": 0.95,
    "fluxbench-finding-recall": 0.72,
    "fluxbench-severity-accuracy": 0.81,
    "fluxbench-persona-adherence": 0.68,
    "fluxbench-instruction-compliance": 0.88,
    "fluxbench-disagreement-rate": 0.15,
    "fluxbench-latency-p50": 2400,
    "fluxbench-token-efficiency": 0.42
  },
  "metadata": {
    "shadow_runs": 20,
    "agent_types_tested": ["checker", "analytical"],
    "baseline_model": "claude-sonnet-4-6",
    "qualification_date": "2026-04-07",
    "source": "interflux-v0.2.57"
  }
}
```

The endpoint validates, writes to `externalBenchmarkScores`, and tags the source as `interflux`. Next snapshot export includes FluxBench data.

## Drift Detection

**Sample-based**: Every Nth review (N=10 default), pick 1 active non-Claude agent. Run it in shadow alongside Claude. Compare FluxBench core metrics against the model's qualified baseline. If any core metric drops >15% from baseline, flag for requalification.

**Trigger-based**: interrank's snapshot includes `releaseDate` per model. On SessionStart, compare active models' registry `qualified_date` against snapshot `releaseDate`. If model was updated after qualification, trigger requalification.

**Drift response**: Model demoted to `qualifying` status. Interflux continues using Claude for that agent's tier until requalification passes. Drift event written to AgMoDB as a new FluxBench report with `metadata.trigger: "drift"`.

## Proactive Surfacing

**SessionStart hook** (awareness):
```bash
# Query interrank for new models scoring above threshold on FluxBench-relevant benchmarks
# Compare against model-registry.yaml — surface models not yet in registry
# Display: "interrank: 2 new model candidates (deepseek-v4, qwen-3.1) — run /flux-drive discover to qualify"
```

**Weekly schedule** (action):
```bash
# Scheduled via /clavain:schedule
# 1. Run discover-models.sh (queries interrank)
# 2. For each new candidate, run 3 synthetic qualification tasks
# 3. Write FluxBench results to AgMoDB
# 4. Update model-registry.yaml
# 5. Create bead if any candidate qualifies
```

## Key Decisions

- **FluxBench is a first-class AgMoDB benchmark suite** (9 metrics — 5 core gates + 4 extended), not a sidecar file
- **Store-and-forward write pattern**: persist FluxBench results locally first (JSONL), forward to AgMoDB asynchronously. Decouples qualification from API availability
- **AgMoDB is authoritative for benchmark data; model-registry.yaml is a local cache** that reads from AgMoDB on startup and stores operational state (status, shadow run counts)
- **Dual drift detection**: sample-based (1-in-10, max gap 2×N reviews) + version-triggered requalification
- **Drift hysteresis**: flag at >15% metric drop, clear only when recovered to within 5% of baseline
- **Dual surfacing**: SessionStart hook (awareness) + weekly schedule (action)
- **Qualification thresholds set empirically** from a calibration phase against 5-10 existing models, not intuition
- **interrank's recommend_model natively includes FluxBench** via category matching and TASK_DOMAIN_MAP
- **Challenger slot**: always reserve 1 agent slot for the highest-scoring unqualified candidate to prevent preferential attachment
- **MVP-first**: FluxBench scoring locally (JSON output) → validate metrics correlate with review quality → then AgMoDB integration

## Review-Incorporated Changes (from flux-drive review 2026-04-07)

### Added: false-positive-rate as 5th core gate metric
A model with 100% recall but 80% false positive rate is worse than 60% recall with 5% FP. Added `fluxbench-false-positive-rate` to core gates (threshold: ≤20% to qualify).

### Changed: severity-weighted finding recall
Raw recall treats all findings equally. Missing a P0 should fail qualification regardless of overall %. Changed to weighted recall: P0=4×, P1=2×, P2=1×, P3=0.5×.

### Changed: format-compliance is now a binary gate, not a scored metric
A model producing perfectly formatted empty findings scores 100% on format compliance. Changed to binary: ≥95% → pass, <95% → fail. Not included in weighted scoring.

### Added: sampling guarantee for drift detection
The 1-in-10 rate has 12% chance of going 20+ reviews without sampling. Added: force shadow run if model hasn't been sampled in 2×N reviews (worst case = 20 reviews for N=10).

### Added: human-validated calibration set
5-10 review tasks with human-annotated ground-truth findings reduce Claude baseline dependency. Provides Goodhart-resistant anchor independent of any model family.

### Acknowledged: Claude baseline circular dependency (highest-convergence finding, 5/6 agents)
Three of four original core metrics reference Claude as baseline. Mitigations:
1. Human-validated calibration set (model-independent anchor)
2. Cross-family disagreement rate measures diversity value, not Claude agreement
3. Over time, FluxBench calibration set accumulates human-verified ground truth that reduces Claude dependency
4. Finding survival rate (do findings lead to code changes?) provides an outcome signal independent of any model

### Acknowledged: AgMoDB write API is a blocking prerequisite
The existing ingest path is git-committed JSONL from scrapers, not a REST API. Store-and-forward pattern handles interim: interflux writes JSONL locally, a periodic script commits to AgMoDB repo.

## Open Questions

- **Synthetic qualification tasks**: Need 5-10 standardized test documents with known ground-truth findings. Where do these live? (Probably `interverse/interflux/tests/fixtures/qualification/`)
- **AgMoDB auth for write-back**: API key, OAuth, or mutual TLS? (AgMoDB currently has no public write API)
- **Persona adherence scoring**: LLM-as-judge is expensive. Should we use Claude Haiku for this or find a heuristic proxy?
- **Cross-project FluxBench**: Should other tools beyond interflux be able to report FluxBench results?
- **Finding survival rate tracking**: Requires integration with beads/git to detect which findings led to code changes. Complex. Defer to v2?
