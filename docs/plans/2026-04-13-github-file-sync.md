---
artifact_type: plan
bead: sylveste-911m
prd: docs/prds/2026-04-13-github-file-sync.md
brainstorm: docs/brainstorms/2026-04-13-github-file-sync-brainstorm.md
stage: plan
---

# Plan: GitHub Bidirectional File Sync

## Execution Order

```
Phase A: F1 (entity correlation) + F5 (ancestor versioning) — parallel, no deps
Phase B: F2 (Contents API + filesync module) — needs F1 + F5
Phase C: F3 (push webhook) + F4 (reconciliation poll) — parallel, need F1
```

Each phase gate: all tasks in phase pass `go test -race ./...` before next phase begins.

## Beads

| Feature | Bead | Deps |
|---------|------|------|
| F1: Entity correlation | sylveste-ykta | — |
| F2: Contents API + filesync | sylveste-m6hb | F1, F5 |
| F3: Push webhook handler | sylveste-jd6m | F1 |
| F4: Tree-SHA reconciliation | sylveste-irlf | F1, F5 |
| F5: AncestorStore versioning | sylveste-2l2x | — |

---

## Phase A: Foundations (F1 + F5, parallel)

### Task A.1: Entity Correlation Table (F1)

**Bead:** sylveste-ykta
**Files:** `internal/correlation/store.go`, `internal/correlation/store_test.go`

**Steps:**
1. New package `internal/correlation/`. SQLite table:
   ```sql
   CREATE TABLE IF NOT EXISTS entity_correlations (
       source_key TEXT NOT NULL,
       target_key TEXT NOT NULL,
       adapter_pair TEXT NOT NULL,
       created_at TEXT NOT NULL,
       PRIMARY KEY (source_key, target_key)
   );
   CREATE INDEX IF NOT EXISTS idx_corr_source ON entity_correlations(source_key);
   CREATE INDEX IF NOT EXISTS idx_corr_target ON entity_correlations(target_key);
   ```
2. SQLite hardening: WAL mode, `busy_timeout=5000`, `SetMaxOpenConns(1)`, context-aware queries (same pattern as journal, ancestor).
3. `New(dbPath string) (*Store, error)` — open/create DB.
4. `Register(ctx, sourceKey, targetKey, adapterPair) error` — upsert (idempotent). Both keys normalized via `NormalizePath()` before insertion.
5. `Resolve(ctx, key string) ([]string, error)` — returns all correlated keys for a given key. Bidirectional: searches both `source_key` and `target_key` columns. Returns empty slice (not error) if no correlations exist.
6. `NormalizePath(p string) string` — Unicode NFC normalization, forward-slash separator, no trailing slash. Applied at every registration and lookup call.
7. `Close() error`.

**Test:**
- Register A↔B, Resolve(A) returns [B], Resolve(B) returns [A]
- Register idempotent (second call no error)
- NormalizePath: NFD input → NFC output; backslash → forward-slash
- Resolve unknown key → empty slice, no error
- Restart persistence: register, close, reopen, Resolve still works

### Task A.2: Wire Correlation into CollisionWindow (F1)

**Bead:** sylveste-ykta
**Files:** `internal/bus/collision.go` (edit), `internal/bus/collision_test.go` (edit), `internal/bus/bus.go` (edit)

**Steps:**
1. Add `correlator` field to `CollisionWindow`:
   ```go
   type EntityResolver interface {
       Resolve(ctx context.Context, key string) ([]string, error)
   }
   ```
   `NewCollisionWindow(ttl, logger, resolver EntityResolver)` — resolver may be nil (no correlation, existing behavior preserved).
2. In `Check(e Event)`: before looking up pending events by EntityKey, call `resolver.Resolve(ctx, e.EntityKey)` to get correlated keys. Check pending map for ALL correlated keys (including the original). If any correlated key has a pending event from a different adapter → collision detected.
3. Update `bus.New()` and `daemon.New()` to pass the correlation store as the resolver.

