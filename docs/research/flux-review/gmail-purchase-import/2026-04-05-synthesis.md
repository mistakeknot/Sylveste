---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-04-05-gmail-purchase-import-brainstorm.md"
target_description: "Gmail purchase import pipeline — Auraken email parsing + context extraction, interjawn MCP for product data, jawncloud as data layer"
tracks: 4
track_a_agents: [fd-gmail-oauth-token-lifecycle, fd-email-parsing-robustness, fd-mcp-idempotency-contracts, fd-jawncloud-data-integrity, fd-personal-data-pipeline-privacy]
track_b_agents: [fd-forensic-accounting-document-reconstruction, fd-health-information-management, fd-insurance-underwriting, fd-data-journalism-source-verification]
track_c_agents: [fd-venetian-glassblowing-batch-kiln, fd-japanese-katagami-stencil-pattern-matching, fd-hanseatic-kontor-trade-ledger-privacy, fd-polynesian-wayfinding-dead-reckoning-context]
track_d_agents: [fd-babylonian-extispicy-zone-parsing, fd-angkorian-baray-hydraulic-governance, fd-akan-goldweight-fuzzy-metrology]
date: 2026-04-05
total_findings: 65
p0_count: 8
p1_count: 24
p2_count: 23
p3_count: 10
---

# Cross-Track Synthesis — Gmail Purchase Import Pipeline

65 findings across 16 agents in 4 tracks. 8 P0, 24 P1, 23 P2, 10 P3.

## Critical Findings (P0/P1)

### P0-1: `add_wardrobe` has no `private` parameter — privacy contract unimplementable
**Agents:** fd-mcp-idempotency-contracts (A3-1), fd-jawncloud-data-integrity (A4-1)
**Tracks:** A (confirmed against actual MCP schema)
**Fix:** Add `private` boolean to interjawn's `add_wardrobe` schema, or enforce `private BOOLEAN NOT NULL DEFAULT true` at jawncloud DB level. This is a **blocking prerequisite** — the brainstorm's core promise ("private by default") cannot be fulfilled without it.

### P0-2: `add_wardrobe` requires `size` — non-apparel items will fail
**Agent:** fd-mcp-idempotency-contracts (A3-2)
**Tracks:** A
**Fix:** Make `size` optional in interjawn's `add_wardrobe` schema with default `"OS"` (one-size). Electronics, books, games, and apps have no size concept.

### P0-3: No sender authentication — spoofed emails inject data into jawncloud
**Agent:** fd-email-parsing-robustness (A2-1), fd-data-journalism-source-verification (B4.4)
**Tracks:** A, B
**Fix:** Check `Authentication-Results` header for DKIM pass before parsing any email body. One header check per message.

### P0-4: Refresh token stored in plaintext (unspecified)
**Agent:** fd-gmail-oauth-token-lifecycle (A1-1)
**Tracks:** A
**Fix:** Encrypt refresh tokens at rest (Fernet + rotatable secret, stored as BYTEA).

### P0-5: No delete-my-data flow
**Agent:** fd-personal-data-pipeline-privacy (A5-1)
**Tracks:** A, B (health info consent), C (Hanseatic charter)
**Fix:** Specify the cascade: revoke OAuth → delete token → delete wardrobe rows → purge Auraken context → confirm to user.

### P0-6: Gmail query scope has no circuit breaker
**Agent:** fd-hanseatic-kontor-trade-ledger-privacy (C3-1)
**Tracks:** C
**Fix:** Assert every fetched message matches sender allowlist *before reading body*. Discard non-matching messages without parsing.

### P0-7: Price zone inversion on HTML template change
**Agent:** fd-babylonian-extispicy-zone-parsing (D-1)
**Tracks:** D
**Fix:** Post-parse invariant: if single-item order, `item_price ≈ order_total ± shipping`. Quarantine failed invariant checks.

### P0-8: No backpressure between parse and interjawn MCP
**Agent:** fd-angkorian-baray-hydraulic-governance (D-4)
**Tracks:** D
**Fix:** Bounded asyncio queue with configurable worker pool (default 3) between parse output and MCP upsert calls.

## Cross-Track Convergence

### Convergence 1: Missing validation layer between parse output and committed records (4/4 tracks)

Every track independently identified the same structural gap — the pipeline has no validation/reconciliation step between raw parser output and the MCP upsert call.

