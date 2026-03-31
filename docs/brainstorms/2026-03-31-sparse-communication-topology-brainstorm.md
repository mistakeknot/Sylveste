---
artifact_type: brainstorm
bead: sylveste-rsj.11
date: 2026-03-31
stage: discover
---

# Brainstorm: Sparse Communication Topology

**Date:** 2026-03-31
**Trigger:** Research finding from fd-swarm-ensemble-frontier: "Sparse communication topology outperforms fully-connected for preserving diversity." Currently interflux's reaction round is fully connected — every agent sees every peer's findings.
**Builds on:** rsj.7 (Sawyer health monitoring), rsj.9 (discourse fixative), rsj.2 (reaction round)

## The Problem

In the current reaction round (Step 2.5.2), each agent receives a **combined** peer findings summary containing ALL other agents' P0/P1 findings. This is fully-connected topology:

```
    A ──── B
    │╲   ╱│
    │ ╲ ╱ │
    │  X  │
    │ ╱ ╲ │
    │╱   ╲│
    C ──── D
```

With 6 agents, each sees 5 peers' findings. The research shows this promotes premature convergence — agents gravitate toward the consensus view rather than maintaining independent perspectives. The Zollman effect (from epistemic network theory) demonstrates that fully-connected networks converge faster but on the **wrong** answer more often than sparse networks.

## The Research Basis

**fd-swarm-ensemble-frontier findings:**
- Sparse topologies preserve cognitive diversity longer than fully-connected
- The optimal topology depends on problem ruggedness (NK landscape theory)
- For review tasks (moderately rugged), ring or small-world topologies outperform complete graphs

**fd-cognitive-diversity-topology findings:**
- Hong-Page theorem: diversity beats ability when errors are uncorrelated
- Fully-connected communication **correlates** errors by exposing all agents to the same information
- Boundary objects (Star & Griesemer): shared substrates plastic enough for local adaptation

**Kelvin boundary propagation (fd-tidal-resonance):**
- Route information along cluster boundaries, not broadcast
- Exponential decay away from interface
- Agents in the same domain should share more; agents across domains should share less

## Design: Domain-Aware Sparse Topology

Instead of every agent seeing all peers, constrain visibility based on **domain proximity**:

### Topology Rules

1. **Same-domain agents** see each other's findings (full within-domain connectivity)
   - fd-safety and fd-correctness are both "reviewer" role → they share findings
   - fd-architecture and fd-systems are both "planner" role → they share findings

2. **Adjacent-domain agents** see a summary (index only, not full findings)
   - Technical agents see cognitive agents' finding titles
   - Cognitive agents see technical agents' finding titles

3. **Distant-domain agents** see nothing from each other
   - fd-game-design doesn't need to see fd-safety's findings
   - fd-perception doesn't need fd-performance's findings

### Domain Proximity Matrix

Using the existing role assignments from `agent-roles.yaml`:

```
           planner  reviewer  editor  checker
planner      FULL    SUMMARY    —       —
reviewer   SUMMARY    FULL   SUMMARY   —
editor       —      SUMMARY    FULL   SUMMARY
checker      —        —      SUMMARY   FULL
```

- **FULL:** Complete peer findings (current behavior within this group)
- **SUMMARY:** Finding IDs + titles only (one-line per finding, no rationale)
- **—:** No visibility (this agent doesn't see that group's findings)

### Implementation

The change is in **Step 2.5.2** where peer findings are assembled. Currently:

```
For each agent: peer_findings = ALL other agents' findings
```

With sparse topology:

```
For each agent:
  same_domain = full findings from same-role agents
  adjacent_domain = summary-only from adjacent-role agents
  peer_findings = same_domain + adjacent_domain
  # distant-domain agents are excluded entirely
```

### Configuration

```yaml
# discourse-topology.yaml
topology:
  enabled: true
  mode: domain-aware  # Options: fully-connected, domain-aware, ring, random-sparse
  domain_proximity:
    same_role: full         # Complete findings exchange
    adjacent_role: summary  # Index lines only
    distant_role: none      # No visibility
  # Role adjacency (from agent-roles.yaml)
  adjacency:
    planner: [reviewer]
    reviewer: [planner, editor]
    editor: [reviewer, checker]
    checker: [editor]
```

## Why This Works

1. **Preserves independent analysis.** Distant-domain agents never see each other's findings, so their reactions are based entirely on their own analysis + their domain neighbors.

2. **Maintains cross-domain bridges.** Adjacent-domain agents see summaries — enough to react to ("I see fd-safety flagged a trust boundary issue — from my architecture perspective, this is actually the expected design") without being influenced by the full reasoning.

3. **Zero additional cost.** The topology just filters what's already collected. No new dispatches, no new data.

4. **Compatible with all existing mechanisms.** The fixative (rsj.9) still works — it checks health metrics across ALL agents. Sawyer (rsj.7) still monitors ALL findings. Lorenzen move validation still applies. The topology only constrains what agents SEE in reaction prompts, not what's measured or synthesized.

5. **Graceful degradation.** If topology is disabled, behavior reverts to fully-connected (current default). If agent-roles.yaml doesn't define roles for an agent, it defaults to seeing all peers.

## What the Topology Does NOT Change

- Phase 2 (initial review): agents still work independently — no change
- Convergence gate: still computed from ALL findings — no change
- Synthesis: still reads ALL agent outputs — no change
- Verdicts: still based on ALL findings — no change
- Health metrics: still computed from ALL agents — no change

The sparse topology ONLY affects what agents see in their **reaction prompts** (Phase 2.5).

## Open Questions

1. **Should project-specific agents (fd-*) follow the same topology?** They don't have roles in agent-roles.yaml. Default: treat as "editor" role (adjacent to reviewer and checker).

2. **Should the topology adapt based on Sawyer health?** If participation Gini is high (imbalanced), the fixative could temporarily widen connectivity to help isolated agents. This is Phase 2.

3. **How do we measure the effect?** Compare novelty_rate and DWSQ (diversity-weighted signal quality) between reviews with and without topology. The metrics exist (rsj.7). The comparison requires enough review runs to be statistically meaningful.
