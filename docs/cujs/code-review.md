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

## The Journey

The developer has code ready for review. This might happen at several points in the [sprint lifecycle](running-a-sprint.md): a plan is written and needs validation before execution, a feature is implemented and needs review before shipping, or a document (PRD, vision, roadmap) needs multi-perspective feedback.

The most common entry point is `/clavain:quality-gates`. Quality-gates reads the current diff, detects what kind of change it is (code, docs, config, migration), and auto-selects the relevant review agents. The developer doesn't choose agents — the system does, based on capability declarations and historical effectiveness. For direct control, developers can also invoke `/interflux:flux-drive` with a specific target (a file path, a git diff, or a plan document), manually selecting the review scope.

The triage layer determines which review agents are relevant. A pure documentation change doesn't need the performance agent. A database migration doesn't need the game design agent. A security-sensitive change gets the safety agent dispatched at high priority. The triage uses capability declarations (each agent declares what kinds of changes it's equipped to review) and historical effectiveness (Interspect data on which agents produced actionable findings for similar changes). Interspect routing overrides can exclude agents that have been consistently unhelpful for this type of change *(Interspect-driven exclusion is partially shipped — the override chain is active, but automated feedback from review dismissals to routing adjustments is Phase 2)*.

The selected agents run in parallel, each examining the change through their specific lens. The architecture agent checks module boundaries, coupling, and design patterns. The safety agent checks credentials, trust boundaries, and deployment risk. The correctness agent checks data consistency, race conditions, and transaction safety. The quality agent checks naming, conventions, and idiomatic patterns. Each agent writes its findings to a file in `.claude/flux-drive-output/`.

The synthesis agent reads all agent outputs, deduplicates overlapping findings, ranks by severity (blocking, important, suggestion, nit), and produces a structured report. The report includes a verdict (approve, request changes, or needs discussion) and a confidence score. *(Planned: findings grouped by theme rather than by agent — the developer would see "three agents flagged this error handling pattern" rather than reading three separate agent sections. Current synthesis groups by agent with deduplication across agents.)*

The developer reads the synthesis. For each finding, they can:
- **Act on it** — make the suggested change. This is a positive signal to Interspect.
- **Dismiss it** — mark as not applicable. If an agent's findings are consistently dismissed, Interspect learns to route around it *(planned — dismissal-to-routing feedback loop is Phase 2)*.
- **Discuss it** — the finding raises a genuine question that needs human judgment.

After resolving findings, the developer can re-run the review on the updated change to verify fixes, or proceed to ship if the verdict was approve. The review findings, agent selections, and developer responses are all recorded as kernel events — they're the evidence that Interspect uses to calibrate the fleet.

Over time, the review gets better. Agents that produce noise get downweighted or excluded. Agents whose findings consistently improve the code get prioritized. The cost of review decreases because fewer agents are dispatched for well-understood change types, while the signal quality increases because the remaining agents are the ones that matter.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Triage selects relevant agents only | observable | No agent is dispatched whose declared capabilities don't match the change type |
| Agent dispatch completes within 2 minutes | measurable | All parallel agents finish and synthesis begins in <120s for typical changes |
| Synthesis deduplicates cross-agent overlap | measurable | Finding count in synthesis is less than sum of individual agent findings |
| At least one finding is genuinely actionable | qualitative | Developer acts on at least one finding that they would not have caught themselves |
| Majority of findings are acted upon | measurable | >50% of findings result in code changes or acknowledged tradeoffs, not dismissals |
| Verdict confidence correlates with quality | observable | High-confidence "approve" verdicts don't precede post-merge regressions |
| Developer reads the full report | qualitative | Report is concise enough that the developer reads it rather than skipping to the verdict |
| Review cost trends downward per change | measurable | Token spend on review decreases as Interspect optimizes agent selection |
| Interspect adjusts routing based on review outcomes | observable | Agent dispatch patterns change after sustained dismissal or action signals |

## Known Friction Points

- **Triage accuracy on novel change types.** When a change doesn't match established patterns (new module, unfamiliar language, cross-cutting refactor), triage may over-dispatch (too many agents, high cost) or under-dispatch (missing the relevant lens).
- **Synthesis quality depends on agent output quality.** If individual agents produce vague or contradictory findings, the synthesis can't magically produce clarity. "Architecture says split this module; quality says keep it together" is a genuine tension, but the synthesis may present it as two unrelated findings rather than a tradeoff.
- **Dismissal friction.** Dismissing a finding should be one action, but the developer may need to explain why (for Interspect to learn effectively). The tension between "fast dismissal" and "informative dismissal" is unresolved.
- **Re-review cost.** Running the review again after fixing findings re-dispatches all agents, not just the ones whose findings were relevant. Incremental re-review (only check what changed since last review) isn't implemented.
- **Review fatigue on large changes.** A 500-line diff produces many findings. Even with deduplication and ranking, the developer may hit review fatigue and start dismissing without reading. The system has no mechanism to detect or prevent this.
- **Interspect feedback latency.** Routing adjustments based on dismissal patterns take multiple sprints to manifest. A developer who dismisses the same agent's findings five times in one session won't see the adjustment until later sessions.
