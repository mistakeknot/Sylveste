---
agent: fd-clinical-terminology-harmonization
track: project
status: NEEDS_ATTENTION
finding_count: 6
---

## Findings

### [P1] Type family system is pre-coordinated — no post-coordination for compound entity queries

**Issue:** The PRD's type family system (F1) defines 5 fixed families with 7 interaction rules that generate the "complete relationship matrix" (line 21). This is a pre-coordinated design: every valid entity-to-entity relationship must be derivable from the (family_a, family_b) pair. SNOMED CT learned that pre-coordination — creating a node for every possible concept combination — leads to combinatorial explosion. The PRD's type families work for the current 5-family model, but agents will need compound queries that span multiple families simultaneously: "show me all Processes that produced Artifacts reviewed by Actor X with Evidence of confidence > probable." This query requires composing relationships across 4 families — the relational calculus engine needs to support post-coordination (composing at query time) rather than only pre-coordinated (family_a, family_b) pairs.

**Failure scenario:** An agent queries `causal-chain` for a bug fix. The chain needs to traverse: Evidence (test failure) > Process (session that investigated) > Artifact (file changed) > Process (PR review) > Actor (reviewer who approved). The relational calculus engine can resolve each (family_a, family_b) pair, but the 5-hop chain requires the engine to compose 4 pair-resolutions in sequence. If the engine only supports single-pair lookup ("what relationships are valid between Process and Artifact?") without a composition operator, the agent must manually chain 4 separate queries. The "relational calculus engine" label in the PRD implies compositional reasoning, but the acceptance criteria (line 28: "given (family_a, family_b), returns valid relationship types") only specify pair-wise lookup.

**Fix:** Add an acceptance criterion to F1: "The relational calculus engine supports path queries: given a sequence of families [F1, F2, F3, ...], returns valid relationship chains connecting them. Path queries are used by F5's `causal-chain` template (3 hops) and can compose any sequence up to the hop limit."

---

### [P1] No formality gradient — all type families and all entity properties have the same binding strength

**Issue:** FHIR defines binding strengths (required, extensible, preferred, example) that let different elements bind to value sets at different rigor levels. The PRD's type family system treats all 5 families and all diagnostic properties at the same formality level. But the families differ fundamentally in schema stability: Artifact and Actor entities have well-defined, stable schemas (files have paths, agents have IDs). Evidence and Relationship entities are inherently fuzzy (a "review finding" can have dozens of optional properties depending on the review tool). The PRD's F1 acceptance criteria (lines 25-30) specify "diagnostic properties" per family but do not specify whether these properties are required, optional, or extensible per family.

**Failure scenario:** The Evidence type family is defined with diagnostic properties `[source, confidence, timestamp, reviewer]`. A new connector (e.g., interwatch drift detection) produces Evidence entities with properties `[drift_score, baseline_hash, detected_at]` that don't map to the family's diagnostic properties. The connector must either (a) force its properties into the fixed schema (losing domain-specific signal) or (b) extend the schema (requiring a change to the type family definition). Neither option is viable without a formality gradient that says "Evidence family properties are extensible (new properties can be added without schema migration)."

**Fix:** Add a binding strength property to each type family's diagnostic properties in F1: `required` (must be present for all entities in this family), `extensible` (standard properties plus connector-specific extensions), or `example` (suggested properties, no enforcement). Recommend: Artifact and Actor = required core + extensible extensions. Process = extensible. Evidence and Relationship = example. Add acceptance criterion: "Each type family declares binding strength for its diagnostic properties; connectors can add properties beyond the declared set for families with extensible or example binding."

---

### [P1] Relationship types are a closed set — the 7 interaction rules cannot accommodate domain-specific relationships

**Issue:** The PRD defines 7 interaction rules (line 22: Productivity, Transformation, Stewardship, Structure, Evidence Production, Annotation, Lifecycle) as the complete relationship vocabulary. When a connector introduces a domain-specific relationship that doesn't map to these 7 (e.g., interwatch's "drift-detected" between a document and its baseline, or interlens's "inspired-by" between two concepts), the connector must either (a) force-map to the closest existing rule (losing semantic precision) or (b) request a schema change to add rule #8 (requiring coordination across all consumers). Clinical terminology systems solved this with extensible value sets: a core set of required relationships, plus a registration mechanism for domain-specific extensions.

**Failure scenario:** The interwatch connector produces relationships of type "drift-detected" between document entities and their baselines. This doesn't fit any of the 7 rules. The connector maps it to "Annotation" (the closest match). An agent queries "what annotations exist for this document?" and gets both human-authored annotations and drift detection signals in the same result set, with no way to distinguish them. The force-mapping destroyed the semantic distinction that made the drift signal useful.

