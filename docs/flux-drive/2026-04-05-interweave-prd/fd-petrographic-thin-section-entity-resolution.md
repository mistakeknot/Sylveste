# fd-petrographic-thin-section-entity-resolution -- PRD Review Findings

**Target:** `docs/prds/2026-04-05-interweave.md`
**Agent:** fd-petrographic-thin-section-entity-resolution (optical mineralogy: identifying entities across observation frames)
**Decision Lens:** Evaluates whether entity resolution uses invariant properties (persist across all subsystem views) or contingent properties (change per view). Checks grain-boundary handling, materialized lookup, and minimum invariant sets.
**Prior review:** `docs/flux-drive/2026-04-04-ontology-graph-concept-brief/fd-petrographic-thin-section-entity-resolution.md` (concept brief)

---

## Context: What This Agent Asked For vs. What the PRD Delivers

The concept-brief review raised 5 findings. The PRD dedicates an entire feature (F2: Identity Crosswalk) to entity resolution. This is the most directly addressed set of findings from any agent. The review checks whether the implementation specification is structurally sound.

---

## Finding 1: Diagnostic vs. contingent property distinction is structurally present but not named

**Severity: P2 (reduced from prior P1)**
**File:** `docs/prds/2026-04-05-interweave.md`, F2, lines 36-44; F1, line 25

The PRD's crosswalk schema (F2, line 38) stores `(subsystem, subsystem_id, canonical_id, confidence, method)`. The `subsystem_id` is the per-subsystem identifier and `canonical_id` is the unified identity -- this IS the diagnostic/contingent distinction in materialized form. The subsystem-specific properties (status, token count, AST structure) stay in their source subsystems. The crosswalk stores only identity anchors.

Additionally, F1 says "5 type families defined as data models with diagnostic properties" (line 25). The word "diagnostic" appears explicitly -- the PRD has absorbed the petrographic terminology.

**Remaining gap:** The PRD does not specify WHICH properties are diagnostic per entity type. F2 specifies resolution methods for files (path normalization, git SHA, tree-sitter AST fingerprinting) but does not provide an equivalent specification for other entity types. What is the diagnostic property for a session? A bead? A discovery? The concept-brief review provided a complete table of "extinction angles" per entity type. The PRD implements file-level resolution in detail but leaves other types implicit.

**Failure scenario (reduced severity):** The architecture is sound -- the crosswalk schema correctly separates identity from contingent properties. But during implementation, without a per-type diagnostic property table, developers may use contingent properties (like status or last-modified timestamp) as crosswalk keys for entity types that lack explicit specification.

**Smallest viable fix:** Add a diagnostic property table to F2 or reference one in the acceptance criteria:

```
Identity anchors per entity type:
  file:       path (normalized) + git SHA for immutable snapshots
  function:   file_path + qualified_name + parameter_types + return_type
  bead:       bead_id
  session:    session_id
  commit:     full SHA
  plugin:     plugin_name (from plugin.json)
  skill:      qualified_name (e.g., "clavain:sprint")
  tool_call:  (session_id, call_index)
```

---

## Finding 2: Grain-boundary entities are partially addressed through dedup detection

**Severity: P2 (reduced from prior P1)**
**File:** `docs/prds/2026-04-05-interweave.md`, F2, lines 43-44

The PRD includes "Dedup detection (flag when two canonical entities likely refer to the same thing)" (line 44). This acknowledges the grain-boundary problem: entities at subsystem interfaces may create multiple canonical entries that are actually the same entity.

**However:** Dedup detection (flagging after the fact) is weaker than grain-boundary resolution rules (preventing duplicates during ingest). The petrographic approach is to resolve at the grain boundary during observation, not to flag duplicates after the thin section has been analyzed.

Consider the commit grain-boundary entity from the concept-brief review: a commit appears in git (full SHA), beads (short SHA or commit message), cass (session + tool call), and intercore (run artifact). The PRD's three connectors (cass, beads, tldr-code) will each harvest commit-related data. Without explicit boundary resolution rules, the crosswalk may create:
- canonical-entity-1 from cass (session that ran `git commit`)
- canonical-entity-2 from beads (commit ref in bead metadata)

These are the same commit. Dedup detection may flag them, but by then they're separate nodes in the index with separate relationship sets.

**Smallest viable fix:** Add grain-boundary resolution rules for entity types that span connector boundaries. In F3 acceptance criteria, add:

```
- [ ] Boundary entity resolution: entities that appear in multiple connectors (commits, files, sessions)
      are resolved to single canonical entries during harvest, not flagged as duplicates post-hoc.
      Connectors declare shared entity types; crosswalk merges during ingest.
```

---

## Finding 3: Materialized entity resolution index is fully specified

