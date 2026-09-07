---
artifact_type: findings
source_brainstorm: docs/brainstorms/2026-04-13-github-file-sync-brainstorm.md
bead: sylveste-911m
generated_at: '2026-04-13'
agents_run:
  project_agents:
    - fd-git-api-concurrency
    - fd-webhook-delivery-reliability
    - fd-three-way-merge-correctness
    - fd-filesync-reconciliation-coverage
    - fd-sync-scope-safety
---

# Flux-Drive Findings: GitHub Repo File Sync Brainstorm
## `interverse/interop/internal/adapters/github/filesync.go` -- Phase 4 (sylveste-911m)

---

## Triage Summary

All five agents triaged as **high-priority Project Agents** with triage bonus (domain-expert knowledge directly applicable to the file sync implementation).

| Agent | Domain | Lens |
|---|---|---|
| fd-git-api-concurrency | Git Contents API optimistic locking | SHA-based concurrency, retry semantics, race windows |
| fd-webhook-delivery-reliability | GitHub webhook delivery guarantees | Push event gaps, webhook replay, reconciliation timing |
| fd-three-way-merge-correctness | Three-way merge on text content | AncestorStore keying, merge base staleness, binary exclusion |
| fd-filesync-reconciliation-coverage | Tree-SHA polling reconciliation | Force-push detection, rename tracking, partial sync coverage |
| fd-sync-scope-safety | Sync scope configuration safety | Path glob escape, default-deny enforcement, sensitive file gates |

---

## Severity Summary

| Severity | Count |
|---|---|
| P0 | 3 |
| P1 | 5 |
| P2 | 4 |
| P3 | 2 |
| **Total** | **14** |

---

## P0 Findings

### P0-1 -- Contents API SHA race: read-modify-write window allows silent overwrites on concurrent edits
**Agent:** fd-git-api-concurrency
**Files:** `internal/adapters/github/filesync.go` (planned), `internal/adapters/github/client.go`
**Trigger:** Two file sync operations targeting the same GitHub file within the Contents API's read-modify-write window

The brainstorm specifies "Git Contents API for file CRUD" with "optimistic concurrency (SHA-based)." The Contents API's PUT endpoint requires the current file SHA as a parameter -- if the SHA does not match the file's current state, the API returns 409 Conflict. However, the brainstorm does not specify retry-with-rebase behavior on 409. The existing `client.go` retry logic (line 69-114) only handles rate limiting (429/403). A 409 from the Contents API is treated as a non-retryable error and propagated as `ErrTransient`, which the bus will retry -- but the retry will re-read the stale SHA from the same adapter state, hitting 409 again in an infinite loop until max retries (3) exhausts.

**Failure scenario:** A local file edit triggers a sync to GitHub. Simultaneously, a developer pushes directly to the same file on GitHub. The filesync module reads the file's current SHA (abc123), prepares its PUT request. The developer's push lands, changing the SHA to (def456). The PUT request sends SHA abc123, GitHub returns 409. The bus retries 3 times, each with the same stale SHA, all fail. The event dead-letters. Meanwhile, the developer's push triggers a `push` webhook back to interop, which reads the new file and overwrites the local copy -- but the local edit is now lost because the outbound sync was abandoned. No conflict is recorded because the collision window sees events from different entity keys (`fs:file:` vs `github:file:`).

**Smallest fix:** On 409 from the Contents API, re-fetch the file's current content and SHA, perform a three-way merge (local change, remote current, ancestor), and retry the PUT with the new SHA. This is the Git equivalent of "pull-rebase-push." The `API` interface needs a new `GetFileContent(ctx, owner, repo, path, ref) (*FileContent, error)` method that returns both content and SHA. The retry loop for 409 must be separate from rate-limit retry and capped at 2 attempts (read-merge-write, then fail to journal).

---

### P0-2 -- EntityKey namespace mismatch between filesystem and GitHub file adapters breaks collision detection
**Agent:** fd-three-way-merge-correctness
**Files:** `internal/adapters/github/filesync.go` (planned), `internal/adapters/filesystem/adapter.go` (line 279), `internal/bus/collision.go` (line 49)
**Trigger:** Any bidirectional file sync operation

