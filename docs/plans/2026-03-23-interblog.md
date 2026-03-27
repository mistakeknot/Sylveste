---
artifact_type: plan
bead: none
stage: design
---
# interblog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none
**Goal:** Build an auto-generating engineering blog at blog.generalsystemsventures.com with a 3-party editorial pipeline (AI surfaces → mk curates → Claude Code drafts → partner edits via Texturaize).

**Architecture:** Interverse plugin (`apps/interblog/`) with Astro static site, deployed to Vercel. Three skills (`scan`, `pitch`, `draft`) surface themes and generate posts. Texturaize API bridge (POST + webhook) handles the editorial round-trip. Gwern sidenotes + Flux Collective minimalist aesthetic.

**Tech Stack:** Astro 5, TypeScript, Tailwind CSS v4, MDX, Vercel, Cloudflare DNS, Buttondown API, interfluence voice profiles

---

## Must-Haves

**Truths** (observable behaviors):
- mk can run `/interblog:scan` and see ranked story candidates from CASS, beads, brainstorms
- mk can run `/interblog:pitch` and interactively select/shape a theme into a post brief
- mk can run `/interblog:draft` and get a markdown post written to `content/drafts/`
- Partner can open a draft in Texturaize via API bridge and edit with track changes
- Edited content returns to interblog via webhook callback
- Published posts render at blog.generalsystemsventures.com with sidenotes and clean typography
- RSS feed is available; Buttondown newsletter auto-publishes from RSS

**Artifacts** (files with specific exports):
- `apps/interblog/.claude-plugin/plugin.json` — valid Interverse plugin
- `apps/interblog/skills/scan/SKILL.md` — theme surfacing skill
- `apps/interblog/skills/pitch/SKILL.md` — curation dialogue skill
- `apps/interblog/skills/draft/SKILL.md` — post generation skill
- `apps/interblog/src/content/config.ts` — Astro content collection schema
- `apps/interblog/src/layouts/Post.astro` — post layout with sidenotes
- `apps/interblog/src/pages/index.astro` — post listing
- `texturaize: apps/web/src/app/api/bridge/ingest/route.ts` — bridge endpoint
- `apps/interblog/src/pages/api/webhook/texturaize.ts` — webhook receiver

**Key Links:**
- Draft skill writes frontmatter matching content collection schema
- Bridge endpoint accepts the exact JSON shape that draft skill produces
- Webhook callback writes to `content/review/` in the same format Astro expects
- Vercel rebuilds on push to `content/published/`

---

### Task 1: Scaffold Astro Project + Plugin Registration

**Files:**
- Create: `apps/interblog/package.json`
- Create: `apps/interblog/astro.config.mjs`
- Create: `apps/interblog/tsconfig.json`
- Create: `apps/interblog/.claude-plugin/plugin.json`
- Create: `apps/interblog/CLAUDE.md`
- Create: `apps/interblog/content/drafts/.gitkeep`
- Create: `apps/interblog/content/review/.gitkeep`
- Create: `apps/interblog/content/published/.gitkeep`

**Step 1: Initialize Astro project**
```bash
cd /home/mk/projects/Sylveste/apps
pnpm create astro@latest interblog -- --template minimal --typescript strict --install --no-git
```

**Step 2: Add dependencies**
```bash
cd /home/mk/projects/Sylveste/apps/interblog
pnpm add @astrojs/mdx @astrojs/rss @astrojs/sitemap @astrojs/tailwind tailwindcss
```

**Step 3: Configure Astro**
```javascript
// astro.config.mjs
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import tailwind from '@astrojs/tailwind';

export default defineConfig({
  site: 'https://blog.generalsystemsventures.com',
  integrations: [mdx(), sitemap(), tailwind()],
  content: {
    collections: {
      published: './content/published',
    }
  }
});
```

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
    "./skills/draft"
  ],
  "commands": [
    "./commands/scan.md",
    "./commands/pitch.md",
    "./commands/draft.md",
    "./commands/publish.md"
  ]
}
```

**Step 5: Create content directories and CLAUDE.md**

Create `content/drafts/.gitkeep`, `content/review/.gitkeep`, `content/published/.gitkeep`.

Write `CLAUDE.md`:
```markdown
# interblog

Engineering blog for General Systems Ventures. Published at blog.generalsystemsventures.com.

## Structure
- `skills/` — scan (theme surfacing), pitch (curation), draft (generation)
- `content/drafts/` — AI-generated posts awaiting editorial
- `content/review/` — returned from Texturaize, awaiting final approval
- `content/published/` — deployed to production via Vercel
- `src/` — Astro site (layouts, pages, components)

