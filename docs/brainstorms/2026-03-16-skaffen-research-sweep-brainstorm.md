---
artifact_type: brainstorm
bead: Sylveste-6qb
stage: discover
---

# Skaffen Research Sweep — Academic Paper Evaluations

**Date:** 2026-03-16
**Bead:** Sylveste-6qb (Skaffen sovereign agent runtime epic)
**Phase:** brainstorm (as of 2026-03-16T05:56:36Z)

## What We Did

Evaluated all 7 open research children of the Skaffen epic in parallel. Each research bead references an academic paper or architectural design question relevant to Skaffen's agent loop, context management, or plugin system.

## Results

| Bead | Topic | Verdict | Assessment Doc |
|------|-------|---------|---------------|
| .1 | SPEAR prompt algebra (CIDR 2026) | inspire-only | assess-spear-prompt-algebra.md |
| .2 | SimpleMem entropy compression (Jan 2026) | inspire-only | assess-simplemem-context-compression.md |
| .3 | AgentFold learned folding (ICLR 2026) | inspire-only | assess-agentfold-context-folding.md |
| .4 | RLMs self-managing context (Prime Intellect) | inspire-only | assess-rlms-self-managing-context.md |
| .5 | MAGMA multi-graph retrieval (Jan 2026) | inspire-only | assess-magma-multi-graph-retrieval.md |
| .6 | SHIELDA root cause tracing (ICLR 2026) | inspire-only | assess-shielda-root-cause-tracing.md |
| .7 | Interverse plugin compatibility | **adopt (phased)** | assess-interverse-plugin-compatibility.md |

## Key Decisions

### D1: No academic paper warrants full adoption

Six of seven papers are "inspire-only" because they solve problems at a different scale or domain than a single-session API-consumer coding agent:

- **SPEAR** targets multi-stage LLM pipelines; Skaffen is single-call-per-turn
- **SimpleMem** targets lifelong multi-session memory; Skaffen is single-session
- **AgentFold/RLMs** require custom model fine-tuning; Skaffen uses API providers
- **MAGMA** targets 100K+ token retrieval stores; Skaffen manages 10-20 prompt sections
- **SHIELDA** lacks quantitative evaluation and requires infrastructure Skaffen doesn't have

### D2: Interverse plugin compatibility is the actionable outcome

The only "adopt" verdict. Skaffen's existing infrastructure (MCP client, skills, hooks) is ~80% compatible with Interverse plugins already. The gap is discovery, not protocol — ~865 lines of new Go code across 4 phases (~20 hours total). Phase 1 (MCP auto-discovery, ~4 hours) unlocks ~80% of plugin value.

### D3: Portable ideas to extract from papers

Concrete improvements to queue for Skaffen, ordered by impact:

1. **Multi-scale compaction** (from AgentFold): Replace `Compact()` single flat summary with tiered summary blocks at different granularities (~50 lines)
2. **Dynamic ContentFunc** (from SPEAR): Let priompt elements render dynamically based on phase/model/turn (~20 lines)
3. **FailureType taxonomy** (from SHIELDA): Add 5 coding-specific failure types to Evidence struct (~30 lines)
4. **Intent-aware compaction** (from MAGMA): Bias summaries toward debugging vs. feature-building based on current work
5. **Score-then-filter** (from SimpleMem): Inform D8 phase-boundary compaction implementation
6. **Sub-LLM delegation** (from RLMs): Spawn focused sub-agent for oversized tool results >30K tokens (v0.3+)

## Open Questions

- Should the 6 "inspire-only" research beads be closed now, or kept open until their portable ideas are implemented?
- Should .7 (plugin compat) graduate from research to a proper implementation epic with its own plan?

## Next Steps

1. Close research beads .1-.6 as "inspire-only — see assessment docs"
2. Promote .7 to implementation: create a plan from the assessment's phased rollout
3. Queue portable ideas as separate implementation beads under the parent epic
