## Flux Drive Review — Auraken-to-Skaffen Migration Brainstorm

**Reviewed**: 2026-04-06 | **Agents**: 16 triaged, 16 launched (4 tracks) | **Verdict**: needs-changes

### Verdict Summary

| Agent | Track | Status | Summary |
|-------|-------|--------|---------|
| fd-python-go-migration-fidelity | A-Adjacent | warn | EMA float precision, sort stability, async-to-goroutine gaps need explicit parity tests |
| fd-go-package-api-design | A-Adjacent | warn | Package dependency direction unspecified; extraction may import fingerprint |
| fd-persona-prompt-architecture | A-Adjacent | warn | TOML schema completeness unverified vs 8+ prompt sections; token budget missing |
| fd-data-migration-identity | A-Adjacent | warn | Identity crosswalk lacks dry-run validation; bi-temporal timezone risk |
| fd-analysis-mode-design | A-Adjacent | warn | Live /analysis pauses flow without state snapshot/restore; observer problem |
| fd-broadcast-signal-migration | B-Orthogonal | warn | No parallel-run phase specified; cutover is all-or-nothing |
| fd-archival-records-schema-migration | B-Orthogonal | warn | No migration provenance columns; JSONB round-trip fidelity untested |
| fd-clinical-trial-site-transfer | B-Orthogonal | warn | No lock-migrate-verify-unlock sequence; reconciliation criteria absent |
| fd-intelligence-analysis-source-migration | B-Orthogonal | warn | Working profiles migrated without entity links; evidence chain breakable |
| fd-togishi-sword-polishing-sequencing | C-Distant | warn | No explicit validation gates at phase boundaries; Phase 4 irreversibility |
| fd-ethiopian-jebena-buna-identity-transformation | C-Distant | warn | Concurrent operation designed as hack, not legitimate transition state |
| fd-orgelbau-tonal-transplantation | C-Distant | warn | No voicing/calibration phase after Go integration |
| fd-thangka-iconometric-proportion | C-Distant | warn | No relational invariant spec for lens graph; proportional fidelity untested |
| fd-ethiopian-gult-tenure-layering | D-Esoteric | warn | Gult/rist separation unclear — transport-specific IDs risk tainting identity tables |
| fd-muisca-tumbaga-depletion-gilding | D-Esoteric | warn | Surface-substrate boundary not graduated; interface may leak Python patterns |
| fd-noh-kata-hana-emergence | D-Esoteric | warn | Persona config decomposes emergent personality into static rules |

### Critical Findings (P0)

**P0-1: Identity fracture during transport migration** (4/16 agents: fd-data-migration-identity, fd-ethiopian-jebena-buna, fd-ethiopian-gult, fd-clinical-trial-site-transfer)
- The brainstorm proposes `user_identities` for multi-transport identity mapping but does not specify whether the primary key is transport-agnostic. If transport-specific IDs (Telegram ID, Signal phone) serve as primary keys rather than a transport-agnostic UUID with transport mappings, adding a new transport requires schema surgery on the identity layer.
- The migration from Auraken's SQLAlchemy schema to Intercom's pgx schema has no specified dry-run validation step. Two Auraken users could map to the same Intercom chat_jid if normalization rules differ.
- **Fix**: Add a `user_id UUID PRIMARY KEY` with a separate `transport_identities` join table. Require dry-run identity crosswalk with diff report before any data moves.

**P0-2: Bi-temporal timestamp loss during migration** (3/16 agents: fd-data-migration-identity, fd-archival-records-schema, fd-ethiopian-gult)
- Preference entities use bi-temporal SPO triples with `valid_from`, `valid_to`, `expired_at`. The brainstorm mentions preserving timestamps but does not specify timezone handling, precision guarantees (nanosecond vs microsecond), or what happens when SQLAlchemy's `DateTime` maps to pgx's `timestamptz`.
- If timestamps are truncated to date precision or lose timezone info, preference ordering breaks, causing incoherent profile narratives.
- **Fix**: Specify UTC normalization and microsecond precision in the migration spec. Add round-trip assertion tests comparing Auraken output to migrated Intercom output.

