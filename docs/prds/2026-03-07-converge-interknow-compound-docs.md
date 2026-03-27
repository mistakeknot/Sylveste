---
artifact_type: prd
bead: Sylveste-7xs
stage: design
---

# PRD: Converge Interknow + Compound Docs

## Problem

Two separate systems store C4 (Curated Knowledge) with different schemas, write paths, retrieval methods, and lifecycle policies. Neither checks the other for duplicates. Agents must search both when looking for known patterns.

## Solution

Converge into a single system: `docs/solutions/` as storage, `/clavain:compound` as write path, compound docs schema extended with interknow's provenance model.

## Deliverables

### P1: Extend compound docs schema with provenance fields

Add 3 optional fields to `os/clavain/skills/engineering-docs/schema.yaml`:
- `lastConfirmed: YYYY-MM-DD` — date of last independent re-observation
- `provenance: independent|primed` — how the entry was confirmed
- `review_count: integer` — times surfaced during reviews (for decay tracking)

Update `engineering-docs` skill (SKILL.md) to write these fields on new entries.

### P2: Migrate interknow entries to docs/solutions/

For each of the 9 entries in `config/knowledge/`:
- Map to compound docs schema (add problem_type, component, severity, etc.)
- Preserve original lastConfirmed and provenance values
- Write to `docs/solutions/{category}/`
- Add deprecation notice to `config/knowledge/README.md`

### P3: Update interknow tooling to point at docs/solutions/

- `/interknow:recall` skill → search `docs/solutions/` instead of `config/knowledge/`
- `/interknow:compound` skill → redirect to `/clavain:compound` with deprecation notice
- interknow SessionStart hook → report from `docs/solutions/`

### P4: Backfill provenance on existing compound docs

For all 32 existing entries without provenance fields:
- Set `lastConfirmed` = existing `date` field
- Set `provenance` = `independent`
- Set `review_count` = `0`

## Non-goals

- Implementing the unified `/recall` command (that's Sylveste-h22, depends on this)
- Implementing decay/archival logic (that's part of Sylveste-ecb)
- Removing `config/knowledge/` directory (keep as read-only fallback until all consumers verified)
- Changing interflux's consumer code (separate follow-up)

## Acceptance Criteria

- [ ] schema.yaml includes lastConfirmed, provenance, review_count as optional fields
- [ ] engineering-docs SKILL.md writes provenance fields on new entries
- [ ] All 9 interknow entries exist in docs/solutions/ with valid frontmatter
- [ ] /interknow:recall searches docs/solutions/ as primary source
- [ ] /interknow:compound redirects to /clavain:compound
- [ ] All 32 existing compound docs have provenance backfill
- [ ] config/knowledge/README.md has deprecation notice