The brainstorm states: "`fs:file:docs/README.md` maps to `github:file:owner/repo:docs/README.md` by convention." The plan (Task 1.2) defines two distinct EntityKey formats: `fs:file:<relative-path>` for filesystem and `github:file:<owner>/<repo>:<path>` for GitHub files. The CollisionWindow (collision.go line 49) keys on `EntityKey` to detect opposing events. If the filesystem adapter emits `EntityKey: "fs:file:docs/README.md"` and the GitHub filesync module emits `EntityKey: "github:file:mistakeknot/interop:docs/README.md"`, these are different strings. The collision window will never match them -- both events pass through independently and dispatch to the other adapter, creating a ping-pong loop.

The plan mentions an `entity_correlation` table (Task 1.2 cross-system correlation) that "maps (source_key, target_key) pairs." But this table does not exist in the current codebase (no `entity_correlation` in `internal/identity/`), and `CollisionWindow.Check()` does not consult any correlation table -- it compares raw `EntityKey` strings.

**Failure scenario:** User edits `docs/README.md` locally. Filesystem adapter emits `fs:file:docs/README.md`. Bus dispatches to GitHub adapter, which pushes the file to GitHub. GitHub sends a `push` webhook. GitHub filesync emits `github:file:owner/repo:docs/README.md`. Bus dispatches to filesystem adapter, which overwrites the local file (identical content, but triggers fsnotify). Filesystem adapter emits again. Infinite loop. The collision window never fires because the EntityKeys never match.

**Smallest fix:** Two options, both required:
1. Implement the entity_correlation table in `internal/identity/` and wire `CollisionWindow.Check()` to resolve correlated EntityKeys to a canonical key before comparison.
2. As a defense-in-depth layer, add content-hash deduplication to the dispatch path: if the content hash of the incoming event matches the content hash of the most recent outbound event for the same logical entity, suppress the dispatch. This catches the ping-pong case even without correlation.

---

### P0-3 -- Push webhook does not carry per-file content -- filesync must make N+1 API calls per push event
**Agent:** fd-webhook-delivery-reliability
**Files:** `internal/adapters/github/adapter.go` (line 22-28, webhookPayload struct), `internal/adapters/github/filesync.go` (planned)
**Trigger:** Any push event with modified files in sync scope

The brainstorm states "Push webhook for real-time detection." The current `webhookPayload` struct (adapter.go line 22-28) does not include push event fields. GitHub's `push` webhook payload contains `commits[].added[]`, `commits[].modified[]`, `commits[].removed[]` as path lists, but does NOT include file content. For each modified/added file path, the filesync module must make a separate Contents API call to fetch the file content. For a push with 10 modified files in sync scope, this is 10 sequential API calls (or 10 concurrent calls, each consuming a rate limit point).

This interacts with GitHub's rate limit: the REST API allows 5,000 requests/hour for authenticated apps. A CI pipeline that auto-commits documentation updates could generate 20+ pushes/hour with 5-10 files each, consuming 100-200 API calls/hour just for content fetching. Combined with issue/PR operations, this can exhaust the rate limit.

The brainstorm acknowledges "Contents API creates one commit per file change" for outbound writes but does not address the inbound N+1 read amplification.

**Smallest fix:** For inbound push events with >3 modified files in sync scope, switch from the Contents API to the Git Trees API: fetch the tree SHA from the push event's `after` commit, call `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=1`, then fetch only the blobs for paths matching `sync_paths`. This reduces N calls to 1 tree fetch + N blob fetches, and the tree fetch provides the complete file listing for reconciliation. For pushes with <=3 files, the Contents API is fine. Add rate-limit budget tracking to the GitHub client: if remaining < 500, defer non-critical content fetches to the next poll cycle.

---

## P1 Findings

### P1-1 -- AncestorStore keyed by EntityID, but file sync has two EntityIDs per logical entity
**Agent:** fd-three-way-merge-correctness
**Files:** `internal/ancestor/store.go` (line 65-77), `internal/conflict/resolver.go` (line 85-110)
**Trigger:** Three-way merge on any file entity

