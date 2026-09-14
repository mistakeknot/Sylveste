---
artifact_type: frontier-delta
date: 2026-09-14
method: 2 Explore agents over the monorepo (docs/, scripts/, .claude/, .beads/issues.jsonl; plugins absent in the cloud checkout) + 21 primary/secondary web sources dated 2026-07..09
predecessors: docs/research/2026-06-21-agentic-frontier-roadmap-delta.md, docs/research/2026-07-16-ecosystem-research-agenda.md
scope: token efficiency, context management, code/product/design quality
---

# Frontier Harness Delta — 2026-09-14

**Method.** Re-scan of the agentic-harness frontier since the 2026-06-21 delta, restricted to three
levers the owner named: **token efficiency**, **context management**, **code/product/design
quality**. Each external finding is mapped against what the estate already has (path:line) and
against open beads, then classified P1 (corrective / measurement — do now), P2 (experiment with a
metric and a kill rule), or P3 (watch item / spike). Anything that would add capability ahead of a
consumer is dropped, per the June delta's "ghost infrastructure" warning.

**What shipped in the window (2026-07-01 → 2026-09-14):** Claude Fable 5.1 (GA 2026-09-01,
1M context, cache reads at 0.025× base); Claude Code 2.1.251 → 2.1.270 (prompt-cache telemetry,
`/skill-doctor`, `claude plugin eval`, effort caps, `PreModelSwitch` hooks, a dozen cache-break
fixes); Managed Agents *Outcomes* + *Dreaming*; MCP spec 2026-07-28 (stateless core, cacheable
lists, Roots/Sampling/Logging deprecated); OpenAI GPT-6-Astra + Codex Agents API; Gemini 3.8 Flash
and the Gemini CLI → Antigravity CLI sunset; Kimi K2.7-Code (open weights); DeepSeek V4 / GLM-5.2 /
Qwen 3.6; and two harness-variance papers (arXiv 2605.23950, 2602.14690) plus GitHub's Copilot
harness-efficiency study.

## Ground truth (verified against the repo and `.beads/issues.jsonl` on 2026-09-14)

- **The estate's only live cost instrument is dead.** `scripts/validate_oyrf_cost_infra.py:257`
  asserted `actions/checkout@v4`; `545e9ce` bumped the workflow to `@v7`, so every 6-hourly OYRF
  run (543 recorded) has failed on its own self-check. Fixed in this PR. Even a green run writes an
  `interstat-empty` row in CI because `interverse/` is gitignored (`estimate-costs.sh:14`);
  `data/cost-trajectory.csv` holds **one real row, 2026-04-30, all zeros**. `sylveste-oyrf` (P3,
  `docs/sylveste-roadmap.md:71`) is the bead.
- **The north-star baseline is 6.5 months old and in the wrong units.**
  `docs/measurements/2026-02-28-north-star-baseline.md`: $1.17 and 22,576 tokens per landable
  change on `claude-opus-4-6`; **output-dominated** — 593K output vs 39K billed input, output ≈ 97%
  of cost; Explore subagents 25.5% of tokens. The tokenizer changed at Opus 4.7 (~30% more tokens for
  the same text), so the token figure is not comparable to anything measured today.
- **No cache-hit-rate metric exists anywhere** (`sylveste-7aj8.9`: collector drops ~97% of rows;
  `api_coverage_pct=0`), despite `sylveste-129h` (cache-corrected north star) and the documented
  600× billing-vs-context divergence (`docs/plans/2026-02-16-token-budget-controls.md:423`).
- `docs/calibration-stages.yaml`: `cost_estimation` and `agent_routing` both at **stage 2 of 4**,
  `stage_3: null`. B2 routing is still shadow (`sylveste-xka6`, P2, `docs/sylveste-roadmap.md:67`).
- 341 generated `fd-*` lens agents were pruned in #98 with `use_count: 0`; `sylveste-b1ha` (unify
  with Auraken lenses) is open, so the quality-gate fleet is in flux.
