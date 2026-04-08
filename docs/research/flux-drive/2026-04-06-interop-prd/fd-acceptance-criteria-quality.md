### Findings Index
- P1 | ACQ-01 | "F1 — CollisionWindow" | CollisionWindow criterion unverifiable without specifying measurement method
- P1 | ACQ-02 | "F2 — Beads Adapter" | "Handles incoming events" criterion has no testable success/failure definition
- P1 | ACQ-03 | "F3 — GitHub Adapter" | "Repo files: bidirectional sync of markdown files with Notion pages" — no criterion for what constitutes sync success or conflict
- P1 | ACQ-04 | "F4 — Notion Adapter" | Three-way merge acceptance criterion has no observable output definition
- P2 | ACQ-05 | "F5 — Filesystem Adapter" | "Handles incoming events: writes/updates/deletes local files" — no criterion for partial failure or atomicity
- P2 | ACQ-06 | "F6 — MCP Server" | "Skills: sync management, conflict resolution, adapter configuration" — not testable as stated; no enumeration of what each skill does
- P2 | ACQ-07 | "F7 — Migration" | "Post-migration verification: all tracked entities present" — no criterion for what "present" means (count match? hash match? field-by-field?)
- P2 | ACQ-08 | "F1 — SyncJournal" | "SyncJournal persists Begin/Complete/MarkFailed/ResolveConflict to SQLite" — no durability guarantee criterion (fsync? WAL mode?)
- P3 | ACQ-09 | "F3 — GitHub" | Rate-limit criterion checks remaining header but has no criterion for retry behavior
- P3 | ACQ-10 | "F4 — Notion" | Multi-workspace support criterion says "token resolution chain" — the chain resolution order is not specified

Verdict: needs-attention

## Summary

The PRD acceptance criteria cover the happy path for each feature but consistently omit observable output definitions for the most failure-prone operations: conflict resolution, migration verification, and three-way merge. Several criteria are activity criteria ("handles incoming events") rather than outcome criteria ("incoming event results in bead state change within 30s OR conflict record written to SyncJournal"). The P1 findings represent criteria that could be marked complete by a developer who implements a stub — nothing in the criterion text would catch it.

## Issues Found

### P1 | ACQ-01 — CollisionWindow criterion unverifiable

**Location**: PRD § F1, criterion 3: "CollisionWindow detects opposing-source events within 5s TTL and routes to ConflictResolver"

**Problem**: "Routes to ConflictResolver" is an internal behavior with no observable external output. A test can only verify this by inspecting internal state. The criterion should specify what externally observable state results: a conflict record in SyncJournal, a structured error response, a metric increment — something a third party can check.

**Failure scenario**: A developer implements CollisionWindow as a stub that calls ConflictResolver with an empty conflict struct. All current criteria pass. ConflictResolver receives a no-op call. No data is written. All downstream features built on CollisionWindow produce silent no-ops in production.

**Fix**: Change criterion 3 to: "CollisionWindow detects opposing-source events within 5s TTL and writes a conflict record to SyncJournal with `status=pending` observable via `GET /conflicts`"

---

### P1 | ACQ-02 — Beads adapter "handles incoming events" not testable

**Location**: PRD § F2, criterion 3: "Handles incoming events: creates beads from GitHub issues, updates state from Notion changes"

**Problem**: No success definition. What does "creates beads" mean — bd create exits 0? The bead appears in `bd list`? What's the latency window? What happens if bd fails — is the event retried or discarded? No criterion exists for the failure path.

**Failure scenario**: Developer implements HandleEvent() to invoke `bd create` and swallows all errors. bd create fails silently due to a Dolt issue. Criterion 3 is marked complete because the code path exists. In production, GitHub issue creates never appear in beads.

**Fix**: Split into two criteria: (a) "HandleEvent(github.IssueOpened) results in a bead visible via `bd list --format=json` within 60s" and (b) "HandleEvent() failure writes ErrTransient to SyncJournal and re-enqueues the event"

---

### P1 | ACQ-03 — GitHub↔Notion file sync criterion lacks observable definition

**Location**: PRD § F3, criterion 3: "Repo files: bidirectional sync of markdown files with Notion pages"

**Problem**: "Bidirectional sync" is an architectural description, not a testable criterion. No test can verify this without knowing: which files? which Notion pages? within what time window? what constitutes "synced"?

**Failure scenario**: Developer implements one-way sync (GitHub→Notion only) and marks this criterion complete because files do flow bidirectionally in the system design. Notion→GitHub sync is never implemented.

