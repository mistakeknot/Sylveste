---
artifact_type: plan
bead: none
stage: design
---
# interblog Implementation Plan (v2 — Post Flux-Drive Review)

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none
**Goal:** Build an auto-generating engineering blog at blog.generalsystemsventures.com with a 3-party editorial pipeline (AI surfaces → mk curates → Claude Code drafts → partner edits via Texturaize).

**Architecture:** Interverse plugin (`apps/interblog/`) with Astro 5 static site, deployed to Vercel. Skills (`scan`, `pitch`, `draft`, `send`) surface themes and generate posts. Texturaize API bridge (POST + webhook) handles the editorial round-trip via a dedicated `bridge_documents` Drizzle table. Gwern sidenotes + Flux Collective minimalist aesthetic.

**Tech Stack:** Astro 5, TypeScript, `@tailwindcss/vite` (NOT `@astrojs/tailwind`), MDX, Vercel, Cloudflare DNS, Buttondown, interfluence voice profiles

**Prior review:** `.claude/flux-drive-output/fd-synthesis-interblog.md` — 6-agent review, 24 findings addressed in this revision.

---

## Changes from v1

| v1 Issue | v2 Fix |
|----------|--------|
| Content at `content/` root | Moved to `src/content/` (Astro 5 native) |
| `@astrojs/tailwind` (v3 only) | `@tailwindcss/vite` as Vite plugin |
| `output: 'hybrid'` for webhook | `output: 'static'` + standalone Vercel API function |
| Webhook writes files to Vercel | GitHub Contents API commit via Octokit |
| Bridge uses raw Supabase client | Drizzle ORM with new `bridge_documents` table |
| `createServerClient` import | `createClient` from `@/lib/supabase/server` |
| `processed_content` column | Read from `document_contents.output_text` |
| Single shared API key | Split: `INTERBLOG_SUBMIT_KEY` + `INTERBLOG_WEBHOOK_SECRET` (HMAC) |
| Draft skill sends to Texturaize | Separated into `/interblog:send` skill |
| Path traversal in draft_id | `basename()` + allowlist regex |
| SSRF via callback_url | Origin allowlist validation |
| Backfill at Task 14 | Moved to Task 2 (partner gets content week 1) |
| Partner is copy editor only | Partner owns publish gate + angle selection |
| No portfolio view | Added editorial portfolio page |
| Dashboard is build-time SSG | Local-dev only (removed from Vercel deploy) |
| No callback retry | Bounded retry with `callback_failed` status |
| Sidenotes CSS grid broken | JS alignment script on DOMContentLoaded |
| `rawContent` (removed in Astro 5) | Compute `readingTime` in draft skill |
| `cass --fast-only` invalid flag | Changed to `--mode fast` |

---

## Must-Haves

**Truths:**
- mk can run `/interblog:scan` and see ranked story candidates
- mk can run `/interblog:draft` and get a post written to `src/content/drafts/`
- mk can run `/interblog:send` and POST a draft to Texturaize, receiving a session URL
- Partner can open session URL in Texturaize, see 5-pillar analysis + track changes
- Partner can accept/reject hunks, the final content returns via webhook
- Partner can approve a post for publishing (she owns the publish gate)
- Published posts render at blog.generalsystemsventures.com with sidenotes
- RSS feed auto-publishes to Buttondown newsletter

**Artifacts:**
- `apps/interblog/.claude-plugin/plugin.json` — valid Interverse plugin
- `apps/interblog/skills/{scan,pitch,draft,send}/SKILL.md` — pipeline skills
- `apps/interblog/src/content/config.ts` — Astro content collections (drafts, review, published)
- `apps/interblog/src/layouts/Post.astro` — post layout with sidenotes
- `apps/interblog/api/webhook/texturaize.ts` — standalone Vercel serverless function
- `texturaize: apps/web/src/db/schema.ts` — `bridgeDocuments` Drizzle table
- `texturaize: apps/web/src/app/api/bridge/ingest/route.ts` — bridge endpoint
- `src/content/themes.yaml` — scan output (contracted shape)
- `src/content/briefs/*.yaml` — pitch output (contracted shape)

**Key Links:**
- Draft skill writes frontmatter matching all three content collection schemas
- `send` skill POSTs JSON matching bridge endpoint's expected shape
- Bridge creates `bridge_documents` row + triggers Texturaize processing pipeline
- Callback reads `document_contents.output_text` for edited content
- Webhook commits to repo via GitHub API → Vercel redeploys

---

### Task 1: Scaffold Astro Project + Plugin Registration

**Files:**
- Create: `apps/interblog/package.json`
- Create: `apps/interblog/astro.config.mjs`
- Create: `apps/interblog/tsconfig.json`
- Create: `apps/interblog/.claude-plugin/plugin.json`
- Create: `apps/interblog/CLAUDE.md`
- Create: `apps/interblog/src/content/drafts/.gitkeep`
- Create: `apps/interblog/src/content/review/.gitkeep`
- Create: `apps/interblog/src/content/published/.gitkeep`
- Create: `apps/interblog/src/content/briefs/.gitkeep`

