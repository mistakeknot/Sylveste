---
artifact_type: plan
bead: sylveste-fbz
prd: docs/prds/2026-04-05-gmail-purchase-import.md
stage: plan
---

# Plan: Gmail Purchase Import Pipeline

PRD: `docs/prds/2026-04-05-gmail-purchase-import.md`
Epic: `sylveste-fbz` (8 children: F1-F8)

## Review Fixes Applied

Fixes from plan review (fd-correctness + fd-architecture):
- All ORM models use SQLAlchemy 2.0 `Mapped`/`mapped_column` with UUID PKs (match Auraken convention)
- `gmail_import/models.py` renamed to `gmail_import/types.py` (avoid collision with `auraken/models.py`)
- `gmail_auth.py`/`gmail_oauth.py` moved inside `gmail_import/` subpackage
- `ParseResult.is_valid()` makes ASIN optional (only required for Amazon parser, not digital receipts)
- `ImportProgress` includes `last_processed_message_id` column
- MCP client uses `mcp.client.stdio.stdio_client` with `StdioServerParameters` (not raw subprocess)
- `InterjawnClient` exposes `list_brands()` for BrandMatcher init
- F2 adds `source` and `import_user_id` columns to WardrobeItem (for deletion flow scoping)
- `context_last_updated` field added to Auraken `CoreProfile` model (own migration)
- All migration stubs include `down_revision` anchors (Alembic chain, not branched graph)
- Staleness check in `CoreProfile` loading path (not just `recommendations.py`)
- Confidence threshold: 0.95 is the staging threshold (below = pending). 0.85 is the auto-reject floor.

## Delivery Order

```
Phase 1 (parallel):  F2 (interjawn schema) + F1 (Gmail OAuth)
Phase 2:             F3 (parser framework + Amazon parser)
Phase 3 (parallel):  F4 (digital parsers) + F5 (brand matching)
Phase 4:             F6 (buffered upsert pipeline)
Phase 5:             F7 (context extraction)
Phase 6:             F8 (import UX + deletion flow)
```

---

## Phase 1A: F2 — interjawn Schema Prerequisites

**Bead:** sylveste-mul (P1)
**Codebase:** interjawn plugin (TypeScript/Prisma)
**Estimated effort:** Small (schema change + migration)

### Step 1: Find interjawn source and Prisma schema

```bash
find /home/mk/projects/Sylveste -path "*/interjawn*" -name "schema.prisma" 2>/dev/null
# Also check for the MCP server entry point and add_wardrobe tool definition
```

### Step 2: Modify Prisma schema

**File:** interjawn's `prisma/schema.prisma`

- Add `private Boolean @default(true)` to `WardrobeItem` model
- Change `size` from required to optional: `size String?` with `@default("OS")`
- Verify `retailPrice` uses `Decimal` type (change from `Float` if needed)
- Review existing unique constraint — update to accommodate optional `size`

### Step 3: Add migration

```bash
cd <interjawn-dir> && npx prisma migrate dev --name add-private-optional-size
```

### Step 4: Update `add_wardrobe` MCP tool

**File:** interjawn's MCP server source (tool definition for `add_wardrobe`)

- Add `private` parameter: `{ type: "boolean", description: "...", default: true }`
- Make `size` optional in the JSON schema (remove from `required` array)
- Update the handler to pass `private` and `size` (with defaults) to Prisma create/upsert

### Step 5: Update `upsert_sku` handler

- Verify `retail_price` is cast to `Decimal` before Prisma write (not stored as float)

### Step 6: Test

- Existing interjawn tests still pass (backward compat)
- New test: `add_wardrobe` without `size` succeeds (defaults to "OS")
- New test: `add_wardrobe` with `private=true` sets DB column correctly
- New test: `add_wardrobe` with `private=false` overrides default

### Verification

- [ ] `add_wardrobe` callable without `size` param
- [ ] `private` column exists with `DEFAULT true`
- [ ] Existing callers unbroken

---

## Phase 1B: F1 — Gmail OAuth + Token Management (parallel with 1A)

