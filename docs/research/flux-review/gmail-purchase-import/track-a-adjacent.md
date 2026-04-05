---
track: A
track_name: Adjacent
agent_count: 5
date: 2026-04-05
target: docs/brainstorms/2026-04-05-gmail-purchase-import-brainstorm.md
---

# Track A: Adjacent Domain Review — Gmail Purchase Import

## Agent 1: fd-gmail-oauth-token-lifecycle

### A1-1. P0 — Refresh token storage security not specified

The brainstorm mentions `google-auth-oauthlib` for OAuth but says nothing about how the refresh token is persisted. Gmail refresh tokens are long-lived credentials that grant ongoing access to the user's mailbox. If stored as plaintext in Auraken's PostgreSQL (the default behavior of most tutorial code, which serializes credentials to a file or stores the JSON blob in a column), a database compromise exposes full read access to every connected user's Gmail.

**Recommendation:** Add a "Token Storage" section to the brainstorm specifying: (a) refresh tokens encrypted at rest using a KMS-backed key or `Fernet` with a rotatable secret, (b) the Auraken DB schema column is explicitly typed as `BYTEA` (encrypted blob), not `TEXT`, (c) key rotation strategy documented before MVP ships.

### A1-2. P1 — No `invalid_grant` recovery flow described

The brainstorm says "the pipeline is idempotent" and "safe to re-run," but does not address the case where a user revokes Gmail access (via Google Account settings) or the refresh token expires (Google revokes tokens after 6 months of inactivity, or when the user changes their password). When the pipeline encounters `invalid_grant`, it must re-prompt the user for consent rather than silently returning zero results or crashing. Without this, a user who triggers "import my purchase history" after revoking access will see "Found 0 purchases" with no indication that re-authorization is needed.

**Recommendation:** Add to the Data Flow section: "On `invalid_grant` or `token_expired`, surface a re-consent prompt to the user via Telegram / conversation UI. Never report a successful zero-result import when the failure is an auth error."

### A1-3. P2 — No token revocation flow on user disconnect

The brainstorm describes "private by default" and "opt-in consent at OAuth time" but does not specify what happens when a user wants to disconnect Gmail integration. Simply deleting the token row from Auraken's database is insufficient -- the grant remains active in Google's system, visible at https://myaccount.google.com/permissions. The token must be revoked via `POST https://oauth2.googleapis.com/revoke` so the user sees the integration as fully disconnected.

**Recommendation:** Add to Open Questions or a new "Disconnect Flow" section: "On user disconnect, call Google's revoke endpoint, then delete the local token row, then cascade-delete imported data (see privacy agent findings)."

### A1-4. P3 — OAuth consent screen copy not specified

The brainstorm says "opt-in consent at OAuth time" but does not specify the consent screen copy. Google's OAuth consent screen allows a custom description. If this just says "Auraken wants to read your Gmail" without specifying "we will scan order confirmation emails and store product names, prices, and purchase dates," the consent is incomplete per both Google's API TOS and GDPR Article 13. This is also a Google verification requirement for sensitive scopes.

**Recommendation:** Draft the consent screen description text in the brainstorm so it can be reviewed alongside the data flow. Include: what emails are scanned (order confirmations only), what data is extracted and stored, and where to find the delete-my-data flow.

---

## Agent 2: fd-email-parsing-robustness

### A2-1. P0 — No sender address validation strategy against spoofing

The brainstorm lists specific sender addresses (`auto-confirm@amazon.com`, `ship-confirm@amazon.com`, etc.) but does not specify how sender identity is verified. Gmail messages have multiple "from" representations: the display name, the `From` header, and the envelope sender (RFC 5321 `MAIL FROM`). A spoofed email with `From: auto-confirm@amazon.com` in the display name but a different envelope sender would pass a naive substring check and inject attacker-controlled product data into jawncloud via `upsert_sku`. The Gmail API returns both `payload.headers` (which includes the raw `From` header) and SPF/DKIM results in the `Authentication-Results` header.

**Recommendation:** Specify in the Email Parsing Strategy section: "Validate the `From` header address (not display name) against the allow-list. Additionally, check `Authentication-Results` for SPF/DKIM pass on the sender domain. Reject emails that fail authentication before parsing."

### A2-2. P1 — No plain-text MIME fallback handling

