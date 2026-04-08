---
artifact_type: plan
bead: sylveste-benl
prd: docs/prds/2026-04-06-auraken-skaffen-migration.md
brainstorm: docs/brainstorms/2026-04-06-auraken-skaffen-migration-brainstorm.md
stage: plan
---

# Plan: Auraken to Skaffen Intelligence Layer Migration

## Overview

Migrate Auraken from standalone Python app to Skaffen ecosystem. 12 features across 4 phases, intelligence-first sequencing. Each task is scoped for one agent session (1-3 hours).

## Phase 0: Prerequisites

### Task 0.1: Capture behavioral baseline from Auraken
**Bead:** n/a (cross-cutting prerequisite)
**Files:** `apps/Auraken/tests/fixtures/`
**Steps:**
1. Read `apps/Auraken/src/auraken/lenses.py` — understand lens selection logic and inputs
2. Create test fixture generator: 35 diverse messages (5 per conversation mode, all 7 modes), with explicit lens community coverage requirement (at least 2 messages should trigger each of the 7 Louvain communities)
3. Run each through Auraken's lens selector, record top-3 selections as golden outputs. **Record the Haiku responses separately** so deterministic components (graph traversal, sort) can be tested independently from LLM components.
4. Run each through style fingerprinter, record StyleProfile as golden outputs
5. Run 5 messages through preference extraction, record SPO triple deltas
6. Run extracted entities through profile generation, record narrative
7. Save all golden outputs as JSON fixtures in `apps/Auraken/tests/fixtures/parity/`
8. Document the Auraken git SHA and model versions used for baseline

**Acceptance:** 35 message fixtures with golden outputs for lens, fingerprint, extraction, and profilegen. All 7 communities covered. Haiku responses recorded separately for deterministic testing.

### Task 0.2: Write relational invariant spec for lens graph
**Bead:** benl.1
**Files:** `docs/specs/lens-graph-invariants.md`
**Steps:**
1. Read `apps/Auraken/src/auraken/lens_library_v2.json` — document JSON schema
2. Read `apps/Auraken/src/auraken/lens_edges.json` — document edge types and weights
3. Read `apps/Auraken/src/auraken/lens_communities.json` — document community structure
4. Read `apps/Auraken/src/auraken/lenses.py` — trace selection algorithm:
   - How are lenses ranked? (score function, tiebreakers)
   - Is traversal order deterministic? (insertion order dependency?)
   - How are communities used in selection?
   - How do bridge scores affect ranking?
5. Write spec: which properties must be preserved (sort stability, edge weight semantics, community membership, bridge scores, effectiveness EMA)
6. Define parity test contract: `Select(msg, history) -> top-3 IDs` must match Python for all fixtures

**Acceptance:** Spec document with explicit invariants. Python developer could verify Go implementation against it.

### Task 0.3: Document Python-to-Go idiom mapping
**Bead:** n/a (cross-cutting)
**Files:** `docs/specs/python-go-idiom-map.md`
**Steps:**
1. Read key Auraken modules: `agent.py`, `lenses.py`, `style.py`, `extraction.py`, `profile_gen.py`, `signals.py`
2. For each Python pattern, document the Go equivalent:
   - `async def` / `await` → goroutines + channels or sync functions
   - `async generators` → channels or iterators
   - `dict` with dynamic keys → typed structs
   - `EMA dicts` (per-mode) → `map[Mode]*EMAState` with method receivers
   - `SQLAlchemy async session` → pgx connection pool
   - `try/except` flow control → error returns with `fmt.Errorf` wrapping
   - `dataclass` → Go struct with constructor function
   - `signal bus` (pub/sub) → channels or callback registration
   - `Haiku JSON structured output` → provider.Stream + JSON unmarshal
3. Flag any patterns with no clean Go equivalent (potential redesign points)

**Acceptance:** Mapping document. Each entry has Python example, Go equivalent, and rationale.