**Bead:** sylveste-pxg (P2)
**Codebase:** `apps/Auraken/src/auraken/`
**Estimated effort:** Medium

### Step 1: Add dependencies

**File:** `apps/Auraken/pyproject.toml`

```
google-auth-oauthlib
google-api-python-client
cryptography  # for Fernet
```

### Step 2: Alembic migration — `gmail_tokens` table

**File:** `apps/Auraken/alembic/versions/<timestamp>_add_gmail_tokens.py`

```python
class GmailToken(Base):
    __tablename__ = "gmail_tokens"
    id = Column(Integer, primary_key=True)
    user_id = Column(String, unique=True, nullable=False, index=True)
    encrypted_refresh_token = Column(LargeBinary, nullable=False)  # Fernet-encrypted
    scopes = Column(String, nullable=False)  # comma-separated
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
```

### Step 3: Token manager module

**New file:** `apps/Auraken/src/auraken/gmail_auth.py`

- `class GmailTokenManager`:
  - `__init__(self, db_session, fernet_key: str)` — load key from env var `GMAIL_FERNET_KEY`
  - `async def get_credentials(self, user_id: str) -> google.oauth2.credentials.Credentials` — decrypt token, build credentials, handle refresh
  - `async def store_token(self, user_id: str, credentials)` — encrypt refresh token, upsert row
  - `async def revoke_token(self, user_id: str)` — call Google revoke endpoint, delete row
  - `async def handle_invalid_grant(self, user_id: str) -> str` — return re-consent URL
  - `async def refresh_if_needed(self, credentials) -> Credentials` — refresh access token if expiry < 5 min (for mid-import refresh)

### Step 4: OAuth flow handler

**New file:** `apps/Auraken/src/auraken/gmail_oauth.py`

- `def build_oauth_flow(redirect_uri: str) -> Flow` — configure with `gmail.readonly` scope
- `def get_consent_url(flow: Flow) -> str` — generate authorization URL
- `def exchange_code(flow: Flow, code: str) -> Credentials` — exchange auth code for tokens

### Step 5: Consent screen text

**New file:** `apps/Auraken/docs/consent-text.md`

Draft consent disclosure:
- What emails scanned (order confirmations from specific senders)
- What data extracted (product names, prices, dates, ASINs)
- Where stored (Auraken context DB + jawncloud product catalog)
- Retention (3 years default, opt-in full history)
- How to delete (Settings > Delete purchase data)

### Step 6: Tests

**New file:** `apps/Auraken/tests/test_gmail_auth.py`

- Token encryption/decryption roundtrip
- `invalid_grant` returns re-consent URL (not silent failure)
- Revoke calls Google endpoint + deletes local row
- Expired token auto-refreshes

### Verification

- [ ] OAuth consent URL generated with correct scope
- [ ] Token stored encrypted, retrievable, refreshable
- [ ] Revocation calls Google + cleans local state
- [ ] `invalid_grant` handled gracefully

---

## Phase 2: F3 — Email Parser Framework + Amazon Parser

**Bead:** sylveste-8z3n (P2)
**Codebase:** `apps/Auraken/src/auraken/`
**Depends on:** F1 (OAuth tokens), F2 (interjawn schema)

### Step 1: Alembic migration — pipeline tables

**File:** `apps/Auraken/alembic/versions/<timestamp>_add_import_tables.py`

Tables: `import_progress`, `failed_extractions`, `purchase_event_log`

