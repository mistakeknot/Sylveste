# PRD: Systematic Mutation Engine for Autoresearch

**Bead:** Sylveste-vd1
**Date:** 2026-03-16
**Brainstorm:** `docs/brainstorms/2026-03-16-mutation-engine-brainstorm.md`

## Problem

Autoresearch campaigns rely on LLM-generated hypotheses (free-text ideas). These are creative but non-reproducible, non-composable, and non-trackable. Structured mutation types give the campaign deterministic, exhaustive search before falling back to creative ideation.

## Goals

1. **Mutation types in campaign YAML** — 7 types: parameter_sweep, swap, toggle, scale, remove, reorder, enum_sweep
2. **Expand mutations to concrete experiments** at campaign load time with content-addressable IDs
3. **Track mutation provenance** in ExperimentRecord (mutation_id, mutation_type)
4. **Surface next mutation** via init_experiment response so the skill knows what to change
5. **Mutations before ideas** — deterministic search first, creative tail second

## Non-Goals

- Composable mutations (cartesian products) — v2
- Adaptive ordering (binary search within sweeps) — v2
- Auto-detection of mutation targets from code analysis — v2

## Deliverables

### D1: Mutation Types in Campaign YAML
Extend `Campaign` struct with `Mutations []Mutation`. Each mutation has a type discriminator and type-specific fields. Validate at load time. Expand to `[]ExpandedMutation` with unique IDs.

### D2: ExperimentRecord Extension
Add `MutationID` and `MutationType` fields. Existing records with empty fields remain valid (backward compatible).

### D3: Segment Mutation Tracking
Track completed mutation IDs in Segment. On resume, skip completed mutations. Surface pending count in Snapshot.

### D4: init_experiment Response Extension
Return `next_mutation` object when mutations are pending. Return null when exhausted (agent falls back to ideas).

### D5: Skill Update
Update `/autoresearch` SKILL.md: check `next_mutation` before ideas, execute structured changes for each mutation type.

## Success Criteria

1. A campaign with `parameter_sweep` generates the correct number of experiments
2. Resume after crash skips already-completed mutations
3. Mutation IDs are deterministic — same YAML produces same IDs
4. Existing campaigns without mutations field continue to work unchanged
