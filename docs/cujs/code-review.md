---
artifact_type: cuj
journey: code-review
actor: regular user (developer reviewing code or documents)
criticality: p1
bead: Demarch-9ha
---

# Multi-Agent Code Review

## Why This Journey Matters

Code review is where quality is either built in or bolted on. Most AI review tools produce a wall of suggestions — formatting nits, style preferences, and obvious observations mixed with the one finding that actually matters. The developer reads twenty findings, dismisses eighteen, and hopes they didn't accidentally dismiss the important one. This is worse than no review at all, because it creates false confidence.

Demarch solves this through cognitive diversity: instead of one model reviewing everything, specialized agents examine the change from distinct perspectives — architecture, safety, correctness, quality, performance, user experience. Each agent has an explicit lens, declared capabilities, and a track record that Interspect monitors. The synthesis layer deduplicates findings, ranks by severity, and produces a verdict. The developer reads one structured report, not twelve raw outputs.

This matters for Demarch specifically because the review fleet is where Interspect has the most immediate leverage. An agent that consistently produces false positives gets downweighted. An agent whose findings are always acted upon gets prioritized. The signal density of the review fleet directly feeds the learning loop. Bad review is not just annoying — it's expensive data pollution.

### Current State vs. Planned

| Capability | Status |
|------------|--------|
| Parallel agent dispatch with per-agent output files | **Shipped** |
| Triage based on capability declarations | **Shipped** |
| Synthesis with deduplication and severity ranking | **Shipped** |
| Verdict (approve/request changes/needs discussion) | **Shipped** |
| Manual routing overrides (`/interspect:override`) | **Shipped** |
| Findings grouped by theme (not agent) | **Planned** |
| Automated dismissal-to-routing feedback loop | **Planned** (Phase 2) |
| Confidence score on verdicts | **Planned** |
| Incremental re-review (only re-check changed code) | **Planned** |

## The Journey

The developer has code ready for review. This might happen at several points in the [sprint lifecycle](running-a-sprint.md): a plan is written and needs validation before execution, a feature is implemented and needs review before shipping, or a document (PRD, vision, roadmap) needs multi-perspective feedback.

The most common entry point is `/clavain:quality-gates`. Quality-gates reads the current diff, detects what kind of change it is (code, docs, config, migration), and auto-selects the relevant review agents. The developer doesn't choose agents — the system does, based on capability declarations and historical effectiveness. For direct control, developers can also invoke `/interflux:flux-drive` with a specific target (a file path, a git diff, or a plan document), manually selecting the review scope.

