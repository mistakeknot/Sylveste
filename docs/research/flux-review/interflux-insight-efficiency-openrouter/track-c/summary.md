# Flux Drive Review — interflux-insight-efficiency-openrouter (Track C: Distant Domain Agents)

**Reviewed**: 2026-04-06 | **Agents**: 4 dispatched, 4 completed | **Verdict**: needs-changes

**Track focus**: Structural isomorphisms from distant knowledge domains — Venetian glassmaking, Javanese gamelan, Korean onggi pottery, and medieval assay verification.

---

### Verdict Summary

| Agent | Status | Summary |
|-------|--------|---------|
| fd-murano-furnace-workshop-allocation | NEEDS_ATTENTION | No explicit task-criticality taxonomy; routing uses finding-volume signals, not nature-of-cognitive-work signals |
| fd-javanese-gamelan-tuning-interference | NEEDS_ATTENTION | Synthesis dedup destroys model provenance; productive ombak (cross-model disagreement as signal) has no collection mechanism |
| fd-korean-onggi-microbial-terroir | NEEDS_ATTENTION | No failure isolation for OpenRouter Bash-dispatch; prompt monoculture will suppress multi-model analytical diversity |
| fd-assay-master-multi-method-verification | NEEDS_ATTENTION | Synthesis presents conflicts without judgment calls; full parallelism ignores cost-ordered staging opportunity |

---

### Critical Findings (P0)

None.

---

### Important Findings (P1) — 7 total

**[P1-A]** No task-criticality taxonomy protecting judgment-critical agents from cost-driven model reassignment
*(fd-murano: MUR-1, MUR-2 | 2/4 agents)*

The proposed OpenRouter routing has no explicit taxonomy that distinguishes "judgment-critical" agents (fd-decisions, fd-safety, fd-correctness — require nuanced reasoning) from "mechanical-procedural" agents (fd-quality, fd-perception — checklist verification, pattern scanning). Current cross-model dispatch in `phases/expansion.md` routes by `expansion_score` and `pressure_label` (finding volume and budget pressure), not by the nature of the cognitive work required. A review under budget pressure will route fd-decisions to DeepSeek because the pressure signal fires, even though fd-decisions requires natural language nuance that many cheap models lack. **Smallest fix**: Add `config/flux-drive/agent-tiers.yaml` with explicit `judgment_critical`, `standard_analytical`, `mechanical_procedural` categories; the cross-model dispatch safety floor in `expansion.md` Step 2.2c should consult this taxonomy before any tier adjustment.

**[P1-B]** Synthesis destroys model provenance — cross-model corroboration and disagreement are untracked
*(fd-javanese: GAM-1 | fd-assay: ASY-3 | 2/4 agents)*

The five dedup rules in `phases/synthesize.md` Step 3.3 and the `findings.json` schema (Step 3.4a) do not capture `model_family` per finding. This means: (a) Claude Haiku + Claude Sonnet converging on a finding produces the same `convergence: 2` as Claude Sonnet + DeepSeek V3 converging — but the latter is an order-of-magnitude stronger signal, and (b) the "model diversity as a signal" hypothesis from the input document is structurally impossible to implement without provenance tracking. **Smallest fix**: Add `model_family: "anthropic|deepseek|qwen|..."` to the `findings.json` finding schema and a `cross_family_convergence` count. Two lines of schema change; synthesis dedup Rule 1 adds one group-by clause.

**[P1-C]** Synthesis makes no judgment call on cross-model conflicts — hallmark left unstamped
*(fd-assay: ASY-1 | 1/4 agents)*

Synthesis Rule 5 ("Conflicting recommendations → preserve both with attribution") is correct for same-family conflicts but wrong for cross-model conflicts where one model has a known capability gap. A Claude Sonnet P1 vs DeepSeek P2 conflict currently produces "Claude says X, DeepSeek says Y" with no verdict — delegating the epistemological integration back to the user who came to the review system to avoid doing that work. **Smallest fix**: Add a judgment mandate to the `intersynth:synthesize-review` prompt: for cross-model conflicts where `model_family` differs, the synthesis must state which assessment it accepts and why, not merely present both. Initially "accept the higher-trust model family's assessment, note the discrepancy."

