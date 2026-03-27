---
artifact_type: plan
bead: Sylveste-4hu
stage: design
prd: docs/prds/2026-03-11-skaffen-go-rewrite.md
requirements:
  - "Provider interface: Stream(ctx, messages, tools, config) → StreamResponse"
  - "Anthropic SSE streaming with tool_use support"
  - "Claude Code proxy via --print --output-format=stream-json"
  - "Provider selection by name"
  - "Unit tests with golden files"
---
# F1: Provider Abstraction + Anthropic Implementation

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Sylveste-4hu
**Goal:** Streaming LLM provider interface with Anthropic Claude as the default backend and Claude Code subprocess proxy as opt-in alternative.

**Architecture:** The provider package defines a `Provider` interface with a single `Stream` method returning an iterator-style `StreamResponse`. The Anthropic provider implements direct SSE streaming against the Messages API (~300 lines). The Claude Code proxy spawns `claude --print --output-format=stream-json` as a subprocess. Both providers are registered in a factory map keyed by name. All types live in `internal/provider/` with sub-packages for each implementation.

**Tech Stack:** Go 1.22, `net/http` for SSE, `os/exec` for subprocess, `encoding/json` for marshaling. No external dependencies — direct implementation over the official `anthropic-sdk-go` (v1.26.0 exists but adds unnecessary abstraction for our streaming needs and couples us to their type system; ~300 lines of direct SSE parsing gives us full control over the streaming pipeline and matches Sylveste's minimal-deps philosophy).

**Research findings** (from API docs + SDK analysis):
- SSE `message_delta.usage.output_tokens` is **cumulative**, not incremental — only read final value
- SSE streams can include `event: error` **after HTTP 200** — must handle mid-stream errors
- Tool use `input_json_delta` emits partial JSON fragments — accumulate until `content_block_stop`, then parse
- Claude Code proxy uses `claude --print --output-format=stream-json` (no `--mode rpc` flag exists)
- `ping` events are keepalive markers — skip silently

---

## Must-Haves

**Truths** (observable behaviors):
- `go test ./internal/provider/...` passes with zero external calls (golden files only)
- Anthropic provider streams text chunks and tool_use blocks from recorded SSE responses
- Claude Code proxy provider returns an actionable error when `claude` binary is missing
- Provider factory returns correct implementation by name ("anthropic", "claude-code")
- Token usage (input, output, cache_read, cache_creation) is reported on every response

**Artifacts** (files that must exist):
- `internal/provider/provider.go` — interface + types
- `internal/provider/anthropic/anthropic.go` — SSE streaming client
- `internal/provider/anthropic/sse.go` — SSE line parser
- `internal/provider/claudecode/claudecode.go` — subprocess proxy
- `internal/provider/factory.go` — name → Provider registry
- `internal/provider/anthropic/testdata/` — golden SSE response files
- `internal/provider/claudecode/testdata/` — golden stream-json files

**Key Links** (where breakage causes cascading failures):
- `StreamResponse.Next()` contract: callers (F3 agent loop) depend on receiving `TextDelta`, `ToolUseStart`, `ToolUseDelta`, `Done` event types in order — wrong sequence breaks tool execution
- `Usage` struct must include `CacheReadInputTokens` — F4 model routing uses this for cost calculation
- `Provider` interface must be mockable — F3 tests inject a mock provider

---

### Task 1: Define provider types and interface

**Files:**
- `internal/provider/provider.go` (new)
- `internal/provider/types.go` (new)

**Changes:**

`types.go` defines the message and content types that match the Anthropic Messages API:

```go
package provider

// Role identifies the message sender.
type Role string

const (
    RoleUser      Role = "user"
    RoleAssistant Role = "assistant"
)

// Message is a single conversation turn.
type Message struct {
    Role    Role          `json:"role"`
    Content []ContentBlock `json:"content"`
}

// ContentBlock is a polymorphic content element.
type ContentBlock struct {
    Type  string `json:"type"`            // "text", "tool_use", "tool_result"
    Text  string `json:"text,omitempty"`
    ID    string `json:"id,omitempty"`    // tool_use ID
    Name  string `json:"name,omitempty"` // tool name
    Input json.RawMessage `json:"input,omitempty"` // tool_use input (raw JSON)

    // tool_result fields
    ToolUseID string `json:"tool_use_id,omitempty"`
    Content   string `json:"content,omitempty"` // tool result text (overloaded with Text for tool_result)
    IsError   bool   `json:"is_error,omitempty"`
}

// ToolDef describes a tool available to the model.
type ToolDef struct {
    Name        string          `json:"name"`
    Description string          `json:"description"`
    InputSchema json.RawMessage `json:"input_schema"`
}

// Config holds per-request settings.
type Config struct {
    Model       string
    MaxTokens   int
    Temperature float64 // -1 means use default
    System      string  // system prompt
    StopReason  string
}

// Usage tracks token consumption.
type Usage struct {
    InputTokens              int `json:"input_tokens"`
    OutputTokens             int `json:"output_tokens"`
    CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
    CacheReadInputTokens     int `json:"cache_read_input_tokens"`
}
```

`provider.go` defines the interface and stream event types:

```go
package provider

import "context"

// EventType identifies a streaming event.
type EventType int

const (
    EventTextDelta    EventType = iota // Partial text content
    EventToolUseStart                   // Tool call begins (has ID, name)
    EventToolUseDelta                   // Partial tool input JSON
    EventDone                           // Stream complete, Usage populated
    EventError                          // Stream error
)

// StreamEvent is a single event from a streaming response.
type StreamEvent struct {
    Type  EventType
    Text  string          // for TextDelta and ToolUseDelta
    ID    string          // for ToolUseStart
    Name  string          // for ToolUseStart
    Input json.RawMessage // for ToolUseStart (partial not used, accumulated by caller)
    Usage *Usage          // for EventDone
    Err   error           // for EventError
    StopReason string     // for EventDone: "end_turn", "tool_use", "max_tokens"
}

// StreamResponse is an iterator over streaming events.
// Call Next() in a loop until it returns false, then check Err().
type StreamResponse struct {
    events <-chan StreamEvent
    current StreamEvent
    err     error
}

// Provider is the LLM inference interface.
type Provider interface {
    // Stream sends a request and returns a streaming response.
    Stream(ctx context.Context, messages []Message, tools []ToolDef, config Config) (*StreamResponse, error)

    // Name returns the provider identifier (e.g., "anthropic", "claude-code").
    Name() string
}
```

Plus `Next()`, `Event()`, and `Err()` methods on `StreamResponse`.

**Tests:** Compile-only — `go build ./internal/provider/`

**Exit criteria:** `go vet ./internal/provider/` passes. Types compile.

---

### Task 2: SSE line parser

**Files:**
- `internal/provider/anthropic/sse.go` (new)
- `internal/provider/anthropic/sse_test.go` (new)

**Changes:**

Implement a minimal SSE parser that reads from an `io.Reader` and emits `SSEEvent` structs. The Anthropic streaming API sends:

```
event: message_start
data: {"type":"message_start","message":{...}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_xxx","name":"read","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\""}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":42}}

event: message_stop
data: {"type":"message_stop"}
```

The parser:
1. Reads lines from the reader
2. Accumulates `event:` and `data:` pairs
3. Emits `SSEEvent{Event string, Data []byte}` on each blank-line boundary
4. Handles `: ` comment lines (keepalive pings) by skipping them
5. Returns `io.EOF` when the reader closes

```go
type SSEEvent struct {
    Event string
    Data  []byte
}

type SSEReader struct {
    scanner *bufio.Scanner
}

func NewSSEReader(r io.Reader) *SSEReader
func (s *SSEReader) Next() (SSEEvent, error)
```

**Tests:** Table-driven tests with multi-event SSE byte streams. Test cases:
- Single text event
- Multiple events separated by blank lines
- Comment lines (`: ping`) skipped
- Empty data field
- Incomplete event (no trailing blank line — blocks until EOF)

**Exit criteria:** `go test ./internal/provider/anthropic/ -run SSE` passes.

---

### Task 3: Anthropic streaming provider

**Files:**
- `internal/provider/anthropic/anthropic.go` (new)
- `internal/provider/anthropic/anthropic_test.go` (new)
- `internal/provider/anthropic/testdata/stream_text.sse` (new)
- `internal/provider/anthropic/testdata/stream_tool_use.sse` (new)
- `internal/provider/anthropic/testdata/stream_error.sse` (new)

**Changes:**

Implement `AnthropicProvider` that:

1. **Constructor:** `New(apiKey string, opts ...Option) *AnthropicProvider`
   - Options: `WithBaseURL(url)`, `WithModel(model)`, `WithHTTPClient(client)`
   - Default base URL: `https://api.anthropic.com`
   - Default model: `claude-sonnet-4-20250514`

2. **Stream method:**
   - Builds POST request to `/v1/messages` with:
     - Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`
     - Body: `{"model", "max_tokens", "messages", "tools", "system", "stream": true}`
   - Sends request via `http.Client`
   - On non-200 response: parse error JSON, return wrapped error with status code and message
   - On 200: create `SSEReader` from response body, launch goroutine that:
     - Reads SSE events
     - Parses JSON `data` field based on `type`:
       - `message_start` → extract initial usage
       - `content_block_start` with `type:"text"` → emit `EventTextDelta("")` (signals text block started)
       - `content_block_start` with `type:"tool_use"` → emit `EventToolUseStart` with ID and name
       - `content_block_delta` with `text_delta` → emit `EventTextDelta` with text
       - `content_block_delta` with `input_json_delta` → emit `EventToolUseDelta` with partial JSON
       - `content_block_stop` → no event (caller accumulates)
       - `message_delta` → extract final usage and stop_reason
       - `message_stop` → emit `EventDone` with accumulated usage
     - Sends events to channel
     - Closes channel on completion or error

3. **Error handling:**
   - HTTP 429 (rate limit): return `ErrRateLimited` with `retry-after` header value
   - HTTP 529 (overloaded): return `ErrOverloaded`
   - HTTP 401: return `ErrUnauthorized`
   - Other 4xx/5xx: return `ErrAPI` with status and message
   - **Mid-stream error** (SSE `event: error` after 200): emit `EventError` with parsed error type and message — API can send `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}` mid-stream
   - `ping` events: skip silently (keepalive, no data to emit)
   - Unknown event types: skip silently (forward compatibility)

**Tests:** Use `httptest.NewServer` that serves golden SSE files from `testdata/`. Test cases:
- `stream_text.sse`: Simple text response → verify text chunks concatenate correctly
- `stream_tool_use.sse`: Response with tool_use → verify tool ID, name, accumulated input JSON
- `stream_error.sse`: 429 response → verify `ErrRateLimited` returned
- Usage tracking: verify `InputTokens`, `OutputTokens`, `CacheReadInputTokens` populated

**Exit criteria:** `go test ./internal/provider/anthropic/` passes with zero network calls.

---

### Task 4: Create golden SSE test files

**Files:**
- `internal/provider/anthropic/testdata/stream_text.sse` (new)
- `internal/provider/anthropic/testdata/stream_tool_use.sse` (new)
- `internal/provider/anthropic/testdata/stream_mixed.sse` (new)

**Changes:**

Create realistic SSE response files based on the Anthropic Messages API format. These are the "recorded HTTP responses" from the acceptance criteria.

`stream_text.sse` — simple text response:
```
event: message_start
data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-20250514","stop_reason":null,"usage":{"input_tokens":25,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", world!"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":8}}

