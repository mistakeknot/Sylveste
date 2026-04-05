---
artifact_type: brainstorm
bead: sylveste-fbz
stage: discover
date: 2026-04-05
domain: discovery
---

# Gmail Purchase Import — Building Personal Context from Purchase History

## What We're Building

A pipeline that imports purchase history from Gmail to build personal context (taste, brand affinity, spending patterns). Auraken owns the extraction and context-building; jawncloud is the product data layer. MVP covers Amazon order confirmations plus digital receipts (App Store, Steam, Kindle).

All imported items are **private by default** — visible only to the owning user, never surfaced externally unless explicitly shared.

## Why This Approach

Purchase history is *revealed preferences* — what someone actually buys, not what they say they like. This is high-signal personal context for two Auraken domains:

- **Discovery & recommendations** — knows what you own, avoids duplicates, understands taste through actual behavior
- **Pattern awareness** — spending rhythm, brand loyalty, impulse vs. considered purchases, category distribution

Gmail API (read-only OAuth) is the right integration point: user consents once, automatable, no manual export needed. The alternative — Amazon Data Takeout CSV — is manual, slow (hours to days), and can't be automated.

## Architecture

```
User consents (Gmail OAuth, gmail.readonly)
    |
Auraken (email parsing + context extraction)
    |
    +---> interjawn MCP tools (upsert_sku, add_wardrobe)
    |         |
    |         +---> jawncloud DB (SKUs, wardrobe — PRIVATE by default)
    |
    +---> Auraken context DB (purchase patterns, brand affinities, spending rhythm)
```

## Key Decisions

1. **Auraken owns the pipeline, not jawncloud.** Understanding *what you buy and why* is personal context, not catalog management. Auraken calls interjawn MCP to write product data.

2. **MVP = Amazon + digital receipts.** Parse order confirmations from Amazon (`auto-confirm@amazon.com`, `ship-confirm@amazon.com`, `digital-no-reply@amazon.com`) plus App Store, Steam, and Kindle. Other retailers deferred to v2.

3. **Private by default.** All imported items marked private. User can explicitly share individual items or categories later. Privacy UX = opt-in consent at OAuth time + post-import summary of what was found.

4. **Full history, no date cap.** Import everything available. Gmail API quotas handled via batch processing with backoff. Large histories may take multiple runs — that's fine, the pipeline is idempotent.

5. **Dedup deferred.** Re-orders, returns, and gift detection are v2. MVP imports all order confirmations as-is. Duplicate SKUs in jawncloud are handled by `upsert_sku` (idempotent by brand+code).

6. **ASIN enrichment deferred.** MVP extracts product name, price, date, ASIN from email HTML. Richer metadata (images, specs) via Amazon PA-API or Exa search is v2.

## Email Parsing Strategy

Amazon order confirmations use structured HTML with consistent patterns:
- Product name, ASIN, price, order date, quantity in predictable DOM locations
- ASIN enables future enrichment but is sufficient as a unique product identifier for now

Digital receipts vary more:
- App Store: `no_reply@email.apple.com` — app name, price, date
- Steam: `noreply@steampowered.com` — game name, price, date
- Kindle: Amazon digital orders use same sender pattern

Each retailer gets a parser module. Parsers are independent — adding a new retailer = adding a new parser, no changes to the pipeline.

## Data Flow

1. OAuth with Gmail (`gmail.readonly` scope, narrow consent)
2. Query for order confirmation emails by sender address
3. **Pre-parse gate**: Assert each fetched message matches sender allowlist before reading body (circuit breaker against query scope drift). Check DKIM via `Authentication-Results` header.
4. Parse email HTML per retailer parser module (two-layer: CSS selector primary, regex fallback)
5. **Validation gate**: `ParseResult.is_valid()` — per-field presence tracking, range validation (price > 0, date parseable), quarantine invalid records. Extract `is_gift` flag and `order_placed_date` from Amazon HTML.
6. Normalize brand names (fuzzy-match against jawncloud via `list_brands`). Record match precedents in `brand_match_precedents` table. Stage ambiguous matches (< 0.95 confidence) for user review.
7. **Buffered upsert**: Bounded asyncio queue (configurable workers, default 3) drains parsed items to interjawn MCP. Per-batch checkpoint written to `import_progress` table after each batch of 100. On crash, resume from last checkpoint.
8. Batch `upsert_sku` + `add_wardrobe(status=OWN)` via interjawn MCP. **Prerequisite**: interjawn schema must add `private` boolean to `add_wardrobe` and make `size` optional (default `"OS"`).
9. Extract purchase-pattern context → write to Auraken's preference/profile models with temporal decay (half-life ~18 months, configurable). Tag derived records with `source=gmail_import`.
10. Present summary: per-parser statistics (count, date range, failures), brand disambiguation queue, zero-price anomaly flags.

## Data Deletion Flow

On user disconnect or deletion request:
1. Revoke OAuth token via Google endpoint
2. Delete token row from Auraken DB
3. Delete all wardrobe rows for this user's imported items from jawncloud (keyed by `purchase_import_id`)
4. Purge all purchase-pattern context and derived models tagged `source=gmail_import` from Auraken context DB
5. Confirm deletion to user

Consent UX must disclose: what data is extracted, where stored (two DBs), persistence after OAuth revocation, and how to delete.

## interjawn Schema Prerequisites

Before implementation:
- `add_wardrobe`: add `private: boolean` param (default `true`), make `size` optional (default `"OS"`)
- Verify `retail_price` maps to `Decimal` (not `Float`) in Prisma schema
- Verify wardrobe has `@@unique([userId, skuId, size])` or equivalent

## Open Questions (v2)

- **Category filtering**: Let user select which categories to track vs. ignore
- **Return/refund detection**: Parse return confirmation emails to update wardrobe status
- **Gift detection**: Shipping address != billing address heuristic
- **Subscription tracking**: Detect recurring purchases from repeat patterns
- **Other retailers**: Extend parser set (Best Buy, Target, Etsy, etc.)
- **ASIN enrichment**: Product images and specs from Amazon PA-API or Exa search

## Implementation Notes

- Auraken is Python 3.12+ (uv, PostgreSQL + pgvector)
- Use `google-auth-oauthlib` + `google-api-python-client` for Gmail OAuth
- interjawn MCP server is TypeScript (Prisma, PostgreSQL) — called via MCP protocol from Auraken
- Trigger: conversation command ("import my purchase history") or `/import` in Telegram
- Pipeline is idempotent — safe to re-run without creating duplicates
