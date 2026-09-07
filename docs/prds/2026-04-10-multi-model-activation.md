---
artifact_type: prd
bead: sylveste-fyo3
stage: strategy
---

# PRD: Multi-Model Activation — Critical Path + Calibration

## Problem

interflux has a complete multi-model dispatch architecture (shadow routing, FluxBench qualification pipeline, model discovery, challenger slots) but zero real models in production. `model-registry.yaml` has `models: {}`, `fluxbench-qualify.sh` rejects non-mock runs (line 44), and `cross_model_dispatch.mode` is stuck on `shadow`. The entire feedback loop — discover candidates, qualify them, route real reviews — has never executed end-to-end.

## Solution

Build the thin vertical slice that activates the feedback loop: an OpenRouter MCP server for non-Claude inference, real model dispatch in FluxBench, a first discovery run to populate candidates, and the shadow→enforce switch. Then calibrate the baseline by running FluxBench against Claude (the known-good reference) and wiring the challenger slot into the dispatch loop.

## Revised Critical Path

```
F1 (MCP server) ─┬─► F5 (Claude calibration) ─► F2 (real qualify) ─► F4 (enforce)
                  │
F3 (discovery) ───┘   F6 (challenger wiring) ─► requires F2 + F5
```

F3 (discovery) runs in parallel with F1 — it depends only on interrank MCP (already exists), not OpenRouter. F5 (Claude calibration) is promoted to P1 and precedes F2, because qualification thresholds must be empirically derived before any candidate is evaluated.

## MCP Invocation Contract

**Root architectural decision** (resolves the script↔MCP gap identified in review):

Shell scripts (qualify.sh, calibrate.sh, discover-models.sh) cannot call MCP tools directly — MCP is only available inside a Claude Code agent loop. Two options:

1. **Orchestrator pattern** (like discover-models.sh): script emits JSON tool-call descriptors to stdout, a SKILL.md instruction block drives the MCP calls and feeds responses back via stdin/tempfiles.
2. **CLI wrapper**: MCP server also exposes a CLI mode (`node index.js --model x --prompt-file y`) so scripts can subprocess it directly.

**Decision: Orchestrator pattern.** Rationale: it matches the existing discover-models.sh design, keeps the MCP server purely MCP (single responsibility), and avoids duplicating request/response logic in a CLI entrypoint. All FluxBench scripts that need model inference will output JSON descriptors; a `fluxbench-orchestrate` SKILL.md block reads them and drives the MCP calls.

This means:
- `fluxbench-qualify.sh` in real mode outputs `{tool, params, fixture_id}` JSON lines instead of making HTTP calls
- A SKILL.md orchestration block reads these, calls `review_with_model` via MCP, writes responses to `work_dir/fixture-N/response.md`
- `fluxbench-score.sh` runs after all responses are collected (unchanged)
- `fluxbench-calibrate.sh` follows the same pattern for Claude native dispatch (uses Agent tool instead of MCP)

## Features

### F1: OpenRouter Provider Integration (fyo3.4) — P1

**What:** Build an `openrouter-dispatch` MCP server that exposes a `review_with_model` tool, allowing FluxBench and flux-drive to dispatch review prompts to any OpenRouter-supported model.

**Acceptance criteria:**
- [ ] MCP server exists at `interverse/interflux/mcp-servers/openrouter-dispatch/` with `index.ts` (TypeScript — matches Claude Code MCP SDK ecosystem; Exa server is also a Node.js launch script)
- [ ] Exposes `review_with_model` tool accepting `{model_id, prompt, system_prompt, max_tokens}`
- [ ] Returns structured response: `{content, model, tokens_used, latency_ms}`
- [ ] Reads `OPENROUTER_API_KEY` from environment (fails with "OPENROUTER_API_KEY not set" — never logs the key value in error output)
- [ ] API key must be model-scoped: document in README that operators should create a key restricted to model IDs matching registry's active models
- [ ] Client-side rate limiting: token-bucket enforcing `providers.openrouter.rate_limit` (default 20/min) before HTTP call, not after
- [ ] On 429 from OpenRouter: return error (caller decides retry/skip), do not retry inline
- [ ] `spend_ceiling_usd` field read from provider config; MCP server tracks cumulative spend via OpenRouter `usage` response field and halts on breach
- [ ] Registered in interflux `plugin.json` under `mcpServers` with `"env": {"OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}"}`
- [ ] Progressive enhancement: downstream scripts detect MCP availability before attempting calls

**Content policy:**
- [ ] Each model entry in `model-registry.yaml` has a `prompt_content_policy` field: `fixtures_only` (default) | `sanitized_diff` | `full_document`
- [ ] MCP server enforces policy: if caller passes `content_policy_override` that exceeds the model's configured policy, reject with error
- [ ] Challenger slot in F6 inherits the model's content policy — no live code is sent unless operator explicitly sets `full_document`

**Dependencies:** OpenRouter API key provisioned (model-scoped)

### F5: Claude Baseline Calibration (fyo3.8) — P1 (promoted from P2)

