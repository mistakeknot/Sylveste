---
artifact_type: brainstorm
bead: sylveste-benl
stage: discover
---

# Auraken to Skaffen: Intelligence Layer Migration

## What We're Building

Auraken (Python) becomes a persona configuration in Skaffen (Go), not a standalone runtime. The migration decomposes into four layers:

1. **Go ecosystem packages** — Lens library, style fingerprinting, preference extraction, and profile generation redesigned as reusable Go packages under `pkg/` (not 1:1 Python ports). Any Skaffen agent can use them.
2. **Skaffen persona integration** — Auraken's OODARC prompt builder and personality become a persona TOML config that injects dynamic context (lens, profile, style, steering) via Skaffen's existing system prompt pipeline and pre-turn hooks.
3. **Intercom transport** — Signal and Telegram move to Intercom behind a new transport interface abstraction. User identity and profile data lives in Intercom's Postgres.
4. **Analysis mode** — Forge mode reimagined as Westworld-style host debugging: live in-band inspection (/analysis command) plus post-hoc separate-session replay. Builder can inspect lens selection reasoning, replay turns with different context, and adjust personality parameters.

End state: `auraken` is a directory in Skaffen containing a persona config, prompt templates, and analysis mode skills. The Python runtime is decommissioned.

## Why This Approach

**Redesign over port.** Auraken's Python modules are tightly coupled to async SQLAlchemy, pgvector, and Python-specific patterns (EMA dicts, async generators). Translating these idiom-by-idiom would produce unnatural Go. Redesigning as Go interfaces lets the packages fit the ecosystem (Skaffen's provider abstraction, Intercom's pgx layer, masaq's shared types).

**Intercom as data home.** Intercom already persists per-user/per-chat state in Postgres (pgx/v5). Extending its schema with profile and preference tables avoids a second database. Skaffen reads user context via MCP tools or direct DB access during the Orient phase.

**Intelligence-first sequencing.** The Go packages (lens, fingerprint, extraction, profile) have zero runtime dependencies — they can be built and tested in isolation before wiring into Skaffen or Intercom. This validates the hardest unknowns (Go redesign of ML-adjacent logic) before touching production transports.

**Interface-first transport.** Intercom's Telegram is currently hardcoded into main.go. Signal landing as a second hardcoded transport would compound the problem. Extracting a Transport interface before porting Signal forces clean separation and makes future transports (WhatsApp, Discord, web) trivial.

## Key Decisions

### 1. Go packages are ecosystem-wide, not Auraken-specific
- `pkg/lens` — Lens selection, graph traversal, community detection. Reads lens_library_v2.json + lens_edges.json. Exposes `Selector` interface for any agent to pick lenses given a message.
- `pkg/fingerprint` — Style observation (word count, contractions, mode classification, register detection). Produces `StyleProfile` structs. No DB dependency — callers persist.
- `pkg/extraction` — Preference extraction via LLM (SPO triples). Defines `Extractor` interface with `Extract(message, existingEntities) -> []Delta`. Callers handle storage and bi-temporal semantics.
- `pkg/profilegen` — Profile narrative generation from preference entities + conversation. Pure function: entities in, narrative out.

### 2. Persona config model in Skaffen
Auraken becomes a persona TOML file that configures:
- Base personality (PM on first day, not friend/therapist)
- Anti-patterns (no flattery, no AI-isms, no italics)
- Register matching rules
- Adaptive depth thresholds
- OODARC section templates with `{{.LensContext}}`, `{{.ProfileContext}}`, `{{.StyleContext}}` template variables
- Context provider hooks: pre-turn functions that populate template variables by calling pkg/ libraries

