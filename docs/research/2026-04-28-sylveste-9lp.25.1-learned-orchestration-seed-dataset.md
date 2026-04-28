---
artifact_type: research
bead: sylveste-9lp.25.1
parent_bead: sylveste-9lp.25
stage: complete
produced_in_session: hermes-amtiskaw-discord-sylveste-qe8h
related_beads:
  - sylveste-qe8h
  - sylveste-rsj.3.5
  - sylveste-2aqs
  - sylveste-magy
  - sylveste-0h8
seed_data: docs/research/learned-orchestration/seed-examples-v0.jsonl
---

# sylveste-9lp.25.1 — learned orchestration seed dataset

## Verdict

**Conditional GO for a shadow evaluator harness; NO-GO for a learned coordinator.**

There is enough real Sylveste evidence to define the schema, seed a manual negative/positive corpus, and build a shadow-mode evaluator that emits records and cost/quality comparisons. There is **not** enough clean labeled data to train or trust a learned coordinator yet: route decisions, quality outcomes, acted-on/dismissed findings, and negative classes are still mostly prose, missing, or detached across Beads, interstat, and interspect.

Immediate next step is **sylveste-9lp.25.2**: design the policy-governed experiment around this schema. `sylveste-9lp.25.3` should start as a replay/evaluator that consumes these records and writes prediction receipts, not as an enforcing or training system.

## Alignment / Conflict

**Alignment:** This follows `PHILOSOPHY.md`: every routing/orchestration action should produce evidence, evidence earns authority, and authority stays scoped. Learned orchestration only proposes; Ockham/Clavain policy authorizes.

**Conflict/Risk:** Fugu/TRINITY/Conductor-style learned coordination is attractive, but opaque topology/model choices would violate Sylveste's evidence-first authority model unless they remain shadowed, replayable, and governor-bounded.

## Data inventory, 2026-04-28

| Surface | Current signal | Useful fields | Gaps |
|---|---:|---|---|
| Beads (`bd show`, `.beads/issues.jsonl`) | Richest semantic failure source | bead id, title, status, close reason, notes, labels, dependencies | Mostly prose; no uniform route/model/topology/cost/outcome fields |
| interstat (`~/.claude/interstat/metrics.db`) | 20,200 `agent_runs`; 689 flux-ish runs with tokens; 129 flux-ish sessions; 56 distinct non-empty beads; 475 flux-ish rows missing bead id | session_id, agent/subagent, model, token counts, wall time, bead_id, phase | Quality/outcome labels mostly absent; many rows have no bead id; no route proposal id |
| interspect (`.clavain/interspect/interspect.db`) | 1,314 evidence rows; 20 `verdict_outcome`; 743 `decomposition_outcome`; 211 advance / 198 cancel / 137 block | event, source, session, status, findings_count, model_used in context | 11/20 verdict outcomes contain `model_used: unknown`; acted_on/dismissed missing; dispatch linkage weak |
| `scripts/analyze-routing-experiments.py` | Replays interstat costs and role-aware projections | agent, model tier, token cost, projected tier, per-session cost | Cost-only; quality not joined; B2-shadow log input optional/not generally present |
| Research / handoff docs | Useful narrative evidence | failure story, design intent, decision, artifacts | Not structured enough for direct training |

Computed cost-only routing check: `python3 scripts/analyze-routing-experiments.py --format markdown` over 129 flux-ish sessions projected role-aware routing at **B1=$115.9199, B2=$147.6236, delta=-$31.7037 / -27.3% savings**. Treat that as a shadow-mode negative: role-aware escalation can increase cost unless quality improvement is proven.

## Compact schema

Seed records live at:

```text
docs/research/learned-orchestration/seed-examples-v0.jsonl
```

Each JSONL record uses this compact shape:

```json
{
  "example_id": "lo-seed-001",
  "source": {"kind": "bead|bead_pair|computed", "id": "...", "path": "..."},
  "label": "negative|negative_fixed|negative_open|negative_shadow_projection|instrumentation_gap|positive_control",
  "negative_classes": ["bad_model_route", "cost_blowup", "context_rot"],
  "task_features": {
    "domain": "model_routing|flux-review|tool_context_routing|...",
    "complexity": "C1-C5 or mixed",
    "risk": "phase-gate-integrity|context-budget|..."
  },
  "chosen_route": {
    "model": "model id or tier",
    "agent_type": "dispatcher/agent/tool if known",
    "topology": "parallel/staged/waterfall/fanout/etc",
    "policy": "policy state if known"
  },
  "alternative_route": {
    "model": "counterfactual if known",
    "topology": "counterfactual if known",
    "policy": "explicit governor/fallback/preflight"
  },
  "outcome": {"status": "open|closed_fixed|computed", "summary": "..."},
  "cost_observed": {"tokens": "...", "usd": "...", "latency": "..."},
  "quality_signal": {"source": "bead|sqlite|script", "value": "..."},
  "available_fields": ["model", "tokens", "summary_counter"],
  "missing_fields": ["acted_on", "dispatch confidence"],
  "usable_for": ["negative training", "cost policy", "positive control"]
}
```