**Step 1: Initialize Astro project**
```bash
cd /home/mk/projects/Sylveste/apps
pnpm create astro@latest interblog -- --template minimal --typescript strict --install --no-git
```

**Step 2: Add dependencies**
```bash
cd /home/mk/projects/Sylveste/apps/interblog
pnpm add @astrojs/mdx @astrojs/rss @astrojs/sitemap @tailwindcss/vite tailwindcss @octokit/rest
```

Note: `@tailwindcss/vite` NOT `@astrojs/tailwind` — the Astro integration only supports Tailwind v3.

**Step 3: Configure Astro**
```javascript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://blog.generalsystemsventures.com',
  output: 'static',
  vite: { plugins: [tailwindcss()] },
  integrations: [mdx(), sitemap()],
});
```

`output: 'static'` — the blog is fully static. The webhook lives as a standalone Vercel API function outside Astro.

**Step 4: Create plugin.json**
```json
{
  "name": "interblog",
  "version": "0.1.0",
  "description": "Auto-generating engineering blog — surfaces themes from Sylveste ecosystem, generates drafts, bridges to Texturaize for editorial review.",
  "author": { "name": "mistakeknot" },
  "license": "MIT",
  "keywords": ["blog", "editorial", "content", "engineering", "systems-thinking"],
  "skills": [
    "./skills/scan",
    "./skills/pitch",
    "./skills/draft",
    "./skills/send"
  ],
  "commands": [
    "./commands/scan.md",
    "./commands/pitch.md",
    "./commands/draft.md",
    "./commands/send.md",
    "./commands/publish.md"
  ]
}
```

**Step 5: Create content directories and CLAUDE.md**

Create `.gitkeep` files in `src/content/{drafts,review,published,briefs}/`.

Write `CLAUDE.md`:
```markdown
# interblog

Engineering blog for General Systems Ventures. Published at blog.generalsystemsventures.com.

## Structure
- `skills/` — scan, pitch, draft, send (pipeline stages)
- `src/content/drafts/` — AI-generated posts awaiting editorial
- `src/content/review/` — returned from Texturaize, awaiting partner's publish approval
- `src/content/published/` — deployed to production via Vercel
- `src/content/briefs/` — post briefs from pitch skill
- `src/content/themes.yaml` — surfaced theme candidates
- `src/` — Astro site (layouts, pages, components)
- `api/` — standalone Vercel serverless functions (webhook receiver)

## Editorial Pipeline
1. `/interblog:scan` → surfaces themes from CASS, beads, brainstorms
2. `/interblog:pitch` → mk (or partner) shapes theme into brief
3. `/interblog:draft` → generates markdown post to src/content/drafts/
4. `/interblog:send` → POSTs draft to Texturaize bridge
5. Partner edits in Texturaize (track changes, 5-pillar analysis)
6. Webhook callback → GitHub API commit to src/content/review/
7. Partner approves → move to src/content/published/ → Vercel deploys

## Partner owns the publish gate
The partner decides when a reviewed post is ready to publish.
```

**Step 6: Commit**
```bash
git add apps/interblog/
git commit -m "feat(interblog): scaffold Astro project + plugin registration"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 2: First Post — Manual Backfill for Immediate Portfolio Evidence

**Files:**
- Create: `apps/interblog/src/content/published/2026-03-24-building-an-ai-factory.mdx`

**Rationale:** The partner needs editorial material NOW, not after 14 tasks. Write one strong seed post manually from existing brainstorms. The partner edits this directly in Texturaize's web UI (no bridge needed yet) while the rest of the pipeline is built.

**Step 1: Select brainstorm and draft**

In collaboration with mk, select the strongest brainstorm for the first post. Candidates:
- Multi-agent code review system
- Sprint resilience and recovery
- Plugin architecture and the composition bet
- Token-efficient skill loading

Write a 1500-2000 word deep-dive post as MDX with proper frontmatter.

**Step 2: Write frontmatter**
```yaml
---
title: "<selected title>"
date: 2026-03-24
category: deep-dive
disclosure: open
description: "<1-2 sentence summary>"
tags: [<relevant tags>]
sources:
  - type: brainstorm
    path: docs/brainstorms/<selected>.md
readingTime: 8
---
```

**Step 3: Partner begins editing**

Partner copies the raw markdown into Texturaize's existing web editor (paste workflow). This produces the first portfolio artifact immediately — no bridge required.

**Step 4: Commit**
```bash
git add apps/interblog/src/content/published/
git commit -m "feat(interblog): first seed post for editorial portfolio"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/src/content/published/2026-03-24-*.mdx`
  expect: exit 0
</verify>

---

### Task 3: Content Collection Schema

**Files:**
- Create: `apps/interblog/src/content/config.ts`

**Step 1: Define all three content collections**

```typescript
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const postSchema = z.object({
  title: z.string(),
  date: z.coerce.date(),
  category: z.enum(['deep-dive', 'digest']),
  disclosure: z.enum(['open', 'abstracted', 'internal-only']),
  description: z.string(),
  tags: z.array(z.string()).default([]),
  sources: z.array(z.object({
    type: z.enum(['brainstorm', 'bead', 'session', 'commit', 'philosophy']),
    path: z.string().optional(),
    id: z.string().optional(),
  })).default([]),
  readingTime: z.number(),
});