**What:** Run `fluxbench-calibrate.sh` against Claude as the baseline model using the orchestrator pattern. This establishes empirically-derived thresholds that all candidate models are measured against. Must run before any candidate qualification (F2).

**Acceptance criteria:**
- [ ] `fluxbench-calibrate.sh` in real mode outputs JSON descriptors for Claude inference; orchestrator drives Agent tool calls
- [ ] Claude reviews each fixture document using the agent persona from agent-roles.yaml
- [ ] Claude's actual responses (not ground-truth copies) are scored by `fluxbench-score.sh`
- [ ] Calibration thresholds written to `fluxbench-thresholds.yaml` with `source: claude-baseline` and `calibrated_at` timestamp
- [ ] All 5 core FluxBench gates computed from real Claude output: format_compliance, finding_recall, false_positive_rate, severity_accuracy, persona_adherence
- [ ] persona_adherence: implement the Haiku LLM-judge call (fixture response + agent persona → 0-1 score), or demote to `gate: false` in fluxbench-metrics.yaml with explicit rationale
- [ ] Guard: calibrate.sh refuses to write thresholds that are worse than existing `source: defaults` values (prevents mock-mode regression)
- [ ] Re-running with `--force` overwrites previous baseline (idempotent)

**Dependencies:** F1 not required (Claude uses native Agent tool dispatch, not OpenRouter MCP)

### F2: Real Model Dispatch in qualify.sh (fyo3.1) — P1

**What:** Replace the `--mock` gate in `fluxbench-qualify.sh` with orchestrator-pattern output. When run without `--mock`, the script outputs JSON descriptors for each fixture; the orchestrator calls `review_with_model` via MCP and writes responses back.

**Acceptance criteria:**
- [ ] `fluxbench-qualify.sh <model-slug>` (no `--mock`) outputs JSON tool-call descriptors to stdout
- [ ] Orchestrator (SKILL.md block) reads descriptors, calls `review_with_model`, writes responses to `work_dir/fixture-N/response.md`
- [ ] Response format identical to mock responses (no format-specific branching in score.sh)
- [ ] `fluxbench-score.sh` processes real responses against Claude-calibrated thresholds from F5
- [ ] Registry records `qualified_via: real` on successful qualification, `qualified_via: mock` for mock runs
- [ ] Timeout per fixture: 120s (configurable via `FLUXBENCH_FIXTURE_TIMEOUT`); timeout counts as fixture failure
- [ ] Partial pass strategy: all fixtures must complete without timeout for overall pass; 4/5 is a fail (but logged for operator review)
- [ ] On MCP unavailability: exit 1 with "OpenRouter MCP not available — use --mock for testing"
- [ ] `--mock` continues to work unchanged (regression test); mock-qualified models clearly marked `qualified_via: mock`

**Dependencies:** F1 (MCP server), F5 (calibrated thresholds)

### F3: First Real Model Discovery Run (fyo3.2) — P1 (parallelizable with F1)

**What:** Execute `discover-models.sh` end-to-end: generate interrank queries, have orchestrator execute them via interrank MCP, merge Pareto-efficient candidates into `model-registry.yaml` with `status: candidate`.

**Acceptance criteria — query generation (existing script):**
- [ ] `discover-models.sh --force` outputs valid JSON tool-call descriptors for interrank MCP
- [ ] Budget filter respected: only requests models below `model_discovery.budget_filter` threshold
- [ ] Confidence filter: only requests models above `model_discovery.min_confidence`

**Acceptance criteria — orchestrator merge (new):**
- [ ] Orchestrator (SKILL.md block or new `discover-merge.sh`) executes interrank MCP calls from the query JSON
- [ ] Pareto-efficient candidates written to `model-registry.yaml` with all required fields: provider, model_family, eligible_tiers, status (`candidate`), discovered date, interrank_score, cost_per_mtok, `prompt_content_policy: fixtures_only` (default)
- [ ] `last_discovery` and `last_discovery_source` updated in registry
- [ ] Duplicate detection: re-running does not create duplicate entries for same model_id
- [ ] Operator confirmation: new model slugs are displayed before registry write (not auto-committed)

**Dependencies:** interrank MCP server (already exists). No dependency on F1/OpenRouter.

### F4: Activate Cross-Model Dispatch — Shadow to Enforce (fyo3.3) — P1

**What:** Switch `cross_model_dispatch.mode` from `shadow` to `enforce` in budget.yaml so that Stage 2/expansion agents are dispatched at their computed model tier.

**Scope clarification:** In this iteration, enforce mode applies Claude tier adjustments (haiku↔sonnet↔opus routing based on expansion score, domain complexity, budget pressure). It does NOT yet substitute OpenRouter models for Claude tier slots — that integration layer (registry-aware dispatch) is a follow-on feature. The value of enforce is: cheaper Claude tiers for low-stakes agents, more expensive tiers for high-stakes agents, based on evidence.

