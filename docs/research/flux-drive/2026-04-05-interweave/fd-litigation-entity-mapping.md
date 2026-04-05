---
agent: fd-litigation-entity-mapping
track: project
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] Person-entity resolution is absent — the PRD has no mechanism to unify a developer's identity across subsystems

**Issue:** The PRD's identity crosswalk (F2) focuses on artifact-level resolution: file paths, function signatures, git SHAs. It does not address person-entity resolution. In the Sylveste ecosystem, the same developer appears as: a GitHub username in git commits, a `claimed_by` value in beads (which is a session ID, not a person ID), a `CLAUDE_SESSION_ID` in cass session logs, and potentially a human name in PR reviews. The `who-touched` query template (F5, line 83) promises to return "agents/humans that modified entity" but the PRD provides no mechanism to recognize that three different identifiers refer to the same actor. E-discovery systems treat person-entity resolution as a first-class problem — the same custodian appears across email, Slack, and documents with different identifiers, and the entity graph must unify them.

**Failure scenario:** An agent queries `who-touched src/lib/dispatch.py`. The graph returns 4 Actor entities: `github:mkuser` (from git commits), `session:a1b2c3d4` (from cass, claimed by the same person), `beads:claimed_by=released` (from a closed bead), and `session:e5f6g7h8` (from a different session by the same person). The agent sees 4 different actors and cannot determine that 3 of them are the same human. The `who-touched` query, which should answer "one person touched this across 3 sessions," instead returns noise.

**Fix:** Add person-entity resolution to F2 as a distinct concern from artifact-entity resolution. The crosswalk needs an Actor identity table: `(subsystem, actor_id, canonical_person_id, confidence, method)`. Methods: `git-config` (git username/email), `session-claim` (beads claimed_by links to session UUID), `explicit-mapping` (manual declaration). The canonical person ID can be the git email (most universal identifier in developer tooling). Add acceptance criterion to F2: "Actor identity crosswalk maps subsystem-specific actor identifiers to canonical person identifiers; `who-touched` queries return deduplicated actor results."

---

### [P1] Confidence scoring (F4) has no false-positive cost model — speculative links and confirmed links have different downstream consequences

**Issue:** The PRD's confidence levels (F4, line 68: confirmed, probable, speculative) are a good start, but the acceptance criteria only specify filtering ("default query filter excludes speculative links," line 69). In e-discovery, confidence scoring includes a cost model: a false-positive link (asserting a connection that doesn't exist) has different consequences than a false-negative (missing a connection that does exist). For interweave, a false-positive in `causal-chain` could cause an agent to misattribute a bug's root cause and waste an entire sprint investigating the wrong subsystem. A false-negative in `related-work` means an agent misses relevant context but can recover by querying subsystems directly. The PRD treats all confidence levels as equal filtering thresholds rather than as risk signals.