## Editorial Pipeline
1. `/interblog:scan` → surfaces themes from CASS, beads, brainstorms
2. `/interblog:pitch` → mk curates themes interactively
3. `/interblog:draft` → generates markdown post
4. POST to Texturaize bridge → partner edits
5. Webhook callback → content/review/
6. Move to content/published/ → Vercel deploys
```

**Step 6: Commit**
```bash
git add apps/interblog/
git commit -m "feat(interblog): scaffold Astro project + plugin registration"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
- run: `cat apps/interblog/.claude-plugin/plugin.json | python3 -c "import json,sys; json.load(sys.stdin); print('valid')" `
  expect: contains "valid"
</verify>

---

### Task 2: Content Collection Schema + Post Frontmatter

**Files:**
- Create: `apps/interblog/src/content/config.ts`
- Create: `apps/interblog/src/content/published/_example.mdx` (test fixture)

**Step 1: Define content collection schema**
```typescript
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const published = defineCollection({
  type: 'content',
  schema: z.object({
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
    readingTime: z.number().optional(),
    status: z.enum(['draft', 'review', 'published']).default('published'),
  }),
});

export const collections = { published };
```

**Step 2: Create example post as test fixture**
```mdx
---
title: "Example Post: Multi-Agent Coordination"
date: 2026-03-23
category: deep-dive
disclosure: open
description: "Test fixture for content collection validation."
tags: [test]
sources: []
---

This is a test post to validate the content collection schema.
```

**Step 3: Verify schema validates**
```bash
cd /home/mk/projects/Sylveste/apps/interblog && pnpm build
```

**Step 4: Commit**
```bash
git add apps/interblog/src/content/
git commit -m "feat(interblog): content collection schema with post frontmatter"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 3: Post Layout with Sidenotes + Base Styles

**Files:**
- Create: `apps/interblog/src/layouts/Post.astro`
- Create: `apps/interblog/src/components/Sidenote.astro`
- Create: `apps/interblog/src/components/TableOfContents.astro`
- Create: `apps/interblog/src/styles/global.css`
- Create: `apps/interblog/src/pages/[...slug].astro`

**Step 1: Create global styles**

Gwern sidenotes + Flux minimalism:
- Sans-serif body (Inter or system font stack)
- Monochrome palette with one accent color
- Generous whitespace, max-width content area
- Sidenote column on the right (desktop), inline on mobile
- Clean typography hierarchy (large titles, comfortable line-height)

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

article {
  max-width: var(--content-width);
  margin: 0 auto;
  padding: 2rem 1rem;
}

/* Sidenote layout */
@media (min-width: 1100px) {
  .post-container {
    display: grid;
    grid-template-columns: var(--content-width) var(--sidenote-gap) var(--sidenote-width);
    max-width: calc(var(--content-width) + var(--sidenote-gap) + var(--sidenote-width));
    margin: 0 auto;
  }

  .post-content {
    grid-column: 1;
  }

  .sidenote {
    grid-column: 3;
    font-size: 0.85rem;
    color: var(--color-text-secondary);
    line-height: 1.5;
    border-left: 2px solid var(--color-border);
    padding-left: 1rem;
    margin-top: 0;
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

hr {
  border: none;
  border-top: 1px solid var(--color-border);
  margin: 2.5rem 0;
}
```

**Step 2: Create Sidenote component**
```astro
---
// src/components/Sidenote.astro
interface Props {
  id: string;
}
const { id } = Astro.props;
---
<span class="sidenote-ref"><sup>{id}</sup></span>
<aside class="sidenote" id={`sn-${id}`}>
  <sup>{id}</sup> <slot />
</aside>
```

**Step 3: Create TableOfContents component**
```astro
---
// src/components/TableOfContents.astro
interface Props {
  headings: { depth: number; slug: string; text: string }[];
}
const { headings } = Astro.props;
const filtered = headings.filter(h => h.depth <= 3);
---
{filtered.length > 0 && (
  <nav class="toc">
    <details open>
      <summary class="text-sm font-semibold text-gray-500 uppercase tracking-wide">Contents</summary>
      <ul class="mt-2 space-y-1 text-sm">
        {filtered.map(h => (
          <li style={`padding-left: ${(h.depth - 2) * 1}rem`}>
            <a href={`#${h.slug}`} class="text-gray-600 hover:text-gray-900 no-underline">{h.text}</a>
          </li>
        ))}
      </ul>
    </details>
  </nav>
)}
```

**Step 4: Create Post layout**
```astro
---
// src/layouts/Post.astro
import '../styles/global.css';
import TableOfContents from '../components/TableOfContents.astro';

