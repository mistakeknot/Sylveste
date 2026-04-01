---
artifact_type: prd
bead: sylveste-09h
stage: design
---
# PRD: intersite — GSV lab/portfolio/development surface

## Problem

GSV has no public site. interblog exists but has zero published posts and sits on a separate subdomain. Projects, experiments, and the dev panel have no web surface. The portfolio reads as disconnected repos rather than a coherent agency.

## Solution

A single Astro app at `generalsystemsventures.com` that folds in the blog, presents the project portfolio with lineage-based coherence, hosts short-form experiment entries, and provides a live xterm.js development panel for authenticated desktop sessions.

## Features

### F1: Astro app scaffold + Cloudflare Tunnel deploy
**What:** New `apps/intersite/` Astro app with Tailwind, MDX, Node adapter. Cloudflare Tunnel deployment on sleeper-service alongside interblog. Dark theme, Geist Sans/Mono. Clerk auth from day one.
**Acceptance criteria:**
- [ ] `apps/intersite/` builds and serves at `generalsystemsventures.com` via Cloudflare Tunnel
- [ ] Landing page with site lede, featured project tier (3-5 projects), project count, latest experiment
- [ ] Clerk integration included in initial scaffold (`@clerk/astro` in astro.config)
- [ ] Tunnel config in `~/.cloudflared/config.yml` on sleeper-service, systemd service with `Restart=on-failure` and `RestartSec=5s`
- [ ] `pnpm build && pnpm start` succeeds locally
- [ ] Contact mechanism in site footer (email link)

### F2: Project pages (template, roster, lineage)
**What:** Content collection for projects with a template that surfaces status, description, architecture, domain tags, and a `lineage` field connecting projects thematically. Sylveste is the parent page; pillars/plugins are subpages. Standalone projects get top-level pages.
**Acceptance criteria:**
- [ ] Project content collection schema with fields: name, status (active|shipped|dormant|early), domain, themes (controlled vocabulary: `emergent-systems`, `human-machine-interface`, `autonomous-agents`, `generative-media`, `infrastructure-tooling`), lineage (max 150 chars, tagline-length bridge to parent insight), featured (boolean), tagline, repo URL, description, what_was_learned (for dormant projects — frames exploration, not abandonment)
- [ ] `/projects/` index: featured tier (3-5 projects, full card treatment) above fold; full roster grid below with domain/status filters; dormant projects hidden by default with opt-in toggle
- [ ] `/projects/sylveste/` parent page with subpage links for all pillars and plugins
- [ ] `/projects/[slug]/` detail page rendering description, lineage, themes, status badge, domain tags
- [ ] All 13 standalone projects + Sylveste from the roster have content files (draft quality OK — content pipeline handles curation)
- [ ] Empty state for `/projects/` when no featured projects are published yet

### F3: Blog fold-in
**What:** Port interblog's content collections and layouts into intersite at `/blog/`. Configure `blog.generalsystemsventures.com` as a 301 redirect to `generalsystemsventures.com/blog/`. interblog plugin continues to own the editorial pipeline, writing to intersite's content directory.
**Acceptance criteria:**
- [ ] `/blog/` renders article index; `/blog/[slug]` renders individual posts
- [ ] interblog content collections copied (NOT symlinked) into intersite — one-way sync, no shared mutable state
- [ ] One-way sync trigger: when interblog advances a file to `published/`, post-write hook copies it into intersite content dir with `pipeline_state: mk_review` (mk must confirm in intersite context)
- [ ] Cloudflare DNS: `blog.generalsystemsventures.com` 301 → `generalsystemsventures.com/blog/`
- [ ] interblog plugin `skills/` updated to write to `apps/intersite/src/content/` paths via configurable `INTERSITE_CONTENT_ROOT` (not hardcoded path)
- [ ] RSS feed at `/blog/rss.xml`
- [ ] Empty state for `/blog/` renders intent placeholder, not empty grid
- [ ] Pipeline mapping table: interblog `draft` → `raw_draft`, interblog `review` → `texturaize_review`, interblog `send` → `mk_review`

