---
artifact_type: prd
bead: sylveste-rsj.11
date: 2026-03-31
---

# PRD: Sparse Communication Topology

## Problem

The reaction round is fully connected — every agent sees every peer's findings. Research shows this promotes premature convergence and correlates errors (Zollman effect). The existing discourse mechanisms (Sawyer monitoring, fixative correction) can detect and respond to convergence, but they cannot prevent it structurally.

## Solution

Add domain-aware sparse topology to the reaction round's peer findings assembly. Same-domain agents share full findings, adjacent-domain agents share summaries only, distant-domain agents share nothing. Zero additional cost — filtering is applied to already-collected data.

## Scope

### In Scope
- Topology configuration (`discourse-topology.yaml`)
- Modified peer findings assembly in reaction phase Step 2.5.2
- Domain proximity matrix derived from existing agent-roles.yaml
- Graceful fallback to fully-connected when disabled or roles unknown

### Out of Scope
- Adaptive topology based on Sawyer health (Phase 2)
- Ring or random-sparse topology modes
- Project-specific agent role classification
- A/B measurement framework

## Success Criteria
1. Agents in the same role group see full peer findings (unchanged behavior within group)
2. Agents in adjacent role groups see summary-only (index line, no rationale)
3. Agents in distant role groups see no peer findings from that group
4. Topology is configurable and can be disabled (reverts to fully-connected)
5. No impact on synthesis, verdicts, health metrics, or convergence gate
