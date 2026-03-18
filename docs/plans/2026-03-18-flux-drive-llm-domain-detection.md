# Plan: flux-drive LLM Domain Detection + flux-gen Dispatch

**Bead:** Demarch-b5md
**Date:** 2026-03-18

## Tasks

### Task 1: Update SKILL-compact.md

Replace Steps 1.0.1 and 1.0.4 with LLM classification and flux-gen dispatch.

### Task 2: Update SKILL.md

Same changes in the full version (Steps 1.0.1-1.0.4).

### Task 3: Verify scoring references

Ensure Step 1.2's `project_domains` and `domain_boost` still work — they should reference the LLM-classified domains from Step 1.0 instead of intersense.yaml.

### Task 4: Build + publish interflux

Bump version and publish so the changes are live.
