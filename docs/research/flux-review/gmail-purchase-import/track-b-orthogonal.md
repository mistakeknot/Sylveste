---
track: B
track_name: Orthogonal
agent_count: 4
date: 2026-04-05
target: docs/brainstorms/2026-04-05-gmail-purchase-import-brainstorm.md
---

# Track B — Orthogonal Review: Gmail Purchase Import Pipeline

Four parallel disciplines review the Auraken Gmail purchase import pipeline. Each brings operational patterns that software engineers rarely formalize because they seem like "obviously we'd handle that" — until the pipeline is running on real data at scale and the silent failures compound.

---

## Agent 1: fd-forensic-accounting-document-reconstruction

**Source discipline:** Forensic accounting / certified fraud examination — transaction history reconstruction from partial, inconsistent, and adversarially incomplete source documents; litigation-defensible intake pipelines.

---

### Finding 1.1

**Severity:** P1

**Title:** Parse failures are silently dropped — no structured failure record per email

**Description:** Forensic accountants never let a document fall off the bottom of the stack without writing a gap entry. If an Amazon order confirmation uses an A/B-tested HTML variant or a localized template the parser has not seen, the brainstorm's pipeline would catch an exception and continue, leaving no trace that the email existed. The user sees "Found N purchases" but has no way to know that N+K emails were tried and K failed. In a litigation context, a missing record is more dangerous than a malformed one — at least the malformed one is visible. The same logic applies here: a user who believes their full history was imported but has silent gaps will make decisions on a preference model with unknown holes.

**Recommendation:** Each parser module must emit a structured result for every email it touches — either a parsed record with source provenance (Gmail message ID, sender, received date) or a failure record with failure reason and raw snippet. The pipeline summary shown to the user ("Found N purchases across M categories") must include a second count: "K emails could not be parsed — [view details]." Failure records go to the same store as successes, just with a `parse_status=failed` flag, so the gap is visible and auditable.

---

### Finding 1.2

**Severity:** P1

**Title:** Brand fuzzy-match normalization decisions are silent and irreversible

**Description:** Step 4 of the data flow normalizes brand names against jawncloud via fuzzy match against `list_brands`. A forensic accountant would demand that every normalization decision — raw input, matched canonical, confidence score, timestamp — be logged in a separate audit table, not just the normalized result. Without this, a systematic normalization error (e.g., "Kindle" consistently matching a malformed "Kindl" brand entry because it scores above the threshold) is invisible until a user notices their Kindle purchases are miscategorized. By then, the brand normalization has been applied to potentially hundreds of records, and there is no way to identify which records were affected or re-run the normalization with a corrected threshold.

**Recommendation:** Log every fuzzy-match decision as a separate normalization event: `{raw_brand, matched_canonical, score, threshold, matched_at, source_email_id}`. Surface the normalization log in the post-import summary as a reviewable step: "Brand matches applied — [review 12 normalization decisions]." This enables batch correction when a systematic error is discovered: identify all records where `matched_canonical = "Kindl"` and re-run normalization.

---

### Finding 1.3

**Severity:** P2

**Title:** Idempotency is a design claim, not a verified property — edge cases not enumerated

**Description:** The brainstorm states the pipeline is idempotent via `upsert_sku`, but this rests entirely on `upsert_sku`'s behavior for edge cases that are not enumerated: same ASIN, different price (price drop between two runs); same ASIN, different order date (re-order); same ASIN from two parsers (a Kindle book appearing in both Amazon and Kindle digital receipt parsers). A forensic accountant would require an idempotency regression test that re-runs the full pipeline against a fixed email fixture set and asserts that the record count and field values are identical across runs — not a conceptual claim but a passing test.

**Recommendation:** Write a fixture-based idempotency test: seed a test Gmail OAuth response with a fixed set of order confirmation emails (including the ASIN edge cases above), run the pipeline twice against the same fixture, assert that jawncloud and Auraken's context DB are byte-identical after both runs. Add the edge cases — same ASIN different price, same ASIN from two retailers, return confirmation emails — as explicit fixture cases.

---

### Finding 1.4

**Severity:** P2

