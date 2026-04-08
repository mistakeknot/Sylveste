### Findings Index
- P1 | DO-01 | "F3 — GitHub Adapter" | Criterion 3 (repo files↔Notion sync) has runtime dependency on F4+F5 but is listed as an F3 criterion with no sequencing guard
- P1 | DO-02 | "F7 — Migration" | F7 verification requires all adapters (F2-F5) to be running — F7 cannot be developed and closed in parallel with F2-F5 as its position implies
- P1 | DO-03 | "F1 — Core Daemon" | F1's CollisionWindow and ConflictResolver are shared infrastructure required by F2-F5 adapters — F2-F5 cannot be integration-tested until F1 is complete, but the PRD doesn't state this ordering
- P2 | DO-04 | "F4 — Notion / F5 — Filesystem" | F4 (Notion adapter, webhook-first) and F5 (fsnotify, local-first) share the same entity model for markdown files — parallel development creates merge conflict risk on the entity type definitions
- P2 | DO-05 | "F6 — MCP Server" | F6 depends on all adapters being queryable (sync-status, trigger-sync, adapter-health all require running adapters) — F6 development can begin before adapters complete, but F6 acceptance criteria cannot be verified until F2-F5 are done
- P2 | DO-06 | "Dependencies — Caddy" | F3 GitHub webhook receiver requires Caddy to be configured to forward X-Hub-Signature-256 — this infrastructure dependency has no setup step in the PRD and is not owned by any feature
- P3 | DO-07 | "F2 — Beads / F3 — GitHub" | F2 and F3 both handle bead creation from external events — parallel development of these two features creates implicit shared interface on the "create bead from event" logic that may diverge
- P3 | DO-08 | "F1 — Core Daemon" | SyncJournal SQLite schema must be defined before F2-F5 adapters write to it — schema defined in F1 but no version or migration path specified for schema evolution during parallel adapter development

Verdict: needs-attention

## Summary

The PRD lists F1-F7 sequentially but does not declare the dependency graph. The critical-path analysis reveals: F1 is a true prerequisite for integration testing of F2-F5; F3 criterion 3 requires F4 and F5 to be running; F7 requires F2-F5 to be running. This means the correct execution order is F1 → (F2, F3-partial, F4, F5) in parallel → F3-criterion-3 + F6 + F7. Without stating this, teams that develop F3 before F4 will block on criterion 3, and teams that start F7 in parallel with adapters will build a migration tool they cannot verify.

## Issues Found

### P1 | DO-01 — F3 criterion 3 has unguarded runtime dependency on F4 and F5

**Location**: PRD § F3, criterion 3: "Repo files: bidirectional sync of markdown files with Notion pages"

**Problem**: This criterion requires the Notion adapter (F4) and the filesystem adapter (F5) to be complete and running. It is listed as an F3 criterion with no sequencing note. If F3 is assigned before F4 and F5 are done, a developer completing F3 will reach criterion 3 and be blocked. If F3 is closed without verifying criterion 3 (to unblock the sprint), the criterion is silently dropped.

**Concrete ordering constraint**: F3 criterion 3 cannot be verified until F4 AND F5 are both passing their own acceptance criteria. The earliest F3 can be fully closed is: max(F4 close, F5 close).

**Fix**: Add sequencing annotation to F3: "Criterion 3 requires F4 and F5 complete. Criteria 1, 2, 4-7 are independent and can be closed before F4/F5."

---

### P1 | DO-02 — F7 verification requires all adapters running; listed as if independent

**Location**: PRD § F7, criterion 4: "Post-migration verification: all tracked entities present in interop"

**Problem**: "All tracked entities present in interop" requires interop to be running with all adapters. If beads adapter (F2) isn't running, the verifier can't confirm beads entities migrated correctly. If the GitHub adapter (F3) isn't running, GitHub issue sync state can't be verified. F7 is the last feature listed, which might imply it's the last to complete — but its position also implies it could be developed in parallel with F2-F5, which it cannot be.

**Concrete dependency**: F7 can be DEVELOPED (migration tool coding) before F2-F5 are done, but F7 acceptance criteria 3 and 4 (dry-run verification and post-migration verification) require F2+F3+F4+F5 all passing.

**Fix**: Add to F7: "Prerequisites for criteria 3-4: F2, F3, F4, F5 complete. Migration tool code (criteria 1-2) can be developed before adapters are complete."

---

### P1 | DO-03 — F2-F5 integration testing requires F1 complete, but PRD doesn't state this

**Location**: PRD § F1-F5 — no sequencing declarations

**Problem**: The EventBus, SyncJournal, AncestorStore, and CollisionWindow are all defined in F1. F2-F5 adapters write to SyncJournal (on errors and completions), emit events to the EventBus, and read from AncestorStore (for merge). A developer building F2 (beads adapter) can write the adapter code against the Go interface, but cannot integration-test it without F1's EventBus running. This is expected and normal — but the PRD should state it so teams don't block each other during integration testing.

**Fix**: Add a "Feature Ordering" section to the PRD: "F1 must be complete before integration testing of F2-F5 begins. F2-F5 can be developed in parallel against the F1 interface (mocked bus/journal for unit tests). F3 criterion 3 requires F4+F5 complete. F7 full verification requires F2-F5 complete."