- **Track A** (fd-mcp-idempotency-contracts): "No MCP error propagation strategy for partial batch failures" — malformed parse output hits interjawn without pre-validation
- **Track B** (all 4 agents): Forensic accounting calls it "gap entries," health info calls it "completeness check," underwriting calls it "construct validation," data journalism calls it "source verification." All four named the same missing step independently.
- **Track C** (fd-venetian-glassblowing): "No phase-gate between HTML parse and brand matching — malformed parse propagates into jawncloud"
- **Track D** (fd-babylonian-extispicy): "Absent-zone detection" — missing fields conflated with zero-value fields; and zone manifest with required/optional flags and value ranges

**Convergence score: 4/4.** This is the highest-confidence finding in the review. The pipeline needs a `ParseResult.is_valid()` gate with per-field presence tracking, range validation, and a quarantine path for invalid records.

### Convergence 2: Silent parse failures / template drift detection (4/4 tracks)

All four tracks flagged that parser breakage is invisible until users notice wrong data.

- **Track A** (fd-email-parsing-robustness): Plain-text MIME fallback gap, no structured error handling
- **Track B** (fd-forensic-accounting + fd-data-journalism): Parse failures silently dropped with no failure record; template drift causes silent partial parse success
- **Track C** (fd-japanese-katagami): Single-strategy DOM extraction with no fallback; negative space undefined
- **Track D** (fd-babylonian-extispicy): Template mutation detection absent; structural fingerprinting recommended

**Convergence score: 4/4.** Add: (1) two-layer extraction (CSS selector primary, regex fallback), (2) structural fingerprinting to detect template mutation, (3) per-email parse outcome logging (success/partial/failed).

### Convergence 3: Brand matching needs precedent memory and audit trail (4/4 tracks)

- **Track A** (fd-jawncloud-data-integrity): Brand normalization fallback undefined; inconsistent slug generation creates duplicates
- **Track B** (fd-forensic-accounting): Normalization decisions silent and irreversible; no audit table
- **Track C** (fd-japanese-katagami): Fuzzy match threshold uncalibrated; no test corpus
- **Track D** (fd-akan-goldweight): No sankofa — same ambiguity re-adjudicated from scratch each run; ambiguous matches need user arbitration

**Convergence score: 4/4.** Add: (1) `brand_match_precedents` table recording `{raw_string, resolved_brand_id, confidence, method}`, (2) user arbitration for low-confidence matches, (3) calibration test corpus for threshold tuning.

### Convergence 4: No checkpoint/resume for large imports (3/4 tracks)

- **Track A** (fd-mcp-idempotency-contracts): Per-email processing record needed for crash recovery
- **Track C** (fd-venetian-glassblowing + fd-hanseatic-kontor): Checkpoint watermark + per-email audit log (solves both)
- **Track D** (fd-angkorian-baray): Non-resumable batch forces full re-process; water-level markers needed

**Convergence score: 3/4.** Add: `last_processed_gmail_message_id` checkpoint table, written per batch of N emails.

### Convergence 5: OAuth revocation doesn't delete data (3/4 tracks)

- **Track A** (fd-personal-data-pipeline-privacy + fd-gmail-oauth-token-lifecycle): No disconnect flow; no cascade delete
- **Track B** (fd-health-information-management): Consent-to-access vs consent-to-store gap undisclosed
- **Track C** (fd-hanseatic-kontor): Revocation incompleteness undisclosed; data persists after charter ends

**Convergence score: 3/4.** Must disclose persistence at consent time + provide explicit delete action.

### Convergence 6: Temporal weighting absent — old purchases dominate model (3/4 tracks)

- **Track B** (fd-insurance-underwriting): Sparse history constructs carry no confidence signal
- **Track C** (fd-venetian-glassblowing + fd-polynesian-wayfinding): Bulk context injection without temporal decay; 2016 purchase equals 2026 purchase
- **Track D** (implicit in brand normalization drift)

**Convergence score: 3/4.** Apply exponential decay at context-write time (half-life ~18 months, configurable).

## Domain-Expert Insights (Track A)

The most consequential Track A finding was **grounding the brainstorm against the actual interjawn MCP schema**, which revealed that two of the brainstorm's core assumptions are wrong:
1. `add_wardrobe` has no `private` parameter (P0)
2. `add_wardrobe` requires `size` as mandatory (P1)

Other high-value domain findings:
- `invalid_grant` recovery flow missing — user sees "0 purchases" instead of re-auth prompt (A1-2)
- Book ISBNs stored as ASINs won't match `B0`-prefixed regex — Kindle is in MVP scope (A2-3)
- GDPR Article 5(1)(c) tension with "full history, no date cap" (A5-2)
- Error logging may leak purchase data to Sentry (A5-5)

