---
artifact_type: plan
bead: none
stage: design
---
# Web Search & Fetch v2 Improvements — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** none (follow-on to shipped Demarch-6i0.20)
**Goal:** Add phase-based Exa tier routing, domain/recency filtering, session caching, and Jina Reader fallback to Skaffen's web tools.

**Architecture:** Four independent improvements to `os/Skaffen/internal/tool/`. Tasks 1-2 (PhasedTool interface + tier routing) are coupled. Tasks 3-5 (filtering, caching, Jina fallback) are independent of each other but depend on Task 1's interface. All changes are in the `tool` package — no changes to `agentloop/` or `agent/` beyond what `registry.go` already supports.

**Tech Stack:** Go 1.22, `net/http`, `golang.org/x/net/html`, `encoding/json`, `sync`

**Prior Learnings:**
- [`docs/solutions/patterns/web-search-ssrf-defense-20260312.md`](../solutions/patterns/web-search-ssrf-defense-20260312.md) — `RegisterForPhases()` not `Register()` for web tools (silent failure gotcha). Error-path body drains must be bounded.
- [`docs/solutions/patterns/go-map-hash-determinism-20260223.md`](../solutions/patterns/go-map-hash-determinism-20260223.md) — Sort map keys before hashing when building cache keys. Go map iteration is non-deterministic.
- [`docs/solutions/patterns/search-surfaces.md`](../solutions/patterns/search-surfaces.md) — Exa is primary web search provider in Demarch. Jina Reader adds a new content extraction surface.

---

## Must-Haves

**Truths** (observable behaviors):
- Brainstorm phase web searches use Exa Deep (richer results, 4-12s latency is acceptable)
- Build phase web searches use Exa Instant (<200ms latency for quick API doc lookups)
- Agent can restrict searches to specific domains (e.g., `pkg.go.dev`) and time ranges
- Identical searches within 15 minutes return cached results without an API call
- WebFetch on JS-rendered pages falls back to Jina Reader instead of returning an error

**Artifacts** (files that must exist):
- [`os/Skaffen/internal/tool/tool.go`] exports `PhasedTool` interface
- [`os/Skaffen/internal/tool/web_search.go`] implements `PhasedTool`, has `searchCache`, domain/recency params
- [`os/Skaffen/internal/tool/web_fetch.go`] has `jinaFetch` fallback method

**Key Links:**
- `registry.Execute()` must check for `PhasedTool` and pass phase to `ExecuteWithPhase()`
- `WebSearchTool.ExecuteWithPhase()` must call `tierForPhase()` before `exaSearch()`
- `searchCache` must be checked before `exaSearch()` and populated after

---

### Task 1: PhasedTool Interface + Registry Wiring

Add a `PhasedTool` interface to `tool.go` and wire it into `registry.Execute()`. This enables any tool to opt into phase-aware execution without changing the `Tool` interface.

**Files:**
- Modify: `os/Skaffen/internal/tool/tool.go:14` (after `ToolResult`)
- Modify: `os/Skaffen/internal/tool/registry.go:136` (in `Execute()`)
- Test: `os/Skaffen/internal/tool/registry_test.go` (new file)

**Step 1: Write the failing test**

Create `os/Skaffen/internal/tool/registry_test.go`:

```go
package tool

import (
	"context"
	"encoding/json"
	"testing"
)

// mockPhasedTool records the phase it was called with.
type mockPhasedTool struct {
	calledPhase Phase
}

func (m *mockPhasedTool) Name() string                                  { return "mock_phased" }
func (m *mockPhasedTool) Description() string                           { return "test phased tool" }
func (m *mockPhasedTool) Schema() json.RawMessage                       { return json.RawMessage(`{}`) }
func (m *mockPhasedTool) Execute(_ context.Context, _ json.RawMessage) ToolResult {
	return ToolResult{Content: "non-phased"}
}
func (m *mockPhasedTool) ExecuteWithPhase(_ context.Context, phase Phase, _ json.RawMessage) ToolResult {
	m.calledPhase = phase
	return ToolResult{Content: "phased:" + string(phase)}
}

// mockPlainTool is a non-phased tool for comparison.
type mockPlainTool struct{}

func (m *mockPlainTool) Name() string                                          { return "mock_plain" }
func (m *mockPlainTool) Description() string                                   { return "test plain tool" }
func (m *mockPlainTool) Schema() json.RawMessage                               { return json.RawMessage(`{}`) }
func (m *mockPlainTool) Execute(_ context.Context, _ json.RawMessage) ToolResult {
	return ToolResult{Content: "plain"}
}

func TestRegistryCallsPhasedTool(t *testing.T) {
	r := NewRegistry()
	phased := &mockPhasedTool{}
	r.RegisterForPhases(phased, []Phase{PhaseBrainstorm, PhaseBuild})

	result := r.Execute(context.Background(), PhaseBrainstorm, "mock_phased", json.RawMessage(`{}`))
	if result.Content != "phased:brainstorm" {
		t.Errorf("expected 'phased:brainstorm', got %q", result.Content)
	}
	if phased.calledPhase != PhaseBrainstorm {
		t.Errorf("expected phase brainstorm, got %q", phased.calledPhase)
	}
}

func TestRegistryCallsPhasedToolBuildPhase(t *testing.T) {
	r := NewRegistry()
	phased := &mockPhasedTool{}
	r.RegisterForPhases(phased, []Phase{PhaseBrainstorm, PhaseBuild})

	result := r.Execute(context.Background(), PhaseBuild, "mock_phased", json.RawMessage(`{}`))
	if result.Content != "phased:build" {
		t.Errorf("expected 'phased:build', got %q", result.Content)
	}
}

func TestRegistryCallsPlainToolUnchanged(t *testing.T) {
	r := NewRegistry()
	r.Register(&mockPlainTool{})

	result := r.Execute(context.Background(), PhaseBuild, "mock_plain", json.RawMessage(`{}`))
	if result.Content != "plain" {
		t.Errorf("expected 'plain', got %q", result.Content)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd os/Skaffen && go test ./internal/tool/ -run TestRegistryCallsPhased -v -count=1`