---

### P2 | DO-04 — F4 and F5 share a markdown entity model — parallel development creates interface drift risk

**Location**: PRD § F4: "Pages ↔ local markdown files (bidirectional)"; PRD § F5: "Emits events on file create/modify/delete"

**Problem**: F4 (Notion adapter) and F5 (filesystem adapter) both handle the same entity type: local markdown files. F4 maps Notion pages → markdown files, F5 watches markdown files and emits events. Their event payloads for the same entity must be compatible — the entity ID, content hash, and file path representation must agree. If F4 and F5 are developed in parallel without agreeing on the markdown entity schema first, they will produce incompatible event payloads that fail when routed through the EventBus to each other.

**Fix**: Before F4 and F5 begin, define a shared `MarkdownFileEntity` schema: entity ID format (relative path from watch root? SHA of canonical path?), content hash algorithm (SHA-256 of raw content? normalized content?), path representation (absolute? relative to configured watch dir?). Both adapters import this schema from a shared package.

---

### P2 | DO-05 — F6 acceptance criteria require running adapters; MCP server itself does not

**Location**: PRD § F6, criteria: "sync-status, trigger-sync, list-conflicts, resolve-conflict, adapter-health"

**Problem**: The MCP server infrastructure (HTTP server, tool registration) can be built and tested independently of adapters. But all five listed MCP tools require adapters to be running to return meaningful data. adapter-health requires F2-F5 running. sync-status requires at least one adapter. If F6 is assigned to a developer and they're expected to close it before adapters are done, the criteria are unverifiable.

**Fix**: Split F6 verification into two phases: "(a) MCP server starts, tool registration succeeds, tools return well-formed JSON error when no adapters registered — verifiable before F2-F5 complete; (b) all tools return correct data with F2-F5 running — verifiable after adapters complete."

---

### P2 | DO-06 — Caddy configuration for GitHub webhook forwarding has no owning step

**Location**: PRD § Dependencies: "Caddy reverse proxy on zklw (existing infrastructure)"; PRD § F3, criterion 2: "Caddy forwards `X-Hub-Signature-256` header correctly"

**Problem**: F3 criterion 2 requires Caddy to be configured to forward the X-Hub-Signature-256 header. This is not a code change — it's an infrastructure configuration change to Caddy's reverse proxy config. It is not owned by any feature (F1-F7 are all code features). If the Caddy config isn't updated before F3 testing begins, criterion 2 fails with an infrastructure issue that looks like a code bug.

**Fix**: Add a "Setup Prerequisites" section to the PRD or to F3: "Caddy config must be updated to forward X-Hub-Signature-256 header to interop. This is a one-time infrastructure change owned by the F3 developer before F3 can be tested. Config snippet: `header_up X-Hub-Signature-256 {http.request.header.X-Hub-Signature-256}`."

---

### P3 | DO-07 — F2 and F3 both create beads from external events — shared logic may diverge

**Location**: PRD § F2, criterion 3: "creates beads from GitHub issues"; PRD § F3, criterion 2: "Issues: create/close/update/comment sync with beads"

**Problem**: Both F2 (beads adapter) and F3 (GitHub adapter) handle bead creation from external events. F2 handles it on the beads side (listening for incoming bus events), F3 handles it on the GitHub side (translating GitHub issue events to bead create calls). If these are developed independently, the "GitHub issue → bead" translation logic may be duplicated, with different field mappings (title truncation, label mapping, assignee resolution) in each adapter.

**Fix**: Before F2 and F3 begin parallel development, define the canonical "GitHub issue to bead" translation spec as a shared document or Go function. Both adapters import or reference the same spec.

---

### P3 | DO-08 — SyncJournal schema evolution during parallel development

**Location**: PRD § F1, criterion 5: "SyncJournal persists Begin/Complete/MarkFailed/ResolveConflict to SQLite"

**Problem**: The SyncJournal SQLite schema is defined as part of F1. F2-F5 adapters all write to SyncJournal. If the schema needs a new column (e.g., F4 needs an adapter_workspace_id column for multi-workspace Notion support), the schema must be migrated while F2-F5 are already writing to it. No schema migration strategy is specified.

**Fix**: Add to F1: "SyncJournal schema uses a migrations table with version tracking. Any adapter that requires a schema change ships a migration file. F1 defines schema v1; adapter-specific columns are added in v2+ migrations." Reference golang-migrate or goose as the migration tool.

## Improvements

1. **Add a Feature Dependency Graph to the PRD** — a simple table or Mermaid diagram: F1 → {F2, F3(partial), F4, F5} → {F3(full), F6, F7}. This is a 10-line addition that prevents sequencing confusion during planning.

2. **Define shared schemas before parallel adapter development begins** — MarkdownFileEntity (F4+F5 shared), GitHub-issue-to-bead translation spec (F2+F3 shared), SyncJournal migration strategy (F1, consumed by all). These are pre-development artifacts, not code features.

3. **Assign infrastructure setup steps** — Caddy config, GitHub App creation, Notion webhook URL registration. Each has an owning feature and a "done" criterion. Without owners, these are assumed to exist and discovered missing during testing.

<!-- flux-drive:complete -->