## Parallel-Discipline Insights (Track B)

Track B's strongest contribution was **naming the missing validation layer from 4 independent professional traditions**. Each discipline has a standard practice for the step between raw intake and committed records:

| Discipline | Name for missing step | Key addition |
|---|---|---|
| Forensic accounting | Reconciliation | Per-email gap entries, normalization audit log |
| Health info management | Completeness check | Per-parser statistics, parser version per record |
| Insurance underwriting | Construct validation | Confidence tiers on derived signals (low/medium/high) |
| Data journalism | Source verification | Canonical output schema with semantic contracts per field |

The underwriting agent's **gift contamination** finding (B3.1) is immediately actionable: Amazon HTML contains `is_gift` flag and shipping-address-matches-billing check — extractable in MVP at parser level, costs nothing to add.

The data journalism agent's **cross-parser semantic schema** finding (B4.1) is architecturally load-bearing: "price" from App Store and Amazon are semantically incompatible (unit cost vs. total with tax). Without a canonical schema, cross-retailer aggregation is meaningless.

## Structural Insights (Track C)

Track C's Venetian glassblowing analogy mapped the pipeline's phases to furnace stages with precision — the "annealing" insight (bulk context injection risks thermal shock to the preference model) is the same finding as Track B's "sparse history over-confidence" but framed as a phase-transition problem rather than a statistical one.

The Hanseatic Kontor's **sensitivity tiers** finding (C3-4) opens a new design direction: not all imported data carries equal exposure risk. Raw purchases > derived affinities > spending patterns in sensitivity. A flat `private` flag conflates these. Separating at the schema level before first write prevents future sharing features from accidentally crossing tiers.

The Polynesian wayfinding agent's **staleness detection** (C4-3) is low-cost and high-value: a single `context_last_updated` field + staleness threshold suppresses stale recommendations. No model evaluation framework needed.

## Frontier Patterns (Track D)

The Babylonian extispicy agent produced the most **structurally precise** finding: zone inversion. The bārū's insight that adjacent liver zones produce *opposite* omens maps exactly to the HTML parsing problem — a price selector resolving to shipping cost isn't "a little wrong," it's categorically inverted. The recommended cross-check (item_price ≈ order_total ± shipping for single-item orders) is elegant and cheap.

The Akan goldweight agent's **sankofa** mechanism is genuinely novel for this domain: recording brand-matching precedents so the same ambiguity isn't re-adjudicated from scratch each run. This converts a stateless fuzzy matcher into a learning system — a single DB table, but the implications for brand-affinity stability over time are significant.

The Angkorian baray agent named the backpressure gap that no other track caught as directly: the pipeline has rate-limiting on the Gmail API side but none on the interjawn MCP side. A bounded asyncio queue is the minimal sluice gate.

## Synthesis Assessment

**Overall quality:** The brainstorm makes the right architectural call (Auraken owns pipeline, jawncloud is data layer) and correctly identifies Gmail API as the integration point. But it treats the pipeline as a simple fetch-parse-write linear flow without addressing the validation, error handling, checkpointing, privacy enforcement, and schema compatibility gaps that arise when the pipeline processes real data at scale.

**Highest-leverage improvement:** Add a **ParseResult validation gate** between parser output and MCP upsert — with per-field presence tracking, range validation, and quarantine path. This single addition addresses the most convergent finding (4/4 tracks) and catches price inversions, missing fields, template drift artifacts, and malformed records before they contaminate jawncloud and the preference model.

**Surprising finding:** The `add_wardrobe` MCP schema doesn't support the brainstorm's `private` parameter (P0, Track A). This wasn't a brainstorm quality issue — it was an assumption about the downstream API that turned out to be wrong. This is exactly the kind of finding that justifies grounding reviews against actual code, not just document text.

**Semantic distance value:** The outer tracks (C/D) contributed qualitatively different insights from the inner tracks (A/B). Track A caught schema mismatches and domain-specific protocol gaps. Track B named the missing validation layer from 4 professional traditions. Track C identified the checkpoint/resume gap through physical analogies (furnace phases, water-level markers) and the sensitivity-tier design direction. Track D produced the most surprising specific mechanisms — zone inversion cross-checks from Babylonian divination, sankofa precedent memory from Akan trade, and backpressure buffering from Khmer hydraulics. Each tier unlocked findings invisible from within the previous tier's frame.
