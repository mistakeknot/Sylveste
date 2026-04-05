---
agent: fd-architecture
target: docs/prds/2026-04-05-gmail-purchase-import.md
date: 2026-04-05
---

# Architecture Review: Gmail Purchase Import PRD

## 1. Dependency Ordering

### [P0] F3/F4 depend on F2, but F5 and F6 also depend on F2 — the blockers list is incomplete

The PRD's dependency section states F2 blocks F6 and F8, but F3/F4 also write to interjawn via `add_wardrobe`, meaning the parser framework (F3) cannot be fully integration-tested without F2's `private` field and `size` default changes. F5 (brand matching) calls `list_brands` and routes through `add_wardrobe` on resolution, so it also depends on F2. Recommendation: mark F2 as blocking F3, F4, F5, F6, and F8 in the dependency table.

### [P1] F6 depends on F5, but neither the PRD text nor the AC makes this explicit

F6's upsert pipeline must resolve brand slugs before calling `add_wardrobe` (which requires a valid brand slug), and that resolution is owned by F5. The PRD describes them as parallelizable but they cannot be. Recommendation: add F5 → F6 to the dependency chain.

### [P2] F7 depends on F6's dual-destination write completing — not just F6 existing

F7 writes context derived from upserted wardrobe rows; if F6's Auraken context write leg is incomplete (it is explicitly decoupled and comes last), F7 has no source rows to derive from. The ordering is technically safe but should be called out: F7 cannot be built against real data until F6's second destination write is live.

## 2. F2 (interjawn Schema) — Downstream Blockers

### [P0] `WardrobeItem` has no `private` column in the current Prisma schema — F2's scope is understated

The live schema at `/home/mk/projects/interjawn/prisma/schema.prisma` has no `private` column on `WardrobeItem`. F2's AC specifies `private BOOLEAN NOT NULL DEFAULT true` enforced at DB level, but this requires a Prisma migration, a `prisma generate`, and a rebuild of the interjawn MCP binary before any F6 upsert call can pass `private=true`. The PRD does not mention this migration or the rebuild step. Recommendation: F2 must explicitly track the Prisma migration + MCP server redeploy as required deliverables.

### [P1] The live `add_wardrobe` tool signature requires `size` as a non-optional positional field

The current live MCP schema marks `size` as required (`"required": ["brand", "code", "size"]`). F2's AC says to make `size` optional with default `"OS"`, but this is a breaking change to the tool's JSON schema — callers passing `size` explicitly will still work, but the F3/F4 parsers that extract size from emails must handle the case where no size is present (digital goods) without the current tool throwing a validation error. Until F2 ships, F3/F4 tests against the live MCP will fail for sizeless items.

### [P1] F2's composite unique constraint conflicts with the existing schema

The live `WardrobeItem` already has `@@unique([userId, skuId, sizeLabel, colorway, status])` — a five-column composite. F2 proposes `@@unique([userId, skuId, size])` (three-column), which is a different constraint and would break the existing upsert logic in `add_wardrobe` (which keys on the five-column form). The PRD needs to clarify whether this replaces the existing constraint or adds a new one, and update the `add_wardrobe` upsert `where` clause accordingly.

## 3. DB Migration Plan

### [P1] Five new Auraken tables listed but no migration file or Alembic chain is described

The PRD lists `gmail_tokens`, `import_progress`, `brand_match_precedents`, `failed_extractions`, and `purchase_event_log` as new tables, but gives no migration strategy — no indication of whether they land in one migration or five, no down-revision anchor, and no mention of the existing migration chain head (`2f4b49b1d5aa`). Given that Auraken uses Alembic with explicit revision chaining, this needs a concrete migration plan before implementation starts. Recommendation: add a migrations section that names the revision files and their dependency order.

### [P2] `import_progress.last_processed_message_id` is typed ambiguously — Gmail message IDs are opaque strings, not sequential integers

The AC describes this as a checkpoint field used to resume on restart, but Gmail message IDs are non-sequential hex strings. Using them as a "last processed" cursor for ordered replay is unreliable; the pipeline should checkpoint on a batch sequence number or a sorted `internalDate` timestamp instead. Recommendation: clarify the resume mechanism and the ordering guarantee.

## 4. MCP Protocol Assumptions

### [P1] The PRD assumes Auraken calls interjawn MCP via the stdio transport, but does not specify how the MCP subprocess is managed in production

The live interjawn server runs as a stdio MCP process (see `/home/mk/projects/interjawn/src/index.ts` — `StdioServerTransport`). The PRD's F6 describes an asyncio queue with configurable workers (default 3), but does not say whether Auraken spawns one long-lived MCP subprocess, one per worker, or uses an HTTP gateway. Three concurrent workers against one stdio subprocess is a sequencing hazard — MCP stdio is inherently single-request-at-a-time. Recommendation: clarify whether F6's concurrency is at the batch level (sequential MCP calls from a single process) or requires a multi-process or HTTP transport upgrade.

### [P2] F6 calls `add_wardrobe` directly, but new items without an existing SKU require `upsert_sku` first — this two-step dependency is not described

The live `add_wardrobe` returns `SKU not found` and explicitly instructs the caller to use `upsert_sku` first. Amazon and digital receipt imports will frequently produce products not in the jawncloud catalog. The PRD has no mention of the `upsert_sku` → `add_wardrobe` two-call pattern, the SKU creation strategy, or how brand/product data from the parsed receipt maps to `upsert_sku` fields. This is a significant implementation gap in F6's AC.

## 5. Concurrency

### [P0] No idempotency key or lock prevents two simultaneous imports from double-inserting the same message IDs

If a user triggers `/import` twice in quick succession (or a retry races a slow in-progress run), both coroutines will read the same `import_progress` checkpoint, process overlapping message batches, and attempt duplicate `add_wardrobe` upserts. The five-column unique constraint on `WardrobeItem` will prevent duplicate wardrobe rows, but `purchase_event_log` and `failed_extractions` have no such protection described in the PRD. Recommendation: add a per-user import lock (e.g., `import_progress.status = 'running'` checked-and-set atomically before starting) with a stale-lock timeout, and define idempotency semantics for `purchase_event_log` inserts.

### [P1] `brand_match_precedents` has a write-race on first match for the same `raw_string`

F5 performs a precedent lookup before fuzzy match, then inserts a new row on miss. If two concurrent import workers process emails with the same brand string, both will find no precedent and both will attempt to insert — producing a unique constraint violation unless the table has `ON CONFLICT DO NOTHING` semantics. The AC does not specify the conflict resolution strategy. Recommendation: add `@@unique([raw_string])` to the table spec and define upsert semantics.
