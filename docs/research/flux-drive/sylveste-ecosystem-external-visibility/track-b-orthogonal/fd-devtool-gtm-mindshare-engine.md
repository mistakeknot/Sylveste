# Track B — Devtool GTM / Mindshare Engine

> Lens: Stripe / Vercel / Linear / Supabase / Railway playbook. Practitioner developers, 15-minute aha, docs-as-marketing.
> Target: Sylveste ecosystem external-visibility review.
> Date: 2026-04-16.

## TL;DR

Sylveste has the infrastructure of a devtool but none of the GTM surface. `install.sh` is curl-pipe-able (good — matches the Railway/Supabase pattern). But above the install line, the README asks a practitioner to absorb 5 pillars, 58 plugins, three brands, and a 7-step workflow before they can imagine what it does. There is no `docs.sylveste.*`, no public changelog at repo root (`CHANGELOG.md` does not exist), no hero demo pinned in the README above the fold, no screenshotable artifact. The `/clavain:project-onboard` command is the closest to a 15-minute-aha primitive, but a cold HN visitor cannot reach it without installing Claude Code first AND running the monorepo bootstrap. Stage 2 should deep-dive the orchestration (L2) layer — specifically Clavain — because it is the one pillar with a pre-existing demo narrative ("route -> brainstorm -> ship") that can be compressed to a single demo GIF and a 15-minute quickstart.

## Findings

### F1 [P0] — No public-facing docs site exists, and the monorepo README is a research index

**Where it lives:** `README.md` is 114 lines of architecture, install, troubleshooting. No `docs.sylveste.io`, no `sylveste.dev`, no Docusaurus/mkdocs/fumadocs build. The monorepo `docs/` has 362 plans, 239 brainstorms, 160 PRDs (counted via `ls | wc -l`) — a research archive, not a docs surface. `docs/guide-power-user.md` is good content but lives inside the repo, not at a URL you can tweet.

**Why it fails the devtool-GTM bar:** Stripe got adoption via `stripe.com/docs`. Supabase via `supabase.com/docs`. Vercel via `vercel.com/docs`. Every category-defining infra devtool has a polished docs site as the first contact surface — not a GitHub README. A HN visitor who lands on `github.com/mistakeknot/Sylveste`, sees "5 pillars / 58 plugins / 3 layers", and scrolls to find the aha path will bounce in under 30 seconds. The README's architecture table (README.md lines 76-85) with five GitHub links to different sub-repos is a "read the codebase" invitation, which is a devtool-GTM anti-pattern.

**Failure scenario:** A senior engineer reads "Every action produces evidence, evidence earns authority" on a colleague's Slack. They click through, land on the monorepo README, see the pillar list, skim the install section, and close the tab. No quickstart, no demo, no docs site — the mindshare window closed.

**Fix (smallest viable, in sequence):**
1. Register `sylveste.dev` or `sylveste.io`. 30 minutes, $12/year.
2. Stand up a minimum-viable fumadocs/Docusaurus site with 5 pages: Quickstart / What is Sylveste / Clavain Tutorial / Plugin Reference / Philosophy. Can reuse `docs/guide-power-user.md` as the Quickstart spine. 1-2 weeks.
3. The README becomes 50 lines: pitch, install command, link to docs site, link to Clavain demo GIF, license. Strip everything else.

### F2 [P1] — No hero demo artifact exists above the fold

**Where it lives:** `README.md` "What you get" section (line 42) is a bulleted feature list. No embedded GIF, no Asciinema cast, no `docs/demo.md`, no YouTube link, no tweet-sized claim. `docs/guide-power-user.md` describes the workflow in prose but shows no output. The interactive ecosystem diagram link (README.md line 90) is listed but not embedded as a screenshot.

**Why it fails the devtool-GTM bar:** Stripe's 7-line payment demo is the hero. Vercel's `vercel` command produces a deploy URL in 15 seconds — that is the demo. Linear's "cmd+K" Figma-quality screenshot is the demo. Sylveste has Clavain's bead-claim sweep, Flux's multi-agent review, the `/clavain:route` -> `/clavain:brainstorm` -> `/clavain:ship` arc — any of these is a legitimate hero demo, but none is polished, screenshottable, embedded above the fold. The [interactive ecosystem diagram](https://mistakeknot.github.io/interchart/) is closer to a demo than anything else currently surfaced — but it is a link, not an embedded artifact, and it shows architecture complexity rather than user value.