**Test:**
- Two events with different EntityKeys but correlated → collision detected
- Two events with uncorrelated keys → no collision (existing behavior)
- Nil resolver → fallback to exact-match only (backward compatible)

### Task A.3: AncestorStore Versioning (F5)

**Bead:** sylveste-2l2x
**Files:** `internal/ancestor/store.go` (edit), `internal/ancestor/store_test.go` (edit)

**Steps:**
1. Alter schema — add `generation` column:
   ```sql
   CREATE TABLE IF NOT EXISTS ancestors (
       entity_id TEXT NOT NULL,
       generation INTEGER NOT NULL DEFAULT 1,
       content_hash TEXT NOT NULL,
       content BLOB NOT NULL,
       adapter_pair TEXT NOT NULL,
       updated_at TEXT NOT NULL,
       PRIMARY KEY (entity_id, generation)
   );
   ```
   **Migration** (P1 fix — SQLite cannot alter PRIMARY KEY, requires table recreation):
   - Check `PRAGMA user_version` — if 0 (old schema), run migration.
   - `CREATE TABLE ancestors_v2 (entity_id TEXT NOT NULL, generation INTEGER NOT NULL DEFAULT 1, content_hash TEXT NOT NULL, content BLOB NOT NULL, adapter_pair TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY (entity_id, generation))`
   - `INSERT INTO ancestors_v2 SELECT entity_id, 1, content_hash, content, adapter_pair, updated_at FROM ancestors`
   - `DROP TABLE ancestors`
   - `ALTER TABLE ancestors_v2 RENAME TO ancestors`
   - `PRAGMA user_version = 1`
   - Wrap in a single transaction. Idempotent: `user_version >= 1` skips migration.
2. `Put(ctx, entityID, a Ancestor) error` — compute next generation: `SELECT COALESCE(MAX(generation), 0) + 1 FROM ancestors WHERE entity_id = ?`, then INSERT.
3. `Get(ctx, entityID) (*Ancestor, error)` — `SELECT ... WHERE entity_id = ? ORDER BY generation DESC LIMIT 1`.
4. `GetGeneration(ctx, entityID, gen int) (*Ancestor, error)` — specific generation for debugging/audit.
5. `Prune(ctx, entityID string, keep int) error` — delete all but the latest `keep` generations. Default keep=3. Called after every `Put()`.
6. Add `Generation int` field to `Ancestor` struct.

**Test:**
- Put 5 times → Get returns generation 5
- Prune(keep=3) → only generations 3,4,5 remain
- GetGeneration(3) returns correct content
- Restart persistence: put, close, reopen, Get returns latest
- Migration: table without generation column → alter adds it, existing row gets generation=1

### Task A.4: First-Sync Bootstrap + ConflictRecord Ancestor Hash (F5)

**Bead:** sylveste-2l2x
**Files:** `internal/conflict/resolver.go` (edit), `internal/conflict/resolver_test.go` (edit), `internal/journal/journal.go` (edit), `internal/journal/schema.sql` (edit)

**Steps:**
1. Add `BootstrapAncestor` to `Resolver`:
   ```go
   func (r *Resolver) BootstrapAncestor(left, right []byte) (ancestor []byte, strategy string) {
       // If contents are identical, either side is the ancestor
       if hash(left) == hash(right) {
           return left, "bootstrap-identical"
       }
       // Default: treat right (GitHub) as synthetic ancestor
       return right, "bootstrap-github-authoritative"
   }
   ```
   Called by the bus dispatch path when `AncestorStore.Get()` returns `sql.ErrNoRows` and both sides have content. The caller MUST store the bootstrapped ancestor via `AncestorStore.Put()` before proceeding.
2. Add `ancestor_hash TEXT` column to `conflict_records` table:
   ```sql
   ALTER TABLE conflict_records ADD COLUMN ancestor_hash TEXT DEFAULT '';
   ```
   Migration: detect missing column via `PRAGMA table_info`, add if absent.
