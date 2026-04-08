## Flux Drive Review — Auraken-to-Skaffen Migration PRD

**Reviewed**: 2026-04-07 | **Agents**: 16 triaged, 16 launched (4 tracks) | **Verdict**: pass-with-findings

### Prior Review Incorporation

The brainstorm review (2026-04-06, 16 agents, 4 tracks) found 3 P0 and 7 P1 issues plus 8 improvement suggestions. This PRD review checks whether the PRD incorporated those fixes and identifies new gaps in feature decomposition and acceptance criteria.

**All 3 P0 findings: FIXED**
- P0-1 (identity fracture): F11 specifies `user_id UUID PRIMARY KEY` + `transport_identities` join table + dry-run crosswalk
- P0-2 (bi-temporal timestamp loss): F11 specifies UTC normalization, microsecond precision
- P0-3 (concurrent dual-write): F11 specifies single-writer-per-user with routing table

**All 7 P1 findings: FIXED**
- P1-1 (no phase gates): Phase Boundary Gates table with explicit criteria for all 4 transitions
- P1-2 (no lens invariant spec): F1 specifies relational invariant spec, property-based parity tests, JSON canonical source
- P1-3 (persona decomposes emergence): F6 specifies conditions for emergence, post-integration voicing/calibration
- P1-4 (Python-shaped Go): Cross-Cutting specifies idiom audit with documented equivalents + Go expert review
- P1-5 (no rollback path): F12 specifies 30-day Skaffen-only, 90-day cold standby, rollback triggers
- P1-6 (Haiku routing): Cross-Cutting + F3/F4 specify provider abstraction routing
- P1-7 (evidence chain): F11 specifies migration order + provenance columns

**6/8 improvements: FIXED**
- IMP-3 (post-migration enrichment): Not addressed — deferred as out-of-scope (reasonable for migration PRD)
- IMP-4 (data cleaning before migration): Not addressed — dry-run crosswalk partially covers this but no explicit cleaning step

### New Findings

| Agent | Track | Status | Summary |
|-------|-------|--------|---------|
| fd-python-go-migration-fidelity | A-Adjacent | pass | All prior findings addressed in F1-F4 acceptance criteria |
| fd-go-package-api-design | A-Adjacent | warn | context.Context missing from LLM-calling package APIs (PRD-P1-2) |
| fd-persona-prompt-architecture | A-Adjacent | warn | Cache invalidation criteria missing for pre-turn hooks (PRD-P1-1) |
| fd-data-migration-identity | A-Adjacent | pass | All prior P0 findings fully addressed in F11 |
| fd-analysis-mode-design | A-Adjacent | warn | Analysis evidence separation lacks schema (PRD-P1-4) |
| fd-broadcast-signal-migration | B-Orthogonal | warn | Sealed sender handling vague (PRD-P1-3), hot-standby trigger unspecified (PRD-P2-1) |
| fd-archival-records-schema-migration | B-Orthogonal | pass | Provenance columns specified, migration order defined |
| fd-clinical-trial-site-transfer | B-Orthogonal | pass | Lock-migrate-verify-unlock addressed, reconciliation checksums specified |
| fd-intelligence-analysis-source-migration | B-Orthogonal | pass | Evidence chain preserved via migration order + regeneration |
| fd-togishi-sword-polishing-sequencing | C-Distant | warn | Voicing/calibration not scoped as discrete feature (PRD-P2-3) |
| fd-ethiopian-jebena-buna-identity-transformation | C-Distant | pass | Concurrent operation designed as legitimate state |
| fd-orgelbau-tonal-transplantation | C-Distant | warn | Voicing/calibration lacks measurable criteria (PRD-P2-3) |
| fd-thangka-iconometric-proportion | C-Distant | pass | Relational invariant spec and parity tests specified |
| fd-ethiopian-gult-tenure-layering | D-Esoteric | warn | Namespace collision prevention unspecified (PRD-P2-2) |
| fd-muisca-tumbaga-depletion-gilding | D-Esoteric | warn | Behavioral baseline not tracked as prerequisite (PRD-P2-5) |
| fd-noh-kata-hana-emergence | D-Esoteric | pass | Persona config captures emergence conditions, calibration specified |

### Findings by Severity

**P0: None** — All prior P0 issues resolved.

**P1 (4 findings)**

**PRD-P1-1: Async pre-turn hook caching lacks invalidation criteria** (fd-persona-prompt-architecture, fd-noh-kata-hana-emergence)
- F5 specifies "don't re-call Haiku if context unchanged" but never defines what "unchanged" means.
- Without cache key definition, stale context produces invisible personality drift.
- **Fix**: Define cache key per context provider (e.g., lens: message hash + recent history; fingerprint: entity count + timestamp).

**PRD-P1-2: No context.Context in LLM-calling package APIs** (fd-go-package-api-design, fd-python-go-migration-fidelity)
- `Extractor.Extract()` and profilegen APIs route Haiku calls through provider abstraction but acceptance criteria omit `context.Context` parameter.
- A hung Haiku call blocks the conversation indefinitely with no cancellation path.
- **Fix**: Add `ctx context.Context` as first parameter to all LLM-calling package functions.

