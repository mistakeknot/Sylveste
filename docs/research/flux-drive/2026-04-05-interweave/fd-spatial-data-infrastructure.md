---
agent: fd-spatial-data-infrastructure
track: project
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Connector discovery threshold is too high — minimum 4 fields still requires connector-side implementation effort

**Issue:** The PRD's connector protocol (F3, line 53) enforces a "minimum discovery threshold" of `entity_type, entity_id, subsystem, created_at`. ISO 19110 feature catalogs learned that even a minimal metadata requirement creates an adoption barrier if connectors must implement custom code to produce the required fields. The PRD's harvest model (F3, line 57: "interweave crawls connectors, zero effort from producers") promises zero connector-side effort, but the minimum threshold requires each subsystem's data to contain (or be derivable to) these 4 fields. For subsystems where `entity_type` is implicit (e.g., cass stores sessions but doesn't tag them with `entity_type: session`) or `created_at` is missing (e.g., tldr-code extracts functions from current source, not from creation timestamps), the "zero effort" promise breaks — someone must write the mapping.

**Failure scenario:** A new connector is needed for interwatch (drift detection). interwatch stores drift events with fields `[document_path, drift_score, detected_at, baseline_hash]`. It has no `entity_type` field (all records are drift events), no `entity_id` field (events are identified by document_path + detected_at), and no `created_at` field (only `detected_at`). The connector author must write mapping logic to derive the 4 minimum fields from interwatch's native schema. This is a small amount of code, but it contradicts the "zero effort from producers" claim and means every new connector requires custom implementation — the same adoption barrier that SDI practitioners found kills catalog participation.

**Failure scenario (second-order):** Because each connector requires custom mapping code, connector coverage grows linearly with engineering effort. After 6 months, only the initial 3 connectors (cass, beads, tldr-code) are implemented. The graph covers 3 of 60+ subsystems. Agents learn that interweave usually returns "no results" for their queries and stop using it. The graph never reaches the critical mass needed to be useful.

