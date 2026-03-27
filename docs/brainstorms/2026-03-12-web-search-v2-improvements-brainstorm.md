---
artifact_type: brainstorm
bead: none
stage: discover
---

# Brainstorm: Web Search & Fetch v2 Improvements

**Date:** 2026-03-12
**Parent:** Sylveste-6i0.20 (shipped v1)

## What We're Building

Four improvement areas for Skaffen's web tools (shipped in v1 as `os/Skaffen/internal/tool/web_search.go` + `web_fetch.go`):

1. **Exa search tiers** — route queries through Instant (<200ms), Auto, or Deep (agentic multi-query) based on the current OODARC phase
2. **Domain + recency filtering** — let the LLM restrict searches to specific domains and time ranges
3. **Session result caching** — LRU cache to avoid duplicate API calls within a session
4. **WebFetch v2** — JS-rendered page support via Jina Reader fallback, PDF extraction, better content quality

## Competitive Landscape (March 2026)

### Search Providers

| Provider | Approach | Strength | Cost |
|----------|----------|----------|------|
| **Exa** (current) | Neural embeddings, own index | Semantic search, 6 search types | $5/1K standard, $12/1K deep |
| **Perplexity Sonar** | LLM + search, synthesized answers | Citations, factuality (0.858 F-score) | $5/1K + $3/M tokens |
| **Brave** | Independent 35B-page index | Privacy, independent index, fast | $3-5/1K |
| **Tavily** | AI-native, LangChain integration | Agent-optimized, generous free tier | ~$8/1K |
| **Firecrawl** | Crawl + extract + search | Full-page extraction, site mapping | $0.8/page |

### Exa API v2 Search Types (Verified)

| Type | Latency | Description |
|------|---------|-------------|
| `auto` | 200-400ms | Default. Combines neural + other methods intelligently |
| `neural` | 200-400ms | Pure embeddings-based semantic search |
| `fast` | <350ms | Streamlined search models |
| `instant` | <200ms | Lowest latency, optimized for real-time |
| `deep` | 4-12s | Light deep search with query expansion |
| `deep-reasoning` | 12-50s | Full agentic search with LLM reasoning, structured output |

### WebFetch Alternatives

| Tool | JS Rendering | Approach | Integration Complexity |
|------|-------------|----------|----------------------|
| **Current** (tag stripping) | No | `x/net/html` tokenizer | N/A (already built) |
| **Jina Reader** | Yes | Prefix URL with `r.jina.ai/` | Trivial (HTTP GET) |
| **Cloudflare /crawl** | Yes | Headless Chrome as a service | Medium (API setup) |
| **Firecrawl** | Yes | Managed scraping + extraction | Medium (API key + SDK) |

### What Competitors Do

- **Claude Code:** WebSearch + WebFetch built-in, dynamic result filtering (Opus 4.6 writes filter code), MCP Tool Search for context-efficient tool discovery
- **Gemini:** Google grounding (not available via API partnership)
- **Amp:** `web_search` + `read_web_page` tools
- **Codex:** Cached/live search modes

## Key Decisions

### 1. Phase-based auto-routing for Exa tiers

The agent does NOT pick the tier — it's selected automatically based on the OODARC phase:

| Phase      | Exa `type` | Rationale |
|------------|------------|-----------|
| brainstorm | `deep`     | Thorough research, latency acceptable (4-12s) |
| plan       | `auto`     | Balanced speed/quality for reference lookups |
| build      | `instant`  | Fast API doc lookups, <200ms latency |
| review     | N/A        | Web search not available in review phase |
| ship       | N/A        | Web search not available in ship phase |

**Why `deep` not `deep-reasoning` for brainstorm:** `deep-reasoning` is 12-50s and $15/1K — too slow and expensive for interactive use. `deep` (4-12s, $12/1K) provides query expansion without the full LLM reasoning overhead.

**Why auto-route instead of LLM-selectable:**
- Zero schema change (no new `mode` param)
- Cost-predictable per phase — LLM can't accidentally burn $12/query in build phase
- Phase already encodes the right intent (research vs. quick lookup)

