---
artifact_type: prd
bead: Demarch-csq
stage: design
---
# PRD: Diagnostic Maturation Skill

## Problem

Interhelm scaffolds diagnostic servers but doesn't guide agents beyond the skeleton. Agents stop at Level 1 (basic health endpoint returning a boolean) and don't build production-grade tooling like Shadow Work's sw-agent (6-subsystem health, 12-point smoke tests, expression evaluator, formatters, diff engine, REPL).

## Solution

A fourth interhelm skill (`diagnostic-maturation`) with two modes: a 6-level maturation ladder and a conformance audit.

## Features

### F1: Maturation Ladder (6 Levels)
**What:** Step-by-step guide from skeleton to production-grade operator toolkit.
**Acceptance criteria:**
- [ ] L1 (Domain Health): Guides identifying subsystems, defining healthy/degraded/unhealthy states, wiring detail fields
- [ ] L2 (Smoke Tests): Guides designing 5-15 E2E assertions with pass/fail/skip
- [ ] L3 (Assert Language): Guides building expression evaluator for scripted verification
- [ ] L4 (CLI Formatting): Guides building human-readable output with compact numbers, colored status
- [ ] L5 (Diff Engine): Guides snapshot-before/after with domain-specific deltas
- [ ] L6 (REPL + Watch): Guides adding interactive and continuous monitoring modes
- [ ] Each level has a "you know you're done when" verification gate

### F2: Conformance Audit Mode
**What:** Evaluate an existing diagnostic server against the maturation ladder.
**Acceptance criteria:**
- [ ] Checks which of the 6 levels are implemented
- [ ] Reports current level and specific gaps
- [ ] Provides actionable next steps for each gap

### F3: Test Updates
**What:** Update structural tests to expect 4 skills.
**Acceptance criteria:**
- [ ] test_skill_count expects 4 skills
- [ ] plugin.json lists 4 skills

## Non-goals
- No new templates (the existing Rust templates remain as-is)
- No new hooks or agents
- No runtime code — this is guidance, not implementation

## Dependencies
- Existing interhelm plugin structure
- Shadow Work sw-agent as reference (read-only, no modifications)