**[P1-D]** No failure isolation for Bash-dispatched OpenRouter agents — API timeout can stall flux-watch.sh
*(fd-korean-onggi: ONG-1 | 1/4 agents)*

`phases/launch.md` Step 2.3 monitors completion via `flux-watch.sh {OUTPUT_DIR} {N} {TIMEOUT}`. For Claude subagents (Agent tool with `run_in_background: true`), process lifecycle is managed independently. For OpenRouter agents dispatched via Bash tool API calls, the Bash call itself is synchronous — a 30-second DeepSeek API timeout delays the orchestrator for 30 seconds. The current retry logic (retry once with `run_in_background: false`) does not handle API errors, rate limits, or JSON parse failures from external providers. **Smallest fix**: Wrap OpenRouter Bash dispatch in a `timeout 30` shell command with immediate error-stub writing on failure. The stub (`Verdict: error`, `<!-- flux-drive:complete -->`) keeps flux-watch.sh's file count correct and synthesis proceeds gracefully.

**[P1-E]** Uniform Claude-designed prompt templates will produce prompt monoculture in non-Claude models
*(fd-korean-onggi: ONG-2 | fd-javanese: GAM-3 | 2/4 agents)*

The `skills/flux-drive/references/prompt-template.md` template is designed for Claude's analytical style and response patterns. Sending it unchanged to DeepSeek or Qwen constrains those models to behave like Claude, suppressing the analytical diversity that is the primary justification for multi-model dispatch. This manifests in two ways: (1) models may not naturally produce the exact `### Findings Index` / `<!-- flux-drive:complete -->` structure, causing Step 3.1 "Malformed" classification; (2) models that do comply will produce Claude-imitative outputs rather than leveraging their own analytical strengths. **Smallest fix**: Create `config/flux-drive/model-prompts/` with per-family variants that differ only in analytical framing while keeping identical required output format. DeepSeek variant emphasizes concrete code paths; Qwen variant emphasizes checklist-style structured analysis.

**[P1-F]** All model tiers dispatch simultaneously — no cost-ordered staging where cheap models inform expensive dispatch
*(fd-assay: ASY-2 | 1/4 agents)*

The staged dispatch (Stage 1 → expansion → Stage 2) gates on finding-volume signals but within each stage all models fire simultaneously. In a heterogeneous fleet, cheap models (DeepSeek at $0.001/1K tokens) completing first could inform whether expensive models (Claude Opus at $0.075/1K tokens) are needed in the same domain. A clean cheap-model verdict reduces but does not eliminate the need for expensive confirmation; a P0 from a cheap model urgently justifies it. Currently these two outcomes are treated identically — both result in the same expensive dispatch. **Smallest fix**: Add `cheap_first: enabled` mode to `budget.yaml` cross-model dispatch config with a 60-second wait window after cheap-tier agents complete; dispatch expensive-tier agents in the same domain only if cheap found P0/P1.

---

### Improvements Suggested (P2–P3)

1. **Model blind-spot profiles** (fd-assay, GAM-4, ASY-4): Accumulate per-model-family empirical profiles of systematic over-flag/under-flag tendencies by finding domain. Store in `config/flux-drive/model-blind-spots.yaml`. Synthesis uses these profiles to weight findings appropriately — a DeepSeek P1 performance finding in a known over-flag category carries a prior. This is a long-term infrastructure investment but the data collection can start immediately (log every cross-family disagreement with domain and severity delta).

2. **Baseline disagreement profiles for model pairs** (fd-javanese, GAM-4): After enough reviews, compute expected inter-family disagreement rates per domain (e.g., "Claude-DeepSeek baseline disagreement on performance findings: 18%"). Surface as "Current disagreement: 35% (baseline: 18%) — elevated discord in performance domain" in the synthesis report. Distinguishes normal ombak from unusual discord.

3. **Finding density tracking for cheap models** (fd-murano, MUR-4): Track `finding_density = findings_count / output_tokens` per agent per model tier. Flag agents where cheap-model density is significantly below baseline for that agent type — may indicate the cheap model did less work (short output) rather than found less (clean code).

