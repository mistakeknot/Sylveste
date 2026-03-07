---
module: Clavain
date: 2026-02-10
problem_type: best_practice
component: tooling
symptoms:
  - "Orchestrator instructions describe pipelining or concurrent execution that the execution model doesn't support"
  - "Instructions like 'start X while preparing Y' fail in sequential execution"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [orchestrator, execution-model, sequential, instructions]
lastConfirmed: 2026-02-10
provenance: independent
review_count: 0
---

# Aspirational Execution Instructions

## Problem

Orchestrator instructions should not describe execution patterns that are impossible given the execution model. Pipelining or concurrent execution instructions fail when the orchestrator executes tool calls sequentially.

## Solution

Review orchestrator dispatch instructions for concurrent/parallel/pipeline terminology. Check if the orchestrator actually supports the described execution model (async tool calls, deferred injection, parallel preparation).

## Evidence

skills/flux-drive/phases/launch.md Step 2.1a instructs "Start qmd queries before agent dispatch. While queries run, prepare agent prompts" but Claude Code orchestrator executes tool calls sequentially with no pipelining mechanism. This creates false expectations and could lead to skipped knowledge injection.

## Prevention

Review orchestrator dispatch instructions for concurrent/parallel/pipeline terminology. Check if the orchestrator actually supports the described execution model.
