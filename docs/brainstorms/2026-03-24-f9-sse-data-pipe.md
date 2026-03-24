---
artifact_type: brainstorm
bead: Demarch-p83z
stage: discover
---

# Brainstorm: F9 SSE Streaming Data Pipe

## Problem

F18 (real-data) currently works via a manual `generate-snapshot.sh` → `snapshot.json` → DataPipe polling loop. This has three problems:

1. **Manual refresh**: Someone must run `watch -n 5 generate-snapshot.sh` on the server. No cron exists.
2. **Latency**: 5-second poll interval + file write = 5-10s stale data. For an ops room, sub-second would be ideal.
3. **No incremental updates**: Every poll re-fetches the full snapshot (~5KB). At 61 agents this is fine, but at scale it wastes bandwidth.

## Design Space

### Architecture: Where does the SSE server run?

**Option A: Standalone Go binary (clavain-cli extension)**
- Add `clavain-cli factory-stream` subcommand that serves SSE on a port
- Reads from the same sources as `factory-status` (tmux, beads, IdeaGUI)
- Runs on sleeper-service alongside the factory
- Pro: single binary, no dependencies, reuses existing data collection
- Con: couples streaming to clavain-cli release cycle

**Option B: Lightweight Python/Node SSE bridge**
- Tiny server that shells out to `clavain-cli factory-status --json` on interval and streams via SSE
- Pro: trivial to implement, decoupled from clavain-cli
- Con: extra process, shell-out overhead (~200ms per call)

**Option C: Go microservice in apps/Meadowsyn/**
- Dedicated streaming server for Meadowsyn data
- Reads factory-status, bd list, IdeaGUI directly
- Pro: clean separation, can add Meadowsyn-specific transforms
- Con: duplicates data collection logic from clavain-cli

→ **Selected: Option A** — `clavain-cli factory-stream` is the cleanest path. The data collection already exists in clavain-cli. Adding SSE output is ~150 lines of Go. All experiments benefit from a single streaming endpoint.

### Transport: How does the browser consume SSE?

**DataPipe v2: Dual-transport**
- Primary: `EventSource` connection to SSE endpoint
- Fallback: polling (current behavior) when SSE unavailable (file://, CORS blocked, server down)
- Auto-reconnect with exponential backoff (EventSource handles this natively)
- Ring buffer history works identically — SSE events just replace poll results

### Event Format

```
event: snapshot
data: {"timestamp":"...","fleet":{...},"queue":{...},"beads":[...]}

event: delta
data: {"type":"agent_status","agent":"clavain-1","from":"idle","to":"executing"}

event: heartbeat
data: {"ts":"...","seq":42}
```

Three event types:
1. **snapshot**: Full state, sent on connect and every 30s (catchup for late joiners)
2. **delta**: Incremental change, sent on each state transition (~100-500 bytes)
3. **heartbeat**: Keepalive every 10s, carries sequence number for gap detection

### CORS & Deployment

- SSE server runs on `stream.meadowsyn.com` (or `api.meadowsyn.com`)
- CORS headers allow `dev.meadowsyn.com` and `meadowsyn.com`
- Optional: simple auth via query param token (not cookies — SSE doesn't support custom headers)
- Caddy reverse proxy on sleeper-service (already runs for IdeaGUI webhook)

### Data Sources

| Source | Command | Refresh | Size |
|--------|---------|---------|------|
| Fleet + WIP | `clavain-cli factory-status --json` | 5s | ~4KB |
| Beads | `bd list --format=json --status=open,in_progress` | 30s | ~8KB |
| IdeaGUI roster | `transfer/ideagui.json` | on change (fsnotify) | ~15KB |

Fleet refreshes fast (5s). Beads and roster are slower-moving — refresh at 30s and on-change respectively. Snapshot event merges all three.

## Scope for This Bead

**In scope:**
1. `clavain-cli factory-stream` subcommand — SSE server with snapshot + heartbeat events
2. `DataPipe` v2 — add EventSource transport with fallback to polling
3. Deploy config: Caddy reverse proxy rule, systemd unit for factory-stream
4. Update F18 (real-data) to use SSE when available
5. Delta events for agent status changes (diff detection in the server)

**Out of scope (future):**
- Authentication / access control beyond CORS
- WebSocket upgrade (SSE is sufficient for unidirectional server→client)
- Bead dependency graph streaming (complex, handle in separate bead)
- Theme derivation from title tags (F18 already stubs this)

## Key Decisions

1. **Go, not Python** — clavain-cli is Go, and SSE in Go is ~50 lines with `net/http`. No new runtime dependency.
2. **Snapshot + delta, not delta-only** — Late joiners and reconnectors need full state. Delta-only requires reliable ordered delivery which SSE doesn't guarantee across reconnects.
3. **DataPipe stays generic** — The SSE transport is opt-in via `{ sse: 'http://...' }` constructor option. Experiments that don't want SSE keep working with polling unchanged.
4. **No WebSocket** — SSE is simpler, auto-reconnects, works through HTTP proxies. We don't need client→server communication.
5. **Caddy, not nginx** — Already running on sleeper-service for IdeaGUI webhook pipeline.

## Open Questions

1. Should `factory-stream` embed the bead-list refresh, or should there be a separate beads SSE stream that the client merges?
2. Port allocation: fixed port (e.g., 8401) or dynamic via Caddy upstream?
3. Should the generate-snapshot.sh script be kept as a fallback data source, or can we deprecate it once SSE works?