### 2. Agent-driven domain and recency filtering

New optional parameters in the tool schema:

```json
{
  "query": "context.WithCancel patterns",
  "domains": ["pkg.go.dev", "go.dev/blog"],
  "exclude_domains": ["w3schools.com"],
  "recency": "month"
}
```

**Design choices:**
- **Agent-driven only** — no curated domain lists. The LLM already knows authoritative sources per language/framework. Hardcoded lists go stale.
- **Recency values:** `day`, `week`, `month`, `year` → computed as `startPublishedDate: now - duration` (ISO8601)
- **Domain limits:** Max 10 include, max 10 exclude (Exa API limit)

**Exa API mapping:**
- `domains` → `includeDomains` in request body
- `exclude_domains` → `excludeDomains` in request body
- `recency` → `startPublishedDate` as ISO8601 timestamp

### 3. Simple query-key LRU cache

In-memory, per-session lifetime:

```go
type searchCache struct {
    mu      sync.Mutex
    entries map[string]*cacheEntry
    maxSize int           // 50 entries
}

type cacheEntry struct {
    results []exaResult
    created time.Time
    ttl     time.Duration // 15 minutes
}
```

**Cache key:** `lowercase(query):numResults:sorted(domains):recency:tier`

**Design choices:**
- 15-minute TTL, 50 entry max, simple LRU eviction
- Different params = different cache key (no cross-tier hits)
- ~30 lines, no external deps

### 4. WebFetch v2 — JS rendering + PDF

Current WebFetch fails on JS-rendered pages (SPAs, modern docs sites) and non-HTML content. Two improvements:

#### 4a. Jina Reader fallback for JS-rendered pages

When the current HTML extraction yields <10% text ratio (already detected — returns error), fall back to Jina Reader:

```go
// In web_fetch.go fetch():
if len(text) < len(bodyBytes)/10 && len(bodyBytes) > 1000 {
    // Current: return error
    // New: try Jina Reader as fallback
    jinaText, err := t.jinaFetch(ctx, rawURL, maxLength)
    if err == nil {
        return jinaText, nil
    }
    // If Jina also fails, return the original error
}
```

**Jina Reader integration:**
- `GET https://r.jina.ai/<encoded-url>` — returns Markdown
- No API key needed for basic usage (rate limited)
- Returns rendered page content including JS-generated text
- ~10 lines of code for the fallback

**Why Jina over Firecrawl/Cloudflare:**
- Zero setup (no API key, no account)
- Trivial integration (HTTP GET with URL prefix)
- Markdown output is LLM-friendly
- Good enough for fallback; if quality matters, user can always web_fetch the Jina URL directly

#### 4b. PDF support (future consideration)

Currently returns "unsupported content type: application/pdf". Options:
- Add `application/pdf` to `isTextContent()` + use a Go PDF library (e.g., `pdfcpu` or `unidoc`)
- Proxy through Jina Reader (handles PDF → Markdown)
- **Decision:** Defer. PDF via web_fetch is rare. If needed, Jina Reader handles it via the JS fallback path anyway.

## Phase Context Injection (Architecture Deep-Dive)

### Current Architecture

Skaffen has 3 layers for tool execution:

```
agent.Agent (phase-aware)
  → buildLoopRegistry(phase) → filters tools by phase
  → agentloop.Loop (phase-agnostic)
    → registry.Execute(ctx, name, params) → tool.Execute(ctx, params)
```

Phase is used for **gating** (which tools are available) but NOT passed to **tool execution**. The `tool.Registry.Execute(ctx, phase, name, params)` already receives phase, but doesn't forward it to tools.

### Recommended: `PhasedTool` interface (Option B)

```go
// In tool.go:
type PhasedTool interface {
    Tool
    ExecuteWithPhase(ctx context.Context, phase Phase, params json.RawMessage) ToolResult
}

// In registry.go Execute():
if pt, ok := t.(PhasedTool); ok {
    return pt.ExecuteWithPhase(ctx, phase, params)
}
return t.Execute(ctx, params) // fallback for non-phased tools
```

