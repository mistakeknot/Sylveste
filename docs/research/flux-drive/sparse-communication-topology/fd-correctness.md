---
reviewer: fd-correctness (Julik)
date: 2026-03-31
plan: docs/plans/2026-03-31-sparse-communication-topology.md
bead: sylveste-rsj.11
verdict: needs-changes
---

# Correctness Review — Sparse Communication Topology

## Invariants

Before findings, the invariants this plan must preserve:

1. **Convergence gate uses ALL findings.** Step 2.5.0 runs before topology filtering and must continue to see every agent's findings unchanged.
2. **Reaction round skip is total or not at all.** Step 2.5.3 already specifies: if `{peer_findings}` is empty, skip this agent. That rule must remain correct after topology filtering changes what "empty" means.
3. **Fixative health metrics must not be distorted by topology filtering.** Step 2.5.2b computes Gini and novelty from collected indexes — these must reflect the real discourse state, not a filtered view.
4. **Synthesis correctness is unaffected.** Topology affects what agents see during the reaction round; it must not touch what synthesis reads in Phase 3.
5. **Fallback to fully-connected is loss-free.** When `topology.enabled: false` or the file is missing, behavior must be identical to the current implementation.
6. **Agent role lookup is total.** Every agent dispatched in Phase 2 must resolve to exactly one role. The `default_role: editor` handles unknown agents — this must apply before any adjacency check, not after a failed lookup.

---

## Findings Index

- P1 | SCT-01 | "Task 2, Step 3" | Topology filtering runs before fixative metric computation — Gini and novelty will be computed on filtered peer sets, not the real discourse state
- P1 | SCT-02 | "Task 2, Step 6 / Plan Overview" | Degenerate-topology silent miss: 2-agent reviews with non-adjacent roles produce empty peer_findings for both agents and trigger the "skip this agent" guard, making the reaction round silently a no-op
- P1 | SCT-03 | "Task 1, adjacency map" | Planner and checker are topological dead-ends: each has exactly 1 neighbor, meaning planner never sees checker or editor findings and checker never sees planner or reviewer findings — domain isolation is too aggressive for safety-critical agents
- P2 | SCT-04 | "Task 2, Step 2" | Missing role validation: agent-roles.yaml contains only 9 of 12 review agents — fd-game-design, fd-user-product, and fd-performance are listed under 'editor' but any generated fd-* agent not in the YAML silently gets default_role: editor, which may place domain experts in the wrong adjacency zone
- P2 | SCT-05 | "Task 1, discourse section in reaction.yaml" | Topology config is not registered in reaction.yaml 'discourse:' section despite the plan instructing it to be — the plan shows the YAML change as a note but Task 1 only creates the file, leaving the registration as implicit
- P2 | SCT-06 | "Task 2, Step 6 (log line)" | Log line reports topology metrics but not per-agent visibility assignments — a planner seeing 0 findings from checkers with no log trace makes silent isolation undetectable during post-run analysis

---

## Findings Detail

### SCT-01 — Fixative metrics computed on filtered view (P1)

**Location:** Task 2, Step description ordering. The plan states:

> Step 2.5.2: topology-aware assembly ... Step 2.5.2b: Discourse Fixative Health Check

The plan's Step 2.5.2 builds per-agent filtered `peer_findings` and that is the only in-scope change to the step. But Step 2.5.2b (the fixative health check, which already exists) reads "the Findings Indexes already collected in Step 2.5.2."

The plan does not say whether Step 2.5.2b should receive the pre-filter or post-filter indexes. Because the topology-aware assembly replaces the single-pass in Step 2.5.2 and the fixative step immediately follows with "already collected," the natural reading is that 2.5.2b will see whatever 2.5.2 produced — which is now per-agent filtered sets.

**Concrete failure:** In a 5-agent run where 2 planner agents find 6 P0/P1 issues each and 3 editor agents find 0, the fixative's Gini computation would see only the 3 editor agents' (empty) contributions (since planners and editors are not adjacent). The real Gini is high (2 agents dominate); the computed Gini is 0 (uniform empty). No imbalance injection fires. The echo-chamber collapse injection also fails to fire. The fixative that was designed exactly for this case becomes blind to it.

**Fix:** The plan must explicitly state that Step 2.5.2b receives the **pre-filter indexes** — i.e., the full per-agent finding counts before topology masking. The topology-filtered view is only used for building `{peer_findings}` strings passed to reaction prompts.