- Already-landed machinery this delta builds on rather than re-proposes: the close-gate
  (`sylveste-6h7x`, **closed**); routing-table v2 phase overrides (`Sylveste-0pk`, **closed**); the
  April deferred-tool + skill-compact audit (`sylveste-ynh7`, **closed**); the CI-enforced 33 KB
  skill-listing budget (`scripts/check-skill-listing-budget.sh`); `routing.yaml` with
  `subagents:`/`dispatch:` tiers; interspect's F1–F5 override chain; the `PreCompact` re-prime hook
  (now firing on auto compaction too — this PR).
- Doctrine to cite, already written: *Measurement before optimization*, *Efficiency = quality*,
  *Goodhart optimization*, *Review theater* (`agents/design-doctrine.md`).

---

## Headline

1. **The cost lever moved to output, which is where the estate already spends.** Fable 5.1's
   headline cut is cache *reads* (0.025× base vs 0.1× elsewhere) — that helps the context side of a
   long session. But the estate's own baseline says ~97% of spend is *output*, and Fable 5.1 ships
   two documented behaviours that inflate output: whole-file rewrites for small edits and one tool
   call per turn in coding loops. The cheapest wins in this window are therefore **effort control**
   (`/effort` no longer breaks the cache on Fable 5.1; per-message effort is in beta; `maxEffortLevel`
   caps spend) and the three prompting lines Anthropic published for exactly these behaviours (now in
   `AGENTS.md` → **Token discipline**).
2. **Nothing can be measured today, and the missing instrument just shipped upstream.** Claude Code
   2.1.251 added a per-session `prompt_cache` object to `/cost` and the status line (hit ratio,
   misses, tokens re-cached, warm/cold); 2.1.260 added the likely cause of each miss. Reviving OYRF
   and wiring that object into `interstat/metrics.db` is the precondition for every experiment below
   — and it closes the "no cache metric" gap for `sylveste-129h` and `Sylveste-4b5.18` for free.
3. **Three upstream features land squarely on open beads.** `claude plugin eval` (6 grader types,
   every case run with and without the plugin → Δ, `--json`/`--report`) is the reproducible
   plugin-quality sweep `sylveste-4jmp` asks for; Managed Agents' *Outcomes* (rubric + grader in a
   separate context + pinpointed retry) is the pattern `Sylveste-06i.4` and `/clavain:quality-gates`
   need; `/skill-doctor` (which loaded skills go unused, and what they cost in context) turns the
   33 KB listing budget from a byte cap into usage-based pruning.
4. **Three upstream changes are risks, not features.** Fable 5.1 binds thinking blocks to the
   conversation and the model — earlier models cannot read them and history must be append-only —
   so a Fable→Opus switch mid-session silently drops reasoning unless the routing layer models
   direction. Gemini CLI is being sunset for Antigravity CLI, which puts a clock on the Gemini host
   (`scripts/gen-gemini-commands.sh`, `.gemini/settings.json`). MCP 2026-07-28 deprecates Roots,
   Sampling and Logging on a 12-month window and removes protocol sessions — an `sdk/interbase`
   migration that all 63 plugins inherit.

**The stance is unchanged from June: corrective-first.** Measure, then spend on output discipline,
then adopt the three upstream features that replace hand-rolled machinery. Do not build new memory
stores, do not switch harnesses, do not widen fan-out.

---

## Prioritized delta

### P1 — corrective / measurement (do now; all cheap)

