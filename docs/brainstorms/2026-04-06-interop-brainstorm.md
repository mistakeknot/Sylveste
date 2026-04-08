---
artifact_type: brainstorm
bead: sylveste-bcok
stage: discover
---

# interop: Unified Integration Fabric

## What We're Building

**interop** is a Go-based integration daemon that replaces interkasten and becomes the single hub for all external system sync in Sylveste. It connects Notion, GitHub, beads, Auraken, and the local file system through an adapter-based event-driven architecture. Google Drive and other integrations follow the same adapter pattern later.

**Day-1 data flows:**
1. **Beads ↔ GitHub Issues** — bidirectional sync (create/close/comment)
2. **Notion ↔ Beads** — port interkasten's core sync, rewritten in Go
3. **Notion pages ↔ local files** — bidirectional markdown sync
4. **Notion ↔ GitHub repo file system** — sync Notion content to/from repo files

**Core identity:** interop is the integration *fabric*, not just another sync plugin. Every external system gets an adapter; the hub routes events, transforms data, and resolves conflicts between them.

## Why This Approach

**Subsume interkasten.** interkasten is TypeScript, tightly coupled to Notion, and 27 MCP handlers deep. Rather than bolting GitHub support onto a Notion-specific plugin, we build a clean adapter architecture in Go where Notion is one adapter among equals. interkasten gets archived after migration.

**Go, not TypeScript.** The user chose Go for consistency with Clavain (L2 OS) and interlock. Go's concurrency model (goroutines + channels) maps naturally to an event-driven hub with multiple adapter goroutine pools. Single static binary simplifies deployment on zklw.

**Event-driven with webhooks.** Both GitHub and Notion support webhooks. Instead of interkasten's 60s polling, interop receives push notifications and reacts immediately. Polling exists only as fallback for systems without webhook support (local file system watcher uses fsnotify).

**Monolith with goroutine isolation.** Single binary, but each adapter runs in its own goroutine pool with panic recovery and circuit breakers. A crashing Notion adapter doesn't take down GitHub sync. Natural Go concurrency idiom.

## Key Decisions

1. **Language: Go** — matches Clavain/interlock ecosystem, single binary deployment, goroutine concurrency model for multi-adapter hub
2. **Architecture: monolith with goroutine isolation** — one binary, per-adapter fault isolation via goroutine pools + panic recovery + circuit breakers
3. **Sync model: event-driven hub** — webhook-first (GitHub, Notion), fsnotify for local files, polling as last resort
4. **Deployment: long-running daemon on zklw** — Docker Compose alongside Auraken. Caddy reverse proxy for webhook ingestion. MCP server mode for Claude Code sessions.
5. **interkasten fate: subsume then archive** — port Notion sync capability into interop's Notion adapter, then archive interkasten
6. **Beads access: via `bd` CLI only** — consistent with ecosystem convention, no direct SQLite/Dolt access
7. **Adapter interface** — each system implements a standard `Adapter` interface: `Start()`, `Stop()`, `HandleEvent(Event)`, `Emit() <-chan Event`
8. **Conflict resolution** — three-way merge for content (ported concept from interkasten), last-write-wins for metadata, configurable per-adapter

## Day-1 Adapters

| Adapter | Webhook | Sync Direction | Primary Entities |
|---------|---------|---------------|-----------------|
| GitHub | yes (GitHub Apps) | bidirectional | Issues, PRs, comments, repo files |
| Notion | yes (Notion webhooks) | bidirectional | Pages, databases, blocks → markdown |
| Beads | no (event watch) | bidirectional | Issues, states, events |
| Local FS | no (fsnotify) | bidirectional | Markdown files, project files |

## Architecture Sketch

```
                     ┌─────────────────────┐
  Webhook ──────────►│   interop daemon     │◄──── MCP (Claude Code)
  (Caddy)            │                      │
                     │  ┌────────────────┐  │
                     │  │   Event Bus    │  │
                     │  │  (channels)    │  │
                     │  └──┬──┬──┬──┬───┘  │
                     │     │  │  │  │       │
                     │  ┌──▼┐┌▼──┐┌▼─┐┌▼──┐│
                     │  │GH ││Not││Bd ││FS ││
                     │  │   ││ion││   ││   ││
                     │  └───┘└───┘└───┘└───┘│
                     │  (goroutine pools)   │
                     └─────────────────────┘
```

## Open Questions

1. **MCP server integration** — should interop expose MCP tools directly (like interlock's Go MCP server) or delegate to a thin Claude Code plugin wrapper?
2. **Auraken adapter scope** — day-1 or day-2? Auraken has its own bridge.py for Intercore signals. Does interop need an Auraken adapter, or does it rely on Intercore as the intermediary?
3. **Identity mapping** — GitHub user ↔ Notion user ↔ beads assignee. Where does the mapping live? Config file? Separate identity service?
4. **Notion webhook setup** — Notion webhooks require an integration with webhook URL. Is this configured per-workspace or globally?
5. **Migration path** — how do we migrate interkasten's existing sync state (WAL, conflict history, tracked databases) into interop?