const drafts = defineCollection({
  type: 'content',
  schema: postSchema.extend({ status: z.literal('draft').default('draft') }),
});

const review = defineCollection({
  type: 'content',
  schema: postSchema.extend({ status: z.literal('review').default('review') }),
});

const published = defineCollection({
  type: 'content',
  schema: postSchema.extend({ status: z.literal('published').default('published') }),
});

export const collections = { drafts, review, published };
```

All three collections share a base schema but enforce correct `status` per directory. A draft in `published/` is a build error, not a silent inclusion.

`readingTime` is required (not optional) — the draft skill must compute it.

**Step 2: Commit**
```bash
git add apps/interblog/src/content/config.ts
git commit -m "feat(interblog): content collection schemas for drafts, review, published"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 4: Post Layout with Sidenotes + Base Styles

**Files:**
- Create: `apps/interblog/src/layouts/Post.astro`
- Create: `apps/interblog/src/components/Sidenote.astro`
- Create: `apps/interblog/src/components/TableOfContents.astro`
- Create: `apps/interblog/src/styles/global.css`
- Create: `apps/interblog/src/pages/[...slug].astro`

**Step 1: Create global styles**

Gwern sidenotes + Flux minimalism. Same CSS as v1 plan but with sidenote positioning via JavaScript (not CSS grid column escape — children can't leave their parent's grid column).

```css
/* src/styles/global.css */
@import 'tailwindcss';

:root {
  --color-text: #1a1a1a;
  --color-text-secondary: #666;
  --color-accent: #2563eb;
  --color-bg: #fafaf9;
  --color-border: #e5e5e5;
  --content-width: 640px;
  --sidenote-width: 240px;
  --sidenote-gap: 2rem;
}

body {
  font-family: 'Inter', system-ui, -apple-system, sans-serif;
  color: var(--color-text);
  background: var(--color-bg);
  line-height: 1.7;
  -webkit-font-smoothing: antialiased;
}

/* Content container with room for sidenotes */
.post-wrapper {
  max-width: calc(var(--content-width) + var(--sidenote-gap) + var(--sidenote-width) + 2rem);
  margin: 0 auto;
  padding: 2rem 1rem;
  position: relative;
}

.post-content {
  max-width: var(--content-width);
}

/* Sidenotes — absolutely positioned to right margin on desktop */
@media (min-width: 1100px) {
  .sidenote {
    position: absolute;
    right: 0;
    width: var(--sidenote-width);
    font-size: 0.85rem;
    color: var(--color-text-secondary);
    line-height: 1.5;
    border-left: 2px solid var(--color-border);
    padding-left: 1rem;
    /* top is set by JS to align with sidenote-ref */
  }
}

/* Mobile: sidenotes inline */
@media (max-width: 1099px) {
  .sidenote {
    font-size: 0.85rem;
    color: var(--color-text-secondary);
    background: #f5f5f4;
    padding: 0.75rem 1rem;
    border-left: 3px solid var(--color-accent);
    margin: 1rem 0;
  }
}

h1 { font-size: 2rem; font-weight: 700; line-height: 1.2; margin-bottom: 0.5rem; }
h2 { font-size: 1.5rem; font-weight: 600; margin-top: 2.5rem; margin-bottom: 1rem; }
h3 { font-size: 1.25rem; font-weight: 600; margin-top: 2rem; margin-bottom: 0.75rem; }

a { color: var(--color-accent); text-decoration: underline; text-underline-offset: 2px; }
a:hover { text-decoration-thickness: 2px; }

code {
  font-family: 'JetBrains Mono', 'Fira Code', monospace;
  font-size: 0.9em;
  background: #f0f0f0;
  padding: 0.1em 0.3em;
  border-radius: 3px;
}

pre {
  background: #1e1e1e;
  color: #d4d4d4;
  padding: 1.25rem;
  border-radius: 6px;
  overflow-x: auto;
  font-size: 0.85rem;
  line-height: 1.5;
  margin: 1.5rem 0;
}

blockquote {
  border-left: 3px solid var(--color-border);
  padding-left: 1rem;
  color: var(--color-text-secondary);
  margin: 1.5rem 0;
}

hr { border: none; border-top: 1px solid var(--color-border); margin: 2.5rem 0; }
```

**Step 2: Create Sidenote component**
```astro
---
// src/components/Sidenote.astro
interface Props { id: string; }
const { id } = Astro.props;
---
<span class="sidenote-ref"><sup>{id}</sup></span>
<aside class="sidenote" data-sidenote-id={id}>
  <sup>{id}</sup> <slot />
</aside>
```