```python
class ImportProgress(Base):
    __tablename__ = "import_progress"
    id = Column(Integer, primary_key=True)
    user_id = Column(String, nullable=False, index=True)
    status = Column(String, nullable=False)  # running, completed, failed
    batch_count = Column(Integer, default=0)
    last_processed_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class FailedExtraction(Base):
    __tablename__ = "failed_extractions"
    id = Column(Integer, primary_key=True)
    import_id = Column(Integer, ForeignKey("import_progress.id"))
    message_id = Column(String, nullable=False)
    sender = Column(String)
    failure_reason = Column(String)
    parser_name = Column(String)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class PurchaseEventLog(Base):
    __tablename__ = "purchase_event_log"
    id = Column(Integer, primary_key=True)
    import_id = Column(Integer, ForeignKey("import_progress.id"))
    message_id = Column(String, nullable=False, unique=True)
    sender = Column(String)
    subject_hash = Column(String)  # SHA-256, not plaintext
    parse_outcome = Column(String)  # success, failed, quarantined
    upsert_outcome = Column(String)  # success, failed, skipped
    parser_name = Column(String)
    parser_version = Column(String)
    purchase_date = Column(DateTime(timezone=True))  # order-placed, not email-received
    product_name = Column(String)
    price = Column(Numeric)
    brand_raw = Column(String)
    brand_resolved = Column(String)
    is_gift = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
```

### Step 2: ParseResult dataclass

**New file:** `apps/Auraken/src/auraken/gmail_import/models.py`

```python
@dataclass
class ParseResult:
    product_name: str | None
    price: Decimal | None
    asin: str | None
    purchase_date: datetime | None
    quantity: int
    is_gift: bool
    retailer: str  # "amazon", "appstore", "steam", "kindle"
    zones_present: set[str]
    zones_absent: set[str]
    raw_brand: str | None
    parser_name: str
    parser_version: str
    message_id: str

    def is_valid(self) -> bool:
        required = {"product_name", "price", "purchase_date"}
        return required.issubset(self.zones_present) and \
               self.price is not None and self.price > 0 and \
               self.product_name is not None and len(self.product_name) > 0
```

### Step 3: Base parser class

**New file:** `apps/Auraken/src/auraken/gmail_import/parsers/base.py`

```python
class BaseEmailParser(ABC):
    name: str
    version: str
    sender_allowlist: list[str]
    required_fields: set[str]
    _structural_fingerprint: str | None = None

    @abstractmethod
    def parse(self, html: str, message_id: str) -> ParseResult: ...

    def check_fingerprint(self, html: str) -> bool:
        """Compare structural skeleton against stored fingerprint. Return False if drifted."""

    def _extract_primary(self, html: str) -> dict:
        """CSS selector extraction."""

    def _extract_fallback(self, html: str) -> dict:
        """Regex-based fallback extraction."""
```

### Step 4: Gmail fetcher with authentication gates

**New file:** `apps/Auraken/src/auraken/gmail_import/fetcher.py`

- `class GmailFetcher`:
  - `SENDER_ALLOWLIST`: set of permitted sender addresses
  - `async def fetch_order_emails(self, credentials, since_message_id=None) -> AsyncIterator[GmailMessage]`
  - Pre-fetch gate: assert `message.from` in `SENDER_ALLOWLIST` before reading body
  - DKIM check: parse `Authentication-Results` header, reject failed/absent
  - Subject-line filter: exclude patterns matching cancellation/return (`Your order has been cancelled`, `Your refund`)
  - Gmail API 429 handling: exponential backoff with jitter
  - Access token refresh: check expiry before each batch, refresh if < 5 min remaining

### Step 5: Amazon parser

**New file:** `apps/Auraken/src/auraken/gmail_import/parsers/amazon.py`

- `class AmazonParser(BaseEmailParser)`:
  - `name = "amazon"`, `version = "1.0.0"`
  - `sender_allowlist = ["auto-confirm@amazon.com", "ship-confirm@amazon.com", "digital-no-reply@amazon.com"]`
  - Primary extraction: CSS selectors for product name, price, ASIN, order date, quantity
  - Fallback: regex for ASIN (`[A-Z0-9]{10}` in `/dp/` URLs), price (`\$[\d,]+\.\d{2}`), date patterns
  - Extract `is_gift` flag from "This is a gift" text or shipping-address-differs heuristic
  - Extract `order_placed_date` from "Order Placed" field (not email `received` timestamp)
  - Post-parse invariant: single-item → `item_price ≈ order_total ± shipping` (tolerance: $0.02)
  - Structural fingerprint: SHA-256 of sorted CSS class names + tag nesting depth at extraction points