const { frontmatter, headings } = Astro.props;
const readingTime = frontmatter.readingTime || Math.ceil(frontmatter.rawContent?.split(/\s+/).length / 250) || '?';
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

  <article>
    <header class="mb-8">
      <h1>{frontmatter.title}</h1>
      <div class="text-sm text-gray-500 flex gap-3 items-center">
        <time datetime={frontmatter.date}>{dateStr}</time>
        <span>·</span>
        <span>{frontmatter.category}</span>
        <span>·</span>
        <span>{readingTime} min read</span>
      </div>
    </header>

    {frontmatter.category === 'deep-dive' && headings && (
      <TableOfContents headings={headings} />
    )}

    <div class="post-container">
      <div class="post-content prose">
        <slot />
      </div>
    </div>
  </article>

  <footer class="max-w-[640px] mx-auto px-4 py-8 border-t border-gray-200 text-sm text-gray-500">
    <div class="flex justify-between">
      <span>General Systems Ventures</span>
      <a href="/rss.xml">RSS</a>
    </div>
  </footer>
</body>
</html>
```

**Step 5: Create dynamic post page**
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

**Step 6: Commit**
```bash
git add apps/interblog/src/
git commit -m "feat(interblog): post layout with Gwern sidenotes + Flux minimalist styles"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 4: Index Page + Post Listing

**Files:**
- Create: `apps/interblog/src/pages/index.astro`
- Create: `apps/interblog/src/components/PostCard.astro`

**Step 1: Create PostCard component**
```astro
---
// src/components/PostCard.astro
interface Props {
  title: string;
  date: Date;
  category: string;
  description: string;
  slug: string;
  tags: string[];
}
const { title, date, category, description, slug, tags } = Astro.props;
const dateStr = new Date(date).toLocaleDateString('en-US', {
  year: 'numeric', month: 'short', day: 'numeric'
});
---
<article class="py-6 border-b border-gray-100 last:border-0">
  <a href={`/${slug}`} class="no-underline group">
    <h2 class="text-xl font-semibold text-gray-900 group-hover:text-blue-600 transition-colors mb-1">{title}</h2>
    <div class="text-sm text-gray-500 flex gap-2 mb-2">
      <time>{dateStr}</time>
      <span>·</span>
      <span class="capitalize">{category}</span>
    </div>
    <p class="text-gray-600 text-sm leading-relaxed">{description}</p>
  </a>
  {tags.length > 0 && (
    <div class="flex gap-2 mt-2">
      {tags.map(tag => (
        <span class="text-xs text-gray-400">#{tag}</span>
      ))}
    </div>
  )}
</article>
```

**Step 2: Create index page**
```astro
---
// src/pages/index.astro
import '../styles/global.css';
import { getCollection } from 'astro:content';
import PostCard from '../components/PostCard.astro';

const posts = (await getCollection('published'))
  .filter(p => p.data.disclosure !== 'internal-only')
  .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>GSV Engineering</title>
  <meta name="description" content="Systems thinking meets engineering practice. Building autonomous software development infrastructure." />
  <link rel="alternate" type="application/rss+xml" title="GSV Engineering Blog" href="/rss.xml" />
</head>
<body>
  <main class="max-w-[640px] mx-auto px-4 py-12">
    <header class="mb-12">
      <h1 class="text-3xl font-bold mb-2">GSV Engineering</h1>
      <p class="text-gray-600 text-lg">Systems thinking meets engineering practice.</p>
    </header>

    <section>
      {posts.map(post => (
        <PostCard
          title={post.data.title}
          date={post.data.date}
          category={post.data.category}
          description={post.data.description}
          slug={post.slug}
          tags={post.data.tags}
        />
      ))}
    </section>
  </main>

  <footer class="max-w-[640px] mx-auto px-4 py-8 border-t border-gray-200 text-sm text-gray-500">
    <div class="flex justify-between">
      <span>General Systems Ventures</span>
      <a href="/rss.xml">RSS</a>
    </div>
  </footer>
</body>
</html>
```

**Step 3: Commit**
```bash
git add apps/interblog/src/
git commit -m "feat(interblog): index page with post listing and PostCard component"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 5: RSS Feed

**Files:**
- Create: `apps/interblog/src/pages/rss.xml.ts`

**Step 1: Create RSS endpoint**
```typescript
// src/pages/rss.xml.ts
import rss from '@astrojs/rss';
import { getCollection } from 'astro:content';
import type { APIContext } from 'astro';

export async function GET(context: APIContext) {
  const posts = (await getCollection('published'))
    .filter(p => p.data.disclosure !== 'internal-only')
    .sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());

  return rss({
    title: 'GSV Engineering',
    description: 'Systems thinking meets engineering practice. Building autonomous software development infrastructure.',
    site: context.site!,
    items: posts.map(post => ({
      title: post.data.title,
      pubDate: post.data.date,
      description: post.data.description,
      link: `/${post.slug}/`,
      categories: [post.data.category, ...post.data.tags],
    })),
  });
}
```

**Step 2: Commit**
```bash
git add apps/interblog/src/pages/rss.xml.ts
git commit -m "feat(interblog): RSS feed endpoint"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 6: Scan Skill — Theme Surfacing