**P0-3: Concurrent dual-write without arbitration** (4/16 agents: fd-clinical-trial-site-transfer, fd-ethiopian-jebena-buna, fd-broadcast-signal, fd-ethiopian-gult)
- Open Question 5 asks "How long is the overlap acceptable?" but the brainstorm has no dual-write arbitration protocol. During concurrent operation, both Auraken and Skaffen may write preference entities for the same user, creating contradictory histories.
- **Fix**: Designate single-writer-per-user during concurrent period. Either route each user to exactly one system, or make one system read-only during overlap.

### Important Findings (P1)

**P1-1: No phase boundary validation gates** (5/16 agents: fd-togishi, fd-orgelbau, fd-thangka, fd-python-go-migration, fd-go-package-api)
- The 4-phase sequencing says "Phase 1 children can run in parallel" and "Phase 2 is mostly sequential" but has no explicit acceptance criteria for phase transitions. Phase 1 packages built in isolation may have interface mismatches that only surface during Phase 2 integration.
- In togishi terms: moving from foundation stones to finish stones without inspection amplifies scratches.
- **Fix**: Add explicit gate criteria at each phase boundary. Phase 1 exit: all packages pass integration-pattern tests (not just unit tests). Phase 2 exit: live session shadow-mode with behavior parity assertions.

**P1-2: Missing relational invariant specification for lens library** (3/16 agents: fd-thangka, fd-python-go-migration, fd-muisca)
- The 291-lens + 1779-edge graph is the core intellectual asset. The brainstorm specifies `Selector` interface and JSON data source but does not define which graph properties must be preserved: edge weight semantics, community detection behavior, traversal ordering guarantees, sort stability.
- Go's `map` iteration is non-deterministic. Python's `dict` (3.7+) is insertion-ordered. If traversal relies on ordering, the Go version silently produces different top-3 lens selections.
- **Fix**: Write a relational invariant spec before coding. Include property-based tests that run identical inputs through both Python and Go implementations and assert output equivalence.

**P1-3: Persona config may decompose emergent personality** (3/16 agents: fd-noh-kata-hana, fd-persona-prompt-architecture, fd-orgelbau)
- Auraken's personality is an emergent property of the interaction between lens selection, style fingerprinting, preference context, and OODARC building. The persona TOML config decomposes this into declarative rules (anti-patterns, register matching) and template variables.
- Risk: the Go reimplementation follows every rule but produces responses that feel mechanical — kata without hana.
- **Fix**: Add a post-integration "voicing/calibration" phase (missing from the 4-phase plan) where the system's behavior in real sessions is observed and parameters are adjusted. The TOML config should define conditions for emergence, not the personality itself.

**P1-4: Python-shaped Go risk** (3/16 agents: fd-orgelbau, fd-muisca, fd-go-package-api)
- The brainstorm says "not 1:1 Python ports" but the interface descriptions (EMA dicts, async generators, pgvector) carry Python-era infrastructure assumptions. The Go packages may replicate Python's async patterns as channels/goroutines rather than achieving the same behavioral effect through Go-idiomatic patterns.
- **Fix**: Conduct a "wind supply audit" — for each Python pattern (async SQLAlchemy, pgvector, EMA dicts), explicitly document the Go-native equivalent and why it achieves the same behavioral effect.

**P1-5: No rollback path after Python decommission** (3/16 agents: fd-togishi, fd-clinical-trial-site-transfer, fd-broadcast-signal)
- Phase 4 decommissions the Python runtime. This is irreversible. The brainstorm has no explicit criteria for when decommission is safe, and no rollback triggers.
- **Fix**: Specify measurable decommission criteria (e.g., 30 days of Skaffen-only operation with <1% behavior regression vs Auraken baseline). Keep Auraken in read-only cold standby for 90 days.