### Negative class vocabulary v0

The vocabulary is intentionally multi-label and open to extension, but every class currently used by `seed-examples-v0.jsonl` is listed here.

- `bad_model_route` — selected model/provider was stale, unsupported, refused, or mismatched to task.
- `provider_error_hidden` / `silent_zero_token_success` — provider failure was swallowed into a normal-looking run receipt.
- `outcome_misclassification` / `false_pass` — orchestration summary classified WARN/error as success.
- `over_escalation` / `cost_blowout_if_enforced` — projected route increases cost without quality evidence.
- `under_escalation` — high-complexity work never reaches higher-capability model/tier.
- `missed_P0_P1` / `premature_phase_advance` — summary or gate allowed advancement despite serious warnings.
- `cost_blowup` / `context_overflow` — route/tool/topology consumed unbounded context/runtime.
- `bad_context_route` — context/tool format choice was wrong for the budget or task.
- `context_rot` / `stale_compact_context` — retrieved instructions omitted load-bearing protocol.
- `missed_orchestration_phase` — a required multi-agent protocol phase was absent from the routed context.
- `invalid_topology` / `duplicate_system` — orchestration created parallel subsystem or unsafe topology.
- `missed_prior_implementation` — planner/agent failed to retrieve shipped overlapping work before proposing new work.
- `recursive_overrun` / `fanout_blowup` — topology multiplied work without a budget/governor bound.
- `policy_refusal` / `fallback_required` — prompt/model topology triggered provider refusal and needed downgrade.
- `prompt_topology_invalid` — prompt/persona/targeting composition itself made the route unsafe or brittle.
- `routing_signal_unavailable` / `under_activation` / `no_production_callers` — routing code exists but callers do not feed it.
- `missing_quality_label` / `outcome_attribution_gap` — instrumentation captures events but not labels needed for learning.
- `unknown_model` — outcome data cannot be tied to the actual model/tier used.
- `stale_model_pin` — model route points at obsolete or deprecated model identifiers.
- `insufficient_quality_signal` — cost/route evidence exists but quality labels are too weak for a promotion decision.

## Seed set summary

| ID | Source | Label | Negative classes / role | Why it matters |
|---|---|---|---|---|
| lo-seed-001 | `sylveste-mb3i` | negative | `bad_model_route`, `provider_error_hidden`, `silent_zero_token_success` | Codex HTTP 400 for `gpt-5.3-codex-xhigh` was swallowed as a normal-looking 0-token run; learned coordinators must learn provider preflight + suspicious-zero guards. |
| lo-seed-002 | `sylveste-4cny` | negative | `false_pass`, `missed_P0_P1`, `premature_phase_advance` | 9/15 WARN verdicts were rolled into Passed, nearly allowing phase advance. |
| lo-seed-003 | `sylveste-sn7.2` | negative | `cost_blowup`, `context_overflow` | `get_screen` defaulted to `full` at ~12K tokens/call, overflowing agents by turn 6-7. |
| lo-seed-004 | `sylveste-s46z` | negative_fixed | `context_rot`, `missed_orchestration_phase` | Compact skill context dropped flux-drive Phase 2.5 reaction orchestration. |
| lo-seed-005 | `sylveste-9gn9` | negative_fixed | `duplicate_system`, `missed_prior_implementation` | Persona-lens ontology PRD duplicated 87%-shipped interweave/lattice work; human policy decision SUBSUME cut estimated work ~10.5w → ~6w. |
| lo-seed-006 | `sylveste-x7c0` | negative_fixed | `recursive_overrun`, `fanout_blowup`, `cost_blowup` | Per-client tmux status topology caused ~136 concurrent processes; cache daemon collapsed it to 0. |
| lo-seed-007 | `sylveste-jfuy` | negative_fixed | `stale_model_pin`, `under_escalation` | Auraken pinned old Claude IDs and never routed Opus despite high-complexity need. |
| lo-seed-008 | `sylveste-efyo` | negative_fixed | `policy_refusal`, `fallback_required`, `prompt_topology_invalid` | Opus 4.7 refused tracks A/D under persona + AI-lab targeting prompt topology; fallback and prompt-policy rewrite shipped. |
| lo-seed-009 | `sylveste-2aqs` + `sylveste-magy` | negative_open | `under_activation`, `routing_signal_unavailable` | B2 routing exists but dispatch callers still do not feed it. |
| lo-seed-010 | `scripts/analyze-routing-experiments.py` + interstat | negative_shadow_projection | `over_escalation`, `cost_blowout_if_enforced` | Role-aware projection over 129 sessions increased cost by 27.3%; keep shadow until quality evidence exists. |
| lo-seed-011 | interspect evidence | instrumentation_gap | `missing_quality_label`, `unknown_model` | Verdict outcomes exist, but more than half have unknown model and lack acted_on/dismissed labels. |
| lo-seed-012 | `sylveste-fyo3.3` | positive_control | policy floor respected | Cross-model dispatch reached enforce mode with checker-tier non-Claude routing while safety floors stayed Sonnet+. |
| lo-seed-013 | `sylveste-qdg` | positive_control | confidence cascade | Multi-model waterfall has explicit thresholds and latency guard: small model → larger → cloud. |
| lo-seed-014 | `sylveste-axo3` | positive_control | policy-governed trigger path | Ockham composes anomaly signals through confirmation + policy before CONSTRAIN/release actions. |

