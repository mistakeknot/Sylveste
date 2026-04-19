---
artifact_type: prd
bead: sylveste-911m
stage: design
---

# PRD: GitHub Bidirectional File Sync

## Problem

interop's sync fabric connects beads, Notion, and local files — but GitHub repository files are read-only. Changes to project docs on GitHub don't propagate locally, and local doc edits require manual git push. This gap means the canonical versioned copies (GitHub) and working copies (local) drift silently.

## Solution

Extend the existing GitHub adapter (Phase 3: Issues/PRs) with bidirectional file sync. Local file edits propagate to GitHub within 120s via the Git Contents API, and GitHub file changes (push events) propagate locally within 120s. Three-way merge via AncestorStore handles concurrent edits. An entity correlation table bridges the `fs:file:*` and `github:file:*` EntityKey namespaces so the CollisionWindow can detect cross-adapter conflicts.

## Features

### F1: Entity Correlation Table

**What:** SQLite-backed table mapping correlated EntityKeys across adapter namespaces, enabling CollisionWindow to detect cross-adapter conflicts on the same logical entity.

**Acceptance criteria:**
- [ ] `entity_correlations` table in SQLite with `(source_key TEXT, target_key TEXT, adapter_pair TEXT)` and bidirectional index
- [ ] `Register(sourceKey, targetKey, adapterPair)` and `Resolve(key) []string` methods
- [ ] Path-based auto-registration: when filesync processes a file, it auto-registers `fs:file:<path>` ↔ `github:file:<owner>/<repo>:<path>`
- [ ] CollisionWindow.Check() consults correlation table before comparing EntityKeys
- [ ] Unicode path normalization (NFC) applied at registration time via `normalizePath()` function
- [ ] Test: two events with correlated keys detected as collision; uncorrelated keys pass through

### F2: GitHub Contents API + File Sync Module

**What:** Git Contents API methods on the GitHub client and a `filesync.go` module that handles bidirectional file events with optimistic concurrency.

**Acceptance criteria:**
- [ ] `GetContent(owner, repo, path, ref) (FileContent, error)` — returns content + SHA
- [ ] `CreateContent(owner, repo, path, content, message, committer) error`
- [ ] `UpdateContent(owner, repo, path, content, sha, message, committer) error` — 409 retry: re-fetch SHA + three-way merge + retry (separate from rate-limit retry)
- [ ] `DeleteContent(owner, repo, path, sha, message, committer) error`
- [ ] Configurable `sync_paths` in `GitHubConfig` — default empty (nothing synced until configured), fail-closed on parse error
- [ ] Extension allow-list for synced files (default: `.md`, `.txt`, `.yaml`) — binary files excluded
- [ ] Default committer identity: `interop-sync <interop@noreply>` (configurable)
- [ ] HandleEvent for `EntityCreated`/`EntityUpdated`/`EntityDeleted` with `github:file:*` EntityKey targets
- [ ] Local file edit → GitHub file updated within 120s
- [ ] Test: incoming ContentPayload event → correct Contents API call; 409 → re-fetch + merge + retry

### F3: Push Webhook Handler

**What:** Handle GitHub `push` webhook events to detect file changes in real-time.

**Acceptance criteria:**
- [ ] `processPushEvent(payload)` added to GitHub adapter webhook handler
- [ ] Parse push payload: extract modified/added/removed file paths from commits
- [ ] Filter to configured `sync_paths` and extension allow-list
- [ ] Fetch content via Contents API for modified/added files
- [ ] Emit `EntityCreated`/`EntityUpdated`/`EntityDeleted` events with `github:file:<owner>/<repo>:<path>` EntityKey
- [ ] Auto-register entity correlation on first sync of each file path
- [ ] Non-blocking: push handler enqueues to channel, returns within 100ms — never blocks on Contents API
- [ ] Suppress self-originated events: ignore pushes from `interop-sync` committer
- [ ] Test: push webhook → correct events emitted; self-originated push → no events; handler returns within 100ms

### F4: Tree-SHA Reconciliation Poll

**What:** Periodic per-subtree comparison that catches missed webhooks, force-pushes, and out-of-band changes.

**Acceptance criteria:**
- [ ] Poll interval configurable (default 5 minutes)
- [ ] Per-subtree tree SHA stored (one per `sync_paths` entry, not repo root)
- [ ] On tree-SHA change: walk changed files, compare with AncestorStore hashes
- [ ] Emit `entity.reconcile` events for detected drift
- [ ] Validate AncestorStore records: if stored hash doesn't match either side's actual content, re-bootstrap ancestor from current state (fixes out-of-band `git pull` corruption)
- [ ] Last-seen commit SHA stored for commit-walk reconciliation (not just tree-SHA point-in-time comparison)
- [ ] Webhook liveness tracking: `lastWebhookReceived` timestamp, warn if >2x poll interval with no webhook
- [ ] Test: tree-SHA change on synced subtree → reconcile events; change on unsynced subtree → no events; stale ancestor detected → re-bootstrapped

### F5: AncestorStore Versioning + First-Sync Bootstrap

**What:** Version ancestor records to prevent destructive overwrites, and bootstrap ancestors for pre-existing files.

**Acceptance criteria:**
- [ ] Add `generation INTEGER DEFAULT 1` column to `ancestors` table
- [ ] `Put()` inserts new row with incremented generation (append, not upsert)
- [ ] `Get()` returns highest-generation record
- [ ] `Prune()` retains last 3 generations per entity, deletes older
- [ ] First-sync bootstrap: when `Get()` returns `sql.ErrNoRows` for a file present on both sides, treat the GitHub version (by commit date) as synthetic ancestor rather than dead-lettering as `ErrUnresolvable`
- [ ] `ConflictRecord` extended with `ancestor_hash TEXT` column for post-hoc re-evaluation
- [ ] Test: Put 5 generations → Get returns latest; Prune keeps 3; first-sync of pre-existing file → no false conflict

## Non-goals

- **Full Git Data API (trees/blobs/commits):** Contents API (one commit per file) is sufficient for sync volume. Batched tree commits are a future optimization if commit pollution becomes a problem.
- **Branch targeting beyond default branch:** Phase 4 syncs against the repo's default branch only. PR file sync is future scope.
- **Binary file sync:** Only text files matching the extension allow-list are synced.
- **Conflict resolution UX:** Conflicts are logged to SyncJournal. Interactive resolution via MCP tools is Phase 5 scope.
- **Rename detection:** Path-based correlation treats rename as delete + create. Paired rename detection is a future refinement.

## Dependencies

- Phase 1 core (event bus, CollisionWindow, SyncJournal, AncestorStore) — complete
- Phase 2 beads + filesystem adapters — complete
- Phase 3 GitHub adapter (Issues/PRs) — complete
- Phase 3 Notion adapter — complete

## Open Questions

1. **Rate limit budget partitioning:** Should the GitHub client reserve a portion of rate limit budget for read operations (poll, reconciliation) separate from write operations (sync)? The brainstorm review flagged this as P2. Recommendation: defer to implementation — monitor rate limit headers and log when writes consume >80% of hourly budget.

2. **Commit message format:** The default `sync: update <path>` avoids leaking local path structure on public repos. Should the commit message include the source adapter or event ID for traceability? Recommendation: configurable template with `{path}` and `{source}` placeholders.