The AncestorStore (store.go) is keyed by `entity_id` as a single TEXT PRIMARY KEY. For file sync, the same logical file has two EntityIDs: `docs/README.md` (from filesystem adapter, which uses relative path as EntityID) and `owner/repo:docs/README.md` (from GitHub filesync). `ResolveThreeWay` receives `base, left, right` byte slices but the caller must fetch the ancestor by `entityID`. If the filesystem adapter stores the ancestor under `docs/README.md` and the GitHub filesync looks it up under `owner/repo:docs/README.md`, it gets `sql.ErrNoRows` -- the merge falls back to no-ancestor behavior, which means any divergent edit is immediately an `ErrUnresolvable` conflict instead of an auto-mergeable three-way diff.

**Smallest fix:** Establish a canonical entity ID for cross-adapter entities. When the entity correlation is established (first successful sync), both adapters must agree on a single canonical ID for ancestor storage. The simplest approach: use the filesystem-relative path as the canonical ID for file entities (it is the shorter, system-independent form). The correlation table maps `github:file:owner/repo:docs/README.md` to canonical ID `docs/README.md`.

---

### P1-2 -- Tree-SHA poll interval (5 minutes) creates a 5-minute blind window after missed webhooks
**Agent:** fd-webhook-delivery-reliability
**Files:** `internal/adapters/github/filesync.go` (planned)
**Trigger:** Webhook delivery failure (GitHub outage, network blip, daemon restart)

The brainstorm specifies "periodic tree-SHA polling provides reconciliation (catches force-pushes, missed webhooks, network blips)" with a 5-minute interval. GitHub's webhook delivery has a documented 99.9% success rate, which means roughly 1 in 1,000 deliveries fails. For a moderately active repo with 50 pushes/day, that is approximately one missed webhook every 20 days. When it happens, the sync is stale for up to 5 minutes.

More critically, GitHub retries failed webhook deliveries with exponential backoff (10s, 30s, 60s), but only for HTTP 5xx responses or timeouts. If the interop daemon returns 200 (accepted) but the internal processing fails (e.g., entity channel full, adapter.go line 366), the webhook is considered delivered and GitHub will not retry. The 5-minute poll is the only recovery path for this scenario.

**Smallest fix:** Reduce the default poll interval to 60 seconds (tree-SHA comparison is a single API call, costs 1 rate limit point per poll). Add a "last webhook received" timestamp; if no webhook has been received for >2 minutes, temporarily reduce poll interval to 30 seconds (adaptive polling). Log a warning at INFO level when poll detects drift that should have been caught by a webhook.

---

### P1-3 -- File rename on GitHub appears as delete + create, losing sync history and ancestor state
**Agent:** fd-filesync-reconciliation-coverage
**Files:** `internal/ancestor/store.go`, `internal/adapters/github/filesync.go` (planned)
**Trigger:** User renames a synced file on GitHub (via web UI or git mv + push)

GitHub's `push` webhook reports renamed files as `commits[].removed[]` + `commits[].added[]` for the old and new paths respectively. The Contents API has no rename operation. When filesync processes this, it will: (1) emit `EntityDeleted` for the old path, deleting the local file and the AncestorStore entry for that path, (2) emit `EntityCreated` for the new path, creating the file locally with no ancestor history. The ancestor chain is broken -- the next edit to the renamed file will have no merge base, causing every divergent edit to be flagged as `ErrUnresolvable` instead of mergeable.

**Smallest fix:** When processing a push event, check if a `removed` path and an `added` path in the same commit share identical blob SHAs (git tracks renames via blob identity). If so, treat it as a rename: update the AncestorStore key from old path to new path (DELETE + INSERT), rename the local file (os.Rename), and emit `EntityUpdated` instead of delete+create. This preserves the ancestor chain across renames.

---

### P1-4 -- No content-type gate on sync scope -- YAML/JSON files treated as text but may contain secrets
**Agent:** fd-sync-scope-safety
**Files:** `internal/config/config.go` (line 52-56, FilesystemConfig), `internal/adapters/github/filesync.go` (planned)
**Trigger:** User configures `sync_paths: ["docs/", "config/"]`

