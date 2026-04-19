---
artifact_type: cuj
journey: fluxbench-model-qualification
actor: interflux operator (developer using flux-drive reviews)
criticality: p1
bead: sylveste-s3z6
---
# FluxBench Model Qualification Loop

**Last updated:** 2026-04-07
**Status:** Living document — regenerate with `/interpath:cuj`

## Why This Journey Matters

interflux dispatches multi-agent code reviews where each agent runs on a specific model. Today, model selection is manual — an operator edits `model-registry.yaml` based on vibes and informal observation. When a provider silently updates model weights or a promising new model launches, nobody notices until review quality visibly degrades or someone reads a changelog. FluxBench closes this gap: it measures models against standardized tasks, feeds scores back into the catalog, detects drift, and surfaces candidates autonomously.

If this journey is poor, interflux either stays locked to a shrinking set of models (missing better options) or unknowingly routes reviews through degraded models (silent quality loss). Both outcomes undermine the multi-model diversity that makes flux-drive reviews valuable.

## The Journey

### Establishing the baseline (first run)

The operator has interflux installed with flux-drive working on Claude. They run `fluxbench-calibrate.sh`, which executes all qualification test fixtures against Claude and computes the baseline thresholds for the 5 core FluxBench metrics: format compliance, finding recall, false-positive rate, severity accuracy, and persona adherence. The calibration output lands in `data/fluxbench-results.jsonl` and updates `model-registry.yaml` with Claude's scores. This is a one-time setup; subsequent calibrations refine thresholds as the ground-truth fixture set grows.

### Qualifying a new model

A new model appears in interrank's catalog — say `deepseek/deepseek-v4`. The operator can discover it two ways:

1. **Passive awareness.** On session start, the SessionStart hook queries interrank's `recommend_model` for code-review tasks and compares against the local registry. If `deepseek-v4` scores above threshold but isn't in the registry, the hook prints: `interrank: 1 new model candidate (deepseek-v4) — run /flux-drive discover to qualify`. The operator sees this and decides whether to act now or let the weekly schedule handle it.

2. **Automated discovery.** The weekly scheduled agent runs `discover-models.sh`, finds `deepseek-v4`, and auto-qualifies it: runs the model against all test fixtures, scores with FluxBench, writes results to JSONL. If all 5 core gates pass, the model moves from `candidate` → `qualified` in the registry and a bead is created for operator awareness.

Either path ends with the model in `qualified` status, its FluxBench scores recorded locally and queued for AgMoDB sync.

### Live qualification via challenger slot

Once qualified, the model enters the challenger slot — one agent position reserved in every flux-drive review for the highest-scoring qualifying/qualified-but-unproven model. The challenger runs alongside established agents on real reviews (never in safety-critical roles like `fd-safety` or `fd-correctness`). Its findings are included in peer findings, tagged `[challenger]`, and its FluxBench metrics accumulate from real-world data. After 10+ challenger runs, the system auto-evaluates: promote to `active` or keep in challenger rotation.

### Drift detection

A provider silently updates `deepseek-v4`'s weights. Every 10th flux-drive review, one active non-Claude agent gets a shadow run — its output scored against its qualified FluxBench baseline. If any core metric drops >15%, the model is demoted to `qualifying` and Claude takes over that agent tier until requalification passes. The operator sees a drift event in the session output. Separately, on session start, if interrank's snapshot shows `deepseek-v4` has a newer `releaseDate` than the registry's `qualified_date`, a full requalification triggers immediately — no waiting for the sampling window.

Drift has hysteresis: the model must recover to within 5% of baseline before re-promotion, preventing oscillation.

### Feedback to the catalog

`fluxbench-sync.sh` runs periodically (or on-demand), reads unsent results from `data/fluxbench-results.jsonl`, formats them as AgMoDB `externalBenchmarkScores` entries, and commits to the AgMoDB repo. On the next interrank snapshot refresh, `recommend_model` natively includes FluxBench scores — queries for "code review agent" return FluxBench-informed rankings because `TASK_DOMAIN_MAP` maps code-review tasks to the `fluxbench` category with affinity boost. The loop is closed: qualification results improve future model recommendations.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Calibration baseline | measurable | `fluxbench-calibrate.sh` exits 0 and writes >=5 fixture results to JSONL |
| SessionStart awareness | observable | Hook prints new-candidate message when interrank has models not in registry |
| Auto-qualification gate | measurable | Model passing all 5 core thresholds transitions to `qualified` in registry |
| Challenger tagging | observable | Challenger findings in flux-drive output carry `[challenger]` tag |
| Drift demotion | measurable | Model with >15% core metric drop demoted to `qualifying` within 2*N reviews |
| Hysteresis recovery | measurable | Demoted model only re-promoted when within 5% of baseline |
| AgMoDB sync | measurable | `fluxbench-sync.sh` commits FluxBench data to AgMoDB repo without duplicates |
| Recommend inclusion | measurable | `recommend_model "code review agent"` returns FluxBench-scored models |
| Safety floor | observable | Challenger never assigned to `fd-safety` or `fd-correctness` agent roles |

## Known Friction Points

- **AgMoDB has no REST write API.** Store-and-forward via git commit works but requires repo access and manual sync until automated. (sylveste-5gr4)
- **Persona adherence uses LLM-as-judge.** Haiku per-run cost for persona scoring adds expense to every qualification. No cheaper heuristic exists for v1. (brainstorm open question)
- **Ground-truth fixtures require human annotation.** The calibration anchor is only as good as the fixture set — initial set of 5 fixtures is minimal. Growing it is manual work. (sylveste-92bq)
- **discover-models.sh outputs query specs, doesn't execute.** The weekly agent must orchestrate MCP calls — the script alone can't close the loop. (sylveste-usvf)
- **Cross-model dispatch is in shadow mode.** Challenger slot needs dispatch in `enforce` mode for the challenger position, while rest stays in shadow. Mixed-mode dispatch isn't implemented yet.
