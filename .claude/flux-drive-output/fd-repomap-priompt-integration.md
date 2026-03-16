# Repomap-Priompt Integration Design

## Executive Summary

The repo map should be a **dynamic, non-stable priompt Element** with a `ContentFunc` that performs budget-aware binary-search fitting internally, boosted during Orient phase and demoted during Reflect/Compound. The current `generateRepoMap()` in `tui/repomap.go` is a static 8KB-capped string with no ranking, no budget awareness, and no priompt integration -- it lives in the TUI layer and is only accessible via the `/map` slash command. The integration path is: (1) extract ranking logic into a reusable package, (2) wrap it in a priompt Element with ContentFunc, (3) wire it into the sections slice passed to `session.NewPriomptSession()`.

## Source Analysis

### priompt.Element (masaq/priompt/priompt.go)

The Element struct (line 30-37) has exactly the fields we need:

```go
type Element struct {
    Name       string
    Content    string         // static fallback
    Render     ContentFunc    // dynamic generator (takes precedence)
    Priority   int            // 0-100 suggested
    PhaseBoost map[string]int // phase tag -> adjustment
    Stable     bool           // render first for cache prefix
}
```

Key Render mechanics (line 128-264):
- `ContentFunc` receives `RenderContext{Phase, Model, TurnCount, Budget}` (line 17-22)
- If ContentFunc returns empty string, element is **silently excluded** -- not in Excluded list (line 149-152)
- Elements are partitioned into stable/dynamic, each sorted by effective priority descending then Name ascending (line 163-187)
- Stable elements are packed first (greedy), then dynamic (line 244-245)
- Separator cost (default "\n\n" = 1 token) is accounted for between elements (line 211-226)
- `RenderResult.StableTokens` is zeroed if any stable element is excluded (line 252-254)

### Current Repo Map (os/Skaffen/internal/tui/repomap.go)

Lines 14-98: Static Go-only symbol extraction with hard limits:
- `maxMapFiles = 100` files parsed
- `maxMapOutput = 8000` characters output
- Walks directory tree, parses Go AST, extracts exported types/functions
- No ranking -- packages sorted alphabetically
- No budget awareness -- truncates at character limit, not token limit
- Only exposed via `/map` command (tui/commands.go:1000)

### Session/Priompt Wiring (os/Skaffen/internal/session/priompt_session.go)

Lines 36-44: `PriomptSession.SystemPrompt()` calls `priompt.Render(s.sections, budget, priompt.WithPhase(string(phase)))`. The sections are injected at construction via `NewPriomptSession(inner, sections)` (line 26-31). This is the integration point -- the repomap Element goes into this sections slice.

### Budget Computation (os/Skaffen/internal/agentloop/loop.go)

Lines 119-125: The prompt budget is derived per turn:
```
promptBudget = contextWindow - outputReserve(8192) - estimateMessageTokens(messages)
```
This budget flows to `SystemPrompt(PromptHints{Budget: promptBudget})` (line 126-131), which flows to `priompt.Render(sections, budget)`, which flows to `RenderContext.Budget` inside every ContentFunc.

### OODARC Phases (os/Skaffen/internal/tool/tool.go:33-45)

Six phases with aliases:
- `observe` (PhaseObserve)
- `orient` / brainstorm (PhaseOrient)
- `decide` / plan (PhaseDecide)
- `act` / build (PhaseAct)
- `reflect` / review (PhaseReflect)
- `compound` / ship (PhaseCompound)

## Design Decisions

### 1. Element Definition

```go
priompt.Element{
    Name:     "repomap",
    Priority: 35,
    Stable:   false,
    PhaseBoost: map[string]int{
        "observe":  +15,  // eff=50: critical for initial codebase understanding
        "orient":   +15,  // eff=50: brainstorming needs structural context
        "decide":   +5,   // eff=40: planning benefits from knowing where things live
        "act":      0,    // eff=35: useful but conversation context is more important
        "reflect":  -15,  // eff=20: review rarely needs full map
        "compound": -20,  // eff=15: shipping doesn't need structural overview
    },
    Render: repomapContentFunc(workDir, ranker),
}
```