### Step 6: Test fixtures and tests

**New dir:** `apps/Auraken/tests/fixtures/gmail/`

Fixture files (saved HTML):
- `amazon_single_item.html` — standard single-item order
- `amazon_multi_item.html` — multiple items in one order
- `amazon_gift.html` — gift order with different shipping address
- `amazon_cancellation.html` — cancellation email (should be filtered)
- `amazon_malformed.html` — truncated/broken HTML

**New file:** `apps/Auraken/tests/test_gmail_import/test_amazon_parser.py`

- Parse each fixture, assert correct field extraction
- Malformed fixture → `is_valid() == False`, written to quarantine
- Cancellation fixture → filtered by subject line, never parsed
- Gift fixture → `is_gift == True`
- Fingerprint drift → warning logged

**New file:** `apps/Auraken/tests/test_gmail_import/test_fetcher.py`

- Mock Gmail API responses
- DKIM absent → message rejected
- Sender not in allowlist → message discarded before body read
- 429 response → exponential backoff (verify delay pattern)

### Verification

- [ ] Amazon fixture parses correctly (name, price, ASIN, date, is_gift)
- [ ] Malformed HTML quarantined with structured error
- [ ] DKIM/sender gates reject non-order emails
- [ ] Subject-line filter excludes cancellations

---

## Phase 3A: F4 — Digital Receipt Parsers (parallel with 3B)

**Bead:** sylveste-nhc1 (P2)
**Depends on:** F3 (parser framework)

### Step 1: App Store parser

**New file:** `apps/Auraken/src/auraken/gmail_import/parsers/appstore.py`

- Sender: `no_reply@email.apple.com`
- Extract: app name, unit price (excl. tax), purchase date
- `price` semantic: unit cost in USD. Free apps = `$0.00`
- Required fields: `{product_name, price, purchase_date}`
- ASIN equivalent: App Store ID from receipt link URL

### Step 2: Steam parser

**New file:** `apps/Auraken/src/auraken/gmail_import/parsers/steam.py`

- Sender: `noreply@steampowered.com`
- Extract: game name, price, purchase date
- Handle regional pricing (MVP: USD only, log non-USD as parse warning)

### Step 3: Kindle parser

**New file:** `apps/Auraken/src/auraken/gmail_import/parsers/kindle.py`

- Same senders as Amazon but detect digital-order format (look for Kindle/digital markers in subject/body)
- Differentiate from physical Amazon orders by content patterns
- ASIN regex same as Amazon

### Step 4: Canonical output validation

**File:** `apps/Auraken/src/auraken/gmail_import/parsers/base.py`

- Add `validate_canonical_schema(result: ParseResult)` — enforces semantic contracts:
  - `price` is unit cost in USD excl. tax
  - `price >= 0` (free items allowed, negative not)
  - `purchase_date` is timezone-aware datetime

### Step 5: Fixtures and tests

- `appstore_receipt.html`, `steam_receipt.html`, `kindle_receipt.html`
- Each parser: correct extraction, partial parse = failure, fingerprint tracking

---

## Phase 3B: F5 — Brand Matching with Precedent Memory (parallel with 3A)

**Bead:** sylveste-zmqe (P2)
**Depends on:** F3 (needs ParseResult output)

### Step 1: Alembic migration — `brand_match_precedents`

```python
class BrandMatchPrecedent(Base):
    __tablename__ = "brand_match_precedents"
    id = Column(Integer, primary_key=True)
    raw_string = Column(String, nullable=False, index=True)
    resolved_brand_id = Column(String)
    resolved_brand_slug = Column(String)
    confidence = Column(Numeric)
    method = Column(String)  # auto, user_confirmed
    resolved_at = Column(DateTime(timezone=True), server_default=func.now())
    __table_args__ = (UniqueConstraint("raw_string", name="uq_brand_precedent_raw"),)
```

### Step 2: Brand matcher module

**New file:** `apps/Auraken/src/auraken/gmail_import/brand_matcher.py`

