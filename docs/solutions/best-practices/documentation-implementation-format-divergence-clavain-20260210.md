---
module: Clavain
date: 2026-02-10
problem_type: best_practice
component: documentation
symptoms:
  - "Architecture documentation states one format but implementation uses another"
  - "Design docs drift from implementation during mid-development changes"
root_cause: inadequate_documentation
resolution_type: documentation_update
severity: medium
tags: [documentation-drift, architecture, format-mismatch]
lastConfirmed: 2026-02-10
provenance: independent
review_count: 0
---

# Documentation-Implementation Format Divergence

## Problem

Architecture documentation can drift from implementation when design decisions change mid-development. This creates a documentation-implementation gap that misleads future developers and agents.

## Solution

Cross-reference architecture design decision descriptions with actual implementation formats. Look for format references that contradict actual implementation.

## Evidence

docs/research/flux-drive-v2-architecture.md describes "YAML frontmatter" as agent output format, but the actual implementation uses Findings Index (markdown format), creating a documentation-implementation gap.

## Prevention

Cross-reference architecture design decision descriptions with actual agent output formats in shared-contracts.md and agent prompt instructions. Look for format references that contradict actual implementation.
