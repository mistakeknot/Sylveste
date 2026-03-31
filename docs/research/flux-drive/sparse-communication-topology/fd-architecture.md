---
agent: fd-architecture
date: 2026-03-31
plan: docs/plans/2026-03-31-sparse-communication-topology.md
bead: sylveste-rsj.11
reviewed: true
---

# Architecture Review: Sparse Communication Topology

**Plan:** `docs/plans/2026-03-31-sparse-communication-topology.md`
**Primary file modified:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Supporting file created:** `interverse/interflux/config/flux-drive/discourse-topology.yaml`

---

### Findings Index

- P1 | ARCH-01 | "Convergence Gate vs. Topology" | Gate population mismatch creates calibration drift
- P1 | ARCH-02 | "Fixative Gini vs. Sparse Input" | Gini computed from full population, reacts to filtered subset
- P2 | ARCH-03 | "Default Role Assignment" | `default_role: editor` is wrong for most project-specific fd-* agents
- P2 | ARCH-04 | "Cognitive Agents in Linear Adjacency Chain" | Single adjacency topology erases cognitive-vs-technical distinction

---

## ARCH-01 — Convergence Gate vs. Topology (P1)

**Location:** `phases/reaction.md` Step 2.5.0 and plan Task 2, note on line 89.

The plan explicitly preserves the convergence gate's full-population overlap computation (Step 2.5.0 runs before topology filtering) while the reaction prompts operate on a filtered subset. This is architecturally inconsistent in a way that degrades over time.

The convergence gate asks: "Do enough agents agree that the reaction round adds no value?" It answers by counting how many agents independently reported the same P0/P1 findings. A high overlap ratio triggers a skip. When the gate passes (overlap is low, reaction proceeds), each agent then sees only a role-proximity subset of peer findings.

The problem is directional: the gate may decide "there is low convergence — reactions are needed" based on full-population diversity, but in a sparse topology that diversity was artificially produced because distant agents cannot see each other's findings. A `planner` (fd-architecture, fd-systems) and a `checker` (fd-resilience, fd-decisions, fd-people, fd-perception) will never surface the same P0/P1 finding just because they occupy distant roles — their domains are genuinely different. The gate counts their non-overlap as "heterogeneity worth reacting to" and proceeds, but then each `planner` agent only sees `reviewer`-role summaries and nothing from `checker`-role agents at all. The gate approved a reaction round that the topology then renders partially blind.

In a fully-connected run this is self-consistent. In a sparse-topology run the gate is calibrated against a population larger than what any single agent will see. This is not a breaking bug today — the gate's skip threshold (0.6) is conservative — but it becomes load-bearing if the threshold is ever tuned against sparse-run data. Any threshold calibration done against sparse runs would undercount true overlap and make the gate more aggressive about proceeding, compounding the inconsistency.

**Smallest viable fix:** The plan's Step 2.5.0 comment should be explicit that the gate's overlap ratio is computed against the *topologically-visible* population of each agent, not the full set. Concretely: when computing `overlap_ratio`, count a finding as shared only if it was reported by two agents that are at least `adjacent_role` to each other. Findings from `distant_role` agent pairs do not count toward the gate's overlap signal because those agents will not interact in the reaction round regardless. This keeps the gate semantically consistent with the topology it governs.

---

## ARCH-02 — Fixative Gini vs. Sparse Input (P1)

**Location:** `phases/reaction.md` Step 2.5.2b, `config/flux-drive/discourse-fixative.yaml`.

The fixative's Gini coefficient is computed from the Findings Indexes collected in Step 2.5.2. The plan states "No changes to Steps 2.5.0, 2.5.2b, 2.5.3, 2.5.4, or 2.5.5." This means the Gini is computed from the full agent population's finding counts, but the `imbalance` injection it produces is delivered to agents who see only a topological subset.

The `imbalance` injection text is: "If you have a perspective that differs from the dominant viewpoint, prioritize expressing it over confirming existing findings." This note is meaningful when an agent can observe the dominant viewpoint in its `{peer_findings}`. Under sparse topology, a `checker`-role agent (fd-resilience, fd-decisions) receives no findings from `planner`-role agents at all. The fixative may fire the `imbalance` injection because fd-architecture produced 8 findings and fd-resilience produced 2, creating a high Gini — but fd-resilience cannot see fd-architecture's findings, so the injection is hollow instruction: "push back against dominance you cannot observe."

The `convergence` injection has the same disconnect. It fires when `novelty_estimate < 0.1` — meaning most agents found the same things — but if sparse topology is creating artificial non-overlap across distant roles, the full-population novelty estimate is artificially high, suppressing a fixative that might be warranted within each role cluster.

These are not catastrophic failures; the fixative is designed as a nudge, not a controller. But they represent a pattern where two independent mechanisms (topology filter, fixative health check) are assembled sequentially without acknowledging they operate on different populations. The Sawyer metrics in synthesis (post-hoc) will eventually measure the real discourse quality, but the fixative's pre-synthesis role is specifically to correct for degradation before it manifests in synthesis. If the fixative's population model is wrong, it fires the wrong injections at the wrong agents.

**Smallest viable fix:** Before computing Gini in Step 2.5.2b, if topology is enabled, use topology-scoped finding counts: for each agent, count only findings from agents that are `same_role` or `adjacent_role`. This gives a Gini over the actually-visible discourse rather than the theoretical full population. It is a four-line change to the Gini computation loop and does not touch any other mechanism.

