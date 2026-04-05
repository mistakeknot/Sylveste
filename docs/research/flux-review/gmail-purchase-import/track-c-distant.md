---
track: C
track_name: Distant
agent_count: 4
date: 2026-04-05
target: docs/brainstorms/2026-04-05-gmail-purchase-import-brainstorm.md
---

# Track C — Distant Domain Review: Gmail Purchase Import Pipeline

---

## Agent 1: fd-venetian-glassblowing-batch-kiln

**Source domain:** Murano furnace batch management — founding, working, annealing phases, each requiring validated intermediate states before the next phase begins.

**Structural isomorphism:** Each transformation stage in the import pipeline (OAuth → Gmail API → HTML parse → brand match → MCP upsert → context extraction) is a furnace phase. Raw material (email HTML) must pass through exact temperature zones in sequence; skipping or rushing a phase produces a defective output that cannot be fixed downstream. The annealing insight is especially apt: bulk context injection is the thermal equivalent of plunging hot glass into cold water.

---

### Finding C1-1

**Severity:** P1

**Title:** No checkpoint/resume mechanism — mid-batch crash silently drops parsed work

**Description:** The brainstorm specifies "full history, no date cap" with "Gmail API quotas handled via batch processing with backoff," but describes no persistent checkpoint between the Gmail API query phase and the MCP upsert phase. A user with 8 years of Amazon orders may have several hundred email messages in a single batch run. If the pipeline crashes between parsing emails (step 3) and completing the interjawn MCP upserts (step 5), all parsed work in the in-flight batch is lost and the next run starts from the beginning. In Murano terms, this is a furnace explosion mid-founding: the molten charge is lost and the maestro must re-charge the furnace from raw silica. The brainstorm claims idempotency at the SKU level (via `upsert_sku`), but idempotency at the destination does not guarantee that the source scan restarts at the right position — without a watermark recording the last successfully processed email message ID, each restart re-scans from the top.

**Recommendation:** Add a per-import watermark table (or lightweight state file) that records the Gmail message ID of the last successfully upserted batch. On restart, query Gmail with `after:` the watermark timestamp. This is a one-row write per batch, not an architecture change.

---

### Finding C1-2

**Severity:** P1

**Title:** No phase-gate validation between HTML parse and brand matching — malformed parse propagates into jawncloud

**Description:** The data flow lists step 3 (parse email HTML) and step 4 (normalize brand names via fuzzy match) as sequential, but the brainstorm contains no specification of what a "failed parse" looks like or how it is handled before being handed to the brand matcher. In glass terms, introducing impure colorant into molten glass contaminates not just this batch but the crucible: a null product name or empty ASIN passed to `list_brands` for fuzzy matching can produce false positives that corrupt the brand catalog. Amazon changes its order confirmation template periodically; a parse that returns an empty string for product name is not obviously wrong — it might silently write a blank SKU. The pipeline needs an explicit validity gate between parse output and the brand-matching step, rejecting records that fail minimum completeness checks (non-empty name, parseable price, valid date).

**Recommendation:** Add a `ParseResult.is_valid()` guard before passing to brand normalization. Minimally: product name non-empty, price parseable as float, date parseable as ISO date. Invalid results go to a quarantine log, not to `upsert_sku`. One function, one conditional, one quarantine append.

---

### Finding C1-3

**Severity:** P2

**Title:** Bulk context injection risks preference model thermal shock — no annealing strategy specified

**Description:** The brainstorm defers context extraction (step 6: "extract purchase-pattern context → write to Auraken's preference/profile models") without specifying how a full-history import of potentially thousands of purchases is integrated. Writing all historical signal at once into the preference model produces a statistically noisy initial state: a user's 2016 electronics purchases carry equal weight to their 2026 ones unless temporal discounting is applied. The glass analogy is precise here — rapid temperature change shatters the object. A preference model seeded with undifferentiated 10-year history will produce recommendations dominated by the user's heaviest historical spend categories, which may no longer reflect current preferences.

**Recommendation:** Apply temporal decay at context-write time rather than at query time. A simple exponential decay keyed on `purchase_date` (e.g., half-life of 18 months) ensures that the initial model state is dominated by recent signal. This is a single multiplier on the contribution weight, not a model architecture change.

---

## Agent 2: fd-japanese-katagami-stencil-pattern-matching

**Source domain:** Ise katagami stencil cutting — intricate paper stencils that must be precise enough to reproduce patterns faithfully across hundreds of dyeing cycles while remaining resilient to repeated use, with the negative space (what is cut away) defining the pattern as much as what remains.

**Structural isomorphism:** Each retailer parser module is a stencil: it defines the negative space (what to ignore) and positive space (what to extract) in the email HTML. Amazon's quarterly template changes are equivalent to the fabric moving under the stencil — a rigid stencil tears; a resilient one accommodates small shifts. The "negative space" insight maps directly to the problem of emails that share sender addresses with real orders but are not orders (promotions, gift orders, cancellations).

