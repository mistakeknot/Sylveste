---
agent: fd-archival-provenance-linkage
track: project
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No multi-level description hierarchy — entities are flattened into a single graph layer

**Issue:** The PRD's type family system (F1) defines 5 families (Artifact, Process, Actor, Relationship, Evidence) with 7 interaction rules, but all entities participate in the same relational calculus at the same level. Archival description is inherently hierarchical: fonds > series > file > item. The interweave ecosystem has an identical nesting structure: a function lives within a module within a pillar; a bead lives within an epic within a sprint. The PRD's acceptance criteria for F1 (lines 25-30) specify "multi-family membership" but not multi-level membership. When an agent asks `related-work src/lib/dispatch.py`, a flat graph returns the file's bead, the bead's parent epic, and every other child of that epic — all as equally weighted 1-hop results. Without level-aware traversal, the signal (this file's direct work items) is drowned by noise (all sibling work items in the epic).

**Failure scenario:** An agent queries `causal-chain` for a P0 bug. The chain traverses: bug-bead > parent-epic > 28-sibling-beads > their sessions. The 3-hop max (F5, line 82) is consumed traversing the hierarchy laterally rather than drilling into the causal chain, because the graph treats the parent-epic > sibling-bead hop as equivalent to the bug-bead > causing-session hop. The causal chain query returns epic-level context instead of bug-level causation.

**Fix:** Add a `level` property to the type family model in F1: each entity declares its hierarchical level (collection, series, item — or in Sylveste terms: epic, feature, unit). The named query templates in F5 should specify level-aware traversal: `causal-chain` traverses within-level and downward, never laterally to siblings via a parent. Add acceptance criterion to F1: "Entities can declare hierarchical level; interaction rules respect level boundaries in traversal."

---

### [P1] Finding-aid test (F7) lacks a rebuild-from-scratch acceptance criterion for the crosswalk

**Issue:** F7's finding-aid audit script (line 108) "deletes the entire index, verifies all subsystems still function, and rebuilds." But the identity crosswalk (F2) contains materialized identity chains (line 41: `fn_v1 > renamed_to > fn_v2`) and function rename/move detection history built from git blame over time. Deleting and rebuilding the crosswalk from scratch will lose the identity chain history — git blame can reconstruct current-state mappings, but the temporal chain of "this function was renamed three times" requires the incremental history that was accumulated over months. Archival finding aids face the same problem: a union catalog can be rebuilt by re-harvesting member catalogs, but the provenance annotations added by catalogers (e.g., "this authority record was merged with record X on date Y because...") are destroyed by a rebuild.

**Failure scenario:** `interweave audit` runs successfully — all subsystems work, the index rebuilds. But function-level identity chains spanning multiple renames are gone. An agent queries `who-touched parseConfig` and gets results only for the current function name, missing the 8 sessions that touched it under its previous names `loadConfig` and `readConfig`. The finding-aid test passes, but the crosswalk's value (accumulated identity resolution history) was silently destroyed.

**Fix:** Split the finding-aid test in F7 into two levels: (a) structural audit — delete the entity index and relationship graph, verify subsystems, rebuild. This tests that interweave is truly a projection layer. (b) crosswalk audit — verify the crosswalk can be regenerated from git history + AST analysis, but preserve the identity chain table separately (it is the one piece of accumulated state that has no external source of truth). Add acceptance criterion to F7: "Identity chain history (F2) is backed up before audit and restored after rebuild; audit verifies chains are consistent with rebuilt crosswalk."

---

### [P2] No accession/deaccessioning lifecycle for dynamic entities

**Issue:** The PRD defines staleness TTL (F7, line 107: "entities not refreshed within 30 days automatically excluded from query results") but has no formal lifecycle model for entity registration and retirement. Archives have accession (formal registration with provenance metadata) and deaccessioning (formal removal with justification). The interweave ecosystem generates entities at wildly different rates: sessions are created hourly, beads weekly, plugins monthly. The PRD's TTL-based exclusion treats all entity types the same — a 31-day-old session is excluded alongside a 31-day-old plugin definition. But sessions become irrelevant in days while plugin definitions remain relevant for years.

**Failure scenario:** A plugin that hasn't been modified in 35 days is excluded from query results because its metadata wasn't "refreshed" — even though the plugin is actively used in every session. The TTL mechanism conflates "last modified" with "last relevant." Meanwhile, the index accumulates thousands of session entities that are only 29 days old but will never be queried again.

**Fix:** Add per-type-family TTL configuration to F7's acceptance criteria. Artifact entities (files, plugins) should have a long TTL or be refresh-on-query. Process entities (sessions, runs) should have a short TTL with an archive policy (move to cold storage rather than exclude). Add acceptance criterion: "TTL is configurable per type family; `interweave health` reports entity counts by family and staleness tier."

---

### [P2] Crosswalk schema (F2) does not record descriptive provenance — only resolution method

**Issue:** The crosswalk schema (F2, line 37) stores `(subsystem, subsystem_id, canonical_id, confidence, method)`. The `method` field records how the match was made (e.g., "git SHA matching") but not the descriptive provenance: who or what asserted the canonical identity, when the assertion was last verified, and whether it was human-confirmed or machine-inferred. Archival authority control records carry provenance annotations: "This authority record was established by [archivist] on [date] based on [evidence]." Without descriptive provenance, all crosswalk entries look equally authoritative regardless of their origin quality.

**Failure scenario:** A crosswalk entry links a function in `core/intercore/` to a bead via tree-sitter AST fingerprinting (method: "body-similarity-heuristic"). Six months later, the function has been rewritten but the crosswalk entry persists because the entry was refreshed (the function still exists, the bead still exists). An agent trusts the link because the confidence field says "probable" and there's no signal that the original similarity match is stale. The link is a false positive — the rewritten function has no relationship to the bead.

**Fix:** Extend the crosswalk schema to include `asserted_by` (connector name or "manual"), `asserted_at` (timestamp), and `last_verified_at` (timestamp of last re-verification that the match still holds). The dedup detection (F2, line 44) should re-verify existing matches during incremental updates, not just detect new duplicates. Add acceptance criterion to F2: "Crosswalk entries include assertion provenance (who, when, last-verified) alongside resolution method."

---

### [P3] No descriptive standard crosswalk between subsystem schemas

**Issue:** The concept brief's archival agent (review approach item 5) specifically flagged that archivists routinely map between MARC, EAD, Dublin Core, and ISAD(G) using formal crosswalks. The PRD's connector protocol (F3) defines an observation contract format (line 52: `entities_indexed, granularity, properties (captured/inferred), refresh cadence, freshness_signal`) but does not define how the properties from different subsystems map to each other. A bead's `status` field and a session's `outcome` field may describe overlapping concepts, but the PRD has no mechanism for a connector to declare "my `status` field maps to the ontology's `lifecycle_state` concept."

**Fix:** Add a property mapping declaration to the connector interface in F3: connectors can optionally declare how their entity properties map to type family diagnostic properties (F1). This enables cross-subsystem property queries ("show me all entities in lifecycle_state=active") without requiring subsystems to change their schemas. Add as a P3 acceptance criterion to F3: "Connectors can declare property mappings to type family diagnostic properties."

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 2, P3: 1)
SUMMARY: The PRD operationalizes the catalog-of-catalogs pattern well but flattens hierarchical context into a single graph layer, lacks lifecycle-aware entity management, and does not preserve accumulated crosswalk provenance through the finding-aid audit.
---