**Step 3: Create Post layout with sidenote JS alignment**
```astro
---
// src/layouts/Post.astro
import '../styles/global.css';
import TableOfContents from '../components/TableOfContents.astro';

interface Props {
  frontmatter: {
    title: string;
    date: Date;
    category: string;
    description: string;
    readingTime: number;
    tags: string[];
  };
  headings: { depth: number; slug: string; text: string }[];
}

const { frontmatter, headings } = Astro.props;
const dateStr = new Date(frontmatter.date).toLocaleDateString('en-US', {
  year: 'numeric', month: 'long', day: 'numeric'
});
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{frontmatter.title} — GSV Engineering</title>
  <meta name="description" content={frontmatter.description} />
  <link rel="alternate" type="application/rss+xml" title="GSV Engineering Blog" href="/rss.xml" />
</head>
<body>
  <header class="max-w-[640px] mx-auto px-4 pt-8 pb-4">
    <a href="/" class="text-sm text-gray-500 no-underline hover:text-gray-700">← GSV Engineering</a>
  </header>

  <div class="post-wrapper">
    <article class="post-content">
      <header class="mb-8">
        <h1>{frontmatter.title}</h1>
        <div class="text-sm text-gray-500 flex gap-3 items-center">
          <time datetime={frontmatter.date.toISOString()}>{dateStr}</time>
          <span>·</span>
          <span>{frontmatter.category}</span>
          <span>·</span>
          <span>{frontmatter.readingTime} min read</span>
        </div>
      </header>

      {frontmatter.category === 'deep-dive' && headings && (
        <TableOfContents headings={headings} />
      )}

      <slot />
    </article>
  </div>

  <footer class="max-w-[640px] mx-auto px-4 py-8 border-t border-gray-200 text-sm text-gray-500">
    <div class="flex justify-between">
      <span>General Systems Ventures</span>
      <a href="/rss.xml">RSS</a>
    </div>
  </footer>

  <!-- Gwern-style sidenote alignment -->
  <script>
    function alignSidenotes() {
      if (window.innerWidth < 1100) return;
      document.querySelectorAll('.sidenote-ref').forEach(ref => {
        const sup = ref.querySelector('sup');
        if (!sup) return;
        const id = sup.textContent;
        const note = document.querySelector(`.sidenote[data-sidenote-id="${id}"]`);
        if (!note) return;
        const refTop = ref.getBoundingClientRect().top + window.scrollY;
        const wrapperTop = document.querySelector('.post-wrapper')?.getBoundingClientRect().top + window.scrollY || 0;
        (note as HTMLElement).style.top = `${refTop - wrapperTop}px`;
      });
    }
    document.addEventListener('DOMContentLoaded', alignSidenotes);
    window.addEventListener('resize', alignSidenotes);
  </script>
</body>
</html>
```

**Step 4: Create dynamic post page**
```astro
---
// src/pages/[...slug].astro
import { getCollection } from 'astro:content';
import Post from '../layouts/Post.astro';

export async function getStaticPaths() {
  const posts = await getCollection('published');
  return posts.map(post => ({
    params: { slug: post.slug },
    props: { post },
  }));
}

const { post } = Astro.props;
const { Content, headings } = await post.render();
---
<Post frontmatter={post.data} headings={headings}>
  <Content />
</Post>
```

**Step 5: Create TableOfContents** (same as v1, omitted for brevity)

**Step 6: Commit**
```bash
git add apps/interblog/src/
git commit -m "feat(interblog): post layout with Gwern sidenotes (JS-aligned) + Flux styles"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 5: Index Page + RSS Feed

Same as v1 Tasks 4 + 5 combined. Index page lists published posts (filtered by `disclosure !== 'internal-only'`), RSS endpoint via `@astrojs/rss`. No changes needed from v1 beyond the `readingTime` field being required.

**Commit:** `feat(interblog): index page + RSS feed`

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 6: Skills — Scan + Pitch + Draft

**Files:**
- Create: `apps/interblog/skills/{scan,pitch,draft}/SKILL.md`
- Create: `apps/interblog/commands/{scan,pitch,draft}.md`

Same as v1 Tasks 6-8 with these corrections:

**Scan skill:** Replace `cass search ... --fast-only` with `cass search ... --mode fast --json` (valid flag).

**Pitch skill:** Add note that partner can also run `/interblog:pitch` to propose angles — not mk-only. This demonstrates "story elicitation" skill for the Anthropic application.

**Draft skill changes:**
- Remove Step 5 (Texturaize POST) — moved to separate `send` skill
- `readingTime` is required: compute as `Math.ceil(wordCount / 250)` and include in frontmatter
- Write to `src/content/drafts/` (not `content/drafts/`)
- Output file path: `src/content/drafts/<date>-<slug>.mdx`

**Commit:** `feat(interblog): scan, pitch, draft skills`

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/scan/SKILL.md`
  expect: exit 0
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/draft/SKILL.md`
  expect: exit 0
</verify>

---

### Task 7: Send Skill — POST Draft to Texturaize

**Files:**
- Create: `apps/interblog/skills/send/SKILL.md`
- Create: `apps/interblog/commands/send.md`

**Step 1: Write the send skill**

```markdown
<!-- apps/interblog/skills/send/SKILL.md -->
---
name: send
description: POST a draft to Texturaize for editorial review. Separate from drafting to ensure idempotency — running draft twice doesn't create duplicate Texturaize sessions.
---