Expected: FAIL — `PhasedTool` is undefined, `ExecuteWithPhase` is not a known method

**Step 3: Add `PhasedTool` interface to `tool.go`**

Add after the `ToolResult` struct (after line 20):

```go
// PhasedTool is optionally implemented by tools that need phase-aware execution.
// The registry checks for this interface and passes the current phase when available.
type PhasedTool interface {
	Tool
	ExecuteWithPhase(ctx context.Context, phase Phase, params json.RawMessage) ToolResult
}
```

**Step 4: Wire `PhasedTool` into `registry.Execute()`**

In `registry.go`, replace line 136:

```go
	return t.Execute(ctx, params)
```

with:

```go
	// If the tool implements PhasedTool, pass the phase for phase-aware behavior.
	if pt, ok := t.(PhasedTool); ok {
		return pt.ExecuteWithPhase(ctx, phase, params)
	}
	return t.Execute(ctx, params)
```

**Step 5: Run tests to verify they pass**

Run: `cd os/Skaffen && go test ./internal/tool/ -run TestRegistry -v -count=1`
Expected: PASS (all 3 registry tests)

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS (all existing tests still pass — non-phased tools are unchanged)

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/tool/tool.go internal/tool/registry.go internal/tool/registry_test.go
git commit -m "feat(tool): add PhasedTool interface for phase-aware tool execution"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestRegistryCallsPhased -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/tool/`
  expect: exit 0
</verify>

---

### Task 2: Phase-Based Exa Tier Routing

Make `WebSearchTool` implement `PhasedTool`. Route brainstorm → `deep`, plan → `auto`, build → `instant`. Update `exaSearch()` to accept a `searchType` parameter and include it in the Exa API request body.

**Files:**
- Modify: `os/Skaffen/internal/tool/web_search.go:49-87` (Execute → ExecuteWithPhase), `102-107` (exaRequest), `122-166` (exaSearch)
- Modify: `os/Skaffen/internal/tool/web_search_test.go` (add tier tests, update test helpers)

**Step 1: Write the failing tests**

Add to `web_search_test.go`:

```go
func TestTierForPhase(t *testing.T) {
	tests := []struct {
		phase Phase
		want  string
	}{
		{PhaseBrainstorm, "deep"},
		{PhasePlan, "auto"},
		{PhaseBuild, "instant"},
		{PhaseReview, "auto"},  // fallback
		{PhaseShip, "auto"},    // fallback
	}

	tool := &WebSearchTool{apiKey: "test"}
	for _, tt := range tests {
		t.Run(string(tt.phase), func(t *testing.T) {
			if got := tool.tierForPhase(tt.phase); got != tt.want {
				t.Errorf("tierForPhase(%s) = %q, want %q", tt.phase, got, tt.want)
			}
		})
	}
}

func TestExaSearchSendsSearchType(t *testing.T) {
	var receivedType string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req exaRequest
		json.NewDecoder(r.Body).Decode(&req)
		receivedType = req.Type
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client()}
	tool.exaSearchWithURL(context.Background(), srv.URL, "test", 5, exaSearchOpts{searchType: "deep"})

	if receivedType != "deep" {
		t.Errorf("expected type 'deep', got %q", receivedType)
	}
}

