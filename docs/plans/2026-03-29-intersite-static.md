---
artifact_type: plan
bead: sylveste-09h
stage: design
requirements:
  - F1: Astro app scaffold + Cloudflare Tunnel deploy
  - F2: Project pages with template, roster, and lineage
  - F4: Experiment entries at /experiments/
  - F7: Interverse plugin index at /projects/sylveste/plugins/
  - F8: intersite Interverse plugin (generate + status commands only)
---
# intersite-static Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** sylveste-09h (epic), features: sylveste-wdw (F1), sylveste-b28 (F2), sylveste-6hf (F4), sylveste-71a (F7), sylveste-t3f (F8)
**Goal:** Ship the static publishing surface at generalsystemsventures.com — project portfolio, experiments, plugin index — deployable via Cloudflare Tunnel on sleeper-service.

**Architecture:** Astro 6 app at `apps/intersite/` with Tailwind 4, MDX, Node adapter (standalone mode), Clerk auth. Content collections for projects, experiments, and plugins with a shared `pipeline_state` frontmatter field. Build-time Zod validation ensures only `published` content renders in production. Interverse plugin at `interverse/intersite/` provides `/intersite:generate` and `/intersite:status` commands.

**Tech Stack:** Astro 6, @astrojs/node, @astrojs/mdx, @astrojs/sitemap, @clerk/astro, Tailwind 4, Zod (via Astro content collections), Geist Sans/Mono fonts, Cloudflare Tunnel (cloudflared)

**Prior Learnings:** CASS confirms interblog deploy pattern — Cloudflare Tunnel to localhost, `node dist/server/entry.mjs` as runtime, systemd service for process management. interblog uses `output: 'static'` with Node adapter — intersite should match. Critical pattern: compiled MCP servers need launcher scripts (relevant for F8 plugin).

---

## Must-Haves

**Truths** (observable behaviors):
- Visitor can browse `/projects/` and see a featured tier of 3-5 projects above the fold with a full roster grid below
- Visitor can click into `/projects/[slug]` and see project description, lineage, themes, status badge
- Visitor can browse `/experiments/` and see short-form lab entries in reverse chronological order
- Visitor can browse `/projects/sylveste/plugins/` and see a searchable grid of all Interverse plugins
- Agent can run `/intersite:generate` and get draft project pages written to content directory
- Agent can run `/intersite:status` and see pipeline state across all collections
- `pnpm build && pnpm start` serves the site locally at port 4321
- Only content with `pipeline_state: "published"` and `mk_approved_at` timestamp renders in production

**Artifacts** (files with specific exports):
- [`apps/intersite/src/content/config.ts`] exports content collection schemas (projects, experiments, plugins)
- [`apps/intersite/src/lib/content.ts`] exports `getPublishedContent(collection)` utility
- [`apps/intersite/src/content/PIPELINE.md`] documents state machine and enforcement seam
- [`interverse/intersite/.claude-plugin/plugin.json`] registers the intersite plugin

**Key Links** (connections where breakage cascades):
- All production pages call `getPublishedContent()` — never `getCollection()` directly
- Plugin index generation reads `interverse/*/`.claude-plugin/plugin.json` for descriptions
- `/intersite:generate` writes content files with `pipeline_state: "raw_draft"` — never `published`

---

### Task 1: Scaffold Astro app with deps and config

**Files:**
- Create: `apps/intersite/package.json`
- Create: `apps/intersite/astro.config.mjs`
- Create: `apps/intersite/tsconfig.json`
- Create: `apps/intersite/src/styles/global.css`

**Step 1: Initialize the Astro project**
```bash
cd /home/mk/projects/Sylveste/apps
mkdir -p intersite/src/styles intersite/src/pages intersite/src/layouts intersite/src/components intersite/src/content intersite/public
```

**Step 2: Write package.json**
```json
{
  "name": "intersite",
  "type": "module",
  "version": "0.1.0",
  "engines": { "node": ">=22.12.0" },
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "start": "node dist/server/entry.mjs",
    "preview": "astro preview"
  },
  "dependencies": {
    "@astrojs/mdx": "^5.0.2",
    "@astrojs/node": "^10.0.3",
    "@astrojs/sitemap": "^3.7.1",
    "@clerk/astro": "^3.0.6",
    "@tailwindcss/vite": "^4.2.2",
    "astro": "^6.0.8",
    "tailwindcss": "^4.2.2"
  }
}
```

**Step 3: Write astro.config.mjs**
```js
// @ts-check
import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import node from '@astrojs/node';
import clerk from '@clerk/astro';