The brainstorm states "sync against default branch only" and "configurable sync scope" with `sync_paths`. It recommends "only sync text files matching configured extensions (.md, .txt, .yaml)." However, the config struct (`FilesystemConfig`) has `WatchPaths` and `Exclude` but no `AllowedExtensions` field. If the filesync module inherits the same config pattern, a user who configures `sync_paths: ["config/"]` would sync ALL files in that directory, including `.env`, `credentials.json`, or `secrets.yaml`. The brainstorm's recommendation for extension filtering is in "Open Questions" section (item 3 about binary files) but is not a hard design constraint.

**Smallest fix:** Add `allowed_extensions` to the GitHub filesync config (default: `[".md", ".txt"]`). Add `blocked_patterns` with hardcoded, non-overridable entries: `["*.env", "*.key", "*.pem", "*.p12", "*credentials*", "*secret*"]`. The hardcoded blocklist is defense-in-depth -- even if the user configures broad sync_paths, these patterns are always excluded. Log a warning at startup if `allowed_extensions` is empty (meaning all extensions allowed).

---

### P1-5 -- Brainstorm specifies 120s sync latency but no mechanism to measure or enforce it
**Agent:** fd-filesync-reconciliation-coverage
**Files:** `internal/adapters/github/filesync.go` (planned), `internal/journal/journal.go`
**Trigger:** SLA monitoring for production sync fabric

The brainstorm states sync should complete "within 120s" and the plan (Task 4.1) repeats this as an explicit acceptance criterion: "local file edit -> GitHub repo file updated within 120s." However, neither the brainstorm nor the existing code provides any mechanism to measure end-to-end sync latency. The SyncJournal records `started_at` and `completed_at` for operations, but does not record the original event timestamp from the source adapter. The event `Timestamp` field is overwritten to interop receive-time by the bus (bus.go line 200), so the actual file modification time is lost.

**Smallest fix:** Add `SourceTimestamp time.Time` to `adapter.Event` (separate from the bus-stamped `Timestamp`). The filesystem adapter sets this to the file's `ModTime()`. The GitHub filesync sets this to the commit timestamp from the push webhook payload. The SyncJournal records both timestamps. A health endpoint (`/metrics/sync-latency`) computes p50/p95/p99 of `completed_at - source_timestamp` over a sliding 1-hour window. Alert if p95 exceeds 120s.

---

## P2 Findings

### P2-1 -- One commit per file change creates noisy git history on the target repo
**Agent:** fd-git-api-concurrency
**Files:** `internal/adapters/github/filesync.go` (planned)

The brainstorm acknowledges "Contents API creates one commit per file change. Acceptable for sync volume." For low-volume sync (a few files/day), this is fine. For batch operations (e.g., a tool that updates 20 docs files at once), this creates 20 commits in rapid succession. Each commit triggers a push webhook back to interop (20 webhook deliveries), each of which must be recognized as "self-originated" and suppressed.

**Suggested improvement:** Batch file changes that arrive within a 5-second window into a single commit using the Git Data API (create tree, create commit, update ref). This reduces commit noise and webhook amplification. The Contents API remains the fallback for single-file operations.

---

### P2-2 -- No self-originated event suppression mechanism described
**Agent:** fd-webhook-delivery-reliability
**Files:** `internal/adapters/github/adapter.go`, `internal/adapters/github/dedup.go`

When filesync pushes a file to GitHub, GitHub sends a `push` webhook back to the same interop instance. The brainstorm does not describe how to suppress these self-originated events. The existing `DeliveryStore` deduplicates by `X-GitHub-Delivery` header (unique per delivery), not by content or originator. Without suppression, every outbound sync triggers an inbound event that either ping-pongs (P0-2) or wastes processing.

**Suggested improvement:** Before pushing a file to GitHub, record the expected commit SHA (or a nonce embedded in the commit message, e.g., `[interop-sync:<nonce>]`) in a short-lived suppression cache. When a push webhook arrives, check if the commit message contains the nonce or if the committer matches the bot identity. If so, skip processing. The suppression cache has a 60-second TTL (covers webhook delivery latency).