func TestExecuteWithPhaseSetsSearchType(t *testing.T) {
	var receivedType string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req exaRequest
		json.NewDecoder(r.Body).Decode(&req)
		receivedType = req.Type
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{
			{Title: "Result", URL: "https://example.com", Text: "Content."},
		}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}
	result := tool.ExecuteWithPhase(context.Background(), PhaseBrainstorm, json.RawMessage(`{"query": "test"}`))

	if result.IsError {
		t.Fatalf("unexpected error: %s", result.Content)
	}
	if receivedType != "deep" {
		t.Errorf("brainstorm should use 'deep', got %q", receivedType)
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tool/ -run "TestTierForPhase|TestExaSearchSendsSearchType|TestExecuteWithPhase" -v -count=1`
Expected: FAIL — `tierForPhase`, `exaSearchOpts`, `baseURL`, `ExecuteWithPhase` undefined

**Step 3: Implement tier routing**

In `web_search.go`, make these changes:

1. Add `baseURL` field to `WebSearchTool` and an `exaSearchOpts` struct:

```go
type WebSearchTool struct {
	apiKey     string
	httpClient *http.Client
	baseURL    string       // empty = production (https://api.exa.ai/search)
	cache      *searchCache // nil until first use
}

// exaSearchOpts carries optional parameters for the Exa API.
type exaSearchOpts struct {
	searchType string // "auto", "instant", "deep", etc.
}
```

2. Add `Type` field to `exaRequest`:

```go
type exaRequest struct {
	Query         string      `json:"query"`
	NumResults    int         `json:"numResults"`
	UseAutoprompt bool        `json:"useAutoprompt"`
	Type          string      `json:"type,omitempty"`
	Contents      exaContents `json:"contents"`
}
```

3. Add `tierForPhase`:

```go
// tierForPhase maps OODARC phases to Exa search types.
func (t *WebSearchTool) tierForPhase(phase Phase) string {
	switch phase {
	case PhaseBrainstorm:
		return "deep"
	case PhasePlan:
		return "auto"
	case PhaseBuild:
		return "instant"
	default:
		return "auto"
	}
}
```

4. Add `ExecuteWithPhase` and refactor `Execute` to delegate:

```go
// ExecuteWithPhase implements PhasedTool — selects Exa tier based on phase.
func (t *WebSearchTool) ExecuteWithPhase(ctx context.Context, phase Phase, params json.RawMessage) ToolResult {
	return t.executeWithOpts(ctx, params, exaSearchOpts{
		searchType: t.tierForPhase(phase),
	})
}

// Execute implements Tool — uses "auto" tier (backward compatible).
func (t *WebSearchTool) Execute(ctx context.Context, params json.RawMessage) ToolResult {
	return t.executeWithOpts(ctx, params, exaSearchOpts{searchType: "auto"})
}
```

5. Extract shared logic into `executeWithOpts`:

```go
func (t *WebSearchTool) executeWithOpts(ctx context.Context, params json.RawMessage, opts exaSearchOpts) ToolResult {
	if ctx.Err() != nil {
		return ToolResult{Content: "web search cancelled: session is shutting down", IsError: true}
	}

	if t.apiKey == "" {
		return ToolResult{
			Content: "Web search requires an API key. Set EXA_API_KEY in your environment:\n  export EXA_API_KEY=your-key-here\n\nGet a key at https://exa.ai",
			IsError: true,
		}
	}

	var p webSearchParams
	if err := json.Unmarshal(params, &p); err != nil {
		return ToolResult{Content: fmt.Sprintf("invalid params: %v", err), IsError: true}
	}
	if p.Query == "" {
		return ToolResult{Content: "query is required", IsError: true}
	}

	numResults := p.NumResults
	if numResults <= 0 {
		numResults = 5
	}
	if numResults > 10 {
		numResults = 10
	}

	url := t.baseURL
	if url == "" {
		url = "https://api.exa.ai/search"
	}

	results, err := t.exaSearchWithURL(ctx, url, p.Query, numResults, opts)
	if err != nil {
		return ToolResult{Content: fmt.Sprintf("web search failed: %v", err), IsError: true}
	}

	if len(results) == 0 {
		return ToolResult{Content: fmt.Sprintf("No results found for: %q", p.Query)}
	}

	return ToolResult{Content: formatSearchResults(p.Query, results)}
}
```

6. Update `exaSearchWithURL` (the test helper) to accept opts and set `Type`:

```go
func (t *WebSearchTool) exaSearchWithURL(ctx context.Context, baseURL, query string, numResults int, opts exaSearchOpts) ([]exaResult, error) {
	if numResults > 10 {
		numResults = 10
	}

	reqBody := exaRequest{
		Query:         query,
		NumResults:    numResults,
		UseAutoprompt: true,
		Type:          opts.searchType,
		Contents: exaContents{
			Text:       exaText{MaxCharacters: 1000},
			Highlights: exaHighlights{NumSentences: 3},
		},
	}
	// ... rest unchanged (marshal, POST, parse response)
```

7. Update `exaSearch` (production path) to delegate:

```go
func (t *WebSearchTool) exaSearch(ctx context.Context, query string, numResults int, opts exaSearchOpts) ([]exaResult, error) {
	return t.exaSearchWithURL(ctx, "https://api.exa.ai/search", query, numResults, opts)
}
```

8. Remove the old `exaSearchURL` test helper — it's replaced by the new `exaSearchWithURL` signature. Update existing tests to pass `exaSearchOpts{}` where needed.

**Step 4: Update existing tests**

Update all calls to `exaSearchURL` and `exaSearchWithURL` in `web_search_test.go` to pass the new `exaSearchOpts{}` parameter. For example:

```go
// Old:
tool.exaSearchURL(context.Background(), srv.URL, "test", 5)
// New:
tool.exaSearchWithURL(context.Background(), srv.URL, "test", 5, exaSearchOpts{})
```

Remove the old `exaSearchURL` helper. Update `TestWebSearchAPIError` and `TestWebSearchEmptyResults` similarly.

**Step 5: Run all tests**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS (all existing + new tests)

**Step 6: Commit**

```bash
cd os/Skaffen && git add internal/tool/web_search.go internal/tool/web_search_test.go
git commit -m "feat(web_search): phase-based Exa tier routing (deep/auto/instant)"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestTierForPhase -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestExaSearchSendsSearchType -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestExecuteWithPhase -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 3: Domain and Recency Filtering

Add `domains`, `exclude_domains`, and `recency` parameters to the WebSearch tool schema. Pass them through to the Exa API as `includeDomains`, `excludeDomains`, and `startPublishedDate`.

**Files:**
- Modify: `os/Skaffen/internal/tool/web_search.go:31-47` (params + schema), `exaRequest` struct, `exaSearchOpts`
- Modify: `os/Skaffen/internal/tool/web_search_test.go`

**Step 1: Write the failing tests**

Add to `web_search_test.go`:

```go
func TestDomainFiltering(t *testing.T) {
	var receivedInclude, receivedExclude []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req exaRequest
		json.NewDecoder(r.Body).Decode(&req)
		receivedInclude = req.IncludeDomains
		receivedExclude = req.ExcludeDomains
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{
			{Title: "Result", URL: "https://pkg.go.dev/context", Text: "Package context."},
		}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}
	params := `{"query": "context patterns", "domains": ["pkg.go.dev", "go.dev"], "exclude_domains": ["w3schools.com"]}`
	result := tool.Execute(context.Background(), json.RawMessage(params))

	if result.IsError {
		t.Fatalf("unexpected error: %s", result.Content)
	}
	if len(receivedInclude) != 2 || receivedInclude[0] != "pkg.go.dev" {
		t.Errorf("expected include [pkg.go.dev, go.dev], got %v", receivedInclude)
	}
	if len(receivedExclude) != 1 || receivedExclude[0] != "w3schools.com" {
		t.Errorf("expected exclude [w3schools.com], got %v", receivedExclude)
	}
}

func TestRecencyFilter(t *testing.T) {
	var receivedStart string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req exaRequest
		json.NewDecoder(r.Body).Decode(&req)
		receivedStart = req.StartPublishedDate
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}
	params := `{"query": "recent updates", "recency": "week"}`
	tool.Execute(context.Background(), json.RawMessage(params))

	if receivedStart == "" {
		t.Fatal("expected startPublishedDate to be set for recency=week")
	}
	// Verify it's a valid ISO8601 date roughly 7 days ago
	if !strings.HasPrefix(receivedStart, "20") {
		t.Errorf("expected ISO8601 date, got %q", receivedStart)
	}
}

func TestDomainLimitClamping(t *testing.T) {
	var receivedInclude []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req exaRequest
		json.NewDecoder(r.Body).Decode(&req)
		receivedInclude = req.IncludeDomains
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{}})
	}))
	defer srv.Close()

	// Send 15 domains — should be clamped to 10
	domains := make([]string, 15)
	for i := range domains {
		domains[i] = fmt.Sprintf("domain%d.com", i)
	}
	domainsJSON, _ := json.Marshal(domains)
	params := fmt.Sprintf(`{"query": "test", "domains": %s}`, domainsJSON)

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}
	tool.Execute(context.Background(), json.RawMessage(params))

	if len(receivedInclude) > 10 {
		t.Errorf("expected max 10 include domains, got %d", len(receivedInclude))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tool/ -run "TestDomainFiltering|TestRecencyFilter|TestDomainLimitClamping" -v -count=1`
Expected: FAIL — new fields not in `webSearchParams` or `exaRequest`

**Step 3: Implement domain and recency filtering**

1. Update `webSearchParams`:

```go
type webSearchParams struct {
	Query          string   `json:"query"`
	NumResults     int      `json:"num_results,omitempty"`
	Domains        []string `json:"domains,omitempty"`
	ExcludeDomains []string `json:"exclude_domains,omitempty"`
	Recency        string   `json:"recency,omitempty"` // "day", "week", "month", "year"
}
```

2. Update `Schema()`:

```go
func (t *WebSearchTool) Schema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"query": {"type": "string", "description": "Natural language search query"},
			"num_results": {"type": "integer", "description": "Number of results to return (default 5, max 10)", "default": 5, "maximum": 10},
			"domains": {"type": "array", "items": {"type": "string"}, "description": "Only include results from these domains (max 10)", "maxItems": 10},
			"exclude_domains": {"type": "array", "items": {"type": "string"}, "description": "Exclude results from these domains (max 10)", "maxItems": 10},
			"recency": {"type": "string", "enum": ["day", "week", "month", "year"], "description": "Only include results published within this time period"}
		},
		"required": ["query"]
	}`)
}
```

3. Update `exaRequest`:

```go
type exaRequest struct {
	Query              string      `json:"query"`
	NumResults         int         `json:"numResults"`
	UseAutoprompt      bool        `json:"useAutoprompt"`
	Type               string      `json:"type,omitempty"`
	IncludeDomains     []string    `json:"includeDomains,omitempty"`
	ExcludeDomains     []string    `json:"excludeDomains,omitempty"`
	StartPublishedDate string      `json:"startPublishedDate,omitempty"`
	Contents           exaContents `json:"contents"`
}
```

4. Update `exaSearchOpts`:

```go
type exaSearchOpts struct {
	searchType     string
	includeDomains []string
	excludeDomains []string
	recency        string // "day", "week", "month", "year"
}
```

5. Add `recencyToDate` helper:

```go
// recencyToDate converts a recency string to an ISO8601 start date.
func recencyToDate(recency string) string {
	var d time.Duration
	switch recency {
	case "day":
		d = 24 * time.Hour
	case "week":
		d = 7 * 24 * time.Hour
	case "month":
		d = 30 * 24 * time.Hour
	case "year":
		d = 365 * 24 * time.Hour
	default:
		return ""
	}
	return time.Now().Add(-d).UTC().Format(time.RFC3339)
}
```

6. Update `executeWithOpts` to pass params through to opts:

```go
// In executeWithOpts, after parsing params:
	// Clamp domain lists to max 10
	domains := p.Domains
	if len(domains) > 10 {
		domains = domains[:10]
	}
	excludeDomains := p.ExcludeDomains
	if len(excludeDomains) > 10 {
		excludeDomains = excludeDomains[:10]
	}
	opts.includeDomains = domains
	opts.excludeDomains = excludeDomains
	opts.recency = p.Recency