**Fix:** Reduce the minimum discovery threshold to 2 fields: `entity_id` and `subsystem`. Make `entity_type` and `created_at` optional (inferred by interweave from the subsystem's connector registration if not provided). For subsystems that expose a filesystem or database, provide a generic connector template that auto-discovers entities by scanning known data locations (e.g., `.beads/backup/issues.jsonl`, `~/.local/share/cass/`). Add acceptance criterion to F3: "A generic filesystem connector can index any subsystem that stores entities in JSONL or SQLite without custom connector code."

---

### [P1] No partial-coverage query semantics — agents cannot distinguish "not found" from "not indexed"

**Issue:** The PRD's graceful degradation (F5, line 88: "if a connector is unavailable, return partial results with source status") only handles the connector-unavailable case. SDI catalog practitioners know that the harder problem is the connector-available-but-incomplete case: a connector exists for cass but has only indexed sessions from the last 7 days, not the full history. When an agent queries `recent-sessions <entity>` and gets no results, the agent cannot distinguish "no sessions touched this entity" from "sessions exist but haven't been indexed yet." The PRD's freshness metadata (F4, line 71: staleness detection) operates at the link level, not the connector level.

**Failure scenario:** An agent queries `who-touched src/lib/dispatch.py`. The tldr-code connector is registered and has indexed the current file structure, but the cass connector has only indexed sessions from the last 3 days. The function was last touched 5 days ago. The query returns: tldr-code results (file exists, function exists) but no session results. The agent concludes "no one has touched this recently" and proceeds to modify it, unaware that another agent modified it 5 days ago in a session that hasn't been indexed yet.

**Fix:** Add connector-level coverage metadata to query results in F5: each result set includes, per contributing connector, `{connector_name, indexed_since, last_harvest_at, coverage_estimate}`. This lets agents make informed decisions about whether to supplement graph results with direct subsystem queries. The `coverage_estimate` is a simple metric: "sessions indexed / sessions known to exist" for cass, "files indexed / files in repo" for tldr-code. Add acceptance criterion to F5: "Query results include per-connector coverage metadata (indexed_since, last_harvest_at, coverage_estimate) alongside entity results."

---

### [P2] Identifier harmonization strategy is implicit — Open Question 3 defers a P1 decision

**Issue:** The PRD's Open Question 3 (line 143) treats entity input disambiguation as a UX question ("How does interweave disambiguate 'src/main.py' from 'Sylveste-abc1'?"). SDI architects know this is actually an infrastructure question: the identifier harmonization strategy determines whether the system can compose cross-subsystem queries at all. The PRD's crosswalk (F2) maps `(subsystem, subsystem_id)` to `canonical_entity_id`, but the canonical ID scheme is not specified. If canonical IDs are UUIDs, agents must learn the UUID for every entity they want to query. If canonical IDs reuse one subsystem's native ID (e.g., file paths), the system is biased toward that subsystem's worldview.

**Failure scenario:** The crosswalk assigns UUID canonical IDs. An agent wants to query the function `parseConfig` in `src/config.py`. The agent knows the file path and function name but not the UUID. The agent calls `related-work src/config.py::parseConfig`. interweave must first resolve this natural-language-ish input to a canonical UUID, then query the graph. If the resolution fails (the function was renamed, the path changed, the AST fingerprint doesn't match), the query returns nothing — and the agent doesn't know whether the entity doesn't exist or the resolution failed.

**Fix:** Resolve Open Question 3 in the PRD body rather than leaving it open. Recommendation: canonical IDs should be composite — `{subsystem}:{native_id}` (e.g., `tldr-code:src/config.py::parseConfig`, `beads:sylveste-abc1`). This preserves subsystem-native IDs (no new namespace to learn), enables prefix-based routing (the subsystem prefix routes to the right connector), and makes canonical IDs human-readable. Add acceptance criterion to F2: "Canonical IDs use composite format {subsystem}:{native_id}; agents can query using either the canonical ID or the native subsystem ID."

---

### [P2] No data currency metadata on connector harvest — agents cannot assess graph freshness per subsystem

**Issue:** SDI catalogs require temporal validity declarations: `last_updated`, `update_frequency`, `next_expected_update`. The PRD's connector observation contract (F3, line 52) includes `refresh_cadence` and `freshness_signal` but these are declared at connector registration time, not reported at harvest time. When a connector's actual refresh cadence drifts from its declared cadence (e.g., cass declares "refresh every 5 minutes" but the index hasn't been rebuilt in 3 hours because the cass daemon crashed), the graph has no mechanism to detect the discrepancy.

**Failure scenario:** The cass connector declares `refresh_cadence: 5 minutes` and `freshness_signal: cass index --check`. But `cass index` hasn't run in 4 hours because a background process died. The graph continues serving stale session data. An agent queries `recent-sessions` and gets results from 4 hours ago, presented as fresh because the connector's declared cadence says "up to 5 minutes old." The `interweave health` command (F7, line 110) reports connector status but only checks whether the connector process is running, not whether it has actually harvested recently.

**Fix:** Add per-harvest timestamp tracking to the connector protocol: each harvest writes `{connector, harvest_started_at, harvest_completed_at, entities_processed, errors}` to a harvest log. `interweave health` compares actual last-harvest time against declared refresh_cadence and flags "overdue" connectors. Add acceptance criterion to F3: "Each harvest records completion timestamp; `interweave health` detects connectors whose actual harvest frequency exceeds their declared refresh cadence."

---

### [P3] Type system is designed top-down from current analysis — no bottom-up extension convention

**Issue:** SDI type hierarchies designed top-down from current system analysis become bottlenecks within 6 months as new subsystems introduce entity types that don't fit. The PRD's 5 type families were derived from analyzing the current ecosystem. The "new entity types can declare family membership(s) and inherit all family rules" criterion (F1, line 28) handles adding entities to existing families, but not adding new families. When a future subsystem introduces entities that don't fit any of the 5 families (e.g., a "Policy" entity from Ockham that governs agent behavior — is it an Artifact? A Relationship? Neither fits well), the family system must be extended, which is a schema-level change.

**Fix:** Add a family extension convention to F1: new families can be registered via a declaration file in the interweave plugin directory. Existing families are core (always loaded); extension families are loaded when their declaring connector is registered. Add acceptance criterion: "New type families can be registered via connector-provided family declarations without modifying the core family definitions."

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 2, P3: 1)
SUMMARY: The catalog-of-catalogs architecture is sound in principle but the connector protocol's minimum metadata threshold creates adoption friction, query results lack per-connector coverage metadata that agents need to assess result completeness, and the identifier harmonization strategy is deferred as an open question when it should be a core design decision.
---