3. Update `ResolveConflict()` signature to accept `ancestorHash string`.
4. Update all callers of `ResolveConflict()` (daemon.go collision handler) to pass ancestor hash.

**Test:**
- BootstrapAncestor with identical content → returns content, "bootstrap-identical"
- BootstrapAncestor with different content → returns right, "bootstrap-github-authoritative"
- ConflictRecord with ancestor_hash persisted and queryable
- Migration: existing DB without ancestor_hash → column added, existing rows get empty string

---

## Phase B: Core File Sync (F2)

### Task B.1: GitHub Contents API Methods

**Bead:** sylveste-m6hb
**Files:** `internal/adapters/github/client.go` (edit), `internal/adapters/github/client_test.go` (new)

**Steps:**
1. Add `FileContent` type:
   ```go
   type FileContent struct {
       Path    string `json:"path"`
       SHA     string `json:"sha"`
       Content string `json:"content"` // base64-decoded
       Size    int    `json:"size"`
   }
   ```
2. Add `CommitterInfo` type:
   ```go
   type CommitterInfo struct {
       Name  string `json:"name"`
       Email string `json:"email"`
   }
   ```
3. Extend `API` interface:
   ```go
   GetContent(ctx, owner, repo, path, ref string) (*FileContent, error)
   CreateContent(ctx, owner, repo, path string, content []byte, message string, committer CommitterInfo) error
   UpdateContent(ctx, owner, repo, path string, content []byte, sha, message string, committer CommitterInfo) error
   DeleteContent(ctx, owner, repo, path, sha, message string, committer CommitterInfo) error
   GetTree(ctx, owner, repo, treeSHA string, recursive bool) (*TreeResponse, error)
   ```
4. Implement on `Client`. Key: `UpdateContent` sends `{"message":..., "content": base64(content), "sha": sha, "committer": {...}}` to `PUT /repos/{owner}/{repo}/contents/{path}`. On 409 response: return a typed `ErrSHAConflict{Path, StaleSHA}` error (NOT retry internally — let the caller handle re-fetch + merge).
5. `GetTree` for reconciliation: `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1`.
6. **Rate-limit budget tracking (P1 fix):** `Client.do()` reads `X-RateLimit-Remaining` from every response and stores it atomically (`atomic.Int32`). `RemainingBudget() int` returns the last-known value. Reconciler checks this before fetch loops.

**Test:**
- Mock HTTP server: GetContent returns content+SHA; CreateContent returns 201; UpdateContent with correct SHA returns 200; UpdateContent with stale SHA returns 409 → ErrSHAConflict; DeleteContent returns 200.

### Task B.2: Config Extensions

**Bead:** sylveste-m6hb
**Files:** `internal/config/config.go` (edit)

**Steps:**
1. Extend `GitHubConfig`:
   ```go
   SyncPaths      []string       `yaml:"sync_paths"`       // paths to sync, default empty
   SyncExtensions []string       `yaml:"sync_extensions"`   // default: [".md", ".txt", ".yaml"]
   Committer      CommitterConfig `yaml:"committer"`
   PollInterval   time.Duration  `yaml:"poll_interval"`     // default: 5m
   ```
2. `CommitterConfig`:
   ```go
   type CommitterConfig struct {
       Name  string `yaml:"name"`   // default: "interop-sync"
       Email string `yaml:"email"`  // default: "interop@noreply"
   }
   ```
3. Startup validation in daemon: if `github.Enabled && github.WebhookSecret == ""`, return startup error. If `github.SyncPaths` is non-empty but `github.Token == ""`, return startup error.
4. **Fail-closed:** `config.Load()` already returns error on YAML unmarshal failure (line 73-77). Verify this is preserved. Add: if `SyncExtensions` is empty and `SyncPaths` is non-empty, default to `[".md", ".txt", ".yaml"]`.

**Test:** Config validation tests for empty webhook secret, empty token with sync paths, extension defaults.

### Task B.3: File Sync Module

**Bead:** sylveste-m6hb
**Files:** `internal/adapters/github/filesync.go`, `internal/adapters/github/filesync_test.go`

