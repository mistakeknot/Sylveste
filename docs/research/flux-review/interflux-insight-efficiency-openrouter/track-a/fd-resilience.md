### Findings Index
- P1 | RES-1 | "Constraints" | Single point of failure in provider dependency — OpenRouter outage during a quality-gate review blocks the entire pipeline
- P2 | RES-2 | "Question" | No staging/sequencing plan — the proposal goes from "no OpenRouter" to "full integration" with no intermediate steps
- P2 | RES-3 | "Current Architecture" | Antifragility opportunity missed — model failures could strengthen the system by building calibration data, but only if failures are captured not suppressed
- P3 | RES-4 | "Question" | Creative constraint not leveraged — the Claude-only constraint may be a feature, not a bug, that forces higher-quality agent design
Verdict: needs-changes

### Summary

The proposal treats OpenRouter integration as a feature to build rather than a hypothesis to test. There is no staging plan — no "try the smallest thing first, measure, then expand." The document should define a minimum viable experiment (1 agent, 1 model, 10 reviews) that tests the core assumption ("non-Claude models produce useful review findings") before building the full dispatch infrastructure. The resilience analysis also reveals a missed antifragility opportunity: if model failures and quality degradation are captured as calibration data (rather than suppressed by fallback), each failure makes the routing policy better. But this requires explicit failure capture, not silent fallback.

### Issues Found

RES-1. **P1: Provider dependency introduces a new SPOF.** Interflux currently has one failure domain: Claude Code's runtime. Adding OpenRouter creates a second failure domain that the orchestrator depends on for a subset of agents. During a quality-gate review (where flux-drive is blocking a merge), an OpenRouter outage would mean: either (a) the review waits for OpenRouter agents to time out (5-10 minutes), delaying the merge pipeline, or (b) the review proceeds without OpenRouter agents, potentially missing findings that the cost model predicted would come from those agents.

The progressive enhancement contract ("OpenRouter as optional acceleration, never a gate") handles case (b) — but case (a) is the operational reality. The 5-10 minute timeout for failed OpenRouter agents adds wall-clock latency to every review where OpenRouter is down, even if the review ultimately proceeds without those findings.

**Smallest fix:** Health-check OpenRouter before dispatch (ping `/api/v1/models`, <2s timeout). If down, skip OpenRouter dispatch entirely for this review — zero latency cost, zero lost findings relative to the Claude-only baseline.

RES-2. **P2: No staged rollout.** The document proposes a comprehensive integration (dispatch backend, token accounting, prompt variants, cost modeling) without defining intermediate checkpoints. A staged approach:

- **Stage 0 (Manual, 1 day):** Manually call DeepSeek V3 via curl with 3 existing agent prompts. Compare output quality. Go/no-go for engineering.
- **Stage 1 (Shadow, 1 week):** Add OpenRouter dispatch for 2 checker-role agents in shadow mode (run both Claude and OpenRouter, compare). No changes to synthesis.
- **Stage 2 (Canary, 2 weeks):** Route 2 checker-role agents to OpenRouter in 10% of reviews. Measure finding recall and format compliance.
- **Stage 3 (Expand, ongoing):** If canary metrics pass, expand to editor-role agents. Never expand to planner/reviewer roles.

Each stage has a clear exit criterion and a rollback plan (disable OpenRouter dispatch, agents fall back to Claude).

RES-3. **P2: Failures as calibration data.** The document's fallback strategy ("if OpenRouter fails, use Claude") treats failures as problems to suppress. But each failure — whether a format compliance failure, a finding quality gap, or a timeout — is calibration data. If captured systematically (model, agent type, failure mode, input complexity), these failures build the dataset needed to answer: "which model + agent combinations work, and which don't?" The interspect evidence system already captures agent-level performance data. Extending it to capture provider-level outcomes would make failures valuable rather than merely tolerable.

RES-4. **P3: The Claude-only constraint as creative driver.** The document frames the Claude-only constraint as a limitation to overcome. But constraints drive innovation — the existing interflux system was designed within the Claude-only constraint, and that constraint forced sophisticated optimization: AgentDropout, cross-model dispatch within Claude tiers, budget-aware selection, and reaction round sycophancy detection. These mechanisms are more advanced than most multi-model systems because the constraint forced depth over breadth. Adding model diversity is a valid direction, but the document should acknowledge what might be lost: the tight integration and well-calibrated quality guarantees of a single-provider system.

### Improvements

RES-I1. Define the "Stage 0 manual test" as the first action item — it costs $0.10 and 30 minutes, and it answers the most important question ("do non-Claude models produce usable findings?") before any engineering begins.

RES-I2. Each stage should have a "kill switch" — a single config flag that disables OpenRouter dispatch globally. The existing `cross_model_dispatch.mode: shadow` in budget.yaml is the right pattern: add `openrouter_dispatch.mode: disabled | shadow | canary | enforce`.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 4 (P0: 0, P1: 1, P2: 2, P3: 1)
SUMMARY: The proposal needs a staged rollout plan (manual test, shadow mode, canary, expand) with explicit kill switches at each stage. Failures should be captured as calibration data rather than suppressed by fallback. A $0.10 manual test should be the first action.
---
<!-- flux-drive:complete -->
