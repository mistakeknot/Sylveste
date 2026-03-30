---
artifact_type: brainstorm
bead: sylveste-rsj.1.8
stage: brainstorm
---

# Compound Autonomy Guard — Brainstorm

## Problem

When Mycroft (fleet orchestrator) operates at tier T2 (auto-dispatch) and dispatches an agent with high capability level (L3), the **compound autonomy** exceeds what either entity was individually authorized for. Neither Mycroft nor the agent is "doing too much" alone, but the combination creates an unaddressed authority gap.

Example: Mycroft T2 can auto-dispatch agents. An L3-capable agent can create/close beads, push code, and modify CI. Together: Mycroft auto-dispatches an agent that auto-pushes code — nobody reviewed either decision.

## Current State

- Sprint autonomy tiers (1/2/3) govern human checkpoint frequency within a sprint
- Mycroft tiers (T0 observe → T1 suggest → T2 recommend → T3 auto-dispatch) govern fleet-level dispatch authority
- Fleet registry has `capabilities` per agent but no formal capability level (L0-L4)
- No mechanism checks the *product* of orchestrator tier × agent capability
- default-policy.yaml has phase-based path/tool deny rules but no compound authority check

## Design

### Agent Capability Levels

Define formal levels in fleet-registry.yaml:

| Level | Description | Examples |
|-------|------------|---------|
| L0 | Read-only observation | drift-check, status reporters |
| L1 | Analysis + suggestions | review agents (fd-*), interpeer |
| L2 | Local mutations (files, tests) | work execution, test runners |
| L3 | External effects (git push, bead mutations, publish) | ship, land, publish agents |
| L4 | Infrastructure changes (deploy, permissions) | reserved for future |

### Compound Autonomy Score

`compound_score = mycroft_tier × agent_level`

| Score | Risk | Policy |
|-------|------|--------|
| 0-2 | Low | Auto-proceed |
| 3-4 | Medium | Log + notify (advisory) |
| 6+ | High | Require human approval before dispatch |
| 9+ | Critical | Block — require explicit user opt-in |

T2 × L3 = 6 → High → human approval required.
T3 × L3 = 9 → Critical → blocked by default.
T1 × L2 = 2 → Low → auto-proceed.

### Implementation Touchpoints

1. **fleet-registry.yaml**: Add `capability_level: <0-4>` field per agent
2. **lib-fleet.sh**: Add `fleet_compound_autonomy_check()` function
3. **session-start.sh** (Mycroft context): Inject compound score into dispatch decision
4. **dispatch.sh**: Gate on compound score before launching agent
5. **default-policy.yaml**: Add compound autonomy thresholds

### What This Does NOT Do

- Does not change sprint autonomy tiers (those govern human involvement within sprints)
- Does not replace phase-based path/tool deny rules
- Does not add runtime enforcement (this is a dispatch-time gate)

## Key Decision

The guard runs at **dispatch time** (before agent starts), not at **action time** (within the agent). This is simpler and avoids the monitoring paradox flagged in the brainstorm — trying to watch agents in real-time creates its own autonomy cliff.
