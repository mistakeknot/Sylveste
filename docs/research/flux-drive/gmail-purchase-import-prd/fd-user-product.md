---
agent: fd-user-product
target: docs/prds/2026-04-05-gmail-purchase-import.md
date: 2026-04-05
---

# User/Product Quality Review: Gmail Purchase Import PRD

## Acceptance Criteria

**[P1] F5: Brand matching confidence thresholds are untestable as written.**
The two-tier tolerance AC defines separate thresholds (0.97 vs 0.85) but does not specify how "fashion" and "luxury" categories are determined — there is no upstream taxonomy at this stage (see Open Question: canonical category taxonomy). Until category taxonomy is resolved, this AC cannot be implemented or verified. Recommendation: either defer the tiered threshold to v2 or define a hardcoded category allowlist (e.g., `["apparel", "footwear", "accessories"]`) as a temporary stand-in.

**[P2] F8: "Category preview step between OAuth and first import" has no defined content or pass/fail condition.**
The AC says "show breakdown before committing" but doesn't specify what breakdown means — item count by retailer, by category, or by date range — or what "committing" requires the user to do (explicit confirm tap, timeout, or passive display). This is the only UX gate in the flow and its vagueness could result in it being skipped. Recommendation: add an AC row specifying the preview content and the required user action (e.g., explicit "Start import" tap required; "Cancel" aborts before any MCP writes).

**[P2] F7: `confidence_tier` thresholds (low < 10, medium 10–50, high > 50) are purchase counts, but the field is labeled as if it signals model confidence.**
The naming conflates data density (number of observations) with inference confidence, which will confuse downstream consumers of the context DB. Recommendation: rename to `density_tier` or add a clarifying note that this represents observation count brackets, not a probability score.

**[P3] F6: "Dual-destination writes decoupled" AC is underspecified for failure recovery.**
The AC says "complete all interjawn upserts, then Auraken context writes" but does not define behavior when interjawn upserts partially succeed before a crash — whether the checkpoint covers interjawn-complete-but-Auraken-pending as a distinct resumable state is unclear. Recommendation: add an AC row for partial-success resume: "If interjawn upserts completed but Auraken writes did not, checkpoint records this state and resumes from Auraken writes on restart (no duplicate interjawn calls)."

## Feature Decomposition and Coupling

**[P1] F2 blocks F6 and F8, but F3/F4 parsers have no stated dependency on F2 and can produce output with no valid destination.**
Parser development (F3/F4) can proceed independently, but end-to-end testing of the pipeline requires F2's schema changes to be live. This is noted in Dependencies but the feature list does not flag F3/F4 as "integration-blocked until F2." Without this annotation, a plan might treat F3 as independently shippable when the full value is gated. Recommendation: add explicit delivery notes: "F3/F4 are developable in isolation; integration tests require F2 to be merged."

**[P2] F5 (brand matching) is consumed by F6 (upsert pipeline) but F5's `pending_brand_match` staging queue has no defined flush mechanism in MVP.**
F6 writes items to interjawn; F5 may stage some as pending. The PRD shows a disambiguation queue surfaced in F8's summary, but there is no AC describing what happens to staged items — are they held indefinitely, written with a placeholder brand, or silently dropped until the user resolves? Recommendation: add an AC to F5 or F6 specifying the pending-item holding behavior: e.g., "items in `pending_brand_match` are written to interjawn with `brand=null` and updated once the user resolves the queue."

## User Flow Gaps

**[P1] There is no defined path from the Telegram `/import` command back to the user if OAuth has not been granted.**
F8 defines the trigger and F1 defines the OAuth flow, but the handoff between them is not specified: does `/import` detect missing token and automatically initiate OAuth, or does it error with instructions? Without this, the first-time user flow is broken at the seam between F1 and F8. Recommendation: add an AC to F8 (or a cross-feature note): "If no valid token exists, `/import` initiates the OAuth consent flow inline before proceeding."

