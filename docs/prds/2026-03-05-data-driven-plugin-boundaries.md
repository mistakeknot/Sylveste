---
artifact_type: prd
bead: iv-mtf12
stage: design
---

# PRD: Data-Driven Plugin Boundary Decisions

## Problem

The accuracy gap benchmark (iv-u74sq) proved that sequencing hints deliver +70% accuracy for multi-tool workflows, but only 4 hints exist today. Unhinted plugin pairs fail at the same rate as having no composition layer at all. There's no mechanism for within-domain disambiguation (interpath vs interdoc), and no documented criteria for when plugins should be consolidated.

## Solution

Audit documented workflows to find missing sequencing hints, add a new disambiguation hint type for within-domain confusion, expand tool-composition.yaml with findings, and establish a consolidation checklist for ongoing boundary evaluation.

## Features

### F1: Manual audit of multi-tool pipelines

**What:** Read all 45 commands and 16 skills in `os/clavain/` to identify every multi-tool pipeline and map which ones lack sequencing hints.

**Acceptance criteria:**
- [ ] Every command in `os/clavain/commands/*.md` reviewed for multi-plugin references
- [ ] Every skill in `os/clavain/skills/*/SKILL.md` reviewed for multi-plugin pipelines
- [ ] Audit output: table of (plugin_a, plugin_b, relationship, covered_by_hint) tuples
- [ ] Gap list: pipelines with no corresponding sequencing or disambiguation hint

### F2: Add disambiguation hints to tool-composition.yaml

**What:** New `disambiguation_hints` section in the YAML schema for within-domain plugin confusion, with Go parser and tool-surface output updates.

**Acceptance criteria:**
- [ ] `disambiguation_hints` section added to `tool-composition.yaml` with `plugins`, `domain`, and `hint` fields
- [ ] Go parser (`tool_surface.go`) updated to parse and render disambiguation hints
- [ ] `clavain-cli tool-surface` output includes a "Disambiguation" section
- [ ] `clavain-cli tool-surface --json` includes disambiguation_hints in JSON output
- [ ] BATS test validates disambiguation hints are parseable and <= 120 chars
- [ ] At least 1 disambiguation hint added (interpath vs interdoc from benchmark Task 10)

### F3: Expand sequencing hints from audit findings

**What:** Add new sequencing hints for multi-tool pipelines discovered in the F1 audit that currently lack hints.

**Acceptance criteria:**
- [ ] Each new hint has evidence (audit finding or benchmark result)
- [ ] Each hint is <= 120 characters (existing R3 ratchet)
- [ ] `tool-composition.yaml` updated with new hints
- [ ] BATS tests pass with expanded hint set
- [ ] Domain/curation groups lightly expanded if audit reveals new confusable clusters

### F4: Consolidation checklist

**What:** Document criteria for when plugin pairs should be consolidated (merged or given a facade), and record that no pair currently meets these criteria.

**Acceptance criteria:**
- [ ] Checklist documented with 4 criteria: hint > 120 chars, >3 hints per pair, persistent failure despite hints, cross-reference needed in tool descriptions
- [ ] Current assessment: "no consolidation needed as of 2026-03-05" recorded
- [ ] Checklist lives in a discoverable location (tool-composition.yaml comments or docs/)
- [ ] Reference to iv-qi80j for telemetry-based validation

## Non-goals

- Automated consolidation detection pipeline (deferred to telemetry phase)
- Runtime tool routing or Tool Search modifications
- Expanding domain groups proactively (only if audit reveals gaps)
- Auditing MCP server tools beyond skills/commands
- Hard cap on hint count (shedding cascade handles overflow)
- Repeating the benchmark with Sonnet/Haiku (separate bead)

## Dependencies

- iv-u74sq (closed): accuracy gap measurement results at `docs/research/accuracy-gap-measurement-results.md`
- iv-3kpfu (closed): shallow composition layer — `tool-composition.yaml` + `tool_surface.go`
- Go build environment for clavain-cli changes
- BATS test framework for shell tests

## Open Questions

1. Should disambiguation hints render as a separate "Disambiguation" subsection in tool-surface output, or inline with domain descriptions?
2. Should the 120-char limit apply to disambiguation hints (same as sequencing), or allow longer hints since disambiguation may need more context?
3. If the audit reveals >10 new hints, should we batch-add them all or phase in gradually to measure impact?