**Fix**: Split into two criteria: (a) "A markdown file edit on GitHub within 60s appears in the corresponding Notion page" and (b) "A Notion page edit within 60s appears as a commit to the corresponding GitHub file"

---

### P1 | ACQ-04 — Three-way merge criterion has no observable output

**Location**: PRD § F4, criterion 5: "Three-way merge for page content using AncestorStore"

**Problem**: "Uses AncestorStore" is an implementation detail, not an outcome. The criterion should describe what happens when a merge succeeds (merged content visible in both systems) and when it fails (conflict record created in SyncJournal, neither side overwritten).

**Fix**: Replace with: "Concurrent edits to the same Notion page from two adapters produce a merged document in Notion AND a SyncJournal entry with type=merge_applied; if merge fails, SyncJournal entry has type=conflict_pending and neither adapter's version is overwritten"

---

### P2 | ACQ-05 — Filesystem adapter write failure has no criterion

**Location**: PRD § F5, criterion 3: "Handles incoming events: writes/updates/deletes local files"

**Problem**: No atomicity or partial-failure criterion. If a write fails mid-operation (disk full), is the partial file removed? Is an error written to SyncJournal? The criterion as written is satisfiable by a best-effort write with no error handling.

**Fix**: Add criterion: "Write failure results in no partial file at target path and an ErrTransient event in SyncJournal"

---

### P2 | ACQ-06 — MCP server skills not enumerated

**Location**: PRD § F6, criterion 3: "Skills: sync management, conflict resolution, adapter configuration"

**Problem**: "Sync management", "conflict resolution", and "adapter configuration" are category names, not testable behaviors. Which MCP tools implement each skill? What are their input/output contracts?

**Fix**: Replace with a list of named skills and their observable effects, or cross-reference a skills spec document.

---

### P2 | ACQ-07 — Migration verification criterion underdefined

**Location**: PRD § F7, criterion 4: "Post-migration verification: all tracked entities present in interop"

**Problem**: "Present" is undefined. Does this mean: same count? same IDs? same sync state? same conflict history? A count-only check would miss entities that migrated with corrupted state.

**Fix**: Change to: "Migration verification reports: (a) entity count matches interkasten's tracked count, (b) each entity's last-sync-state hash matches, (c) zero entities with status=error in interop's SyncJournal"

---

### P2 | ACQ-08 — SyncJournal durability not specified

**Location**: PRD § F1, criterion 5: "SyncJournal persists Begin/Complete/MarkFailed/ResolveConflict to SQLite"

**Problem**: "Persists to SQLite" doesn't specify durability. SQLite in WAL mode with fsync disabled will lose the last ~seconds of writes on crash. The criterion should specify WAL mode + synchronous=NORMAL at minimum.

**Fix**: Add criterion: "SyncJournal SQLite connection uses WAL mode; daemon crash during a journal write does not corrupt existing completed entries"

---

### P3 | ACQ-09 — GitHub rate-limit retry behavior missing

**Location**: PRD § F3, criterion 7: "Per-adapter `*http.Client` with rate limit awareness (respect `X-RateLimit-Remaining`)"

**Problem**: "Respect" is undefined. Does the adapter back off, queue, or drop? When does it resume? No retry behavior is specified.

**Fix**: Add: "When X-RateLimit-Remaining falls below 10, adapter queues outbound requests and resumes after X-RateLimit-Reset timestamp"

---

### P3 | ACQ-10 — Notion multi-workspace token resolution order unspecified

**Location**: PRD § F4, criterion 6: "Multi-workspace support via config (token resolution chain)"

**Problem**: "Token resolution chain" is undefined. YAML config key order? Environment variables? First-match? The resolution order matters when an entity exists in two workspaces.

**Fix**: Add a sentence: "Token resolution: config-file entry for workspace_id takes precedence over INTEROP_NOTION_TOKEN env var; first matching workspace_id in config wins"

## Improvements

1. **Add a "Definition of Done" section to the PRD** — specify that criteria must be outcome-oriented (observable state), not activity-oriented (code path exists). This would catch ACQ-01 through ACQ-04 at authoring time.

2. **Add latency SLOs to all async criteria** — "within 60s" or "within 30s" for every criterion involving cross-system propagation. Async sync without a latency bound is unverifiable.

3. **Cross-reference SyncJournal as the universal failure witness** — every adapter's failure criteria should specify what SyncJournal entry results. This creates a single observable surface for all failure testing.

<!-- flux-drive:complete -->
