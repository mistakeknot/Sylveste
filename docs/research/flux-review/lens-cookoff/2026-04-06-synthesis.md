---
artifact_type: review-synthesis
method: flux-review
target: "apps/Auraken/data/calibration/"
target_description: "Auraken lens selection calibration pipeline (cookoff + analysis + anchor suite)"
tracks: 4
track_a_agents: [fd-psychometric-instrument-design, fd-distributed-pipeline-reliability, fd-statistical-aggregation-methodology, fd-multi-provider-model-behavior, fd-information-theoretic-lens-calibration]
track_b_agents: [fd-actuarial-model-credibility, fd-sensory-panel-protocol, fd-clinical-laboratory-proficiency, fd-election-audit-risk-limiting]
track_c_agents: [fd-song-celadon-kiln-calibration, fd-talmudic-machloket-adjudication, fd-polynesian-star-compass-calibration, fd-mesoamerican-obsidian-knapping-platform, fd-ottoman-hat-calligraphy-repertoire]
track_d_agents: [fd-yoruba-ifa-odu-verse-selection, fd-byzantine-iconographic-program-selection, fd-akkadian-baru-hepatoscopy-classification]
date: 2026-04-06
---

# Lens Cookoff Pipeline — Cross-Track Synthesis

## Critical Findings (P0/P1)

### 1. Stale `LOW_BIAS_MODELS` produces zero anchors [P0]
**Found by:** Track A (psychometric, statistical), Track C (Polynesian), Track D (Yoruba Ifa)

`build_anchor_suite.py` line 27 hardcodes `LOW_BIAS_MODELS = {"gpt-5.4-mini", "llama-4-maverick", "command-r-plus", "deepseek-v3.2"}`. Three of these four are no longer in the active model lineup. Result: `n_low = 0` for every dilemma, `corrected_agreement = 1.0`, `corrected_consensus = []`, and the anchor extraction filter (`info["corrected_consensus"]` must be non-empty) rejects everything. **The pipeline currently produces zero anchors.**

**Fix:** Derive `LOW_BIAS_MODELS` dynamically from the analysis output, or update the hardcoded set to match the current ensemble.

### 2. Fixed lens ordering makes position bias a shared confound [P0]
**Found by:** Track A (multi-provider), Track B (sensory panel), Track C (Polynesian, Song celadon, obsidian), Track D (Byzantine, Akkadian, Yoruba Ifa)
**Convergence: 4/4 tracks (highest confidence)**

`build_lens_index()` produces one fixed ordering used by all 12 models on all 1,360 dilemmas. Position bias and genuine lens quality are inseparable. The per-model bias grades in `analyze_cookoff.py` measure incremental bias above an already-elevated shared baseline — but that baseline is invisible. The 3.4% random baseline (line 231) is wrong because the actual baseline for early-position lenses is elevated for ALL models simultaneously.

**Fix:** Add optional `seed` parameter to `build_lens_index()` that shuffles lens order. Run a held-out 10% with shuffled order to disentangle position from content.

### 3. No model-family independence weighting [P1]
**Found by:** Track A (information-theoretic), Track B (actuarial, clinical lab), Track C (Song celadon, Talmudic), Track D (Yoruba Ifa)
**Convergence: 4/4 tracks**

The 12-model ensemble includes correlated model families (2 Nvidia Nemotron variants, 2 Qwen variants, GPT via both API and Codex CLI). Agreement between family members is counted the same as cross-family agreement. Effective ensemble size may be 8-9, not 12. No code computes pairwise or family-stratified agreement.

**Fix:** Define `MODEL_FAMILIES` dict, require corrected consensus to span at least 2 distinct families. Compute pairwise Jaccard similarity matrix.

### 4. No model version capture in JSONL [P0/P1]
**Found by:** Track B (clinical lab proficiency, actuarial), Track C (Polynesian)

OpenRouter and OpenAI may silently update models mid-run (especially with `--resume`). The JSONL records `"model": "deepseek-v3.2"` but not the resolved version or system fingerprint. Two model checkpoints can be conflated under one name.

**Fix:** Capture `data.get("model", "")` and `data.get("system_fingerprint", "")` from API responses, write to JSONL.

### 5. No completion manifest before aggregation [P0]
**Found by:** Track B (election audit)

Neither `analyze_cookoff.py` nor `build_anchor_suite.py` verifies that all expected `(dilemma, model)` pairs are present. Timeout/error gaps silently reduce panel size, making apparent consensus on incomplete data eligible for anchor promotion.

**Fix:** Build expected manifest, warn on missing pairs, flag dilemmas with fewer than full panel.

### 6. Self-referential calibration loop [P1]
**Found by:** Track A (psychometric), Track C (Polynesian), Track D (Yoruba Ifa, Akkadian)
**Convergence: 3/4 tracks**

`LOW_BIAS_MODELS` is derived from analysis → anchors derived from `LOW_BIAS_MODELS` → anchors validate the pipeline. No external ground truth enters anywhere. The system certifies precision (cross-model consistency) but not accuracy.

**Fix:** Add 20-30 expert-validated scenarios with human-judged lens selections. Break the self-referential loop.

## Cross-Track Convergence