---

### Finding C2-1

**Severity:** P1

**Title:** Parser stencils are described as DOM-path-based with no fallback — a single Amazon template change breaks all future order extraction

**Description:** The brainstorm notes that Amazon order confirmations use "consistent patterns" with "product name, ASIN, price, order date, quantity in predictable DOM locations," implying CSS class or DOM path selectors as the primary extraction strategy. Amazon has historically changed its email template format several times per year; the Kindle and digital order formats differ from physical orders. A stencil that relies on a single DOM path — for example, extracting ASIN from a specific `<td class="a-span9">` — fails silently when Amazon reorganizes the layout, producing empty ASIN fields that the phase-gate in C1-2 should catch but currently would not. Unlike a torn stencil which is visibly damaged, a broken CSS selector produces empty output that looks valid.

**Recommendation:** Implement a two-layer extraction strategy for each retailer: primary (CSS selector or XPath), fallback (regex on raw text for ASIN pattern `B[0-9A-Z]{9}`, price pattern, etc.). The fallback is the ito-ire silk thread reinforcement that holds the stencil together when the paper tears. If primary fails but fallback succeeds, log a parser-degraded warning so template drift is visible.

---

### Finding C2-2

**Severity:** P2

**Title:** Negative space undefined — promotional emails and cancellation confirmations share sender addresses with real orders

**Description:** The brainstorm identifies sender addresses (`auto-confirm@amazon.com`, `ship-confirm@amazon.com`, `digital-no-reply@amazon.com`) as the query filter, but Amazon sends promotional emails, order cancellations, return confirmations, and gift order notifications from overlapping sender domains. The stencil analogy reveals why this matters: a stencil that cuts positive space for "all Amazon email" includes the void space of non-purchase signals. A "Your order has been cancelled" email has the same sender as an order confirmation and similar DOM structure; a parser that extracts product name and price from it will create a wardrobe entry for a product the user does not own. The brainstorm explicitly defers return/refund detection to v2, but does not note that this means v1 will import cancellations as purchases.

**Recommendation:** Add subject-line filtering as a secondary gate alongside sender filtering. The subject patterns for Amazon order confirmations are stable (`Your Amazon.com order`, `Your order has been placed`). Cancellations and returns use distinct subject patterns and can be excluded with a blocklist. This is a single additional filter predicate in the Gmail API query, not a parser change.

---

### Finding C2-3

**Severity:** P2

**Title:** Fuzzy brand matching tolerance is uncalibrated — false merges and missed variants are equally likely

**Description:** Step 4 of the data flow specifies "normalize brand names (fuzzy-match against existing jawncloud brands via `list_brands`)" without specifying the matching algorithm, threshold, or test corpus. Katagami masters calibrate stencil cutting depth to the specific fabric weight — a threshold appropriate for cotton will tear silk. `Ralph Lauren` vs. `RALPH LAUREN` vs. `Polo Ralph Lauren` vs. `Lauren Ralph Lauren` are four distinct brand representations in retail data, some of which are the same brand and some of which are distinct product lines. An over-tight threshold (cosine similarity > 0.95) will create duplicate brand entries; an over-loose threshold (> 0.7) will merge `Nike` and `Nikko` or `Apple` (the company) with `Apple` (the fruit basket brand). Neither failure mode is visible in the v1 summary ("Found N purchases across M categories").

**Recommendation:** Establish a calibration test set of 20–30 brand name pairs (true positives: known variants of the same brand; true negatives: similar-looking different brands) before shipping fuzzy matching. Set the threshold to maximize F1 on this set. Store the threshold as a config value, not a hardcoded constant, so it can be tuned without a code change.

---

## Agent 3: fd-hanseatic-kontor-trade-ledger-privacy

**Source domain:** Hanseatic League Kontor factors managing foreign trading posts under limited, revocable charters — trade data kept under the Kontor's own jurisdiction while operating in foreign sovereign territory, with strict compartmentalization by privilege level.

**Structural isomorphism:** The Gmail OAuth consent is a charter: the user grants Auraken limited trading rights in Google's territory. The `gmail.readonly` scope is the broadest possible charter — access to all diplomatic correspondence, not just the purchase ledgers. The Kontor factor who reads the host city's dispatches loses the trading privilege permanently; Auraken accessing non-purchase email content faces the same revocation risk, now enforced by App Store review policies and GDPR.

---

### Finding C3-1

**Severity:** P0

**Title:** Charter overreach risk — `gmail.readonly` grants access to all email; pipeline discipline is the only enforcement

