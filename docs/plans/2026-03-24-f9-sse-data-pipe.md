---
artifact_type: plan
bead: Sylveste-p83z
prd: docs/prd/2026-03-24-f9-sse-data-pipe.md
brainstorm: docs/brainstorms/2026-03-24-f9-sse-data-pipe.md
---

# Plan: F9 SSE Streaming Data Pipe

## Summary

Add `clavain-cli factory-stream` SSE endpoint + upgrade DataPipe to dual-transport (SSE primary, polling fallback). Update F18 real-data experiment to use live streaming.

## Implementation Steps

### Step 1: `factory_stream.go` — SSE server in clavain-cli

**File:** `os/Clavain/cmd/clavain-cli/factory_stream.go` (new)

Create `cmdFactoryStream(args)` subcommand:
- Parse `--port` flag (default 8401), `--interval` flag (default 5s)
- Start HTTP server with `/stream` endpoint
- `/stream` handler:
  - Set `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`
  - CORS headers: `Access-Control-Allow-Origin` from `--cors-origins` flag (default `*`)
  - On connect: send full `snapshot` event immediately
  - Loop: every `interval`, call `gatherFactoryStatus()`, marshal to JSON, send as `event: snapshot`
  - Detect agent status deltas between snapshots → send `event: delta` with changed agents only
  - Heartbeat: `event: heartbeat` every 10s with sequence number
  - Each event gets `id:` field (monotonic counter) for `Last-Event-ID` reconnect
- `/health` endpoint: returns `{"ok":true,"clients":<count>,"uptime":"..."}`
- Connection tracking: count active SSE clients (increment on connect, decrement on disconnect via `CloseNotifier` / context cancellation)
- Graceful shutdown on SIGTERM/SIGINT

Key design decisions:
- Reuse `gatherFactoryStatus()` directly — no code duplication
- One goroutine per connected client (Go's HTTP server already does this)
- `Flusher` interface for streaming: `flusher, ok := w.(http.Flusher)` — flush after each event
- Delta detection: compare `fleetAgent.Active` between consecutive snapshots

### Step 2: Register subcommand in `main.go`

**File:** `os/Clavain/cmd/clavain-cli/main.go`

- Add `case "factory-stream":` → `err = cmdFactoryStream(args)`
- Add usage line in help text under Factory section

### Step 3: DataPipe v2 — SSE transport

**File:** `apps/Meadowsyn/experiments/split-flap/public/data-static/data-pipe.js` (edit)
**Also sync:** `apps/Meadowsyn/experiments/data-static/data-pipe.js`

Add SSE support to DataPipe constructor:
- New option: `{ sse: 'http://localhost:8401/stream' }`
- When `sse` is set:
  - Create `EventSource(url)` as primary transport
  - On `snapshot` event: parse JSON, push to ring buffer, notify subscribers
  - On `delta` event: parse JSON, merge into latest snapshot, notify subscribers
  - On `error`: EventSource auto-reconnects; after 3 consecutive failures, fall back to polling
  - On `open`: cancel any active polling timer
- New method: `getTransport()` → returns `'sse'` | `'polling'` | `'disconnected'`
- Existing polling works unchanged when `sse` is not set

### Step 4: Update F18 real-data experiment

**File:** `apps/Meadowsyn/experiments/real-data/index.html` (edit)
**Also sync:** `apps/Meadowsyn/experiments/split-flap/public/real-data/index.html`

- Read `?sse=<url>` query param
- Pass to DataPipe constructor: `new DataPipe({ sse: sseUrl, url: 'snapshot.json', interval: 5000 })`
- Update source badge: "LIVE" (green) when SSE connected, "POLLING" (amber) when falling back, "STALE" (red) when disconnected
- Subscribe to `pipe.on('transport', ...)` to update badge reactively

### Step 5: Deployment config

**File:** `apps/Meadowsyn/deploy/factory-stream.service` (new)
- systemd unit for `clavain-cli factory-stream --port 8401 --cors-origins "https://dev.meadowsyn.com,https://meadowsyn.com"`

**File:** `apps/Meadowsyn/deploy/Caddyfile.meadowsyn-stream` (new)
- Reverse proxy `stream.meadowsyn.com` → `localhost:8401`
- TLS via Cloudflare DNS challenge (existing pattern from IdeaGUI webhook)

### Step 6: Build and test

- `cd os/Clavain/cmd/clavain-cli && go build -o /tmp/clavain-cli-test .`
- Run `/tmp/clavain-cli-test factory-stream --port 8401` in background
- `curl -N http://localhost:8401/stream` — verify SSE events stream
- Open F18 with `?sse=http://localhost:8401/stream` — verify live data renders
- Kill server → verify fallback to polling within 5s
- Restart server → verify SSE reconnects automatically

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `os/Clavain/cmd/clavain-cli/factory_stream.go` | Create | ~180 |
| `os/Clavain/cmd/clavain-cli/main.go` | Edit | ~5 |
| `apps/Meadowsyn/experiments/split-flap/public/data-static/data-pipe.js` | Edit | ~80 |
| `apps/Meadowsyn/experiments/data-static/data-pipe.js` | Sync | same |
| `apps/Meadowsyn/experiments/real-data/index.html` | Edit | ~15 |
| `apps/Meadowsyn/experiments/split-flap/public/real-data/index.html` | Sync | same |
| `apps/Meadowsyn/deploy/factory-stream.service` | Create | ~15 |
| `apps/Meadowsyn/deploy/Caddyfile.meadowsyn-stream` | Create | ~12 |

## Test Strategy

1. **Unit**: SSE event formatting (correct `event:`, `data:`, `id:` fields)
2. **Integration**: Start server, connect with curl, verify event stream
3. **Browser**: F18 with `?sse=` param shows live data, badge shows LIVE
4. **Fallback**: Kill server mid-stream → badge changes to POLLING → restart → reconnects
5. **Load**: 3 browser tabs open simultaneously → server health shows 3 clients, <20MB RSS

## Risks & Mitigations

- **`gatherFactoryStatus()` is slow (~200ms for tmux + bd list)**: Run in separate goroutine, serve cached result to SSE clients. Cache TTL = interval.
- **CORS with Vercel**: Test with actual `dev.meadowsyn.com` domain before deploying Caddy.
- **Go build breaks**: clavain-cli has existing tests — run `go test ./...` after changes.
