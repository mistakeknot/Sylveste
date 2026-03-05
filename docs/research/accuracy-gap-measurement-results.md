# Accuracy Gap Measurement Results

**Bead:** iv-u74sq
**Date:** 2026-03-05
**Method:** Synthetic benchmark — 15 tasks, 3 categories, with/without composition context
**Model:** Claude Opus 4.6 (subagent dispatch)
**Composition Layer:** tool-composition.yaml (1,758 chars / ~440 tokens)

---

## Raw Results

### Discovery (tool selection with clear need)

| # | Task | Expected | With Comp | Without Comp | W | WO |
|---|---|---|---|---|---|---|
| 1 | Semantic code search | intersearch/tldr-swinton | intersearch | intersearch | 1 | 1 |
| 2 | Documentation drift check | interwatch | interwatch | intercheck | 1 | 0 |
| 3 | Active agents | intermux | intermux | intermux | 1 | 1 |
| 4 | Token/cost tracking | interstat | interstat | interstat | 1 | 1 |
| 5 | Architecture diagrams | interchart | interchart | interchart | 1 | 1 |

**Discovery: With 5/5 (100%), Without 4/5 (80%). Delta: +20%**

Task 2 is the interesting case: without composition context, the agent confused "check docs" with "intercheck" (a quality/verification tool). The composition layer's Docs domain listing (`interwatch, interdoc, interpath, interkasten — Documentation lifecycle, drift detection`) disambiguated this.

### Sequencing (correct tools AND correct order)

| # | Task | Expected | With Comp | Without Comp | W | WO |
|---|---|---|---|---|---|---|
| 6 | Reserve files for editing | interpath→interlock | interpath→interlock | interlock (alone) | 1 | 0 |
| 7 | Review plan then sprint | interflux→clavain | interflux→clavain | serena→intercheck | 1 | 0 |
| 8 | Set up tracking then sprint | interstat→clavain | interstat→clavain | interstat (alone) | 1 | 0.5 |
| 9 | Check reservations then review | interlock→interflux | interlock→interflux | interlock→serena | 1 | 0.5 |
| 10 | Generate docs then check drift | interpath→interwatch | interdoc→interwatch | interdoc→intercheck | 0.5 | 0 |

**Sequencing: With 4.5/5 (90%), Without 1/5 (20%). Delta: +70%**

The sequencing hints had the strongest effect. Without them, the agent either:
- Used only one tool where two were needed (tasks 6, 8)
- Selected wrong tools entirely (task 7: serena→intercheck instead of interflux→clavain)
- Got one tool right but the second wrong (task 9: interlock→serena instead of interlock→interflux)

Task 10 scored 0.5 with composition because the expected answer was interpath→interwatch but the agent chose interdoc→interwatch. The interpath vs interdoc distinction is subtle (both are in the docs domain), but interpath is the artifact generator while interdoc manages AGENTS.md. The sequencing hint doesn't cover this pair — it covers interpath→interlock and interflux→clavain. This suggests the composition layer works well for EXPLICITLY hinted pairs but doesn't generalize to unhinted pairs in the same domain.

### Scale (ambiguous prompts — any valid tool is correct)

| # | Task | Valid Options | With Comp | Without Comp | W | WO |
|---|---|---|---|---|---|---|
| 11 | Understand codebase | tldr-swinton/intermap/serena/intersearch | tldr-swinton | intermap | 1 | 1 |
| 12 | Pre-ship check | interflux/intercheck/clavain:verify | intercheck | intercheck | 1 | 1 |
| 13 | Find callers | serena/tldr-swinton/intermap | tldr-swinton | tldr-swinton | 1 | 1 |
| 14 | Document work | interdoc/interpath/interkasten | interdoc | interdoc | 1 | 1 |
| 15 | Coordinate with agent | interlock/intermux/intercom | interlock | interlock | 1 | 1 |

**Scale: With 5/5 (100%), Without 5/5 (100%). Delta: 0%**

As expected, the composition layer doesn't affect ambiguous-prompt performance. Both variants scored perfectly because any valid tool counts as correct. The model's name-inference capability handles scale tasks well — "interlock" obviously relates to locking, "interdoc" to documentation, etc.