**Steps:**
1. `FileSync` struct — owned by the GitHub adapter, not a separate adapter:
   ```go
   type FileSync struct {
       api          API
       correlator   correlation.Store
       ancestors    *ancestor.Store
       resolver     *conflict.Resolver
       syncPaths    []string
       extensions   []string
       committer    CommitterInfo
       owner, repo  string
       logger       *slog.Logger
   }
   ```
2. `NewFileSync(...)` constructor.
3. `HandleFileEvent(ctx, e adapter.Event) error` — called by the GitHub adapter's `HandleEvent` when event has `github:file:*` EntityKey or correlated `fs:file:*` key:
   - **Create:** `api.CreateContent(...)` with configured committer. Register entity correlation.
   - **Update:** `api.GetContent(...)` for current SHA, then `api.UpdateContent(...)`. On `ErrSHAConflict`: re-fetch current content, call `resolver.ResolveThreeWay(ancestor, local, remote)`, retry UpdateContent with new SHA + merged content. If merge fails → dead-letter to SyncJournal.
   - **Delete:** `api.GetContent(...)` for current SHA, then `api.DeleteContent(...)`.
4. `ShouldSync(path string) bool` — check path against `syncPaths` prefixes AND `extensions` allow-list. Path must match both.
5. `EntityKeyForPath(owner, repo, path string) string` — returns `github:file:<owner>/<repo>:<path>` with NFC normalization.
6. Self-originated event suppression: check `e.SourceAdapter == adapter.AdapterGitHub` before processing outbound. The bus already skips source adapter, but filesync operates within the same adapter — check `e.RoutingHints["origin"] != "filesync"` or similar tag.

**Test:**
- HandleFileEvent Create → CreateContent called with correct args
- HandleFileEvent Update → GetContent + UpdateContent called
- HandleFileEvent Update with 409 → re-fetch + three-way merge + retry
- HandleFileEvent Update with unresolvable conflict → dead-lettered
- ShouldSync: "docs/readme.md" with sync_paths=["docs/"] → true
- ShouldSync: ".env" → false (not in extensions)
- ShouldSync: "src/main.go" with sync_paths=["docs/"] → false
- Entity correlation auto-registered on first sync

### Task B.4: Wire FileSync into GitHub Adapter

**Bead:** sylveste-m6hb
**Files:** `internal/adapters/github/adapter.go` (edit), `internal/daemon/daemon.go` (edit)

**Steps:**
1. Add `fileSync *FileSync` field to GitHub `Adapter`.
2. In `New()`: create FileSync if `cfg.SyncPaths` is non-empty.
3. In `HandleEvent()`: if event has `github:file:*` or correlated `fs:file:*` EntityKey, delegate to `fileSync.HandleFileEvent()`. Otherwise, fall through to existing issue/PR handling.
4. In daemon: pass correlation store and ancestor store to GitHub adapter constructor. Add `correlator` field to `Daemon` struct. Add `correlator.Close()` to shutdown sequence after ancestor store close (step 10 → 10a: close ancestor, 10b: close correlation).

**Test:** Integration: emit `fs:file:docs/test.md` ContentPayload → GitHub adapter's HandleEvent delegates to FileSync → CreateContent called.

---

## Phase C: Detection Channels (F3 + F4, parallel)

### Task C.1: Push Webhook Handler (F3)

**Bead:** sylveste-jd6m
**Files:** `internal/adapters/github/adapter.go` (edit), `internal/adapters/github/adapter_test.go` (edit)

**Steps:**
1. Add `push` payload types:
   ```go
   type pushPayload struct {
       Ref     string       `json:"ref"`
       Commits []commitData `json:"commits"`
       Pusher  pusherData   `json:"pusher"`
   }
   type commitData struct {
       Added    []string `json:"added"`
       Modified []string `json:"modified"`
       Removed  []string `json:"removed"`
       Author   struct {
           Name string `json:"name"`
       } `json:"author"`
   }
   type pusherData struct {
       Name string `json:"name"`
   }
   ```