**P1-6: Haiku call routing undecided** (2/16 agents: fd-go-package-api, fd-persona-prompt-architecture)
- Open Question 2 asks whether Haiku calls go through Skaffen's provider abstraction or direct API calls. This decision affects budget tracking, rate limiting, and coupling. The brainstorm leaves it open.
- **Fix**: Route through provider abstraction. The coupling cost is justified by budget tracking and rate limiting benefits.

**P1-7: Evidence chain breakage risk** (2/16 agents: fd-intelligence-analysis-source, fd-archival-records-schema)
- Working profiles should trace back to the preference_entities and profile_episodes that produced them. The migration may break these links if foreign keys change or if working profiles are migrated without regeneration.
- **Fix**: Migrate entities and episodes first, then regenerate working profiles from migrated data as a validation step.

### Improvements Suggested

1. **Add migration provenance columns** (fd-archival-records, fd-intelligence-analysis): Every migrated record should carry `source_system`, `migrated_at`, `original_id` — enables debugging and audit trail continuity.

2. **Design concurrent operation as legitimate state** (fd-ethiopian-jebena-buna): The dual-transport period is the "tona round" — explicitly design it with authority rules, not as a temporary hack. Specify which transport is authoritative for profile updates per user.

3. **Post-migration identity enrichment** (fd-ethiopian-jebena-buna, fd-ethiopian-gult): After migration, Intercom identity should offer capabilities Signal-only never had (cross-transport presence, unified profile). Specify this additive value.

4. **Data cleaning step before migration** (fd-ethiopian-jebena-buna): A "frankincense moment" — validate and clean data before migrating from SQLAlchemy to pgx schema.

5. **pkg/extraction hidden dependency on pkg/fingerprint** (fd-go-package-api, fd-togishi): Within Phase 1, check if extraction depends on fingerprint's StyleProfile output. If so, there's a sequential dependency within a nominally parallel phase.

6. **Canonical source declaration for lens data** (fd-thangka): Decide: is the JSON the canonical source (Go reads it), or is the Go struct canonical (JSON is derived)? This affects update flows.

7. **Context provider composition, not concatenation** (fd-noh-kata-hana): Pre-turn hooks should compose their outputs into an integrated perspective, not concatenate independent sections. Use a composition step that weaves LensContext, ProfileContext, and StyleContext.

8. **Reconciliation script with checksums** (fd-clinical-trial-site): Row counts + content checksums comparing Auraken source to Intercom target, run before declaring migration complete.

### Section Heat Map

| Section | P0 | P1 | P2 | Agents Reporting |
|---------|----|----|-----|-----------------|
| User Identity / Transport | 2 | 2 | 1 | 8 agents |
| Go Package Redesign | 0 | 3 | 2 | 7 agents |
| Phase Sequencing | 0 | 2 | 1 | 5 agents |
| Persona / Prompt Architecture | 0 | 2 | 2 | 4 agents |
| Data Migration / Schema | 1 | 2 | 2 | 5 agents |
| Analysis Mode | 0 | 1 | 2 | 3 agents |
| Concurrent Operation | 1 | 1 | 0 | 4 agents |

### Conflicts

No direct conflicts detected. All agents converge on the same high-risk areas (identity migration, phase gates, concurrent operation). Distant/esoteric lenses (togishi, jebena buna, orgelbau, thangka, gult, tumbaga, noh) independently validated the same structural concerns identified by adjacent agents, providing strong cross-track convergence.

### Files
- Summary: `/home/mk/projects/Sylveste/docs/research/flux-drive/2026-04-06-auraken-skaffen-migration-brainstorm-20260406T1911/summary.md`
- Findings: `/home/mk/projects/Sylveste/docs/research/flux-drive/2026-04-06-auraken-skaffen-migration-brainstorm-20260406T1911/findings.json`
