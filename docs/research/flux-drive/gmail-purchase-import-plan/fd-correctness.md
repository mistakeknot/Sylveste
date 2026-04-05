---
agent: fd-correctness
target: docs/plans/2026-04-05-gmail-purchase-import.md
date: 2026-04-05
---

# Plan Correctness Review: Gmail Purchase Import Pipeline

## AC Coverage Gaps

### F3-AC4: `is_valid()` ASIN regex not enforced for non-Amazon parsers
**Severity: P1**
The PRD requires `ParseResult.is_valid()` to include an ASIN regex check (`[A-Z0-9]{10}`). The plan's `ParseResult.is_valid()` only checks `product_name`, `price`, and `purchase_date` in `zones_present`. App Store and Steam items have no ASIN — the AC must be scoped to Amazon-only, but neither the plan nor `is_valid()` makes this conditional. If left as-is, all digital parsers will always fail validation.

### F3-AC6: Parser-degraded warning on CSS→regex fallback not covered
**Severity: P2**
PRD AC: "Log parser-degraded warning on fallback." The plan describes `_extract_primary` and `_extract_fallback` in `BaseEmailParser` but never specifies a warning log call when the fallback path is taken. No step in Phase 2 or 3A adds this logging, and no test asserts on the warning.

### F6-AC8: Dual-destination decoupling not implemented
**Severity: P1**
PRD requires: "complete all interjawn upserts, then Auraken context writes" (dual-destination decoupled). The plan's `pipeline.py` describes a single consumer worker calling `upsert_sku` → `add_wardrobe` inline, but there is no step that separates the Auraken context write phase from the interjawn upsert phase. F7 (`PurchaseContextExtractor`) reads from `purchase_event_log`, which is written during pipeline execution — but the PRD's ordering guarantee (all interjawn writes first, then context writes) is never architecturally enforced. If the pipeline crashes mid-run, partial context writes may exist without complete interjawn state.

### F6-AC3: `last_processed_message_id` missing from `ImportProgress` schema
**Severity: P1**
PRD AC specifies `import_progress` must store `{user_id, last_processed_message_id, status, batch_count}`. The plan's Alembic migration for `ImportProgress` (Phase 2, Step 1) omits `last_processed_message_id` — the column used for checkpoint resume. Resume logic in `pipeline.py` (Phase 4, Step 1) says "resume from last audit log entry for this user" which is a different mechanism, but the PRD explicitly requires this column in the table schema. These are inconsistent.

### F5-AC5: Confidence threshold discrepancy
**Severity: P1**
PRD states: "Matches below 0.95 confidence staged as `pending_brand_match`." The plan implements two-tier thresholds of 0.97 (fashion/luxury) and 0.85 (standard), but neither tier uses 0.95 as the staging cutoff. The plan's staging logic says "below threshold → stage as `pending_brand_match`" which means items scoring 0.86–0.96 on the standard tier would be committed, violating the PRD's 0.95 floor for auto-commit. The plan needs an explicit cross-tier floor at 0.95 or the PRD must be updated.

### F7-AC4: Confidence tier thresholds differ from PRD
**Severity: P1**
PRD specifies: `low < 10, medium 10–50, high > 50`. The plan's test step says `5 observations → low, 30 → medium, 100 → high` (consistent with PRD), but the narrative in `PurchaseContextExtractor` uses "low/medium/high" with no explicit thresholds and `observation_count`. The implementation step omits the numeric thresholds entirely — the thresholds must be hardcoded in `context.py`, not only implied in the test.

### F8-AC9: Consent screen text is a doc, not a test-verified artifact
**Severity: P2**
PRD requires "Consent screen text drafted and reviewable." The plan creates `apps/Auraken/docs/consent-text.md` in Phase 1B, Step 5. This is adequate for the PRD's reviewability requirement, but no test or verification step asserts that the OAuth flow presents this text to the user — it exists as a documentation artifact only, with no link to the `gmail_oauth.py` consent URL builder.

### F8: Conversation trigger ("import my purchase history") not covered
**Severity: P2**
PRD AC1: "Telegram `/import` command or conversation trigger." Phase 6, Step 1 only implements the `/import` command handler. The NLP conversation trigger path (natural language "import my purchase history") has no corresponding step. If NLP intent handling exists elsewhere in `telegram.py` this may be in-scope, but the plan makes no reference to it.

---

## File Path and Module Name Consistency

### `recommendations.py` path unverified
**Severity: P2**
Phase 5, Step 2 references `apps/Auraken/src/auraken/recommendations.py` with "(or equivalent)" — the exact file is not identified. If this file doesn't exist, the staleness detection step has no concrete anchor. A prior step should locate or create this file.

### `gmail_import/` package `__init__.py` never created
**Severity: P2**
The plan creates `apps/Auraken/src/auraken/gmail_import/models.py`, `fetcher.py`, `pipeline.py`, etc. as a sub-package, but no step creates `apps/Auraken/src/auraken/gmail_import/__init__.py` or `apps/Auraken/src/auraken/gmail_import/parsers/__init__.py`. Python will treat these as namespace packages under Python 3.3+ but the absence is a gap if the project uses explicit package declarations or mypy strict mode.

