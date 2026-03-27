# PRD: Skaffen Web Search Built-in Tool

**Bead:** Sylveste-6i0.20
**Date:** 2026-03-12
**Status:** prd
**Parent:** Sylveste-6i0 (Bridge competitive landscape gaps)

## Problem Statement

Skaffen lacks web search capability. 4 of 5 competitors (Claude Code, Gemini, Amp, Codex) have it. Users must manually paste search results or work without current documentation, API references, or error context. This is the #1 missing utility in brainstorm/plan phases.

## Solution

Add two native Go tools to Skaffen's built-in tool registry:

1. **WebSearch** — semantic search via Exa API
2. **WebFetch** — retrieve and extract content from a URL

Native implementation (not MCP) for lowest latency, best phase gating, and zero external dependency.

## Features

### F1: WebSearch Tool
- Exa API client in Go (`net/http`)
- Input: `query` (required), `num_results` (default 5, max 10)
- Output: numbered results with title, URL, snippet, published date
- Phase gates: brainstorm, plan, build
- Graceful degradation: helpful error when `EXA_API_KEY` is missing
- 10s timeout per request, no retry

### F2: WebFetch Tool
- HTTP GET with HTML-to-text extraction
- Input: `url` (required), `max_length` (default 5000)
- Output: extracted text content (tags stripped)
- Phase gates: brainstorm, plan, build
- URL validation: https-only by default, no localhost/private IPs
- Redirect following: max 3 hops, validate each hop
- 15s timeout, 1MB response body cap

### F3: Phase Gate Updates
- Add `web_search` and `web_fetch` to brainstorm, plan, and build phase gates in `registry.go`
- No changes to review or ship phases

### F4: Trust Integration
- `web_search` → `Allow` (read-only, low risk, query visible in tool call)
- `web_fetch` → `Prompt` (arbitrary URL access has security implications)
- Add to `rules.go` safe-tool list for `web_search`, prompt-required for `web_fetch`

## Design Decisions (from Open Questions)

1. **WebFetch redirects:** Yes, max 3 hops with URL validation on each (no scheme/host downgrade)
2. **Session caching:** No for v1. Adds complexity, low ROI (searches are usually unique). Revisit if Exa costs become an issue.
3. **Build phase search:** Yes. Developers look up API docs mid-coding. Restricting to brainstorm/plan only is artificial.
4. **Search provider:** Exa. Already integrated in intersearch, good semantic search, autoprompt.
5. **Content extraction:** Simple tag stripping via `golang.org/x/net/html` tokenizer. No readability algorithm for v1.

## Non-Goals

- Cached/offline search
- Multi-provider search
- Search history or bookmarks
- MCP exposure (future, after native tool is validated)
- WebFetch for non-HTML content (PDF, images)

## Success Criteria

- [ ] `web_search` returns relevant results for programming queries
- [ ] `web_fetch` extracts readable text from documentation sites
- [ ] Both tools are phase-gated (available in brainstorm/plan/build only)
- [ ] Missing API key produces clear setup instructions
- [ ] `go test ./internal/tool/...` passes with mocked HTTP
- [ ] No credential leakage (EXA_API_KEY not in tool output or logs)

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Exa API cost | Medium | Default 5 results, max 10. Future: session budget cap |
| Latency (200-800ms) | Low | Acceptable for research phases. Streaming not needed |
| WebFetch SSRF | High | URL validation: https-only, block private IPs, validate redirects |
| Exa API changes | Low | Thin client, easy to swap. Response schema is stable |
