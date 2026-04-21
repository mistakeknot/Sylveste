---
artifact_type: research
bead: sylveste-ynh7
---
# Skill listing contribution audit (2026-04-21)

**Sampled:** 156 unique skills across 62 plugins (post dedup of marketplace + cache layouts).
**Total description bytes:** 32,330

## Top 20 plugins by description contribution

| plugin | skills | desc_bytes | mcp_calls_30d | flag | examples |
|---|---:|---:|---:|:---:|---|
| vercel | 26 | 5,661 | 0 | COLD | auth, nextjs, shadcn |
| plugin-dev | 7 | 2,939 | 0 | COLD | plugin-settings, mcp-integration, plugin-structure |
| jetty | 4 | 2,642 | 0 | COLD | jetty, jetty-setup, create-runbook |
| clavain | 17 | 2,563 | 0 | HARD-EXCL | lane, ship, galiana |
| mcp-server-dev | 3 | 1,342 | 0 | COLD | build-mcpb, build-mcp-app, build-mcp-server |
| interbrowse | 5 | 1,215 | 0 | COLD | browse, research, teardown |
| interfluence | 6 | 1,121 | 11 |  | apply, ingest, refine |
| notion | 4 | 1,029 | 84 |  | knowledge-capture, meeting-intelligence, research-documentation |
| dotenv | 2 | 933 | 0 | COLD | dotenv, dotenvx |
| interplug | 3 | 596 | 0 | COLD | plugin, validate, troubleshoot |
| interjawn | 2 | 440 | 0 |  | add-jawn, record-jawn |
| telegram | 2 | 435 | 0 |  | access, configure |
| discord | 2 | 430 | 0 |  | access, configure |
| interlab | 2 | 421 | 27 |  | autoresearch, autoresearch-multi |
| intermonk | 1 | 418 | 0 |  | dialectic |
| imessage | 2 | 410 | 0 |  | access, configure |
| intertest | 3 | 395 | 0 |  | systematic-debugging, test-driven-development, verification-before-completion |
| interskill | 2 | 392 | 0 |  | skill, audit |
| interject | 6 | 371 | 1 |  | scan, inbox, status |
| intersearch | 1 | 364 | 0 | HARD-EXCL | session-search |

## Cold-plugin candidates (7 plugins, 15,328 bytes total ≈ 4034 tokens)

Criteria: ≥500 bytes of description contribution AND <5 MCP calls in last 30 days AND not in HARD_EXCLUDE list.

- **vercel** — 26 skills, 5,661 bytes (~1490 tokens), 0 MCP calls/30d. Sample skills: auth, nextjs, shadcn.
- **plugin-dev** — 7 skills, 2,939 bytes (~773 tokens), 0 MCP calls/30d. Sample skills: plugin-settings, mcp-integration, plugin-structure.
- **jetty** — 4 skills, 2,642 bytes (~695 tokens), 0 MCP calls/30d. Sample skills: jetty, jetty-setup, create-runbook.
- **mcp-server-dev** — 3 skills, 1,342 bytes (~353 tokens), 0 MCP calls/30d. Sample skills: build-mcpb, build-mcp-app, build-mcp-server.
- **interbrowse** — 5 skills, 1,215 bytes (~320 tokens), 0 MCP calls/30d. Sample skills: browse, research, teardown.
- **dotenv** — 2 skills, 933 bytes (~246 tokens), 0 MCP calls/30d. Sample skills: dotenv, dotenvx.
- **interplug** — 3 skills, 596 bytes (~157 tokens), 0 MCP calls/30d. Sample skills: plugin, validate, troubleshoot.

## Hard-excluded workflow plugins

Plugins that appear cold by MCP signal alone but are workflow-critical (use the Skill tool rather than MCP):

- **clavain** — 17 skills, 2,563 bytes. Kept.
- **intersearch** — 1 skills, 364 bytes. Kept.
- **interdev** — 2 skills, 360 bytes. Kept.
- **interstat** — 4 skills, 260 bytes. Kept.
- **interflux** — 1 skills, 201 bytes. Kept.
- **interpath** — 1 skills, 195 bytes. Kept.
- **interwatch** — 1 skills, 144 bytes. Kept.
- **intermem** — 2 skills, 83 bytes. Kept.

## Recommendation for sylveste-ynh7 Task 4

Surface all 7 cold candidates in a multiSelect AskUserQuestion. User picks which to disable. If all 7 are approved for disable, headline savings: ~4034 tokens from external-plugin contribution alone — exceeds the 500-token in-scope floor on its own.