# interblog: Send to Texturaize

## Step 1: Select Draft

List drafts in `src/content/drafts/`:
```bash
ls apps/interblog/src/content/drafts/*.mdx 2>/dev/null
```

Use AskUserQuestion to let mk select which draft to send.

## Step 2: Check for Existing Session

Read the draft's frontmatter. If `texturaize_session_url` is already set, warn:
"This draft was already sent to Texturaize at <url>. Send again? (creates a new session)"

## Step 3: Send to Bridge

Read the draft file content. Extract the slug from the filename.

```bash
CONTENT=$(cat "src/content/drafts/<selected>.mdx")
SLUG=$(basename "<selected>.mdx" .mdx)

# Use jq to safely construct JSON (handles quotes, newlines, code blocks)
jq -n \
  --arg content "$CONTENT" \
  --arg slug "$SLUG" \
  --arg callback "https://blog.generalsystemsventures.com/api/webhook/texturaize" \
  '{
    source: "interblog",
    draft_id: $slug,
    content: $content,
    callback_url: $callback
  }' | curl -s -X POST https://texturaize.com/api/bridge/ingest \
    -H "Authorization: Bearer $INTERBLOG_SUBMIT_KEY" \
    -H "Content-Type: application/json" \
    -d @-
```

## Step 4: Record Session URL

Update the draft's frontmatter to include `texturaize_session_url: <url>` (idempotency guard).

Report the session URL to mk for forwarding to partner via Signal.
```

**Commit:** `feat(interblog): send skill — POST draft to Texturaize bridge`

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/send/SKILL.md`
  expect: exit 0
</verify>

---

### Task 8: Texturaize Bridge — Drizzle Schema + Ingest Endpoint

**Files (in Texturaize repo: `/home/mk/projects/texturaize`):**
- Modify: `apps/web/src/db/schema.ts` — add `bridgeDocuments` table
- Create: `supabase/migrations/YYYYMMDD_bridge_documents.sql`
- Create: `apps/web/src/app/api/bridge/ingest/route.ts`

**Step 1: Add bridge_documents Drizzle schema**

Add to `apps/web/src/db/schema.ts`:

```typescript
// Bridge documents — external content sent for editorial review
export const bridgeDocuments = pgTable('bridge_documents', {
  id: uuid('id').defaultRandom().primaryKey(),
  // Link to main documents table after processing
  documentId: uuid('document_id').references(() => documents.id),
  source: text('source').notNull(), // e.g., "interblog"
  draftId: text('draft_id').notNull(),
  callbackUrl: text('callback_url').notNull(),
  callbackStatus: text('callback_status').default('pending'), // pending | sent | failed
  metadata: jsonb('metadata').default({}),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  updatedAt: timestamp('updated_at').defaultNow().notNull(),
});
```

**Step 2: Create migration**
```sql
-- supabase/migrations/YYYYMMDD_bridge_documents.sql
CREATE TABLE IF NOT EXISTS bridge_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id UUID REFERENCES documents(id),
  source TEXT NOT NULL,
  draft_id TEXT NOT NULL,
  callback_url TEXT NOT NULL
    CHECK (callback_url LIKE 'https://blog.generalsystemsventures.com/%'),
  callback_status TEXT DEFAULT 'pending',
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- RLS: only accessible via service role (bridge API key auth, not user session)
ALTER TABLE bridge_documents ENABLE ROW LEVEL SECURITY;
-- No user-facing policies — bridge endpoints use service role
```

**Step 3: Create ingest endpoint**