---

### P2-3 -- Force-push to default branch replaces entire tree -- poll must handle non-fast-forward history
**Agent:** fd-filesync-reconciliation-coverage
**Files:** `internal/adapters/github/filesync.go` (planned)

The brainstorm mentions "catches force-pushes" in the poll reconciliation. A force-push replaces the branch tip, meaning the `before` commit in the push webhook may not be an ancestor of `after`. Tree-SHA comparison (current vs. last-known) will detect the change, but the reconciliation logic must handle the case where previously-synced files are deleted, modified, or restored to earlier versions in a single operation. The existing `EntityDeleted`/`EntityCreated`/`EntityUpdated` event model handles this, but the reconciliation diff must compare the full tree, not just the delta from the push event's commit list (which may be empty or misleading for force-pushes).

**Suggested improvement:** On poll, always compare the full tree-SHA. If it differs from the last-known tree-SHA, fetch both trees and compute a path-level diff (added/modified/removed). Do not rely on the push webhook's `commits[]` list for force-push events -- it may be empty or reference commits that are no longer reachable.

---

### P2-4 -- Filesystem adapter exclude patterns match only basename, not full path
**Agent:** fd-sync-scope-safety
**Files:** `internal/adapters/filesystem/adapter.go` (line 293-315)

The existing filesystem adapter's `isExcluded` method (line 308-311) matches configurable exclude patterns against `filepath.Base(path)` only. This means a pattern like `*.yaml` excludes all YAML files everywhere, but a pattern like `config/*.yaml` is silently ignored because `filepath.Match("config/*.yaml", "secrets.yaml")` returns false. Users expecting directory-scoped exclusions will get no exclusion at all. When filesync inherits these exclude patterns, the gap becomes a security issue (see P1-4).

**Suggested improvement:** Match exclude patterns against both `filepath.Base(path)` and the full relative path. Use `filepath.Match(pattern, relPath)` as a second check. Document that patterns without `/` match basename only (glob-style), patterns with `/` match relative path (path-style).

---

## P3 Findings

### P3-1 -- Commit attribution default "interop-sync" is not a valid GitHub verified committer
**Agent:** fd-git-api-concurrency

The brainstorm recommends `interop-sync <interop@noreply>` as the default committer. The Contents API uses the authenticated token's identity for commits, not a custom committer field. If using a GitHub App token, the committer will be `<app-name>[bot]`. If using a PAT, it will be the PAT owner. The brainstorm's recommendation for a custom committer name only works with the Git Data API (create-commit endpoint accepts `committer` object). This is a documentation/design inconsistency, not a bug.

---

### P3-2 -- Branch targeting "default branch only" may diverge from repo's actual default if renamed
**Agent:** fd-webhook-delivery-reliability

The brainstorm recommends syncing against the "default branch." If the repo's default branch is renamed (e.g., `master` to `main`), the cached branch name in interop's config becomes stale. The GitHub API returns the current default branch via `GET /repos/{owner}/{repo}`, but this must be re-fetched periodically, not cached at startup.

---

## Cross-Cutting Observations

1. **Entity correlation is the critical prerequisite.** P0-2 and P1-1 both stem from the missing `entity_correlation` table. Without it, collision detection, ancestor lookup, and self-originated event suppression all break for cross-adapter file entities. This table should be implemented before filesync.go.

2. **The Contents API is adequate for low-volume sync but creates architectural debt.** P0-1 (409 retry), P0-3 (N+1 reads), P2-1 (commit noise), and P3-1 (committer attribution) all trace back to the Contents API's per-file-per-commit model. The Git Data API (trees/blobs/commits) solves all four but is more complex. A staged approach: start with Contents API for v1, add Git Data API as an optimization when volume exceeds thresholds.

3. **Self-originated event suppression is upstream of everything else.** P0-2 (ping-pong) and P2-2 (no suppression) combine into a feedback loop that can only be broken by either the correlation table or a content-hash dedup layer. Both should be implemented -- correlation for correctness, content-hash for defense-in-depth.