export default defineConfig({
  site: 'https://generalsystemsventures.com',
  output: 'static',
  adapter: node({ mode: 'standalone' }),
  vite: { plugins: [tailwindcss()] },
  integrations: [mdx(), sitemap(), clerk()],
});
```

**Step 4: Write tsconfig.json**
```json
{
  "extends": "astro/tsconfigs/strict",
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  }
}
```

**Step 5: Write global.css with Tailwind + Geist fonts**
```css
@import "tailwindcss";

@font-face {
  font-family: 'Geist Sans';
  src: url('/fonts/GeistVF.woff2') format('woff2');
  font-display: swap;
}
@font-face {
  font-family: 'Geist Mono';
  src: url('/fonts/GeistMonoVF.woff2') format('woff2');
  font-display: swap;
}

@theme {
  --font-sans: 'Geist Sans', system-ui, sans-serif;
  --font-mono: 'Geist Mono', ui-monospace, monospace;
  --color-bg: #09090b;
  --color-surface: #18181b;
  --color-border: #27272a;
  --color-text: #fafafa;
  --color-text-muted: #a1a1aa;
  --color-accent: #3b82f6;
}

html {
  background-color: var(--color-bg);
  color: var(--color-text);
  font-family: var(--font-sans);
}
```

**Step 6: Install dependencies**
Run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm install`

**Step 7: Commit**
```bash
git add apps/intersite/package.json apps/intersite/astro.config.mjs apps/intersite/tsconfig.json apps/intersite/src/styles/global.css apps/intersite/pnpm-lock.yaml
git commit -m "feat(intersite): scaffold Astro app with Tailwind, MDX, Clerk"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 2: Content collection schemas + pipeline validation

**Files:**
- Create: `apps/intersite/src/content/config.ts`
- Create: `apps/intersite/src/lib/content.ts`
- Create: `apps/intersite/src/content/PIPELINE.md`

**Step 1: Write content collection schemas**
```ts
// apps/intersite/src/content/config.ts
import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

const pipelineState = z.enum([
  "raw_draft",
  "texturaize_review",
  "voice_review",
  "mk_review",
  "published",
  "archived",
]);

const themes = z.array(
  z.enum([
    "emergent-systems",
    "human-machine-interface",
    "autonomous-agents",
    "generative-media",
    "infrastructure-tooling",
  ])
).default([]);

const projectSchema = z.object({
  name: z.string(),
  status: z.enum(["active", "shipped", "dormant", "early"]),
  domain: z.string(),
  themes,
  lineage: z.string().max(150).default(""),
  featured: z.boolean().default(false),
  tagline: z.string().default(""),
  repo: z.string().url().optional(),
  description: z.string(),
  what_was_learned: z.string().optional(),
  pipeline_state: pipelineState.default("raw_draft"),
  mk_approved_at: z.string().datetime().optional(),
});

const experimentSchema = z.object({
  title: z.string(),
  date: z.coerce.date(),
  tags: z.array(z.string()).default([]),
  result: z.enum(["success", "failure", "inconclusive"]),
  summary: z.string(),
  pipeline_state: pipelineState.default("raw_draft"),
  mk_approved_at: z.string().datetime().optional(),
});

const pluginSchema = z.object({
  name: z.string(),
  description: z.string(),
  notable: z.boolean().default(false),
  plugin_count: z.number().optional(),
});

