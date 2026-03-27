# Plan: Skaffen Web Search Built-in Tool

**Bead:** Sylveste-6i0.20
**PRD:** docs/prd/2026-03-12-skaffen-web-search-prd.md
**Date:** 2026-03-12

## Summary

Add WebSearch (Exa API) and WebFetch (HTTP + HTML extraction) as built-in tools to Skaffen. 4 tasks, ~500 lines of Go. Promotes `golang.org/x/net` from indirect to direct dep (already in go.mod).

## Task Breakdown

### Task 1: WebSearch tool (`internal/tool/web_search.go`) [Sylveste-zpr7]

**Files:** `internal/tool/web_search.go`, `internal/tool/web_search_test.go`

Implementation:
1. Define `WebSearchTool` struct with `apiKey string` and `httpClient *http.Client`
2. Define `webSearchParams` struct: `Query string` (required), `NumResults int` (default 5, max 10)
3. Implement `Tool` interface: Name() → `"web_search"`, Description, Schema (JSON), Execute
4. Implement `func (t *WebSearchTool) exaSearch(ctx, query, numResults)` method:
   - POST to `https://api.exa.ai/search` with JSON body
   - Headers: `x-api-key`, `Content-Type: application/json`
   - Request body: `{query, numResults, useAutoprompt: true, contents: {text: {maxCharacters: 1000}, highlights: {numSentences: 3}}}`
   - 10s timeout via `context.WithTimeout` (composes with parent ctx)
   - Parse response: `[]SearchResult{Title, URL, Text, PublishedDate, Score}`
   - **Clamp** `numResults` to max 10 in Go (schema max is advisory only)
   - **Error redaction:** on API errors, only surface status code + generic message — never include raw response that could echo the API key
5. Format results as numbered list with title, URL, date, snippet
6. Graceful degradation: no API key → helpful setup message
7. Constructor: `NewWebSearchTool()` reads `EXA_API_KEY` from env at creation time
8. **Pre-expired context check:** if `ctx.Err() != nil` at entry, return distinct cancellation message

Tests (mock HTTP via `httptest.NewServer`):
- Success case: 3 results returned, formatted correctly
- Missing API key: returns setup instructions
- API error (500): returns generic error, IsError=true, **key string absent from output**
- Empty results: "No results found" message
- Timeout: context deadline exceeded handling
- NumResults > 10: clamped to 10

### Task 2: WebFetch tool (`internal/tool/web_fetch.go`) [Sylveste-6tys]

**Files:** `internal/tool/web_fetch.go`, `internal/tool/web_fetch_test.go`

Implementation:
1. Define `WebFetchTool` struct with `httpClient *http.Client`
2. Define `webFetchParams` struct: `URL string` (required), `MaxLength int` (default 5000)
3. Implement `Tool` interface: Name() → `"web_fetch"`, Description, Schema, Execute
4. URL validation — extract `validateURL(rawURL string) error` helper:
   - Parse with `url.Parse`
   - Scheme must be `https` (reject http, file, ftp, etc.)
   - Block: localhost, 127.0.0.0/8, ::1, 0.0.0.0, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 (cloud metadata), fe80::/10 (link-local), fc00::/7 (ULA), ::ffff:127.0.0.0/104 (IPv4-mapped loopback)
5. HTTP GET with custom `DialContext` (DNS rebinding protection):
   - Custom `net.Dialer` that resolves hostname, checks resolved IPs against blocklist before connecting
   - `CheckRedirect`: max 3 hops, re-validate each hop URL
   - 15s timeout via `context.WithTimeout`
   - Read body: `io.LimitReader(resp.Body, 1<<20)` (1MB cap)
   - **Drain remainder:** `io.Copy(io.Discard, resp.Body)` after limited read to enable connection reuse