| # | Item | Lever | Cost | Gates on | Basis |
|---|------|-------|------|----------|-------|
| 1 | **Revive the cost instrument.** Regex fix landed (this PR). The structural half remains: the 6-hourly exporter must run **where interstat lives** (workstation timer, pattern of `ops/rig-self-checks.md`), with CI reduced to schema validation — a CI checkout can never produce a non-zero row. | measurement | quick | `sylveste-oyrf` | run 34873388856 log; `estimate-costs.sh:14`; `data/cost-trajectory.csv` |
| 2 | **Wire `prompt_cache` into interstat** — the CC 2.1.251 status-line object (hit ratio, misses, tokens re-cached, warm/cold) + 2.1.260 miss causes → `interstat/metrics.db`. Record **harness config per session** alongside it: CC version (from `ops/cc-changelog-watch`), model, effort, `autoCompactWindow`, MCP-set hash. | token, context | quick–mod | `sylveste-129h`, `Sylveste-4b5.18`, `sylveste-9um7` | CC changelog 2.1.251/2.1.260; arXiv 2605.23950 (harness-induced variance can exceed model-induced variance, with ranking reversals — routing calibration that omits harness config attributes harness deltas to models) |
| 3 | **Re-baseline the north star** on Opus 5 / Fable 5.1 with the cache split and an explicit accounting model (the Oracle review's unanswered demand, `docs/research/oracle-token-efficiency-review.md`). Report $/landable change, tokens/landable change, output:input, cache-hit ratio. | measurement | quick | #1, #2 | `docs/measurements/2026-02-28-north-star-baseline.md` is on `opus-4-6` and a pre-4.7 tokenizer |
| 4 | **Output-discipline lines in `AGENTS.md`** (landed, this PR): targeted edits over rewrites; batch independent tool calls; keep changes and tests to the task. Then **audit agent prompts for "hold findings for the final response"-style lines**, which Anthropic says to remove before adding anything. | token | quick | — | Fable 5.1 prompting guide: rewrite behaviour "costs more output tokens and time"; one-call-per-turn "costs tokens, round trips, and wall-clock" |
| 5 | **`PreCompact` fires on auto compaction** (landed, this PR). Fable/Sonnet 5 auto-compact at ~967K by default; the bead re-prime only ran on `/compact`. | context | quick | — | CC model-config: `autoCompactWindow` defaults |

### P2 — experiments (each with a metric and a kill rule; all gated on P1 producing numbers)

6. **Effort as a routing dimension.** Extend `routing.yaml`'s phase→tier mapping (v2 overrides
   landed in `Sylveste-0pk`) with an `effort:` axis — plan `high`/`xhigh`, execute `medium`,
   verify/lens `low`–`medium` — and put `maxEffortLevel` in `os/Clavain/config/budget.yaml`. On
   Fable 5.1, `/effort` no longer invalidates the prompt cache and Anthropic's guidance is that
   `medium` "roughly matches Fable 5 at lower cost" and `low` "is often competitive with Opus and
   Sonnet on cost per task while scoring higher". For SDK-driven loops use per-message effort
   (beta `mid-conversation-output-config-2026-07-01`). *Metric:* $/landable change.
   *Kill:* quality-gate P0/P1 escape rate rises. *Gates:* `sylveste-xka6`.
7. **Subagent model forcing for lenses and Explore.** `CLAUDE_CODE_SUBAGENT_MODEL[_FORCE]` and
   agent-frontmatter `model:`/`effort:`; Explore was 25.5% of baseline tokens. *Metric:* tokens per
   review at equal finding recall (`sylveste-9lp.18` rubric). *Kill:* recall drops. *Ties:*
   `Sylveste-7zi` (opus-vs-sonnet lens disagreement), `sylveste-b1ha`.
8. **`claude plugin eval` as the Interverse CI gate.** `evals/` per plugin, `claude plugin eval
   init` to draft cases, Δ vs the no-plugin baseline, `--json` → PQS. The decision metric is
   **Δ per KB of skill-listing context**: a plugin with Δ ≤ 0 is pure context tax → disable
   (extends `docs/research/2026-04-21-plugin-disable-decisions.yaml`). Start with the ten largest
   contributors to the 33 KB listing; add `claude plugin validate --json` to the pre-commit hook.
   *Kill:* judge-graded Δ variance across three runs exceeds Δ itself (the reliability concern in
   `Sylveste-06i.4`). *Ties:* `sylveste-4jmp` ("keep PQS as telemetry, not a deterministic gate").