**Files:**
- Create: `apps/interblog/skills/scan/SKILL.md`
- Create: `apps/interblog/commands/scan.md`

**Step 1: Write the scan skill**

```markdown
<!-- apps/interblog/skills/scan/SKILL.md -->
---
name: scan
description: Surface publishable engineering themes from Sylveste ecosystem — CASS sessions, beads, brainstorms, PHILOSOPHY.md, git activity. Produces ranked story candidates.
---

# interblog: Theme Surfacing

You are scanning the Sylveste ecosystem for publishable engineering stories.

## Step 1: Gather Signals

Run these in parallel:

### Recent beads (last 7 days)
```bash
bd list --status=closed --since=7d 2>/dev/null || echo "beads unavailable"
```

### Recent brainstorms
```bash
find docs/brainstorms/ -name "*.md" -mtime -7 -type f 2>/dev/null | sort -r | head -10
```

### PHILOSOPHY.md changes
```bash
git log --oneline -5 -- PHILOSOPHY.md 2>/dev/null
```

### Git activity (significant commits)
```bash
git log --oneline --since="7 days ago" --no-merges | head -20
```

### CASS sessions (interesting patterns)
```bash
cass search "architecture decision lesson learned emergence" --limit 5 --json --fast-only 2>/dev/null
```

## Step 2: Extract Themes

From the gathered signals, identify 3-7 themes that would make compelling blog posts. For each theme:

1. **Title** — working title for the post
2. **Category** — deep-dive or digest
3. **Hook** — one sentence explaining why this is interesting through a systems thinking lens
4. **Sources** — which signals surfaced this theme
5. **Disclosure** — open, abstracted, or internal-only
6. **Strength** — high/medium/low based on narrative potential

Prioritize themes that:
- Reveal surprising emergence or feedback loops
- Show engineering decisions through conceptual frameworks
- Have clear before/after or tension/resolution structure
- Connect to broader ideas (McLuhan, Meadows, Komoroske)

## Step 3: Present Candidates

Present themes as a ranked list. Use AskUserQuestion to let mk select which to develop further.

Format:
```
## Theme Candidates

1. **[Title]** (deep-dive, high)
   Hook: [one sentence]
   Sources: [brainstorm X, bead Y, commit Z]

2. ...
```

After mk selects, save selection to `content/themes.yaml` (append, don't overwrite):

```yaml
- title: "Selected Title"
  category: deep-dive
  date_surfaced: 2026-03-23
  sources:
    - type: brainstorm
      path: docs/brainstorms/2026-03-23-foo.md
  status: selected
```
```

**Step 2: Write the scan command**
```markdown
<!-- apps/interblog/commands/scan.md -->
---
name: scan
description: Surface publishable engineering themes from Sylveste ecosystem activity.
---

Invoke the `interblog:scan` skill.
```

**Step 3: Commit**
```bash
git add apps/interblog/skills/ apps/interblog/commands/
git commit -m "feat(interblog): scan skill — theme surfacing from ecosystem signals"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/scan/SKILL.md`
  expect: exit 0
</verify>

---

### Task 7: Pitch Skill — Curation Dialogue

**Files:**
- Create: `apps/interblog/skills/pitch/SKILL.md`
- Create: `apps/interblog/commands/pitch.md`

**Step 1: Write the pitch skill**

```markdown
<!-- apps/interblog/skills/pitch/SKILL.md -->
---
name: pitch
description: Interactive curation dialogue — discuss surfaced themes with mk, shape selected theme into a post brief with angle, structure, and disclosure decisions.
---

# interblog: Curation Dialogue

You are helping mk shape a surfaced theme into a blog post brief.

## Step 1: Load Context

Read the latest entries from `content/themes.yaml` (status: selected).
If no selected themes, suggest running `/interblog:scan` first.

For the selected theme, read the source materials:
- If brainstorm source: read the brainstorm doc
- If bead source: `bd show <id>`
- If session source: `cass search "<topic>" --limit 1`

## Step 2: Propose Angle

Present 2-3 angles for the post using AskUserQuestion. Each angle should:
- Frame the engineering work through a systems thinking lens
- Suggest a narrative structure (tension/resolution, before/after, exploration)
- Name specific influences it draws from (McLuhan, Meadows, Rao, etc.)

Example angles for "multi-agent coordination":
1. **Immune system analogy** — tolerance, self/non-self, clonal selection → how the factory learned to stop rejecting its own agents
2. **Stigmergy** — indirect coordination through environment modification → agents coordinating through artifacts instead of messages
3. **Pace layering** — fast/slow layers → how dispatch speed and review depth operate at different tempos

## Step 3: Shape the Brief

After mk selects an angle, build the post brief interactively:

1. **Title** — propose 2-3 options (AskUserQuestion)
2. **Opening hook** — the first paragraph that draws the reader in
3. **Structure** — section outline (3-5 sections for deep-dive, 1-2 for digest)
4. **Key insight** — the one thing the reader should take away
5. **Disclosure level** — what to name vs abstract
6. **Sidenotes** — 2-3 planned margin notes for context, definitions, or asides

## Step 4: Save Brief

Write the brief to `content/briefs/<date>-<slug>.yaml`:

```yaml
title: "Final Title"
slug: "multi-agent-coordination-immune-tolerance"
category: deep-dive
disclosure: open
angle: "Immune system analogy"
hook: "The factory doesn't have a central controller..."
structure:
  - section: "The tolerance problem"
    key_point: "..."
  - section: "Self/non-self in code review"
    key_point: "..."