event: message_stop
data: {"type":"message_stop"}
```

`stream_tool_use.sse` — tool call response:
```
event: message_start
data: {"type":"message_start","message":{"id":"msg_02","type":"message","role":"assistant","content":[],"model":"claude-sonnet-4-20250514","stop_reason":null,"usage":{"input_tokens":100,"output_tokens":0}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"I'll read that file."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_01ABC","name":"read","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"file_path\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"/tmp/test.go\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":45}}

event: message_stop
data: {"type":"message_stop"}
```

`stream_mixed.sse` — multiple tool calls + cache stats in usage.

**Tests:** No separate test — these are consumed by Task 3's tests.

**Exit criteria:** Files exist and are valid SSE format (parseable by Task 2's SSEReader).

---

### Task 5: Claude Code proxy provider

**Files:**
- `internal/provider/claudecode/claudecode.go` (new)
- `internal/provider/claudecode/claudecode_test.go` (new)
- `internal/provider/claudecode/testdata/stream_response.jsonl` (new)

**Changes:**

Implement `ClaudeCodeProvider` that delegates inference to a local `claude` binary:

1. **Constructor:** `New(opts ...Option) *ClaudeCodeProvider`
   - Options: `WithBinaryPath(path)` (default: look up `claude` in PATH), `WithModel(model)`
   - Constructor validates binary exists via `exec.LookPath`
   - If binary not found: store error, `Stream()` returns it immediately with message: `"claude binary not found in PATH. Install Claude Code: https://docs.anthropic.com/en/docs/claude-code"`

2. **Stream method:**
   - Spawns: `claude --print --output-format=stream-json --model <model> --permission-mode=bypassPermissions`
   - Writes the user prompt to stdin (last user message content)
   - Reads stream-json lines from stdout
   - Each line is a JSON object with a `type` field:
     - `{"type":"assistant","content":[{"type":"text","text":"..."}]}` → emit text events
     - `{"type":"result","result":"...","cost_usd":0.01,"usage":{"input":100,"output":50}}` → emit done with usage
   - Maps to `StreamEvent` types and sends to channel
   - On subprocess exit with non-zero: return error with stderr content

3. **Error cases:**
   - Binary not found → actionable install message
   - Binary exists but not logged in → detect from stderr ("not logged in", "authentication"), return: `"Claude Code is not logged in. Run: claude login"`
   - Unexpected response format → return error with first 200 chars of output
   - Context cancellation → kill subprocess via `cmd.Process.Kill()`

**Tests:** Mock the subprocess by setting `WithBinaryPath` to a test script that echoes golden JSONL. Test cases:
- Successful text response
- Binary not found error
- Non-zero exit code

**Exit criteria:** `go test ./internal/provider/claudecode/` passes.

---

### Task 6: Provider factory and registration

**Files:**
- `internal/provider/factory.go` (new)
- `internal/provider/factory_test.go` (new)

**Changes:**

```go
// Registry maps provider names to constructors.
var registry = map[string]func(cfg ProviderConfig) (Provider, error){
    "anthropic":   newAnthropicFromConfig,
    "claude-code": newClaudeCodeFromConfig,
}

// ProviderConfig holds provider initialization settings.
type ProviderConfig struct {
    APIKey   string // for anthropic
    Model    string
    BaseURL  string // override for testing
}

// New creates a provider by name.
func New(name string, cfg ProviderConfig) (Provider, error)

// Default returns the default provider name.
func Default() string { return "anthropic" }
```

- `newAnthropicFromConfig` reads `ANTHROPIC_API_KEY` env var if `cfg.APIKey` is empty
- `newClaudeCodeFromConfig` calls `claudecode.New()`
- Unknown name → `fmt.Errorf("unknown provider %q, available: anthropic, claude-code", name)`

**Tests:**
- `New("anthropic", ...)` returns `*anthropic.AnthropicProvider`
- `New("claude-code", ...)` returns `*claudecode.ClaudeCodeProvider`
- `New("openai", ...)` returns error with available providers listed
- `New("anthropic", ProviderConfig{})` reads from `ANTHROPIC_API_KEY` env var

**Exit criteria:** `go test ./internal/provider/ -run Factory` passes.

---

### Task 7: StreamResponse iterator implementation

**Files:**
- `internal/provider/stream.go` (new)
- `internal/provider/stream_test.go` (new)

**Changes:**

Complete the `StreamResponse` implementation from Task 1:

```go
// NewStreamResponse creates a StreamResponse from a channel.
func NewStreamResponse(events <-chan StreamEvent) *StreamResponse

// Next advances to the next event. Returns false when done or error.
func (s *StreamResponse) Next() bool

// Event returns the current event. Only valid after Next() returns true.
func (s *StreamResponse) Event() StreamEvent

// Err returns the error, if any. Check after Next() returns false.
func (s *StreamResponse) Err() error

// Collect reads all events and returns accumulated text, tool calls, and usage.
// Convenience method for non-streaming callers.
func (s *StreamResponse) Collect() (*CollectedResponse, error)

type CollectedResponse struct {
    Text      string
    ToolCalls []ToolCall
    Usage     Usage
    StopReason string
}

type ToolCall struct {
    ID    string
    Name  string
    Input json.RawMessage
}
```

The `Collect()` method is critical for testing and for the agent loop (F3) which needs accumulated tool calls.

**Tests:**
- Feed events through channel, verify `Next()`/`Event()` returns them in order
- `Collect()` accumulates text deltas into single string
- `Collect()` accumulates tool_use start + deltas into `ToolCall` with complete JSON input
- Error event causes `Next()` to return false and `Err()` to return the error
- Context cancellation mid-stream

**Exit criteria:** `go test ./internal/provider/ -run Stream` passes.

---

### Task 8: Integration test — full provider round-trip

**Files:**
- `internal/provider/provider_test.go` (new)

**Changes:**

End-to-end test that verifies the full chain: factory → provider → stream → collect.

```go
func TestAnthropicProvider_StreamText(t *testing.T) {
    // Start httptest server serving stream_text.sse
    // Create provider via factory with test server URL
    // Stream a simple message
    // Collect response
    // Assert: text == "Hello, world!", usage.InputTokens == 25, stop_reason == "end_turn"
}

func TestAnthropicProvider_StreamToolUse(t *testing.T) {
    // Serve stream_tool_use.sse
    // Collect response
    // Assert: 1 tool call, name == "read", input has file_path
    // Assert: text == "I'll read that file."
    // Assert: stop_reason == "tool_use"
}

func TestClaudeCodeProvider_BinaryNotFound(t *testing.T) {
    // Create with nonexistent binary path
    // Stream returns error with install instructions
}

func TestFactoryDefault(t *testing.T) {
    // Default() returns "anthropic"
    // New("anthropic", ...) with test server works
}
```

**Exit criteria:** `go test ./internal/provider/...` — all tests pass, zero network calls, `go vet` clean.

---

### Task 9: Update go.mod and verify clean build

**Files:**
- `go.mod` (edit)

**Changes:**
- Verify `go 1.22` is sufficient (no 1.23+ features used)
- Run `go mod tidy` to clean up
- Run `go vet ./...` to verify no issues
- Run `go build ./cmd/skaffen/` to verify the binary still builds
- The main.go doesn't import provider yet — that happens in F3 (agent loop)

**Exit criteria:** `go build ./...` and `go vet ./...` pass. `go test ./...` passes (all provider tests + main package).
