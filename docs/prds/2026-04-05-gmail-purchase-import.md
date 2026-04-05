---
artifact_type: prd
bead: sylveste-fbz
stage: design
---

# PRD: Gmail Purchase Import Pipeline

## Problem

Auraken builds deep personal context but has no access to purchase history — one of the strongest signals for taste, brand affinity, and spending patterns. Users currently add items one-at-a-time via `/add-jawn`, which doesn't scale.

## Solution

Import purchase history from Gmail (read-only OAuth) to bootstrap the user's product catalog in jawncloud and build purchase-pattern context in Auraken. Auraken owns the pipeline; jawncloud is the data layer via interjawn MCP. MVP covers Amazon + digital receipts (App Store, Steam, Kindle). All imports are private by default.

## Features

### F1: Gmail OAuth + Token Management
**What:** Implement OAuth consent flow with `gmail.readonly` scope, encrypted token storage, and lifecycle management.
**Acceptance criteria:**
- [ ] OAuth consent screen grants `gmail.readonly` with clear disclosure of data categories extracted
- [ ] Refresh token encrypted at rest (Fernet + rotatable secret, stored as BYTEA)
- [ ] `invalid_grant` triggers re-consent prompt (not silent zero-result)
- [ ] Token revocation calls Google's revoke endpoint and deletes local row
- [ ] Consent text covers: what emails scanned, what extracted, where stored, retention, deletion path

### F2: interjawn Schema Prerequisites
**What:** Extend interjawn's `add_wardrobe` MCP tool to support privacy and non-apparel items.
**Acceptance criteria:**
- [ ] `add_wardrobe` accepts optional `private` boolean (default `true`)
- [ ] `add_wardrobe` accepts optional `size` (default `"OS"`)
- [ ] `retail_price` maps to `Decimal` in Prisma (not `Float`)
- [ ] Wardrobe unique constraint updated to accommodate optional `size` (verify against existing five-column constraint)
- [ ] `private BOOLEAN NOT NULL DEFAULT true` enforced at DB level
- [ ] Prisma migration file with down-revision anchor; MCP binary rebuilt and deployed after schema change

### F3: Email Parser Framework + Amazon Parser
**What:** Build the parser framework (two-layer extraction, validation gate, authentication) and the first parser (Amazon order confirmations).
**Acceptance criteria:**
- [ ] Pre-parse gate: assert fetched message matches sender allowlist before reading body
- [ ] DKIM validation via `Authentication-Results` header; reject failed auth or absent header
- [ ] `ParseResult` dataclass with per-field presence flags (`zones_present`, `zones_absent`)
- [ ] `ParseResult.is_valid()` gate: non-empty name, parseable price (> 0), valid date, ASIN regex matches `[A-Z0-9]{10}`
- [ ] Two-layer extraction: CSS selector primary, regex fallback. Log parser-degraded warning on fallback
- [ ] Amazon parser extracts: product name, price, ASIN, order-placed date (not email received date), quantity, `is_gift` flag
- [ ] Post-parse invariant: single-item orders check `item_price ≈ order_total ± shipping`
- [ ] Invalid/quarantined records written to `failed_extractions` table with `message_id` and failure reason
- [ ] Subject-line filtering excludes cancellation/return patterns from sender-matched emails

### F4: Digital Receipt Parsers
**What:** Parsers for App Store, Steam, and Kindle following the F3 framework.
**Acceptance criteria:**
- [ ] App Store parser: extracts app name, price (unit cost excl. tax), date from `no_reply@email.apple.com`
- [ ] Steam parser: extracts game name, price, date from `noreply@steampowered.com`
- [ ] Kindle parser: handles digital orders from Amazon sender pattern (differentiated from physical orders)
- [ ] Each parser declares required fields; partial parse (e.g., `price=None`) is a failure, not a success
- [ ] Structural fingerprint per parser for template mutation detection (hash of tag/class skeleton)
- [ ] Canonical output schema enforced: `price` = unit cost in USD excl. tax; `$0.00` for free items

### F5: Brand Matching with Precedent Memory
**What:** Fuzzy brand name normalization against jawncloud's brand catalog with audit trail and learning.
**Acceptance criteria:**
- [ ] `list_brands` called once at pipeline start; brand-to-slug mapping cached
- [ ] Deterministic slug generation (python-slugify with fixed settings)
- [ ] `brand_match_precedents` table: `{raw_string, resolved_brand_id, confidence, method, resolved_at}`
- [ ] Precedent lookup before fuzzy match; `method=user_confirmed` precedents are immutable
- [ ] Matches below 0.95 confidence staged as `pending_brand_match` for user review
- [ ] Two-tier tolerance: high-sensitivity categories (fashion, luxury) require >= 0.97; standard >= 0.85
- [ ] All normalization decisions logged: `{raw_brand, matched_canonical, score, threshold, source_email_id}`
- [ ] Post-import summary includes brand disambiguation queue

