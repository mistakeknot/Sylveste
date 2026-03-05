---
artifact_type: brainstorm
bead: iv-mtf12
stage: discover
---

# Brainstorm: Let Data Determine Plugin Boundary Decisions

**Bead:** iv-mtf12
**Date:** 2026-03-05
**Depends on:** iv-u74sq (accuracy gap measurement — closed)

## What We're Building

A data-driven framework for deciding plugin boundary changes (keep separate with hints, add disambiguation, or consolidate). Consumes the accuracy gap research results and produces concrete changes to `tool-composition.yaml` plus a consolidation checklist for ongoing boundary evaluation.

The benchmark (iv-u74sq) established:
- **Sequencing hints dominate:** +70% accuracy improvement for multi-tool workflows
- **Discovery metadata is marginal:** +20%, mostly from name disambiguation
- **Scale is a non-issue:** 0% gap — the model handles 49 plugins fine
- **No consolidation signal:** No plugin pair required deep docs or merging

## Why This Approach

### 1. Hybrid discovery: manual audit now + telemetry later

Rather than waiting weeks for telemetry data (iv-qi80j), do a manual audit of Clavain's 45 commands and 16 skills to find multi-tool pipelines that lack sequencing hints. This unblocks immediate improvements while telemetry collects real-world data for validation.

**Rationale:** The 4 current hints cover critical pipelines but the benchmark showed unhinted pairs score poorly (Task 10: interpath vs interdoc). A manual audit will find obvious gaps faster than waiting for instrumentation.

### 2. Two hint types: sequencing + disambiguation

**Sequencing hints** (existing): `first → then` ordering for multi-tool pipelines.
**Disambiguation hints** (new): `when` clauses for within-domain confusion.

Example disambiguation hint:
```yaml
disambiguation_hints:
  - plugins: [interpath, interdoc]
    domain: docs
    hint: "interpath generates artifacts (roadmaps, changelogs); interdoc manages AGENTS.md"
```

The benchmark showed the model confuses plugins within the same domain (Task 10: interpath vs interdoc for "generate docs then check drift"). Sequencing hints don't help here because the issue isn't order — it's selection. A new `disambiguation_hints` section addresses this directly.

### 3. No hard cap on hints — shedding cascade decides

At ~50 chars/hint formatted, even 20 hints = ~1000 chars. The SessionStart context has a 10K char cap with priority-based shedding. Composition context sheds before discovery context, so overflow is handled gracefully. Let every hint that demonstrably improves accuracy earn its place.

### 4. Domain/curation groups: keep, lightly expand

Current 8 domains and 4 curation groups are adequate. Only add new groups if the manual audit reveals confusable plugin pairs not covered by existing groups. Don't proactively expand.

### 5. Consolidation checklist (proactive, not reactive)

Build criteria for when to merge plugins, even though no pair currently triggers consolidation:
- Hint exceeds 120-char limit (the R3 ratchet)
- More than 3 hints exist between the same plugin pair
- Persistent failure rate despite hints (once telemetry is available)
- Tool descriptions need cross-references to explain interaction

Document that as of 2026-03-05, no plugin pair meets these criteria.

## Key Decisions

1. **Manual audit scope:** All 45 commands and 16 skills in `os/clavain/` — these define the documented multi-tool workflows
2. **New hint type:** `disambiguation_hints` with `plugins`, `domain`, and `hint` fields — addresses within-domain confusion
3. **No hint budget cap:** Let shedding cascade handle overflow; each hint must have evidence (benchmark or audit finding)
4. **Consolidation is a checklist, not a mechanism:** Document criteria for human/agent evaluation, not an automated pipeline
5. **tool-composition.yaml grows:** New `disambiguation_hints` section; existing sections stay, may get light additions from audit
6. **Follow-up:** iv-qi80j (audit real sessions for unhinted pipelines) remains open for telemetry-based validation

## Open Questions

1. **Schema change:** Adding `disambiguation_hints` requires updating the Go parser (`tool_surface.go`) and the `tool-surface` output format. How should disambiguation hints render in the SessionStart context?
2. **Audit granularity:** Should we audit plugin-level tools (MCP server tools) in addition to skills/commands, or are skills/commands sufficient to find pipelines?
3. **Test update:** The existing BATS test enforces sequencing hints <= 120 chars. Should disambiguation hints have the same limit, or a different one?
4. **Curation group expansion:** If the audit finds a new confusable cluster, should it become a curation group, a disambiguation hint, or both?
