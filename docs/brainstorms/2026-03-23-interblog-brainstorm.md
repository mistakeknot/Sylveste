---
artifact_type: brainstorm
bead: none
stage: discover
---

# interblog — Auto-Generating Engineering Blog with Editorial Workflow

**Date:** 2026-03-23

## What We're Building

An Interverse plugin (`interblog`) paired with an Astro static blog site that auto-generates engineering blog posts from the Sylveste ecosystem. Published at `blog.generalsystemsventures.com`. Three-party editorial pipeline:

1. **AI surfaces themes** — scans CASS sessions, beads, brainstorms, PHILOSOPHY.md changes, git activity to identify publishable engineering stories
2. **mk curates** — discusses surfaced themes with Claude Code, selects and shapes which stories to develop
3. **Claude Code drafts** — generates markdown blog posts with frontmatter
4. **Partner edits via Texturaize** — interblog POSTs draft to Texturaize API, partner receives session URL, edits with 5-pillar editorial pipeline and track changes, Texturaize webhooks the result back

**Portfolio goal:** Partner builds a body of editorial work on technical content — before/after diffs, editorial annotations, published posts — demonstrating the exact skills required for Anthropic's Engineering Editorial Lead role.

## Editorial Identity

**General Systems Ventures engineering blog × AI engineering journal** — systems thinking meets engineering practice, through mk's intellectual lens.

Influences: Flux Collective newsletter, Maggie Appleton's digital garden, Venkatesh Rao (Ribbonfarm/Breaking Smart), Alex Komoroske's systems thinking, Marshall McLuhan (media as environment), Joshua Meyrowitz (information environments).

Not "what we shipped" but "what we learned about complex systems by building autonomous software development infrastructure." Each post is a node in a larger intellectual framework — exploring emergence, feedback loops, agency, autonomy, and information architecture through the lens of real engineering work.

**Content mix:**
- **Deep-dives** (1/week) — "How multi-agent coordination mirrors immune system tolerance" — architectural decisions examined through systems thinking frameworks
- **Digests** (1-2/week) — "This week in the factory" — concise, pattern-oriented summaries of what changed and why it matters
- **Cadence:** 2-3 posts/week total

## Why This Approach

**Plugin + Astro** was chosen over a standalone Next.js app (overkill) and a minimal markdown repo (too bare for portfolio presentation).

- **Interverse plugin** integrates with existing CASS, beads, interpath, and interfluence infrastructure — no reinvention
- **Astro** is the industry standard for content-focused static sites (fast, markdown-native, minimal JS)
- **Texturaize API bridge** (POST + webhook callback) eliminates copy-paste friction with full round-trip
- **Layered disclosure** — some posts fully open-source (architecture, philosophy), others abstract sensitive details — editorial judgment per post
- **Separate GitHub repo** (`github.com/mistakeknot/interblog`), physically in `apps/interblog/` — same pattern as all Sylveste subprojects

## Key Decisions

### Content Pipeline

| Stage | Tool | Output |
|-------|------|--------|
| Theme surfacing | `/interblog:scan` skill | `themes.yaml` with ranked story candidates |
| Curation | `/interblog:pitch` skill | mk selects themes via Claude Code dialogue |
| Drafting | `/interblog:draft` skill | Markdown file in `apps/interblog/content/drafts/` |
| Editing | Texturaize API bridge (POST + webhook) | Partner edits in Texturaize editor |
| Publishing | Move to `content/published/` | Astro auto-deploys via Vercel |

### Theme Surfacing Sources

- **CASS sessions** — query for interesting patterns, debugging stories, architectural decisions
- **Beads** — recently closed work items with their themes, dependencies, lessons
- **Brainstorms** — `docs/brainstorms/` design documents (80+ existing)
- **PHILOSOPHY.md** — design bets and tradeoffs (when updated)
- **Git activity** — significant commits, new modules, cross-cutting changes
- **interpath artifacts** — changelogs, roadmaps, vision docs as narrative seeds

### Texturaize API Bridge

**POST + webhook callback model:**

```
POST texturaize.com/api/bridge/ingest
{
  "source": "interblog",
  "draft_id": "2026-03-23-multi-agent-review",
  "content": "# How Multi-Agent Coordination Mirrors...",
  "callback_url": "https://blog.generalsystemsventures.com/api/webhook/texturaize",
  "metadata": { "category": "deep-dive", "disclosure": "open" }
}

Response: { "session_url": "https://texturaize.com/edit/abc123" }
```