### F6: Buffered MCP Upsert Pipeline
**What:** Rate-limited, checkpointed pipeline from parsed results to interjawn MCP + Auraken context DB.
**Acceptance criteria:**
- [ ] Per-user import lock (advisory lock or `import_progress.status=running` check) prevents concurrent imports
- [ ] Bounded asyncio queue between parse output and MCP upsert (single worker — interjawn uses stdio transport, not concurrent-safe)
- [ ] Per-batch checkpoint: `import_progress` table with `{user_id, last_processed_message_id, status, batch_count}`
- [ ] Resume from checkpoint on restart (skip already-processed message IDs via audit log, not message ID ordering)
- [ ] Access token refresh mid-import: re-acquire token every 45 minutes during long-running imports
- [ ] Per-email audit log: `{import_id, message_id, sender, date, subject_hash, parse_outcome, upsert_outcome}`
- [ ] MCP call results tracked per-item; summary distinguishes successes from failures
- [ ] Dual-destination writes decoupled: complete all interjawn upserts, then Auraken context writes
- [ ] `upsert_sku` called before `add_wardrobe` for unknown SKUs (two-call pattern per item)
- [ ] `parser_name` and `parser_version` stored per record
- [ ] Gmail API 429/quota-exceeded handled with exponential backoff

### F7: Context Extraction with Temporal Decay
**What:** Extract purchase-pattern signals for Auraken's preference model with temporal weighting and confidence tiers.
**Acceptance criteria:**
- [ ] Temporal decay at context-write time: half-life ~18 months (configurable)
- [ ] All derived records tagged `source=gmail_import` + `user_id` for cascade deletion
- [ ] Brand affinity stored as `(brand, category, price_tier, purchase_count, last_purchase_date)` tuple
- [ ] `observation_count` and `confidence_tier` (low < 10, medium 10-50, high > 50) per construct
- [ ] `is_gift=true` purchases excluded from brand affinity and taste constructs (still in wardrobe)
- [ ] `context_last_updated` field; staleness threshold (> 6 months) suppresses confidence-dependent recommendations
- [ ] Raw purchase event log preserved as first-class artifact for v2 pattern detection

### F8: Import UX + Deletion Flow
**What:** User-facing trigger, progress reporting, and data lifecycle management.
**Acceptance criteria:**
- [ ] Telegram `/import` command or conversation trigger ("import my purchase history")
- [ ] Post-import summary: per-parser stats (count, date range, failures), zero-price anomaly flags
- [ ] Brand disambiguation queue presented to user for ambiguous matches
- [ ] Category preview step between OAuth and first import (show breakdown before committing)
- [ ] First-time `/import` with no token redirects to OAuth consent flow
- [ ] Delete-my-data flow: cancel in-flight import → revoke OAuth → delete token → delete wardrobe rows → purge context (incl. `brand_match_precedents`, `failed_extractions`, `import_progress`, `purchase_event_log`) → confirm
- [ ] Delete-my-data smoke test: assert zero rows across all 6 tables after deletion for test user
- [ ] Rate limit on `/import` trigger (max 1 concurrent per user, max 3 per day)
- [ ] Consent screen text drafted and reviewable (what scanned, what extracted, where stored, retention period, how to delete)

## Non-goals

- International Amazon domains (amazon.co.uk, amazon.de) — v2 alongside other retailers
- ASIN enrichment via Amazon PA-API or Exa — v2
- Return/refund processing (update `status=RETURNED`) — v2 (cancellations excluded by subject-line filter in v1)
- Full subscription detection — v2 (raw event log preserved for it)
- Cross-user aggregation — never (all data is per-user, private by default)
- Recommendation feedback loop tracking — schema supports it (`recommendation_influenced` field), active tracking is v2

## Dependencies

- **interjawn schema change (F2)** — blocks F3, F4, F5, F6, F8. Must ship first (breaks existing `add_wardrobe` callers if not backward-compatible).
- **F1 (OAuth)** — blocks F3, F4, F6, F8 (pipeline needs tokens to fetch email)
- **F3 (parser framework)** — blocks F4 (digital parsers follow framework), F5 (brand matching needs parse output)
- **F5 (brand matching)** — blocks F6 (upsert needs resolved brand slugs)
- **Google Cloud Console project** — OAuth client ID, consent screen verification for sensitive scopes
- **Auraken DB migrations** — new tables: `gmail_tokens`, `import_progress`, `brand_match_precedents`, `failed_extractions`, `purchase_event_log`. Alembic migration chain with down-revision anchors.
- **Test fixtures** — Gmail API mock/fixture infrastructure for CI (no live API calls in tests). Fixture set: multi-item order, single-item, gift order, digital receipt, cancellation, malformed HTML.

## Delivery Order

```
F2 (interjawn schema) ──┐
                        ├──> F3 (parser framework + Amazon) ──> F4 (digital parsers)
F1 (Gmail OAuth) ───────┘           │
                                    ├──> F5 (brand matching) ──> F6 (buffered upsert) ──> F7 (context extraction)
                                    │
                                    └──> F8 (import UX + deletion) [needs F1, F2, F6]
```

F2 and F1 can be built in parallel. F3 requires both. F4 and F5 follow F3. F6 follows F5. F7 follows F6. F8 integrates everything.

## Data Retention

Default: **3 years** of purchase history retained (per GDPR Art. 5(1)(c) data minimization). Users may opt in to full history at import time. Older records are soft-deleted (excluded from context extraction) but available for user export. Hard deletion on user request via delete-my-data flow.

## Open Questions

- **Google verification timeline**: Sensitive scope (`gmail.readonly`) requires Google review — what's the turnaround for internal/test-only use?
- **Canonical category taxonomy**: Should we define Auraken's category system now, or use retailer pass-through with mapping in v2?