const projects = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx}", base: "src/content/projects" }),
  schema: projectSchema,
});

const experiments = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx}", base: "src/content/experiments" }),
  schema: experimentSchema,
});

const plugins = defineCollection({
  loader: glob({ pattern: "**/*.{md,mdx}", base: "src/content/plugins" }),
  schema: pluginSchema,
});

export const collections = { projects, experiments, plugins };
```

**Step 2: Write getPublishedContent utility**
```ts
// apps/intersite/src/lib/content.ts
import { getCollection } from "astro:content";

export async function getPublishedContent(
  collection: "projects" | "experiments"
) {
  const entries = await getCollection(collection);
  return entries.filter(
    (e) =>
      e.data.pipeline_state === "published" &&
      e.data.mk_approved_at !== undefined
  );
}

export async function getPublishedProjects() {
  return getPublishedContent("projects");
}

export async function getFeaturedProjects() {
  const published = await getPublishedProjects();
  return published.filter((p) => p.data.featured);
}

export async function getPublishedExperiments() {
  const published = await getPublishedContent("experiments");
  return published.sort(
    (a, b) => b.data.date.valueOf() - a.data.date.valueOf()
  );
}

export async function getAllPlugins() {
  return getCollection("plugins");
}
```

**Step 3: Write PIPELINE.md**
```markdown
# Content Pipeline State Machine

## States
- `raw_draft` — auto-generated or manually created. Visible in dev only.
- `texturaize_review` — submitted to Texturaize for factual review. Visible in dev only.
- `voice_review` — returned from Texturaize, awaiting interfluence voice check.
- `mk_review` — voice-checked, awaiting mk's final approval.
- `published` — live on production. Requires `mk_approved_at` timestamp.
- `archived` — removed from production. Can return to `mk_review` for republish.

## Transitions
```
raw_draft → texturaize_review → voice_review → mk_review → published → archived
                                                                ↑              |
                                                                └──────────────┘
```

## Enforcement Seam
- **App (build time):** Zod schema validates `pipeline_state` + `mk_approved_at`. `getPublishedContent()` is the single gate. Production pages must not call `getCollection()` directly.
- **Plugins (convention):** `/intersite:generate` always writes `pipeline_state: "raw_draft"`. Only mk sets `published` via `/intersite:publish` after review.
```

**Step 4: Create content directories**
```bash
mkdir -p apps/intersite/src/content/{projects,experiments,plugins}
```

**Step 5: Commit**
```bash
git add apps/intersite/src/content/config.ts apps/intersite/src/lib/content.ts apps/intersite/src/content/PIPELINE.md
git commit -m "feat(intersite): content schemas with pipeline state machine + validation"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 3: Base layout + landing page

**Files:**
- Create: `apps/intersite/src/layouts/Base.astro`
- Create: `apps/intersite/src/pages/index.astro`
- Create: `apps/intersite/src/components/Footer.astro`

**Step 1: Write Base layout**
```astro
---
// apps/intersite/src/layouts/Base.astro
interface Props {
  title: string;
  description?: string;
}
const { title, description = "Notes from a frontier of human/machine comparative advantage" } = Astro.props;
---
<html lang="en" class="dark">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{title} — GSV</title>
  <meta name="description" content={description} />
  <link rel="sitemap" href="/sitemap-index.xml" />
</head>
<body class="bg-[var(--color-bg)] text-[var(--color-text)] min-h-screen font-sans antialiased">
  <nav class="border-b border-[var(--color-border)] px-6 py-4">
    <div class="max-w-5xl mx-auto flex items-center justify-between">
      <a href="/" class="font-mono text-sm tracking-wider uppercase text-[var(--color-text-muted)] hover:text-[var(--color-text)]">GSV</a>
      <div class="flex gap-6 text-sm text-[var(--color-text-muted)]">
        <a href="/projects/" class="hover:text-[var(--color-text)]">Projects</a>
        <a href="/experiments/" class="hover:text-[var(--color-text)]">Experiments</a>
      </div>
    </div>
  </nav>
  <main class="max-w-5xl mx-auto px-6 py-12">
    <slot />
  </main>
  <Footer />
</body>
</html>

<style>
  @import '../styles/global.css';
</style>
```

