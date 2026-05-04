---
title: Microrouter Track B6 — Design revision (calibration independence + holdout protocol)
date: 2026-05-04
status: brainstorm
beads: [sylveste-s3z6.19.8, sylveste-s3z6.19.1, sylveste-s3z6.19.2, sylveste-s3z6.19.3, sylveste-s3z6.19.4, sylveste-s3z6.19.5, sylveste-s3z6.19.6, sylveste-s3z6.19.7]
findings_absorbed: [P0-B, P0-C, P0-D, P0-E]
findings_deferred: [P0-J, P0-L]
predecessor: docs/handoffs/2026-05-02-microrouter-track-b6-start-19-8.md
---

# Microrouter Track B6 — Design Revision

Hard prerequisite for `.19.1`. Resolves cross-cutting findings from the 2026-05-01 four-track flux-review that the existing children's bead bodies do not cover. Without this revision, the eval pipeline grades the router on agreement with its own training judge, the holdout leaks via the calibration feedback loop, and the holdout-accuracy gate is satisfied by majority-class collapse.

## Decision summary

| Decision | Choice | Why |
|---|---|---|
| Judge-baseline architecture | **β primary, α fallback at <2K usable pass@1 examples** | Real outcomes are stronger eval signal than judge agreement; data exists per `.19.2`; α fallback gives a buildable v0 if outcome extraction is too noisy |
| Inference path for judge augmentation | **Subscription leverage** (`claude -p` for Claude family, `codex exec -m gpt-5.5` for OpenAI family) with API-billing safety floor (~$50 budget) | Open-source non-profit context; Max + ChatGPT Pro flat fees already paid; subscription quota amortizes labeling cost to zero at the margin |
| Per-tier accuracy gate | **Replace aggregate accuracy with vector** | Aggregate ≥0.85 is satisfied by majority-class collapse; per-tier recall ≥0.60 catches it |
| Calibration freeze | **Snapshot at holdout cut date with SHA hash check enforced at training pipeline entry** | Live-file leakage flagged by P0-C; hash check makes the freeze auditable |
| Held-out agents | **Add fourth eval workload; pick 2-3 high-volume non-safety-floor agents** | Specific picks deferred to `.19.4`; constraint is the load-bearing decision here |

## Architecture: β primary, α fallback

### β architecture (primary)

- **Augmentation judge**: GPT-5.5 (via `codex exec -m gpt-5.5`) and Claude Opus (via `claude -p`) — used to fill missing labels in the corpus where bead verdicts don't have clean pass/fail attribution. Both judges run on the same examples for high-confidence labels; disagreement triggers human review.
- **Baseline anchor**: **Observed downstream pass@1**. The router is graded on whether tasks the chosen agent×model actually shipped — not on similarity to a teacher recommendation. Sources:
  - Bead-history verdicts (~498 closed beads with pass/fail/needs-retry status, per `os/Clavain/CLAUDE.md`)
  - Session JSONL outcomes (10K+ sessions indexed via cass; task → outcome implicit via session continuation/abandonment patterns)
  - Sprint reflection artifacts (`docs/reflections/*`) for high-fidelity post-hoc judgments

### α architecture (v0 fallback)

If `.19.2` dataset construction produces fewer than **2K usable pass@1 examples** with attribution clean enough for training, fall back to:

- **Augmentation judge**: Gemini 2.5 (via Vertex AI) or local Qwen3.6-35B consensus
- **Baseline anchor**: existing GPT-5.5/Opus calibration data (`routing-calibration.json`)

The router learns from one teacher, is graded against another — different model families, no circular calibration.

### Threshold rationale (2K)

The microrouter is a 3B classifier with rank-16 LoRA. Empirical floor for stable LoRA training in the open literature: ~1K-2K examples for classification with reasonable class balance. Below 2K, label noise dominates and the model may not learn anything beyond the most frequent class. The α fallback is preferable to a β with insufficient data, because β with too-few labels recreates the majority-class-collapse failure mode that `.19.8` Required Change #4 (per-tier recall) was designed to catch.

### Decision belongs in `.19.1`

`.19.1` (design doc) is the place where this picks one path. `.19.8` establishes the criterion (the 2K threshold) and the fallback path (α). The actual call happens in `.19.2` after the dataset coverage report.

## Inference path: subscription leverage

For β-baseline judge augmentation and α-fallback judge augmentation alike, the inference stack is:

| Model family | CLI | Backend | Quota |
|---|---|---|---|
| Claude (Sonnet/Opus) | `claude -p` | Claude Max OAuth via CLIProxyAPI | Max plan flat fee |
| OpenAI (gpt-5.5) | `codex exec -m gpt-5.5` | ChatGPT Pro OAuth via CLIProxyAPI | ChatGPT Pro flat fee |
| Fallback for rate-limit edge | Anthropic API + OpenAI API | Direct | ~$50 budget cap |

### Operating constraints

1. **Rate-limit collision with daily-driver work.** Hermes overlay (bead `sylveste-khb8`) and microrouter labeling both compete for the same Max bucket through CLIProxyAPI. Schedule batch labeling off-hours (e.g., overnight cron) OR throttle to ≤30% of recent peak rate. Budget gate in dataset construction: track Max-bucket usage during run; pause if 80% of daily quota consumed.
2. **Reproducibility.** Subscription endpoints don't pin model version — silent backend upgrades could shift labels mid-run. Mitigate: capture `model` field in each label record; document calibration cut-date in `.19.2` output; if the backend version shifts mid-run, freeze and restart with the new version recorded.
3. **xhigh variants suspect on ChatGPT auth.** Plain `gpt-5.5` is verified safe; xhigh variants need a smoke call before relying. Stick to plain `gpt-5.5` for batch labeling.
4. **API-billing safety floor.** ~$50 budget is for cases where subscription rate-limits block dataset construction. Track which backend labeled each example via a `judge_backend` field: `claude_max | chatgpt_pro | api_anthropic | api_openai`. Allows post-hoc audit and bias-checking.
5. **Multi-judge consensus.** For β, run both `claude -p` (Opus) and `codex exec` (gpt-5.5) on the same examples for a sample (~10% of corpus). Compare. Disagreement rate >15% → flag the labeling rubric for ambiguity; restate.

## Required design changes (per `.19.8` bead body)

### Change #1 — Judge family ≠ baseline anchor

**β implementation:** Augmentation judge is GPT-5.5 + Claude Opus (model-family ensemble); baseline anchor is observed downstream pass@1 (no model judging the holdout — the holdout is graded against actual shipped/failed outcomes from production data).

**α fallback implementation:** Augmentation judge is Gemini 2.5 OR local Qwen3.6-35B; baseline anchor is GPT-5.5/Opus calibration JSON. Different families.

**Decision belongs in `.19.1`** — `.19.8` establishes the constraint, `.19.1` documents the picked architecture in the canonical design doc.

### Change #2 — Calibration freeze date + SHA hash check

**Procedure:**
1. At the holdout cut date (TBD in `.19.1`, recommended: 2026-05-15 to allow ~10 more days of organic data accumulation), snapshot `.clavain/interspect/routing-calibration.json` as `routing-calibration.SNAPSHOT-2026-05-15.json`. Compute SHA256.
2. Record SHA in three places:
   - `interverse/interlab/datasets/microrouter-v0/MANIFEST.json` (the dataset manifest)
   - `.19.1` design doc (the canonical reference)
   - Training pipeline entry script (hardcoded constant)
3. **Hash check enforced at**:
   - Training pipeline entry — refuse to start if snapshot SHA doesn't match recorded constant
   - Eval pipeline entry — same check
   - Judge-augmentation pipeline — reads ONLY the snapshot, never the live file
4. The live `routing-calibration.json` continues to update from production work — that's correct behavior. The snapshot is the frozen training-time view.

### Change #3 — Held-out-agents eval workload

Add a fourth workload to the `.19.4` eval matrix:

```
held-out-agents: exclude all tasks from agents A, B, C during training.
                 Evaluate model performance as if these were new agents
                 it had never seen during training.
```

This is the only workload that catches "the router memorized task-text → tier mappings during training." LCB v6, replayed history, and synthetic adversarial workloads all share training-time exposure to the same agent set.

**Constraint on agent picks:**
- Must be **high-volume** (need enough holdout examples for stable evaluation — minimum 100 examples/agent)
- Must NOT be **safety-floor agents** (fd-safety, fd-correctness) — these have routing floors that bypass the microrouter entirely; their holdout doesn't exercise the router
- Must span **at least two phases** (e.g., one design-phase agent + one execution-phase agent + one review-phase agent) — phase-specific overfitting is a known risk