### Test directory `test_gmail_import/` needs `__init__.py`
**Severity: P3**
Phase 2 Step 6 creates `apps/Auraken/tests/test_gmail_import/test_amazon_parser.py` but never creates `tests/test_gmail_import/__init__.py`. Depending on pytest configuration this may work, but it is inconsistent with the plan creating test files in a subdirectory without initializing the package.

---

## Phase Ordering

### Phase ordering is correct
The delivery sequence F1+F2 (parallel) → F3 → F4+F5 (parallel) → F6 → F7 → F8 matches the PRD dependency DAG. No ordering violations found.

### F8 Step 3 (category preview) requires fetch+parse before any writes
**Severity: P2**
The category preview step (Phase 6, Step 3) gates all writes on user confirmation after parsing. However, the plan notes "email bodies are already in memory at this point" — for large mailboxes this means holding all parsed email content in memory until confirmation. No buffering or streaming strategy is described. This is a design gap, not a blocker, but could cause OOM on imports with hundreds of emails.

---

## Steps Assuming Nonexistent Code

### `pipeline.py` calls `mcp_client.list_brands` at init but `InterjawnClient` never exposes `list_brands`
**Severity: P1**
Phase 3B (F5) `BrandMatcher.__init__` calls `list_brands` at pipeline start via `mcp_client`. Phase 4 `InterjawnClient` (mcp_client.py) only defines `upsert_sku` and `add_wardrobe`. No step adds `list_brands` to `InterjawnClient`. The brand matcher will fail to initialize.

### `deletion.py` queries wardrobe rows "by user_id, filter by source" but interjawn has no `user_id` or `source` column
**Severity: P1**
Phase 6, Step 4 assumes `delete_import_data` can query interjawn wardrobe rows by `user_id` and filter by `source=gmail_import`. The F2 schema change (Phase 1A) adds `private` and makes `size` optional — neither it nor any other step adds `user_id` or `source` to the `WardrobeItem` model. The deletion flow will have no way to target gmail-imported rows without this attribution field, or an alternative deletion strategy (e.g., tracking inserted IDs in `purchase_event_log`).

### `staleness detection` in `recommendations.py` reads `context_last_updated` but no step adds it
**Severity: P1**
Phase 5, Step 2 checks `context_last_updated` on the user's profile, and Phase 5, Step 1 sets it. But no Alembic migration adds `context_last_updated` to any existing user/profile table. The field is referenced without being created.

---

## Alembic Migration Chain

### No down-revision anchors in migration stubs
**Severity: P1**
PRD dependencies section explicitly requires: "Alembic migration chain with down-revision anchors." Neither migration stub in the plan (Phase 1B Step 2: `gmail_tokens`; Phase 2 Step 1: pipeline tables; Phase 3B Step 1: `brand_match_precedents`) includes a `down_revision` value or instructions to chain them. In Alembic, each migration must reference its predecessor — migrations generated without `down_revision` will either conflict or create a branched graph.

### `brand_match_precedents` migration (Phase 3B) not anchored to pipeline tables migration (Phase 2)
**Severity: P1**
If Phase 3B runs after Phase 2, its migration's `down_revision` must reference Phase 2's migration head. The plan treats these as independent schema stubs without specifying the chain order. This will produce an Alembic "multiple heads" error on `alembic upgrade head`.

### No migration for `context_last_updated` on user profile table
**Severity: P1**
See finding above — the field is used but the migration is absent.

---

## Test Strategy

### Happy path end-to-end test absent
**Severity: P1**
Phase 4, Step 4 tests the pipeline with mock inputs but focuses on error cases (lock, crash, MCP failure). No test asserts the full happy path: OAuth → fetch → parse → brand match → upsert → audit log row → `ImportSummary` with correct counts. Without a happy-path integration test, regressions in the normal flow will be caught only at manual QA.

### Security gate tests present but incomplete: no test for expired DKIM header
**Severity: P2**
Phase 2, Step 6 tests DKIM-absent rejection. The PRD requires "reject failed auth or absent header" — "failed" (header present but `dkim=fail`) is a different case from "absent." Only absence is tested; a `dkim=fail` case is not covered.

### `delete_import_data` test asserts "zero rows across all 6 tables" but only 5 tables named in PRD
**Severity: P2**
PRD F8 AC: "zero rows across all 6 tables." The PRD's delete flow lists 5 Auraken-side tables (`purchase_event_log`, `failed_extractions`, `import_progress`, `brand_match_precedents`, `gmail_tokens`) plus interjawn wardrobe rows (the 6th). The plan's test in Phase 6, Step 5 says "all 6 tables" but deleting interjawn rows via MCP is not a DB-level assert — it requires a mock MCP call asserting `add_wardrobe`-equivalent deletion was invoked. The test step does not describe how to verify interjawn-side deletion.

### Fingerprint drift test present but fingerprint storage not implemented
**Severity: P2**
Phase 2 and 3A describe `_structural_fingerprint` as a class attribute (`str | None = None`) and tests assert "fingerprint drift → warning logged." But no step describes how the fingerprint is persisted between runs (stored in DB? hardcoded? loaded from file?). The test will always see `None` (no stored fingerprint) and never exercise drift detection unless a storage mechanism is implemented first.

### No test for token refresh mid-import (45-minute boundary)
**Severity: P2**
PRD F6 AC: "re-acquire token every 45 minutes during long-running imports." The plan describes the logic but no test mocks a token expiring mid-pipeline and verifies re-acquisition. This is a critical path for users with large historical imports.