## B2/B3 linkage

This dataset should become the training/evaluation input format for the B2/B3 route loop:

1. **B2 complexity-aware routing** needs raw task features (`prompt_tokens`, `file_count`, `reasoning_depth`, domain, phase, risk) and actual outcomes. `sylveste-2aqs` / `sylveste-magy` are therefore prerequisites for future automated examples: without caller injection, examples cannot reliably contain the chosen route features.
2. **B3 adaptive routing** needs verdict outcomes (`acted_on`, `dismissed`, severity, finding type), token/cost actuals, and fallback decisions. Today interstat and interspect are complementary but not joined tightly enough.
3. **Shadow evaluator** should compare: static route, B2 route, B3 route, and learned proposal. It must report false pass, missed warning, over-escalation, under-escalation, context blowup, and policy rejection counts.

## Fugu / TRINITY / Conductor implications

From `sylveste-qe8h`, learned orchestration is relevant but should enter Sylveste as a **proposal layer**, not an authority layer.

- **Fugu-style learned coordinator:** useful target shape for topology/model proposal, but too opaque for direct dispatch authority.
- **TRINITY-style Thinker/Worker/Verifier:** maps well to Sylveste's existing sparse multi-agent review pattern; examples need role/topology labels before comparison.
- **Conductor-style generated workflows:** maps to experiment/topology proposals; must be bounded by explicit access lists, budgets, recursion limits, and Ockham/Clavain gates.
- **Agentica/Arcgentica (`sylveste-rsj.3.5`):** should be included in `sylveste-9lp.25.2` as the comparator for stateful REPL, compressed subagent summaries, and parallel hypothesis exploration.

## Instrumentation required before training or enforce-mode

Minimum additions for future real examples:

1. **Route decision receipt** at every dispatch point:
   - `route_id`, `bead_id`, `phase`, `task_hash`, `agent`, `chosen_model`, `chosen_topology`, `route_source` (`static|B2|B3|learned_proposal|manual_override`), `policy_gate`, `fallback_chain`.
2. **Task feature capture**:
   - `prompt_tokens`, `file_count`, `diff_size`, `reasoning_depth`, `risk_level`, `requires_tools`, `requires_write`, `domain`, `phase`.
3. **Outcome join key**:
   - Interstat `agent_runs`, interspect `verdict_outcome`, Beads issue, and artifacts should share `route_id` or `dispatch_id`.
4. **Quality labels**:
   - `acted_on`, `dismissed`, `false_positive`, `false_negative`, `severity`, `human_override`, `post_merge_defect`, `rework_required`.
5. **Negative labels**:
   - explicit multi-label `negative_classes` from the vocabulary above, with `labeler`, `confidence`, and freeform rationale.
6. **Governor decision**:
   - for every learned proposal: `authorized|shadow_only|blocked`, reason, budget delta, safety-floor check, recursion/topology bound.

## Recommendation

- **Do now:** use `seed-examples-v0.jsonl` as the canonical v0 hand-labeled corpus for `sylveste-9lp.25.2`.
- **Do next:** design the experiment so the learned coordinator only emits proposals and governor decisions in shadow mode.
- **Do not do yet:** train a learned coordinator, buy into Fugu API dependency, or change production routing based on this seed set.
- **Go/no-go for `sylveste-9lp.25.3`:** GO only for a replay/shadow evaluator that consumes this schema and emits prediction receipts; NO-GO for enforce mode or learned autonomous routing until at least ~30 joined, labeled route/outcome examples per major negative class exist.
