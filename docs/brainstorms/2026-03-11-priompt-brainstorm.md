---
artifact_type: brainstorm
bead: Sylveste-qsw
stage: discover
---
# Priompt: Priority-Based Prompt Composition for Skaffen

## What We're Building

A shared prompt composition library (`masaq/priompt`) that assembles prompt elements into a token budget using priority-based greedy packing. Each prompt section (system instructions, tool definitions, phase context, conversation history, user-provided files) has a base priority and optional phase-specific boosts. When the context window fills, lowest-priority elements are dropped first.

The library is cache-aware: elements marked `Stable` render first to maximize Anthropic prompt cache prefix hits. Token counting uses a pluggable interface with a character-ratio heuristic default.

**Prior art:** [Priompt](https://github.com/tg1482/priomptipy) (Anysphere/Cursor) — TypeScript/JSX priority scoping. [PriomptiPy](https://pypi.org/project/priompt/) — Python port. No Go implementation exists. We take the core concept (priority-based budget rendering) and build a Go-native version tailored to the Sylveste agent ecosystem.

## Why This Approach

### Masaq shared library, not Skaffen-internal

Priompt is pure rendering logic — no agent, provider, or tool imports. It belongs in Masaq alongside theme, viewport, diff, and the other rendering components. This means Autarch, future agents, and even CLI tools can use the same priority prompt assembly. The existing `masaq/` module pattern (separate Go module with `replace` directive) makes this zero-friction.

### Greedy sort algorithm

The rendering problem is a knapsack variant, but for ~10-20 elements, a greedy approach (sort by effective priority, include until budget exhausted) is optimal in practice. O(n log n) sort dominates, which is instant for typical element counts. Fractional knapsack and two-pass reserves are over-engineering for v1 — they can be added later behind the same `Render()` API if needed.

### Pluggable tokenizer

Ship with `CharHeuristic{Ratio: 4}` (~85% accuracy) as the default. Consumers can plug in tiktoken-go or API-based counting later via `SetTokenizer()`. This avoids a 5MB dependency for a feature that only needs relative accuracy (we're making "include/exclude" decisions, not exact fits).

### Cache-aware ordering via Stable flag

Anthropic's prompt caching works by prefix — the first N tokens of a prompt that match a previous request are cache hits (90% cheaper). By partitioning elements into Stable (rendered first) and Dynamic (rendered after), we guarantee the system prompt + tool definitions form a stable prefix across turns. This is a meaningful cost optimization that requires no consumer effort beyond marking elements as stable.

### String-based phase tags

Phase boost uses `map[string]int` rather than importing Skaffen's `tool.Phase` enum. Masaq stays decoupled — Skaffen casts `string(phase)` at the call site. Any consumer with any phase model can use string tags like `"brainstorm"`, `"build"`, `"planning"`, etc.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Lives in `masaq/priompt/` | Follows Masaq's rendering-only pattern. No agent imports. Reusable across Sylveste agents. |
| D2 | Greedy sort rendering | O(n log n), simple, predictable. ~10-20 elements makes knapsack unnecessary. |
| D3 | Pluggable Tokenizer interface | Ships with char heuristic (4 chars/token). Upgradeable to tiktoken-go later. |
| D4 | `Stable` flag for cache optimization | Stable elements render first → stable prefix → cache hits. Major cost savings. |
| D5 | `PhaseBoost map[string]int` | Decouples from Skaffen's Phase enum. Any consumer's phase model works via string tags. |
| D6 | `Element` as flat struct, not tree | Unlike Cursor's JSX-based Priompt, we use flat elements. Go doesn't have JSX. Tree composition can be layered later via `Group()` helpers if needed. |
| D7 | `Render()` returns `string` + `RenderResult` | Returns both the concatenated prompt string and metadata (included/excluded elements, total tokens, cache boundary position). |

## API Surface (Sketch)

```go
package priompt

// Element is a prompt section with priority metadata.
type Element struct {
    Name       string            // identifier for debugging/metrics
    Content    string            // the actual prompt text
    Priority   int               // higher = more important (0-100 suggested range)
    PhaseBoost map[string]int    // phase tag → priority adjustment
    Stable     bool              // render first for cache prefix stability
}

// Tokenizer estimates token count for a string.
type Tokenizer interface {
    Count(s string) int
}

// Option configures a Render call.
type Option func(*renderConfig)

func WithPhase(tag string) Option       // activate phase boosts
func WithTokenizer(t Tokenizer) Option  // override default tokenizer
func WithSeparator(sep string) Option   // element separator (default: "\n\n")

// RenderResult contains the rendered prompt and metadata.
type RenderResult struct {
    Prompt       string   // concatenated prompt text
    Included     []string // names of included elements
    Excluded     []string // names of excluded elements (over budget)
    TotalTokens  int      // estimated token count of rendered prompt
    StableTokens int      // token count of stable prefix (for cache boundary)
}

// Render assembles elements into a prompt within the token budget.
func Render(elements []Element, budget int, opts ...Option) RenderResult
```

## Integration Points

### Skaffen: Replace static SystemPrompt

Current: `Session.SystemPrompt(phase)` returns a fixed string.
After: Session builds `[]priompt.Element` from system prompt, tool docs, phase context, conversation history, and project context. Calls `priompt.Render()` with the router's budget state.

```go
func (s *PriomptSession) SystemPrompt(phase tool.Phase) string {
    elements := s.buildElements(phase)
    budget := s.contextBudget() // from router budget state
    result := priompt.Render(elements, budget, priompt.WithPhase(string(phase)))
    s.lastRender = result // for evidence emission
    return result.Prompt
}
```

### Evidence emission

The `RenderResult.Excluded` list feeds into Skaffen's evidence pipeline — when elements are dropped, that's a signal for the calibration pipeline (future: adjust priorities based on what the model actually uses).

### Router budget integration

The router's `BudgetState()` already reports (spent, max, percentage). Priompt's budget parameter should be `contextWindowSize - estimatedOutputReserve - existingMessageTokens`, computed by Skaffen at each turn.

## Open Questions

1. **Separator handling:** Should separators count against the token budget? (Probably yes, but they're small.)
2. **Empty content:** Should elements with empty Content be silently skipped? (Yes.)
3. **Deterministic ordering:** Elements with equal effective priority — sort by name for determinism? (Yes, follows the Go map iteration lesson from docs/solutions.)
4. **Nested scopes:** Cursor's Priompt supports nested priority scopes (parent scope affects children). Do we need this in v1? (Probably not — flat elements with explicit priorities cover the initial use cases.)
5. **Dynamic budget:** Should Render accept a callback to re-check budget mid-assembly? (No for v1 — budget is computed once before Render.)
