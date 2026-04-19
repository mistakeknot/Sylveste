### Findings Index
- P1 | P1 | "SKILL.md + SKILL-compact.md across all phases" | Map/territory: skill documents itself as a deterministic dispatcher but downstream subsystems (qmd, interstat, lib-routing) have non-deterministic availability — the "deterministic" claim is stale
- P1 | P2 | "phases/synthesize.md Step 3.4c convergence with slicing + synthesize.md Step 3.4a verdict logic" | Goodhart risk: convergence count becomes the primary signal for finding importance; agents that over-converge on minor issues inflate verdict severity
- P1 | P3 | "phases/expansion.md Step 2.2a.6 + partial findings reading" | Change blindness: incremental expansion reads Stage 1 outputs as they complete, but the orchestrator has no summary of what it has seen vs what it is still waiting for
- P1 | P4 | "SKILL.md Phase 1.3 auto-proceed + phases/launch.md background dispatch" | Streetlight: auto-proceed + background dispatch optimizes for user perception of responsiveness, not for actual review quality
- P2 | P5 | "phases/reaction.md topology-aware visibility" | Perspective-taking absent by default: fully-connected visibility means agents share a single lens rather than maintaining distinct roles
- P2 | P6 | "phases/launch.md Step 2.3 flux-watch.sh progress display" | Leading vs lagging: completion count is a lagging indicator; no leading indicator (e.g., tokens generated per agent in flight)
- P2 | P7 | "phases/synthesize.md Step 3.5 Report structure" | Availability heuristic: report leads with P0/P1 findings — improvements and zero-finding agents recede, even when the latter are the actual signal
- P2 | P8 | "config/flux-drive/*.yaml + inline step references" | Mental model fragmentation: configuration split across 6 YAML files referenced from 8 phase files — no unified "dispatch profile" view
Verdict: needs-changes

### Summary

The skill's self-description models a clean 3-phase pipeline with scored triage and parallel dispatch. The territory is messier: 8+ progressive enhancements that may or may not activate, 6 YAML configs that interact in undocumented ways, a dual-file orchestration layer, a research mode that shares infrastructure but diverges on several dispatch rules. A reader using the "map" (SKILL.md) to predict behavior will be surprised by the territory. Convergence count is the primary synthesis signal, which creates Goodhart risk — agents optimized to find converging things will find them. The Phase 3 report structure amplifies availability bias (prominent findings first), and the flux-watch progress line is a lagging indicator dressed as a progress bar. The skill has the pieces of a rigorous sensemaking tool; what's missing is the meta-layer that tracks its own signal quality.

### Issues Found

1. P1. P1: Map-territory gap on "deterministic" dispatch. SKILL.md Step 1.3: "Auto-proceed (default): ... the triage algorithm is deterministic and the user can inspect the table output." The algorithm is deterministic given its inputs. But the inputs include: qmd availability, lib-routing.sh presence, interstat data freshness, overlays directory contents, trust scores from intertrust, routing-overrides.json, CLAUDE.md contents — a third of these can change between runs without user action. The skill presents determinism that the environment doesn't guarantee. Fix: reframe as "auto-proceed because the decision is reproducible — see decisions.log" (see fd-decisions IMP-3) rather than "deterministic". Reproducibility is the actual property.

2. P2. P1: Goodhart on convergence count. `phases/synthesize.md` Step 3.4c slicing convergence boost: "If 2+ agents agree on a finding AND reviewed different priority sections, boost the convergence score by 1." Dedup rule 1 (L105): "Same file:line + same issue → merge, credit all agents". Verdict logic (Step 3.4a): "If any P0 → risky. If any P1 → needs-changes." Convergence is a good heuristic for evidence strength, but agents can converge on minor issues (e.g., "Section X is thin" flagged by multiple cognitive agents because they all read the same thin section). Once convergence becomes a measured signal, it becomes a target — agents may start reporting small convergent issues to look productive. Fix: distinguish convergence on severity from convergence on presence. Weight by severity, and track "P0/P1 convergence rate per agent over time" to detect convergence-seeking behavior.

