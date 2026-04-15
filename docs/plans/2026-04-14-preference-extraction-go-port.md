---
artifact_type: plan
bead: sylveste-benl.4
stage: plan
---

# Plan: Preference Extraction Pipeline Go Port

Port `apps/Auraken/src/auraken/extraction.py` (538 lines) to `os/Skaffen/pkg/extraction/`.

**Key difference from benl.2/3:** This is NOT pure computation. The Python source is coupled to SQLAlchemy, asyncio, and `claude -p` subprocess. The Go port separates concerns:
- **Pure logic** (prompt templates, response parsing, entity diffing, feedback detection) → `pkg/extraction/`
- **DB operations** → interfaces (concrete implementation deferred to benl.10)
- **LLM calls** → Skaffen's existing provider abstraction

## Design Decisions

1. **DB as interfaces.** `EntityStore` and `EpisodeStore` interfaces let the extraction logic work without knowing the storage backend. benl.10 provides the concrete PostgreSQL implementation.
2. **Provider for LLM.** Use Skaffen's `provider.Provider` interface instead of `claude -p` subprocess. The extraction prompts are the same; only the transport changes.
3. **Go timer for debounce.** Replace asyncio.Task + sleep(3) with `time.AfterFunc` per user. Map with mutex for concurrent access.
4. **Shared entity types.** `Entity`, `Episode`, `Feedback` types defined here, reused by benl.10.

## File Layout

```
os/Skaffen/pkg/extraction/
  doc.go              # Package doc
  types.go            # Entity, Episode, Feedback, ExtractionResult types
  store.go            # EntityStore, EpisodeStore interfaces
  prompts.go          # EXTRACTION_PROMPT, FEEDBACK_EXTRACTION_PROMPT templates
  parse.go            # ParseExtractionResponse, ParseFeedbackResponse
  parse_test.go       # Parsing tests with real LLM output samples
  feedback.go         # IsLikelyFeedback (regex), feedback detection patterns
  feedback_test.go    # Feedback detection tests
  extract.go          # Extractor struct (orchestrates pipeline)
  extract_test.go     # Pipeline tests with mock store/provider
```

## Tasks

### Task 1: Types and interfaces

**Files:** `doc.go`, `types.go`, `store.go`

- `Entity` struct: Domain, Type, Value, Valence, Origin, Confidence, Action, ValidUntil, SourceEpisodeIDs, SourceContradicts
- `Episode` struct: UserID, SessionID, ChunkText, ChunkType
- `ExtractionResult` struct: HasPreferenceSignal bool, Entities []Entity
- `FeedbackResult` struct: HasFeedback bool, Entities []FeedbackEntity
- `FeedbackEntity` struct: Type, Value, Valence, Confidence
- `EntityStore` interface: `GetActive(ctx, userID) ([]Entity, error)`, `Apply(ctx, userID, sessionID, entities []Entity, episodeText string) (int, error)`, `SetProfileDirty(ctx, userID) error`
- `EpisodeStore` interface: `Create(ctx, episode Episode) (string, error)`
- Valence/Origin/Action as string type constants

### Task 2: Prompt templates

**Files:** `prompts.go`

- `ExtractionPrompt` — the extraction system prompt with `{existing_entities}` and `{conversation}` markers
- `FeedbackExtractionPrompt` — feedback extraction with `{conversation}` marker
- `FormatConversation(turns []Turn, limit int) string` — formats turn history
- `FormatEntities(entities []Entity) string` — formats existing entities for comparison

### Task 3: Response parsing

**Files:** `parse.go`, `parse_test.go`

- `ParseExtractionResponse(raw string) (ExtractionResult, error)` — strips markdown fences, parses JSON
- `ParseFeedbackResponse(raw string) (FeedbackResult, error)` — same pattern
- Tests with real-world LLM output samples (clean JSON, markdown-fenced, malformed)

### Task 4: Feedback detection

**Files:** `feedback.go`, `feedback_test.go`

- Port all 28 `_FEEDBACK_PATTERNS` regex patterns
- Compile at package init (same pattern as style package)
- `IsLikelyFeedback(text string) bool`
- Tests for each pattern category

### Task 5: Extractor pipeline

**Files:** `extract.go`, `extract_test.go`

- `Extractor` struct: store EntityStore, provider LLMProvider, debounceWindow time.Duration
- `LLMProvider` interface: `Complete(ctx context.Context, systemPrompt, userPrompt string) (string, error)`
- `(*Extractor) Extract(ctx, userID, sessionID string, messages []Turn) (int, error)` — the full pipeline: format conversation → get existing entities → call LLM → parse → apply
- `(*Extractor) ExtractFeedback(ctx, userID string, text string, history []Turn) error` — meta-feedback path
- `(*Extractor) ScheduleExtraction(userID string, messages []Turn)` — debounced via per-user `time.AfterFunc`
- Tests with mock store + mock provider (no real LLM calls)

## Build Sequence

Task 1 → Task 2 → Task 3 → Task 4 → Task 5 (sequential, each depends on previous)

## What's Deferred

- Concrete `EntityStore` implementation (benl.10 — shared identity DB)
- Provider wiring (Skaffen already has this; extraction just calls the interface)
- `register_subscribers` stub (Skaffen has its own event wiring)
- Actual burst deduplication timer (the `ScheduleExtraction` method is implemented but not wired to a message bus)
