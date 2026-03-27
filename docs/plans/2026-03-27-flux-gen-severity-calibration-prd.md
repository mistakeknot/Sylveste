---
bead: sylveste-pkx
title: "PRD: Fix flux-gen P0/P1 severity calibration"
date: 2026-03-27
type: prd
---

# PRD: Fix Flux-Gen P0/P1 Severity Calibration

## Problem Statement

Generated agents (created via `/flux-gen`) produce 0% P0/P1 findings across 120+ flux-drive runs. All high-severity signal comes from 6 core agents. This means project-specific agents — which should encode domain expertise — contribute only noise-level P2/P3 findings.

## Success Criteria

1. Generated agents produce P0/P1 findings when reviewing content that warrants it
2. Domain profiles provide severity anchors to all agents (core and generated)
3. The flux-gen LLM prompt produces agents with domain-specific decision methodology

## Features

### F1: Severity Calibration Block in Agent Template
- Add structured severity section to `render_agent()` in generate-agents.py
- Template renders `severity_calibration` field from agent spec into P0/P1/P2 guidance
- Fallback: if spec lacks calibration, generate domain-generic calibration from focus area

### F2: P0/P1/P2 Criteria Tables in Domain Profiles
- Backfill all 11 domain profiles with Review Criteria tables
- Format matches protocol.md:201 spec (Priority | Criterion | Check)
- Tables injected into agent prompts during flux-drive dispatch (existing injection path)

### F3: Enhanced Flux-Gen LLM Prompt
- Request `severity_calibration`, `review_sequence`, and `failure_scenarios` from LLM
- Update spec schema to include new fields
- Backward compatible: old specs without new fields render with fallback

## Non-Goals

- Changing core agent severity calibration (they work fine)
- Adding severity calibration to research agents (not applicable)
- Rethinking the P0-P3 severity scale itself

## Risks

- **Over-calibration**: Generated agents might flag everything as P0/P1 → mitigate with "When in doubt, describe the failure scenario" heuristic
- **LLM prompt regression**: Changing the generation prompt could reduce agent quality in other dimensions → mitigate by testing against existing agent specs

## Ordering

F3 (LLM prompt) → F1 (template) → F2 (domain profiles). F3 is highest-leverage; F1 makes it renderable; F2 is independent backfill.
