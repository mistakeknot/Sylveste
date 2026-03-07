---
module: Clavain
date: 2026-02-10
problem_type: best_practice
component: documentation
symptoms:
  - "Agent descriptions lack concrete example blocks with commentary"
  - "Missing examples make agent triggering unreliable"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [agent-description, examples, triggering, conventions]
lastConfirmed: 2026-02-10
provenance: independent
review_count: 0
---

# Agent Description Example Blocks Required

## Problem

Agent descriptions must include concrete `<example>` blocks with `<commentary>` explaining when to trigger the agent. This convention is documented but was omitted in some agent sets.

## Solution

All agent description fields must include `<example>` blocks with `<commentary>`. Compare new agents against established convention documentation.

## Evidence

All 6 fd-v2-*.md agents (fd-v2-architecture, fd-v2-safety, fd-v2-correctness, fd-v2-quality, fd-v2-performance, fd-v2-user-product) at line 3 (description field) lacked `<example>` blocks, while v1 agents all included them.

## Prevention

Check agents/review/*.md frontmatter description fields for `<example>` blocks when creating new agents.
