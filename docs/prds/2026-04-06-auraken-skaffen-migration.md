---
artifact_type: prd
bead: sylveste-benl
stage: design
---

# PRD: Auraken to Skaffen Intelligence Layer Migration

## Problem

Auraken runs as a standalone Python process with its own transport layer, database, and intelligence pipeline. This isolates its capabilities (lens selection, style fingerprinting, preference extraction, profile generation) from the rest of the Sylveste ecosystem, preventing other Skaffen agents from using them.

## Solution

Decompose Auraken into reusable Go packages, a Skaffen persona configuration, and Intercom transport adapters. End state: "Auraken" is a personality config in Skaffen, not a Python process. Intelligence capabilities become ecosystem-wide Go libraries.

## Features

### F1: Extract lens library to Go package (benl.1, P0, Phase 1)
**What:** Redesign the 291-lens + 1779-edge graph as `pkg/lens` with a `Selector` interface.
**Acceptance criteria:**
- [ ] `Selector.Select(message, history) -> []Lens` returns top-N lenses
- [ ] Graph traversal, community detection, and bridge scoring work on the embedded JSON data
- [ ] Property-based parity tests: identical inputs through Python and Go produce identical top-3 selections
- [ ] Relational invariant spec written and validated (edge weights, community membership, sort stability)
- [ ] JSON is canonical source via Go `embed`; Go structs are derived
- [ ] Zero imports from sibling packages (fingerprint, extraction, profilegen)

### F2: Port style fingerprinting to Go (benl.2, P0, Phase 1)
**What:** Redesign per-mode EMA style observation as `pkg/fingerprint` producing `StyleProfile` structs.
**Acceptance criteria:**
- [ ] Observes: word count, contractions, laughter, emoji, punctuation, caps, hedging
- [ ] Mode classification: emotional, analytical, playful, intimate, logistics, update, general
- [ ] Per-mode EMA profiles with configurable alpha and cold-start handling
- [ ] Register detection (casual/formal/voice-dominant)
- [ ] No DB dependency — callers persist StyleProfile
- [ ] EMA floating-point parity tests vs Python implementation

### F3: Port preference extraction to Go (benl.4, P1, Phase 1)
**What:** Redesign SPO triple extraction as `pkg/extraction` with an `Extractor` interface.
**Acceptance criteria:**
- [ ] `Extractor.Extract(message, existingEntities) -> []Delta` with ADD/UPDATE/EXPIRE/NOOP actions
- [ ] Burst deduplication (3-second window for rapid messages)
- [ ] Contradiction handling: stated values + revealed behavior as "submerged" origin
- [ ] All LLM-calling functions take `ctx context.Context` as first parameter (enables cancellation and timeout)
- [ ] Haiku calls routed through Skaffen's provider abstraction (not direct API)
- [ ] Domains: goals, constraints, values, priorities, patterns, decisions, skills, relationships
- [ ] No import of sibling packages

### F4: Port profile generation to Go (benl.5, P1, Phase 1)
**What:** Redesign profile narrative generation as `pkg/profilegen` — pure function: entities in, narrative out.
**Acceptance criteria:**
- [ ] Generates 300-500 token narrative from preference entities + conversation
- [ ] Covers: core goals, constraints, values, thinking patterns, contradictions
- [ ] All LLM-calling functions take `ctx context.Context` as first parameter
- [ ] Haiku/Sonnet calls via provider abstraction
- [ ] Idempotent: same entities produce same narrative (modulo LLM variance)

### F5: Port OODARC prompt builder to Go (benl.3, P1, Phase 2)
**What:** Implement Auraken's 8-section dynamic system prompt as Skaffen context provider hooks.
**Acceptance criteria:**
- [ ] Template variables: `{{.LensContext}}`, `{{.ProfileContext}}`, `{{.StyleContext}}`, `{{.SteeringContext}}`, `{{.FeedbackContext}}`, `{{.SessionContext}}`
- [ ] Each section populated by a pre-turn hook calling the corresponding pkg/ library
- [ ] Token budget per section with overflow strategy (truncate oldest context first)
- [ ] Context providers compose their outputs (not concatenate)
- [ ] Async pre-turn hooks with caching. Cache key per provider: lens = hash(message + last 3 turns); fingerprint = hash(message text); profile = entity count + latest entity timestamp. Invalidate on cache key change only.

### F6: Define Auraken as Skaffen agent configuration (benl.8, P1, Phase 2)
**What:** Create persona TOML config that captures conditions for emergence, not the personality itself.
**Acceptance criteria:**
- [ ] TOML config with: base personality, anti-patterns, register matching rules, adaptive depth thresholds
- [ ] Context provider hook registration (which pkg/ libraries to call, in what order)
- [ ] Calibration parameters tunable post-integration
- [ ] Validated against Auraken's prompts.py section-by-section
- [ ] Post-integration voicing/calibration phase produces behavior-parity vs Auraken baseline

### F7: Analysis mode — Westworld debugging (benl.9, P1, Phase 2)
**What:** Live in-band and post-hoc inspection of agent cognition.
**Acceptance criteria:**
- [ ] `/analysis` command pauses normal flow with session state snapshot/restore
- [ ] Inspector package: read-only access to lens selection reasoning, fingerprint state, preference deltas
- [ ] Post-hoc replay: separate session targeting conversation history, turn replay with modified context
- [ ] Builder identity gating via config (not transport ID)
- [ ] Copy-on-write for parameter experiments (never persists to live config)
- [ ] Analysis evidence tagged with `evidence_type=analysis` in evidence JSONL; preference extraction and profilegen pipelines filter out `evidence_type=analysis` records to prevent debug interactions from polluting real user profiles

