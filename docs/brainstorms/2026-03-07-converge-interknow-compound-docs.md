---
artifact_type: brainstorm
bead: Demarch-7xs
stage: discover
---

# Converge Interknow + Compound Docs

**Date:** 2026-03-07
**Bead:** Demarch-7xs (P2 feature)
**Parent:** iv-nnxzo (Memory Architecture Convergence, R3.2)

## Current State

### Interknow (interverse/interknow/)

- **9 entries** in `config/knowledge/` (0 archived)
- **Simple schema:** 2 frontmatter fields — `lastConfirmed` (date), `provenance` (independent|primed)
- **Entry format:** 1-3 sentence generalized heuristic + evidence anchors + verification steps
- **Read path:** `/interknow:recall` — semantic search via qmd MCP server, falls back to filename/heading matching, cap 5 results
- **Write path:** `/interknow:compound` — writes to `config/knowledge/{kebab-case}.md`
- **Decay:** 10 reviews without independent confirmation → archive to `config/knowledge/archive/`
- **Provenance tracking:** Distinguishes `independent` (agent found pattern without prompt) vs `primed` (agent had entry in context). Only independent confirmations reset decay timer. This prevents feedback loops.
- **Consumer:** interflux (flux-drive reviews check interknow entries for known patterns)

### Compound Docs (docs/solutions/)

- **32 entries** across 7 category subdirectories
- **Complex schema:** 13 enum-validated fields (module, problem_type, component, symptoms, root_cause, resolution_type, severity, plus optional tags, framework_version)
- **Entry format:** Full problem description with code examples, investigation steps, root cause analysis, prevention measures
- **Read path:** Enum-based category directories + `index.json` metadata + grep search
- **Write path:** `/clavain:compound` → `clavain:engineering-docs` skill (7-step workflow with BLOCKING YAML validation at step 5)
- **Decay:** None — entries persist forever
- **Schema validation:** `os/clavain/skills/engineering-docs/schema.yaml` enforces enum constraints
- **Features:** Cross-referencing, critical pattern promotion, synthesis tracking

### Key Differences

| Aspect | Interknow | Compound Docs |
|--------|-----------|---------------|
| Entries | 9 | 32 |
| Schema complexity | 2 fields | 13 fields |
| Decay mechanism | 10-review archival | None |
| Provenance tracking | independent/primed | None |
| Entry granularity | Generalized heuristics | Specific problems with code |
| Retrieval | Semantic (qmd) | Enum-based categories |
| Write interface | `/interknow:compound` | `/clavain:compound` |
| Storage | Plugin-local (`config/knowledge/`) | Project-level (`docs/solutions/`) |

## The Convergence Problem

These two systems store the same category of memory (C4: Curated Knowledge) in different locations with different schemas, different write tools, different retrieval methods, and different lifecycle policies. Neither checks the other for duplicates. An agent looking for a known pattern must search both.

### What interknow has that compound docs needs

1. **Provenance tracking** (independent vs primed) — prevents feedback loop decay gaming
2. **Staleness-based decay** — entries that aren't independently re-confirmed eventually archive
3. **Semantic retrieval** — qmd embedding search finds conceptually related entries, not just keyword matches

### What compound docs has that interknow needs

1. **Enum-validated schema** — structured metadata enables filtering by problem_type, severity, component
2. **Category organization** — human-browsable directory structure
3. **Cross-referencing** — related entries linked bidirectionally
4. **Critical pattern promotion** — high-severity findings promoted to required reading
5. **Richer entry format** — full investigation steps, code examples, prevention measures

## Convergence Design

### D1: docs/solutions/ is the single storage location

**Decision:** Move interknow's 9 entries into `docs/solutions/` format. `docs/solutions/` is the canonical home for all C4 knowledge.

**Rationale:**
- `docs/solutions/` already has 32 entries (3.5× more content)
- Project-level storage (`docs/`) is more discoverable than plugin-local (`config/knowledge/`)
- Category subdirectories provide browsable organization
- `index.json` provides machine-readable metadata

### D2: Add provenance fields to compound docs schema

