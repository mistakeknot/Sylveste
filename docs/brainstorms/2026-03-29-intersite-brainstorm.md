---
artifact_type: brainstorm
bead: sylveste-09h
stage: discover
---

# intersite: GSV lab/portfolio/development surface

## What We're Building

A single site at `generalsystemsventures.com` that replaces the current blog subdomain and serves as GSV's public presence: projects, experiments, articles, and a live development surface where new ideas can be sketched and built using Claude Code in a browser side panel.

### Content types

1. **Projects** — each major project gets a page. Auto-generated from beads/git/filesystem, then curated through Texturaize/interfluence before publishing. No AI-generated text goes live without mk's review.
2. **Experiments** — short-form lab entries. Thing tried, result, maybe a screenshot.
3. **Articles** — folded in from interblog. Same editorial pipeline (scan, pitch, draft, send, Texturaize review, partner publish gate). Lives at `/blog/`.
4. **Sketches** — hardware and software ideas that don't exist yet. The site is where they get developed interactively.

### Project roster

**Sylveste** (parent page, subpages for all pillars/plugins):
- Clavain, Skaffen, Ockham, Zaka, Alwe (os/)
- Intercore, Intermute (core/)
- Autarch, Intercom, Meadowsyn, interblog (apps/)
- All 54+ Interverse plugins (interverse/)

**Standalone projects:**
- texturaize — AI-assisted editorial SaaS
- Typhon — prediction market toolkit
- Horza — FLUX cover photo gen + LoRA
- Enozo — macOS Core Audio enhancement
- pattern-royale — persistent CA battlefield (shipped)
- Nartopo — narrative topology engine
- agmodb — AI model comparison database (shipped)
- Auraken — voice-first AI recommendation platform
- shadow-work — Claude Code configuration + game interaction
- elf-revel — browser elven colony sim with DF-depth
- Lowbeer — macOS battery-aware CPU throttling
- garden-salon — multiplayer human-agent CRDT workspace
- duellm — Flow-Lenia AI dueling arena

Early/dormant/private is fine. The point is coherent reach across domains.

### Live development panel

WebSocket terminal relay: browser opens an xterm.js panel that connects to a Claude Code process on sleeper-service. Context-aware — opening the panel from a project page pre-loads that project's directory.

Architecture:
- xterm.js in the browser (side panel, slide-out)
- Custom WebSocket server on sleeper-service spawning/managing Claude Code PTY sessions
- Authenticated (session token, not open to public)
- Cloudflare Tunnel for transport (dev.generalsystemsventures.com or same domain)

This makes the site a live workspace — not just showing work, but a place where work happens.

### Audience

Both technical peers and potential sponsors/partners. Dense enough for engineers, accessible enough for non-technical visitors who want to understand what's being built and why.

## Why This Approach

**One site, not two.** interblog has zero published posts. No reason for a separate subdomain. The editorial pipeline (interblog plugin) stays — it just writes to intersite's content directory.

**Auto-generate, then curate.** Project pages start from beads/git/CLAUDE.md data. mk edits them through Texturaize/interfluence to ensure voice consistency. Nothing AI-generated goes live unreviewed.

**Astro + xterm.js WebSocket.** Astro handles static/SSR content well. The dev panel is a custom xterm.js + WebSocket relay — more work than ttyd but fully integrated (shares auth, context-aware per project page).

**Show breadth.** Including early/dormant projects signals coherent vision across domains. The site grows with the work rather than waiting for things to be "done."

## Key Decisions

1. **Fold interblog into intersite.** blog.generalsystemsventures.com 301s to /blog/. One app, one deploy, one tunnel.
2. **Sylveste subpages.** All pillars and plugins are subpages of /projects/sylveste/, not top-level project pages.
3. **Sponsorship deferred.** Get the site up first. Add per-project token sponsorship (Stripe, receipts) in a later phase.
4. **Custom xterm.js relay.** Not ttyd, not claude.ai embed. Custom WebSocket server for full integration.
5. **No AI text without review.** Auto-generation is for drafts. Everything goes through Texturaize + mk's voice profile before publish.
6. **Domain: generalsystemsventures.com.** Already on Cloudflare. New tunnel endpoint.

## Open Questions

1. **Dev panel auth** — session tokens via Clerk? Simple shared secret? How to prevent unauthorized access to a Claude Code shell on sleeper-service?
2. **Project page template** — what does a project page actually look like? Status badge, description, architecture diagram, active beads, recent commits? Reference: ACRNM product pages.
3. **Experiment format** — how short? Tweet-length with a screenshot? Or more like a lab notebook entry with methods/results?
4. **interblog migration** — does the existing Astro app become the base for intersite, or start fresh and port content collections?
5. **Interverse plugin pages** — all 54+ get individual pages, or a grid/index with detail pages only for notable ones?
6. **Mobile** — does the dev panel even make sense on mobile, or is it desktop-only?