**Title:** Return confirmation emails will be imported as purchases — wardrobe inflated with un-owned items

**Description:** The brainstorm defers return/refund detection to v2, but the implication of deferral is not stated: Amazon return confirmation emails (`return@amazon.com`, `returns@amazon.com`) will be parsed as order confirmations if their HTML structure is similar enough, adding returned items to the wardrobe with `status=OWN`. A forensic accountant reconciling a transaction ledger would note that importing credits (returns) as debits (purchases) is a systematic sign error — items the user no longer owns appear in the preference model as owned, distorting both the wardrobe and the spending pattern context.

**Recommendation:** Before deferring to v2, add a sender-address denylist for known Amazon return/refund senders to the MVP sender allowlist. This is a one-line addition to the sender filter and costs nothing. The full return-parsing feature (updating `status=RETURNED`) remains v2; the immediate fix is to not incorrectly import returns as purchases.

---

### Finding 1.5

**Severity:** P3

**Title:** Zero results from sender query is indistinguishable from pipeline error

**Description:** If the Gmail query for `auto-confirm@amazon.com` returns zero results, the pipeline reports "0 Amazon purchases found." A user who has years of Amazon purchase history — but whose Gmail account had a filter that archived those emails into a non-searched label — cannot distinguish "you have no Amazon purchases" from "the pipeline searched the wrong location." Forensic accountants distinguish between "document not found" and "document search was not exhaustive." The pipeline currently only does one.

**Recommendation:** After a zero-result query for a known high-volume sender like `auto-confirm@amazon.com`, surface a soft warning in the post-import summary: "No Amazon order confirmations found — if you have Amazon purchases, check that your Gmail labels include All Mail in the search scope." This requires no architectural change, just a zero-result branch in the summary generation.

---

## Agent 2: fd-health-information-management

**Source discipline:** Health information management / AHIMA-credentialed RHIA — patient data integration pipelines, consent management architecture, HIPAA-compliant longitudinal record construction, data-subject rights.

---

### Finding 2.1

**Severity:** P1

**Title:** OAuth revocation does not imply data deletion — consent UX does not communicate this

**Description:** In health information management, the distinction between "consent to access" and "consent to store what was already accessed" is foundational — revoking a release-of-information authorization does not delete the records already released. Here, `gmail.readonly` OAuth access is revocable at any time through Google, but revoking it leaves all previously imported SKUs and wardrobe entries intact in jawncloud and Auraken's preference DB. A user who revokes access expecting their purchase data to disappear — a reasonable expectation given that revoking is the only control they see — will experience this as a data governance failure. The brainstorm describes "private by default" but does not address revocation semantics at all.

**Recommendation:** The OAuth consent screen copy and the post-import summary must explicitly state that imported data persists after OAuth revocation and requires a separate deletion action. Add a "Delete all imported purchase data" action to the account settings, clearly scoped to both jawncloud (SKUs + wardrobe) and Auraken's preference DB. The consent-at-import and the data-at-rest are two separate decisions; the UX must surface them as such.

---

### Finding 2.2

**Severity:** P1

**Title:** Post-import summary aggregates too coarsely to surface systematic parser errors

**Description:** "Found N purchases across M categories" is the health equivalent of a discharge summary that says "patient had several encounters" — it aggregates to the point where a systematic error is invisible in the summary. If the App Store parser imports all subscription renewals as one-time purchases, or imports all prices as $0.00 due to a template change, the N-across-M summary will not flag this. A health information manager reviewing a longitudinal record extract would require per-source statistics — records per provider, date ranges, anomaly flags — before certifying completeness. The same discipline applies here.

**Recommendation:** The post-import summary must include per-parser statistics: `Amazon: 87 records, date range 2018-03-12 to 2026-04-05, 2 parse failures; App Store: 24 records, date range 2020-01-01 to 2026-04-04, 0 parse failures; Steam: 12 records...`. Include a zero-price rate per parser: if App Store shows 18/24 records at $0.00, that is a parser anomaly flag, not a normal distribution. The user can then judge whether the import is complete before the data is committed to the preference model.

---

### Finding 2.3

**Severity:** P2

**Title:** Item-level deletion does not propagate to Auraken's preference model — orphaned signals

