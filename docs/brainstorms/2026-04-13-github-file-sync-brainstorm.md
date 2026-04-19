---
artifact_type: brainstorm
bead: sylveste-911m
stage: discover
---

# GitHub Repo File Sync (Bidirectional)

## What We're Building

Bidirectional sync between local filesystem files and GitHub repository files, extending the existing GitHub adapter (Phase 3: Issues/PRs) with file CRUD capabilities. When a local markdown file changes, the corresponding GitHub repo file updates within 120s, and vice versa.

This closes the loop on interop's sync fabric: beads track state, Notion holds prose, the filesystem holds files, and GitHub holds the canonical versioned copies. File sync is the last adapter capability before MCP server (Phase 5).

## Why This Approach

**Path-based entity correlation.** Same relative path = same entity. `fs:file:docs/README.md` maps to `github:file:owner/repo:docs/README.md` by convention. No lookup table, no migration surface, covers the primary use case (syncing project docs between local and remote). The EntityKey format `github:file:<owner>/<repo>:<path>` is already defined in the plan (Task 1.2).

**Hybrid detection: push webhook + periodic poll.** Push events provide real-time detection (seconds). Periodic tree-SHA polling provides reconciliation (catches force-pushes, missed webhooks, network blips). This mirrors the Notion adapter pattern: webhook for real-time + FullSync for drift correction.

**Event bus routing, not direct adapter-to-adapter.** File changes flow through the EventBus like all other events. The filesystem adapter emits `fs:file:*` events; the GitHub filesync module emits `github:file:*` events. The bus handles collision detection and conflict resolution. The ConflictResolver uses AncestorStore for three-way merge on content.

## Key Decisions

1. **Path-based correlation over explicit mapping.** Relative paths are the join key. No correlation table needed. If a file exists at the same relative path in both systems, they're the same entity. Files only in one system are not synced unless explicitly created via event.

2. **Push webhook for real-time, poll for reconciliation.** Add `push` event handling to the GitHub adapter's webhook handler. Add periodic tree-SHA comparison (every 5 minutes) for FullSync. Push gives <10s latency; poll gives correctness guarantee.

3. **Git Contents API for file CRUD.** The GitHub REST API's Contents endpoints handle single-file operations with optimistic concurrency (SHA-based). For the sync use case (individual file changes), this is simpler than the Git Data API (trees/blobs/commits). The trade-off: Contents API creates one commit per file change. Acceptable for sync volume.

4. **Configurable sync scope.** Not all repo files should sync. Config specifies which paths to watch (e.g., `sync_paths: ["docs/", "plans/"]`). Default: nothing synced until configured. This prevents accidental sync of CI configs, build artifacts, or sensitive files.

5. **Filesync as a module within the GitHub adapter, not a separate adapter.** The plan specifies `filesync.go` inside `internal/adapters/github/`. File sync shares the GitHub adapter's auth, rate limiting, and webhook handler. It adds new event types to the same adapter rather than registering a second adapter for the same system.

## Open Questions

1. **Commit attribution.** When interop pushes a file change to GitHub, what committer name/email should it use? Options: a dedicated bot identity, or the identity-mapped user who made the local change. Recommendation: configurable, default to a bot identity (`interop-sync <interop@noreply>`).

2. **Branch targeting.** Should sync target a specific branch (e.g., `main`) or the repo's default branch? What about PRs that modify synced files — should those trigger sync events? Recommendation: sync against default branch only; PR file changes are Phase 4+ scope.

3. **Binary files.** The Contents API supports binary files (base64-encoded), but three-way merge doesn't work on binary content. Recommendation: skip binary files entirely — only sync text files matching configured extensions (`.md`, `.txt`, `.yaml`).

4. **Conflict UX.** When three-way merge fails (divergent edits), the ConflictResolver dead-letters to SyncJournal. How does the user resolve it? Phase 5 (MCP server) will expose `/conflicts` and `/resolve-conflict` tools. For Phase 4, conflicts are logged and queryable via SyncJournal directly.