**PRD-P1-3: Signal sealed sender handling too vague** (fd-broadcast-signal-migration, fd-clinical-trial-site-transfer)
- F9 lists "sealed sender handling" without specifying whether sealed messages are supported, degraded, or rejected.
- If sender identity is hidden, user routing fails silently.
- **Fix**: Specify behavior: extract sender from signal-cli-rest-api envelope; document limitation if not exposed.

**PRD-P1-4: Analysis evidence separation unspecified** (fd-analysis-mode-design)
- F7 says evidence is logged separately but does not define schema mechanism.
- Analysis replay turns could pollute real evidence, causing preference extraction to learn from debug interactions.
- **Fix**: Add `evidence_type=analysis` tag or separate table; require extraction/profilegen to exclude analysis evidence.

**P2 (5 findings)**

**PRD-P2-1: Hot-standby fallback trigger unspecified** (fd-broadcast-signal-migration)
- F9 states "hot-standby fallback" without trigger conditions or switchover mechanism.
- **Fix**: Define health check interval, failure threshold, and automatic routing table update.

**PRD-P2-2: ChatID namespace collision prevention unspecified** (fd-data-migration-identity, fd-ethiopian-gult-tenure-layering)
- F8 mentions namespace registry but F11 does not reference it.
- **Fix**: Add UNIQUE constraint on prefix in namespace registry; validate at transport startup.

**PRD-P2-3: Voicing/calibration phase is a gate condition, not a scoped feature** (fd-togishi-sword-polishing-sequencing, fd-orgelbau-tonal-transplantation)
- Referenced in F6 acceptance criteria and Phase 2->3 gate, but has no discrete acceptance criteria.
- **Fix**: Add measurable calibration criteria to the Phase 2->3 gate (N conversations tested, behavior-parity score threshold).

**PRD-P2-4: EMA cold-start handling unspecified** (fd-python-go-migration-fidelity, fd-thangka-iconometric-proportion)
- F2 lists "cold-start handling" without defining threshold, alpha values, or mode-switch behavior.
- **Fix**: Specify cold-start threshold, alpha_cold, alpha_steady, and mode-switch reset rule.

**PRD-P2-5: Behavioral baseline capture not tracked as prerequisite** (fd-muisca-tumbaga-depletion-gilding)
- Cross-Cutting mentions baseline capture but it is not a feature, prerequisite, or work item.
- **Fix**: Add as Phase 0 prerequisite or F0 with explicit fixture count and coverage requirements.

**P3 (2 findings)**

**PRD-P3-1: Voice transcription fallback chain ambiguous** (fd-ethiopian-jebena-buna-identity-transformation)
- F10 says "ported or delegated" for Deepgram + Whisper without clarifying the architecture.
- **Fix**: Specify whether transcription is a pkg/ library, Skaffen service, or external API call.

**PRD-P3-2: Community detection algorithm unspecified** (fd-go-package-api-design)
- F1 requires community detection without naming the algorithm. Go port must match Python's algorithm.
- **Fix**: Name the algorithm and require same-algorithm or parity-tested alternative.

### Section Heat Map

| Section | P0 | P1 | P2 | P3 | Agents Reporting |
|---------|----|----|----|----|-----------------|
| Go Package APIs (F1-F4) | 0 | 1 | 1 | 1 | 5 agents |
| OODARC / Prompt Pipeline (F5-F6) | 0 | 1 | 1 | 0 | 4 agents |
| Analysis Mode (F7) | 0 | 1 | 0 | 0 | 1 agent |
| Transport / Signal (F8-F9) | 0 | 1 | 2 | 0 | 4 agents |
| Identity / Migration (F11) | 0 | 0 | 1 | 0 | 2 agents |
| Cross-Cutting | 0 | 0 | 1 | 1 | 3 agents |

### Convergence Analysis

The PRD successfully incorporated all P0/P1 findings from the brainstorm review. The remaining gaps are at the P1-P2 level — acceptance criteria that are present in concept but lack implementation-level specificity. The strongest cross-track convergence is on voicing/calibration (PRD-P2-3), where both distant (togishi: phase gate rigor) and distant (orgelbau: tonal integration) agents independently flag the same gap from different perspectives.

No agent conflicts detected. All agents agree the PRD represents a strong improvement over the brainstorm.

### Verdict

**pass-with-findings** — The PRD correctly captures all P0/P1 fixes from the brainstorm review. 4 new P1 findings and 5 P2 findings relate to acceptance criteria that need more implementation specificity before entering the planning phase. None block the PRD from proceeding to planning, but all P1 items should be resolved before starting implementation.

### Files
- Summary: `docs/research/flux-drive/2026-04-07-auraken-skaffen-migration-prd-20260407T0256/summary.md`
- Findings: `docs/research/flux-drive/2026-04-07-auraken-skaffen-migration-prd-20260407T0256/findings.json`
- Prior review: `docs/research/flux-drive/2026-04-06-auraken-skaffen-migration-brainstorm-20260406T1911/summary.md`