**[P2] The category preview step (F8) comes after OAuth but before import, yet F3/F4 parsers must run to generate the preview.**
To show a "breakdown by category" the pipeline must fetch and parse emails first — but parsing before user confirmation means data has already been read from Gmail. This contradicts the intent of the preview as a consent gate. Recommendation: clarify whether the preview is generated from a dry-run parse (emails fetched but nothing written), or from metadata only (subject-line scan without body extraction). The distinction affects both privacy posture and implementation complexity.

**[P3] No error state defined for the post-import summary when zero items are imported.**
F8 defines summary stats for successful imports but does not describe the user-facing message when all records fail validation or the inbox has no matching emails. An empty result with no explanation will appear as a silent failure. Recommendation: add an AC: "If import completes with zero successful items, summary displays a distinct empty-state message with the count of attempted emails and top failure reason."

## Scope Creep

**[P2] F7's `context_last_updated` staleness suppression ("suppresses confidence-dependent recommendations") is a recommendation engine behavior, not an import pipeline behavior.**
Defining recommendation suppression logic in an import PRD introduces a behavioral dependency on Auraken's recommendation layer that is outside the stated solution scope ("bootstrap context"). This either needs to be cut to v2 or moved into an Auraken recommendation PRD with a forward reference here. Recommendation: replace with a scoped AC: "Write `context_last_updated` timestamp on each context write; Auraken recommendation engine consults this field (behavior defined separately)."

**[P3] F5's structural fingerprint per parser ("hash of tag/class skeleton") for template mutation detection is operationally useful but has no consumer defined in MVP.**
There is no AC describing what happens when a fingerprint mismatch is detected — no alert, no fallback path, no user notification. If nothing consumes it, it is premature instrumentation. Recommendation: cut to v2 unless an AC is added for the detection-to-action path (e.g., "fingerprint mismatch logs a `parser_degraded` warning and disables that parser until a human updates the selector").

## Missing Edge Cases

**[P1] Concurrent import protection is absent.**
No AC prevents a user from triggering two simultaneous imports (e.g., double-tapping `/import` in Telegram, or a restart race with a stalled import). The `import_progress` table exists but no AC enforces a mutex or in-progress guard. Without this, two workers could process the same message IDs, producing duplicate wardrobe entries. Recommendation: add an AC to F6: "If an import is already `status=in_progress` for the user, new import requests return an 'Import already running' message with current progress stats."

**[P1] The delete-my-data flow (F8) does not specify whether in-flight imports are cancelled before deletion.**
If a user triggers deletion while an import is processing, the pipeline may write new records after the purge completes, leaving orphaned data. Recommendation: add an AC: "Delete-my-data sets `import_progress.status=cancelled` for any in-progress job; pipeline checks this flag before each batch write and halts if set."

**[P2] No AC covers the Gmail quota exhaustion case.**
Gmail API has per-user and per-project quotas. A user with thousands of Amazon emails could exhaust quotas mid-import. The checkpoint mechanism handles restarts, but there is no AC for rate-limit errors (HTTP 429) from the Gmail API itself — only MCP rate limits are mentioned (F6 bounded queue). Recommendation: add an AC to F3 or F6: "Gmail API 429 responses trigger exponential backoff; current batch is checkpointed before backing off."

**[P2] The `is_gift` detection flag has no defined extraction logic in F3 or F4.**
F7 uses `is_gift=true` to exclude items from brand affinity, but neither F3 nor F4 specifies how `is_gift` is determined from email content — Amazon order confirmations include gift indicators in some formats but not all. Without a defined extraction AC, this flag will likely default to `false` for all records, silently including gifted items in taste modeling. Recommendation: add an AC to F3: "Amazon parser extracts `is_gift` from the 'This order is a gift' field or equivalent order metadata; defaults to `false` with a warning log if the field is absent from an otherwise-valid parse."

**[P3] No AC covers token expiry during a long-running import.**
Access tokens expire after one hour; a large historical import may exceed this. F1 covers `invalid_grant` (refresh token invalidated) but not mid-import access token refresh. Recommendation: add an AC to F1 or F6: "Pipeline refreshes access token proactively when remaining TTL < 5 minutes; mid-import token refresh is transparent to the parse/upsert loop."