```

7. Update `exaSearchWithURL` to set request fields from opts:

```go
	reqBody := exaRequest{
		Query:              query,
		NumResults:         numResults,
		UseAutoprompt:      true,
		Type:               opts.searchType,
		IncludeDomains:     opts.includeDomains,
		ExcludeDomains:     opts.excludeDomains,
		StartPublishedDate: recencyToDate(opts.recency),
		Contents: exaContents{
			Text:       exaText{MaxCharacters: 1000},
			Highlights: exaHighlights{NumSentences: 3},
		},
	}
```

**Step 4: Run all tests**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/web_search.go internal/tool/web_search_test.go
git commit -m "feat(web_search): add domain filtering and recency parameters"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestDomainFiltering -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestRecencyFilter -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestDomainLimitClamping -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 4: Session Result Cache

Add an in-memory LRU cache to `WebSearchTool`. Cache key is normalized `query:numResults:domains:recency:tier`. TTL 15 minutes, max 50 entries.

**Files:**
- Modify: `os/Skaffen/internal/tool/web_search.go` (add `searchCache` struct, wire into `executeWithOpts`)
- Modify: `os/Skaffen/internal/tool/web_search_test.go`

**Step 1: Write the failing tests**

Add to `web_search_test.go`:

```go
func TestCacheHit(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{
			{Title: "Cached Result", URL: "https://example.com", Text: "Content."},
		}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}

	// First call — hits API
	r1 := tool.Execute(context.Background(), json.RawMessage(`{"query": "go context"}`))
	if r1.IsError {
		t.Fatalf("first call failed: %s", r1.Content)
	}
	if callCount != 1 {
		t.Fatalf("expected 1 API call, got %d", callCount)
	}

	// Second identical call — should use cache
	r2 := tool.Execute(context.Background(), json.RawMessage(`{"query": "go context"}`))
	if r2.IsError {
		t.Fatalf("second call failed: %s", r2.Content)
	}
	if callCount != 1 {
		t.Errorf("expected cache hit (1 API call), got %d", callCount)
	}
	if r1.Content != r2.Content {
		t.Error("cached result should match original")
	}
}