**Description:** The brainstorm correctly notes that `gmail.readonly` is the integration point and that the pipeline queries by sender address. However, the sender-address Gmail query filter is the only technical mechanism preventing the pipeline from touching personal correspondence, financial statements, medical records, or legal documents that happen to arrive from recognized domains. Gmail's query API (`from:auto-confirm@amazon.com`) does filter server-side, but if the query is ever broadened (e.g., to support a new retailer by temporarily querying all unread mail), the charter is silently violated. A Kontor factor who copies the host city's diplomatic letters has no way to un-copy them; similarly, once personal email content has transited Auraken's Python process memory, the data sovereignty violation has already occurred. There is no described circuit breaker, no audit of what the Gmail query actually returned vs. what was expected, and no test that would catch a query accidentally broadened.

**Recommendation:** Add a pre-processing assertion that validates every message retrieved matches an expected sender allowlist before any content is read. If a message passes the Gmail query but does not match the allowlist, log and discard without reading the body. This is the minimum technical enforcement of charter scope — one assert, not an architecture change. Also add a unit test that passes a non-purchase email through the pipeline and verifies it is discarded before parse.

---

### Finding C3-2

**Severity:** P1

**Title:** No audit trail — user cannot verify which emails were accessed or what was extracted

**Description:** The brainstorm specifies a post-import summary ("Found N purchases across M categories") but does not describe any persistent per-email audit log. In Kontor terms, the factor has completed a trading season, handed the merchant a summary invoice, but destroyed the original ledger entries. The merchant cannot verify whether the factor accessed only the purchase correspondence or also read the dispatch letters. For a product operating under `gmail.readonly` scope, the inability to produce an email-level access log is a trust and regulatory liability: GDPR Article 15 (right of access) requires the controller to be able to enumerate what personal data was processed, from which sources, and when. The aggregate summary satisfies none of this.

**Recommendation:** Write a per-import access log: `{import_id, message_id, sender, date, subject_hash, parse_outcome, upsert_outcome}`. Subject is hashed, not stored in plaintext, to avoid storing email content. This log serves as the ledger the user can inspect. It is also the data source for the checkpoint/resume mechanism in C1-1, so implementing it resolves two findings.

---

### Finding C3-3

**Severity:** P2

**Title:** Revocation incompleteness is undisclosed — revoking OAuth leaves imported data in place without user awareness

**Description:** The brainstorm states "User can explicitly share individual items or categories later" under privacy UX but does not address the case where the user revokes OAuth consent. The Hanseatic charter analogy is precise: the charter is revoked, but the copied ledgers remain in the Kontor's vault. Imported SKUs in jawncloud and purchase patterns in Auraken's profile models persist after OAuth revocation. This is not a bug — it is the correct behavior for a data import — but it must be explicitly disclosed at consent time. The current consent UX description ("opt-in consent at OAuth time + post-import summary") does not mention data persistence after revocation. A user who revokes access expecting their data to be deleted will find it is not.

**Recommendation:** Add a single sentence to the OAuth consent screen and the post-import summary: "Your imported purchase data is stored in [product] and remains available after you disconnect Gmail. You can delete it from Settings > Purchase History." This is a copy change, not an engineering change, but it must be in v1 before any user-facing launch.

---

### Finding C3-4

**Severity:** P2

**Title:** Sensitivity tiers are flat — purchase data, brand affinities, and spending patterns have different exposure risk profiles

**Description:** The brainstorm treats all imported data as "private by default" under a single privacy flag, but a Kontor factor knows that not all ledger entries carry the same risk: cargo manifests are less sensitive than credit terms, which are less sensitive than diplomatic correspondence. Purchase-level data (what you bought, when, price) is more sensitive than derived affinities (you seem to prefer mechanical keyboards); spending rhythm is more sensitive than either (you spend heavily in Q4, suggesting income patterns). Storing all three at the same sensitivity tier means a breach of the brand-affinity table also exposes raw purchase records, and a feature that shares brand preferences (a future "public wishlist") could inadvertently expose spending rhythm data if the access controls are not tiered.

**Recommendation:** Define three explicit storage tiers at schema design time: `raw_purchases` (highest sensitivity, never shareable), `derived_affinities` (medium, user-shareable), `spending_patterns` (high sensitivity, never shareable by default). Even if all three start as private, separating them at the schema level means future sharing features cannot accidentally cross tiers.

---

## Agent 4: fd-polynesian-wayfinding-dead-reckoning-context

**Source domain:** Micronesian etak non-instrument wayfinding — building a reliable position fix by integrating sparse signals (star bearings, swell patterns, bird flight paths, cloud reflections) over time, where no single signal is sufficient but the accumulation triangulates reliably. The navigator's model must handle missing signals, contradictory inputs, and long gaps between observations.