---

## Summary

| Category | With Composition | Without Composition | Delta |
|---|---|---|---|
| Discovery | 100% (5/5) | 80% (4/5) | **+20%** |
| Sequencing | 90% (4.5/5) | 20% (1/5) | **+70%** |
| Scale | 100% (5/5) | 100% (5/5) | **0%** |
| **Overall** | **96.7% (14.5/15)** | **66.7% (10/15)** | **+30%** |

## Gap Decomposition (Mapping to R3 Dialectic Bands)

The R3 sublation predicted three bands: discovery, sequencing, scale. The benchmark results map cleanly:

1. **Discovery gap (shallow metadata closes it): +20%**
   - Domain groups and curation groups help disambiguate when plugin names are misleading (interwatch vs intercheck for "drift").
   - Most discovery works from names alone — the model infers well from "intersearch", "interstat", etc.
   - The composition layer's value is at the margins: the few cases where naming is ambiguous.

2. **Sequencing gap (shallow hints close most of it): +70%**
   - This is where the composition layer delivers the most value. Without explicit `first→then` hints, the model frequently:
     - Omits prerequisite tools (uses interlock without interpath first)
     - Selects wrong tools for multi-step workflows (serena→intercheck instead of interflux→clavain)
     - Doesn't know which tools form a pipeline
   - The effect is limited to EXPLICITLY hinted pairs. Task 10 (interpath→interwatch vs interdoc→interwatch) shows the gap where no hint exists.

3. **Scale gap (irreducible, model handles it): 0%**
   - With 34+ plugins, the model still selects valid tools for ambiguous prompts at 100%.
   - This contradicts the original "18-point gap" framing — the model IS capable at scale when the task is genuinely ambiguous (multiple valid answers).
   - The real 18-point gap was likely dominated by sequencing failures, not scale degradation.

## Interpretation

**The composition layer's value is almost entirely in sequencing hints, not discovery metadata.**

- Discovery metadata: nice-to-have, marginal improvement (+20%). The model's name inference handles most discovery.
- Sequencing hints: essential for multi-step workflows (+70%). Without them, the model doesn't know tool pipelines.
- Scale: non-issue. The original "18-point gap" was measuring sequencing failures, not scale degradation.

**The R3 dialectic was right about the three-band decomposition but wrong about the relative sizes.** It expected:
- Discovery: large band (most plugins need shallow metadata)
- Sequencing: moderate band (fewer cross-tool dependencies)
- Scale: small band (irreducible)

Actual: Discovery is small, Sequencing is dominant, Scale is zero.

## Recommendation for iv-mtf12

**Invest in expanding sequencing hints, not adding more domain metadata.**

1. The current 4 sequencing hints cover the most critical pipelines. Audit real sessions (once instrumentation is collecting data) to find unhinted pipelines that users encounter.
2. Domain groups are useful for the composition YAML but add marginal accuracy improvement. Don't over-invest in expanding them.
3. The "consolidation signal" from R3 (deep docs → merge plugins) is not triggered. No plugin pair in the benchmark required page-level documentation to compose correctly. Keep all 49 plugins separate.
4. Monitor real instrumentation data (now that hooks are deployed) to validate these synthetic results. Create a follow-up bead for the definitive measurement after 2+ weeks of data collection.

## Caveats

1. **Sample size:** 5 tasks per category is directional, not statistically significant. The sequencing delta is so large (+70%) that it's likely real, but the discovery delta (+20%) could be noise.
2. **Synthetic bias:** Tasks were designed around known plugin relationships. Real-world tasks may have different distributions across the three categories.
3. **Name inference:** These plugins have descriptive names ("intersearch", "interwatch"). Poorly-named plugins would show larger discovery deltas.
4. **Model capability:** Opus 4.6 is strong at name inference. Haiku/Sonnet might show larger discovery gaps.
5. **Single run:** No repeated trials. Agent responses may vary across runs.

## Follow-Up Beads

- Create bead: "Audit real sessions for unhinted sequencing pipelines" (depends on interstat hook data)
- Create bead: "Repeat benchmark with Sonnet to test model-capability sensitivity"
