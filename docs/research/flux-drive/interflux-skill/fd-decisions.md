### Findings Index
- P1 | D1 | "SKILL.md Phase 1.3 + SKILL-compact.md Phase 1.3" | Auto-proceed default removes the human review step, locking in scoring-algorithm choices without validation — asymmetric cost to errors
- P1 | D2 | "phases/expansion.md Step 2.2b — expansion decision" | Binary "AUTO-EXPAND vs AUTO-STOP" over expansion scores is a false dichotomy when score=2 could merit partial expansion
- P1 | D3 | "phases/launch.md Step 2.2-challenger" | Challenger "shadow vs enforce" framing presents a binary that hides the actual optionality (per-agent, per-score, per-domain)
- P1 | D4 | "phases/expansion.md Step 2.2c cross-model dispatch" | 8-step iterative tier adjustment with "cap at 2 passes to prevent oscillation" — oscillation is a symptom of unstable decision criteria, capping doesn't fix the decision itself
- P2 | D5 | "SKILL.md Phase 1.2a.0 routing-overrides" | Routing overrides are an exclusion-only mechanism — no "prefer" or "require" counterpart; asymmetric decision affordance
- P2 | D6 | "phases/synthesize.md P0/P1 verdict logic" | "Any P0 → risky; any P1 → needs-changes" is anchored on single-finding severity, ignoring convergence — one flaky agent can force "risky" verdict
- P2 | D7 | "phases/expansion.md Step 2.2a.5 AgentDropout threshold" | Single 0.6 threshold with 4 additive components treats 0.4+0.3 (neighbors saturated) as equivalent to 0.3+0.3 (neighbor + finding density) — false equivalence
- P2 | D8 | "SKILL.md + SKILL-compact.md dual load" | The "load compact instead" directive is a decision with no documented criteria — reader can't tell when to prefer compact
Verdict: needs-changes

### Summary

The skill makes many automated decisions. Most are defensible — budget enforcement, slot ceilings, tier bonuses, expansion scoring. The trouble is cumulative: a review is ~20 autonomous decisions, and the only human intervention point is `--interactive`, which is opt-in and off by default. The auto-proceed default optimizes for speed and removes deliberation from the path. For a tool whose output drives beads creation and knowledge compounding (both of which feed back into future decisions), the blast radius of a bad decision is multi-session. Several decision criteria are binary where the underlying space is continuous (expansion score 0-3 collapses to expand/stop; challenger mode collapses to shadow/enforce; verdict logic treats any-P0 the same as all-agents-P0). A few decisions use anchored defaults without documenting the anchor's origin.

### Issues Found

1. D1. P1: Auto-proceed as default is a commitment without a cone of uncertainty. SKILL.md Step 1.3: "Auto-proceed (default): Proceed directly to Phase 2. No confirmation needed — the triage algorithm is deterministic and the user can inspect the table output." Determinism is not correctness. A deterministic wrong triage will still run. The user can inspect the table, but the skill proceeds while the table is being inspected (background dispatch). For expensive reviews (8 agents, 200K tokens), the cost of a wrong triage is meaningful. Fix: flip the default — human approval for reviews over N agents or M estimated tokens. Keep auto-proceed for small reviews. This is the "starter option" pattern — smallest commitment before scaling.

2. D2. P1: Expansion decision is a false dichotomy. `phases/expansion.md` Step 2.2b:
   | max(expansion_scores) | Decision |
   | >= 3 | AUTO-EXPAND |
   | 2 | AUTO-EXPAND |
   | <= 1 | AUTO-STOP |
   
   Score 2 and score 3 trigger the same action. Score 1 and score 0 trigger the same action. The decision has 4 input buckets but 2 output actions. A middle ground — "expand top 1 candidate at score >= 2, expand all at score >= 3" — would respect the signal gradient. Fix: decision table should be `>= 3: all eligible; 2: top-scored only; 1: starter option (one speculative); <= 0: stop`.

3. D3. P1: Shadow/enforce hides per-agent optionality. Challenger dispatch is "all agents run at original model" (shadow) vs "all agents run at adjusted model" (enforce). But the cross-model dispatch in expansion.md Step 2.2c allows per-agent decisions. Shadow-for-some and enforce-for-others is absent from the config surface. Fix: `cmd_mode: shadow|enforce|per-agent` with an override list.