func TestCacheMissDifferentParams(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{
			{Title: "Result", URL: "https://example.com", Text: "Content."},
		}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}

	tool.Execute(context.Background(), json.RawMessage(`{"query": "go context"}`))
	tool.Execute(context.Background(), json.RawMessage(`{"query": "go context", "domains": ["pkg.go.dev"]}`))

	if callCount != 2 {
		t.Errorf("different params should miss cache: expected 2 calls, got %d", callCount)
	}
}

func TestCacheTTLExpiry(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{
			{Title: "Result", URL: "https://example.com", Text: "Content."},
		}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}

	// First call
	tool.Execute(context.Background(), json.RawMessage(`{"query": "test"}`))

	// Manually expire the cache entry
	tool.cache.mu.Lock()
	for k, v := range tool.cache.entries {
		v.created = v.created.Add(-20 * time.Minute) // 20 min ago > 15 min TTL
		tool.cache.entries[k] = v
	}
	tool.cache.mu.Unlock()

	// Second call — should miss cache (expired)
	tool.Execute(context.Background(), json.RawMessage(`{"query": "test"}`))

	if callCount != 2 {
		t.Errorf("expired cache should miss: expected 2 calls, got %d", callCount)
	}
}

func TestCacheEviction(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		json.NewEncoder(w).Encode(exaResponse{Results: []exaResult{}})
	}))
	defer srv.Close()

	tool := &WebSearchTool{apiKey: "test-key", httpClient: srv.Client(), baseURL: srv.URL}

	// Fill cache beyond max (50 unique queries)
	for i := 0; i < 55; i++ {
		q := fmt.Sprintf(`{"query": "query-%d"}`, i)
		tool.Execute(context.Background(), json.RawMessage(q))
	}

	// Cache should not exceed 50 entries
	tool.cache.mu.Lock()
	size := len(tool.cache.entries)
	tool.cache.mu.Unlock()

	if size > 50 {
		t.Errorf("cache should be bounded at 50, got %d entries", size)
	}
}