The brainstorm states "Parse email HTML per retailer parser module" and describes "structured HTML with consistent patterns." However, some Gmail messages arrive as `text/plain` only -- corporate email proxies, forwarded messages, or Google's own plain-text rendering for older clients strip the HTML part. A parser that only reads `text/html` MIME parts will silently skip these emails without error, producing an incomplete import that appears complete to the user ("Found 47 purchases" when there were actually 52).

**Recommendation:** Each parser module should: (a) attempt `text/html` first, (b) fall back to `text/plain` with a simplified regex extractor, (c) if neither yields parseable data, log a structured warning with the `message-id` and sender for manual review. The brainstorm should note this three-tier strategy.

### A2-3. P1 — ASIN regex likely misses book ISBNs stored as ASINs

The brainstorm says "ASIN enables future enrichment but is sufficient as a unique product identifier." Amazon ASINs come in two forms: the `B0XXXXXXXXXX` format (10 chars starting with B0) for most products, and plain 10-digit ISBNs for books (e.g., `0321125215`). A regex anchored on `B0[A-Z0-9]{8}` will miss every book purchase. Since Kindle is explicitly in MVP scope, this is a direct gap -- Kindle purchases of books will have ISBN-format ASINs in the confirmation emails.

**Recommendation:** Specify the ASIN extraction regex as `/[A-Z0-9]{10}/` validated against known Amazon ASIN link patterns (e.g., `/dp/[A-Z0-9]{10}/` in href attributes), not a `B0`-prefixed pattern.

### A2-4. P2 — No handling of Amazon international email format variants

The brainstorm targets `auto-confirm@amazon.com` but does not mention `auto-confirm@amazon.co.uk`, `auto-confirm@amazon.de`, `auto-confirm@amazon.co.jp`, etc. Users with international Amazon accounts will have order confirmations from these domains. The HTML templates also differ: currency formats (`EUR 1.299,99` vs `$1,299.99`), product name encoding (UTF-8 with non-ASCII characters), and DOM structure variations between regional templates.

**Recommendation:** Add to the Email Parsing Strategy: "MVP targets `amazon.com` senders. International Amazon domains are deferred to v2 alongside other retailers. The sender allow-list must use exact domain matching, not substring, to avoid accidentally processing international variants with the US parser."

### A2-5. P2 — No structured error handling for malformed emails

The brainstorm does not address what happens when an email matches the sender allow-list but has unexpected HTML structure (template redesign, truncated email, corrupted encoding). An unhandled `KeyError` or `AttributeError` mid-batch would crash the pipeline and lose progress on all previously-parsed emails in that batch if there is no checkpoint mechanism.

**Recommendation:** Specify that each parser wraps extraction in a try/except that catches parse failures, logs the `message-id` and failure reason as a structured error, and continues to the next email. Failed emails should be surfaced in the post-import summary ("Found 47 purchases, 3 emails could not be parsed").

---

## Agent 3: fd-mcp-idempotency-contracts

### A3-1. P0 — `add_wardrobe` has no `private` parameter; brainstorm's privacy contract is unimplementable