**Step 2: Write Footer component**
```astro
---
// apps/intersite/src/components/Footer.astro
---
<footer class="border-t border-[var(--color-border)] mt-24 px-6 py-8">
  <div class="max-w-5xl mx-auto flex justify-between items-center text-sm text-[var(--color-text-muted)]">
    <span class="font-mono">General Systems Ventures</span>
    <a href="mailto:mk@generalsystemsventures.com" class="hover:text-[var(--color-text)]">Contact</a>
  </div>
</footer>
```

**Step 3: Write landing page**
```astro
---
// apps/intersite/src/pages/index.astro
import Base from '../layouts/Base.astro';
import { getFeaturedProjects, getPublishedProjects, getPublishedExperiments, getAllPlugins } from '../lib/content';

const featured = await getFeaturedProjects();
const allProjects = await getPublishedProjects();
const experiments = await getPublishedExperiments();
const plugins = await getAllPlugins();
const latestExperiment = experiments[0];
---
<Base title="General Systems Ventures">
  <section class="mb-16">
    <p class="text-[var(--color-text-muted)] font-mono text-sm mb-2 uppercase tracking-wider">General Systems Ventures</p>
    <h1 class="text-3xl font-light mb-4 leading-tight">Notes from a frontier of human/machine comparative advantage</h1>
    <div class="flex gap-6 text-sm text-[var(--color-text-muted)] font-mono">
      <span>{allProjects.length} projects</span>
      <span>{plugins.length} plugins</span>
      <span>{experiments.length} experiments</span>
    </div>
  </section>

  {featured.length > 0 && (
    <section class="mb-16">
      <h2 class="text-sm font-mono text-[var(--color-text-muted)] uppercase tracking-wider mb-6">Featured</h2>
      <div class="grid gap-4">
        {featured.map((p) => (
          <a href={`/projects/${p.id}/`} class="block border border-[var(--color-border)] rounded-lg p-6 hover:border-[var(--color-accent)] transition-colors">
            <div class="flex items-center gap-3 mb-2">
              <h3 class="text-lg font-medium">{p.data.name}</h3>
              <span class="text-xs font-mono px-2 py-0.5 rounded bg-[var(--color-surface)] text-[var(--color-text-muted)]">{p.data.status}</span>
            </div>
            <p class="text-[var(--color-text-muted)] text-sm">{p.data.tagline || p.data.description}</p>
            {p.data.themes.length > 0 && (
              <div class="flex gap-2 mt-3">
                {p.data.themes.map((t) => (
                  <span class="text-xs font-mono text-[var(--color-text-muted)]">#{t}</span>
                ))}
              </div>
            )}
          </a>
        ))}
      </div>
    </section>
  )}

  {featured.length === 0 && allProjects.length === 0 && (
    <section class="mb-16 border border-[var(--color-border)] rounded-lg p-8 text-center">
      <p class="text-[var(--color-text-muted)]">Projects are published here as they clear editorial review</p>
    </section>
  )}

  {latestExperiment && (
    <section class="mb-16">
      <h2 class="text-sm font-mono text-[var(--color-text-muted)] uppercase tracking-wider mb-6">Latest Experiment</h2>
      <a href={`/experiments/${latestExperiment.id}/`} class="block border border-[var(--color-border)] rounded-lg p-6 hover:border-[var(--color-accent)] transition-colors">
        <div class="flex items-center gap-3 mb-2">
          <h3 class="font-medium">{latestExperiment.data.title}</h3>
          <span class={`text-xs font-mono px-2 py-0.5 rounded ${
            latestExperiment.data.result === 'success' ? 'bg-green-900/30 text-green-400' :
            latestExperiment.data.result === 'failure' ? 'bg-red-900/30 text-red-400' :
            'bg-yellow-900/30 text-yellow-400'
          }`}>{latestExperiment.data.result}</span>
        </div>
        <p class="text-[var(--color-text-muted)] text-sm">{latestExperiment.data.summary}</p>
      </a>
    </section>
  )}
</Base>
```

