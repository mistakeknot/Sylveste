# Flux-Drive Review Synthesis: interblog Implementation Plan

**Plan:** `docs/plans/2026-03-23-interblog.md`
**Agents:** architecture, safety, correctness, quality, user-product, integration
**Date:** 2026-03-23

## Verdict: REVISE BEFORE IMPLEMENTATION

The plan's editorial pipeline design and skill structure are sound. Three systemic issues must be resolved before any code is written:

---

## Critical Issues (Must Fix)

### 1. Texturaize Bridge Is Structurally Invalid
**Found by:** integration, correctness, safety
**Impact:** Tasks 9, 10 cannot compile or run

The bridge code was written against an assumed Texturaize schema, not the real one:
- Uses `createServerClient` (doesn't exist) — real export is `createClient`
- Uses raw Supabase `.from().insert()` — Texturaize is Drizzle ORM only
- Inserts into `documents` table with 4 invented columns, misses 2 required NOT NULL columns
- Reads `processed_content` which doesn't exist — edits are in `document_contents.output_text`
- `status: 'pending_review'` is not in the `processing_status` enum

**Fix:** Create a dedicated `bridge_documents` table with Drizzle schema. Use `createClient` and Drizzle queries. Read edited content from `document_contents.output_text` via join.

### 2. Content Directory Path Mismatch
**Found by:** architecture, correctness, quality, integration
**Impact:** Site builds with zero posts. Affects Tasks 1, 2, 3, 4, 5, 11, 12.

Plan creates `content/` at project root. Astro 5 resolves collections from `src/content/`. The `content.collections` config key doesn't exist in Astro 5. Webhook writes to wrong path. Publish command moves files to wrong directory.

**Fix:** Move all content directories to `src/content/drafts/`, `src/content/review/`, `src/content/published/`. Update all references.

### 3. Vercel Serverless Cannot Write Files
**Found by:** architecture, safety, correctness, user-product
**Impact:** Task 11 webhook silently loses all edited content.

`writeFile` on Vercel serverless has ephemeral, read-only filesystem. Written files vanish between invocations. The webhook returns 200 but content is lost.

**Fix:** Replace filesystem write with GitHub Contents API commit to the repo. Vercel redeploys from the new commit.

### 4. Path Traversal in Webhook Receiver
**Found by:** safety, quality
**Impact:** Arbitrary file write via crafted `draft_id`.

`draft_id: "../../src/pages/index"` overwrites any file. `path.join` resolves `..` components.

**Fix:** `basename(draft_id)` + allowlist regex `[a-zA-Z0-9_-]` before any path construction.

### 5. SSRF via Stored `callback_url`
**Found by:** safety
**Impact:** Credential exfiltration. Texturaize server fetches attacker-controlled URL with API key in Authorization header.

**Fix:** Validate `callback_url` against origin allowlist at ingest time + before fetch. Consider eliminating by having interblog poll instead of accepting push.

### 6. Tailwind v4 Integration Wrong
**Found by:** quality
**Impact:** Build fails immediately.

`@astrojs/tailwind` only supports Tailwind v3. Need `@tailwindcss/vite` as a Vite plugin.

**Fix:** Replace `pnpm add @astrojs/tailwind` with `pnpm add @tailwindcss/vite`. Use `vite: { plugins: [tailwindcss()] }` in config.

---

## High-Priority Issues

### 7. Partner's Role Is Copy Editor, Not Editorial Lead
**Found by:** user-product
The Anthropic role requires story elicitation, editorial strategy, publish decisions. Current plan puts the partner in a receive-and-polish role only.

**Fix:** Give partner the publish gate (her approval required). Consider partner access to pitch/angle selection.

### 8. Portfolio View Doesn't Exist
**Found by:** user-product
No designed surface to present before/after diffs, editorial rationale, content strategy to a hiring manager.

**Fix:** Add editorial portfolio page stub to the plan.

### 9. First Post Is Task 14 — Too Late
**Found by:** user-product
Partner needs evidence in days. Backfill and voice profile are last in sequence.

**Fix:** Move backfill to Task 2. First manually-drafted post within the first week.

### 10. Single API Key Both Directions
**Found by:** architecture, safety, correctness, quality, integration
One key authenticates both interblog→Texturaize and Texturaize→interblog. Compromise breaks everything.

**Fix:** Split into `INTERBLOG_SUBMIT_KEY` and `INTERBLOG_WEBHOOK_SECRET` (HMAC-SHA256).

### 11. No Callback Retry Logic
**Found by:** correctness
Callback fails → edited content stuck in Texturaize forever. No retry, no `callback_failed` status.

**Fix:** Bounded retry with backoff + `callback_failed` status.

### 12. Dashboard Is Build-Time Only
**Found by:** correctness, quality, user-product
`readdirSync` runs at deploy time. Counts never update until next push.

**Fix:** Server-render with `prerender = false`, or replace with Supabase query.

---

## Medium Issues

| # | Issue | Found by |
|---|-------|----------|
| 13 | `rawContent` doesn't exist in Astro 5 — reading time always `?` | correctness, quality |
| 14 | Draft skill conflates generation with Texturaize delivery | architecture |
| 15 | Webhook overwrites on duplicate `draft_id` — no idempotency | correctness |
| 16 | `INTERBLOG_BRIDGE_API_KEY` missing from Vercel env — all callbacks 401 | correctness |
| 17 | exec.yaml `repo` key non-standard — cross-repo tasks run in wrong dir | correctness |
| 18 | Only `published` collection declared — no schema for drafts/review | correctness |
| 19 | Sidenotes need JS alignment — CSS grid approach won't work | quality, correctness |
| 20 | Dashboard publicly accessible — leaks draft filenames | safety |
| 21 | `cass search --fast-only` likely invalid flag | quality |
| 22 | Raw MDX in curl JSON body breaks on quotes/newlines | quality, correctness |
| 23 | Scan→pitch→draft is 3 attention gates before partner sees anything | user-product |
| 24 | Texturaize bridge assumes features that may not exist for bridge docs | user-product |

---

## Recommended Plan Revision Order

1. **Validate Texturaize capabilities first** — run a manual session to confirm track-changes and annotations work for bridge-ingested documents
2. **Redesign Texturaize bridge** — new `bridge_documents` table, Drizzle schema, correct imports, proper column mapping
3. **Fix content paths** — everything under `src/content/`
4. **Fix Tailwind v4 integration** — `@tailwindcss/vite`
5. **Replace webhook filesystem write** — GitHub Contents API
6. **Reorder tasks** — backfill first, partner gets content within week 1
7. **Add partner decision gates** — publish approval, angle selection access
8. **Add portfolio page** — editorial evidence presentation surface
9. **Split API keys** — separate inbound/outbound secrets
10. **Add security guards** — path traversal sanitization, SSRF origin allowlist, HMAC webhook verification