### F4: Experiment entries
**What:** Short-form lab entries. Thing tried, result, optional screenshot. Rendered at `/experiments/`.
**Acceptance criteria:**
- [ ] Experiment content collection with fields: title, date, tags, result (success|failure|inconclusive), summary (1-2 sentences), body (MDX)
- [ ] `/experiments/` index page, reverse-chronological
- [ ] `/experiments/[slug]` detail page with result badge, date, body
- [ ] At least 3 seed experiments (can be retroactive from interlab campaigns); written as narratives, not test reports
- [ ] Empty state for `/experiments/` renders intent placeholder when no experiments are published

### F5: Content pipeline state machine
**What:** Explicit state machine for content lifecycle. States: `raw_draft → texturaize_review → voice_review → mk_review → published → archived`. Backward transition: `archived → mk_review` (must re-pass gates to republish). Frontmatter-driven, enforced by build-time Zod validation.
**Acceptance criteria:**
- [ ] All content collections (projects, experiments, articles) include `pipeline_state` and `mk_approved_at` frontmatter fields
- [ ] Build-time Zod validation: only `pipeline_state === "published"` content renders on production pages; `archived` explicitly excluded
- [ ] Single shared utility `getPublishedContent(collection)` — all production pages use it; no direct `getCollection()` calls in production pages
- [ ] Validation logic lives in `apps/intersite/` (build-time Zod schema). Plugins enforce legal transitions by convention, app enforces at build time. Documented as explicit seam in `apps/intersite/src/content/PIPELINE.md`
- [ ] Only mk (via `/intersite:publish` after review) can set `pipeline_state: published` — enforced by requiring `mk_approved_at` timestamp; build rejects `published` files without it
- [ ] `raw_draft` and `texturaize_review` content visible in dev/preview only; preview URLs gated by Clerk auth
- [ ] MDX import statements stripped by rehype plugin at build time — content files cannot execute arbitrary JS
- [ ] `archived → mk_review` backward transition allowed; `archived → published` disallowed