```typescript
// apps/web/src/app/api/bridge/ingest/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/db';
import { bridgeDocuments, documents, documentContents } from '@/db/schema';
import { eq } from 'drizzle-orm';
import { createClient } from '@/lib/supabase/server';
import crypto from 'crypto';

const SUBMIT_KEY = process.env.INTERBLOG_SUBMIT_KEY;
const ALLOWED_CALLBACK_ORIGINS = ['https://blog.generalsystemsventures.com'];

function isAllowedCallbackUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return ALLOWED_CALLBACK_ORIGINS.includes(parsed.origin)
      && parsed.pathname.startsWith('/api/webhook/');
  } catch { return false; }
}

export async function POST(req: NextRequest) {
  // Guard: key must be configured
  if (!SUBMIT_KEY) {
    return NextResponse.json({ error: 'Bridge not configured' }, { status: 503 });
  }

  // API key auth
  const authHeader = req.headers.get('authorization');
  const providedKey = authHeader?.replace('Bearer ', '') || '';
  if (!crypto.timingSafeEqual(
    Buffer.from(providedKey),
    Buffer.from(SUBMIT_KEY)
  )) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  let body: any;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }

  const { source, draft_id, content, callback_url } = body;

  if (!source || !draft_id || !content) {
    return NextResponse.json(
      { error: 'Missing required fields: source, draft_id, content' },
      { status: 400 }
    );
  }

  // SSRF prevention: validate callback_url
  if (callback_url && !isAllowedCallbackUrl(callback_url)) {
    return NextResponse.json(
      { error: 'callback_url must be from an allowed origin' },
      { status: 400 }
    );
  }

  // Sanitize draft_id
  const safeDraftId = draft_id.replace(/[^a-zA-Z0-9_-]/g, '-');

  // Get or create bridge workspace (service account)
  // TODO: create a dedicated bridge workspace during setup
  const bridgeWorkspaceId = process.env.INTERBLOG_WORKSPACE_ID;
  if (!bridgeWorkspaceId) {
    return NextResponse.json({ error: 'Bridge workspace not configured' }, { status: 503 });
  }

  const wordCount = content.split(/\s+/).filter(Boolean).length;

  // Create document record (same as normal Texturaize flow)
  const [doc] = await db.insert(documents).values({
    workspaceId: bridgeWorkspaceId,
    title: safeDraftId,
    inputWordCount: wordCount,
    inputFormat: 'md',
    processingStatus: 'pending',
    processingSettings: {
      edit_aggressiveness: 'light',
      specificity_target: 'medium',
      voice_lock: 'strict',
      terminology_lock: { protected_terms: [], do_not_change_spans: [] },
      structure_permission: 'keep_order',
    },
  }).returning({ id: documents.id });

  // Store content
  await db.insert(documentContents).values({
    documentId: doc.id,
    inputText: content,
    outputText: '', // filled by processing pipeline
  });

  // Create bridge record for callback tracking
  await db.insert(bridgeDocuments).values({
    documentId: doc.id,
    source,
    draftId: safeDraftId,
    callbackUrl: callback_url || '',
    callbackStatus: 'pending',
  });

  // TODO: Trigger processing pipeline (same as /api/process)
  // For now, the document is created and can be opened in the editor

  const sessionUrl = `${process.env.NEXT_PUBLIC_APP_URL}/edit/${doc.id}`;

  return NextResponse.json({
    session_url: sessionUrl,
    document_id: doc.id,
  });
}
```

**Step 4: Add env vars**
```
INTERBLOG_SUBMIT_KEY=<generated-key>
INTERBLOG_WORKSPACE_ID=<bridge-workspace-uuid>
```

**Step 5: Commit (in Texturaize repo)**
```bash
cd /home/mk/projects/texturaize
git add apps/web/src/db/schema.ts apps/web/src/app/api/bridge/ supabase/migrations/
git commit -m "feat: bridge API — bridge_documents table + ingest endpoint for interblog"
```

<verify>
- run: `cd /home/mk/projects/texturaize && pnpm build`
  expect: exit 0
</verify>

---

### Task 9: Texturaize Bridge — Callback Sender

**Files (in Texturaize repo):**
- Create: `apps/web/src/app/api/bridge/callback/route.ts`

**Step 1: Create callback sender with retry + idempotency**

```typescript
// apps/web/src/app/api/bridge/callback/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/db';
import { bridgeDocuments, documents, documentContents } from '@/db/schema';
import { eq } from 'drizzle-orm';
import crypto from 'crypto';

const WEBHOOK_SECRET = process.env.INTERBLOG_WEBHOOK_SECRET;

export async function POST(req: NextRequest) {
  // Internal endpoint — triggered when partner clicks "Done editing"
  const { document_id } = await req.json();

  // Find bridge record
  const bridge = await db.query.bridgeDocuments.findFirst({
    where: eq(bridgeDocuments.documentId, document_id),
  });

  if (!bridge) {
    return NextResponse.json({ error: 'Not a bridge document' }, { status: 404 });
  }

  // Idempotency: don't fire twice
  if (bridge.callbackStatus === 'sent') {
    return NextResponse.json({ status: 'already_sent' }, { status: 200 });
  }

  if (!bridge.callbackUrl) {
    return NextResponse.json({ error: 'No callback URL' }, { status: 400 });
  }

  // Get edited content from document_contents
  const content = await db.query.documentContents.findFirst({
    where: eq(documentContents.documentId, document_id),
  });

  const editedContent = content?.outputText || content?.inputText || '';

  // HMAC signature for webhook verification
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const payload = JSON.stringify({
    draft_id: bridge.draftId,
    edited_content: editedContent,
    source: bridge.source,
    metadata: bridge.metadata,
    document_id,
  });
  const signature = crypto
    .createHmac('sha256', WEBHOOK_SECRET || '')
    .update(`${timestamp}.${payload}`)
    .digest('hex');

  // Bounded retry (3 attempts, exponential backoff)
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) {
      await new Promise(r => setTimeout(r, 1000 * Math.pow(2, attempt)));
    }
    try {
      const res = await fetch(bridge.callbackUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Interblog-Signature': signature,
          'X-Interblog-Timestamp': timestamp,
        },
        body: payload,
      });
      if (res.ok) { lastError = null; break; }
      lastError = new Error(`HTTP ${res.status}`);
    } catch (e) { lastError = e as Error; }
  }

  // Update status
  const newStatus = lastError ? 'failed' : 'sent';
  await db.update(bridgeDocuments)
    .set({ callbackStatus: newStatus, updatedAt: new Date() })
    .where(eq(bridgeDocuments.documentId, document_id));

  if (lastError) {
    console.error('Bridge callback failed:', lastError.message);
    return NextResponse.json({ error: 'Callback failed after retries' }, { status: 502 });
  }

  return NextResponse.json({ status: 'sent' });
}
```

