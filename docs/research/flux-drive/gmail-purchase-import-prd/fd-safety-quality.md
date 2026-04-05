---
agent: fd-safety-quality
target: docs/prds/2026-04-05-gmail-purchase-import.md
date: 2026-04-05
---

# Safety & Code Quality Review: Gmail Purchase Import PRD

## Privacy / GDPR

**P1 — Retention window left open as an "Open Question"**
The PRD defers the retention decision (3-year default vs. full history) to an open question, but this is a GDPR Article 5(1)(e) storage-limitation obligation — not an optional design choice. Recommendation: resolve it before the plan stage; default to 3-year window with opt-in full history (minimization principle) and document the legal basis in the PRD.

**P1 — Deletion flow is incomplete for derived data**
F8's delete-my-data flow lists: revoke OAuth → delete token → delete wardrobe rows → purge context. It does not explicitly cover `brand_match_precedents`, `failed_extractions`, `import_progress`, or `purchase_event_log`. F7 tags Auraken context records with `source=gmail_import` + `user_id` for cascade deletion, but the cascade must be verified in the migration for every table that stores `user_id`. Recommendation: enumerate all tables in the deletion AC and add a smoke-test AC that asserts zero rows remain after the flow completes.

**P2 — No data processor agreement (DPA) mention for Google**
The PRD treats Gmail as a data source but does not reference whether a DPA with Google is in place for processing user email content. Under GDPR Art. 28 this is mandatory when acting as a data controller. Recommendation: add a dependency on legal/DPA confirmation before GA launch; note this in the Dependencies section.

**P2 — Audit log stores `subject_hash` but not the hash function or salt**
F6's per-email audit log includes `subject_hash`. Without specifying the hash algorithm and whether a user-scoped salt is applied, this field could allow reconstruction of subjects via rainbow tables. Recommendation: specify HMAC-SHA256 keyed with the user's token-scoped secret, not a bare hash.

## Security

**P1 — Sender allowlist is insufficient without DKIM enforcement as a hard gate**
F3 specifies DKIM validation via `Authentication-Results` header and rejects failed auth, which is correct. However, `Authentication-Results` is a header set by the receiving MTA — if Auraken fetches raw messages via the Gmail API, Google's own authentication results are trustworthy. The concern is that the AC does not specify what to do when `Authentication-Results` is absent (not all Google-processed messages include it). Recommendation: treat missing `Authentication-Results` as a failure, not a pass-through.

**P1 — No mention of token storage key rotation procedure**
F1 specifies "Fernet + rotatable secret" but has no AC for how rotation is triggered, how in-flight tokens survive a rotation, or who holds the Fernet key. A rotatable-but-never-rotated secret provides false assurance. Recommendation: add ACs covering key rotation cadence, re-encryption of stored tokens on rotation, and the secret's storage location (e.g., secrets manager, not env var).

**P2 — Brand fuzzy-match input is user-influenced and fed into DB writes**
The raw brand string from a parsed email is stored directly in `brand_match_precedents.raw_string` and used as a fuzzy-match query. If an attacker crafts a malicious receipt (e.g., via a forwarded email), they can inject arbitrary strings into the precedents table. Recommendation: add a length cap and character-class allowlist for `raw_string` before storage; fuzzy-match queries should use parameterized inputs, not string interpolation.

**P2 — No mention of rate limiting on the `/import` Telegram command**
F8 exposes a Telegram trigger that can kick off a full email scan. Without rate limiting, a user (or compromised Telegram session) could trigger repeated full-history imports, exhausting Gmail API quota and generating large DB writes. Recommendation: add an AC enforcing a cooldown period between imports (e.g., one full import per 24 hours per user).

## Error Handling

**P1 — No AC for interjawn MCP being unreachable mid-import**
F6 describes a buffered pipeline with checkpointing, but no AC specifies the behavior when MCP calls fail after the parse stage has completed. The checkpoint only tracks `last_processed_message_id`; if MCP is down, the pipeline must either hold all parsed-but-not-upserted results in memory (unbounded for large imports) or persist them to a staging table. Recommendation: add a `parsed_pending_upsert` staging buffer and an AC that verifies resume correctly drains it after MCP recovers.

**P1 — Token expiry mid-import is not addressed**
F1 handles `invalid_grant` at import start but does not address token expiry occurring partway through a long import. A 60-minute access token can expire during large history imports. Recommendation: add an AC requiring the refresh flow to be invoked transparently mid-import; if refresh fails, checkpoint current position and surface a re-consent prompt with a "resume" path.

**P2 — Gmail API quota exhaustion not handled**
The Gmail API has per-user and per-project quotas (250 quota units/second; 1B units/day). A user with a large mailbox could exhaust the project quota mid-import. The PRD has no AC for detecting 429/quota-exceeded responses or implementing exponential backoff with jitter. Recommendation: add explicit retry-with-backoff ACs in F6 and surface quota errors to the user in the post-import summary.

**P2 — Parser template mutation detection (F4 structural fingerprint) has no escalation path**
F4 specifies a structural fingerprint per parser for template mutation detection, but there is no AC for what happens when a fingerprint mismatch is detected. Silent degraded parsing is worse than a clean failure. Recommendation: add an AC that quarantines the entire email on fingerprint mismatch (not just partial-parse failure) and emits an alert to an ops channel.

## Testing Strategy

**P1 — No test infrastructure specified for Gmail API mocking**
Parsers and the OAuth flow depend on live Gmail API responses. Without a recorded fixture library or a mock API layer, CI tests will either hit the live API (flaky, quota-consuming) or not exist. Recommendation: add a dependency on a fixture library (e.g., VCR cassettes or manually recorded message fixtures per sender), and require each parser to pass a fixture suite as part of its AC.

**P2 — Brand matching tests can't be isolated without a `list_brands` stub**
F5's brand matcher calls `list_brands` at pipeline start. In unit tests this couples brand-matching logic to a live interjawn MCP call. Recommendation: require that `list_brands` results are injectable (passed in, not fetched inside the matcher), enabling pure unit tests against a fixed catalog snapshot.

**P2 — Deletion flow has no end-to-end smoke test AC**
F8 describes the deletion flow steps but no AC requires an automated test that runs the full flow and asserts zero rows across all tables for the target user. This is the highest-risk user-facing guarantee (GDPR right to erasure). Recommendation: add a mandatory E2E test AC covering the full deletion sequence.

**P3 — No mention of test fixtures for multi-item orders or gift orders**
F3's `is_gift` flag and multi-item order parsing are complex edge cases. Without explicit fixture requirements in the ACs, these paths are likely undertested. Recommendation: require at least two Amazon parser fixtures: a multi-item order and a gift order.

## Naming Conventions

**P3 — F3's `zones_present` / `zones_absent` field names are non-obvious**
`ParseResult` uses `zones_present` and `zones_absent` as per-field presence flags, but "zones" has no referent in the rest of the PRD. Likely intended to mean "fields" or "extraction regions." Recommendation: rename to `fields_present` / `fields_absent` or document what a "zone" is.

**P3 — `add_wardrobe` tool name is misleading for non-apparel items**
F2 extends `add_wardrobe` to accept non-apparel items (App Store apps, games, Kindle books), but the name implies clothing. This will become increasingly awkward as the importer covers more categories. Recommendation: either rename the MCP tool to `add_catalog_item` in F2, or explicitly note that the name mismatch is a known debt to be resolved in v2.