### F6: Dev panel v1 (xterm.js + WebSocket PTY relay)
**What:** Slide-out terminal panel on project pages. xterm.js in browser connects via WebSocket to a **separate relay service** (`apps/intersite-relay/`) on sleeper-service. Single-session, single-project, desktop-only. Clerk JWT auth verified at WebSocket upgrade.
**Acceptance criteria:**
- [ ] `apps/intersite/src/components/DevPanel.tsx` — xterm.js slide-out, client-only component
- [ ] **Separate service** at `apps/intersite-relay/` with own `package.json`, systemd unit, process lifecycle independent of Astro app
- [ ] Relay binds to `127.0.0.1` only (enforced in code, not just docs). Cloudflare Tunnel forwards to relay port
- [ ] Clerk JWT verified at HTTP 101 upgrade step using Clerk JWKS endpoint — not just token-exists check. Signed `relay_session_id` claim, 8-hour expiry
- [ ] Project slug resolved via static allowlist map (slug → absolute path) built at startup. Rejects unknown slugs with 400 before spawning
- [ ] PTY lifecycle: two-phase tracking (`spawning` → `active`). Cleanup attached to both phases. If socket closes during spawn, child process killed in spawn callback
- [ ] Disconnect grace period: 60-second reap timer on disconnect. Reconnect within window reattaches to existing PTY. Timer fires → PTY killed. No orphans
- [ ] Hard server-side PTY TTL of 4 hours regardless of activity
- [ ] Single-session enforcement: relay rejects second WebSocket connection per user with structured error ("session already active")
- [ ] Project navigation while session alive: relay detects working directory mismatch and presents choice (kill+respawn or keep current)
- [ ] Rate limiting on WebSocket upgrade using `CF-Connecting-IP` header; deny if header absent (request didn't come through Cloudflare)
- [ ] Panel trigger **not rendered in DOM** for unauthenticated sessions (Clerk session check at render time)
- [ ] Desktop-only: panel hidden on viewports < 1024px
- [ ] Panel displays "development panel temporarily unavailable" on WebSocket connection failure
- [ ] All PTY spawns/terminations logged with timestamp, Clerk user ID, source IP

### F7: Interverse plugin index
**What:** Grid index of all Interverse plugins at `/projects/sylveste/plugins/`. Notable plugins get detail pages; others are grid-only with name + one-liner.
**Acceptance criteria:**
- [ ] Plugin list sourced from `.claude-plugin/plugin.json` `description` field (canonical, machine-readable); fall back to CLAUDE.md first-line if plugin.json lacks description
- [ ] `/projects/sylveste/plugins/` grid page with search/filter
- [ ] Detail pages for plugins with explicit `notable: true` flag in CLAUDE.md frontmatter (not bead-count heuristic)
- [ ] Plugin count displayed on Sylveste parent page
- [ ] Manifest file (`apps/intersite/src/content/plugins/.manifest.json`) tracks generated slugs; deleted/renamed plugins cleaned up on regeneration

### F8: intersite plugin (editorial pipeline integration)
**What:** New Interverse plugin at `interverse/intersite/` that provides CLI commands for content generation, pipeline management, and deploy.
**Acceptance criteria:**
- [ ] `interverse/intersite/.claude-plugin/plugin.json` with plugin registration
- [ ] `/intersite:generate` command — auto-generates project page drafts from beads/git/CLAUDE.md. Uses interlock `reserve_files` on target content file to prevent concurrent generation races
- [ ] `/intersite:publish` command — delegates validation to `pnpm build` (app owns the gate, plugin owns the trigger). Implements atomic swap: build to `dist.next/`, smoke test (curl local port, expect HTTP 200), swap `dist/` → `dist.prev/`, `dist.next/` → `dist/`, restart service. Abort on smoke failure. Keep `dist.prev/` as one-step rollback
- [ ] `/intersite:status` command — shows content pipeline state across all collections
- [ ] CLAUDE.md and AGENTS.md for the plugin

## Non-goals

- Per-project token sponsorship (Stripe integration) — deferred to later phase
- Mobile dev panel — desktop-only for v1
- Concurrent terminal sessions — single-session for v1
- AI-generated text going live without mk review — hard constraint, not a feature
- Replacing interblog plugin — it stays as the editorial pipeline, just targets intersite's content directory

## Dependencies

- Cloudflare Tunnel access on sleeper-service (already configured for interblog)
- `generalsystemsventures.com` DNS on Cloudflare (use `CF_ZONE_ID` env var — do not hardcode in docs)
- interblog app (for content copy in F3 — one-way sync, not symlink)
- Texturaize bridge (for content pipeline — webhook must verify HMAC signature before writing files)
- interfluence voice profile (for voice review gate)

## Resolved Questions

1. **Auth for dev panel** — **Clerk.** No shared-secret fallback. Relay must not enter production without Clerk JWT verification. Matches interblog precedent; avoids split-auth debt.
2. **interblog migration strategy** — **Start fresh, copy content.** interblog's config is blog-specific; intersite needs different routing, layouts, and the relay. Content is copied (not symlinked) with one-way sync trigger.
3. **Plugin detail page threshold** — **`notable: true` flag** in CLAUDE.md frontmatter. Bead-count heuristic dropped.

## Architectural Decisions (from flux-drive review)

1. **Relay is a separate service.** `apps/intersite-relay/` with own package.json, systemd unit, and process lifecycle independent of Astro app. The Astro app holds only the xterm.js client component.
2. **Content is copied, not symlinked.** interblog and intersite have separate content directories. One-way sync trigger on interblog publish.
3. **Pipeline validation lives in the app.** `apps/intersite/` owns Zod schema validation at build time. Plugins enforce transitions by convention, app enforces at build time. Documented as explicit seam.
4. **Plugin publish delegates to app build.** `/intersite:publish` triggers `pnpm build`; if it fails (invalid pipeline states), publish aborts. Plugin owns "when," app owns "whether."
5. **Site identity is portfolio-first, workspace-second.** The dev panel is a genuine differentiator but invisible to visitors. The lede and landing page optimize for portfolio presentation.

## Recommended Epic Split (from architecture review)

The 8 features split into 3 independent tracks after F1:

| Epic | Features | Rationale |
|------|----------|-----------|
| **intersite-static** | F1, F2, F4, F7, F8 (generate+status) | Pure publishing surface, no external deps beyond tunnel |
| **intersite-blog-migration** | F3, F5 | Cross-module migration with interblog; explicit pipeline + mapping |
| **intersite-relay** | F6, F8 (publish) | Separate service, separate deployment, separate failure domain |

F1 is the shared prerequisite. intersite-static can ship without the blog fold-in or dev panel.