---

## Phase 1: Go Ecosystem Packages

Tasks within Phase 1 can run in parallel. Verified: `extraction.py` does NOT import or reference StyleProfile, style.py, or fingerprint. All Phase 1 packages are independently buildable.

### Task 1.1: Scaffold pkg/ directory structure
**Bead:** benl.1
**Files:** `os/Skaffen/pkg/lens/`, `os/Skaffen/pkg/fingerprint/`, `os/Skaffen/pkg/extraction/`, `os/Skaffen/pkg/profilegen/`
**Steps:**
1. Create package directories under `os/Skaffen/pkg/`
2. Add go files with package declarations and doc comments
3. Define shared types in `os/Skaffen/pkg/types/` if needed (e.g., `Message`, `Entity` structs used across packages)
4. Verify `go build ./pkg/...` succeeds with empty packages
5. Update `os/Skaffen/go.mod` if needed

**Acceptance:** `go build ./pkg/...` passes. Each package has a doc.go with purpose description. Shared types package (`pkg/types/`) defined with `Message`, `Entity`, `StyleProfile`, `Delta` structs reviewed for minimal coupling.

### Task 1.2: Implement pkg/lens — lens library
**Bead:** benl.1
**Files:** `os/Skaffen/pkg/lens/`
**Steps:**
1. Read invariant spec from Task 0.2
2. Embed `lens_library_v2.json` and `lens_edges.json` via `//go:embed`
3. Define types: `Lens`, `Edge`, `Community`, `Graph`
4. Parse embedded JSON into typed structs at init time
5. Implement `Graph` with:
   - `Load()` — parse embedded data
   - `Communities()` — return Louvain communities
   - `BridgeLenses()` — return cross-community bridges
   - `Neighbors(lensID, edgeType)` — graph traversal
6. Define `Selector` interface: `Select(ctx context.Context, message string, history []string) ([]Lens, error)`
7. Implement `HaikuSelector` that:
   - Takes a `provider.Provider` for Haiku calls
   - Sends message + all lens metadata to Haiku
   - Parses structured JSON response for top-N lens IDs
   - Returns `[]Lens` sorted by relevance
8. Ensure deterministic sort: use stable sort with explicit tiebreaker (lens ID)
9. Write unit tests using golden fixtures from Task 0.1
10. Write property-based parity tests comparing Go output to Python golden outputs

**Acceptance:** All deterministic parity tests pass (graph traversal, sort stability, bridge scoring produce identical results). For Haiku-dependent selection: use recorded Haiku responses from fixtures (not live calls) to test Go's prompt construction and response parsing. `Selector.Select()` with recorded responses returns identical top-3 for all 35 fixture messages.

### Task 1.3: Implement pkg/fingerprint — style fingerprinting
**Bead:** benl.2
**Files:** `os/Skaffen/pkg/fingerprint/`
**Steps:**
1. Read `apps/Auraken/src/auraken/style.py` — understand all observables and EMA logic
2. Define types: `StyleProfile`, `ModeProfile`, `Mode`, `Register`, `Observation`
3. Define `Mode` enum: emotional, analytical, playful, intimate, logistics, update, general
4. Implement `Observer` struct with:
   - `Observe(message string) Observation` — extract raw observables (word count, contractions, laughter, emoji, punctuation, caps, hedging)
   - `Classify(obs Observation) Mode` — classify conversation mode
   - `Update(profile *StyleProfile, obs Observation, mode Mode)` — update per-mode EMA
5. EMA implementation:
   - Configurable `Alpha` (default from Python, e.g., 0.1)
   - Cold-start: use raw value for first N observations (threshold configurable), then switch to EMA
   - Per-mode separate profiles
6. Register detection: `DetectRegister(profile *StyleProfile) Register`
7. No DB dependency — `StyleProfile` is a plain struct, callers marshal/persist
8. Write parity tests against Python golden fixtures
9. Test edge cases: empty messages, very long messages, non-English text (contraction detection should degrade gracefully)