**Rationale for Priority 35 (base):**
- The system prompt context files (CLAUDE.md, SKAFFEN.md, AGENTS.md) should be Stable=true at Priority 80-90. These are the identity and behavioral instructions that MUST be present.
- Fault localization guidance (currently injected at session.go:97) should be Priority 60-70 with Phase boost on Act.
- Quality history (session.go:82) should be Priority 40 with Phase boost on Orient.
- Repomap at Priority 35 means it's below behavioral instructions and phase-specific guidance, but above optional context like inspiration data.
- With Orient boost to 50, it rises above quality history (40) during brainstorming -- correct, since you need to know the code before you can reason about past quality.
- With Reflect demotion to 20 and Compound demotion to 15, conversation history wins the budget fight in late phases -- correct, since by then the agent has already navigated the codebase.

**Rationale for Stable=false:**
- The repo map content changes between turns as files are created/modified/deleted.
- Even with identical ranking, conversation context changes cause the total prompt to shift.
- Making it Stable would mean the first N tokens of every prompt include the map, which wastes Anthropic prompt cache on content that changes.
- The context files (CLAUDE.md etc.) are the correct stable prefix -- they rarely change within a session.
- If we later want partial cache stability (e.g., the map header is stable but entries vary), that requires a sub-element split, not the Stable flag.

### 2. ContentFunc Design: Internal Binary-Search Fitting

The ContentFunc closure should own the binary-search fitting. This is the critical architectural decision.

**Why inside ContentFunc (not pre-render or new API):**

The priompt Render function (priompt.go:128) calls ContentFunc exactly once per render cycle with the full budget in `RenderContext.Budget`. But the budget in RenderContext is the **total prompt budget**, not the per-element budget. The ContentFunc doesn't know how much space it will actually get -- priompt's greedy packer decides that after all content is generated.

This creates a tension: the repomap wants to fill exactly its available space, but doesn't know that space until after priompt decides to include it.

**Resolution: Use budget as upper bound, generate conservatively.**

```go
func repomapContentFunc(workDir string, ranker *RepoMapRanker) priompt.ContentFunc {
    return func(ctx priompt.RenderContext) string {
        // Estimate repomap's share of the budget.
        // Heuristic: repomap gets at most 15% of total prompt budget.
        maxTokens := ctx.Budget * 15 / 100
        if maxTokens < 500 {
            return "" // not worth including below 500 tokens
        }
        if maxTokens > 8000 {
            maxTokens = 8000 // cap: beyond 8K tokens the map is too large to be useful
        }

        // Binary search: find the maximum number of ranked entries
        // that fit within maxTokens.
        entries := ranker.Rank(workDir, ctx) // ranked by relevance
        return binarySearchFit(entries, maxTokens)
    }
}
```

The 15% heuristic is derived from the token partition model below. The key insight is that the ContentFunc doesn't need the exact per-element budget -- it needs a reasonable upper bound. If it generates 3000 tokens but priompt only has room for 2000, priompt will simply exclude the element entirely. So the ContentFunc should target a size that's likely to fit, which is the conservative share of the total budget.

**Binary search within ContentFunc:**

```go
func binarySearchFit(entries []MapEntry, maxTokens int) string {
    h := priompt.CharHeuristic{Ratio: 4}

    // Fast path: try all entries
    full := formatEntries(entries)
    if h.Count(full) <= maxTokens {
        return full
    }

    // Binary search on entry count
    lo, hi := 1, len(entries)
    best := ""
    for lo <= hi {
        mid := (lo + hi) / 2
        candidate := formatEntries(entries[:mid])
        if h.Count(candidate) <= maxTokens {
            best = candidate
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return best
}
```

This is O(n log n) where n is ranked entries. With typical repos (50-500 files), this takes <1ms. The ranker.Rank() call is the expensive part -- it should be cached.

### 3. Token Partition Model

#### 200K Context Window (default for all Claude models)