**Fix:** Change the interaction rules from a closed set of 7 to an extensible set: 7 core rules (always present, well-defined semantics) plus a registration convention for domain-specific rules. Format: `{namespace}:{rule-name}` (e.g., `interwatch:drift-detected`). Connectors register their domain-specific rules when they register with interweave. The relational calculus engine treats registered rules as first-class — they participate in path queries and named templates. Add acceptance criterion to F1: "Interaction rules are extensible via namespace registration; connectors can declare domain-specific rules beyond the core 7."

---

### [P2] No temporal validity on relationships — F4's schema captures creation but not expiration

**Issue:** SNOMED CT publishes biannual releases where concept meanings shift, relationships are deprecated, and new concepts subsume old ones. The PRD's link schema (F4, line 65) includes `created_at` and `last_verified_at` but no `valid_from` / `valid_until` temporal window. When a file is renamed, the old path > bead relationship should be marked as historically valid but currently superseded. The staleness detection (F4, line 71: "links not re-verified within TTL flagged as stale") is a proxy for temporal validity but conflates "not recently checked" with "no longer true." A relationship that was true last month and is still true today gets flagged as stale if the TTL expired, while a relationship that ended yesterday but was just verified appears fresh.

**Failure scenario:** A function is extracted from `utils.py` into `helpers.py`. The crosswalk (F2) correctly creates a new identity chain. But the relationship graph (F4) still shows the old `utils.py > bead-abc` link as "last_verified_at = yesterday" because the beads connector re-verified that the bead exists and utils.py exists — it didn't check whether the function is still in utils.py. An agent queries `who-touched helpers.py:extractedFn` and misses all the historical sessions that touched it when it lived in utils.py, because the relationship was recorded against the old path and never marked as superseded.

**Fix:** Add `valid_from` and `valid_until` (nullable) to the link schema in F4. When a relationship is superseded (e.g., file rename), set `valid_until` on the old link and `valid_from` on the new link. Default queries filter to `valid_until IS NULL` (current relationships). Historical queries can include expired links. Add acceptance criterion: "Link schema includes temporal validity window; superseded relationships are marked as historically valid, not deleted."

---

### [P2] Crosswalk maintenance cost is unacknowledged — no acceptance criteria for ongoing map currency

**Issue:** Clinical terminologists know that maintaining cross-terminology maps is the most expensive ongoing cost of a terminology system. The PRD's crosswalk (F2) will map identities across cass, beads, and tldr-code — three subsystems that evolve their schemas independently. When beads adds a new entity type (e.g., "sprint" distinct from "epic"), the crosswalk must be updated to recognize the new type. When cass changes its session ID format, the crosswalk's identifier-match method breaks. The PRD specifies "incremental updates" (F2, line 43) but no acceptance criteria for detecting when a subsystem schema change has invalidated existing crosswalk mappings.

**Failure scenario:** beads v0.70 changes the bead ID format from `Sylveste-xxx` to `sylveste/xxx`. The crosswalk's identifier-match method still looks for the old format. New beads get new crosswalk entries with the new format. Old beads retain old entries. An agent queries a function that was worked on across both bead ID formats — the crosswalk returns two separate canonical entities for what is actually one continuous stream of work. The dedup detection (F2, line 44) might catch this, but only if it runs after the format change and the old/new IDs are similar enough to trigger the heuristic.

**Fix:** Add a schema version field to the connector interface (F3): each connector declares its current entity schema version. When a connector's schema version changes, the crosswalk flags all existing entries from that connector for re-verification. Add acceptance criterion to F3: "Connectors declare schema version; version changes trigger crosswalk re-verification for affected entries." Add acceptance criterion to F2: "Crosswalk detects connector schema version changes and re-verifies affected entries."

---

### [P3] Named query interface (F5) requires formal entity IDs — no interface terminology mapping

**Issue:** Clinical informatics distinguishes between interface terminologies (what clinicians type) and reference terminologies (formal codes in the backend). The PRD's named query templates (F5, line 85) accept "file path, bead ID, session ID, function name, or canonical entity ID." But agents think in natural language: "the dispatch function," "the sprint planning epic," "the session where we fixed the build." The PRD's Open Question 3 (line 143) acknowledges the disambiguation problem but only considers syntactic disambiguation (prefix-based routing). There is no mechanism for an agent to query using a natural-language description and have interweave resolve it to the formal entity.

**Fix:** Add a natural-language entity resolution step to F5's input handling: before prefix-based routing, check if the input matches a known entity name or alias. Connectors can register entity aliases (e.g., beads registers bead titles alongside bead IDs). This is a P3 because prefix-based routing handles the 80% case; natural-language resolution is a progressive enhancement.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 6 (P0: 0, P1: 3, P2: 2, P3: 1)
SUMMARY: The type system lacks post-coordination for compound queries, a formality gradient across families, and extensible relationship types — three patterns clinical terminology solved decades ago that would prevent the schema from becoming either too rigid or too loose as connectors multiply.
---