**Acceptance:** EMA values within float64 epsilon of Python outputs. Mode classification matches for all fixtures.

### Task 1.4: Implement pkg/extraction — preference extraction
**Bead:** benl.4
**Files:** `os/Skaffen/pkg/extraction/`
**Steps:**
1. Read `apps/Auraken/src/auraken/extraction.py` — understand SPO triple logic, dedup, contradiction handling
2. Define types: `Entity`, `Delta`, `DeltaAction` (ADD/UPDATE/EXPIRE/NOOP), `Domain`
3. Define `Extractor` interface: `Extract(ctx context.Context, message string, existing []Entity) ([]Delta, error)`
4. Implement `HaikuExtractor`:
   - Takes `provider.Provider` for Haiku structured output calls
   - Prompt: classify intent (preference signal vs neutral), extract SPO triples
   - Compare against existing entities, produce Delta actions
   - Contradiction handling: detect stated vs revealed behavior, mark "submerged" origin
5. Burst deduplication: `Deduplicator` struct with 3-second window, coalesces rapid messages
6. Domain classification: goals, constraints, values, priorities, patterns, decisions, skills, relationships
7. All exported functions take `ctx context.Context` as first parameter
8. Write tests with fixture messages that contain preference signals

**Acceptance:** Extract produces correct Delta actions for fixture messages. Burst dedup tested with rapid-fire inputs.

### Task 1.5: Implement pkg/profilegen — profile generation
**Bead:** benl.5
**Files:** `os/Skaffen/pkg/profilegen/`
**Steps:**
1. Read `apps/Auraken/src/auraken/profile_gen.py` — understand narrative structure and prompt
2. Define `Generator` interface: `Generate(ctx context.Context, entities []Entity, recentConversation []string) (string, error)`
3. Implement `LLMGenerator`:
   - Takes `provider.Provider` for Sonnet/Haiku calls
   - Prompt template covering: core goals, constraints, values, thinking patterns, contradictions
   - Target: 300-500 token narrative
4. All exported functions take `ctx context.Context`
5. Test with fixture entities from Task 0.1

**Acceptance:** Generated narratives cover required topics. Length within target range.

### Task 1.6: Phase 1 integration test suite
**Bead:** benl.1 (cross-cutting)
**Files:** `os/Skaffen/pkg/integration_test.go`
**Steps:**
1. Write integration test that exercises the full pipeline: message → lens selection → extraction → fingerprint update → profile regen
2. Use a mock provider (local provider in Skaffen) to avoid real API calls
3. Verify packages compose correctly: no import cycles, compatible types
4. Verify each package has zero imports from siblings
5. Run `go vet ./pkg/...` and `staticcheck ./pkg/...`

**Acceptance:** Integration test passes. No import cycles. go vet clean. Optional: run `go test ./pkg/... -integration` against live Haiku for a subset of fixtures to validate the LLM call path (not required for gate).

### Phase 1 → 2 Gate
- [ ] All parity tests pass (lens, fingerprint, extraction, profilegen)
- [ ] Integration test passes
- [ ] Each package reviewed for Go idiom compliance (no Python-shaped Go)
- [ ] `go vet` and `staticcheck` clean

---

## Phase 2: Skaffen Integration

Two sequential chains that can be parallel with each other:
- Chain A: Task 2.1a → 2.1b → 2.2a → 2.2b → 2.3 → 2.4
- Chain B: Task 2.5 → 2.6

### Task 2.1a: Design and implement ContextProvider interface
**Bead:** benl.3
**Files:** `os/Skaffen/internal/agent/context.go`
**Steps:**
1. Read `os/Skaffen/internal/agent/agent.go` and `deps.go` — understand current system prompt construction (`SystemPrompt(phase, budget) string` — static string, no provider pipeline)
2. Design `ContextProvider` interface:
   ```go
   type ContextProvider interface {
       Name() string
       Provide(ctx context.Context, turn TurnContext) (string, error)
       CacheKey(turn TurnContext) string
   }
   ```
