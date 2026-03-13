# Brainstorm: Skaffen Web Search Built-in Tool

**Bead:** Demarch-6i0.20
**Date:** 2026-03-12
**Status:** brainstorm

## Problem

4 of 5 competitors have web search: Claude Code (WebSearch + WebFetch), Gemini (Google grounding), Amp (web_search + read_web_page). Skaffen has no web search capability, forcing users to manually paste search results or leave the agent to work without current documentation, API references, or error context.

## Existing Infrastructure

Demarch already has 90% of the web search plumbing:

- **intersearch** (`interverse/intersearch/src/intersearch/exa.py`) — async Exa API client with semantic search, autoprompt, result deduplication, highlighting, graceful degradation on missing API key
- **Exa API** — endpoint `https://api.exa.ai/search`, auth via `EXA_API_KEY` header, returns title/url/text/highlights/score/publishedDate
- **intercore redaction** — `CategoryExaAPIKey` already in redaction types (credential handling exists)
- **intersearch MCP server** — exists but only exposes embedding tools, not web search

## Design Options

### Option A: Native Go Tool (Recommended)

Add `WebSearchTool` and `WebFetchTool` to `internal/tool/` as built-in tools, implementing the `tool.Tool` interface directly. Exa API client in Go, no Python dependency.

**Pros:**
- Zero subprocess overhead, lowest latency (~200-400ms per search)
- Phase-gated via existing `tool.Registry` — brainstorm + plan + build phases
- Consistent with how Read/Write/Bash are implemented
- No external process to manage or crash
- Trust system integration (Prompt for first use, then Allow)

**Cons:**
- Duplicates Exa client logic (Go vs existing Python)
- Skaffen-specific — other Demarch tools can't reuse directly

**Scope:** ~300 lines Go (tool + Exa HTTP client + tests)

### Option B: MCP Server (intersearch)

Expose Exa search as an MCP tool in the existing intersearch server. Skaffen loads via MCP manager.

**Pros:**
- Reuses existing Python Exa client
- All Demarch tools get web search (not just Skaffen)
- Matches ecosystem pattern (MCP is the extensibility model)

**Cons:**
- Subprocess overhead (Python startup + stdio IPC)
- Requires intersearch to be installed and running
- Phase gating through MCP plugin config, less granular
- Additional failure mode (intersearch crashes)

**Scope:** ~100 lines Python (MCP tool wrapper) + schema

### Option C: Hybrid (Recommended Final State)

Native tool for Skaffen core (latency, reliability, phase gating) + MCP exposure in intersearch for ecosystem access.

**Why not start here:** Premature. Validate with native tool first; add MCP later if other consumers need it.

## Recommended Approach: Option A (Native Go Tool)

### Two Tools

1. **WebSearch** — semantic search via Exa API
   - Input: `query` (string, required), `num_results` (int, default 5, max 10), `category` (string, optional — "research paper", "tweet", "company", etc.)
   - Output: formatted results with title, URL, snippet, published date
   - Phase gates: brainstorm, plan, build (research is useful during coding too)

2. **WebFetch** — retrieve and extract content from a URL
   - Input: `url` (string, required), `max_length` (int, default 5000)
   - Output: extracted text content (HTML stripped, main content extracted)
   - Phase gates: brainstorm, plan, build
   - Implementation: HTTP GET + html-to-text extraction (readability-style)

### Phase Gating

```
brainstorm: [read, glob, grep, ls, web_search, web_fetch]  ← NEW
plan:       [read, glob, grep, ls, web_search, web_fetch]  ← NEW
build:      [read, write, edit, bash, grep, glob, ls, web_search, web_fetch]  ← NEW
review:     [read, glob, grep, ls]  (no search — reviewing existing code)
ship:       [read, glob, ls, bash]  (no search — shipping phase)
```

### Trust Rules

- `web_search` → `Prompt` on first use per session, then `Allow` (user sees what's being searched)
- `web_fetch` → `Prompt` always (fetching arbitrary URLs has security implications)
- Both respect `safeEnv()` credential stripping (EXA_API_KEY not in subprocess env)

### Graceful Degradation

- No `EXA_API_KEY` → tool returns helpful error: "Web search requires EXA_API_KEY. Set it in your environment or run `skaffen config set exa_api_key <key>`"
- Exa API error → fail-open with error message, don't crash the agent loop
- Rate limit → backoff message, suggest narrowing query

### Result Format

```
Web Search Results for: "go context cancellation patterns"

1. Context Cancellation in Go: A Complete Guide
   https://example.com/go-context
   Published: 2026-01-15
   Go's context package provides cancellation propagation through call chains...

2. Understanding Context in Go
   https://example.com/understanding-context
   Published: 2025-11-20
   The context.Context type carries deadlines, cancellation signals, and...

Found 5 results. Use web_fetch to read full content from any URL.
```

## Architecture

```
tool/
├── builtin.go          # RegisterBuiltins() — add WebSearch + WebFetch
├── web_search.go       # WebSearchTool + Exa API client
├── web_fetch.go        # WebFetchTool + HTML extraction
├── web_search_test.go  # Unit tests (mock HTTP)
└── web_fetch_test.go   # Unit tests (mock HTTP)

registry.go             # Update defaultGates for new phases
```

### Exa Client (embedded in web_search.go)

```go
type exaClient struct {
    apiKey     string
    httpClient *http.Client
    baseURL    string
}

func (c *exaClient) Search(ctx context.Context, query string, numResults int) ([]SearchResult, error)
```

- Timeout: 10s per request (configurable)
- No retry — single attempt, fail fast
- Response parsing: unmarshal JSON, extract title/url/text/highlights/score

### WebFetch (web_fetch.go)

```go
type WebFetchTool struct {
    httpClient *http.Client
}
```

- HTTP GET with 15s timeout
- Content-Type check: only process text/html, text/plain
- HTML extraction: strip tags, extract main content (use golang.org/x/net/html tokenizer)
- Size limit: truncate at `max_length` characters
- Security: no following redirects to file:// or localhost URLs

## Open Questions

1. **Should WebFetch follow redirects?** Leaning yes (max 3 hops), with URL validation on each hop
2. **Should we cache search results within a session?** Leaning yes — same query returns cached result, saves API cost
3. **Should build phase include web search?** Leaning yes — developers frequently need to look up API docs mid-coding
4. **Exa vs Brave/Tavily/SerpAPI?** Exa is already integrated in intersearch. Validate with Exa first; swap provider later if needed
5. **WebFetch content extraction quality?** May need a readability algorithm. Start simple (strip tags), improve based on usage

## Risks

- **API cost:** Exa charges per query. Need to surface cost to user or budget cap
- **Latency:** Network roundtrip adds 200-800ms per search. Acceptable for brainstorm/plan, may feel slow in build
- **Content quality:** Exa snippets may be too short. WebFetch full-page extraction may include boilerplate
- **Security:** WebFetch on arbitrary URLs could expose local network services. Must validate URL scheme (https only by default)

## Not in Scope

- Cached/offline search (Codex-style) — future enhancement
- Google grounding (Gemini-style) — requires Google partnership
- Search history / bookmarks — future enhancement
- Multi-provider search (Brave + Exa) — future enhancement