4. **Context budget per model family** (fd-korean-onggi, ONG-3): Before dispatching to OpenRouter, check prompt token estimate against model context limit. Force aggressive slicing if prompt exceeds 80% of the model's context window. Prevents silent mid-document truncation.

5. **Model version pinning** (fd-korean-onggi, ONG-4): Pin model versions in routing config (`deepseek/deepseek-chat-v3` not `deepseek/deepseek-chat`) and add periodic capability probe to detect version drift. Stale capability assumptions degrade routing quality silently.

---

### Section Heat Map

| Section | P1 Issues | P2 Issues | Agents Reporting |
|---------|-----------|-----------|-----------------|
| Synthesis / dedup rules | 2 (P1-B, P1-C) | 1 | fd-javanese, fd-assay |
| OpenRouter infrastructure | 2 (P1-D, P1-E) | 1 | fd-korean-onggi, fd-javanese |
| Cross-model dispatch / routing | 2 (P1-A, P1-F) | 1 | fd-murano, fd-assay |
| Model diversity signal | 0 | 2 | fd-javanese, fd-assay |

---

### Conflicts

No direct conflicts between agents. The four domain lenses are cleanly partitioned and complementary:
- **Murano** focused on the delegation hierarchy (which tasks need which tier) — no overlap with the other three
- **Gamelan** focused on inter-model disagreement as signal — distinct from Murano's skill hierarchy and Onggi's infrastructure
- **Onggi** focused on infrastructure (failure isolation, prompt environment, context permeability) — distinct from signal/epistemology concerns
- **Assay** focused on synthesis epistemology (judgment calls, cost-ordered staging, blind spots) — distinct from infrastructure concerns

The four agents corroborated on two structural gaps: prompt monoculture (Gamelan GAM-3 + Onggi ONG-2) and model provenance in synthesis (Gamelan GAM-1 + Assay ASY-3). Cross-agent convergence on these two points increases confidence they are genuine structural gaps rather than lens artifacts.

---

### Cross-Domain Structural Isomorphisms

The four distant-domain lenses converge on a single meta-pattern invisible from within the AI domain:

**The diversity-capture problem**: Every domain reveals that the value of heterogeneous participants is only realized if the system is explicitly designed to *preserve and amplify* the heterogeneity, rather than standardizing inputs (prompt monoculture, Onggi/Gamelan), aggregating outputs (synthesis without provenance, Assay/Gamelan), or routing by the wrong signal (volume pressure instead of task nature, Murano). The Venetian maestro who insists on identical techniques from all workers gets consistent but shallow glass. The gamelan tuned to unison sounds dead. The onggi with uniform porosity produces flat fermentation. The Wardein who averages test results without knowing which test measures what hallmarks debased metal.

Applied to interflux + OpenRouter: **the multi-model fleet will be valuable only if the architecture explicitly captures, preserves, and integrates the provenance of heterogeneous outputs**. Without model_family tracking in findings, provenance-aware dedup, model-adapted prompts, and judgment-stamped synthesis, the heterogeneous fleet is operationally equivalent to a same-family fleet with higher complexity and lower reliability.

---

### Files

- Summary: `docs/research/flux-review/interflux-insight-efficiency-openrouter/track-c/summary.md`
- Individual reports:
  - [fd-murano-furnace-workshop-allocation](./fd-murano-furnace-workshop-allocation.md) — P1: no task-criticality taxonomy; routing uses wrong signals
  - [fd-javanese-gamelan-tuning-interference](./fd-javanese-gamelan-tuning-interference.md) — P1: synthesis destroys model provenance; no ombak-signal collection
  - [fd-korean-onggi-microbial-terroir](./fd-korean-onggi-microbial-terroir.md) — P1: no failure isolation for OpenRouter dispatch; prompt monoculture risk
  - [fd-assay-master-multi-method-verification](./fd-assay-master-multi-method-verification.md) — P1: synthesis abdicates judgment on conflicts; missed cost-ordered staging