- Partner receives session URL (email notification or dashboard)
- Texturaize loads content into Tiptap editor, runs 5-pillar analysis
- Track changes + editorial annotations preserved
- On "Done editing" → webhook POSTs edited content back to interblog
- interblog writes edited markdown to `content/review/` for final approval

### Blog Architecture

```
apps/interblog/
├── .claude-plugin/        # Interverse plugin registration
│   └── plugin.json
├── skills/
│   ├── scan.md            # Theme surfacing
│   ├── pitch.md           # Curation dialogue
│   └── draft.md           # Post generation
├── content/
│   ├── drafts/            # AI-generated, awaiting editorial
│   ├── review/            # Returned from Texturaize, awaiting final approval
│   └── published/         # Ready for deployment
├── src/                   # Astro site
│   ├── layouts/
│   ├── pages/
│   └── components/
├── astro.config.mjs
└── package.json
```

### Deployment

- **Domain:** `blog.generalsystemsventures.com` (Cloudflare DNS, already owned)
- **Hosting:** Vercel (Astro static build)
- **DNS:** CNAME record in Cloudflare → Vercel
- **Auto-deploy:** Push to `content/published/` triggers Vercel rebuild

### Disclosure Levels (Frontmatter)

```yaml
---
title: "How Multi-Agent Coordination Mirrors Immune System Tolerance"
date: 2026-03-23
category: deep-dive          # or "digest"
disclosure: open              # open | abstracted | internal-only
sources:
  - type: brainstorm
    path: docs/brainstorms/2026-02-15-linsenkasten-flux-agents-brainstorm.md
  - type: bead
    id: Sylveste-xyz
tags: [multi-agent, coordination, systems-thinking, emergence]
status: draft                 # draft | review | published
---
```

### Voice and Tone

- Use interfluence to establish a blog-specific voice profile derived from mk's writing + systems thinking influences
- Essayistic, not tutorial — ideas explored through engineering specifics
- First person singular ("I") for essays, plural ("we") for project narratives
- Dense but accessible — assume technical literacy, explain conceptual frameworks
- Show the thinking, not just the decision — "the tension between X and Y led us to Z"
- Anti-patterns: no "leveraging", no "it's worth noting", no corporate hedging

### Portfolio Evidence Strategy

Each post generates three portfolio artifacts:
1. **Published post** — the final output on the live blog
2. **Track changes view** — Texturaize's before/after with editorial annotations (stored in Texturaize)
3. **Editorial rationale** — optional companion notes explaining editorial decisions (why restructured, what was cut, what was added for clarity)

### Backfill Strategy

Generate seed posts from strongest existing brainstorms, in close collaboration with mk to identify which themes are publishable. This bootstraps the portfolio with real content and gives the editor immediate material to work with.

### Visual Design

**Hybrid: Gwern structure + Flux Collective aesthetics.**

- Gwern's sidenotes and progressive disclosure (collapsible sections, footnotes as margin notes)
- Flux Collective's clean sans-serif minimalism (generous whitespace, monochrome + one accent)
- Influences: Gwern.net, read.fluxcollective.org, Maggie Appleton's digital garden
- Table of contents on deep-dives, estimated read time, clean typography hierarchy

### Distribution

- **RSS** — Astro native, zero effort
- **Newsletter** — Buttondown (markdown-native, free tier, minimal)
- Shows editorial distribution skill in portfolio

### Notifications

- Simple draft queue dashboard in interblog (partner checks when ready)
- Signal message in group chat when new drafts are ready

### Authentication

- API key auth for Texturaize bridge endpoint (rotatable, stored in env vars)
- Separate from Texturaize's user auth system

### Voice Profile

- New blog-specific interfluence voice profile
- Derived from mk's writing but tuned for systems-thinking-meets-engineering tone
- Informed by influences: Gwern, Flux Collective, Rao, Appleton, Komoroske, McLuhan, Meyrowitz

## Open Questions

1. **Buttondown integration** — Manual cross-post or auto-publish from RSS?
2. **Blog design implementation** — Custom Astro theme from scratch, or fork an existing Gwern-style template?