**Step 2: Commit (in Texturaize repo)**
```bash
cd /home/mk/projects/texturaize
git add apps/web/src/app/api/bridge/callback/
git commit -m "feat: bridge callback with HMAC signing, retry, and idempotency"
```

<verify>
- run: `cd /home/mk/projects/texturaize && pnpm build`
  expect: exit 0
</verify>

---

### Task 10: Webhook Receiver — Standalone Vercel Function

**Files:**
- Create: `apps/interblog/api/webhook/texturaize.ts`

This is a **standalone Vercel API function** at `api/webhook/texturaize.ts` (project root, NOT inside `src/`). Vercel auto-deploys files in `api/` as serverless functions independently of Astro.

**Step 1: Create webhook receiver**

```typescript
// api/webhook/texturaize.ts
// Standalone Vercel serverless function — NOT an Astro page
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { Octokit } from '@octokit/rest';
import crypto from 'crypto';
import { basename } from 'path';

const WEBHOOK_SECRET = process.env.INTERBLOG_WEBHOOK_SECRET;
const GITHUB_TOKEN = process.env.INTERBLOG_GITHUB_TOKEN;
const REPO_OWNER = 'mistakeknot';
const REPO_NAME = 'interblog';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  if (!WEBHOOK_SECRET || !GITHUB_TOKEN) {
    return res.status(503).json({ error: 'Webhook not configured' });
  }

  // HMAC signature verification
  const signature = req.headers['x-interblog-signature'] as string;
  const timestamp = req.headers['x-interblog-timestamp'] as string;

  if (!signature || !timestamp) {
    return res.status(401).json({ error: 'Missing signature' });
  }

  const body = JSON.stringify(req.body);
  const expectedSig = crypto
    .createHmac('sha256', WEBHOOK_SECRET)
    .update(`${timestamp}.${body}`)
    .digest('hex');

  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedSig))) {
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // Replay protection: reject timestamps > 5 min old
  const age = Math.floor(Date.now() / 1000) - parseInt(timestamp);
  if (age > 300) {
    return res.status(401).json({ error: 'Timestamp too old' });
  }

  const { draft_id, edited_content } = req.body;

  if (!draft_id || !edited_content) {
    return res.status(400).json({ error: 'Missing draft_id or edited_content' });
  }

  // Sanitize draft_id — prevent path traversal
  const safeName = basename(draft_id);
  if (!/^[a-zA-Z0-9_-]+$/.test(safeName)) {
    return res.status(400).json({ error: 'Invalid draft_id' });
  }

  // Idempotency: check if file already exists in review/
  const octokit = new Octokit({ auth: GITHUB_TOKEN });
  const filePath = `src/content/review/${safeName}.mdx`;

  try {
    await octokit.repos.getContent({
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path: filePath,
    });
    // File exists — already received
    return res.status(409).json({ error: 'Draft already received', path: filePath });
  } catch (e: any) {
    if (e.status !== 404) {
      return res.status(500).json({ error: 'GitHub API error' });
    }
    // 404 = file doesn't exist yet, proceed
  }

  // Commit edited content to repo via GitHub API
  try {
    await octokit.repos.createOrUpdateFileContents({
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path: filePath,
      message: `editorial: receive edited draft "${safeName}" from Texturaize`,
      content: Buffer.from(edited_content).toString('base64'),
    });
  } catch (e: any) {
    console.error('GitHub commit failed:', e.message);
    return res.status(500).json({ error: 'Failed to commit to repo' });
  }

  // Vercel auto-redeploys from the new commit
  return res.status(200).json({ status: 'committed', path: filePath });
}
```

**Step 2: Add env vars to Vercel**
```bash
vercel env add INTERBLOG_WEBHOOK_SECRET production
vercel env add INTERBLOG_GITHUB_TOKEN production
```

The `INTERBLOG_GITHUB_TOKEN` needs `contents:write` scope on the interblog repo.

**Step 3: Commit**
```bash
git add apps/interblog/api/
git commit -m "feat(interblog): webhook receiver — GitHub API commit, HMAC verification, path traversal protection"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/api/webhook/texturaize.ts`
  expect: exit 0
</verify>

---

### Task 11: Publish Command (Partner-Owned Gate)

**Files:**
- Create: `apps/interblog/commands/publish.md`