2. **P2 fix: raw JSON for push parsing.** Extend the webhook handler to pass raw body bytes alongside parsed payload. In `WebhookHandler()`, after unmarshal to `webhookPayload`, also store `rawBody` for event-specific re-parsing. Add `"push"` case to `processWebhookEvent()` that re-unmarshals `rawBody` to `pushPayload`:
   ```go
   case "push":
       a.processPushEvent(rawBody)
   ```
3. `processPushEvent(rawBody []byte)` — unmarshal to `pushPayload`:
   - Parse push-specific fields from raw JSON (need to unmarshal to `pushPayload`).
   - **Self-originated suppression:** if `pusher.Name` matches configured committer name (`interop-sync`), return immediately — no events.
   - Collect all file paths from all commits (added + modified + removed), deduplicate.
   - Filter through `fileSync.ShouldSync(path)`.
   - For each synced path: enqueue a lightweight event to `a.ch` with `github:file:<owner>/<repo>:<path>` EntityKey. **Do NOT fetch content here** — the push handler must return within 100ms. Content fetch happens when the event is processed by HandleEvent.
   - Event payload: `GenericPayload{Data: map[string]any{"paths": filteredPaths, "action": "push"}}` for batch, or individual events per path.
4. **Non-blocking contract:** The push handler ONLY writes to `a.ch`. No API calls, no disk I/O.

**Test:**
- Push with 3 modified files in sync_paths → 3 events emitted
- Push with files outside sync_paths → 0 events
- Push from `interop-sync` committer → 0 events (self-suppression)
- Push handler returns within 100ms (timed test)
- Push with added + removed → EntityCreated + EntityDeleted events

### Task C.2: Push Content Fetch (F3)

**Bead:** sylveste-jd6m
**Files:** `internal/adapters/github/filesync.go` (edit)

**Steps:**
1. When FileSync receives a `github:file:*` event from a push (detected via payload or routing hint), it fetches content via `api.GetContent()`.
2. For `EntityCreated`/`EntityUpdated`: fetch content, compute hash, emit to bus as `ContentPayload` (so other adapters — filesystem — can apply the change).
3. For `EntityDeleted`: emit deletion event (no content fetch needed).
4. Register entity correlation on first encounter of each path.
5. Update AncestorStore after successful sync.

**Test:**
- Push event with modified file → GetContent called → ContentPayload emitted → AncestorStore updated

### Task C.3: Tree-SHA Reconciliation Poll (F4)

**Bead:** sylveste-irlf
**Files:** `internal/adapters/github/reconcile.go`, `internal/adapters/github/reconcile_test.go`

**Steps:**
1. `Reconciler` struct:
   ```go
   type Reconciler struct {
       api         API
       ancestors   *ancestor.Store
       correlator  *correlation.Store
       syncPaths   []string
       extensions  []string
       owner, repo string
       pollInterval time.Duration
       lastTreeSHAs map[string]string // sync_path -> tree SHA
       lastCommitSHA string
       lastWebhookAt time.Time
       logger      *slog.Logger
       ch          chan<- adapter.Event // shared with adapter
   }
   ```
2. `Start(ctx)` — launches poll goroutine. On each tick:
   a. **Rate-limit budget check (P1 fix):** Call `api.RemainingBudget()`. If remaining < 200 (out of 5000/hour), defer content-fetch to next tick, log warning: "rate limit low ({remaining}/5000), deferring reconciliation." Only the tree-SHA comparison runs (1 API call per sync_path); content fetches are batched to max 10 per tick.
   b. For each `sync_paths` entry: fetch subtree via `api.GetTree(owner, repo, "HEAD:"+syncPath, true)`. Compare tree SHA with stored value. If changed, identify modified files.
   c. For each changed file (capped at 10 per tick): fetch content via `api.GetContent()`. Compare hash with AncestorStore. If different → emit `entity.reconcile` event. Remaining files deferred to next tick.
   c. **Ancestor validation:** For each file in AncestorStore that has a correlation, verify stored hash matches current content on both sides. If mismatch detected (out-of-band `git pull` or direct GitHub edit), re-bootstrap ancestor.
   d. Update `lastTreeSHAs` and `lastCommitSHA`.