**Why this over context.WithValue:**
- Type-safe — no string keys or type assertions
- Explicit — tools that need phase opt-in by implementing the interface
- Non-breaking — existing tools work unchanged
- Discoverable — `PhasedTool` interface is self-documenting

**Why NOT the other options:**
- context.WithValue (Option A): Works but type-unsafe, convention-dependent
- Tool context hint (Option D): Pollutes user-facing JSON params, hacky
- Phase on tool instance (Option C): Race-prone if phase changes mid-execution

**Plumbing required:**
1. Add `PhasedTool` interface to `tool.go` (~5 lines)
2. Add type check in `tool.Registry.Execute()` (~5 lines)
3. Implement `ExecuteWithPhase` in `WebSearchTool` (wraps existing `Execute` + tier selection)
4. No changes to agentloop — the tool registry already has the phase

## Open Questions (Resolved + Remaining)

### Resolved

1. ~~**Exa API v2 exact parameter names?**~~ → Verified: `type` field with values `auto`, `neural`, `fast`, `instant`, `deep`, `deep-reasoning`
2. ~~**Phase context injection approach?**~~ → `PhasedTool` interface (Option B)
3. ~~**WebFetch for JS pages?**~~ → Jina Reader fallback when extraction ratio <10%

### Remaining

1. **Exa Deep + recency interaction?** Does `deep` search respect `startPublishedDate`? Deep does its own query expansion — need to verify via API testing.
2. **Jina Reader rate limits?** Free tier has undocumented rate limits. If Skaffen hits them in heavy brainstorm sessions, may need a Jina API key or fallback to Firecrawl.
3. **Cache warming across phase transitions?** brainstorm:deep → build:instant for same query = cache miss (different tier). Correct behavior since result quality differs. But should we allow opt-in cache promotion?
4. **Cost tracking?** Deep at $12/1K + instant at Exa's base rate — should we surface per-session search cost in the status bar? Deferred unless costs surprise us.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Exa Deep latency (4-12s) in brainstorm | Medium | "Searching..." status. Acceptable for research phase. |
| Exa Deep cost ($12/1K) | Low | Phase-based routing prevents accidental use in build. ~$0.04/session. |
| Jina Reader availability | Low | Fallback only — primary extraction still works for static HTML. |
| Cache staleness | Low | 15-minute TTL. Coding query results don't change in 15 minutes. |
| `PhasedTool` interface churn | Low | Opt-in interface. Only WebSearchTool implements it initially. |
| Domain filtering reduces result quality | Low | Optional param. Agent only uses it when confident. |

## What We Chose NOT to Do (and Why)

| Feature | Why Not |
|---------|---------|
| Multi-provider (Perplexity, Brave, Tavily) | Exa quality is sufficient for coding queries. Adds provider abstraction complexity. Revisit if Exa reliability drops. |
| LLM-synthesized answers (Perplexity-style) | Changes tool semantics from "search results" to "generated answer." Better as a separate tool. |
| Structured output from Exa Deep | Premature — standard result format works for the agent loop. |
| Full headless Chrome (Cloudflare /crawl) | Over-engineering. Jina Reader fallback covers 95% of JS cases. |
| PDF extraction in WebFetch | Rare use case via URL. Jina Reader handles it if needed. |
| Cached/offline search (Codex-style) | Fundamentally different architecture. |
| `deep-reasoning` tier | 12-50s latency is too slow for interactive brainstorm. `deep` (4-12s) is the sweet spot. |

## Scope Summary

| Change | Files | Estimated LOC |
|--------|-------|---------------|
| PhasedTool interface | `tool.go`, `registry.go` | ~10 |
| Exa tier routing | `web_search.go` | ~20 |
| Domain + recency params | `web_search.go` | ~30 |
| Session cache | `web_search.go` | ~30 |
| Jina Reader fallback | `web_fetch.go` | ~15 |
| Tests | `web_search_test.go`, `web_fetch_test.go` | ~120 |
| **Total** | **5 files** | **~225 lines** |