**Severity: RESOLVED (from prior P2)**
**File:** `docs/prds/2026-04-05-interweave.md`, F2, lines 42-43

The PRD explicitly specifies: "O(1) lookup at runtime via materialized index" (line 42) and "Incremental updates (don't rebuild entire crosswalk on each change)" (line 43). This IS the Michel-Levy chart -- a precomputed resolution index that avoids real-time cross-subsystem joins.

The materialization is backed by SQLite (line 38), which provides the indexed lookup. Incremental updates prevent the Mandalay-rebuild problem. This finding from the concept-brief review is fully addressed.

---

## Finding 4: Pleochroism (type changing across views) is addressed through multi-family membership

**Severity: RESOLVED (from prior P2)**
**File:** `docs/prds/2026-04-05-interweave.md`, F1, line 29

The PRD's multi-family membership (F1, line 29) resolves the pleochroism finding. A Session that appears as an Agent entity in one view and a Knowledge entity in another simply declares membership in both families. The crosswalk resolves identity (session_id is the extinction angle); the family system handles type multiplicity.

---

## Finding 5: Function-level identity resolution tackles the hardest extinction-angle problem

**Severity: P2 (new finding)**
**File:** `docs/prds/2026-04-05-interweave.md`, F2, lines 39-41

The PRD specifies function-level resolution: "tree-sitter AST fingerprinting (canonical signature = file_path + function_name + parameter_types + return_type)" (line 40) and "Function rename/move detection: body similarity heuristic (>80% match links identities)" (line 41) with "Identity chain recording: fn_v1 -> renamed_to -> fn_v2" (line 41).

This is ambitious and addresses the concept-brief finding that Development entities have mutable identifiers (the hardest extinction-angle problem). The petrographic analogy: this is like tracking mineral grains through metamorphic recrystallization, where grain boundaries change so completely that identity must be inferred from body composition rather than external geometry.

**Concern:** The 80% body similarity threshold is a single magic number. In petrography, body-composition matching works when the specimen is relatively pure, but fails at grain boundaries where contamination from adjacent minerals changes the composition. Similarly, function body similarity will fail when:
- A function is split into two (which one is the "same" function?)
- Two functions are merged (the merged function is >80% similar to both)
- A function is moved AND significantly refactored in the same commit

These are metamorphic-grade identity changes. The PRD should acknowledge that function-level identity resolution has a reliability boundary.

**Smallest viable fix:** Add a confidence tier to function identity resolution:

```
- [ ] Function identity confidence tiers:
      - High: same file_path + same qualified_name (rename detection not needed)
      - Medium: same file_path + body similarity >80% (likely rename within file)
      - Low: different file_path + body similarity >80% (likely move across files)
      - Unresolvable: split/merge/major-refactor (flag for human review)
```

---

## Finding 6: Staleness TTL is a structural safeguard the concept brief lacked

**Severity: RESOLVED (positive finding)**
**File:** `docs/prds/2026-04-05-interweave.md`, F7, lines 102-109

F7 (Gravity-Well Safeguards) specifies "Staleness TTL: entities not refreshed within 30 days automatically excluded from query results" (line 103) and a finding-aid audit that deletes and rebuilds the entire index (line 108). This directly addresses the petrographic concern about the materialized index accumulating stale entries.

The finding-aid audit is particularly elegant: it proves the ontology is a finding aid (not a system of record) by demonstrating that destroying it and rebuilding causes no data loss. This is the petrographic equivalent of proving that your identification chart is a tool, not the specimen itself.

---

## Summary

| # | Severity | Finding | Status vs. Concept Brief |
|---|----------|---------|-------------------------|
| 1 | P2 | Diagnostic properties named per-family but not per-entity-type -- no extinction angle table | Partially addressed |
| 2 | P2 | Grain-boundary entities use post-hoc dedup, not ingest-time resolution | Partially addressed |
| 3 | Resolved | Materialized index with O(1) lookup and incremental updates (Michel-Levy chart) | Fully addressed |
| 4 | Resolved | Pleochroism handled through multi-family membership | Fully addressed |
| 5 | P2 | Function-level identity resolution needs confidence tiers for metamorphic-grade changes | New finding |
| 6 | Resolved | Finding-aid audit and staleness TTL are structural safeguards | Fully addressed (new) |

**Overall assessment:** The PRD made the identity crosswalk a first-class feature (F2) with exactly the architecture the concept-brief review recommended: materialized index, invariant identifiers, incremental updates, O(1) lookup. The remaining gaps are specification-level: the per-type diagnostic property table is implicit rather than explicit, and grain-boundary resolution happens after ingest rather than during. Function-level identity resolution is ambitious and needs confidence tiers. The structural architecture is sound.