3. Implement provider registry in agent: ordered list of providers, called pre-turn
4. Test with a mock provider

**Acceptance:** ContextProvider interface compiles. Provider registry calls providers in order. Mock provider test passes.

### Task 2.1b: Implement caching, token budgeting, and composition
**Bead:** benl.3
**Files:** `os/Skaffen/internal/agent/context.go`
**Steps:**
1. Implement caching layer: cache by `CacheKey()` output, invalidate on change
2. Implement token budgeting: each provider has a max token budget, overflow truncates oldest content
3. Implement composition step: providers can declare dependencies, compose outputs semantically (not just concatenate)
4. Test: cache invalidation works correctly, token budget enforced, composition order correct

**Acceptance:** Cache invalidation tested. Token budget enforced. Composition produces integrated output.

### Task 2.2a: Implement core context providers (Lens, Profile, Style)
**Bead:** benl.3
**Files:** `os/Skaffen/internal/auraken/providers.go`
**Steps:**
1. Read `apps/Auraken/src/auraken/prompts.py` — map each section to a provider
2. Implement `LensContextProvider` — calls `pkg/lens.Selector`, formats selected lenses + forces + questions. Cache key: hash(message + last 3 turns)
3. Implement `ProfileContextProvider` — reads working profile from DB/state. Cache key: entity count + latest entity timestamp
4. Implement `StyleContextProvider` — reads StyleProfile, generates register-matching instructions. Cache key: hash(message text)
5. Write parity tests: compare each provider's output to corresponding Auraken prompt section

**Acceptance:** Three core providers produce output matching Auraken's prompt sections for test inputs.

### Task 2.2b: Implement auxiliary providers + wiring + validation
**Bead:** benl.3
**Files:** `os/Skaffen/internal/auraken/providers.go`
**Steps:**
1. Implement `SteeringContextProvider` — reads reframe engine output (if exists)
2. Implement `FeedbackContextProvider` — reads meta-feedback as instructions
3. Implement `SessionContextProvider` — last N exchanges
4. Wire all 6 providers into the agent context pipeline in correct order
5. Validate: for a given input, assembled system prompt matches Auraken's output section-by-section

**Acceptance:** Full system prompt assembled from all 6 providers matches Auraken's prompts.py output for test inputs.

### Task 2.3: Create Auraken persona TOML config
**Bead:** benl.8
**Files:** `os/Skaffen/personas/auraken.toml`
**Steps:**
1. Read `apps/Auraken/src/auraken/prompts.py` — extract all personality rules
2. Read `apps/Auraken/PHILOSOPHY.md` — extract design principles
3. Create TOML config with sections:
   - `[personality]` — base personality (PM on first day), OODARC approach
   - `[anti_patterns]` — no flattery, no AI-isms, no italics, no leading questions
   - `[register_matching]` — rules for mirroring user's communication style
   - `[adaptive_depth]` — shallow → deep escalation thresholds
   - `[providers]` — ordered list of context providers to register
   - `[calibration]` — tunable parameters (lens gating threshold, EMA alpha, etc.)
4. Implement persona loader in Skaffen that reads TOML and configures agent
5. Test: loading persona config produces a working agent with Auraken personality

**Acceptance:** `skaffen --persona=auraken` launches an agent with correct personality. Validated against prompts.py.

### Task 2.4: Voicing/calibration session
**Bead:** benl.8
**Files:** n/a (manual validation)
**Steps:**
1. Run Skaffen-Auraken agent against 10 test conversations
2. Compare response quality, personality consistency, lens selection against Auraken baseline
3. Adjust calibration parameters in persona TOML based on observed differences
4. Document parameter adjustments and rationale
5. Re-run and verify behavior-parity improves