sidenotes:
  - ref: "factory"
    text: "By 'factory' we mean the Sylveste autonomous dev agency — 32 agents operating concurrently."
sources:
  - type: brainstorm
    path: "..."
tags: [multi-agent, coordination, emergence]
date_briefed: 2026-03-23
```
```

**Step 2: Write the pitch command**
```markdown
<!-- apps/interblog/commands/pitch.md -->
---
name: pitch
description: Shape a surfaced theme into a blog post brief through interactive dialogue.
---

Invoke the `interblog:pitch` skill.
```

**Step 3: Commit**
```bash
git add apps/interblog/skills/pitch/ apps/interblog/commands/pitch.md
git commit -m "feat(interblog): pitch skill — curation dialogue for post briefs"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/pitch/SKILL.md`
  expect: exit 0
</verify>

---

### Task 8: Draft Skill — Post Generation

**Files:**
- Create: `apps/interblog/skills/draft/SKILL.md`
- Create: `apps/interblog/commands/draft.md`

**Step 1: Write the draft skill**

```markdown
<!-- apps/interblog/skills/draft/SKILL.md -->
---
name: draft
description: Generate a full blog post from a brief — markdown with frontmatter, sidenotes, and systems-thinking narrative. Writes to content/drafts/.
---

# interblog: Post Generation

You are generating a blog post from a brief. The voice is essayistic and intellectually dense but accessible — systems thinking meets engineering practice.

## Step 1: Load Brief

Read the brief from `content/briefs/<slug>.yaml`.
Read all source materials referenced in the brief.

## Step 2: Load Voice Profile

Check for interfluence voice profile:
```bash
cat .interfluence/profiles/interblog.yaml 2>/dev/null || echo "no voice profile"
```

If available, adapt writing to match the voice profile. If not, use these defaults:
- Essayistic, not tutorial
- First person singular for essays, plural for project narratives
- Dense but accessible — assume technical literacy, explain conceptual frameworks
- Show the thinking: "the tension between X and Y led us to Z"
- Anti-patterns: no "leveraging", no "it's worth noting", no corporate hedging

## Step 3: Generate Post

Write the post as MDX following this structure:

### Deep-dive posts (1500-3000 words):
1. **Opening hook** (1 paragraph) — draw the reader into the core tension
2. **Context** (1-2 paragraphs) — what we were building, why it matters
3. **Body sections** (3-5 sections from brief) — each section explores one facet, uses engineering specifics to illuminate conceptual framework
4. **Sidenotes** — use `<Sidenote id="N">text</Sidenote>` component for margin notes
5. **Closing** (1-2 paragraphs) — what we learned, what it means beyond our context

### Digest posts (500-1000 words):
1. **Lead** — one sentence summary of the theme
2. **Entries** — 3-5 notable changes, each with a "why it matters" angle
3. **Pattern** — one connecting thread across the entries

### Frontmatter:
```yaml
---
title: "<from brief>"
date: <today>
category: <from brief>
disclosure: <from brief>
description: "<1-2 sentence summary for RSS and meta tags>"
tags: <from brief>
sources: <from brief>
readingTime: <calculated>
status: draft
---
```

## Step 4: Save Draft

Write to `content/drafts/<date>-<slug>.mdx`.

Show the opening paragraph to mk for quick feedback. If approved, the draft is ready for Texturaize.

## Step 5: Send to Texturaize (if configured)

If `INTERBLOG_TEXTURAIZE_API_KEY` is set:
```bash
curl -X POST https://texturaize.com/api/bridge/ingest \
  -H "Authorization: Bearer $INTERBLOG_TEXTURAIZE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "interblog",
    "draft_id": "<slug>",
    "content": "<markdown content>",
    "callback_url": "https://blog.generalsystemsventures.com/api/webhook/texturaize",
    "metadata": { "category": "<category>", "disclosure": "<disclosure>" }
  }'
```

Report the session URL to mk for forwarding to partner.
```

**Step 2: Write the draft command**
```markdown
<!-- apps/interblog/commands/draft.md -->
---
name: draft
description: Generate a blog post from a brief and optionally send to Texturaize for editorial review.
---

Invoke the `interblog:draft` skill.
```