**Description:** The brainstorm describes "private by default" with the implication that the user controls their data, but the data-subject right to delete at item granularity requires that deletion cascade across all stores where the item's signal lives. In health information, a patient's right to request amendment or deletion of a specific record applies to every system that received that record — not just the primary source. Here, deleting a wardrobe entry from jawncloud leaves its purchase-pattern signal in Auraken's preference DB untouched. A user who deletes a gift purchase they don't want in their taste profile will find that the brand affinity signal persists because the preference model update is not rolled back.

**Recommendation:** Define a `purchase_import_id` that links each wardrobe entry in jawncloud to its corresponding preference signal writes in Auraken's context DB. Deletion of a wardrobe entry by `purchase_import_id` triggers a cascading signal removal in Auraken. This requires the cross-system linkage to be designed now — it cannot be bolted on cleanly after the preference model has been running for months.

---

### Finding 2.4

**Severity:** P2

**Title:** Parser version is not logged per record — re-parsing after a bug fix is undiscoverable

**Description:** When a parser bug is fixed — say, the Amazon parser was incorrectly extracting quantity as 1 for all multi-quantity orders — the pipeline can re-run (idempotent, safe to re-run). But without a `parser_version` field on each imported record, the operator has no way to identify which records were produced by the buggy version and which were produced by the fixed version. Health information management requires that every record carry the version of the workflow that produced it, precisely because correction workflows require knowing the scope of the error. The brainstorm has no mention of parser versioning.

**Recommendation:** Add `parser_name` and `parser_version` to the per-record provenance metadata alongside the Gmail message ID. On re-run, the pipeline can identify records produced by an older parser version and flag them for review or overwrite. Semver-pin each parser module; increment on any behavioral change.

---

### Finding 2.5

**Severity:** P3

**Title:** Category opt-out is deferred to v2 but consent granularity argument applies to MVP

**Description:** The brainstorm defers category filtering to v2, but the consent-granularity argument from health information management applies at MVP: a user who consents to "import my purchase history" at OAuth time may not intend to import medical supply purchases, adult content purchases, or political donation receipts that arrive as order confirmations. `gmail.readonly` grants full inbox access, and the sender-based filter is the only scope limiter. Consent architecture that does not name what categories will be imported before the user clicks "authorize" is consent architecture that is doing the least possible work.

**Recommendation:** Add a lightweight category preview step between OAuth and first import: after querying the inbox but before writing any records, show the user a breakdown of what was found by retailer and estimated category — "We found 87 Amazon orders, 24 App Store receipts, 12 Steam receipts — [proceed / exclude categories]." This is a UX addition that fits within the MVP scope and gives the user meaningful consent granularity without requiring the full category-filtering feature.

---

## Agent 3: fd-insurance-underwriting

**Source discipline:** Personal lines underwriting / actuarial analysis — behavioral data intake pipelines that convert observable signals into profile constructs; failure modes of proxy drift, feedback contamination, and sparse-history over-confidence.

---

### Finding 3.1

**Severity:** P1

**Title:** Gift purchases are imported as self-directed taste signals with no flagging mechanism

**Description:** An underwriter building a behavioral risk profile from purchase data must account for the systematic contamination of gift-buying seasons — December purchases for a household-of-four buyer look like the buyer's own preferences if the model does not separate gift orders from self-directed orders. The brainstorm explicitly defers gift detection to v2, but this means December holiday shopping, birthday gifts, and baby shower purchases will be weighted identically to self-directed purchases in the brand affinity and category distribution constructs. Unlike the return-handling deferral (which can be partially addressed by a sender denylist), gift detection requires data available in the MVP parse scope: Amazon order confirmations contain a "This is a gift" flag and can carry a shipping address distinct from the account billing address.

**Recommendation:** Extract the `is_gift` flag and shipping-address-matches-billing check from Amazon order confirmation HTML in the MVP parser (both fields are present in the structured HTML). Store them on the wardrobe entry. Do not exclude gift purchases from the wardrobe (the user may want to see what they gave), but pass `is_gift=true` to Auraken's preference model extraction so the context builder can discount or exclude gift signals from brand affinity and taste constructs. This is a parser-level addition that does not require the full v2 gift detection feature.