9. **`/skill-doctor` pruning pass.** Run across ~20 sessions; defer or disable never-used skills;
   convert `check-skill-listing-budget.sh` from a byte cap to a usage-weighted target. The April
   audit (`sylveste-ynh7`, closed) did this by hand; upstream now instruments it.
10. **Outcomes-style verify loop in `/sprint`.** Bead acceptance criteria → rubric; one grader
    subagent (haiku/sonnet) in its **own context window**; on fail, the grader pinpoints the fix and
    the implementer retries, ≤ 2 rounds; consumes `sylveste-9lp.35`'s VerificationStep and the
    landed close-gate. Anthropic's +8.4/+10.1 pt figures are on docx/pptx generation and Harvey's 6×
    is legal documents — **hypothesis for code, not evidence**. *Metric:* first-pass landable-change
    rate. *Guardrail:* tokens/landable change ≤ +15%. *Kill:* flat after 20 beads (the existing
    `min_non_bootstrap_sessions` threshold). *Ties:* `Sylveste-06i.4`, `Sylveste-4b5.1`
    (separate-context grader is the consensus-trap mitigation).
11. **`autoCompactWindow` A/B on 1M models.** Default compaction at ~967K means a session can sit
    at 600K context: cheap while the cache holds ($0.25/MTok reads), ~$6 per turn when it breaks.
    Test 300–400K vs default on matched `/sprint` tasks, with Anthropic's "tell the model what to
    preserve" compaction instruction. *Metric:* $/landable change + the context-rot proxy from
    `Sylveste-4b5.16`. *Kill:* rework rate rises at the smaller window.
12. **Context-editing API in SDK-driven loops** (Skaffen, interfer dispatch, flux-drive runner):
    `clear_tool_uses_20250919` with `trigger`, `keep`, `clear_at_least` (so each clear is worth its
    cache-write cost) and `exclude_tools` for beads/state tools; beta `context-management-2025-06-27`.
    Plus `bashOutputMaxChars`/`taskOutputMaxChars` lowered for verify subagents. This is the estate's
    first **runtime** output-trimming policy — today only startup surfaces are budgeted. *Metric:*
    input tokens per task at equal outcome. *Ties:* `sylveste-9lp.29`, `sylveste-18a.3`,
    `Sylveste-4b5.16`.
13. **Dreaming-style memory consolidation, as a PR-only Routine.** Nightly: read the last ≤100
    session transcripts + `MEMORY.md`, propose a curated memory diff **as a pull request, never
    auto-applied** — the T3 memory-poisoning threat in
    `docs/brainstorms/2026-02-23-token-optimization-security-threat-model.md` applies verbatim.
    Anthropic's memory tool (`/memories` file ops; "initializer session, progress log, feature
    checklist, end-of-session update") is a small stable interface the ten stores in
    `docs/brainstorms/2026-03-07-memory-architecture-convergence.md` could converge on; adopt the
    interface, not a new store. *Metric:* share of proposed entries accepted. *Kill:* < 30% after
    four weeks. *Ties:* `sylveste-a4oj.12`.