**Structural isomorphism:** Each purchase is a star sighting — a single data point that constrains but does not determine the user's position in preference space. Brand affinity, taste profile, and spending rhythm are the navigational position built by integrating these sightings over time. The etak system's key insight — that the navigator's reference frame moves, not the canoe — maps to the temporal weighting problem: the preference model's reference frame should be the present, making old purchases appear to recede rather than treating them as equivalent to recent ones.

---

### Finding C4-1

**Severity:** P1

**Title:** No temporal weighting specified — a 2016 purchase has equal influence to a 2026 purchase in the context model

**Description:** The brainstorm specifies "full history, no date cap" and "extract purchase-pattern context → write to Auraken's preference/profile models" but contains no specification of how purchase date affects contribution weight. A Polynesian navigator who gives equal weight to a star bearing taken three days ago and one taken this morning will calculate a position fix with large uncertainty; the older bearing carries useful information but must be discounted by the accumulated dead reckoning error. Without temporal weighting, a user who bought 20 video games in 2017 but has not bought a game since 2021 will have a preference model that strongly signals "gamer" — potentially overriding more recent signals from 2022–2026 showing a shift toward hardware and books. The recommendation system will recommend games to someone who has moved on.

**Recommendation:** Apply purchase-date decay at context extraction time (step 6). A half-life parameter (suggested starting value: 18 months, configurable) means a 2017 purchase contributes `weight * 0.5^((2026-2017)/1.5)` ≈ 0.6% of a 2026 purchase's weight. This is a single multiplier in the context extraction function, not a model architecture change. The half-life should be a config value to support future calibration.

---

### Finding C4-2

**Severity:** P2

**Title:** Brand affinity stored as opaque context — collapses multi-modal preferences into an undifferentiated signal

**Description:** The brainstorm describes "brand affinities" as a context output without specifying representation. The dead-reckoning analogy reveals the failure mode: a navigator who averages all their star sightings loses the information that some bearings were taken in calm water (high confidence) and others in heavy swell (low confidence). A user who buys both $15 earbuds and $350 over-ear headphones in the same year is not exhibiting a budget preference — they have context-dependent preferences (commute vs. studio). Collapsing this into a single "audio brand affinity" score loses the categorical context (budget/impulse vs. considered/premium) that makes the signal useful for recommendations. The brainstorm notes "impulse vs. considered purchases" as a pattern to detect, but does not connect this to how brand affinities are stored.

**Recommendation:** Store brand affinity as a (brand, category, price_tier, purchase_count, last_purchase_date) tuple rather than a scalar score. This preserves the multi-modal distribution and enables recommendations to ask "does the user want a premium audio product or a budget one?" rather than "does the user like audio products?" This is a schema decision that must be made before the first write; retrofitting it later requires a migration.

---

### Finding C4-3

**Severity:** P2

**Title:** No reference island — no mechanism to validate whether the context model is improving or drifting after initial import

**Description:** The etak navigator uses a known reference island (a fixed landmark) to calibrate accumulated dead reckoning error; without periodic recalibration against a fixed point, drift compounds silently. The pipeline's context model has no specified feedback loop or accuracy metric. After the initial full-history import, the preference model's quality is unknown: it might accurately represent the user's current tastes or it might be dominated by a concentrated historical spend that no longer reflects them. The brainstorm's discovery/recommendation use case depends on model quality, but v1 specifies no mechanism to measure recommendation relevance, detect model staleness, or alert when the model has not received new signal in an extended period.

**Recommendation:** Define a staleness threshold (e.g., if the most recent imported purchase is > 6 months old, mark the context model as "stale" and suppress confidence-dependent recommendations or surface a "refresh your purchase history" prompt). This is a single field (`context_last_updated`) and a staleness check in the recommendation query — not a model evaluation framework, but it prevents silent drift from degrading the product experience invisibly.

---

### Finding C4-4

**Severity:** P3

**Title:** Swell pattern detection (subscription and seasonal rhythm) deferred without a data preservation strategy

**Description:** Subscription tracking and seasonal buying pattern detection are listed as v2 open questions. The wayfinding analogy identifies a specific risk in this deferral: swell patterns (the regular, low-frequency oscillations that carry information about distant weather systems) must be observed over many cycles to be detected. If v1 stores only the final context output and not the raw purchase event stream with timestamps, the data needed to detect subscription patterns in v2 will be gone — the swell was occurring but the navigator was not recording it. The idempotent `upsert_sku` approach means re-importing emails in v2 is possible, but it assumes Gmail history is still available and the OAuth token is still active.

**Recommendation:** Ensure that the raw purchase event log (message_id, purchase_date, product_name, price, retailer) is preserved as a first-class artifact, not just as a side effect of the wardrobe import. This log is the substrate for all v2 pattern detection features. Storing it costs little; reconstructing it from re-import is fragile.