3. P3. P1: Change blindness during incremental expansion. `phases/expansion.md` Step 2.2a.6 triggers speculative launches based on "as each Stage 1 agent completes, read its Findings Index." The orchestrator reads one agent at a time, makes a local expansion decision, and loses the global view. After 3 stage-1 completions, the orchestrator has made 3 speculative decisions but has no "what have I seen so far" summary. If agent 1 completes with a P1, agent 2 completes later with a matching P1 (would have been a convergence signal), the speculative decision already fired on agent 1 alone. Fix: maintain a running "Stage 1 evidence summary" that incremental decisions consult.

4. P4. P1: Streetlight on auto-proceed UX. "Auto-proceed" favors the metric "user perceives immediate response" over "user validates the plan before N agents burn 150K tokens". The perception is that automation is fast; the reality is that a wrong triage runs for 5 minutes and produces noise. Fix: consider auto-proceed-with-undo — dispatch immediately but show a "cancel and edit" prompt with a 30-second window during which the Task calls can still be cancelled cheaply. Present both the decision and the escape hatch.

5. P5. P2: Perspective-taking absent by default. `phases/reaction.md` Step 2.5.2a: "If missing/disabled, use fully-connected (all agents see all findings)." In fully-connected mode, fd-safety and fd-architecture and fd-performance all see each other's findings. Distinct perspectives collapse into a shared frame. The intent of multi-agent review is to preserve perspective diversity. Fix: topology-enabled-by-default (see fd-systems SY7). At minimum, document the perception cost of fully-connected.

6. P6. P2: Flux-watch progress is lagging. The progress line `[N/M | elapsed] agent-name` reports completion count (lagging). Agents take 30s-3min each. A more informative signal: current agent token count during dispatch (leading), or "3 agents running, 0 completed, longest-running 2m" (active status). Fix: extend flux-watch.sh to report in-flight token counts when available via transcript polling.

7. P7. P2: Report availability bias. `phases/synthesize.md` Step 3.5 Report: leads with "Critical Findings (P0)", then "Important Findings (P1)", then "Improvements Suggested". Users skim the top and stop. Zero-findings agents (listed in "Verdict Summary" table) are above the fold only because the summary table is first. Improvements — often the highest-volume output — are third. In a review where P0/P1 are few but improvements are rich, the user perceives "not much to do" and closes the report. Fix: lead with finding counts (P0: 2, P1: 5, Improvements: 12), then detail. If no P0/P1, lead with improvements.

8. P8. P2: Configuration fragmentation. The skill consults `config/flux-drive/budget.yaml`, `reaction.yaml`, `routing-overrides.json`, `discourse-topology.yaml`, `discourse-fixative.yaml`, `discourse-lorenzen.yaml`, `model-registry.yaml`, and domain profiles. No single view lists what configs were used for a run. The same file inline (e.g., launch.md) tells the reader "see budget.yaml section X, Y, Z" without showing what X/Y/Z contain. Fix: a `decisions.log` that includes "config: budget.yaml@sha=abc, reaction.yaml@sha=def, ..." and their effective values for this run. Pairs with fd-decisions IMP-3.

### Improvements

1. IMP-1. Signposts for changed assumptions. Pre-commit to triggers that surface change blindness: "If qmd becomes unavailable for 3 consecutive runs, show banner." "If interstat data ages >30 days, show warning." These are sensing mechanisms the skill currently lacks.

2. IMP-2. Distinguish leading from lagging. Every report metric tagged "leading" or "lagging" (e.g., findings count is lagging — measures the past review; agent selection diversity is leading — predicts future recall). Forces the writer to state which they're offering.

3. IMP-3. Perspective-taking explicit: in reaction-round prompts, ask each agent to explicitly state "how would an agent from adjacent-domain Y view this finding?" before reacting. Makes the diversity intentional.

4. IMP-4. Map-territory check as a recurring ritual. Once per week, a user runs `/interflux:flux-drive` on a canary document with a known-good expected finding set. If the actual findings drift from expected by >30%, fire an alarm. The skill's self-model stays aligned with its behavior.

5. IMP-5. Cone-of-uncertainty bars on numeric reports. The cost report's "estimated vs actual tokens" should include a range ("estimated 12K, actual 9-15K range expected from historical variance") rather than a point estimate. Enables calibration over time.

<!-- flux-drive:complete -->