### 3. User identity in Intercom's Postgres
Transport-agnostic identity model:
- `users` — `user_id UUID PRIMARY KEY` as the canonical identity. Transport-agnostic.
- `transport_identities` — Join table: `(user_id, transport, transport_id)`. Maps `tg:123`, `signal:+1234567890` to one user. Enables cross-transport identity without schema surgery when adding transports.
- `preference_entities` — Bi-temporal SPO triples (immutable, only expired via `valid_until`). UTC normalization, microsecond precision on `valid_from/valid_until`. Migration must preserve timezone and sub-second ordering.
- `profile_episodes` — Immutable conversation evidence chunks
- `working_profiles` — LLM-generated narrative profiles. Migrated profiles carry `source_system=auraken`, `migrated_at`, `original_id` provenance columns. After migration, regenerate from migrated entities as validation — if regenerated profile diverges significantly from migrated profile, flag for review.
- `style_fingerprints` — Per-mode EMA style observations
- pgvector extension for profile embeddings (if needed; evaluate whether Intercom's Postgres version supports it)

**Migration provenance:** Every migrated record carries `source_system`, `migrated_at`, `original_id`. Native records have `source_system=intercom`. This enables debugging and audit trail continuity across the migration boundary.

**Identity crosswalk validation:** Before any data moves, run a dry-run crosswalk that produces a diff report: Auraken user → Intercom user_id mapping, flagging any collisions (two Auraken users mapping to the same identity) or orphans (Auraken users with no Intercom match).

### 4. Transport interface in Intercom
```go
type Transport interface {
    Run(ctx context.Context) error
    Name() string
}

type IncomingMessage struct {
    ChatID    string    // normalized: "tg:123", "signal:+1234567890"
    SenderID  string
    Text      string
    MediaType string    // "", "photo", "voice", "document"
    Timestamp time.Time
}

type Messenger interface {
    SendText(ctx context.Context, chatID string, text string) error
    SendTyping(ctx context.Context, chatID string) error
}
```
Telegram and Signal both implement Transport + Messenger. Main.go wires handlers generically.

### 5. Analysis mode (Westworld debugging)
Two interfaces to the same inspection capability:
- **Live:** `/analysis` command in any active conversation. Pauses normal flow. Builder can: inspect current lens selection reasoning, view style fingerprint state, see preference entity deltas, replay last turn with modified context.
- **Post-hoc:** Separate Skaffen session targeting a conversation history. Can: replay any turn, diff lens selections across turns, visualize profile evolution over time, A/B test personality parameter changes.

Underlying capability: an `Inspector` package that reads session evidence + preference state and produces structured analysis. Both interfaces call the same Inspector.

### 6. Phased sequencing (intelligence-first)

| Phase | Children | Dependency | Validates |
|-------|----------|------------|-----------|
| 1: Go packages | benl.1, benl.2, benl.4, benl.5 | None (pure libraries) | Go redesign of ML-adjacent logic |
| 2: Skaffen integration | benl.3, benl.8, benl.9 | Phase 1 packages | Persona config + prompt pipeline |
| 3: Transport | benl.6, benl.7, benl.10 | Phase 2 (agent must exist) | Signal in Intercom, identity DB |
| 4: Decommission | benl.11 | Phases 1-3 complete | Python runtime removed |

Phase 1 children can run in parallel (but check: does extraction depend on fingerprint's StyleProfile output? If so, sequential dependency within Phase 1). Phase 2 is mostly sequential (prompt builder before persona config before analysis mode). Phase 3 can partially parallelize (interface + Signal vs Telegram migration).

**Phase boundary gates (mandatory):**
- **Phase 1 → 2 gate:** All packages pass integration-pattern tests (not just unit tests). Lens graph property-based parity tests pass. Package interfaces reviewed for Go idiom compliance.
- **Phase 2 → 3 gate:** Skaffen agent produces behavior-parity responses vs Auraken baseline in shadow mode. Post-integration voicing/calibration session completed.
- **Phase 3 → 4 gate:** 30 days of Skaffen-only operation with <1% behavior regression vs Auraken baseline. All users migrated. Reconciliation checksums pass.
- **Phase 4 completion:** Auraken enters read-only cold standby for 90 days before full decommission. Explicit rollback trigger criteria documented.

### 7. Concurrent operation protocol
During the overlap period, designate **single-writer-per-user**: each user is routed to exactly one system for preference writes. The non-authoritative system operates read-only for that user. Routing table tracks which system owns each user. Migration moves users in cohorts, not all-at-once.

This is a legitimate transition state, not a hack. The concurrent period has its own design: authority rules, user-routing table, conflict detection, and explicit exit criteria.

### 8. Lens graph relational invariants
Before any Go code, write a relational invariant specification for the lens library:
- Which graph properties must be preserved: edge weight semantics, community membership, bridge scores
- Traversal ordering guarantees (Python's insertion-ordered dict vs Go's non-deterministic map)
- Sort stability for top-N lens selection
- Property-based parity tests: identical inputs through Python and Go produce identical top-3 lens selections

JSON is the canonical source (Go reads it at startup via `embed`). Go structs are derived. Update flow: edit JSON, rebuild.

### 9. Haiku call routing
Route through Skaffen's provider abstraction, not direct API calls. The coupling cost is justified by:
- Budget tracking (Haiku calls count against session token budget)
- Rate limiting (shared limiter across all agent calls)
- Model routing (Intercore can override Haiku → different model if needed)
- Evidence emission (lens selection and extraction calls appear in session evidence)

### 10. Python-to-Go idiom audit
For each Python pattern used in Auraken, document the Go-native equivalent before coding:
- async SQLAlchemy → pgx with connection pool
- async generators → channels or iterators
- EMA dicts → typed structs with method receivers
- exception-based flow → error returns with wrapping
- duck typing → explicit interfaces

Review each Go package for "Python-shaped Go" — code that compiles but violates Go idioms. A Go expert (not the Python author) should review.

### 11. Persona config captures conditions for emergence, not the personality itself
The TOML config defines:
- Anti-patterns and guard rails (what NOT to do)
- Register matching rules (observation → response style mapping)
- Context provider composition (how lens, profile, style sections integrate — composition, not concatenation)
- Calibration parameters that can be tuned post-integration

It does NOT define the personality directly. Personality emerges from the interaction of lens selection, profile context, style matching, and the base OODARC phase. A post-integration voicing/calibration phase (between Phase 2 and Phase 3) validates that emergence works.

### 12. Evidence chain preservation
Migration order for data integrity:
1. Migrate `preference_entities` and `profile_episodes` first (immutable source data)
2. Regenerate `working_profiles` from migrated entities as validation
3. Compare regenerated profiles to migrated profiles — divergence flags data integrity issues
4. Only then migrate `style_fingerprints` (derived, can be recomputed)

Every migrated entity retains its extraction context (which message, which model, which prompt version) via provenance columns.

## Open Questions

1. ~~**Lens library size in Go**~~ — **Resolved (Decision 8):** JSON is canonical source, loaded via Go `embed`. Update flow: edit JSON, rebuild.

2. ~~**Haiku call patterns**~~ — **Resolved (Decision 9):** Route through Skaffen's provider abstraction for budget tracking, rate limiting, and evidence emission.

3. **Migration of existing user data** — Partially resolved (Decisions 3, 7, 12). Migration order and provenance specified. Remaining: write the actual migration script with dry-run mode and reconciliation checksums.

4. **pgvector in Intercom** — Still open. Check Intercom's Postgres version. If pgvector unavailable, profile embeddings can be deferred to post-migration (they're derived data, recomputable from entities).

5. ~~**Concurrent operation period**~~ — **Resolved (Decision 7):** Single-writer-per-user with routing table. Cohort-based migration. Legitimate transition state with authority rules and exit criteria.