### F8: Design transport interface abstraction (sylveste-2nfd, P0, Phase 3)
**What:** Extract Intercom's hardcoded Telegram into a Transport interface before adding Signal.
**Acceptance criteria:**
- [ ] `Transport` interface: `Run(ctx) error`, `Name() string`
- [ ] `Messenger` interface: `SendText`, `SendTyping`, media support
- [ ] `IncomingMessage` struct with normalized ChatID (`tg:`, `signal:` prefixes)
- [ ] Telegram refactored to implement both interfaces
- [ ] Main.go wires handlers generically (no transport-specific code in main)
- [ ] Namespace registry for ChatID prefixes with collision prevention

### F9: Add Signal transport to Intercom (benl.6, P0, Phase 3)
**What:** Implement Signal as a Transport adapter in Intercom, replacing Auraken's Signal integration.
**Acceptance criteria:**
- [ ] WebSocket listener to signal-cli-rest-api (json-rpc mode)
- [ ] Signal-specific: sealed sender messages extract sender from signal-cli-rest-api envelope field; if envelope lacks sender (true sealed sender), route to unknown-sender handler with degraded response (no profile context). Document signal-cli-rest-api version requirement for envelope sender exposure.
- [ ] Linked device normalization: multiple devices for same phone number resolve to single user_id
- [ ] Parallel-run capability: Signal on both Auraken and Intercom simultaneously for validation
- [ ] Cutover validation checklist with measurable criteria
- [ ] Hot-standby fallback to Auraken Signal transport during transition

### F10: Migrate Telegram transport (benl.7, P1, Phase 3)
**What:** Move Telegram handling from Auraken to Intercom (already partially there in Go rewrite).
**Acceptance criteria:**
- [ ] All Auraken Telegram commands available in Intercom: /start, /new, /profile, /forget, /deleteall, /export, /mode, /help
- [ ] Voice transcription (Deepgram + Whisper fallback) ported or delegated
- [ ] Burst window handling (5s text, 60s voice)

### F11: Shared user identity + profile database (benl.10, P0, Phase 3)
**What:** Transport-agnostic identity model in Intercom's Postgres with migrated Auraken data.
**Acceptance criteria:**
- [ ] `users` table with `user_id UUID PRIMARY KEY` (transport-agnostic)
- [ ] `transport_identities` join table: `(user_id, transport, transport_id)`
- [ ] All migrated records carry `source_system`, `migrated_at`, `original_id` provenance
- [ ] Bi-temporal fields: UTC normalization, microsecond precision
- [ ] Dry-run identity crosswalk with diff report before data moves
- [ ] Migration order: entities/episodes first, regenerate working_profiles as validation
- [ ] Reconciliation script: row counts + content checksums
- [ ] Single-writer-per-user during concurrent operation (routing table)
- [ ] pgvector evaluated; deferred if unavailable (recomputable from entities)

### F12: Decommission Auraken Python runtime (benl.11, P2, Phase 4)
**What:** Shut down the Python process after all capabilities are running in Go.
**Acceptance criteria:**
- [ ] 30 days Skaffen-only operation with <1% behavior regression vs baseline
- [ ] All users migrated (zero remaining on Auraken transports)
- [ ] Reconciliation checksums pass for all data tables
- [ ] Auraken enters read-only cold standby for 90 days
- [ ] Explicit rollback trigger criteria documented
- [ ] Final confirmation from builder before deletion

## Phase Boundary Gates

| Transition | Gate Criteria |
|-----------|--------------|
| Phase 1 → 2 | All 4 packages pass integration-pattern tests. Lens graph parity tests pass. Each package reviewed for Go idiom compliance. |
| Phase 2 → 3 | Skaffen-Auraken agent produces behavior-parity responses in shadow mode. Voicing/calibration session completed. |
| Phase 3 → 4 | 30 days Skaffen-only with <1% regression. All users migrated. Reconciliation checksums pass. |
| Phase 4 done | 90-day cold standby complete. No rollback triggers fired. |

## Non-goals

- **WhatsApp/Discord/web transports** — Transport interface enables these but they're out of scope.
- **New lens capabilities** — Port existing 291 lenses; don't design new ones during migration.
- **Multi-user profiles** — Identity model supports it structurally but shared profiles are not in scope.
- **Performance optimization** — Correctness and parity first. Optimize after migration.

## Dependencies

- Intercom Go rewrite (apps/Intercom/go/) must be operational for Phase 3
- signal-cli-rest-api must be deployed for Signal transport
- Skaffen's persona config system must support TOML + context provider hooks (may need extension)
- Intercom's Postgres must support pgvector extension (or defer embeddings)

## Cross-Cutting Concerns

- **Haiku routing:** All LLM calls from pkg/ libraries go through Skaffen's provider abstraction for budget tracking, rate limiting, and evidence emission.
- **Python-to-Go idiom audit:** Each Python pattern documented with its Go-native equivalent before coding. Go expert review on each package.
- **Evidence chain:** Every migrated entity retains extraction context (message, model, prompt version) via provenance columns.
- **Behavioral baseline:** Capture Auraken's current behavior as test fixtures before any migration begins.
