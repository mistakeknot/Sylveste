---
module: Clavain
date: 2026-02-10
problem_type: best_practice
component: documentation
symptoms:
  - "Agent merge mappings missing some agents from old roster"
  - "Capability loss risk when consolidating N agents to M"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [agent-merge, consolidation, capability-tracking, accountability]
lastConfirmed: 2026-02-10
provenance: independent
review_count: 0
---

# Agent Merge Accountability

## Problem

When consolidating agents (N-to-M merge), missing agents in merge mappings create "where did agent X go?" confusion and risk capability loss.

## Solution

Explicitly document where each retired agent's capabilities were absorbed. Every agent in the old roster should appear in at least one merge target, even if capability overlap is partial.

## Evidence

fd-v2 19-to-6 merge listed architecture-strategist → fd-v2-architecture, but data-migration-expert and spec-flow-analyzer were absent from the merge table despite being in the v1 roster. The merge table showed 16 agents mapped but claimed 19 were replaced.

## Prevention

Count agents in "before" roster vs agents listed in merge mapping table. Every agent in the old roster should appear in at least one merge target.