- `class BrandMatcher`:
  - `__init__(self, db_session, mcp_client)` — load `list_brands` at init, cache brand→slug map
  - `async def resolve(self, raw_brand: str, category_hint: str | None) -> BrandMatch`
  - Lookup precedents table first → if found and `method=user_confirmed`, return immediately
  - Fuzzy match using `thefuzz.fuzz.token_sort_ratio` (or `rapidfuzz`)
  - Two-tier threshold: high-sensitivity (fashion/luxury) >= 0.97, standard >= 0.85
  - Category hint from retailer: Amazon fashion → high sensitivity; App Store → standard
  - Below threshold → stage as `pending_brand_match` (don't commit)
  - Above threshold → commit and write precedent
  - Deterministic slug: `python-slugify` with `separator="-", lowercase=True`
  - Log every decision: `{raw_brand, matched, score, threshold, source_email_id}`

### Step 3: Tests

- Known brand pairs (true positives): "NIKE" → "nike", "Arc'teryx" → "arcteryx"
- Known negatives: "Nike" vs "Nikko", "Apple" (tech) vs "Apple" (grocery)
- Precedent hit → skip fuzzy match
- `user_confirmed` precedent → immutable, never overridden
- Concurrent first-match → `ON CONFLICT DO NOTHING` (no write-race)

---

## Phase 4: F6 — Buffered MCP Upsert Pipeline

**Bead:** sylveste-0z24 (P2)
**Depends on:** F5 (brand resolution), F3 (parser framework), F1 (OAuth)

### Step 1: Import pipeline orchestrator

**New file:** `apps/Auraken/src/auraken/gmail_import/pipeline.py`

- `class ImportPipeline`:
  - `__init__(self, db_session, gmail_creds, mcp_client, brand_matcher)`
  - `async def run(self, user_id: str) -> ImportSummary`
  - Per-user lock: check `import_progress.status != 'running'` for this user; abort if locked
  - Create `import_progress` row with `status=running`
  - Fetch emails via `GmailFetcher` (resume from last audit log entry for this user)
  - Parse each email → validate → brand match → queue for upsert
  - Bounded asyncio queue (maxsize=100), single consumer worker (stdio transport constraint)
  - Consumer: `upsert_sku` then `add_wardrobe` per item (two-call pattern)
  - Write audit log per email: `{message_id, parse_outcome, upsert_outcome}`
  - Checkpoint: update `import_progress.batch_count` every 100 emails
  - Token refresh: check `credentials.expiry` before each batch, refresh if < 5 min
  - On completion: set `import_progress.status=completed`
  - On error: set `import_progress.status=failed`, log error, preserve partial progress

### Step 2: MCP client wrapper

**New file:** `apps/Auraken/src/auraken/gmail_import/mcp_client.py`

- `class InterjawnClient`:
  - Wraps MCP stdio calls to interjawn
  - `async def upsert_sku(self, brand_name, brand_slug, code, category, retail_price, ...) -> Result`
  - `async def add_wardrobe(self, brand, code, status="OWN", private=True, size="OS", ...) -> Result`
  - Error handling: timeout → retry once, then log failure
  - Result tracking: success/failure per call

### Step 3: Import summary

```python
@dataclass
class ImportSummary:
    total_emails: int
    parsed: int
    failed: int
    quarantined: int
    upserted: int
    upsert_failed: int
    per_parser: dict[str, ParserStats]  # {parser_name: {count, date_range, failures, zero_price_count}}
    pending_brand_matches: list[PendingBrandMatch]
    duration_seconds: float
```

### Step 4: Tests

- Full pipeline with mock Gmail API + mock MCP client
- Concurrent import attempt → lock prevents double-run
- Mid-import crash → resume from checkpoint (only new emails processed)
- MCP failure for 1 item → logged, pipeline continues, summary shows failure count

---

## Phase 5: F7 — Context Extraction with Temporal Decay

**Bead:** sylveste-isx8 (P2)
**Depends on:** F6 (upserted purchase data)

### Step 1: Context extraction module

**New file:** `apps/Auraken/src/auraken/gmail_import/context.py`

- `class PurchaseContextExtractor`:
  - Reads from `purchase_event_log` for a given import
  - Applies temporal decay: `weight = 0.5 ** ((now - purchase_date).days / (18 * 30))`
  - Excludes `is_gift=True` from brand affinity (still counts in wardrobe)
  - Builds brand affinity tuples: `(brand, category, price_tier, purchase_count, last_purchase_date)`
  - Price tiers: budget (< $25), mid ($25-100), premium ($100-500), luxury (> $500)
  - Computes `observation_count` per construct → `confidence_tier` (low/medium/high)
  - Tags all derived records: `source=gmail_import`, `user_id=<user_id>`
  - Sets `context_last_updated` on user's profile

### Step 2: Staleness detection

**File:** `apps/Auraken/src/auraken/recommendations.py` (or equivalent)

- Before using purchase-derived constructs: check `context_last_updated`
- If stale (> 6 months): suppress confidence-dependent recommendations or prompt refresh

### Step 3: Tests

- Temporal decay: 2017 purchase contributes ~0.6% of 2026 purchase weight
- Gift exclusion: `is_gift=True` not in brand affinity output
- Confidence tiers: 5 observations → low, 30 → medium, 100 → high
- Staleness: 7-month-old context → stale flag set

---

## Phase 6: F8 — Import UX + Deletion Flow

**Bead:** sylveste-i207 (P2)
**Depends on:** F1, F2, F6 (full pipeline integration)

### Step 1: Telegram handler

**File:** `apps/Auraken/src/auraken/telegram.py`

- Add `/import` command handler
- First-time (no token): redirect to OAuth consent flow (generate URL, send to user)
- Has token: run `ImportPipeline.run(user_id)` in background task
- Rate limit: max 1 concurrent, max 3 per day per user
- Progress: send "Importing..." → "Found N emails, parsing..." → final summary

### Step 2: Post-import summary formatter

**New file:** `apps/Auraken/src/auraken/gmail_import/summary.py`

- Format `ImportSummary` as Telegram message
- Per-parser stats: `Amazon: 87 items (2018-03 to 2026-04), 2 failures`
- Zero-price anomaly flags: `App Store: 18/24 items at $0.00 (free apps)`
- Brand disambiguation queue: "3 brands need confirmation: [review]"
- Parse failure count: "5 emails could not be parsed — [details]"

### Step 3: Category preview (pre-commit gate)

- After OAuth + email fetch but before any writes:
  - Parse all emails, compute per-retailer/category breakdown
  - Send preview to user: "Found 87 Amazon, 24 App Store, 12 Steam — proceed?"
  - Wait for confirmation before writing to jawncloud/Auraken
  - Note: email bodies are already in memory at this point (parsed but not committed)

### Step 4: Delete-my-data flow

**New file:** `apps/Auraken/src/auraken/gmail_import/deletion.py`

- `async def delete_import_data(user_id: str, db_session, mcp_client, token_manager)`:
  1. Cancel in-flight import (set `import_progress.status=cancelled`)
  2. `token_manager.revoke_token(user_id)` — Google revoke + local delete
  3. Delete wardrobe rows via interjawn MCP (query by user_id, filter by source)
  4. Delete from Auraken tables: `purchase_event_log`, `failed_extractions`, `import_progress`, `brand_match_precedents` — all WHERE `user_id`
  5. Purge context: delete all preference records tagged `source=gmail_import` for this user
  6. Send confirmation to user

### Step 5: Tests

- `/import` with no token → OAuth URL sent
- `/import` while already running → "Import already in progress"
- Delete flow: assert zero rows across all 6 tables after deletion
- Rate limit: 4th import in a day → rejected with message

### Verification (end-to-end)

- [ ] User triggers `/import` → sees OAuth consent → grants access → sees progress → sees summary with per-parser stats
- [ ] Brand disambiguation queue works (ambiguous matches presented, user confirms)
- [ ] Delete-my-data removes ALL records across ALL tables
- [ ] Re-import after deletion works (fresh start)
