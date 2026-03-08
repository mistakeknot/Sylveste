---
artifact_type: plan
bead: iv-30zy3
stage: planned
---
# Session Attribution Ledger — Implementation Plan

**Goal:** Add durable session attribution to the intercore kernel, replacing temp-file-based session→bead→run→phase tracking with a kernel-backed `sessions` + `session_attributions` table pair, `ic session` CLI commands, and dual-write hooks.

**Architecture:** Follow the `landed` package pattern: SQL migration → Go store → CLI commands → hook integration. The `landed_changes` implementation (v25) is the direct template.

**Tech Stack:** Go 1.22, `modernc.org/sqlite`, SQL (v26 migration), bash (hooks)

**Bead:** iv-30zy3

**Prior Learnings:**
- intercore uses `PRAGMA user_version` only (no schema_version table)
- CTE wrapping `UPDATE ... RETURNING` is not supported by `modernc.org/sqlite` — use direct queries
- TTL computation in Go (`time.Now().Unix()`) not SQL (`unixepoch()`) to avoid float promotion
- `SetMaxOpenConns(1)` required for SQLite; PRAGMAs set explicitly after `sql.Open`
- Bash hooks must treat `ic` failures as non-blocking (dual-write safety)

---

### Task 1: Create v26 migration and update schema.sql

**Files:**
- Create: `core/intercore/internal/db/migrations/026_sessions.sql`
- Modify: `core/intercore/internal/db/schema.sql` (append new tables)
- Modify: `core/intercore/internal/db/db.go` (bump `currentSchemaVersion` and `maxSchemaVersion` to 26)

**Step 1: Write the migration file**

Create `core/intercore/internal/db/migrations/026_sessions.sql`:

```sql
-- v26: durable session attribution ledger (iv-30zy3)
-- Replaces temp-file attribution (/tmp/interstat-*) with kernel-backed
-- session lifecycle and attribution event tracking.

CREATE TABLE IF NOT EXISTS sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    agent_type      TEXT NOT NULL DEFAULT 'claude-code',
    model           TEXT,
    started_at      INTEGER NOT NULL DEFAULT (unixepoch()),
    ended_at        INTEGER,
    metadata        TEXT,
    UNIQUE(session_id, project_dir)
);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_dir, started_at);
CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at);

CREATE TABLE IF NOT EXISTS session_attributions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      TEXT NOT NULL,
    project_dir     TEXT NOT NULL,
    bead_id         TEXT,
    run_id          TEXT,
    phase           TEXT,
    created_at      INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS idx_session_attr_session ON session_attributions(session_id, project_dir);
CREATE INDEX IF NOT EXISTS idx_session_attr_bead ON session_attributions(bead_id) WHERE bead_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_session_attr_created ON session_attributions(created_at);
```

**Step 2: Append tables to schema.sql**

Add the same DDL to the end of `core/intercore/internal/db/schema.sql` (after the `run_replay_inputs` section).

**Step 3: Bump schema version**

In `core/intercore/internal/db/db.go`, change:
```go
const (
    currentSchemaVersion = 26
    maxSchemaVersion     = 26
)
```

**Step 4: Verify migration applies**

```bash
cd core/intercore && go test ./internal/db/... -run TestMigrat -v
```

**Step 5: Commit**

- [x] `core/intercore/internal/db/migrations/026_sessions.sql`
- [x] `core/intercore/internal/db/schema.sql`
- [x] `core/intercore/internal/db/db.go`

```bash
git add core/intercore/internal/db/migrations/026_sessions.sql core/intercore/internal/db/schema.sql core/intercore/internal/db/db.go
git commit -m "feat(intercore): add sessions + session_attributions tables (v26 migration)"
```

---

### Task 2: Create session store package

**Files:**
- Create: `core/intercore/internal/session/store.go`

**Step 1: Write the store**

Follow the `landed/store.go` pattern exactly. Create `core/intercore/internal/session/store.go`:

```go
package session

import (
    "context"
    "database/sql"
    "fmt"
    "strings"
    "time"
)

// Session represents a registered agent session.
type Session struct {
    ID        int64   `json:"id"`
    SessionID string  `json:"session_id"`
    ProjectDir string `json:"project_dir"`
    AgentType  string `json:"agent_type"`
    Model     *string `json:"model,omitempty"`
    StartedAt int64   `json:"started_at"`
    EndedAt   *int64  `json:"ended_at,omitempty"`
    Metadata  *string `json:"metadata,omitempty"`
}

// Attribution represents a point-in-time attribution change within a session.
type Attribution struct {
    ID        int64   `json:"id"`
    SessionID string  `json:"session_id"`
    ProjectDir string `json:"project_dir"`
    BeadID    *string `json:"bead_id,omitempty"`
    RunID     *string `json:"run_id,omitempty"`
    Phase     *string `json:"phase,omitempty"`
    CreatedAt int64   `json:"created_at"`
}

// CurrentAttribution is the latest attribution state for a session.
type CurrentAttribution struct {
    SessionID  string  `json:"session_id"`
    ProjectDir string  `json:"project_dir"`
    BeadID     *string `json:"bead_id,omitempty"`
    RunID      *string `json:"run_id,omitempty"`
    Phase      *string `json:"phase,omitempty"`
    UpdatedAt  int64   `json:"updated_at"`
}

// StartOpts holds the fields for registering a session.
type StartOpts struct {
    SessionID  string
    ProjectDir string
    AgentType  string
    Model      string
    Metadata   string
}

// AttributeOpts holds the fields for recording an attribution change.
type AttributeOpts struct {
    SessionID  string
    ProjectDir string // defaults to session's project_dir if empty
    BeadID     string
    RunID      string
    Phase      string
}

// ListOpts filters session queries.
type ListOpts struct {
    ProjectDir string
    SessionID  string
    Since      int64
    ActiveOnly bool
    Limit      int
}

// Store provides session operations.
type Store struct {
    db *sql.DB
}

// NewStore creates a session store.
func NewStore(db *sql.DB) *Store {
    return &Store{db: db}
}
```

Then implement the methods:

- `Start(ctx, StartOpts) (int64, error)` — UPSERT into `sessions` (idempotent). Return row ID.
- `Attribute(ctx, AttributeOpts) (int64, error)` — INSERT into `session_attributions`. Return row ID.
- `End(ctx, sessionID string) error` — UPDATE `sessions` SET `ended_at`. Scoped to all project_dir rows for this session.
- `Current(ctx, sessionID, projectDir string) (*CurrentAttribution, error)` — SELECT latest attribution.
- `List(ctx, ListOpts) ([]Session, error)` — SELECT sessions with filters.

Key implementation details:
- `Start` uses `INSERT ... ON CONFLICT(session_id, project_dir) DO UPDATE SET started_at = excluded.started_at` (idempotent, updates metadata on re-register)
- `Attribute` inserts partial rows — only non-empty fields are written (uses `NULLIF(?, '')`)
- `Current` joins sessions with `session_attributions` using `ORDER BY created_at DESC LIMIT 1`
- `End` uses `time.Now().Unix()` for ended_at (per TTL convention)

**Step 2: Write tests**

Create `core/intercore/internal/session/store_test.go` with tests for:
- Start creates a session row
- Start is idempotent (second call updates metadata)
- Attribute inserts an attribution event
- Current returns the latest attribution
- Current returns nil when no attributions exist
- End sets ended_at
- List filters by project and since
- List active-only excludes ended sessions

**Step 3: Run tests**

```bash
cd core/intercore && go test ./internal/session/... -v
```

**Step 4: Commit**

- [x] `core/intercore/internal/session/store.go`
- [x] `core/intercore/internal/session/store_test.go`

```bash
git add core/intercore/internal/session/
git commit -m "feat(intercore): add session store package (start, attribute, end, current, list)"
```

---

### Task 3: Add `ic session` CLI commands

**Files:**
- Create: `core/intercore/cmd/ic/session.go`
- Modify: `core/intercore/cmd/ic/main.go` (register `session` command)

**Step 1: Write session.go**

Follow `landed.go` pattern. Create `core/intercore/cmd/ic/session.go` with:

```go
func cmdSession(ctx context.Context, args []string) int {
    // Subcommands: start, attribute, end, current, list
}

func cmdSessionStart(ctx context.Context, args []string) int {
    // Flags: --session=, --project=, --agent-type=, --model=, --metadata=
    // Required: --session, --project
    // Calls session.Store.Start()
}

func cmdSessionAttribute(ctx context.Context, args []string) int {
    // Flags: --session=, --project=, --bead=, --run=, --phase=
    // Required: --session
    // --project defaults to CWD if not provided
    // Calls session.Store.Attribute()
}

func cmdSessionEnd(ctx context.Context, args []string) int {
    // Flags: --session=
    // Required: --session
    // Calls session.Store.End()
}

func cmdSessionCurrent(ctx context.Context, args []string) int {
    // Flags: --session=, --project=
    // Required: --session
    // --project defaults to CWD if not provided
    // Calls session.Store.Current()
    // Output: JSON when --json, text otherwise
}

func cmdSessionList(ctx context.Context, args []string) int {
    // Flags: --project=, --since=, --active-only, --limit=
    // Calls session.Store.List()
}
```

**Step 2: Register in main.go**

Add to the switch statement in `main()`:
```go
case "session":
    os.Exit(cmdSession(ctx, args[2:]))
```

**Step 3: Build and verify**

```bash
cd core/intercore && go build -o ic ./cmd/ic && ./ic session start --help
```

**Step 4: Write integration test**

Add a test in `core/intercore/cmd/ic/session_test.go` or extend `test-integration.sh`:
```bash
# Start → attribute → current → end → list
./ic --db="$TMPDB" session start --session=test-123 --project=/tmp/test
./ic --db="$TMPDB" session attribute --session=test-123 --bead=iv-test --phase=brainstorm
./ic --db="$TMPDB" --json session current --session=test-123 --project=/tmp/test
./ic --db="$TMPDB" session end --session=test-123
./ic --db="$TMPDB" --json session list --project=/tmp/test
```

**Step 5: Run full test suite**

```bash
cd core/intercore && go test ./... -v
```

**Step 6: Commit**

- [x] `core/intercore/cmd/ic/session.go`
- [x] `core/intercore/cmd/ic/main.go`
- [x] Any test files

```bash
git add core/intercore/cmd/ic/session.go core/intercore/cmd/ic/main.go
git commit -m "feat(intercore): add ic session CLI commands (start, attribute, end, current, list)"
```

---

### Task 4: Update interstat session-start hook (dual-write)

**Files:**
- Modify: `interverse/interstat/hooks/session-start.sh`

**Step 1: Add `ic session start` call**

After the temp-file write (line 13), add:

```bash
# Dual-write to kernel session ledger (iv-30zy3)
if command -v ic &>/dev/null && [[ -n "$session_id" ]]; then
    ic session start --session="$session_id" --project="$(pwd)" --agent-type="${CLAUDE_AGENT_TYPE:-claude-code}" 2>/dev/null || true
fi
```

**Step 2: Add `ic session attribute` for existing bead context**

After the bead context write (line 21), add:

```bash
# Dual-write attribution to kernel ledger
if command -v ic &>/dev/null && [[ -n "$session_id" ]] && [[ -n "$bead_id" ]]; then
    local phase_val=""
    [[ -f "$phase_file" ]] && phase_val=$(cat "$phase_file" 2>/dev/null || echo "")
    ic session attribute --session="$session_id" --bead="$bead_id" ${phase_val:+--phase="$phase_val"} 2>/dev/null || true
fi
```

**Step 3: Verify hook syntax**

```bash
bash -n interverse/interstat/hooks/session-start.sh
```

**Step 4: Commit**

- [x] `interverse/interstat/hooks/session-start.sh`

```bash
git add interverse/interstat/hooks/session-start.sh
git commit -m "feat(interstat): dual-write session start to kernel ledger (iv-30zy3)"
```

---

### Task 5: Update clavain route/sprint attribution (dual-write)