```
Total context window:           200,000 tokens
Output reserve:                  -8,192 tokens (hardcoded, loop.go:120)
Available for system + messages: 191,808 tokens

Turn 1 (minimal conversation history):
  Message tokens (1 user msg):   ~200-500 tokens
  System prompt budget:          ~191,300 tokens

  System prompt allocation:
    Context files (Stable):      3,000-8,000 tokens  (CLAUDE.md + SKAFFEN.md + AGENTS.md)
    Fault localization guidance:  ~1,200 tokens       (session.go:102-141, ~4800 chars)
    Quality history:             ~200-400 tokens       (when SignalReader present)
    Repo map (dynamic):          2,000-8,000 tokens   (15% budget cap = ~28K, but 8K hard cap)
    Remaining (for growth):      ~175,000+ tokens

Turn 20 (deep conversation):
  Message tokens:                ~50,000-100,000 tokens
  System prompt budget:          ~91,800-141,800 tokens

  Repo map at 15% of budget:    ~13K-21K -> capped at 8,000 tokens
  Still fits comfortably.

Turn 40+ (context pressure):
  Message tokens:                ~150,000+ tokens
  System prompt budget:          ~41,800 tokens

  Repo map at 15% of budget:    ~6,270 tokens -> fits
  If budget < ~3,300:           map returns "" (500-token minimum)
```

#### 100K Context Window (if configured via router.Config.ContextWindows)

```
Total:                          100,000 tokens
Output reserve:                  -8,192 tokens
Available:                       91,808 tokens

Turn 1:
  System prompt budget:          ~91,300 tokens
  Repo map at 15%:              ~13,700 -> capped at 8,000 tokens

Turn 20:
  Message tokens:                ~50,000 tokens
  System prompt budget:          ~41,800 tokens
  Repo map at 15%:              ~6,270 tokens

Turn 30+:
  Message tokens:                ~70,000 tokens
  System prompt budget:          ~21,800 tokens
  Repo map at 15%:              ~3,270 tokens (near minimum viable)
```

**Key finding:** The 15% heuristic and 8K hard cap work for both window sizes. The 500-token floor ensures the map degrades to empty rather than showing a useless fragment. The map is the first dynamic element to be excluded by priompt's greedy packer when the budget shrinks, which is correct behavior -- conversation history is always more valuable than structural context.

### 4. Cache Stability Analysis

**Anthropic prompt cache mechanics:** The API caches a prefix of the system prompt. Subsequent requests that share the same prefix get cache hits on that portion. The cache key is based on exact byte equality of the prefix.

**Impact of repomap changes between turns:**

Current architecture (priompt.go:244-245): stable elements render first, forming a deterministic prefix. Dynamic elements follow. If the repomap (dynamic, non-stable) changes between turns, only the bytes after the stable prefix are affected. The stable prefix still gets cache hits.

Scenario analysis:

1. **Repomap content identical between turns:** Full cache hit on both stable prefix and repomap portion. This happens when no files are created/modified between turns (common in Orient, Decide phases).

2. **Repomap ranking changes (file created/edited):** Cache hit on stable prefix only. The repomap bytes differ, so everything after the stable prefix is a cache miss. This is acceptable -- the alternative (making repomap stable) would mean ANY rank change invalidates the entire stable prefix, which is worse.

3. **Repomap excluded due to budget pressure:** Cache hit on stable prefix. No repomap bytes at all. Next turn if budget recovers and repomap re-appears, it's a cache miss on the repomap portion. Acceptable degradation.

**Recommendation:** Keep repomap as `Stable: false`. Monitor `StableTokens` in evidence (already emitted at agentloop/loop.go:209) to detect if stable elements are being dropped. If `ExcludedStable` is ever non-empty, that's a more serious problem than repomap cache misses.

**Future optimization:** If repomap content is expensive to generate, cache the ranked output in the Ranker with a TTL keyed on the most recent file modification timestamp. The ContentFunc checks the cache before regenerating. This avoids regeneration cost without affecting prompt cache behavior.

### 5. Output Format Recommendation

**Recommendation: Aider-style tree text format** (what `generateRepoMap` already produces, but with ranking).

Evaluation:

| Format | Tokens/entry | LLM parse quality | Cache friendliness | Implementation |
|--------|-------------|-------------------|-------------------|----------------|
| Tree text | ~4-6 | Excellent (natural for code structure) | High (stable formatting) | Simplest |
| JSON | ~8-12 | Good (but verbose braces/quotes) | Medium (quotes shift positions) | Moderate |
| Markdown | ~5-7 | Excellent | High | Moderate |