3. **Webhook liveness:** Track `lastWebhookAt` (updated by adapter on each webhook receipt). If `time.Since(lastWebhookAt) > 2 * pollInterval`, log warning: "No webhooks received in {duration} — possible endpoint misconfiguration or network issue."
4. `Stop()` — cancel context.

**Test:**
- Tree SHA unchanged → no events
- Tree SHA changed, file in sync_paths modified → reconcile event emitted
- Tree SHA changed, file outside sync_paths → no events
- Stale ancestor detected → re-bootstrapped from current content
- Webhook liveness: no webhook for 2x poll interval → warning logged
- Reconciler Stop → goroutine exits cleanly

---

## Config Changes Summary

`GitHubConfig` final shape:
```go
type GitHubConfig struct {
    Enabled        bool            `yaml:"enabled"`
    WebhookSecret  string          `yaml:"webhook_secret"`
    AppID          int64           `yaml:"app_id"`
    PrivateKey     string          `yaml:"private_key_path"`
    Token          string          `yaml:"token"`
    Owner          string          `yaml:"owner"`
    Repo           string          `yaml:"repo"`
    SyncPaths      []string        `yaml:"sync_paths"`
    SyncExtensions []string        `yaml:"sync_extensions"`
    Committer      CommitterConfig `yaml:"committer"`
    PollInterval   time.Duration   `yaml:"poll_interval"`
}
```

## New Files

```
internal/correlation/store.go          # F1: Entity correlation SQLite store
internal/correlation/store_test.go     # F1: Tests
internal/adapters/github/filesync.go   # F2: File sync module
internal/adapters/github/filesync_test.go
internal/adapters/github/client_test.go # B.1: Contents API tests
internal/adapters/github/reconcile.go  # F4: Tree-SHA reconciler
internal/adapters/github/reconcile_test.go
```

## Modified Files

```
internal/bus/collision.go              # A.2: EntityResolver interface + correlation lookup
internal/bus/collision_test.go
internal/bus/bus.go                    # A.2: Pass resolver to CollisionWindow
internal/ancestor/store.go            # A.3: Generation column + versioned Put/Get/Prune
internal/ancestor/store_test.go
internal/conflict/resolver.go          # A.4: BootstrapAncestor
internal/conflict/resolver_test.go
internal/journal/journal.go            # A.4: ancestor_hash column on ConflictRecord
internal/adapters/github/client.go     # B.1: Contents API + GetTree methods
internal/adapters/github/adapter.go    # B.4 + C.1: FileSync wiring + push handler
internal/adapters/github/adapter_test.go # C.1: Push webhook tests
internal/config/config.go              # B.2: SyncPaths, extensions, committer, poll
internal/daemon/daemon.go              # B.4: Pass correlation + ancestor to GitHub adapter
```

## Risk Mitigations from Flux-Review

| P0/P1 Finding | Addressed In |
|---------------|--------------|
| EntityKey namespace mismatch → ping-pong | Task A.1 + A.2 (correlation table + CollisionWindow) |
| AncestorStore destructive upsert | Task A.3 (generation counter) |
| Null-ancestor first-sync dead-letters | Task A.4 (BootstrapAncestor) |
| Contents API SHA race / 409 | Task B.1 (ErrSHAConflict) + B.3 (re-fetch+merge) |
| Webhook handler must not block | Task C.1 (enqueue-only contract, 100ms test) |
| Out-of-band ancestor corruption | Task C.3 (ancestor validation in reconciler) |
| Webhook liveness gap | Task C.3 (lastWebhookAt tracking) |
| Unicode path normalization | Task A.1 (NormalizePath in correlation store) |
| ConflictRecord missing ancestor | Task A.4 (ancestor_hash column) |
