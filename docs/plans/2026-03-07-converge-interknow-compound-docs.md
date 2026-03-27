---
artifact_type: plan
bead: Sylveste-7xs
stage: plan
---

# Plan: Converge Interknow + Compound Docs

**Bead:** Sylveste-7xs
**PRD:** docs/prds/2026-03-07-converge-interknow-compound-docs.md

## Tasks

### T1: Extend schema.yaml with provenance fields
- [x] Add `lastConfirmed`, `provenance`, `review_count` to `optional_fields` in `os/clavain/skills/engineering-docs/schema.yaml`
- Similar to existing `framework_version` and `tags` optional fields

### T2: Update engineering-docs SKILL.md to write provenance fields
- [x] In Step 6 (Create Documentation), add provenance fields to the generated frontmatter
- [x] Set defaults: `lastConfirmed: today`, `provenance: independent`, `review_count: 0`

### T3: Migrate 8 interknow entries to docs/solutions/
- [x] Map each entry to compound docs schema (problem_type, component, severity, etc.)
- [x] Write to appropriate `docs/solutions/{category}/` with merged frontmatter
- [x] Entries to migrate:
  1. `multi-step-cli-init-rollback` → best-practices (logic_error, cli)
  2. `shell-pipe-delimited-format-injection` → best-practices (security_issue, cli)
  3. `aspirational-execution-instructions` → best-practices (documentation_gap, tooling)
  4. `shim-function-mismatch-wrapper-pattern` → best-practices (integration_issue, tooling)
  5. `agent-description-example-blocks-required` → best-practices (documentation_gap, documentation)
  6. `documentation-implementation-format-divergence` → best-practices (documentation_gap, documentation)
  7. `agent-merge-accountability` → best-practices (workflow_issue, documentation)
  8. `shell-stat-fallback-epoch-zero` → best-practices (logic_error, cli)

### T4: Backfill provenance on existing 32 compound docs
- [x] For each existing entry without provenance fields, add: `lastConfirmed: <date>`, `provenance: independent`, `review_count: 0`

### T5: Update interknow /recall skill to search docs/solutions/
- [x] Modify `interverse/interknow/skills/recall/SKILL.md` to search `docs/solutions/` as primary, `config/knowledge/` as fallback

### T6: Update interknow /compound skill to redirect
- [x] Modify `interverse/interknow/skills/compound/SKILL.md` to redirect to `/clavain:compound`

### T7: Update interknow SessionStart hook
- [x] Modify `interverse/interknow/hooks/session-start.sh` to report from `docs/solutions/` instead of `config/knowledge/`

### T8: Add deprecation notice to config/knowledge/README.md
- [x] Add notice explaining entries have moved to docs/solutions/

## Execution Order

T1 → T2 (schema first, then skill update)
T3 + T4 (migration + backfill, can be parallel)
T5 + T6 + T7 + T8 (tooling updates, can be parallel)