**Files:**
- Modify: `os/clavain/commands/route.md` (bead-context registration blocks)
- Modify: `os/clavain/commands/sprint.md` (bead token attribution block)

**Step 1: Find the bead-context registration blocks in route.md**

Search for `interstat-bead-` writes in route.md. After each block that writes to `/tmp/interstat-bead-${_is_sid}`, add:

```bash
# Dual-write to kernel session ledger
ic session attribute --session="${_is_sid}" --bead="$CLAVAIN_BEAD_ID" 2>/dev/null || true
```

**Step 2: Update sprint.md bead token attribution block**

After the `Before Starting` section's bead token attribution block, add:

```bash
# Dual-write to kernel session ledger
if [[ -n "${CLAVAIN_BEAD_ID:-}" ]] && [[ -n "$_is_sid" ]]; then
    ic session attribute --session="$_is_sid" --bead="$CLAVAIN_BEAD_ID" 2>/dev/null || true
fi
```

**Step 3: Add phase attribution to sprint phase advances**

After each `sprint-advance` or `advance-phase` call in sprint.md, add:

```bash
ic session attribute --session="$(cat /tmp/interstat-session-id 2>/dev/null || echo '')" --phase="<phase>" 2>/dev/null || true
```

Note: These are markdown instruction files — they instruct the agent what bash to run, not executable scripts. The changes are documentation changes to the agent protocol.

**Step 4: Commit**

- [x] `os/clavain/commands/route.md`
- [x] `os/clavain/commands/sprint.md`

```bash
git add os/clavain/commands/route.md os/clavain/commands/sprint.md
git commit -m "feat(clavain): dual-write bead/phase attribution to kernel session ledger (iv-30zy3)"
```

---

### Task 6: Update interstat session-end hook

**Files:**
- Modify: `interverse/interstat/hooks/session-end.sh`

**Step 1: Add `ic session end` call**

After session_id extraction (line 10), before the background parser (line 17), add:

```bash
# Record session end in kernel ledger (iv-30zy3)
if command -v ic &>/dev/null; then
    ic session end --session="$SESSION_ID" 2>/dev/null || true
fi
```

**Step 2: Verify hook syntax**

```bash
bash -n interverse/interstat/hooks/session-end.sh
```

**Step 3: Commit**

- [x] `interverse/interstat/hooks/session-end.sh`

```bash
git add interverse/interstat/hooks/session-end.sh
git commit -m "feat(interstat): dual-write session end to kernel ledger (iv-30zy3)"
```

---

### Task 7: Build `ic` binary and integration smoke test

**Step 1: Build**

```bash
cd core/intercore && go build -o ic ./cmd/ic
```

**Step 2: Run full test suite**

```bash
cd core/intercore && go test ./... -v
```

**Step 3: Manual smoke test**

```bash
TMPDB=$(mktemp -d)/test.db
./ic --db="$TMPDB" init
./ic --db="$TMPDB" session start --session=smoke-001 --project=/tmp/test --agent-type=claude-code
./ic --db="$TMPDB" session attribute --session=smoke-001 --bead=iv-test --phase=brainstorm
./ic --db="$TMPDB" --json session current --session=smoke-001 --project=/tmp/test
# Expect: {"session_id":"smoke-001","project_dir":"/tmp/test","bead_id":"iv-test","phase":"brainstorm",...}
./ic --db="$TMPDB" session attribute --session=smoke-001 --bead=iv-test --run=run-abc --phase=executing
./ic --db="$TMPDB" --json session current --session=smoke-001 --project=/tmp/test
# Expect: updated bead_id, run_id, phase
./ic --db="$TMPDB" session end --session=smoke-001
./ic --db="$TMPDB" --json session list --project=/tmp/test
# Expect: array with one ended session
rm -rf "$(dirname "$TMPDB")"
```

**Step 4: Verify bash syntax for all modified hooks**

```bash
bash -n interverse/interstat/hooks/session-start.sh
bash -n interverse/interstat/hooks/session-end.sh
```

**Step 5: Final commit if needed**

```bash
git add -A && git diff --cached --stat
# Only commit if there are changes from smoke test cleanup
```