**Step 3: Commit**
```bash
git add apps/interblog/skills/draft/ apps/interblog/commands/draft.md
git commit -m "feat(interblog): draft skill — post generation with voice profile support"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/skills/draft/SKILL.md`
  expect: exit 0
</verify>

---

### Task 9: Texturaize Bridge API Endpoint

**Files:**
- Create: `apps/web/src/app/api/bridge/ingest/route.ts` (in Texturaize repo)

**Step 1: Create bridge ingest endpoint**

This task is in the **Texturaize** repository (`/home/mk/projects/texturaize`).

```typescript
// apps/web/src/app/api/bridge/ingest/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createServerClient } from '@/lib/supabase/server';

const BRIDGE_API_KEY = process.env.INTERBLOG_BRIDGE_API_KEY;

interface BridgeIngestRequest {
  source: string;
  draft_id: string;
  content: string;
  callback_url: string;
  metadata: {
    category: string;
    disclosure: string;
  };
}

export async function POST(req: NextRequest) {
  // Validate API key
  const authHeader = req.headers.get('authorization');
  if (!authHeader || authHeader !== `Bearer ${BRIDGE_API_KEY}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const body: BridgeIngestRequest = await req.json();

  if (!body.content || !body.draft_id || !body.source) {
    return NextResponse.json(
      { error: 'Missing required fields: content, draft_id, source' },
      { status: 400 }
    );
  }

  const supabase = await createServerClient();

  // Create a document record for the bridge draft
  const { data: doc, error } = await supabase
    .from('documents')
    .insert({
      title: body.draft_id,
      original_content: body.content,
      source: body.source,
      callback_url: body.callback_url,
      metadata: body.metadata,
      status: 'pending_review',
    })
    .select('id')
    .single();

  if (error) {
    return NextResponse.json({ error: 'Failed to create document' }, { status: 500 });
  }

  const sessionUrl = `${process.env.NEXT_PUBLIC_APP_URL}/edit/${doc.id}`;

  return NextResponse.json({
    session_url: sessionUrl,
    document_id: doc.id,
  });
}
```

**Step 2: Add bridge columns to documents table (migration)**

Create Supabase migration:
```sql
-- supabase/migrations/YYYYMMDDHHMMSS_add_bridge_fields.sql
ALTER TABLE documents ADD COLUMN IF NOT EXISTS source TEXT;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS callback_url TEXT;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';
ALTER TABLE documents ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
```

**Step 3: Add env var to .env.example**
```
INTERBLOG_BRIDGE_API_KEY=your-api-key-here
```

**Step 4: Commit (in Texturaize repo)**
```bash
cd /home/mk/projects/texturaize
git add apps/web/src/app/api/bridge/ supabase/migrations/
git commit -m "feat: add bridge API endpoint for interblog editorial integration"
```

<verify>
- run: `test -f /home/mk/projects/texturaize/apps/web/src/app/api/bridge/ingest/route.ts`
  expect: exit 0
</verify>

---

### Task 10: Texturaize Webhook Callback — "Done Editing"

**Files:**
- Create: `apps/web/src/app/api/bridge/callback/route.ts` (in Texturaize repo)

**Step 1: Create callback sender**

When the partner finishes editing a bridge document, Texturaize POSTs the edited content back to the interblog callback URL.

```typescript
// apps/web/src/app/api/bridge/callback/route.ts
// This is triggered internally by Texturaize when a bridge document is marked "done"
import { NextRequest, NextResponse } from 'next/server';
import { createServerClient } from '@/lib/supabase/server';