func TestCacheKeyDeterminism(t *testing.T) {
	// Verify cache key is deterministic across 100 iterations (Go map gotcha)
	domains := []string{"b.com", "a.com", "c.com"}
	keys := make(map[string]bool)
	for i := 0; i < 100; i++ {
		k := buildCacheKey("test query", 5, domains, nil, "week", "deep")
		keys[k] = true
	}
	if len(keys) != 1 {
		t.Errorf("cache key not deterministic: got %d unique keys from 100 runs", len(keys))
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tool/ -run "TestCache" -v -count=1`
Expected: FAIL — `searchCache`, `buildCacheKey` undefined

**Step 3: Implement the cache**

Add to `web_search.go`:

```go
import "sort"

const (
	cacheMaxEntries = 50
	cacheTTL        = 15 * time.Minute
)

// searchCache provides in-memory result caching with TTL and LRU eviction.
type searchCache struct {
	mu      sync.Mutex
	entries map[string]*cacheEntry
}

type cacheEntry struct {
	results []exaResult
	created time.Time
}

func newSearchCache() *searchCache {
	return &searchCache{entries: make(map[string]*cacheEntry)}
}

// get returns cached results if present and not expired.
func (c *searchCache) get(key string) ([]exaResult, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || time.Since(e.created) > cacheTTL {
		if ok {
			delete(c.entries, key) // clean up expired
		}
		return nil, false
	}
	return e.results, true
}

// put stores results, evicting the oldest entry if at capacity.
func (c *searchCache) put(key string, results []exaResult) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Evict oldest if at capacity
	if len(c.entries) >= cacheMaxEntries {
		var oldestKey string
		var oldestTime time.Time
		for k, v := range c.entries {
			if oldestKey == "" || v.created.Before(oldestTime) {
				oldestKey = k
				oldestTime = v.created
			}
		}
		delete(c.entries, oldestKey)
	}

	c.entries[key] = &cacheEntry{results: results, created: time.Now()}
}

// buildCacheKey creates a deterministic cache key.
// Note: domains are sorted before joining to avoid Go map iteration non-determinism
// (see docs/solutions/patterns/go-map-hash-determinism-20260223.md).
func buildCacheKey(query string, numResults int, domains, excludeDomains []string, recency, tier string) string {
	sortedDomains := make([]string, len(domains))
	copy(sortedDomains, domains)
	sort.Strings(sortedDomains)

	sortedExclude := make([]string, len(excludeDomains))
	copy(sortedExclude, excludeDomains)
	sort.Strings(sortedExclude)

	return fmt.Sprintf("%s:%d:%s:%s:%s:%s",
		strings.ToLower(strings.TrimSpace(query)),
		numResults,
		strings.Join(sortedDomains, ","),
		strings.Join(sortedExclude, ","),
		recency,
		tier,
	)
}
```

Wire into `executeWithOpts` — check cache before API call, populate after:

```go
func (t *WebSearchTool) executeWithOpts(ctx context.Context, params json.RawMessage, opts exaSearchOpts) ToolResult {
	// ... (validation unchanged) ...

	// Lazy-init cache
	if t.cache == nil {
		t.cache = newSearchCache()
	}

	// Check cache
	cacheKey := buildCacheKey(p.Query, numResults, opts.includeDomains, opts.excludeDomains, opts.recency, opts.searchType)
	if cached, ok := t.cache.get(cacheKey); ok {
		if len(cached) == 0 {
			return ToolResult{Content: fmt.Sprintf("No results found for: %q (cached)", p.Query)}
		}
		return ToolResult{Content: formatSearchResults(p.Query, cached)}
	}

	url := t.baseURL
	if url == "" {
		url = "https://api.exa.ai/search"
	}

	results, err := t.exaSearchWithURL(ctx, url, p.Query, numResults, opts)
	if err != nil {
		return ToolResult{Content: fmt.Sprintf("web search failed: %v", err), IsError: true}
	}

	// Cache results (even empty ones, to avoid re-querying)
	t.cache.put(cacheKey, results)

	if len(results) == 0 {
		return ToolResult{Content: fmt.Sprintf("No results found for: %q", p.Query)}
	}

	return ToolResult{Content: formatSearchResults(p.Query, results)}
}
```

**Step 4: Run all tests**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/web_search.go internal/tool/web_search_test.go
git commit -m "feat(web_search): add session result caching with LRU eviction and TTL"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestCacheHit -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestCacheMiss -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestCacheTTL -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestCacheEviction -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestCacheKeyDeterminism -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
</verify>

---

### Task 5: Jina Reader Fallback for WebFetch

When HTML extraction yields <10% text ratio (JS-rendered pages), fall back to Jina Reader (`r.jina.ai`) before returning an error. Jina Reader handles JS rendering and returns Markdown.

**Files:**
- Modify: `os/Skaffen/internal/tool/web_fetch.go:136-140` (replace error with fallback)
- Modify: `os/Skaffen/internal/tool/web_fetch_test.go`

**Step 1: Write the failing tests**

Add to `web_fetch_test.go`:

```go
func TestWebFetchJinaFallback(t *testing.T) {
	// Simulate a JS-rendered page (huge body, almost no extracted text)
	jsPage := "<html><body><script>" + strings.Repeat("var x = 1;\n", 500) + "</script><noscript>Enable JS</noscript></body></html>"

	primaryCalled := false
	jinaCalled := false

	// Primary server returns JS-heavy page
	primary := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		primaryCalled = true
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(jsPage))
	}))
	defer primary.Close()

	// Jina server returns rendered markdown
	jina := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jinaCalled = true
		w.Write([]byte("# Page Title\n\nThis is the rendered content from the JS page."))
	}))
	defer jina.Close()

	tool := &WebFetchTool{
		httpClient:  primary.Client(),
		jinaBaseURL: jina.URL, // override for testing
	}

	result := tool.Execute(context.Background(), json.RawMessage(fmt.Sprintf(`{"url": "%s"}`, primary.URL)))

	if !primaryCalled {
		t.Error("primary fetch should have been called")
	}
	if !jinaCalled {
		t.Error("Jina fallback should have been called")
	}
	if result.IsError {
		t.Fatalf("expected success via Jina fallback, got error: %s", result.Content)
	}
	if !strings.Contains(result.Content, "rendered content") {
		t.Errorf("expected Jina content, got: %s", result.Content)
	}
}