6. Content extraction:
   - Check Content-Type: only text/html, text/plain
   - HTML: use `golang.org/x/net/html.Tokenizer` to extract text nodes, skip script/style/nav/footer tags
   - Plain text: return as-is
   - Truncate to `MaxLength` characters
   - **Encoding heuristic:** if extracted text is <10% of bytes consumed, return IsError with encoding warning
7. Constructor: `NewWebFetchTool()` with custom http.Client (SSRF-safe transport)
8. **Pre-expired context check:** if `ctx.Err() != nil` at entry, return distinct cancellation message

Tests — use `extractContent()` and `validateURL()` directly for unit tests (avoid TLS/SSRF self-block):
- `TestValidateURL`: https allowed, http/file/ftp rejected, localhost/private IPs rejected, 0.0.0.0 rejected, fe80:: rejected, ::ffff:127.0.0.1 rejected
- `TestExtractHTML`: extracts text, strips tags, skips script/style
- `TestExtractPlainText`: returns as-is
- `TestExtractTruncation`: truncates at MaxLength
- Integration test via `Execute` with `httptest.NewServer` (http, relaxed for test):
  - Inject test-friendly client that skips SSRF checks for test URLs
  - Large response: body drain + truncation
  - Non-text Content-Type: rejected

### Task 3: Phase gate + registration (`internal/tool/registry.go`, `builtin.go`) [Sylveste-3pfp]

**Files:** `internal/tool/registry.go`, `internal/tool/builtin.go`

Changes:
1. **Do NOT edit `defaultGates`** — `RegisterForPhases` handles gating directly
2. In `RegisterBuiltins()`:
   - Add `r.RegisterForPhases(NewWebSearchTool(), []Phase{PhaseBrainstorm, PhasePlan, PhaseBuild})`
   - Add `r.RegisterForPhases(NewWebFetchTool(), []Phase{PhaseBrainstorm, PhasePlan, PhaseBuild})`
   - Update comment: "9 built-in tools" (was 7)

### Task 4: Trust rules (`internal/trust/rules.go`) [Sylveste-q9nw]

**Files:** `internal/trust/rules.go`, `internal/trust/trust_test.go`

Changes:
1. Do NOT add `web_search` to `safeTools` — it calls an external paid API and leaks queries to a third party. Both `web_search` and `web_fetch` stay as `Prompt` (default for unknown tools)
2. Add comment explaining the trust split: "web_search and web_fetch are deliberately Prompt — web_search costs money per call and sends queries to Exa; web_fetch has SSRF risk. The user gate on web_fetch is load-bearing for prompt injection defense."
3. Add test: `TestWebSearchToolRequiresPrompt` — verifies web_search returns Prompt
4. Add test: `TestWebFetchToolRequiresPrompt` — verifies web_fetch returns Prompt

## Execution Order

```
Task 1 (WebSearch) ──┐
                      ├── Task 3 (Phase gates + registration) ── Task 4 (Trust rules)
Task 2 (WebFetch) ───┘
```

Tasks 1 and 2 are independent — can be implemented in parallel.
Task 3 depends on both (needs the constructors).
Task 4 depends on Task 3 (needs tools registered to verify behavior).

## Validation

After all tasks:
```bash
cd os/Skaffen && go test ./internal/tool/... -v -count=1
cd os/Skaffen && go test ./internal/trust/... -v -count=1
cd os/Skaffen && go vet ./...
cd os/Skaffen && go build ./cmd/skaffen
```

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `internal/tool/web_search.go` | Create | ~150 |
| `internal/tool/web_search_test.go` | Create | ~120 |
| `internal/tool/web_fetch.go` | Create | ~150 |
| `internal/tool/web_fetch_test.go` | Create | ~120 |
| `internal/tool/builtin.go` | Edit | ~3 |
| `internal/tool/registry.go` | Edit | ~3 |
| `internal/trust/rules.go` | Edit | ~1 |
| `internal/trust/trust_test.go` | Edit | ~15 |

Total: ~560 lines new, ~22 lines changed