**Failure scenario:** A conference speaker wants to cite Sylveste in a talk. They need a single screenshot or 10-second GIF. They have nothing to paste. The mention never happens.

**Fix:** Pick ONE hero demo and polish it to a 15-second terminal cast. Candidate: `/clavain:route` running against a fresh-onboarded project, classifying complexity, and auto-dispatching a brainstorm. Record with `vhs` (Asciinema) as `docs/assets/clavain-route-demo.gif`. Embed in README.md above the "Quick start" heading. This is 1 day of work.

### F3 [P1] — The 15-minute-aha path is gated on four preconditions

**Where it lives:** `install.sh` requires `jq`, `Go 1.22+`, `git` (README.md lines 17-19). After install, user must have Claude Code installed (not mentioned in README's prerequisites but required to run `/clavain:project-onboard`). After that, they must `/clavain:project-onboard` in their own project. After that, they must run `/clavain:route` and have something actually work.

**Why it fails the devtool-GTM bar:** Supabase's aha is one curl to `api.supabase.com/new` -> working Postgres in 90 seconds. Railway's aha is `railway up` -> deployed in 60 seconds. Sylveste's aha requires: (1) install Claude Code, (2) install Sylveste, (3) have a project, (4) understand enough to not break the onboard flow. That is 4 gates before value. Each gate compounds the bounce rate multiplicatively.

**Failure scenario:** A Python developer with no Claude Code account reads "autonomous software development agency" and runs `install.sh`. The installer succeeds. They open a project. Nothing happens because Claude Code isn't installed. They blame Sylveste. The drop-off is silent and untracked.

**Fix:** Create a zero-precondition demo path. Candidate: ship a `sylveste-demo` subcommand that runs a canned brainstorm->plan->review cycle against a fixed fixture project, using whatever models the user has configured, producing a `demo-output/` directory in under 5 minutes. This gives a cold visitor something to see before they've committed to Claude Code + onboarding. This is 2-3 weeks of polish on top of existing primitives.

### F4 [P2] — Changelog-as-narrative is entirely internal

**Where it lives:** No `CHANGELOG.md` at repo root (confirmed via `ls CHANGELOG*` — no matches). `docs/brainstorms/` has 239 files. `docs/plans/` has 362 files. `docs/handoffs/` has dated session handoffs. These are internal artifacts. Plugins each have their own `plugin.json` version strings but no unified public changelog.

**Why it fails the devtool-GTM bar:** Linear's changelog is their #1 marketing surface — monthly, dated, narrative, with screenshots and GIFs. Vercel's changelog is embedded in the dashboard AND on the blog. Supabase's changelog doubles as a release-notes feed. Sylveste ships features continuously (v0.6.236 per the ecosystem snapshot) but has no public-facing narrative. The flywheel that turns development into mindshare — "every ship is a marketing moment" — is missing entirely.

**Failure scenario:** A developer who tried Sylveste 3 months ago and bounced has no way to discover that the feature they were missing now exists. The second-chance conversion never fires.

**Fix:** Create `CHANGELOG.md` at repo root AND a monthly blog-style update at `docs/releases/YYYY-MM.md`. Linear-style: 1 screenshot, 2-4 paragraphs, 5-10 bullets of specifics. Auto-generate the first draft from recent beads + commit history — curate by hand. Cadence: once a month, matched to minor version bumps.

### F5 [P2] — Brand trinity (Sylveste / Garden Salon / Meadowsyn) is a 10-second explainer problem

**Where it lives:** `MISSION.md` line 5 says "Two brands, one architecture" then names three. README.md mentions only Sylveste. `apps/Meadowsyn/CLAUDE.md` still labels itself "Demarch AI factory" (line 3 — stale). `PHILOSOPHY.md` "Brand Registers" section enforces layer-boundary discipline but this is internal guidance, not user-facing narrative.

**Why it fails the devtool-GTM bar:** Linear didn't split into "Linear + Linear Design Salon." Vercel didn't ship "Vercel + Edge Salon + Preview Meadowsyn." Devtool GTM demands brand clarity in under 10 seconds. "Sylveste is the infrastructure, Garden Salon is the app, Meadowsyn is the dashboard" is three concepts to hold before the reader has even decided whether they care. At pre-1.0 stage with no external users, this is premature brand proliferation.

**Failure scenario:** A journalist writes about the project. They pick one brand to lead with. The other two become footnotes. Whichever they pick, two-thirds of the narrative leaks out.

**Fix (choose one):**
- **Option A:** Collapse to "Sylveste" as the single brand for the next 12 months. Garden Salon becomes "Sylveste Workspace" (product-mode suffix). Meadowsyn becomes "Sylveste Dashboard" (surface-mode suffix). Revisit at v1.0.
- **Option B:** Keep the three brands but relegate Garden Salon and Meadowsyn to "experimental" or "coming soon" — they are pre-M1 per the Capability Mesh; treat them like that externally.
- Either way, update README.md to pick one. Do not lead with all three.

### F6 [P2] — Install flow has no production-path signal

**Where it lives:** `install.sh` supports `--update`, `--uninstall`, `--dry-run` (good). README.md line 23: "Install takes ~2 minutes (power user) or ~30 minutes (full platform). Disk: ~2 GB core, ~5 GB with all plugins." No pricing page, no hosted-offering mention, no "production path" copy.

**Why it fails the devtool-GTM bar:** Even 100% OSS devtools like Supabase and Railway signal seriousness via a pricing page that explains the production path. A cold visitor asks "is this a real thing or a research project?" A pricing page (even if tier 1 is "free forever, self-host") answers that question. The current README reads as a research monorepo — which is accurate but discourages practitioner adoption.

**Failure scenario:** A CTO evaluating agent platforms needs to justify time investment. Without a pricing/production signal, Sylveste reads as "someone's side project" and gets filtered out in the shortlist stage.

**Fix:** Add one line to README.md under the pitch: "Open source, self-hostable today. Hosted Sylveste coming 2026 — [waitlist](#)." This is a signal, not a commitment. Swap to real link when ready.

## Layer-for-Stage-2 Recommendation

**Stage 2 should deep-dive the ORCHESTRATION (L2) layer** — specifically Clavain + its companion plugins.

Rationale:
1. Clavain is the one pillar with a narrative shape already ("route -> brainstorm -> strategize -> plan -> execute -> review -> ship") that compresses to a 15-second demo GIF.
2. `docs/guide-power-user.md` is already a near-publishable quickstart — it just needs a docs-site wrapper and a demo asset above the fold.
3. `/clavain:project-onboard` is the 15-minute-aha primitive — deep-diving the onboarding experience, not the kernel internals, is the leverage point.
4. The kernel (Intercore) is too abstract for practitioner-developers; the plugin ecosystem (Interverse, 58 plugins) is too diffuse. Clavain sits at the right altitude — opinionated enough to be memorable, concrete enough to demo.
5. The README.md already treats Clavain as the headline ("Sylveste is the platform behind Clavain, a self-improving Claude Code agent rig") — aligning Stage 2 with this framing avoids rewriting the brand narrative.

## Concrete Actions

1. **Ship a docs site at `sylveste.dev`** (1-2 weeks). Minimum viable: 5 pages (Quickstart, What is Sylveste, Clavain Tutorial, Plugin Reference, Philosophy). Reuse `docs/guide-power-user.md` as Quickstart. This single move fixes F1, partially fixes F3, and creates a home for F4's public changelog.

2. **Record a Clavain hero demo GIF and embed above the fold in README** (1-2 days). Candidate: `/clavain:route` on a fresh project producing a brainstorm artifact. Record via `vhs`. Commit as `docs/assets/clavain-hero.gif`. Insert in README.md line 7 (above "Quick start"). Tweet it from @mistakeknot on ship day.

3. **Create `CHANGELOG.md` at repo root + commit to monthly `docs/releases/YYYY-MM.md` cadence** (1 day to bootstrap, 2-4 hours/month to maintain). Start with April 2026 retrospective. This turns existing ship velocity into a mindshare engine rather than invisible work.

## Decision-Lens Self-Check

If a senior practitioner lands on Sylveste via HN today, do they reach an aha moment in under 15 minutes? **No.** They cannot even reach a decision to try it in under 15 minutes — the README is an architecture document, not a landing page. After F1+F2+F3 are shipped? **Yes** — a docs site + hero demo + zero-precondition demo command produces a polished devtool surface that matches the Supabase/Railway/Linear bar.