**Specific picks deferred to `.19.4`** — depends on volume distribution after `.19.2` dataset construction completes. `.19.4` records the picks in its bead body once chosen.

### Change #4 — Per-tier recall vector replacing aggregate accuracy

In `.19.3` "Done when":

- **Replace:** `Holdout accuracy ≥ 0.85`
- **With:**
  ```
  aggregate accuracy ≥ 0.85
  AND per-tier recall ≥ 0.60 for every tier present in training data
  AND per-tier confusion matrix promoted to first-class gating artifact
  ```

**Why aggregate alone fails (P0-E):** if the corpus is Sonnet-heavy (say 75% Sonnet), a model that predicts "Sonnet" always trivially clears 0.85 aggregate accuracy on the holdout. Per-tier recall ≥0.60 breaks this — the always-Sonnet model has 0.0 recall for every non-Sonnet tier.

**0.60 per-tier rationale:** below 0.50 the model is worse than coin-flip on that tier (assuming binary). 0.60 is the lowest defensible threshold that says "the model has learned this tier exists." Higher thresholds (0.75+) are aspirational but may be unachievable with sparse tiers.

**Confusion matrix as gating artifact:** the eval report MUST include per-tier confusion matrix (rows = true tier, cols = predicted tier). The pass criterion is computable from the matrix. Reviewers can spot-check tier-specific failure modes before approving training run.

## Findings traceability

| Finding | Track | Severity | How addressed |
|---|---|---|---|
| P0-B (gongfu-cha) — Circular judge↔baseline calibration | C | P0 | Change #1: family separation. β primary makes judge↔baseline different *categories* (judge is model, baseline is observation), not just different families. |
| P0-C — `routing-calibration.json` is both training signal and live-updating | A | P0 | Change #2: SHA-pinned snapshot at training pipeline entry; live file untouched but unread by training. |
| P0-D — Replayed bead-history workload uses tasks whose verdicts were the source of labels | A | P0 | Change #3: held-out-agents workload as the orthogonal check; LoRA memorization caught by holdout from agents not in training set. |
| P0-E — ≥0.85 holdout accuracy satisfied by always-predict-majority-class | A | P0 | Change #4: per-tier recall vector + confusion matrix as gating artifacts. |

### Findings deferred (NOT in `.19.8` scope)

| Finding | Track | Where it goes |
|---|---|---|
| P0-J — Audit-trail unconformity (microrouter no-op short-circuit erases resolver layer) | A | `.19.5` body update; tracked in `Sylveste-a5u` |
| P0-L — Privacy fail-mode (sensitive tasks fall through to cloud when router down) | C | `.19.6` body update; tracked in `Sylveste-906` |

These finding beads remain open until `.19.5` and `.19.6` absorb them. Closing them now would lose the audit trail.

## Done when (`.19.8` exit criteria)

- [x] This brainstorm doc written and committed
- [ ] `.19.1` bead body edited to reference this revision and document the chosen architecture (β primary)
- [ ] `.19.2` bead body edited to reference this revision and document the 2K threshold for α fallback + the inference-path subscription leverage
- [ ] `.19.3` bead body edited to reference Change #4 (per-tier recall + confusion matrix gate) and Change #2 (snapshot read, not live file)
- [ ] `.19.4` bead body edited to reference Change #3 (held-out-agents workload) and the agent-pick constraint
- [ ] `.beads/issues.jsonl` regenerated via `bd export -o .beads/issues.jsonl`
- [ ] Commit `chore(beads): track B6 .19.8 design revision absorbed P0-B/C/D/E + inference-path subscription leverage`
- [ ] `.19.8` closed with note pointing at this brainstorm and the four downstream bead edits

## Open questions for `.19.1` and `.19.4`

These belong in the next bead's design phase, not in this revision:

1. **Calibration freeze cut date** — recommended 2026-05-15 (10 days from now); finalize in `.19.1`.
2. **Held-out agents (specific picks)** — depends on `.19.2` volume distribution; finalize in `.19.4` after dataset coverage report.
3. **β-vs-α call** — depends on `.19.2` outcome-label coverage; finalize in `.19.2` itself once dataset is built.
4. **Multi-judge consensus disagreement threshold** — recommended 15%; finalize empirically after first labeling pilot.
5. **Daily Max-bucket quota cap for batch labeling** — recommended 80%; depends on user's typical daily-driver usage during the labeling window.