Tree text wins on token efficiency (fewest tokens per semantic unit) and LLM familiarity (Aider's format is well-represented in training data). Example:

```
Repository Map (ranked by relevance)
=====================================

internal/agent/
  type Agent
  func New()
  func (*Agent) Run()
  func (*Agent) CurrentPhase()

internal/agentloop/
  type Loop
  func New()
  func (*Loop) Run()
  func (*Loop) RunWithContent()

masaq/priompt/
  type Element
  type RenderContext
  func Render()
```

Key formatting rules:
- Header line identifies this as ranked (not alphabetical) so the LLM knows ordering is meaningful
- Top-ranked packages first (not alphabetical)
- Within each package, types before functions (matches Go convention)
- No file paths within packages -- too verbose, package-level is sufficient for navigation
- Indentation with 2 spaces (consistent with existing `generateRepoMap`)

### 6. Ranker Design (Architecture Sketch)

The ranker is out of scope for this integration design (it's a separate research question), but the interface contract matters for the ContentFunc.

```go
// RepoMapRanker produces a relevance-ordered list of map entries.
type RepoMapRanker interface {
    // Rank returns entries sorted by descending relevance.
    // ctx provides phase and conversation context for relevance scoring.
    Rank(workDir string, rctx priompt.RenderContext) []MapEntry
}

type MapEntry struct {
    Package string   // e.g., "internal/agent"
    Symbols []string // e.g., ["type Agent", "func New()", "func (*Agent) Run()"]
}
```

The ranker should accept `priompt.RenderContext` so it can adjust ranking by phase (e.g., boost test packages during Reflect) and model (e.g., include more detail for Opus which has better utilization of structural context).

## Integration Path

### Step 1: Extract repomap generation into a reusable package

Move `generateRepoMap()` and `extractGoSymbols()` from `internal/tui/repomap.go` to a new `internal/repomap/` package. The TUI `/map` command becomes a thin wrapper.

### Step 2: Add ranked output and budget-aware fitting

Add `Rank()` method that accepts relevance signals (initially: just recency of file access from the conversation). Add `binarySearchFit()` for token-budget fitting. Keep `generateRepoMap()` as the unranked fallback.

### Step 3: Create the priompt Element factory

```go
// internal/repomap/element.go

func NewElement(workDir string, ranker Ranker) priompt.Element {
    return priompt.Element{
        Name:     "repomap",
        Priority: 35,
        Stable:   false,
        PhaseBoost: map[string]int{
            "observe": +15, "orient": +15, "decide": +5,
            "act": 0, "reflect": -15, "compound": -20,
        },
        Render: contentFunc(workDir, ranker),
    }
}
```

### Step 4: Wire into buildSystemPrompt / PriomptSession

In `cmd/skaffen/main.go`, the current `buildSystemPrompt()` (line 723-733) returns a flat string from contextfiles. This needs to become a `[]priompt.Element` slice. The wiring point is wherever `session.New()` or `session.NewPriomptSession()` is called (main.go:305-306 for print mode, main.go:519-526 for TUI mode).

Currently `NewPriomptSession` exists (priompt_session.go:26) but is not wired -- the main.go still uses `session.New()` with a flat string prompt. The migration is:

1. Convert context files string into a Stable Element at Priority 85
2. Convert fault localization guidance into a Dynamic Element at Priority 65 with Act boost
3. Convert quality history into a Dynamic Element at Priority 40 with Orient boost
4. Add repomap Element at Priority 35
5. Pass all four to `NewPriomptSession(inner, sections)`

### Step 5: Evidence monitoring

The evidence pipeline already captures priompt metadata (loop.go:207-212). After integration, monitor:
- `excluded_elements` containing "repomap" -- indicates budget pressure, expected in late turns
- `excluded_stable` ever non-empty -- indicates system prompt is too large for the budget, needs investigation
- `stable_tokens` -- should be consistent across turns (validates cache prefix stability)

## Open Questions for Future Research

1. **Ranker signals:** What signals beyond file recency should drive ranking? Candidates: import graph centrality, symbol reference count in conversation, phase-specific boosting (test files during Reflect), explicit @-mentions.

2. **Multi-language support:** Current `extractGoSymbols()` is Go-only. The ranked repomap needs language-agnostic symbol extraction. Tree-sitter is the obvious choice but adds a dependency.

3. **Incremental updates:** Should the ranker maintain state across turns (incremental re-ranking based on new file activity) or re-rank from scratch? The ContentFunc is called once per turn, so incremental is possible via closure state.

4. **PriomptSession migration:** The main.go currently uses flat string prompts, not PriomptSession. This migration is a prerequisite for the repomap Element and should be done as a separate change before wiring in the repomap.