**Failure scenario:** The `causal-chain` query template (F5, line 82) traverses 3 hops with max 20 results. At hop 2, the traversal follows a "probable" link (structural match via co-modified files) from a session to a config file. The config file leads to an infrastructure bead at hop 3. The agent receives a causal chain that suggests "the bug was caused by an infrastructure change." But the hop-2 link was a probable inference (the session touched the config file, but didn't modify it — it only read it). The agent spends 2 hours investigating the infrastructure bead. The false-positive link cost more than the entire query was worth.

**Fix:** Add per-query confidence floors to F5's named query templates. High-stakes queries (`causal-chain`, `who-touched`) should require `confirmed` or `probable` links by default, with no option to include `speculative` links in the chain (speculative links can appear in leaf results but not in traversal edges). Lower-stakes queries (`related-work`, `recent-sessions`) can include `probable` links in traversal. Add acceptance criterion to F5: "Each named query template declares a minimum confidence floor for traversal edges (distinct from the leaf-result filter in F4)."

---

### [P2] No iterative enrichment model — the PRD assumes comprehensive indexing before useful queries

**Issue:** The PRD's connector protocol (F3) describes a harvest model where connectors provide entity metadata that interweave indexes. The 3 initial connectors (cass, beads, tldr-code) are described as complete implementations. E-discovery builds entity graphs iteratively: an initial broad collection (cheap, coarse) is followed by targeted deep-indexing of high-value entities. The PRD does not describe an equivalent enrichment workflow. When interweave is first deployed, it must fully index all 3 subsystems before any cross-system query returns useful results. If the initial indexing takes hours (cass has 10K+ sessions, tldr-code must parse every file), the system provides no value during the bootstrap period.

**Failure scenario:** interweave is deployed. The tldr-code connector begins indexing the full codebase — parsing ASTs for every file takes 45 minutes. During this period, `related-work src/lib/dispatch.py` returns empty results because the file hasn't been indexed yet. An agent falls back to direct tldr-code and cass queries. By the time indexing completes, the agent has established a workflow that bypasses interweave. Adoption never recovers.

**Fix:** Define an enrichment model in F3: connectors support two harvest modes — `broad` (index entity IDs, types, and timestamps only — fast, covers everything) and `deep` (index full metadata including relationships, AST fingerprints, etc. — slow, per-entity). The initial bootstrap runs `broad` harvest for all connectors (minutes, not hours). `deep` harvest runs on-demand when a query touches an entity that only has broad metadata. Add acceptance criterion to F3: "Connectors support broad (fast, metadata-only) and deep (slow, full-relationship) harvest modes; initial bootstrap uses broad mode; deep mode triggers on first query."

---

### [P2] No deduplication signal for near-duplicate entities across subsystems

**Issue:** The PRD's dedup detection (F2, line 44: "flag when two canonical entities likely refer to the same thing") operates within the crosswalk — detecting when two crosswalk entries should be merged. But it does not address near-duplicate entities across subsystems: the same logical concept appearing as slightly different entities in different subsystems. E-discovery routinely handles near-duplicates (the same email in multiple custodians' mailboxes, the same document with minor edits). In interweave, a "sprint planning" bead and a "sprint planning" session and a "sprint planning" finding may all reference the same logical event but are three distinct entities in three subsystems. The graph treats them as unrelated unless an explicit cross-system link exists.

**Failure scenario:** An agent queries `related-work sprint-planning-v2` (a bead). The graph returns the bead's direct relationships. But there are 5 sessions titled "sprint planning" that worked on related topics and 3 flux-drive findings about sprint planning methodology — none of them are explicitly linked to the bead because the connections are semantic (topic overlap), not structural (explicit reference). The agent gets a narrow view of sprint planning work despite the graph containing rich related context.

**Fix:** Add a semantic similarity signal to F4's link methods (line 67): alongside `explicit-reference`, `temporal-cooccurrence`, `identifier-match`, and `embedding-similarity`, add `topic-overlap` as a relationship method that uses entity titles/descriptions for lightweight matching. Links created via `topic-overlap` are automatically classified as `speculative` confidence. Add acceptance criterion to F4: "Topic-overlap method detects semantic near-duplicates across subsystems; near-duplicate links are classified as speculative and surfaced when agents explicitly request speculative results."

---

### [P3] No access control model on graph traversal — all entities and relationships are equally visible to all agents

**Issue:** The PRD does not address access control on entity relationships. In e-discovery, some relationships are privileged (attorney-client) and must be withheld even though they exist in the graph. In the Sylveste ecosystem, the equivalent concern is weaker but real: an agent working on plugin A should not necessarily see the detailed session logs of an agent working on plugin B through a transitive bead relationship. The current ecosystem is single-user, so this is P3, but the graph's cross-system traversal could expose context that was not intended to be connected.

**Fix:** Add a "visibility scope" field to the link schema in F4: `scope: public | project | connector`. Public links are visible to all queries. Project-scoped links are visible only to queries originating from entities in the same project. Connector-scoped links are only visible to queries from the same connector. Default: public. Add as a future-iteration note to F4 rather than a v0.1 acceptance criterion.

--- VERDICT ---
STATUS: warn
FILES: 0 changed
FINDINGS: 5 (P0: 0, P1: 2, P2: 2, P3: 1)
SUMMARY: The PRD's entity resolution focuses on artifacts but completely omits person-entity resolution (the developer identity that spans all subsystems), the confidence scoring lacks a cost model that distinguishes high-stakes traversal edges from low-stakes leaf results, and the harvest model assumes comprehensive indexing rather than the iterative enrichment that prevents bootstrap-period abandonment.
---