**Acceptance criteria:**
- [ ] `budget.yaml` has `cross_model_dispatch.mode: enforce`
- [ ] Pre-flight gate: a validate script checks that at least one model in `model-registry.yaml` has `status` in (`auto-qualified`, `qualified`, `active`) AND `qualified_via: real` — blocks enforce if only mock-qualified models exist
- [ ] `enforce_since` timestamp written to budget.yaml when mode is first set (for incident scoping)
- [ ] flux-drive Phase 2.2c reads mode and applies tier adjustments when `enforce`
- [ ] Safety floors enforced: fd-safety and fd-correctness never below Sonnet regardless of tier computation
- [ ] Rollback: changing `mode: shadow` stops future dispatch adjustments. Note: rollback applies to future reviews only; reviews dispatched under enforce are not re-reviewed automatically
- [ ] Shadow proxy log lines changed from `[shadow-proxy]` to `[enforce]` prefix

**Signpost for full registry dispatch (future):** When ≥3 models are qualified across ≥2 distinct tiers via `qualified_via: real`, build the integration layer that substitutes registry models for Claude tier slots.

**Dependencies:** F2 (at least one model with `qualified_via: real`), F5 (calibrated thresholds)

### F6: Challenger Slot Wiring (fyo3.9) — P2

**What:** Connect `fluxbench-challenger.sh` to the flux-drive dispatch loop. During real reviews, the challenger model is dispatched alongside regular agents using the orchestrator pattern, and its output is scored automatically.

**Scope note:** This IS a change to the dispatch architecture — specifically, it adds a new dispatch branch in Phase 2 for challenger agents. The non-goal "no changes to the 3-phase lifecycle or triage algorithm" still holds; challenger injection is additive within Stage 2, not a structural change to triage or phase boundaries.

**Acceptance criteria:**
- [ ] `fluxbench-challenger.sh select` picks the highest-scoring candidate with `qualified_via: real` (rejects mock-qualified)
- [ ] During flux-drive Phase 2, if `challenger.enabled` and a challenger is selected, dispatch the challenger agent via orchestrator pattern alongside Stage 2 agents
- [ ] Challenger receives prompts constrained by its `prompt_content_policy` — default `fixtures_only` means no live code unless operator explicitly upgrades
- [ ] Challenger output written to `fluxbench-results.jsonl` with model_slug, fixture scores, timestamps (explicit write path, not just "not discarded")
- [ ] After `promotion_threshold` (10) real runs, `fluxbench-challenger.sh evaluate` promotes or rejects
- [ ] `safety_exclusions` enforced: challenger never fills fd-safety or fd-correctness slots
- [ ] Early exit at run 5 if passing by `early_exit_margin` (0.20)
- [ ] Stale rejection after `stale_threshold` (20) runs without passing
- [ ] Graceful degradation: if OpenRouter MCP times out mid-review, skip the challenger for this cycle and log; do NOT abort the parent flux-drive session

**Dependencies:** F2 (real qualification), F5 (calibrated baseline for scoring)

## Non-goals

- Changing the 3-phase lifecycle or triage algorithm (challenger injection is additive, not structural)
- Registry-aware dispatch: substituting OpenRouter models for Claude tier slots (follow-on after ≥3 models qualified across ≥2 tiers)
- Supporting providers other than OpenRouter for this iteration
- Automated weekly discovery cron (fyo3.10 — deferred; F3 in this iteration requires manual operator invocation)
- Oracle cross-AI review integration (fyo3.11 — deferred)
- Fleet drift coordination (fyo3.5 — deferred, but note: fyo3.5 must be in_progress before enforce has been active for more than 50 reviews)
- Hard budget enforcement (fyo3.6), interspect overlay (fyo3.7) — deferred

## Dependencies

- **OpenRouter API key** — must be model-scoped and available as `OPENROUTER_API_KEY`
- **interrank MCP** — already exists as plugin, needed for F3 discovery queries
- **FluxBench fixtures** — already exist at `tests/fixtures/qualification/`
- **interflux plugin** — all scripts and configs in place, need modification not creation

## Resolved Questions (from review)

1. **MCP server language:** TypeScript. The Exa MCP server uses a Node.js launch script, and the Claude Code MCP SDK is TypeScript-native. Consistent with ecosystem.
2. **MCP invocation from bash:** Orchestrator pattern. Scripts output JSON descriptors; a SKILL.md block drives the MCP calls. Matches discover-models.sh precedent.
3. **Claude baseline dispatch:** Uses native Agent tool (not MCP). F5 has no dependency on F1.
4. **Staging strategy:** One model with `qualified_via: real` is sufficient for the enforce switch. But enforce in this iteration only adjusts Claude tiers — it doesn't yet substitute registry models for Claude slots. Full registry dispatch gated on ≥3 models across ≥2 tiers.
5. **Mock vs real qualification tracking:** `qualified_via: real|mock` field added to registry. Enforce gate requires `qualified_via: real`.
6. **Content policy:** Per-model `prompt_content_policy` field. Default `fixtures_only`. Operator must explicitly upgrade to `full_document` per model.

## Open Questions

1. **persona_adherence gate:** Implement the Haiku LLM-judge call (adds ~$0.01/fixture), or demote to informational metric? Leaning implement — it's only 5 fixtures.
2. **Drift monitoring timeline:** fyo3.5 deferred but flagged as must-start before 50 enforce-mode reviews. Is 50 the right threshold, or should it be time-based (2 weeks)?