4. D4. P1: 8-step iterative tier adjustment with oscillation guard. `phases/expansion.md` Step 2.2c § Cross-model dispatch does: (1) tentative adjustment, (2) recompute pressure, (3) if label changed, re-run (2 pass cap), (4) downgrade cap, (5) upgrade savings recycling, (6) pool-level quality assertion, (7) shadow-vs-enforce decision, (8) dispatch. The "2 pass cap" is a hack — if the algorithm oscillates, it means the pressure-to-adjustment function is non-monotonic. A stable algorithm wouldn't need an iteration cap. Fix: use a fixed-point formulation — all adjustments solved jointly as a constraint problem, one pass, no iteration.

5. D5. P2: Routing overrides are exclusion-only. `SKILL.md` Step 1.2a.0 reads `.claude/routing-overrides.json` and applies `"action": "exclude"`. There's no `"include"` or `"require"` or `"prefer"`. A user who wants fd-safety to always run (regardless of pre-filter) has no direct mechanism. `budget.yaml → exempt_agents` is close but is config not per-scope override. Fix: extend action vocabulary to `exclude|include|require|prefer` with documented precedence.

6. D6. P2: Verdict logic doesn't consider convergence. `phases/synthesize.md` Step 3.4a: "If any finding is P0 → 'risky'. If any P1 → 'needs-changes'. Otherwise → 'safe'." One agent's P0 produces "risky" regardless of how many agents reviewed or whether any other agent saw the same thing. A P0 from 3/5 agents is much stronger evidence than a P0 from 1/5. Fix: weight verdict by convergence count, e.g., "risky" if any P0 with convergence >= 2 OR any P1 with convergence >= 3 OR any P0 reported by safety-critical agent (fd-safety, fd-correctness).

7. D7. P2: AgentDropout threshold 0.6 is anchored, not derived. The 4-component scoring (0.4 + 0.3 + 0.2 + 0.1) sums to 1.0. Threshold 0.6 means: any 2 of {domain_converged, adjacency_saturated} drops the agent; `domain_converged (0.4) + adjacent_findings (0.2) + low_trust (0.1) = 0.7` drops; but `adjacency_saturated (0.3) + adjacent_findings (0.2) + low_trust (0.1) = 0.6` just barely drops. Where did 0.6 come from? Fix: add a calibration pass documented in a `config/flux-drive/dropout-calibration.md` — the number should come from measured precision/recall on historical data, not anchored intuition.

8. D8. P2: "Load compact instead" has no stated criteria. The HTML comment at SKILL.md top says: "compact: SKILL-compact.md — if it exists in this directory, load it instead". The decision "when to prefer compact" isn't stated. A reader with full context should use SKILL.md (it's more precise); a reader running low on tokens should use compact. But the directive says "load instead" unconditionally. Fix: state the criteria ("use compact when you need to orchestrate quickly without deep reference lookups; use SKILL.md when authoring or debugging the skill itself").

### Improvements

1. IMP-1. Document the cone of uncertainty for each automated decision. For triage scoring, AgentDropout, expansion, tier adjustment — what's the expected precision of the decision? If an expansion decision is 70% likely correct, auto-proceed is appropriate. If 50%, it should gate on human. Without uncertainty quantification, auto-proceed is asymmetric risk.

2. IMP-2. Add pre-committed signposts for human intervention. Signposts: (a) triage selects >8 agents, (b) estimated tokens >150K, (c) routing override excluded a cross-cutting agent, (d) expansion recommends >3 Stage 2 launches, (e) trust multiplier changed an agent's score by >2.0. Any of these fires an interactive gate.

3. IMP-3. Log all auto-decisions to `{OUTPUT_DIR}/decisions.log` with: decision point, inputs, rule applied, output chosen, reasoning. Enables post-hoc review and calibration.

4. IMP-4. Consider a "snake oil test" for compounding. Knowledge entries have a provenance note (independent/primed). Before a compounded entry reaches "used by many reviews", require at least one blind re-verification — a review that explicitly doesn't prime on the entry, to confirm the finding reproduces without prompting.

5. IMP-5. Starter option for new domains. When `domain_boost: +2` fires for a new domain, only promote the agent to Stage 1 if a human confirms once. After 3 confirmed promotions, auto-promote. This lets humans calibrate domain detection without forcing them to ack every run.

<!-- flux-drive:complete -->