func TestWebFetchJinaFallbackError(t *testing.T) {
	// Both primary and Jina fail — should return original error
	jsPage := "<html><body><script>" + strings.Repeat("var x = 1;\n", 500) + "</script></body></html>"

	primary := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(jsPage))
	}))
	defer primary.Close()

	jina := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer jina.Close()

	tool := &WebFetchTool{
		httpClient:  primary.Client(),
		jinaBaseURL: jina.URL,
	}

	result := tool.Execute(context.Background(), json.RawMessage(fmt.Sprintf(`{"url": "%s"}`, primary.URL)))

	if !result.IsError {
		t.Fatal("expected error when both primary and Jina fail")
	}
	if !strings.Contains(result.Content, "JavaScript-rendered") {
		t.Errorf("expected JS-rendered warning, got: %s", result.Content)
	}
}

func TestWebFetchNoFallbackForGoodContent(t *testing.T) {
	// Good HTML page — Jina should NOT be called
	jinaCalled := false

	primary := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<html><body><h1>Title</h1><p>Substantial content that is long enough to pass the ratio check with plenty of text.</p></body></html>"))
	}))
	defer primary.Close()

	jina := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		jinaCalled = true
		w.Write([]byte("Should not be called"))
	}))
	defer jina.Close()

	tool := &WebFetchTool{
		httpClient:  primary.Client(),
		jinaBaseURL: jina.URL,
	}

	result := tool.Execute(context.Background(), json.RawMessage(fmt.Sprintf(`{"url": "%s"}`, primary.URL)))

	if result.IsError {
		t.Fatalf("expected success, got error: %s", result.Content)
	}
	if jinaCalled {
		t.Error("Jina should NOT be called for pages with good content extraction")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd os/Skaffen && go test ./internal/tool/ -run "TestWebFetchJina" -v -count=1`
Expected: FAIL — `jinaBaseURL` field doesn't exist

**Step 3: Implement Jina Reader fallback**

1. Add `jinaBaseURL` field to `WebFetchTool`:

```go
type WebFetchTool struct {
	httpClient  *http.Client
	jinaBaseURL string // empty = production (https://r.jina.ai)
}
```

2. Add `jinaFetch` method:

```go
// jinaFetch retrieves page content via Jina Reader (handles JS-rendered pages).
func (t *WebFetchTool) jinaFetch(ctx context.Context, rawURL string, maxLength int) (string, error) {
	base := t.jinaBaseURL
	if base == "" {
		base = "https://r.jina.ai"
	}
	jinaURL := base + "/" + rawURL

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jinaURL, nil)
	if err != nil {
		return "", fmt.Errorf("create Jina request: %w", err)
	}
	req.Header.Set("User-Agent", "Skaffen/1.0 (web-fetch tool)")
	req.Header.Set("Accept", "text/plain")

	// Use a simple HTTP client for Jina (no SSRF concern — Jina is a trusted proxy)
	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("Jina request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		return "", fmt.Errorf("Jina returned HTTP %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", fmt.Errorf("read Jina response: %w", err)
	}
	io.Copy(io.Discard, resp.Body) // drain

	text := string(bodyBytes)
	if len(text) > maxLength {
		text = text[:maxLength] + "\n\n[Content truncated at " + fmt.Sprintf("%d", maxLength) + " characters]"
	}

	return text, nil
}
```

3. Replace the error return in `fetch()` with Jina fallback:

In `web_fetch.go`, replace lines 137-140:

```go
		if len(text) > 0 && len(text) < len(bodyBytes)/10 && len(bodyBytes) > 1000 {
			return "", fmt.Errorf("content extraction yielded very little text — the page may be JavaScript-rendered or use an unsupported character encoding")
		}