---

### Finding 3.2

**Severity:** P1

**Title:** Preference model constructs carry no confidence signal — sparse and dense histories treated identically

**Description:** An actuarial model that reports "probability of claim: 0.73" for a risk with 3 data points and for a risk with 3,000 data points without confidence intervals is not a model — it is a number generator. The brainstorm names four constructs Auraken will extract: taste, brand affinity, spending patterns, discovery context (owns-avoidance). None of these constructs have defined confidence representations based on observation count. A user with 8 Amazon purchases over 3 years will have a "brand affinity" construct that rests on 8 data points; a user with 400 purchases will have one that rests on 400. Auraken's recommendation logic will use both constructs identically, causing the sparse-history user to receive highly confident-sounding recommendations derived from what might be 3 purchases in a given brand.

**Recommendation:** Each extracted construct in Auraken's preference model must carry an `observation_count` and a `confidence_tier` (e.g., `low` < 10 observations, `medium` 10-50, `high` > 50). Downstream recommendation logic must discount or suppress construct-based recommendations when `confidence_tier = low`. This does not require a full actuarial confidence interval — a simple observation count threshold is sufficient for MVP and prevents the most egregious over-confidence failures.

---

### Finding 3.3

**Severity:** P2

**Title:** Email receipt timestamp used as purchase-date proxy — order-placed date is available and more accurate

**Description:** Underwriters analyzing spending rhythm from telematics or transaction data are meticulous about the distinction between event timestamp and reporting timestamp. An order confirmation email arrives 0-48 hours after the order is placed, and email client filters can batch emails into weekly digests. If Auraken extracts spending rhythm from the Gmail `received` timestamp rather than the order-placed date embedded in the Amazon confirmation HTML, a user whose email client batches Amazon emails into a weekly digest will show an artificial Sunday-purchase pattern. The order-placed date is available in the Amazon order confirmation HTML — it is not a future enrichment problem.

**Recommendation:** The Amazon parser must extract the order-placed date from the email HTML (the "Order placed" field in the confirmation), not use the Gmail `received` timestamp as the purchase date. For App Store and Steam, the email receipt date is the closest available proxy, but it should be labeled `receipt_date` rather than `purchase_date` to distinguish its provenance. Auraken's spending-rhythm extraction must use `purchase_date` where available and fall back to `receipt_date` with a lower confidence weight.

---

### Finding 3.4

**Severity:** P2

**Title:** Feedback loop between Auraken recommendations and imported purchase history is unacknowledged

**Description:** An actuarial model that is trained on data it helped generate is subject to feedback loop contamination — a well-known failure mode in usage-based insurance where recommended behaviors change behavior, which then reinforces the model's prior. Once Auraken uses purchase history to make recommendations, future purchases will be influenced by those recommendations. A user who buys a brand because Auraken suggested it will have that purchase reimported on the next pipeline run, reinforcing the brand affinity signal. The brainstorm does not acknowledge this loop, which means it is also not designed to be measurable or controllable.

**Recommendation:** Add a `recommendation_influenced` flag to wardrobe entries that can be set when a user acts on an Auraken recommendation. This is a future feature, but the data schema must support it now — a field added after the fact requires backfilling. In the interim, document the feedback loop in the preference model design notes so future work on construct validity starts from an acknowledged baseline rather than discovering it empirically when model drift is observed.

---

### Finding 3.5

**Severity:** P3

**Title:** Construct definitions are absent — "brand affinity" is operationally undefined

**Description:** An underwriting model that defines "homeowner" as "has a home insurance policy" is circular and produces nonsense when the observable doesn't match the intent. The brainstorm names "brand affinity" as a construct but does not define what operationalizes it: is it the number of orders from a brand? The total spend? The recency? Whether the brand appears in multi-category purchases? Without an explicit operational definition, two engineers implementing the preference model will produce two incompatible constructs that both label themselves "brand affinity."