| Finding | Tracks | Score | Key Agents |
|---------|--------|-------|------------|
| Fixed lens ordering confounds all bias measurement | A, B, C, D | **4/4** | multi-provider, sensory-panel, Polynesian, Song celadon, Byzantine, Akkadian, Yoruba Ifa |
| Model-family independence not weighted | A, B, C, D | **4/4** | info-theoretic, actuarial, clinical-lab, Talmudic, Song celadon, Yoruba Ifa |
| Self-referential calibration (no external ground truth) | A, C, D | **3/4** | psychometric, Polynesian, Yoruba Ifa, Akkadian |
| Lens description properties as selection covariates | A, C, D | **3/4** | info-theoretic, obsidian, Akkadian, Ottoman calligraphy |
| Near-miss boundary topology not aggregated | C, D | **2/4** | Polynesian, Akkadian |
| Universal-silence dilemmas discarded from anchors | D | **1/4** | Yoruba Ifa |

## Domain-Expert Insights (Track A)

The strongest adjacent-domain findings cluster around statistical methodology:
- **Fleiss's kappa**: Raw agreement metric doesn't correct for chance. With 291 labels, even small coincidental overlap looks like consensus. (statistical-aggregation)
- **Binary bias correction is a step function**: The 40% threshold for LOW_BIAS_MODELS creates a discontinuity — 39% gets full weight, 41% gets zero. Inverse-bias weighting would be smoother. (statistical-aggregation)
- **CLI prompt asymmetry**: CLI models get `"System: {prompt}\n\n{input}"` as flat text, not a structured system message. This is a structural difference affecting instruction-following. (multi-provider)
- **No cardinality enforcement**: Models can return >3 lenses despite the prompt saying 0-3. Over-selecting models inflate their vote weight. (multi-provider)
- **JSONL resume crash on truncated lines**: If killed mid-write, the last line is partial JSON that crashes the resume reader. (pipeline-reliability)

## Parallel-Discipline Insights (Track B)

- **Credibility weighting (actuarial)**: Models should be weighted by Z = n/(n+k) where k reflects cross-model variance, not treated as equally credible. The SBI attractor is partly a missing-prior artifact.
- **Blind duplicates (sensory panel)**: No within-model reproducibility check exists. Inserting 2-3% blind duplicate dilemmas would measure intra-model reliability before trusting cross-model agreement.
- **Sequential stopping (election audit)**: BRAVO-style early termination could reduce cost 30-60% — stop sampling for lenses that reach stable consensus after 200 dilemmas.
- **Narrow-margin anchors (election audit)**: The anchor suite excludes borderline cases (55-65% agreement) — exactly the dilemmas most sensitive to future model changes.

## Structural Insights (Track C)

- **Bias gradient, not binary (Song celadon)**: Position bias should be modeled as a per-model curve (top-10 AND top-30 rates), not a 3-bucket grade.
- **Principled vs. factual disagreement (Talmudic)**: Two models defensibly selecting competing frameworks ≠ one model misreading the dilemma. The pipeline treats both as identical disagreement scores.
- **Lens co-contestation matrix (Polynesian, Akkadian)**: Aggregating which lens pairs are contested together across 50+ near-misses would map the 291-lens boundary topology — 10 lines of Counter logic.
- **Per-model effective repertoire (Ottoman calligraphy)**: How many of 291 lenses each model actually uses. Narrow-repertoire models have equal vote weight to broad-repertoire models.
- **Selection volume normalization (obsidian)**: Models averaging 0.4 vs 2.8 lenses/dilemma are not normalized before vote counting.

## Frontier Patterns (Track D)

- **Recall-order bias correction (Yoruba Ifa)**: The Ifa tradition's rotational recitation practice (varying start position each cycle) is exactly the shuffled lens index fix. Cross-lineage agreement (Oyo vs. Ekiti) maps to cross-family model agreement.
- **Hierarchical-constraint distortion (Byzantine)**: High-agreement anchors (>90%) may be the "apse positions" — theologically mandated, not genuinely judged. The mid-agreement band (5-9/12) is the "nave" where real calibration signal concentrates.
- **Prototype-anchoring bias (Akkadian)**: Lens descriptions themselves create attractor basins. SBI's 38% rate may track description vividness (acronym, concrete examples) not applicability. A 10-line join of `lens_freq` against `lens_library_v2.json` metadata would test this.
- **Silence-as-signal (Yoruba Ifa)**: Dropped models (maverick 97.8% zero, step-3.5-flash 100% zero) are coherent signals about how certain architectures interpret the task, not broken data.

## Synthesis Assessment

**Overall quality:** The pipeline's design is sound — multi-model cookoff with streaming JSONL, bias detection, and anchor extraction is the right architecture. The implementation has one blocking bug (stale `LOW_BIAS_MODELS`) and several structural gaps that reduce the calibration signal's validity.

**Highest-leverage improvement:** Shuffle lens ordering with a per-run seed. This single change (one `random.shuffle` call + seed in JSONL) breaks the shared position-bias confound that 4/4 tracks independently identified as the most fundamental threat to calibration validity.

**Surprising finding:** The Akkadian "prototype-anchoring" insight — that the lens descriptions themselves may be the primary driver of selection frequency, not the dilemmas. Testing whether `lens_freq` correlates with description length/vividness would take 10 lines and could reframe the entire calibration problem from "which models are biased" to "which lens descriptions are biased."

**Semantic distance value:** The outer tracks (C/D) contributed qualitatively different insights. Track A and B identified the same bugs through different professional vocabularies. Track C's Polynesian agent found the self-referential calibration loop. Track D's Yoruba agent identified the silence-as-signal principle (dropped models as diagnostic data). The Akkadian agent's prototype-anchoring reframe (audit the lens library, not just the models) was invisible to all other tracks.
