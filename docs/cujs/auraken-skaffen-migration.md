---
artifact_type: cuj
journey: auraken-skaffen-migration
actor: builder (migrating Auraken intelligence layer to Skaffen ecosystem)
criticality: p0
bead: sylveste-benl
---

# Auraken to Skaffen Migration

**Last updated:** 2026-04-08
**Status:** Living document — regenerate with `/interpath:cuj`
**Companion CUJs:** [Skaffen Sovereign Session](skaffen-sovereign-session.md), [Intercom Telegram Assistant](intercom-telegram-assistant.md)

## Why This Journey Matters

Auraken is the cognitive augmentation agent — 291 lenses, style fingerprinting, preference extraction, profile generation — running as a standalone Python process. Its intelligence capabilities are locked inside a single runtime. No other Skaffen agent can select lenses, observe style, or build user profiles. The migration dissolves Auraken into the ecosystem: Go packages that any agent can use, a persona configuration that makes "Auraken" a personality rather than a process, and transport handling that lives where it belongs (Intercom).

The stakes are high because Auraken has live users with accumulated profiles. Preference entities are bi-temporal and immutable — they represent months of conversation evidence. Losing them is losing the user's cognitive history. Getting the migration wrong means either data loss (profiles corrupted, preferences misordered) or personality regression (the Go agent responds like a generic assistant instead of the lens-wielding PM that users know). Both failures are visible immediately and erode trust that took months to build.

## The Journey

The builder starts by capturing what Auraken actually does. Before touching any Go code, they run 35 test messages through the Python system — 5 per conversation mode, covering all 7 lens communities — and record golden outputs: which lenses were selected and why, how style fingerprints shifted, what preference triples were extracted, what narrative profiles were generated. These fixtures become the reference island. Every Go package will be validated against them.

Phase 1 is the intellectual core. The builder creates four Go packages under `os/Skaffen/pkg/`: lens (graph traversal, community detection, Haiku-based selection), fingerprint (EMA style observation per conversation mode), extraction (SPO triple extraction with burst dedup and contradiction handling), and profilegen (narrative generation from accumulated entities). Each package stands alone — zero imports from siblings, no database dependency, `context.Context` on every LLM-calling function. The packages are designed for the ecosystem, not for Auraken specifically. The lens `Selector` interface accepts any lens set; the `Extractor` interface works with any entity store. When parity tests pass — deterministic components produce identical results, Haiku-dependent components match against recorded responses — Phase 1 is complete.

Phase 2 wires the packages into Skaffen. The builder implements a `ContextProvider` interface that replaces Skaffen's static system prompt with a dynamic pipeline. Six providers (Lens, Profile, Style, Steering, Feedback, Session) populate template variables in the persona config, each with its own cache key and token budget. The Auraken persona becomes a TOML file: personality rules, anti-patterns, register matching, calibration parameters. It defines conditions for emergence — not the personality itself. The builder then runs a voicing session: 10 conversations through the Skaffen-Auraken agent, comparing against Python baseline, adjusting calibration parameters until the responses feel right. In parallel, the Inspector package and `/analysis` command give the builder Westworld-style debugging — pause a live conversation, inspect why a lens was chosen, replay a turn with different context, all without altering the agent's state.

Phase 3 moves transport and data. The builder first extracts Intercom's hardcoded Telegram into a Transport interface — `Run(ctx)`, `Name()`, `SendText()`, `SendTyping()` — then implements Signal as a second adapter (WebSocket to signal-cli-rest-api). The identity schema lands in Intercom's Postgres: `user_id UUID PRIMARY KEY` (transport-agnostic) with a `transport_identities` join table. The migration script runs dry first, producing a diff report of the identity crosswalk (collisions, orphans, clean mappings). Then it migrates in order: entities and episodes first (immutable source data), regenerate working profiles as validation (compare regenerated vs migrated — significant divergence flags data integrity issues), then style fingerprints and lens usage. During the concurrent operation period, a routing table enforces single-writer-per-user — each user is owned by exactly one system for preference writes.

Phase 4 is the long goodbye. Shadow-mode monitoring runs daily: 10 conversations processed by both systems, agreement rates tracked (lens selection >99%, preference extraction >95%). After 30 days of Skaffen-only operation with metrics holding, Auraken enters read-only cold standby. After 90 days with no rollback triggers, the Python runtime is archived and decommissioned. The builder confirms explicitly before deletion.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Lens parity | measurable | Go `Selector.Select()` with recorded Haiku responses returns identical top-3 for all 35 fixtures |
| Fingerprint parity | measurable | Go EMA values within float64 epsilon of Python for all fixtures |
| Extraction parity | measurable | Go `Extractor.Extract()` produces identical Delta actions for fixture messages |
| Profile generation | measurable | Generated narratives cover required topics, 300-500 token range |
| Package isolation | measurable | `go vet ./pkg/...` clean, zero cross-package imports |
| Persona behavior | qualitative | Skaffen-Auraken responses indistinguishable from Python Auraken in voicing session |
| Identity crosswalk | measurable | Dry-run produces zero collisions, zero orphans |
| Migration checksums | measurable | Row counts + content checksums match between Auraken source and Intercom target for all migrated tables |
| Bi-temporal precision | measurable | `valid_from`/`valid_until` timestamps preserved with microsecond precision and UTC normalization |
| Transport interface | observable | Telegram works identically through new Transport interface (no user-visible change) |
| Signal transport | observable | Signal messages received and responded to through Intercom |
| Shadow agreement | measurable | Lens selection agreement >99%, preference extraction >95% over 30-day monitoring |
| Analysis isolation | measurable | Evidence records with `evidence_type=analysis` excluded from preference extraction pipeline |
| Decommission safety | observable | Zero traffic to Auraken endpoints for 90 consecutive days |

## Known Friction Points

- **LLM non-determinism in parity tests.** Haiku responses vary between calls even with temperature=0. Parity tests must use recorded responses for deterministic components and tolerate variance for LLM-dependent components. (Addressed in Task 0.1 and Task 1.2 acceptance criteria.)
- **Style fingerprint as JSONB in core_profiles.** Auraken stores style fingerprint as a JSONB column inside `core_profiles`, not as a separate table. The migration must extract it correctly. The brainstorm originally described a separate `style_fingerprints` table — the plan corrected this.
- **`valid_until` not `valid_to`.** Auraken's actual column name is `valid_until` and there is no `expired_at` column. Early brainstorm drafts used wrong names. Corrected in plan review.
- **Lens usage cold-start.** If `lens_usage` table is not migrated, the adaptive evolution system resets — every lens starts at baseline effectiveness. Migration plan includes lens_usage; if deferred, a cold-start strategy must be documented.
- **pgvector availability.** Intercom's Postgres may not have pgvector installed. Profile embeddings are deferred if unavailable — they're derived data, recomputable from entities.
- **Calendar-time gates.** Phase 3→4 requires 30 days of operation; Phase 4 requires 90 days of cold standby. These are production observation periods, not agent sessions. The total migration spans months.
- **Persona emergence vs decomposition.** The Noh *hana* risk: decomposing Auraken's personality into TOML rules may produce kata (form) without hana (flower). The voicing/calibration phase (Task 2.4) is the mitigation — but it requires the builder's qualitative judgment, not just automated metrics.