```markdown
<!-- apps/interblog/commands/publish.md -->
---
name: publish
description: Move a reviewed post to published. The PARTNER owns this gate — she decides when a post is ready.
---

# Publish a Reviewed Post

**Important:** This command should be run by or with explicit approval from the editorial partner. She owns the publish decision.

List posts in `src/content/review/`:
```bash
ls apps/interblog/src/content/review/*.mdx 2>/dev/null
```

Use AskUserQuestion to confirm which post to publish and whether the partner has approved.

Then:
1. Update frontmatter: `status: published`
2. Move: `src/content/review/<selected>.mdx` → `src/content/published/<selected>.mdx`
3. Commit and push (triggers Vercel rebuild)

```bash
mv src/content/review/<selected>.mdx src/content/published/<selected>.mdx
git add src/content/
git commit -m "publish: <post title>"
git push
```
```

**Commit:** `feat(interblog): publish command with partner approval gate`

---

### Task 12: Vercel + Cloudflare Deployment

**Files:**
- Create: `apps/interblog/vercel.json`

```json
{
  "framework": "astro",
  "installCommand": "pnpm install",
  "buildCommand": "pnpm build",
  "outputDirectory": "dist"
}
```

**Steps:**
1. `npx vercel --prod` — deploy to Vercel
2. Add Cloudflare CNAME: `blog` → `cname.vercel-dns.com` (DNS only, not proxied — Vercel manages SSL)
3. `npx vercel domains add blog.generalsystemsventures.com`
4. Add env vars: `vercel env add INTERBLOG_WEBHOOK_SECRET production` etc.

Note: Cloudflare proxy disabled is intentional — Vercel needs to manage its own TLS certificate. DDoS protection is traded off for SSL simplicity.

**Commit:** `feat(interblog): Vercel deployment + Cloudflare DNS`

---

### Task 13: Editorial Portfolio Page

**Files:**
- Create: `apps/interblog/src/pages/editorial.astro`

A curated view the partner controls, showing:
- Published posts with links
- Brief editorial statement (content strategy, voice guidelines, editorial process)
- Per-post editorial notes (optional companion markdown rendered inline)
- The partner can link this page in her Anthropic application

```astro
---
// src/pages/editorial.astro
import '../styles/global.css';
import { getCollection } from 'astro:content';

const posts = (await getCollection('published'))
  .filter(p => p.data.disclosure !== 'internal-only')
  .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Editorial Portfolio — GSV Engineering</title>
</head>
<body>
  <main class="max-w-[640px] mx-auto px-4 py-12">
    <header class="mb-12">
      <h1 class="text-3xl font-bold mb-4">Editorial Portfolio</h1>
      <div class="text-gray-600 space-y-3">
        <p>I serve as editorial lead for the GSV Engineering blog — a publication exploring
        systems thinking, emergence, and feedback loops through the lens of building
        autonomous software development infrastructure.</p>
        <p>My role spans the full editorial lifecycle: identifying which engineering stories
        are worth telling, shaping the narrative angle, and editing AI-generated drafts
        into rigorous, accessible posts that connect engineering specifics to broader
        conceptual frameworks.</p>
      </div>
    </header>

    <section>
      <h2 class="text-xl font-semibold mb-6">Published Work</h2>
      {posts.map(post => (
        <article class="py-4 border-b border-gray-100 last:border-0">
          <a href={`/${post.slug}`} class="no-underline group">
            <h3 class="text-lg font-medium text-gray-900 group-hover:text-blue-600">{post.data.title}</h3>
          </a>
          <p class="text-sm text-gray-600 mt-1">{post.data.description}</p>
          <div class="text-xs text-gray-400 mt-2">
            {new Date(post.data.date).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })}
            · {post.data.category} · {post.data.readingTime} min
          </div>
        </article>
      ))}
    </section>
  </main>
</body>
</html>
```

**Commit:** `feat(interblog): editorial portfolio page for Anthropic application`

---

### Task 14: Voice Profile + Continued Backfill

Same as v1 Task 14 but earlier in the user-facing timeline (partner already has Task 2 content). Initialize interfluence config, ingest mk's writing samples, run analysis, then collaborate with mk to select 5-10 more brainstorms for backfill.

**Commit:** `feat(interblog): interfluence voice profile config`

---

## Task Dependency Graph (Revised)

```
Task 1 (scaffold) ──┬── Task 2 (FIRST POST — immediate portfolio evidence)
                     │
                     ├── Task 3 (schema) ── Task 4 (layout) ── Task 5 (index + RSS)
                     │
                     ├── Task 6 (scan + pitch + draft skills)
                     │
                     ├── Task 7 (send skill) ── depends on Task 8
                     │
                     ├── Task 12 (deployment)
                     │
                     ├── Task 13 (portfolio page)
                     │
                     └── Task 14 (voice + backfill)

Task 8  (Texturaize bridge schema + ingest) ── Task 9 (callback sender)
                                                      │
Task 10 (webhook receiver) ──────────────────── depends on Task 8, 9
                                                      │
Task 11 (publish command) ──────────────────── depends on Task 10
```

**Wave 1 (parallel):** Tasks 1, 8
**Wave 2 (after Task 1):** Tasks 2, 3, 6, 12, 13
**Wave 3 (after Wave 2):** Tasks 4, 7, 9, 14
**Wave 4 (after Wave 3):** Tasks 5, 10
**Wave 5 (after Wave 4):** Task 11