```

with:

```go
		if len(text) > 0 && len(text) < len(bodyBytes)/10 && len(bodyBytes) > 1000 {
			// JS-rendered page — try Jina Reader as fallback
			if jinaText, err := t.jinaFetch(ctx, rawURL, maxLength); err == nil {
				return jinaText, nil
			}
			// Jina also failed — return original error
			return "", fmt.Errorf("content extraction yielded very little text — the page may be JavaScript-rendered or use an unsupported character encoding")
		}
```

**Step 4: Run all tests**

Run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
Expected: PASS

**Step 5: Commit**

```bash
cd os/Skaffen && git add internal/tool/web_fetch.go internal/tool/web_fetch_test.go
git commit -m "feat(web_fetch): add Jina Reader fallback for JS-rendered pages"
```

<verify>
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestWebFetchJinaFallback$ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestWebFetchJinaFallbackError -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -run TestWebFetchNoFallbackForGoodContent -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go test ./internal/tool/ -v -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./internal/tool/`
  expect: exit 0
</verify>

---

### Task 6: Full Integration Test + Final Verification

Run the full test suite, vet, and verify the complete build. No new code — just validation.

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `cd os/Skaffen && go test ./... -count=1`
Expected: PASS (all packages)

**Step 2: Run go vet**

Run: `cd os/Skaffen && go vet ./...`
Expected: Clean (no warnings)

**Step 3: Verify build**

Run: `cd os/Skaffen && go build ./cmd/skaffen`
Expected: Success (binary compiles)

**Step 4: Commit if any cleanup was needed**

Only if previous steps required fixes.

<verify>
- run: `cd os/Skaffen && go test ./... -count=1`
  expect: exit 0
- run: `cd os/Skaffen && go vet ./...`
  expect: exit 0
- run: `cd os/Skaffen && go build ./cmd/skaffen`
  expect: exit 0
</verify>