**Step 4: Commit**
```bash
git add apps/intersite/src/layouts/Base.astro apps/intersite/src/pages/index.astro apps/intersite/src/components/Footer.astro
git commit -m "feat(intersite): base layout, landing page, footer with contact link"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 4: Project pages — index, detail, Sylveste parent

**Files:**
- Create: `apps/intersite/src/pages/projects/index.astro`
- Create: `apps/intersite/src/pages/projects/[slug].astro`
- Create: `apps/intersite/src/pages/projects/sylveste/index.astro`
- Create: `apps/intersite/src/components/StatusBadge.astro`
- Create: `apps/intersite/src/components/ThemeTag.astro`

**Step 1: Write StatusBadge and ThemeTag components**
StatusBadge: renders colored badge for active/shipped/dormant/early.
ThemeTag: renders `#theme-name` in muted mono text.

**Step 2: Write /projects/ index page**
- Queries `getPublishedProjects()` — never `getCollection()` directly
- Renders featured tier (featured=true) above fold with full card treatment
- Renders full roster grid below with domain/status filters (client-side JS filter)
- Dormant projects hidden by default, toggle to show
- Empty state when no published projects

**Step 3: Write /projects/[slug] detail page**
- `getStaticPaths()` from `getPublishedProjects()`
- Renders: name, status badge, tagline, description, lineage, themes, repo link
- For dormant projects: renders `what_was_learned` section
- MDX body rendered below metadata

**Step 4: Write /projects/sylveste/ parent page**
- Hardcoded Sylveste overview
- Links to pillar subpages and plugin index at `/projects/sylveste/plugins/`
- Plugin count from `getAllPlugins().length`

**Step 5: Commit**
```bash
git add apps/intersite/src/pages/projects/ apps/intersite/src/components/StatusBadge.astro apps/intersite/src/components/ThemeTag.astro
git commit -m "feat(intersite): project pages — index with featured tier, detail, sylveste parent"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 5: Experiment pages — index + detail

**Files:**
- Create: `apps/intersite/src/pages/experiments/index.astro`
- Create: `apps/intersite/src/pages/experiments/[slug].astro`
- Create: `apps/intersite/src/components/ResultBadge.astro`

**Step 1: Write ResultBadge component**
Green for success, red for failure, yellow for inconclusive.

**Step 2: Write /experiments/ index page**
- Queries `getPublishedExperiments()` — reverse chronological
- Renders cards with title, date, result badge, summary
- Empty state: "Experiments are published here as they complete"

**Step 3: Write /experiments/[slug] detail page**
- `getStaticPaths()` from `getPublishedExperiments()`
- Renders: title, date, result badge, tags, MDX body

**Step 4: Commit**
```bash
git add apps/intersite/src/pages/experiments/ apps/intersite/src/components/ResultBadge.astro
git commit -m "feat(intersite): experiment pages — index + detail with result badges"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 6: Plugin index page

**Files:**
- Create: `apps/intersite/src/pages/projects/sylveste/plugins/index.astro`
- Create: `apps/intersite/src/pages/projects/sylveste/plugins/[slug].astro`

**Step 1: Write plugin index page**
- Queries `getAllPlugins()`
- Renders searchable grid (client-side JS filter by name/description)
- Each tile: plugin name + one-liner description
- Notable plugins link to detail page; others are grid-only

**Step 2: Write plugin detail page**
- `getStaticPaths()` filtered to `notable === true` only
- Renders: name, description, MDX body