**Decision:** Extend the compound docs YAML schema with 3 new optional fields:

```yaml
lastConfirmed: YYYY-MM-DD          # Date of last independent re-observation
provenance: independent|primed     # How the entry was confirmed
review_count: integer              # Number of times surfaced during reviews
```

**Rationale:** These enable interknow's decay model without breaking existing entries (all 3 are optional with sensible defaults).

**Default values for existing entries:**
- `lastConfirmed`: use existing `date` field value
- `provenance`: `independent` (assume pre-existing entries were human-validated)
- `review_count`: `0`

### D3: /clavain:compound becomes the single write path

**Decision:** `/clavain:compound` (via `engineering-docs` skill) is the only way to create C4 entries. `/interknow:compound` is deprecated.

**Changes needed:**
- `engineering-docs` skill adds provenance fields to its YAML validation (step 5)
- `engineering-docs` template includes lastConfirmed and provenance in frontmatter
- `/interknow:compound` redirects to `/clavain:compound` with a deprecation notice

### D4: Unified retrieval absorbs interknow's recall

**Decision:** The future `/recall` command (Demarch-h22) replaces `/interknow:recall`. Until `/recall` exists, `/interknow:recall` is updated to search `docs/solutions/` instead of `config/knowledge/`.

**Interim step:** Update `/interknow:recall` skill to:
1. Search `docs/solutions/` (primary)
2. Search `config/knowledge/` (fallback for any unmigrated entries)
3. Return results ranked by lastConfirmed recency + provenance weight

### D5: Decay policy for compound docs

**Decision:** Adopt interknow's 10-review archival model, augmented with a 180-day staleness check:

- **Review counter:** Each time an entry is surfaced during flux-drive or `/recall`, increment `review_count`
- **Staleness check:** If `lastConfirmed` is >180 days old AND `review_count` > 10 without a `provenance: independent` refresh → archive
- **Archive path:** `docs/solutions/archive/{category}/` (preserves category structure)
- **Reactivation:** If an archived entry is independently re-confirmed, move back to active

## Migration Plan

### Phase 1: Schema extension (no migration)

1. Add `lastConfirmed`, `provenance`, `review_count` as optional fields to `schema.yaml`
2. Update `engineering-docs` skill to write these fields on new entries
3. Update validation to accept but not require provenance fields

### Phase 2: Migrate interknow entries

1. For each of the 9 interknow entries:
   - Map to compound docs schema (add problem_type, component, severity, etc.)
   - Preserve original `lastConfirmed` and `provenance` values
   - Write to appropriate `docs/solutions/{category}/` subdirectory
   - Add to `index.json`
2. Verify all 9 entries migrated correctly
3. Add deprecation notice to `config/knowledge/README.md`

### Phase 3: Update tooling

1. `/interknow:recall` → search `docs/solutions/` instead of `config/knowledge/`
2. `/interknow:compound` → redirect to `/clavain:compound`
3. interflux flux-drive → read from `docs/solutions/` instead of `config/knowledge/`
4. interknow SessionStart hook → report from `docs/solutions/` instead of `config/knowledge/`

### Phase 4: Backfill provenance on existing entries

1. For all 32 existing compound docs entries without provenance fields:
   - Set `lastConfirmed` = `date` field value
   - Set `provenance` = `independent`
   - Set `review_count` = `0`

## What NOT to do

- Don't remove `config/knowledge/` immediately — keep as read-only archive until all consumers migrated
- Don't make provenance fields required — breaks existing entries
- Don't merge schema.yaml validation changes with migration in the same commit
- Don't drop semantic search capability — ensure docs/solutions/ entries can be searched by qmd too

## Open Questions

1. **interflux consumer:** flux-drive currently reads from `config/knowledge/`. Need to update the interflux skill to read from `docs/solutions/`. Is interflux in this repo or a separate plugin?
2. **qmd integration:** Does qmd need to re-index after entries move to `docs/solutions/`?
3. **index.json regeneration:** Is index.json manually maintained or auto-generated? If auto, is there a script?