---

### SCT-02 — Degenerate topology: 2-agent dispatch with non-adjacent roles (P1)

**Location:** Plan overview, "Zero new dispatches. Fully backward-compatible."

The existing Step 2.5.3, item 3, reads:

> If `{peer_findings}` is empty for this agent (no other agents found P0/P1 issues), skip this agent — no reaction needed.

This guard was designed for the case where peers found nothing. Topology filtering introduces a new way for `peer_findings` to be empty: the peer found issues but is invisible due to role distance. The skip guard fires on both cases identically.

**Failure interleaving for a 2-agent review:**

1. Flux-drive dispatches fd-architecture (planner) and fd-decisions (checker).
2. Both agents complete Phase 2 with substantive findings.
3. Step 2.5.0: overlap is low, reaction round proceeds.
4. Step 2.5.2 topology filter: planner adjacency = [reviewer] only; checker adjacency = [editor] only. Neither agent is adjacent to the other.
5. fd-architecture builds peer_findings: fd-decisions is distant role → excluded → `peer_findings` = empty.
6. fd-decisions builds peer_findings: fd-architecture is distant role → excluded → `peer_findings` = empty.
7. Step 2.5.3 guard fires for both agents: "no other agents found P0/P1 issues" (factually wrong — they did, they're just filtered out). Both agents skip.
8. Step 2.5.5 reports: "2 agents dispatched, 0 reactions produced, 2 empty (no relevant peer findings)."

The report looks like a healthy empty-reaction round. The operator sees no anomaly. The reaction round produced nothing despite both agents having findings the other should have seen, at minimum via the asymmetry gate's domain criterion.

This is not an edge case. Cognitive agents (fd-decisions, fd-resilience, fd-perception, fd-people) are all checkers. Architecture and systems agents are planners. A document review that dispatches fd-architecture + fd-resilience, or fd-systems + fd-perception, hits this path. These are common co-dispatch pairs on plan documents.

**Fix:** Distinguish the two empty cases at the skip guard. If `peer_findings` is empty due to topology filtering (some peers exist but are all distant), log:

```
Topology: {agent} has no adjacent peers in this dispatch — skipped (topology-isolated, not findings-empty)
```

And consider a minimum-visibility fallback: if an agent would be completely isolated (all peers distant), promote their nearest role's findings to `summary` visibility rather than `none`. This preserves sparse topology for high-cardinality reviews while preventing total blackout in small dispatches.

---

### SCT-03 — Dead-end roles: planner and checker have 1 neighbor each (P1)

**Location:** Task 1, `adjacency` map:

```yaml
adjacency:
  planner: [reviewer]
  reviewer: [planner, editor]
  editor: [reviewer, checker]
  checker: [editor]
```

The chain is: `planner ↔ reviewer ↔ editor ↔ checker`. Planner and checker are terminal nodes.

fd-architecture and fd-systems are planners. fd-correctness, fd-quality, and fd-safety are reviewers. fd-architecture is the agent most likely to find structural issues that safety (reviewer) and correctness (reviewer) need to know about — and they ARE adjacent (planner ↔ reviewer). That part is fine.

The problem is checker agents: fd-decisions, fd-resilience, fd-perception, fd-people. These never see planner or reviewer findings in the reaction round. In practice, fd-resilience (checker) is exactly the agent whose reaction to an fd-architecture finding about fragile module boundaries is most valuable — the architectural plan and the resilience lens are naturally complementary. With this topology, fd-resilience will never see fd-architecture findings.

Symmetrically, fd-architecture (planner) will never see checker findings. A resilience blind spot that fd-resilience flags will never reach the architect's reaction round.

**Note:** This does not corrupt synthesis — synthesis still reads all findings. The loss is specifically in the reaction round's cross-domain contestation, which is the entire value of the reaction round. A finding that only checkers noticed, but which an architect would contest, never gets contested.

**Fix options:**

- Option A: Make the chain bidirectional at distance 2 with summary-only visibility, preserving the chain structure but allowing planner↔editor and reviewer↔checker summary links.
- Option B: Give planner a second adjacency entry: `planner: [reviewer, checker]` — connect the domain experts at the extremes. This is non-symmetric but reflects actual review complementarity.
- Option C: Leave the chain as designed but document explicitly that planner↔checker cross-examination is intentionally sacrificed. The current plan has no such documentation and the chain structure looks like an accidental omission rather than a deliberate tradeoff.

Of the three, Option C is the minimum required change — at least make the limitation explicit so operators can override `adjacency` in their local config.

---

### SCT-04 — Generated fd-* agents have no role assignment and silent default (P2)

**Location:** Task 2, Step 2 — role lookup.

The plan correctly notes: "Agents not in the map get `default_role` from topology config." The default is `editor`.

The flux-gen command generates project-specific agents with names like `fd-broadcast-engineering`, `fd-fermentation-culture`, `fd-dispatch-intelligence`. The new `.claude/agents/` directory has 36 such generated agents visible in the git status. None of these are in `agent-roles.yaml`.

All 36 generated agents will be treated as editors. If a generated `fd-dispatch-intelligence` agent (which may have planner-level concerns) is co-dispatched with `fd-architecture` (planner), they are adjacent (editor ↔ reviewer ↔ planner is 2 hops — not adjacent). The dispatch agent gets summary at best, nothing at worst.

More critically: if two generated agents are co-dispatched (both default to editor), they will see each other's full findings (same_role → full). This is correct behavior — same role = full visibility. But the assignment is arbitrary; the agent may not actually be an "editor" in the MAS taxonomy sense.

This is a P2 because the default is reasonable (editor sits in the middle of the chain and has the most adjacency connections) and the alternative (no default, crash on unknown agent) is worse. But it should be documented explicitly and the role lookup should log which agents used the default.

---

### SCT-05 — Topology config not wired into reaction.yaml discourse section (P2)

**Location:** Task 1, last paragraph.

The plan says: "Also register in reaction.yaml under `discourse:`". The current `reaction.yaml` has:

```yaml
discourse:
  sawyer: discourse-sawyer.yaml
  lorenzen: discourse-lorenzen.yaml
  fixative: discourse-fixative.yaml
```

Task 1 creates the YAML file but the plan does not include an explicit edit to `reaction.yaml`. The verification checklist (item 3) says "Grep for `discourse-topology` in reaction.yaml — registered in discourse section" — but this will fail unless Task 1 is understood to include the `reaction.yaml` edit.

This is ambiguous in the plan text. If implementors read "Also register" as part of the file creation task, they may create the file and move on, leaving the registration undone until the verification step catches it. That's a test-time failure, not a silent production failure, so P2.

**Fix:** Expand Task 1 to include an explicit sub-task: "Edit `config/flux-drive/reaction.yaml`, add `topology: discourse-topology.yaml` under `discourse:`."

---

### SCT-06 — Log line insufficient for post-run observability of topology isolation (P2)

**Location:** Task 2, Step 6.

The proposed log line:

```
Topology: domain-aware (5 agents, 8 full, 4 summary, 3 excluded)
```

This tells you that 3 edges were excluded globally, but not which agents were isolated or what they missed. In a production review, if synthesis produces an unexpected verdict, there is no way to reconstruct which agent saw which peers without re-running with topology disabled.

The fixative's existing logging (`Fixative: active (2 injections: imbalance, convergence)`) is more granular because it names the injections. The topology log should similarly name the isolated agents.

Suggested format:

```
Topology: domain-aware (5 agents, 8 full, 4 summary, 3 excluded)
  Isolated: fd-architecture→fd-decisions (planner→checker), fd-systems→fd-perception (planner→checker)
```

Or at minimum: emit a per-agent line in debug mode showing each agent's peer visibility table.

---

## Summary

| ID | Severity | Location | Issue |
|----|----------|----------|-------|
| SCT-01 | P1 | Task 2, step ordering | Fixative metric computation will see filtered indexes instead of full discourse state |
| SCT-02 | P1 | 2-agent dispatch edge case | Non-adjacent role pairs → both agents silently isolated → reaction round no-op with misleading report |
| SCT-03 | P1 | adjacency map design | Planner and checker are dead-ends; planner↔checker cross-examination never happens |
| SCT-04 | P2 | generated agent role lookup | 36+ generated fd-* agents silently default to editor with no logging |
| SCT-05 | P2 | Task 1 scope | reaction.yaml topology registration described but not explicitly tasked |
| SCT-06 | P2 | Step 6 log line | Log shows aggregate counts but not which agents were isolated |

**Blocking for ship:** SCT-01 and SCT-02 must be addressed before implementation. SCT-03 needs at minimum a documented decision (accept or fix). SCT-04, SCT-05, SCT-06 are improvements that can follow.