**Step 3: Commit**
```bash
git add apps/intersite/src/pages/projects/sylveste/plugins/
git commit -m "feat(intersite): plugin index with search + notable detail pages"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 7: Seed content — project roster

**Files:**
- Create: `apps/intersite/src/content/projects/sylveste.md`
- Create: `apps/intersite/src/content/projects/texturaize.md`
- Create: `apps/intersite/src/content/projects/typhon.md`
- Create: `apps/intersite/src/content/projects/horza.md`
- Create: `apps/intersite/src/content/projects/enozo.md`
- Create: `apps/intersite/src/content/projects/pattern-royale.md`
- Create: `apps/intersite/src/content/projects/nartopo.md`
- Create: `apps/intersite/src/content/projects/agmodb.md`
- Create: `apps/intersite/src/content/projects/auraken.md`
- Create: `apps/intersite/src/content/projects/shadow-work.md`
- Create: `apps/intersite/src/content/projects/elf-revel.md`
- Create: `apps/intersite/src/content/projects/lowbeer.md`
- Create: `apps/intersite/src/content/projects/garden-salon.md`
- Create: `apps/intersite/src/content/projects/duellm.md`

**Step 1: Write all 14 project content files**
Each file has frontmatter matching `projectSchema`. All start at `pipeline_state: "raw_draft"` — they won't render in production until mk reviews and promotes them.

Source data from: each project's CLAUDE.md or AGENTS.md (for Sylveste subprojects), package.json description fields (for standalone repos). Use the `themes` controlled vocabulary. Set `featured: true` for Sylveste, texturaize, and pattern-royale as initial featured tier.

Example:
```markdown
---
name: Sylveste
status: active
domain: autonomous-development
themes: ["autonomous-agents", "infrastructure-tooling"]
lineage: The root — an autonomous software development agency
featured: true
tagline: Autonomous software development agency platform
repo: https://github.com/mistakeknot/Sylveste
description: "Monorepo for an open-source autonomous software development agency. 6 pillars across 3 layers: OS kernel, agent intelligence, plugin ecosystem, and application surfaces."
pipeline_state: raw_draft
---

Sylveste is the parent project...
```

**Step 2: Commit**
```bash
git add apps/intersite/src/content/projects/
git commit -m "feat(intersite): seed 14 project content files (raw_draft)"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
</verify>

---

### Task 8: Seed content — experiments + plugins

**Files:**
- Create: 3 experiment content files in `apps/intersite/src/content/experiments/`
- Create: plugin content files generated from `interverse/*/`

**Step 1: Write 3 seed experiments as narratives**
Source from recent interlab campaigns. Write as lab notebook entries (hypothesis, method, observation), not test reports.

**Step 2: Generate plugin content files**
Script that reads `interverse/*/.claude-plugin/plugin.json` for each plugin, extracts `name` and `description`, checks for `notable: true` in CLAUDE.md frontmatter, and writes a minimal content file per plugin.

Write manifest to `apps/intersite/src/content/plugins/.manifest.json` tracking generated slugs.

**Step 3: Commit**
```bash
git add apps/intersite/src/content/experiments/ apps/intersite/src/content/plugins/
git commit -m "feat(intersite): seed 3 experiments + generate plugin index content"
```

<verify>
- run: `cd /home/mk/projects/Sylveste/apps/intersite && pnpm build`
  expect: exit 0
- run: `ls apps/intersite/src/content/plugins/ | wc -l`
  expect: contains "5"
</verify>

---

### Task 9: intersite Interverse plugin scaffold

**Files:**
- Create: `interverse/intersite/.claude-plugin/plugin.json`
- Create: `interverse/intersite/CLAUDE.md`
- Create: `interverse/intersite/AGENTS.md`
- Create: `interverse/intersite/skills/generate/SKILL.md`
- Create: `interverse/intersite/skills/status/SKILL.md`

**Step 1: Write plugin.json**
```json
{
  "name": "intersite",
  "version": "0.1.0",
  "description": "GSV portfolio site content generation and pipeline management",
  "skills": [
    { "name": "generate", "path": "skills/generate/SKILL.md" },
    { "name": "status", "path": "skills/status/SKILL.md" }
  ]
}
```