**Recommendation:** Before implementation, write a one-paragraph operational definition for each extracted construct: what observable signals from the parsed email data are inputs, what the extraction algorithm computes, what the output represents, and what it explicitly does not represent (e.g., "brand affinity does not distinguish between self-directed and gift purchases in MVP — see is_gift flag"). These definitions belong in the Auraken preference model design doc, not in the brainstorm, but the brainstorm should reference that they exist before implementation begins.

---

## Agent 4: fd-data-journalism-source-verification

**Source discipline:** Data journalism / computational investigative reporting — multi-source document intake pipelines, cross-parser consistency, source-level audit trails, defense of published findings under legal challenge.

---

### Finding 4.1

**Severity:** P1

**Title:** Cross-parser output schema is not enforced — "price" from App Store and Amazon are semantically incompatible

**Description:** An investigative journalist building a multi-source database knows that the most dangerous inconsistencies are the ones that look consistent in the schema but diverge in semantics. If the Amazon parser extracts `price` as the per-unit cost in USD and the App Store parser extracts `price` as the total transaction amount including tax, the unified jawncloud wardrobe stores both as `price: Decimal` — schema-valid, semantically wrong. The App Store also has free apps, in-app purchases distinct from app purchases, and subscription renewals that may be reported differently than initial purchases. Steam has regional pricing. None of these cross-parser semantic contracts are defined in the brainstorm, which means each parser author will make independent decisions.

**Recommendation:** Define a canonical parser output schema with semantic contracts per field — not just types but meanings: `price` is defined as "unit price in USD, exclusive of tax, at time of order, for self-directed purchases; $0.00 for free items." Each parser must produce an output that satisfies this contract or emit a failure. Add a schema validation step between parser output and the `upsert_sku` call that rejects records that violate the semantic contract (e.g., `price < 0`, `price > 10000` without a flag, `currency != USD` without a conversion step).

---

### Finding 4.2

**Severity:** P1

**Title:** Template drift causes silent field extraction failure — partial parses succeed without alerting

