---
artifact_type: prd
bead: Sylveste-p83z
stage: strategized
brainstorm: docs/brainstorms/2026-03-24-f9-sse-data-pipe.md
---

# PRD: F9 SSE Streaming Data Pipe

## Problem Statement

Meadowsyn's real-data experiment (F18) requires manual intervention to refresh data — someone must run `watch -n 5 generate-snapshot.sh`. This makes the ops room unusable as a persistent display. The polling architecture adds 5-10s latency, defeating the purpose of real-time factory awareness.

## Solution

Add a `factory-stream` SSE endpoint to clavain-cli that streams factory state to browser clients, and upgrade DataPipe to consume SSE as its primary transport with polling fallback.

## Requirements

### P0 — Must Have

1. **SSE server endpoint** in clavain-cli that streams unified snapshots (fleet + queue + WIP)
2. **DataPipe v2** with `EventSource` transport, automatic fallback to polling when SSE unavailable
3. **F18 experiment updated** to use SSE when `?sse=<url>` param is present
4. **Heartbeat events** every 10s to detect connection staleness
5. **CORS support** for `dev.meadowsyn.com` and `meadowsyn.com` origins

### P1 — Should Have

6. **Delta events** for agent status transitions (reduces bandwidth, enables animation triggers)
7. **Caddy reverse proxy config** for `stream.meadowsyn.com` subdomain
8. **systemd unit** for persistent factory-stream process on sleeper-service
9. **Sequence numbers** on events for gap detection

### P2 — Nice to Have

10. **Beads data** merged into snapshots (bd list refresh at 30s interval)
11. **IdeaGUI roster** enrichment via fsnotify on `transfer/ideagui.json`
12. **Last-Event-ID** reconnect support with replay buffer

## Architecture

```
┌─────────────────┐     SSE      ┌──────────────┐     iframe     ┌─────────────┐
│  factory-stream │ ──────────→  │  DataPipe v2  │ ─────────────→ │  F18 / F11  │
│  (Go, :8401)    │              │  (browser JS) │                │  experiment  │
│                 │              │               │                │             │
│  sources:       │   fallback   │  EventSource  │                │  Cytoscape  │
│  - tmux sessions│ ←──poll───── │  + poll       │                │  + glow     │
│  - bd list      │              │  + ring buffer│                └─────────────┘
│  - ideagui.json │              └──────────────┘
└─────────────────┘
        │
        │ Caddy reverse proxy
        ▼
  stream.meadowsyn.com
```

## Acceptance Criteria

1. Opening F18 with `?sse=http://localhost:8401/stream` shows live agent data without running generate-snapshot.sh
2. Killing the SSE server causes DataPipe to fall back to polling within 5s (no visible disruption)
3. Reconnecting after network drop resumes streaming without page reload
4. HUD shows "LIVE" badge when SSE connected, "POLLING" when falling back
5. `factory-stream` process uses <20MB RSS and <2% CPU at 5s refresh with 3 connected clients

## Non-Goals

- Authentication (password-protected via Caddy basic auth if needed)
- Bidirectional communication (no WebSocket)
- Streaming bead dependency graphs (separate scope)
- Production deployment to external infrastructure (sleeper-service only)

## Risks

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| CORS issues with Vercel + sleeper-service | Medium | Test with actual Vercel domain; Caddy config handles CORS headers |
| tmux data collection blocks SSE goroutine | Low | Data collection runs in separate goroutine with timeout |
| Browser EventSource reconnect floods server | Low | Server-side connection limiting; EventSource retry field |