**Step 2: Write CLAUDE.md**
Document the plugin's purpose, content pipeline seam (plugin writes `raw_draft`, app validates at build time), and the `INTERSITE_CONTENT_ROOT` convention.

**Step 3: Write generate skill**
`/intersite:generate [project-slug]` — reads project's CLAUDE.md/AGENTS.md/beads, generates content file with `pipeline_state: "raw_draft"`. Uses interlock `reserve_files` to prevent concurrent generation. Never writes `pipeline_state: "published"`.

**Step 4: Write status skill**
`/intersite:status` — lists all content files across projects/experiments/plugins collections with their `pipeline_state`. Groups by state. Shows counts.

**Step 5: Commit**
```bash
git add interverse/intersite/
git commit -m "feat(intersite): interverse plugin with generate + status commands"
```

<verify>
- run: `cat interverse/intersite/.claude-plugin/plugin.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['name'])"`
  expect: contains "intersite"
</verify>

---

### Task 10: CLAUDE.md + AGENTS.md for intersite app

**Files:**
- Create: `apps/intersite/CLAUDE.md`
- Create: `apps/intersite/AGENTS.md`

**Step 1: Write CLAUDE.md**
Document: build/start commands, content pipeline rules (only `getPublishedContent()` for production pages, never direct `getCollection()`), Cloudflare Tunnel deploy process, the pipeline validation seam, and Clerk auth setup.

**Step 2: Write AGENTS.md**
Document: directory structure, content collection schemas, pipeline states, deploy target (sleeper-service via Cloudflare Tunnel), relationship to interblog (one-way content sync).

**Step 3: Commit**
```bash
git add apps/intersite/CLAUDE.md apps/intersite/AGENTS.md
git commit -m "docs(intersite): CLAUDE.md + AGENTS.md with pipeline rules and deploy process"
```

---

### Task 11: Cloudflare Tunnel deploy to sleeper-service

**Files:**
- Modify: `~/.cloudflared/config.yml` on sleeper-service (via SSH)
- Create: `~/.config/systemd/user/intersite.service` on sleeper-service

**Step 1: Build the site locally and verify**
```bash
cd /home/mk/projects/Sylveste/apps/intersite
pnpm build && pnpm start
# Verify at http://localhost:4321
```

**Step 2: Update cloudflared config on sleeper-service**
Add intersite ingress rule to existing tunnel config. intersite runs on a different port than interblog (e.g., 4322).

**Step 3: Create systemd service**
```ini
[Unit]
Description=intersite Astro server
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/mk/projects/Sylveste/apps/intersite
ExecStart=/usr/bin/node dist/server/entry.mjs
Environment=PORT=4322
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
```

**Step 4: Enable and start**
```bash
systemctl --user daemon-reload
systemctl --user enable intersite
systemctl --user start intersite
```

**Step 5: Restart cloudflared tunnel**
```bash
systemctl --user restart cloudflared
```

**Step 6: Verify site is live**
```bash
curl -sI https://generalsystemsventures.com | head -5
```

**Step 7: Commit config files**
```bash
git add apps/intersite/
git commit -m "feat(intersite): cloudflare tunnel deploy config + systemd service"
```

<verify>
- run: `curl -s https://generalsystemsventures.com | grep -o "GSV"`
  expect: contains "GSV"
</verify>

---

## Original Intent (cut from this plan, preserved for future iterations)

The full PRD has 3 epic tracks. This plan covers **intersite-static** only:

| Deferred Epic | Features | Trigger |
|---------------|----------|---------|
| **intersite-blog-migration** | F3 (blog fold-in), F5 (full pipeline enforcement) | After static site is live and stable |
| **intersite-relay** | F6 (xterm.js + WebSocket PTY relay), F8 (publish command) | After blog migration complete |

F5 is partially implemented in this plan (schema + `getPublishedContent()` gate), but the full enforcement (MDX import stripping, preview URL gating, Texturaize webhook HMAC verification) ships with the blog-migration epic.