**Acceptance:** Skaffen-Auraken responses are qualitatively indistinguishable from Auraken for test conversations.

### Task 2.5: Implement Inspector package for analysis mode
**Bead:** benl.9
**Files:** `os/Skaffen/internal/auraken/inspector.go`
**Steps:**
1. Read `os/Skaffen/internal/evidence/emitter.go` — understand existing evidence emission patterns and `Emitter` interface
2. Design `Inspector` struct with read-only access to:
   - Lens selection reasoning (which lenses, why, scores)
   - Style fingerprint state (current profile, mode history)
   - Preference entity deltas (recent ADD/UPDATE/EXPIRE)
   - Provider cache state (what's cached, cache keys)
3. Integrate with existing evidence infrastructure (use `Emitter` interface, not parallel system)
4. Implement session snapshot/restore for live analysis (copy-on-write semantics)
5. Implement turn replay: re-execute a turn with modified context (different lenses, different profile)
6. Add `evidence_type=analysis` tag to all evidence emitted during analysis mode
7. Ensure extraction and profilegen pipelines filter out analysis evidence

**Acceptance:** Inspector provides read-only access to all agent internals. Uses existing evidence infrastructure. Analysis evidence isolated.

### Task 2.6: Implement /analysis skill command
**Bead:** benl.9
**Files:** `os/Skaffen/commands/analysis/SKILL.md`
**Steps:**
1. Create SKILL.md for `/analysis` command
2. Live mode: pause current conversation, enter inspection REPL
   - `inspect lenses` — show current lens selection + reasoning
   - `inspect profile` — show current working profile
   - `inspect style` — show style fingerprint state
   - `replay [turn_id] [--context=modified]` — replay a turn
   - `resume` — restore session state and continue conversation
3. Post-hoc mode: load conversation history, replay any turn
4. Builder identity gating: check config for authorized builder IDs
5. Wire Inspector package as backend for both modes

**Acceptance:** /analysis works in both live and post-hoc modes. Session state preserved after analysis.

### Phase 2 → 3 Gate
- [ ] Skaffen-Auraken agent produces behavior-parity responses in shadow mode
- [ ] Voicing/calibration session completed with documented adjustments
- [ ] /analysis command works in both modes
- [ ] Analysis evidence properly isolated

---

## Phase 3: Transport Migration

F8 (transport interface) must complete before F9 (Signal) and F10 (Telegram). F11 (identity DB) can partially parallel with F8.

### Task 3.1: Design and implement Transport interface in Intercom
**Bead:** sylveste-2nfd
**Files:** `apps/Intercom/go/internal/transport/`
**Steps:**
1. Read `apps/Intercom/go/internal/telegram/bot.go` and `delivery.go`
2. Read `apps/Intercom/go/cmd/intercomd/main.go` — understand current Telegram wiring
3. Create `transport` package with interfaces:
   ```go
   type Transport interface {
       Run(ctx context.Context) error
       Name() string
   }
   type Messenger interface {
       SendText(ctx context.Context, chatID string, text string) error
       SendTyping(ctx context.Context, chatID string) error
       SendWithButtons(ctx context.Context, chatID string, text string, buttons []Button) error
       EditText(ctx context.Context, chatID string, messageID string, text string) error
   }
   type IncomingMessage struct {
       ChatID    string
       SenderID  string
       Text      string
       MediaType string
       Timestamp time.Time
       Transport string // "telegram", "signal"
   }
   ```
4. Create namespace registry: `map[string]string` with UNIQUE prefix enforcement
5. Refactor Telegram to implement both interfaces
6. Update main.go to use generic handler wiring (no transport-specific code in main)
7. Test: existing Telegram functionality works identically through new interface

**Acceptance:** Telegram works through Transport interface. main.go has no transport-specific handler code.

### Task 3.2: Implement identity schema in Intercom's Postgres
**Bead:** benl.10
**Files:** `apps/Intercom/go/internal/db/identity.go`, `apps/Intercom/go/internal/db/schema.go`
**Steps:**
1. Read `apps/Intercom/go/internal/db/schema.go` — understand existing schema
2. Add tables matching Auraken's actual schema (10 tables in `models.py`):
   - `users` — `user_id UUID PRIMARY KEY DEFAULT gen_random_uuid()`, `created_at`, `updated_at`
   - `transport_identities` — `(user_id, transport, transport_id)` UNIQUE on `(transport, transport_id)` (replaces Auraken's `user_identities`)
   - `core_profiles` — structured_prefs JSONB, style_fingerprint JSONB, profile_dirty_since (matches Auraken's structure — style fingerprint is JSONB in this table, NOT a separate table)
   - `preference_entities` — bi-temporal: `valid_from TIMESTAMPTZ`, `valid_until TIMESTAMPTZ` (Auraken uses `valid_until`, NOT `valid_to`; no `expired_at` column)
   - `profile_episodes` — immutable conversation evidence
   - `working_profiles` — LLM-generated narratives
   - `sessions` — conversation history (message arrays)
   - `lens_usage` — adaptive lens evolution history (effectiveness scores, selection counts)
   - `profile_embeddings` — pgvector (defer if pgvector unavailable)
   - Skip `venue_cache` (Auraken-specific, not needed in Intercom)
3. All tables have `source_system TEXT DEFAULT 'intercom'`, `migrated_at TIMESTAMPTZ`, `original_id TEXT`
4. Write CRUD functions for each table
5. Run schema with `ensure_schema()` on startup

**Acceptance:** Schema created. CRUD operations tested. Provenance columns on all tables.

### Task 3.3: Write Auraken data migration script
**Bead:** benl.10
**Files:** `apps/Intercom/go/cmd/migrate-auraken/main.go`
**Steps:**
1. Read `apps/Auraken/src/auraken/models.py` — understand source schema (10 tables: users, user_identities, sessions, core_profiles, preference_entities, profile_episodes, profile_embeddings, working_profiles, lens_usage, venue_cache)
2. **Prerequisite:** Verify network connectivity between migration host and both Postgres instances (Auraken on sleeper-service, Intercom location). Document connection strings or environment variables needed.
3. Connect to both Auraken Postgres and Intercom Postgres
3. Implement dry-run identity crosswalk:
   - Map Auraken `users` + `user_identities` → Intercom `users` + `transport_identities`
   - Detect collisions (two Auraken users → same transport_id)
   - Produce diff report: mapped, collisions, orphans
4. Migration order (all 9 migratable tables):
   a. Users and transport identities (from `users` + `user_identities`)
   b. Core profiles (structured_prefs JSONB, style_fingerprint JSONB — single table, not separate)
   c. Preference entities (preserve `valid_from`/`valid_until` timestamps, UTC normalize, microsecond precision)
   d. Profile episodes (immutable, copy directly)
   e. Sessions (conversation history — evaluate: migrate or let new sessions accumulate naturally?)
   f. Lens usage (adaptive evolution — needed for warm-start; without it, lens effectiveness scores reset)
   g. Regenerate working_profiles from migrated entities (validation step)
   h. Profile embeddings (pgvector — defer if unavailable, recomputable)
5. Compare regenerated profiles to original — flag significant divergence
6. Reconciliation: row counts + content checksums per table
7. All migrated records: `source_system='auraken'`, `migrated_at=now()`, `original_id=<auraken_id>`

**Acceptance:** Dry-run produces clean diff. Migration completes with matching checksums. Regenerated profiles validate.

### Task 3.4: Implement Signal transport adapter
**Bead:** benl.6
**Files:** `apps/Intercom/go/internal/signal/`
**Steps:**
1. Read `apps/Auraken/src/auraken/signal_transport.py` — understand WebSocket + REST pattern
2. Implement `signal.Bot` implementing `transport.Transport`:
   - WebSocket connection to signal-cli-rest-api
   - JSON-RPC message parsing
   - OnMessage/OnCommand/OnCallback handlers
3. Implement `signal.Messenger` implementing `transport.Messenger`:
   - REST API for sending messages
   - Chat ID normalization: `signal:+1234567890`
4. Handle sealed sender: extract from envelope; degrade gracefully if absent
5. Linked device normalization: resolve to single user_id by phone number
6. Wire into main.go through Transport interface
7. Test with signal-cli-rest-api in dev environment

**Acceptance:** Signal messages received and responded to through Intercom. Sealed sender handled.

### Task 3.5: Implement concurrent operation routing table
**Bead:** benl.10
**Files:** `apps/Intercom/go/internal/db/routing.go`
**Steps:**
1. Create `user_routing` table: `(user_id, authoritative_system TEXT, routed_at TIMESTAMPTZ)`
2. Implement routing logic: check `user_routing` before writing preferences
3. Default: new users → Intercom (authoritative). Existing Auraken users → Auraken until migrated.
4. Migration moves users in cohorts (batch update routing table)
5. Non-authoritative system operates read-only for that user's preference data

**Acceptance:** Routing table enforces single-writer-per-user. Cohort migration tested.

### Task 3.6: Migrate Telegram commands from Auraken
**Bead:** benl.7
**Files:** `apps/Intercom/go/internal/telegram/commands.go`
**Steps:**
1. Read `apps/Auraken/src/auraken/telegram.py` — list all commands and behaviors
2. Implement missing commands in Intercom's Telegram adapter: /start, /new, /profile, /forget, /deleteall, /export, /mode
3. Port burst window handling (5s text, 60s voice)
4. Voice transcription: evaluate whether to port as Go package or delegate to external service
5. Test each command against Auraken behavior

**Acceptance:** All Auraken Telegram commands work in Intercom. Burst windows enforced.

### Task 3.7: Implement and test rollback procedure
**Bead:** benl.10
**Files:** `apps/Intercom/go/cmd/rollback-auraken/main.go`
**Steps:**
1. Design rollback procedure: re-route transport traffic to Auraken, re-enable Auraken write mode, replay Intercom-only preference data back to Auraken
2. Implement rollback script with dry-run mode
3. Test rollback: migrate a test user, write new data in Intercom, rollback, verify Auraken has all data
4. Document rollback trigger criteria and runbook

**Acceptance:** Rollback tested end-to-end. Runbook documented. Dry-run mode available.

### Task 3.8: Set up shadow-mode monitoring and regression measurement
**Bead:** benl.10
**Files:** `apps/Intercom/go/internal/monitoring/`
**Steps:**
1. Implement shadow-mode comparison: both Auraken and Skaffen-Auraken process the same messages, outputs compared
2. Define regression metrics:
   - Lens selection top-3 agreement rate (target: >99%)
   - Response quality score (automated: response length, format adherence; manual: weekly 10-conversation sample)
   - Preference extraction delta agreement rate
3. Implement daily comparison job: sample 10 conversations, run through both systems, log agreement rates
4. Set up alerting: if agreement drops below 99% for 3 consecutive days, trigger review
5. Dashboard: daily agreement rates visible

**Acceptance:** Shadow-mode comparison running. Daily metrics logged. Alert threshold configured.

### Phase 3 → 4 Gate
- [ ] Signal transport operational in Intercom
- [ ] Telegram commands fully migrated
- [ ] All users migrated (reconciliation passes)
- [ ] Single-writer-per-user routing enforced
- [ ] 30 days Skaffen-only operation with regression metrics: lens selection agreement >99%, preference extraction agreement >95%, on daily 10-conversation sample measured by shadow-mode comparison (Task 3.8)

---

## Phase 4: Decommission

### Task 4.1: Freeze Auraken and enter cold standby
**Bead:** benl.11
**Files:** `apps/Auraken/docker-compose.yml`
**Steps:**
1. Verify all Phase 3 gate criteria pass
2. Set Auraken to read-only mode (disable write endpoints)
3. Route all transport traffic to Intercom
4. Document rollback triggers: >1% behavior regression, data integrity failure, transport outage >1hr
5. Keep Auraken container running in read-only mode for 90 days
6. Monitor for rollback triggers weekly

**Acceptance:** Auraken in read-only cold standby. Rollback triggers documented. Monitoring active.

### Task 4.2: Final decommission
**Bead:** benl.11
**Files:** `apps/Auraken/`
**Steps:**
1. Verify 90-day standby period complete with no rollback triggers
2. Final reconciliation checksums
3. Get explicit builder confirmation
4. Archive Auraken database (pg_dump)
5. Stop Auraken container
6. Mark bead as closed

**Acceptance:** Auraken stopped. Database archived. Epic closed.

---

## Dependency Graph

```
Task 0.1 (baseline) ──────────────────────────────────────┐
Task 0.2 (invariants) ──┐                                 │
Task 0.3 (idiom map) ───┤                                 │
                         │                                 │
Task 1.1 (scaffold) ─────┤                                 │
                         ├── Task 1.2 (lens) ──────────┐   │
                         ├── Task 1.3 (fingerprint) ───┤   │
                         ├── Task 1.4 (extraction) ────┤   │
                         └── Task 1.5 (profilegen) ────┤   │
                                                       │   │
Task 1.6 (integration) ───────────────────────────────-┘   │
         │                                                 │
    [Phase 1→2 Gate]                                       │
         │                                                 │
    Chain A (sequential):            Chain B (parallel):   │
    2.1a (interface) ──┐             2.5 (inspector) ──┐   │
    2.1b (cache/budget)┤             2.6 (/analysis) ──┘   │
    2.2a (core provs) ─┤                                   │
    2.2b (aux provs) ──┤                                   │
    2.3 (persona TOML) ┤                                   │
    2.4 (voicing) ─────┘                                   │
         │                                                 │
    [Phase 2→3 Gate]                                       │
         │                                                 │
Task 3.1 (transport iface) ──┬── Task 3.4 (Signal) ───┐   │
Task 3.2 (identity schema) ──┤                         │   │
Task 3.3 (migration script) ─┤                         │   │
Task 3.5 (routing table) ────┤                         │   │
Task 3.6 (Telegram cmds) ────┤                         │   │
Task 3.7 (rollback) ─────────┤                         │   │
Task 3.8 (monitoring) ───────┘                         │   │
         │                                              │   │
    [Phase 3→4 Gate: 30 days shadow-mode]               │   │
         │                                              │   │
Task 4.1 (cold standby) ────── Task 4.2 (decommission) │   │
                                                        │   │
    [Phase 4 done: 90 days] ────────────────────────────┘───┘
```

## Session Estimates

| Phase | Tasks | Parallel? | Sessions |
|-------|-------|-----------|----------|
| Phase 0 | 3 | Yes (0.1 ∥ 0.2 ∥ 0.3) | 1-2 |
| Phase 1 | 6 | Yes (1.2 ∥ 1.3 ∥ 1.4 ∥ 1.5) | 2-4 |
| Phase 2 | 8 | Two parallel chains (A: 2.1a→2.4, B: 2.5→2.6) | 5-7 |
| Phase 3 | 8 | Partial (3.1+3.2 before 3.4+3.6; 3.7+3.8 parallel) | 5-7 |
| Phase 4 | 2 | Sequential (30+90 day waits) | 1 |
| **Total** | **27** | | **16-22 sessions** |

Note: Phase 4 has calendar-time dependencies (30-day operation, 90-day standby) that span months regardless of session count.