export async function POST(req: NextRequest) {
  const { document_id } = await req.json();

  const supabase = await createServerClient();

  const { data: doc, error } = await supabase
    .from('documents')
    .select('*')
    .eq('id', document_id)
    .single();

  if (error || !doc) {
    return NextResponse.json({ error: 'Document not found' }, { status: 404 });
  }

  if (!doc.callback_url) {
    return NextResponse.json({ error: 'No callback URL configured' }, { status: 400 });
  }

  // Send edited content back to interblog
  const callbackResponse = await fetch(doc.callback_url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${process.env.INTERBLOG_BRIDGE_API_KEY}`,
    },
    body: JSON.stringify({
      draft_id: doc.title,
      edited_content: doc.processed_content || doc.original_content,
      source: doc.source,
      metadata: doc.metadata,
      document_id: doc.id,
    }),
  });

  if (!callbackResponse.ok) {
    return NextResponse.json({ error: 'Callback failed' }, { status: 502 });
  }

  // Update document status
  await supabase
    .from('documents')
    .update({ status: 'callback_sent' })
    .eq('id', document_id);

  return NextResponse.json({ status: 'callback_sent' });
}
```

**Step 2: Commit (in Texturaize repo)**
```bash
cd /home/mk/projects/texturaize
git add apps/web/src/app/api/bridge/callback/
git commit -m "feat: bridge callback sender — POST edited content back to interblog"
```

<verify>
- run: `test -f /home/mk/projects/texturaize/apps/web/src/app/api/bridge/callback/route.ts`
  expect: exit 0
</verify>

---

### Task 11: Interblog Webhook Receiver

**Files:**
- Create: `apps/interblog/src/pages/api/webhook/texturaize.ts`

**Step 1: Create webhook endpoint**

Astro server endpoint that receives edited content from Texturaize and writes to `content/review/`.

```typescript
// src/pages/api/webhook/texturaize.ts
import type { APIRoute } from 'astro';
import { writeFile } from 'fs/promises';
import { join } from 'path';

const BRIDGE_API_KEY = import.meta.env.INTERBLOG_BRIDGE_API_KEY;

export const POST: APIRoute = async ({ request }) => {
  const authHeader = request.headers.get('authorization');
  if (!authHeader || authHeader !== `Bearer ${BRIDGE_API_KEY}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const body = await request.json();
  const { draft_id, edited_content, metadata } = body;

  if (!draft_id || !edited_content) {
    return new Response(
      JSON.stringify({ error: 'Missing draft_id or edited_content' }),
      { status: 400 }
    );
  }

  // Write edited content to content/review/
  const filename = `${draft_id}.mdx`;
  const reviewPath = join(process.cwd(), 'content', 'review', filename);

  await writeFile(reviewPath, edited_content, 'utf-8');

  return new Response(
    JSON.stringify({ status: 'received', path: `content/review/${filename}` }),
    { status: 200 }
  );
};
```

**Step 2: Update astro.config.mjs for server endpoints**

Add `output: 'hybrid'` to enable server endpoints while keeping static pages:
```javascript
export default defineConfig({
  site: 'https://blog.generalsystemsventures.com',
  output: 'hybrid',
  integrations: [mdx(), sitemap(), tailwind()],
});
```

**Step 3: Commit**
```bash
git add apps/interblog/src/pages/api/ apps/interblog/astro.config.mjs
git commit -m "feat(interblog): webhook receiver — accepts edited content from Texturaize"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/src/pages/api/webhook/texturaize.ts`
  expect: exit 0
</verify>

---

### Task 12: Publish Command + Dashboard Page

**Files:**
- Create: `apps/interblog/commands/publish.md`
- Create: `apps/interblog/src/pages/dashboard.astro`

**Step 1: Write publish command**
```markdown
<!-- apps/interblog/commands/publish.md -->
---
name: publish
description: Move a reviewed post from content/review/ to content/published/ and trigger deployment.
---

# Publish a Reviewed Post

List posts in `content/review/`:
```bash
ls apps/interblog/content/review/*.mdx 2>/dev/null
```

Use AskUserQuestion to let mk select which post to publish.

Then:
1. Update frontmatter `status: published`
2. Move file from `content/review/` to `content/published/`
3. Commit and push (triggers Vercel rebuild)

```bash
mv content/review/<selected>.mdx content/published/<selected>.mdx
git add content/
git commit -m "publish: <post title>"
git push
```
```

**Step 2: Create dashboard page**

Simple page showing post counts by status (drafts, in review, published).

```astro
---
// src/pages/dashboard.astro
import '../styles/global.css';
import { readdirSync } from 'fs';
import { join } from 'path';

const contentDir = join(process.cwd(), 'content');
const drafts = readdirSync(join(contentDir, 'drafts')).filter(f => f.endsWith('.mdx'));
const review = readdirSync(join(contentDir, 'review')).filter(f => f.endsWith('.mdx'));
const published = readdirSync(join(contentDir, 'published')).filter(f => f.endsWith('.mdx'));
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Dashboard — GSV Engineering</title>
</head>
<body>
  <main class="max-w-[640px] mx-auto px-4 py-12">
    <h1 class="text-2xl font-bold mb-8">Editorial Dashboard</h1>

    <div class="grid grid-cols-3 gap-4 mb-8">
      <div class="p-4 border rounded-lg">
        <div class="text-3xl font-bold text-amber-600">{drafts.length}</div>
        <div class="text-sm text-gray-500">Drafts</div>
      </div>
      <div class="p-4 border rounded-lg">
        <div class="text-3xl font-bold text-blue-600">{review.length}</div>
        <div class="text-sm text-gray-500">In Review</div>
      </div>
      <div class="p-4 border rounded-lg">
        <div class="text-3xl font-bold text-green-600">{published.length}</div>
        <div class="text-sm text-gray-500">Published</div>
      </div>
    </div>

    {review.length > 0 && (
      <section class="mb-8">
        <h2 class="text-lg font-semibold mb-3">Ready for Review</h2>
        <ul class="space-y-2">
          {review.map(f => (
            <li class="p-3 bg-blue-50 rounded border border-blue-100 text-sm">
              {f.replace('.mdx', '')}
            </li>
          ))}
        </ul>
      </section>
    )}

    {drafts.length > 0 && (
      <section>
        <h2 class="text-lg font-semibold mb-3">Awaiting Editorial</h2>
        <ul class="space-y-2">
          {drafts.map(f => (
            <li class="p-3 bg-amber-50 rounded border border-amber-100 text-sm">
              {f.replace('.mdx', '')}
            </li>
          ))}
        </ul>
      </section>
    )}
  </main>
</body>
</html>
```

**Step 3: Commit**
```bash
git add apps/interblog/commands/publish.md apps/interblog/src/pages/dashboard.astro
git commit -m "feat(interblog): publish command + editorial dashboard page"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/interblog && pnpm build`
  expect: exit 0
</verify>

---

### Task 13: Vercel + Cloudflare Deployment

**Files:**
- Create: `apps/interblog/vercel.json`
- Modify: Cloudflare DNS (via API or dashboard)

**Step 1: Create vercel.json**
```json
{
  "framework": "astro",
  "installCommand": "pnpm install",
  "buildCommand": "pnpm build",
  "outputDirectory": "dist"
}
```

**Step 2: Deploy to Vercel**
```bash
cd /home/mk/projects/Sylveste/apps/interblog
npx vercel --prod
```

Follow prompts to link to Vercel project. Note the deployment URL.

**Step 3: Add Cloudflare CNAME**

Add DNS record via Cloudflare dashboard or API:
- Type: CNAME
- Name: blog
- Target: cname.vercel-dns.com
- Proxy: DNS only (not proxied, for Vercel SSL)

**Step 4: Configure custom domain in Vercel**
```bash
npx vercel domains add blog.generalsystemsventures.com
```

**Step 5: Commit**
```bash
git add apps/interblog/vercel.json
git commit -m "feat(interblog): Vercel deployment config"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/vercel.json`
  expect: exit 0
</verify>

---

### Task 14: Voice Profile + Backfill Preparation

**Files:**
- Create: `apps/interblog/.interfluence/config.yaml`

**Step 1: Initialize interfluence for interblog**

```bash
cd /home/mk/projects/Sylveste/apps/interblog
mkdir -p .interfluence
```

Write config:
```yaml
# .interfluence/config.yaml
profile_name: interblog
mode: manual
influences:
  - gwern
  - flux-collective
  - venkatesh-rao
  - maggie-appleton
  - alex-komoroske
  - marshall-mcluhan
  - joshua-meyrowitz
tone:
  - essayistic
  - systems-thinking
  - dense-but-accessible
  - first-person
anti_patterns:
  - leveraging
  - "it's worth noting"
  - "it's important to"
  - corporate hedging
  - passive voice excess
```

**Step 2: Ingest mk's writing samples**

Use `/interfluence:ingest` to feed mk's brainstorm documents and PHILOSOPHY.md as corpus samples. This builds the voice profile the draft skill will use.

Run:
```
/interfluence:ingest apps/interblog PHILOSOPHY.md docs/brainstorms/2026-03-23-interblog-brainstorm.md
```

Then:
```
/interfluence:analyze
```

**Step 3: Identify backfill candidates**

Run `/interblog:scan` with `--all` flag to scan all brainstorms (not just last 7 days). Present the top 10-15 candidates to mk for selection. Selected themes become the seed content batch.

**Step 4: Commit**
```bash
git add apps/interblog/.interfluence/
git commit -m "feat(interblog): interfluence voice profile config for systems-thinking editorial voice"
```

<verify>
- run: `test -f /home/mk/projects/Sylveste/apps/interblog/.interfluence/config.yaml`
  expect: exit 0
</verify>

---

## Task Dependency Graph

```
Task 1 (scaffold) ──┬── Task 2 (schema) ── Task 3 (layout) ── Task 4 (index) ── Task 5 (RSS)
                     │
                     ├── Task 6 (scan skill) ──┐
                     ├── Task 7 (pitch skill) ──┼── Task 14 (voice + backfill)
                     ├── Task 8 (draft skill) ──┘
                     │
                     ├── Task 11 (webhook receiver) ── Task 12 (publish + dashboard)
                     │
                     └── Task 13 (deployment)

Task 9  (Texturaize bridge) ──┐
Task 10 (Texturaize callback) ┘── (independent, in Texturaize repo)
```

**Wave 1 (parallel):** Tasks 1, 9, 10
**Wave 2 (after Task 1):** Tasks 2, 6, 7, 8, 13
**Wave 3 (after Wave 2):** Tasks 3, 11, 12, 14
**Wave 4 (after Task 3):** Tasks 4, 5