The triage layer determines which review agents are relevant. A pure documentation change doesn't need the performance agent. A database migration doesn't need the game design agent. A security-sensitive change gets the safety agent dispatched at high priority. The triage uses capability declarations (each agent declares what kinds of changes it's equipped to review) and historical effectiveness (Interspect data on which agents produced actionable findings for similar changes). Interspect routing overrides can exclude agents that have been consistently unhelpful for this type of change *(Interspect-driven exclusion is partially shipped — the override chain is active, but automated feedback from review dismissals to routing adjustments is Phase 2)*.

The selected agents run in parallel, each examining the change through their specific lens. The architecture agent checks module boundaries, coupling, and design patterns. The safety agent checks credentials, trust boundaries, and deployment risk. The correctness agent checks data consistency, race conditions, and transaction safety. The quality agent checks naming, conventions, and idiomatic patterns. Each agent writes its findings to a file in `.claude/flux-drive-output/`.

The synthesis agent reads all agent outputs, deduplicates overlapping findings, ranks by severity (P0/critical, P1/important, P2/suggestion, IMP/improvement), and produces a structured report. The report includes a verdict: approve, request changes, or needs discussion. *(Planned: findings grouped by theme rather than by agent — the developer would see "three agents flagged this error handling pattern" rather than reading three separate agent sections. Current synthesis groups by agent with deduplication across agents. Confidence scores on verdicts are also planned.)*

The developer reads the synthesis. For each finding, they can:
- **Act on it** — make the suggested change. This is a positive signal to Interspect.
- **Dismiss it** — mark as not applicable. If an agent's findings are consistently dismissed, Interspect learns to route around it *(planned — dismissal-to-routing feedback loop is Phase 2)*.
- **Discuss it** — the finding raises a genuine question that needs human judgment.

After resolving findings, the developer can re-run the review on the updated change to verify fixes, or proceed to ship if the verdict was approve. The review findings, agent selections, and developer responses are all recorded as kernel events — they're the evidence that Interspect uses to calibrate the fleet.

Over time, the review gets better — but today this requires manual effort. The operator runs `/interspect:propose` to detect patterns in agent effectiveness, reviews the proposals, and approves overrides with `/interspect:approve`. Agents that produce noise get excluded via routing overrides. Agents whose findings consistently improve the code stay in the default triage set. *(The long-term goal is automated feedback: dismissal patterns trigger routing proposals without manual intervention. This is Phase 2.)*

## Success Signals

| Signal | Type | Status | Assertion |
|--------|------|--------|-----------|
| Triage selects relevant agents only | observable | active | Dispatched agent list in `.claude/flux-drive-output/` matches change type; no capability-mismatched agents |
| Agent dispatch completes within 2 minutes | measurable | active | Wall-clock from `/quality-gates` invocation to synthesis start is <120s for <500-line diffs |
| Synthesis deduplicates cross-agent overlap | measurable | active | Finding count in `synthesis.md` is less than sum of per-agent finding counts |
| At least one finding is genuinely actionable | qualitative | active | Developer acts on at least one finding that they would not have caught themselves |
| Majority of findings are acted upon | measurable | active | >50% of findings result in code changes or acknowledged tradeoffs, not dismissals |
| Developer reads the full report | qualitative | active | Report is concise enough that the developer reads it rather than skipping to the verdict |
| Agent timeout produces partial synthesis | observable | active | If one agent fails/times out, synthesis proceeds with available results and notes the missing agent |
| Review cost trends downward per change | measurable | planned | Token spend per review (via `interstat`) decreases over 10-review window as routing improves |
| Interspect adjusts routing based on review outcomes | observable | planned | Agent dispatch patterns change after manual `/interspect:propose` + `/interspect:approve` cycle |

## Known Friction Points

- **Triage accuracy on novel change types.** When a change doesn't match established patterns (new module, unfamiliar language, cross-cutting refactor), triage may over-dispatch (too many agents, high cost) or under-dispatch (missing the relevant lens). *Workaround: use `/interflux:flux-drive` directly with explicit agent selection instead of auto-triage.*
- **Synthesis quality depends on agent output quality.** If individual agents produce vague or contradictory findings, the synthesis can't magically produce clarity. "Architecture says split this module; quality says keep it together" is a genuine tension, but the synthesis may present it as two unrelated findings rather than a tradeoff. *No mitigation yet — tension detection in synthesis is planned.*
- **Dismissal friction.** Dismissing a finding should be one action, but the developer may need to explain why (for Interspect to learn effectively). The tension between "fast dismissal" and "informative dismissal" is unresolved. *No mitigation yet.*
- **Re-review cost.** Running the review again after fixing findings re-dispatches all agents, not just the ones whose findings were relevant. Incremental re-review (only check what changed since last review) isn't implemented. *Workaround: use `/interflux:flux-drive` with a narrow file target instead of a full re-review.*
- **Review fatigue on large changes.** A 500-line diff produces many findings. Even with deduplication and ranking, the developer may hit review fatigue and start dismissing without reading. The system has no mechanism to detect or prevent this. *No mitigation yet.*
- **Interspect feedback latency.** Today, routing adjustments require manual steps: run `/interspect:propose` to detect patterns (needs ~5+ dismissed findings from the same agent), review proposals, then `/interspect:approve` to activate overrides. A developer in their first week of use won't have enough evidence for proposals to surface. Expect 2-4 weeks of use before routing improvements appear. *Automated feedback (skipping the manual propose/approve cycle) is Phase 2.*
- **Agent timeout or error during dispatch.** If one agent fails or times out during parallel dispatch, the synthesis proceeds with partial results. The developer may not notice a missing perspective unless they check the agent list. *Mitigation: synthesis notes which agents were dispatched and which completed. Missing agents are listed in the report.*