14. **Open-weight cheap tier for B2 enforce.** Kimi K2.7-Code (open weights, Modified MIT, −30%
    reasoning tokens vs K2.6 — and Kimi Code is already the estate's fourth host), DeepSeek V4 Flash
    ($0.14/$0.28), GLM-5.2 (1M context), Qwen 3.6 Plus — via the OpenRouter MCP from `sylveste-fyo3`,
    on C1–C2 verify/lint tasks in shadow. *Prereq:* fix `Sylveste-uk3` (OpenRouter omits
    `reasoning_tokens`) or the cost evidence is wrong by construction. *Gates:* `sylveste-xka6`;
    feeds `sylveste-lon1`.
15. **`fallbackModel` chain** (`Sylveste-u59`, still open): Fable 5.1 → Opus 5 → Sonnet 5. Fable
    5.1's permitted fallbacks are Opus 4.8/Opus 5; `fallbacks: "default"` (beta) plus fallback
    credit refunds the prompt-cache cost of switching. Add a `PreModelSwitch` hook (CC 2.1.251) that
    annotates direction: Fable→X loses thinking, X→Fable does not.
16. **Advisor model in plan mode** (`advisorModel: haiku`, `/advisor`): A/B on `/reflect`
    artifacts. Pin CC ≥ 2.1.267 — earlier builds re-sent the full conversation uncached on advisor
    background requests. *Kill:* no measurable plan-defect reduction.
17. **Non-blocking subagent dispatch.** Anthropic: letting the lead keep working while subagents
    run lowers wall-clock at similar tokens and cost. Confirm `sylveste-3kol` Rimsky and
    `dispatch.sh` return immediately and deliver results as later messages. Wall-clock only — not a
    token saver; the June warning on pricing the fan-out multiplier stands.

### P3 — watch items / spikes

18. **MCP 2026-07-28 migration in `sdk/interbase`** — stateless servers, `server/discover`,
    `resultType`, `ttlMs`/`cacheScope` on list results, Tasks moved to a polling extension (relevant
    to interlock's long operations), Roots/Sampling/Logging deprecated (12-month window). The spec
    now says servers *SHOULD* return `tools/list` in deterministic order "to improve LLM prompt cache
    hit rates" — do that part in P2 as a spike and measure the cache-hit delta with #2. One change in
    interbase reaches all 63 plugins (charter D1).
19. **Gemini CLI → Antigravity CLI.** Audit `scripts/gen-gemini-commands.sh`, `.gemini/settings.json`,
    `docs/guide-gemini-setup.md`; decide keep-and-port or retire the Gemini host before investing
    further. Gemini 3.8 Flash is GA and cheap, so the *model* stays interesting even if the CLI goes.
20. **Codex Agents API / GPT-6-Astra** for `dispatch.sh` cloud offload of the `deep` tier. Run the
    community claim that Claude Code uses 3–4× the tokens of Codex on the same work as a controlled
    measurement on ten estate beads under the arXiv 2605.23950 disclosure protocol before believing
    it — GitHub's Copilot study normalised away tool search and MCP entirely, which is not this estate.
21. **Turn-scoped system messages for per-turn hook context.** `clear_at: "next_user_message"`
    (beta `mid-conversation-system-clear-at-2026-08-21`) keeps a per-turn reminder out of history at
    zero input tokens without breaking cache or thinking binding. The `UserPromptSubmit` skill-prefix
    router (`scripts/skill-prefix-router-hook.sh`) emits `additionalContext` every turn: verify
    whether CC already turn-scopes it; Skaffen and any SDK loop must, or they violate Fable 5.1's
    append-only rule. Diagnostic: run with `prefix_mismatch_behavior: "drop_block"` and log
    `input_transformations`.
22. **ACP (Zed's Agent Client Protocol)** — 60+ agents, an official Claude Code adapter, JetBrains/
    Zed/Neovim/Emacs. Watch only; no estate consumer until Clavain is exposed as an editor agent.
23. **Managed Agents as a Clavain runtime target** — budget controls, environment/memory webhooks,
    session seeding, GitHub-loaded skills — vs intercore's scheduler. Watch; the ockham line ("no
    private audit store, quality gates stay Clavain's") and the 30-day retention on Fable-class
    models both cut against adopting the platform itself.
24. **Design and product quality.** No product-discovery or UX doctrine exists (product quality
    rests on 27 CUJs + PRDs); this delta flags it, it does not invent one. Two spikes once #10 proves
    the loop on code: an Outcomes rubric on design artifacts (where Anthropic's gains were measured),
    and Fable 5.1 crop-and-zoom vision to verify UI output against the design (Claude Design canvas /
    DesignSync) as a verify-gate step for UI work.

---

## What the frontier VALIDATES (keep prioritizing)

- **Corrective-first.** The June stance holds: every P1 here is measurement or plumbing.
- **Measurement before optimization** (`agents/design-doctrine.md`). Two papers now say the harness
  explains more variance than the model; the estate's interspect calibration cannot be trusted
  without harness config in the evidence schema (`sylveste-9um7`).
- **Separate-verifier over self-critique.** Anthropic's *Outcomes* runs the grader in its own context
  "so its judgment is not contaminated by the agent's reasoning" — the same reasoning as
  `Sylveste-4b5.1`'s consensus-trap breaker.
- **The 33 KB skill-listing budget.** Anthropic built the same instrument (`/skill-doctor`) three
  months after the estate enforced it in CI; the byte cap was the right call, usage-weighting is the
  upgrade.
- **`sylveste-xka6` as the routing spine.** Effort, cheap tiers and cache-aware cost all still hang
  off shadow→enforce.
- **Kimi as a host.** Moonshot shipping K2.7-Code with open weights and a 30% reasoning-token cut
  makes the fourth host the natural cheap tier, not a curiosity.

## What was deliberately DROPPED (anti-hype)

- **1M context as a feature.** Full-price bloat on an output-heavy workload; June already dropped
  "bigger windows — rot makes them worse". #11 tests the *opposite* direction.
- **Kimi K2.6's 300-subagent "agent swarm".** Contradicts `Sylveste-rgj`'s open null test
  (does multi-agent beat single-strong-model here?) and the fan-out conflict economics in the June
  delta.
- **Switching harness** (Copilot CLI, Codex, OpenCode, Antigravity). The efficiency studies hold the
  harness fixed and strip MCP/tool search; the estate's value *is* the plugin layer. Measure (#20)
  before concluding anything.
- **Managed Agents platform adoption**, Claude Finance, Word add-ins, content-provenance watermark —
  no consumer, no action.
- **Auto-applied "dreaming".** Memory poisoning (T3) is a documented estate threat; #13 keeps a
  human on the merge button.
- **Expanding the local-MLX model program.** The relevant beads are blocked; open-weight models enter
  via OpenRouter (#14) where cost telemetry already exists.

## Meta — verify before acting

- All vendor numbers (Fable 5.1 pricing and behaviour, Outcomes/Dreaming gains, Copilot harness
  claims, K2.7-Code token cut, open-weight prices) are post-cutoff and quoted from vendor or
  secondary pages listed below; treat patterns as load-bearing, figures as hypotheses.
- Claude Code entries cite changelog versions (2.1.251–2.1.270); confirm the pinned CC version on the
  rig before relying on any of them (`ops/cc-changelog-watch`).
- Bead states are a 2026-09-14 snapshot of `.beads/issues.jsonl`; re-check before filing.
- The cloud checkout has no plugins (`os/`, `core/`, `interverse/`, `sdk/*` gitignored); every P2/P3
  item lands on the workstation.

## Bead candidates (cloud session — beads read-only; file at the workstation)

1. `sylveste-oyrf`: move the exporter's data path to the workstation timer; CI validates schema only.
2. Wire the CC `prompt_cache` status-line object + miss causes into interstat; add harness-config
   columns (CC version, model, effort, autoCompactWindow, MCP-set hash) — child of `sylveste-9um7`.
3. Re-baseline the north star on current models with the accounting model the Oracle review asked for.
4. Audit agent/skill prompts for narration-suppressing lines; remove per the Fable 5.1 guide.
5. `routing.yaml` effort axis + `maxEffortLevel` in `budget.yaml` — child of `sylveste-xka6`.
6. Subagent model forcing A/B for lenses/Explore — with `Sylveste-7zi`, `sylveste-b1ha`.
7. `claude plugin eval` gate: `evals/` for the ten largest listing contributors; Δ-per-KB metric;
   `claude plugin validate --json` in pre-commit — with `sylveste-4jmp`.
8. `/skill-doctor` pass; usage-weighted skill-listing budget.
9. Outcomes-style verify loop in `/sprint` — with `Sylveste-06i.4`, `sylveste-9lp.35`.
10. `autoCompactWindow` A/B — with `Sylveste-4b5.16`.
11. Context-editing API + output caps in SDK loops — with `sylveste-9lp.29`, `sylveste-18a.3`.
12. Dreaming-style consolidation Routine (PR-only) — with `sylveste-a4oj.12`.
13. Open-weight C1–C2 tier via OpenRouter; fix `Sylveste-uk3` first — with `sylveste-xka6`, `sylveste-lon1`.
14. `fallbackModel` chain + `PreModelSwitch` direction hook — `Sylveste-u59`.
15. `sdk/interbase` MCP 2026-07-28 migration; deterministic `tools/list` ordering spike first.
16. Gemini host: Antigravity CLI audit, keep-or-retire decision.
17. Turn-scoped hook context investigation (CC) + Skaffen adoption.

## Sources

Anthropic — [What's new in Claude Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1) ·
[Prompting Claude Fable 5.1](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1) ·
[Context editing](https://platform.claude.com/docs/en/build-with-claude/context-editing) ·
[Memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool) ·
[Claude Code changelog](https://code.claude.com/docs/en/changelog) ·
[Claude Code model configuration](https://code.claude.com/docs/en/model-config) ·
[Test plugins with evals](https://code.claude.com/docs/en/plugin-evals) ·
[New in Claude Managed Agents: dreaming, outcomes, multiagent orchestration](https://claude.com/blog/new-in-claude-managed-agents) ·
[Introducing Claude Fable 5.1 and Claude Mythos 5.1](https://www.anthropic.com/claude-fable-and-mythos-5-1)

Protocols — [MCP 2026-07-28 key changes](https://modelcontextprotocol.io/specification/2026-07-28/changelog) ·
[Agent Client Protocol — agents](https://agentclientprotocol.com/get-started/agents) ·
[@zed-industries/claude-code-acp](https://www.npmjs.com/package/@zed-industries/claude-code-acp)

Other vendors — [Introducing upgrades to Codex (OpenAI)](https://openai.com/index/introducing-upgrades-to-codex/) ·
[Gemini CLI → Antigravity CLI transition](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/) ·
[Gemini 3 Flash in Gemini CLI](https://developers.googleblog.com/gemini-3-flash-is-now-available-in-gemini-cli/) ·
[Kimi K2.7-Code (MarkTechPost)](https://www.marktechpost.com/2026/06/12/moonshot-ai-releases-kimi-k2-7-code-a-coding-model-reporting-21-8-on-kimi-code-bench-v2-over-k2-6/) ·
[Kimi K2.7-Code targets token efficiency (DevOps.com)](https://devops.com/moonshot-ais-kimi-k2-7-code-targets-token-efficiency-in-agentic-coding/) ·
[Open-weight coding models 2026 (Morph)](https://www.morphllm.com/best-open-source-coding-model-2026)

Research — [Stop Comparing LLM Agents Without Disclosing the Harness (arXiv 2605.23950)](https://arxiv.org/abs/2605.23950) ·
[Harness Engineering for Agentic AI Coding Tools (arXiv 2602.14690)](https://arxiv.org/pdf/2602.14690) ·
[Evaluating the GitHub Copilot agentic harness (GitHub Blog)](https://github.blog/ai-and-ml/github-copilot/evaluating-performance-and-efficiency-of-the-github-copilot-agentic-harness-across-models-and-tasks/) ·
[Coding agent harness comparison 2026 (Tech Stackups)](https://techstackups.com/comparisons/coding-agent-harness-comparison-2026/)