The brainstorm specifies `add_wardrobe(status=OWN, private=true)` as the MCP call for imported items. However, the actual `add_wardrobe` tool schema (from interjawn's MCP server) accepts only `brand`, `code`, `size`, `status`, `colorway`, `quantity`, and `user_id`. There is no `private` parameter. This means the brainstorm's core privacy guarantee -- "all imported items are private by default" -- cannot be fulfilled through the `add_wardrobe` MCP call as currently designed. Either interjawn needs a schema change to add `private` support, or privacy must be enforced through a separate mechanism.

**Recommendation:** This is a blocking design gap. Either: (a) add a `private` boolean parameter to the `add_wardrobe` MCP tool schema in interjawn, or (b) if privacy is enforced at the jawncloud DB layer via a default, document that explicitly and remove the `private=true` parameter from the brainstorm's data flow to avoid confusion. Resolve before implementation begins.

### A3-2. P1 — `add_wardrobe` requires `size` but purchase emails rarely contain size data

The `add_wardrobe` MCP tool schema lists `size` as a **required** parameter (`"required": ["brand", "code", "size"]`). Order confirmation emails for non-apparel items (electronics, books, games, apps) do not have a size concept, and even apparel confirmations often omit size from the email body (it appears on the order detail page, not the confirmation email). The pipeline will fail on every `add_wardrobe` call for items without extractable size data unless a default or sentinel value is used.

**Recommendation:** Either: (a) make `size` optional in interjawn's `add_wardrobe` schema (with a default like `"OS"` for one-size), or (b) document in the brainstorm that the pipeline passes a sentinel value (e.g., `"OS"` or `"N/A"`) for items without size. The current schema will reject calls without `size`.

### A3-3. P1 — `upsert_sku` idempotency key is (brand_slug, code), not (brand, code) as brainstorm states

The brainstorm says "Duplicate SKUs in jawncloud are handled by `upsert_sku` (idempotent by brand+code)." The actual `upsert_sku` schema requires both `brand_name` and `brand_slug`. If the idempotency key uses `brand_slug` + `code` (the natural unique key), then inconsistent slug generation from the same brand name across pipeline runs will create duplicate SKUs. For example, "Arc'teryx" might slugify to `arcteryx` in one run and `arc-teryx` in another, creating two brand entries and two SKU entries for the same product.

**Recommendation:** Document the exact idempotency key in the brainstorm. Ensure the pipeline uses deterministic slug generation (e.g., `python-slugify` with fixed settings) and that the slug is generated once and cached per brand, not recomputed per email. Consider calling `list_brands` at pipeline start to build a brand-name-to-slug mapping from existing jawncloud data.

### A3-4. P1 — No MCP error propagation strategy for partial batch failures

The brainstorm says the pipeline makes batch `upsert_sku` + `add_wardrobe` calls but does not describe error handling when some calls succeed and others fail. If the MCP server returns errors for 50 out of 500 calls, the pipeline must: (a) count and report failures separately from successes, (b) not report "Found 500 purchases" when only 450 were written, (c) enable retry of only the failed items. The brainstorm's claim that the pipeline is "idempotent" only holds if the error tracking allows selective retry.

**Recommendation:** Add to the Data Flow section: "MCP call results are tracked per-item. The import summary distinguishes successful writes from failures. Failed items are logged with their email `message-id` for retry. The pipeline never reports a successful import count that includes unwritten items."

### A3-5. P2 — No per-email checkpoint for crash recovery

The brainstorm says "Large histories may take multiple runs" but does not describe a checkpoint mechanism. Without a per-email processing record (keyed by Gmail `message-id`), a pipeline crash at email 300 of 600 will restart from the beginning. While `upsert_sku` is idempotent for data correctness, re-processing 300 emails wastes Gmail API quota and MCP call budget. More critically, without checkpoints, the pipeline cannot distinguish "not yet processed" from "processed but MCP call failed."

**Recommendation:** Specify a checkpoint table in Auraken's DB: `(gmail_message_id TEXT PRIMARY KEY, status TEXT, processed_at TIMESTAMPTZ, error TEXT)`. Write status before MCP calls, update on success/failure. On re-run, skip message IDs with `status = 'success'`.

---

## Agent 4: fd-jawncloud-data-integrity

### A4-1. P0 — `private` flag has no enforcement path in jawncloud schema

The brainstorm's central privacy guarantee is "all imported items are private by default." However, the `add_wardrobe` MCP tool has no `private` parameter (see A3-1), and the `upsert_sku` tool similarly has no privacy field. This means there is no documented path for the import pipeline to mark items as private in jawncloud's database. If privacy is enforced via a database default (`private BOOLEAN NOT NULL DEFAULT true`), that default must be verified in the Prisma schema. If it relies on application logic, any code path that queries wardrobe items without a `WHERE private = false` filter will leak private purchases.

**Recommendation:** Verify the jawncloud Prisma schema has `private Boolean @default(true)` on the wardrobe model (not nullable). If the column does not exist, this is a schema change prerequisite for the pipeline. Database-level enforcement is the only safe approach -- application-layer filtering is too easy to bypass or forget in new queries.

### A4-2. P1 — No composite unique constraint documented for (user_id, sku_id) in wardrobe

The brainstorm claims idempotent re-runs via `upsert_sku`, but `add_wardrobe`'s description says it "creates or increments the wardrobe entry." If the wardrobe table lacks a composite unique constraint on `(user_id, sku_id)` (or `(user_id, brand, code, size)`), re-running the pipeline could create duplicate ownership rows. The `add_wardrobe` tool's "increments" behavior suggests it may increase `quantity` rather than creating duplicates, but this is undocumented in the brainstorm and the actual behavior under concurrent or repeated calls is unspecified.

**Recommendation:** Verify the jawncloud Prisma schema has `@@unique([userId, skuId, size])` or equivalent on the wardrobe model. Document in the brainstorm: "Re-runs increment quantity on existing wardrobe entries rather than creating duplicates, enforced by a DB-level unique constraint."

### A4-3. P2 — `retail_price` is typed as `number` (float) in MCP schema

The `upsert_sku` MCP tool defines `retail_price` as `"type": "number"` in its JSON schema. JavaScript/TypeScript `number` is IEEE 754 double-precision floating point. If this maps to a `Float` column in Prisma (and `DOUBLE PRECISION` in PostgreSQL), spending-pattern aggregations in Auraken will accumulate rounding errors. A purchase of `$1,299.99` stored as a float may become `1299.9899999999998` after round-tripping. Over hundreds of purchases, aggregate totals will diverge from receipt totals.

**Recommendation:** Verify the Prisma schema uses `Decimal` type for `retail_price` (maps to PostgreSQL `NUMERIC`). The MCP JSON schema can remain `number` since JSON has no decimal type, but the server-side handler must cast to `Decimal` before writing. Document this in the brainstorm's implementation notes.

### A4-4. P2 — Brand normalization fallback behavior undefined

The brainstorm says "Normalize brand names (fuzzy-match against existing jawncloud brands via `list_brands`)" but does not specify what happens when no match is found. The `upsert_sku` tool's description says it "also creates the brand if it doesn't exist," which means unmatched brands will auto-create new brand records. This is acceptable for MVP but risks brand fragmentation: "Arc'teryx", "Arcteryx", "ARC'TERYX", and "Arc'teryx Veilance" could all become separate brands if the fuzzy matcher threshold is too high or the email uses inconsistent casing.

**Recommendation:** Document the brand normalization strategy: (a) call `list_brands` once at pipeline start, (b) fuzzy-match each extracted brand name against the list with a documented threshold (e.g., 85% similarity), (c) if no match, create a new brand, (d) log all new brand creations in the import summary for user review. Consider a post-import brand merge tool for v2.

### A4-5. P3 — ASIN not stored as a dedicated indexed column

The brainstorm mentions ASIN as a unique product identifier and future enrichment key, but the `upsert_sku` schema has no dedicated `asin` field. ASIN would need to go into either the `code` field or the `specs` JSON object. If it goes into `specs`, future ASIN-based queries (enrichment, dedup, cross-retailer matching) require JSON path extraction rather than a simple indexed column lookup.

**Recommendation:** For MVP, using `code` = ASIN is acceptable for Amazon products. Document this convention explicitly: "For Amazon SKUs, `code` is set to the ASIN. For App Store / Steam, `code` is the app/game identifier." Consider adding a dedicated `external_ids JSONB` column in v2 for multi-source product identity.

---

## Agent 5: fd-personal-data-pipeline-privacy

### A5-1. P0 — No delete-my-data flow specified

The brainstorm describes import and storage but has no deletion flow. When a user disconnects Gmail or requests data deletion, the pipeline must delete: (a) the OAuth refresh token from Auraken, (b) all imported wardrobe rows from jawncloud, (c) all extracted purchase-pattern context from Auraken's preference/profile models, (d) any derived data (brand affinity scores, spending rhythm). Without this, a user who revokes Gmail access still has their purchase history permanently stored across two databases with no way to remove it. Under GDPR Article 17 (right to erasure), this is a compliance failure if Auraken serves EU users.

**Recommendation:** Add a "Data Deletion Flow" section to the brainstorm with a numbered sequence: (1) revoke OAuth token via Google endpoint, (2) delete token row from Auraken DB, (3) delete all wardrobe rows for this user's imported items from jawncloud, (4) purge purchase-pattern context and derived models from Auraken's context DB, (5) confirm deletion to user. This must be specified before MVP, not deferred to v2.

### A5-2. P1 — "Full history, no date cap" violates data minimization principle

The brainstorm explicitly states "Full history, no date cap. Import everything available." Under GDPR Article 5(1)(c), personal data must be "adequate, relevant and limited to what is necessary." If Auraken's recommendation models only need 2-3 years of purchase history to build meaningful taste profiles, importing 10-15 years of Gmail history collects data far beyond what is necessary for the stated purpose. A regulator reviewing this design would flag the unbounded collection scope.

**Recommendation:** Define a default retention window (e.g., 3 years) with an opt-in override for users who want full history. Document the justification: "3 years provides sufficient purchase density for taste modeling; older data adds noise and increases storage of personal financial data beyond necessity." Users who want full history can explicitly opt in, satisfying the "specific consent" requirement.

### A5-3. P1 — Consent screen does not disclose stored data categories

The brainstorm says "Privacy UX = opt-in consent at OAuth time + post-import summary of what was found" but does not specify what the consent screen tells the user about data storage. Telling users "we will read your Gmail" is not the same as telling them "we will extract and permanently store product names, prices, purchase dates, brand names, and spending patterns derived from your order confirmation emails in two separate databases." GDPR Article 13 requires disclosure of: categories of data collected, purposes of processing, retention period, and right to erasure.

**Recommendation:** Draft the consent disclosure text in the brainstorm. It must cover: (a) what emails are scanned (order confirmations from specific senders), (b) what data is extracted (product names, prices, dates, ASINs), (c) where it is stored (Auraken context DB + jawncloud product catalog), (d) how long it is retained, (e) how to delete it. This text is a prerequisite for the OAuth consent screen and the privacy policy.

### A5-4. P2 — Derived data lineage not tracked for cascade deletion

The brainstorm describes two storage destinations: jawncloud (SKUs, wardrobe) and Auraken's context DB (purchase patterns, brand affinities, spending rhythm). The Auraken context DB stores derived data -- aggregations and models built from individual purchase records. If a user deletes their Gmail import, the derived data must also be purged, but without lineage tracking (which records contributed to which derived model), selective deletion is impossible. The system would need to either: (a) re-derive all models from scratch minus the deleted user's data, or (b) delete all derived data for that user and rebuild.

**Recommendation:** Add to the implementation notes: "Auraken's context DB must tag all derived records with the source integration (gmail_import) and user_id. On deletion, all records with that tag are purged. Derived models (brand affinity, spending rhythm) are per-user and deleted entirely on user data deletion -- they are not shared or aggregated across users."

### A5-5. P2 — Error logging may leak purchase data to third-party services

The brainstorm uses Python 3.12+ and does not mention error tracking infrastructure. In production Python services, it is common to use Sentry, Datadog, or similar APM tools that capture local variables on exception. If a parser throws an exception while processing an email, the default exception handler will serialize the email HTML (containing product names, prices, and order details) into the error payload. This sends personal financial data to a third-party service without consent.

**Recommendation:** Add to implementation notes: "Error handlers must sanitize exception context before logging. Email bodies, parsed product data, and user identifiers must never appear in error payloads sent to external services. Use structured error codes with the Gmail `message-id` only."

---

## Summary

| Agent | P0 | P1 | P2 | P3 | Total |
|-------|----|----|----|----|-------|
| fd-gmail-oauth-token-lifecycle | 1 | 1 | 1 | 1 | 4 |
| fd-email-parsing-robustness | 1 | 2 | 2 | 0 | 5 |
| fd-mcp-idempotency-contracts | 1 | 3 | 1 | 0 | 5 |
| fd-jawncloud-data-integrity | 1 | 1 | 2 | 1 | 5 |
| fd-personal-data-pipeline-privacy | 1 | 2 | 2 | 0 | 5 |
| **Total** | **5** | **9** | **8** | **2** | **24** |

### Critical path (P0 findings that must resolve before implementation):

1. **A3-1 / A4-1**: `add_wardrobe` MCP tool has no `private` parameter -- the brainstorm's core privacy contract is unimplementable with the current interjawn schema. This blocks both the MCP integration and the data integrity layer.
2. **A1-1**: Refresh token storage security is unspecified -- long-lived Gmail credentials must not be stored in plaintext.
3. **A2-1**: No sender spoofing protection -- without SPF/DKIM validation, the parser is an injection vector into jawncloud.
4. **A5-1**: No delete-my-data flow -- GDPR compliance requires erasure capability before collecting personal financial data.