**Description:** Data journalists who have run multi-source document pipelines for years know that template drift is not an edge case — it is a scheduled event. Amazon, Apple, and Steam update their transactional email templates with major platform releases. When the App Store changes where the price appears in its HTML (as it did with iOS 17's redesigned receipts), the parser extracts `price=None` for all new receipts. If the pipeline treats a parse that extracted name and date but not price as a success, it will write `price=None` to jawncloud and zero out the price signal in Auraken's spending-pattern model for all App Store purchases after the template change. The user sees N purchases imported with no error — but the price data is silently gone.

**Recommendation:** Define required fields per parser: for every retailer, which fields must be non-None for the record to be considered a valid parse. `price` is required for Amazon, App Store, Steam, and Kindle. A parse that produces name and date but `price=None` is a parse failure, not a partial success — it must go to the failure record store, not the wardrobe. Additionally, the post-import summary must surface per-parser null-rate statistics: if 18/24 App Store records have `price=None`, that is a visible anomaly regardless of whether the parser raised an exception.

---

### Finding 4.3

**Severity:** P1

**Title:** Category taxonomy is not canonical — cross-retailer aggregation produces meaningless constructs

**Description:** A data journalist aggregating across multiple source databases knows that collapsing non-equivalent categories under a shared label produces findings that look real but measure nothing. Amazon uses its own product taxonomy (Electronics, Books, Clothing, Health & Household). The App Store uses Apple's categories (Games, Productivity, Entertainment, Lifestyle). Steam uses its own genre tags (Action, RPG, Strategy). If each parser passes through the source taxonomy as `category` and Auraken's context builder aggregates across all four, "Entertainment: 45% of purchases" is a collision of three incompatible definitions of "Entertainment" — the construct is meaningless and the recommendation logic built on it will be structurally wrong.

**Recommendation:** Define a canonical Auraken category taxonomy before any parser is implemented (Physical/Digital, Functional/Entertainment, Recurring/One-time are examples of dimensions rather than leaf nodes). Each parser must map source categories to canonical categories at parse time, with unmapped categories going to `category=UNKNOWN` rather than passing through the source label. The mapping tables (Amazon taxonomy → Auraken taxonomy, App Store taxonomy → Auraken taxonomy) must be versioned alongside the parsers so that taxonomy updates can be applied retroactively.

---

### Finding 4.4

**Severity:** P2

**Title:** Source authentication is absent — forged order confirmation emails are trusted

**Description:** A data journalist receiving document tips knows that document authenticity must be verified before publication — provenance is not just knowing where a document came from but confirming it is what it claims to be. The pipeline trusts any email from a sender address in its allowlist without DKIM verification or SPF check. A user whose Gmail account has been compromised, or who has been targeted by a phishing email that mimics Amazon order confirmation format, could have forged purchases imported into their wardrobe and preference model. Gmail's API exposes message authentication headers; using them requires no additional OAuth scope.

**Recommendation:** After fetching each email via the Gmail API, check the `Authentication-Results` header for DKIM pass before passing the email body to the parser. Emails that fail DKIM verification for the expected sender domain should be logged as authentication failures and excluded from parsing. This is a low-cost addition (one header field check per message) and eliminates the spoofed-sender attack surface entirely.

---

### Finding 4.5

**Severity:** P2

**Title:** Processing order affects stateful constructs — oldest-first vs. newest-first is not specified

**Description:** A data journalist building a timeline-dependent dataset knows that processing order matters for any stateful derivation. The pipeline processes all available emails on each run, but the brainstorm does not specify ordering. Constructs like "first purchase date," "brand loyalty" (based on repeat-purchase sequences), and "spending rhythm" (based on inter-purchase intervals) are order-dependent: processing newest-first produces different intermediate states than processing oldest-first. On incremental re-runs (new emails since last import), the ordering relative to previously imported records also affects whether `upsert_sku` overwrites or preserves existing fields.

**Recommendation:** Specify in the parser design that emails are processed in ascending order by order-placed date (not Gmail received date — see Finding 3.3). Document this ordering invariant as a contract of the pipeline. Add a test case that processes the same email set in both orderings and asserts that stateful constructs (first-purchase-date, brand-loyalty-signal) are identical — this confirms the constructs are not accidentally order-dependent.

---

## Cross-Agent Summary

| Finding | Agent | Severity | Theme |
|---|---|---|---|
| Parse failures silently dropped | Forensic Accounting | P1 | Completeness |
| Brand normalization silent and irreversible | Forensic Accounting | P1 | Audit trail |
| Idempotency unverified at edge cases | Forensic Accounting | P2 | Correctness |
| Return emails imported as purchases | Forensic Accounting | P2 | Record integrity |
| Zero-results vs. search-error indistinguishable | Forensic Accounting | P3 | Gap detection |
| OAuth revocation does not delete imported data | Health Information | P1 | Consent/data rights |
| Post-import summary too coarse to surface errors | Health Information | P1 | Transparency |
| Item deletion does not cascade to preference model | Health Information | P2 | Data subject rights |
| Parser version not logged per record | Health Information | P2 | Longitudinal governance |
| Category opt-out absent from consent flow | Health Information | P3 | Consent granularity |
| Gift purchases contaminate taste signals | Underwriting | P1 | Signal validity |
| Sparse history constructs carry no confidence signal | Underwriting | P1 | Model calibration |
| Email timestamp used instead of order-placed date | Underwriting | P2 | Proxy accuracy |
| Recommendation feedback loop unacknowledged | Underwriting | P2 | Model contamination |
| Construct definitions absent | Underwriting | P3 | Specification clarity |
| Cross-parser semantic schema not enforced | Data Journalism | P1 | Schema integrity |
| Template drift causes silent partial parse | Data Journalism | P1 | Parser resilience |
| Category taxonomy not canonical | Data Journalism | P1 | Aggregation validity |
| Sender authentication absent | Data Journalism | P2 | Source authenticity |
| Processing order affects stateful constructs | Data Journalism | P2 | Determinism |

**P1 count: 8** — all blockable before first production import run.

The deepest cross-discipline agreement is on one structural gap: the pipeline lacks a layer between raw parse output and committed records that validates, logs, and surffaces anomalies before they propagate into jawncloud and Auraken's preference model. Forensic accountants call it a reconciliation step. Health information managers call it a completeness check. Underwriters call it construct validation. Data journalists call it source verification. It is the same missing layer.
