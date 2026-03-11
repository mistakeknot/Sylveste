---
artifact_type: plan
bead: Demarch-2ic
stage: design
prd: docs/prds/2026-03-11-skaffen-go-rewrite.md
requirements:
  - "JSONL append-only session format with metadata per turn"
  - "Basic truncation: keep system prompt + last N turns"
  - "Session resume from JSONL file"
  - "Implement agent.Session interface"
---
# F5: Session Persistence

> **For Claude:** REQUIRED SUB-SKILL: Use clavain:executing-plans to implement this plan task-by-task.

**Bead:** Demarch-2ic
**Goal:** Implement the `Session` interface from F3's `deps.go` with JSONL-backed persistence. Sessions survive process restarts and context stays bounded via basic truncation.

**Architecture:** `internal/session/` package. A `JSONLSession` struct implements `agent.Session`. Each turn is appended as a JSON line to `~/.skaffen/sessions/<id>.jsonl`. On load, reads all lines back. Truncation keeps system prompt + last N turns.

**Key insight:** The current `agent.Session` interface only has `SystemPrompt()` and `Save()`. We need to extend it to also provide message history for the agent loop to use. Rather than changing the interface (which would break the NoOp), we'll add a `Messages()` method to the interface — the NoOp returns empty, the real session returns history.

**Tech Stack:** Go 1.22, `encoding/json`, `os` for file I/O, `sync` for concurrent safety.

---

## Must-Haves

**Truths:**
- `go test ./internal/session/...` passes
- Session saves turns to JSONL, loads them back identically
- Truncation keeps system prompt + last N turns when history exceeds threshold
- Session ID is a stable identifier for file naming

**Artifacts:**
- `internal/session/session.go` — JSONLSession implementation
- `internal/session/session_test.go` — roundtrip and truncation tests
- `internal/agent/deps.go` — updated Session interface with Messages()

---

### Task 1: Extend Session interface with Messages()

**Files:**
- `internal/agent/deps.go` (modify)

**Changes:**

Add `Messages()` to the Session interface so the agent loop can read back conversation history for session resume:

```go
type Session interface {
    SystemPrompt(phase tool.Phase) string
    Save(turn Turn) error
    Messages() []provider.Message
}
```

Update `NoOpSession` to return nil:
```go
func (s *NoOpSession) Messages() []provider.Message { return nil }
```

**Exit criteria:** `go test ./internal/agent/...` still passes.

---

### Task 2: JSONLSession implementation

**Files:**
- `internal/session/session.go` (new)

**Changes:**

```go
type JSONLSession struct {
    id       string
    dir      string // ~/.skaffen/sessions/
    prompt   string
    messages []provider.Message
    maxTurns int // truncation threshold, default 20
    mu       sync.Mutex
}

func New(id, dir, systemPrompt string, maxTurns int) *JSONLSession
func (s *JSONLSession) SystemPrompt(phase tool.Phase) string
func (s *JSONLSession) Save(turn agent.Turn) error  // append to JSONL
func (s *JSONLSession) Messages() []provider.Message
func (s *JSONLSession) Load() error                  // read from JSONL
```

JSONL format — each line is a JSON object:
```json
{"type":"turn","phase":"build","messages":[...],"usage":{"input_tokens":10},"tool_calls":1,"timestamp":"2026-03-11T..."}
```

Save: marshal turn + timestamp, append line + newline, fsync.
Load: read file line by line, unmarshal, reconstruct messages slice.
Truncation: after load or save, if len(messages) > maxTurns*2 (rough heuristic for messages per turn), keep first message (system context) + last maxTurns*2 messages.

**Exit criteria:** Compiles. `go vet` clean.

---

### Task 3: Session file I/O with fsync

**Files:**
- `internal/session/session.go` (extend)

**Changes:**

Save opens file in append mode, writes one JSON line, calls `f.Sync()` before close. This ensures crash safety — partial writes don't corrupt previous data.

Load reads the entire file, splits by newline, unmarshals each line. Skips empty lines and malformed entries gracefully (log warning, continue).

File path: `<dir>/<id>.jsonl`

Creates directory if needed (`os.MkdirAll`).

**Exit criteria:** File written after Save, readable after Load.

---

### Task 4: Basic truncation

**Files:**
- `internal/session/session.go` (extend)

**Changes:**

After loading or after accumulating messages beyond threshold:
- Count message pairs (user+assistant = 1 turn)
- If turns > maxTurns: keep messages[0] (first user message as context anchor) + last maxTurns*2 messages
- This is intentionally simple — v0.2 adds Priompt-style priority rendering

**Exit criteria:** Truncation test: save 30 turns, load with maxTurns=5, verify only ~10 messages returned.

---

### Task 5: Wire session into CLI

**Files:**
- `cmd/skaffen/main.go` (modify)

**Changes:**

Add `--session` flag for session ID. If provided, create JSONLSession instead of NoOpSession:

```go
flagSession = flag.String("session", "", "Session ID for persistence (creates ~/.skaffen/sessions/<id>.jsonl)")
```

In `run()`:
```go
if *flagSession != "" {
    dir := filepath.Join(os.Getenv("HOME"), ".skaffen", "sessions")
    sess := session.New(*flagSession, dir, *flagSystem, 20)
    sess.Load() // ignore error on first run
    opts = append(opts, agent.WithSession(sess))
}
```

Also update the agent loop to use `session.Messages()` as initial conversation history when non-empty (prepend to the task message).

**Exit criteria:** `skaffen -session test1 -p "hello"` creates a JSONL file. Second run with same session ID loads history.

---

### Task 6: Update agent loop to use session messages

**Files:**
- `internal/agent/loop.go` (modify)

**Changes:**

At the start of `Run()`, check if session has existing messages:
```go
messages := a.session.Messages()
if len(messages) == 0 {
    messages = []provider.Message{
        {Role: provider.RoleUser, Content: []provider.ContentBlock{
            {Type: "text", Text: task},
        }},
    }
} else {
    // Append new task as latest user message
    messages = append(messages, provider.Message{
        Role: provider.RoleUser, Content: []provider.ContentBlock{
            {Type: "text", Text: task},
        },
    })
}
```

**Exit criteria:** Agent loop uses session history when available.

---

### Task 7: Tests

**Files:**
- `internal/session/session_test.go` (new)

**Changes:**

1. **Save and Load roundtrip** — save 3 turns, load, verify messages match
2. **Truncation** — save 30 turns with maxTurns=5, verify truncated correctly
3. **Empty session** — new session returns empty Messages()
4. **Fsync safety** — save writes to file, verify file exists and is valid JSONL
5. **Concurrent saves** — multiple goroutines saving, no corruption

**Exit criteria:** `go test ./internal/session/ -v` passes.

---

### Task 8: Verify clean build

**Files:** none new

**Changes:**
- `go mod tidy && go vet ./... && go test ./... && go build -o /tmp/skaffen ./cmd/skaffen/`

**Exit criteria:** All tests pass. Binary built.
