# SYNTHESIS — F5 Named Query Templates Brainstorm (Track D: Esoteric)

**Target:** `docs/brainstorms/2026-04-07-interweave-f5-named-query-templates-brainstorm.md`
**Track:** D (Esoteric)
**Agents:** fd-venetian-avogadori-di-comun-genealogical-registry, fd-yoruba-aroko-encoded-object-messaging, fd-syriac-masora-vocalization-intermediary-layer
**Date:** 2026-04-07
**Bead:** sylveste-5b7 (F5 stage: discover)

---

## Findings Summary

| ID | Severity | Agent | Finding |
|----|----------|-------|---------|
| S-1 | P0 | Syriac Masora | Go adapter requires new subprocess dispatch capability that serves no purpose outside the template layer — base text modification |
| V-1 | P1 | Venetian Avogadori | Shadow caching not prohibited; `bead_context` "full context graph" risks implicit data materialization |
| V-2 | P1 | Venetian Avogadori | `QueryResult` has no gap/lacuna annotation; partial source failures produce silent omissions |
| V-3 | P1 | Venetian Avogadori | Join ordering in `who_touched_file` unspecified; parallel fan-out risks merging on unresolved path strings |
| A-1 | P1 | Yoruba Aroko | All 8 templates return generic `QueryResult`; response shape opaque to agents at tool selection time |
| A-2 | P1 | Yoruba Aroko | `entity_relationships` and `related_artifacts` indistinguishable from MCP tool schema alone |
| S-2 | P1 | Syriac Masora | Template join logic not reconstructible from the documented 7 interaction rules |
| S-3 | P1 | Syriac Masora | `QueryTemplate` ABC enforces method presence only; implementations will diverge in error handling |
| A-3 | P2 | Yoruba Aroko | `execute()` connector dependency not declared in template interface; templates not self-contained |
| A-4 | P2 | Yoruba Aroko | `who_touched_file` and `actor_activity` overlap without canonical entry-point guidance |
| V-4 | P2 | Venetian Avogadori | `TemplateRegistry.list()` will require Python class imports; O(N) startup cost for tool enumeration |
| S-4 | P2 | Syriac Masora | No template usage metadata; layer cannot evolve from call patterns |
| V-5 | P3 | Venetian Avogadori | `bead_context` traversal depth unbounded |
| S-5 | P3 | Syriac Masora | `entity_relationships` may add a layer without adding meaning |

**Total findings: 14**
- P0: 1
- P1: 7
- P2: 4
- P3: 2

---

## Cross-Agent Convergence

Three findings converge from different lenses onto the same root issue:

**The `QueryResult` type is doing too much work with too little structure.** V-2 (needs gap annotations), A-1 (needs per-template typed response fields), and S-3 (needs standardized error handling) all point to `QueryResult` being under-designed. A single fix — extending `QueryResult` with `gaps: list[SourceGap]`, `error: str | None`, and per-template typed payload fields — resolves all three simultaneously.

**The connector dependency is invisible in the interface.** V-3 (join ordering must be explicit), A-3 (connectors not declared as interface dependencies), and S-2 (join logic not derivable from documented rules) converge on the same gap: the template interface declares inputs and outputs but not the relational structure of the query or the subsystem dependencies. Constructor injection of `Crosswalk` and `ConnectorRegistry` (A-3's fix) plus per-template specification of which rules govern which joins (S-2's fix) address this together.

---

## Priority Order for F5 Implementation

**Before writing any template code:**

1. **Resolve P0 S-1 first** — decide the Go ↔ Python bridge architecture. Option (b) (independent Python MCP server) avoids modifying the Go adapter. This decision gates everything else.

2. **Extend `QueryResult`** — add `gaps: list[SourceGap]`, `error: str | None`, and template-specific payload types. Define these before implementing any template class.

3. **Define `QueryTemplate` ABC constructor** — `__init__(self, crosswalk: Crosswalk, connectors: ConnectorRegistry)`. Add `validate_parameters()` as an abstract method. Add non-caching constraint to docstring.

4. **Add `TemplateManifest`** — separate static metadata from live instances so the registry is self-describing without class imports.

5. **Write per-template specifications** — for each of the 8 templates, document which type families are traversed, which interaction rules govern each join, and which connectors provide data for which family.

6. **Disambiguate `entity_relationships` vs. `related_artifacts`** — either merge into `entity_context` with a `rule_scope` parameter, or write MCP descriptions that encode the distinction by use-case.

**After initial implementation:**

7. **Add `TemplateRegistry.record_invocation()`** — instrument calls before production use so the first real-world data informs template evolution.

---

## Alignment / Conflict

**Alignment:** All three lenses affirm the catalog-of-catalogs principle from interweave's CLAUDE.md ("This plugin is a catalog-of-catalogs — it never owns entity data") and the finding-aid test. The P1 findings are not philosophical objections to F5 — they are implementation constraints that, if addressed, make F5 structurally sound.

**Conflict/Risk:** S-1 (P0) is the only finding with architectural weight. If the Go adapter must be modified to support template dispatch, the intermediary-layer contract breaks and creates a bidirectional coupling that will complicate future evolution of both the adapter and the template layer. The independent Python MCP server path avoids this at the cost of one additional process for operators to manage.