---

## ARCH-03 — Default Role Assignment for Project-Specific Agents (P2)

**Location:** `config/flux-drive/discourse-topology.yaml` (plan Task 1), `agent-roles.yaml`.

The plan assigns `default_role: editor` to any agent not found in `agent-roles.yaml`. There are 324 project-specific `fd-*` agents in `.claude/agents/`. None of them are in `agent-roles.yaml`. They all get `editor`.

In the adjacency map, `editor` sits between `reviewer` and `checker`. Agents assigned `editor` see full findings from other editors, summaries from reviewers and checkers, and nothing from planners. Given the role descriptions in `agent-roles.yaml`:

- `planner` — architectural decisions, systems thinking (fd-architecture, fd-systems)
- `reviewer` — detailed checking, correctness, safety (fd-correctness, fd-quality, fd-safety)
- `editor` — practical suggestions, UX, performance (fd-performance, fd-user-product, fd-game-design)
- `checker` — pattern matching, cognitive lens application (fd-perception, fd-resilience, fd-decisions, fd-people)

Project-specific agents like `fd-authority-rework-routing`, `fd-adversarial-architecture-exploitation`, `fd-alignment-recursive-improvement`, or `fd-autonomy-risk` are substantively closer to `planner` or `reviewer` than `editor`. Assigning them `editor` by default cuts them off from `planner`-role peer findings entirely (planners are two hops away from editors under the adjacency map), which is probably the most important peer signal for an architectural or safety-domain agent.

The `default_role: editor` choice is understandable as a conservative midpoint, but it is wrong for agents whose names indicate high-reasoning domains. It will silently degrade discourse quality for the majority of the project-specific agent population.

**Smallest viable fix:** Expose a per-agent `role` override field in `discourse-topology.yaml` so individual project-specific agents can be mapped without modifying `agent-roles.yaml`. A secondary option is to derive the default role from the agent file name prefix using a naming convention (e.g., agents with names matching `fd-*-architecture*`, `fd-*-safety*`, `fd-*-alignment*` default to `reviewer`). Either approach is incremental and backward-compatible. The current single `default_role` flat assignment is a forced simplification that collapses meaningful role distinctions.

---

## ARCH-04 — Cognitive Agents in a Linear Technical Adjacency Chain (P2)

**Location:** `config/flux-drive/discourse-topology.yaml` (plan Task 1), `agent-roles.yaml`.

The adjacency map is `planner ↔ reviewer ↔ editor ↔ checker`. This is a linear chain derived from the SC-MAS/Dr. MAS model-tier ordering in `agent-roles.yaml`, where roles correspond to decreasing reasoning capability requirements. The chain encodes capability tier, not epistemic proximity.

The `checker` role contains all four cognitive agents: fd-perception, fd-resilience, fd-decisions, fd-people. These agents are not weak versions of planners — they apply different analytical frameworks (systems perception, organizational resilience, decision theory, human factors). Under the linear adjacency map, cognitive agents (`checker`) can see summaries from `editor`-role agents but nothing from `planner`-role agents. This severs the most relevant pairing: fd-systems (planner) and fd-resilience (checker) are both systems-level thinkers whose findings should be mutually visible.

The `agent-roles.yaml` comment acknowledges the distinction: "cognitive agents review documents only" vs. technical agents. But the adjacency map does not encode this — it treats cognitive agents as lower-tier technical agents and positions them accordingly.

This is not a boundary violation; the linear chain is internally consistent within the technical-tier model. It is a category error: using a single linear topology for two orthogonal axes (capability tier and domain type). Technical agents are correctly ordered by tier. Cognitive agents are not tier-ordered relative to technical agents; they are domain-orthogonal.

**Smallest viable fix:** Add a second adjacency cluster or a cross-cluster visibility rule. The minimal change is to add an explicit `cross_cluster` adjacency in `discourse-topology.yaml` that allows cognitive agents (`checker` role) to also see summaries from `planner`-role agents and vice versa. This does not require changing the capability tier mapping in `agent-roles.yaml` — it is a topology overlay that decouples the communication graph from the model-tier graph.

Example addition to `discourse-topology.yaml`:

```yaml
cross_cluster_adjacency:
  checker:
    - planner   # cognitive agents should see planner-level systems thinking
```

This would give `checker` agents summary visibility into both `editor` (via chain adjacency) and `planner` (via cross-cluster), without changing any other mechanism.

---

## Summary

Two findings are structural concerns worth resolving before shipping (P1). The convergence gate and the fixative both compute metrics against a population that does not match the filtered population each agent will actually see. These are independent mechanisms assembled without shared population semantics — a pattern that compounds if either mechanism is later calibrated against live sparse-topology data.

Two findings are improvement candidates (P2). The `default_role: editor` assignment affects 324 project-specific agents and silently degrades discourse for high-reasoning domain agents. The linear adjacency chain collapses cognitive and technical agents into the same tier ordering, severing epistemically proximate pairings (fd-systems / fd-resilience).

The plan's backward-compatibility contract (disabled mode = fully-connected) is sound. The fallback path is clean. The two-file scope is appropriate. These concerns do not block the plan's core mechanism; they should be addressed as amendments before the config is enabled in production runs.
