### Findings Index
- P0 | BSC-01 | "Architecture — AncestorStore" | AncestorStore persistence is stated but no acceptance criterion verifies behavior across daemon restart
- P1 | BSC-02 | "F4 — Notion Adapter" | Three-way merge criterion does not specify clock source for LWW fallback — external timestamps create silent overwrite risk
- P1 | BSC-03 | "F7 — Migration" | Ancestor store population from interkasten WAL is absent from F7 criteria — first post-migration sync will treat all previously-synced entities as diverged-from-empty
- P1 | BSC-04 | "Architecture — EventBus / SyncJournal" | Conflict resolution policy is not per-adapter-pair — no config mechanism for "beads is authoritative for status fields" vs "Notion is authoritative for page content"
- P2 | BSC-05 | "Architecture — CollisionWindow" | CollisionWindow 5s TTL is stated but no criterion tests behavior when both events arrive after the window — late-arriving events bypass collision detection entirely
- P2 | BSC-06 | "F4 — Notion" | Block-level debouncing (2s) and CollisionWindow (5s) operate on different timescales with no documented interaction — debounce can suppress one side of a collision before the window opens
- P2 | BSC-07 | "Non-goals" | "Real-time collaborative editing" non-goal correctly excluded, but sync-boundary conflict resolution for concurrent edits within a single sync cycle has no documented policy
- P3 | BSC-08 | "F3 — GitHub" | Webhook delivery deduplication TTL (7 days) specified but no criterion for behavior when deduplication store exceeds memory/disk bounds

Verdict: needs-attention

## Summary

The PRD correctly identifies AncestorStore as a first-class persistent component, incorporates CollisionWindow, and names SyncJournal as the neutral conflict arbiter — all are the right primitives. However, three critical correctness gaps remain: (1) no acceptance criterion verifies the AncestorStore survives a daemon restart, which is the primary P0 data-loss scenario for bidirectional sync; (2) the migration plan in F7 does not include ancestor store population, meaning the first post-migration sync will treat every previously-synced entity as having no history; (3) no per-adapter-pair conflict resolution policy exists, meaning all conflicts fall through to a single global tiebreaker that will be wrong for at least one adapter pair on every conflict.

## Issues Found

### P0 | BSC-01 — AncestorStore restart-persistence not verified by any criterion

**Location**: PRD § F1, criterion 6: "AncestorStore persists and retrieves common ancestors by entity ID"

**Problem**: The criterion states persistence but does not test it across a daemon restart. "Persists" in the criterion is satisfiable by an in-memory map that happens to have the word "store" in its name. The actual P0 scenario is: interop restarts (planned or unplanned), AncestorStore is re-initialized empty, the next sync cycle treats both sides of every previously-synced entity as diverged from an empty ancestor, and three-way merge produces a combined document that contains content from both sides rather than detecting no-change.

**Failure scenario**: A planned Docker Compose restart for a config change causes interop to restart at 14:00. At 14:00:05, the first polling cycle runs. Every Notion page has a stored ancestor hash of "" (empty). Notion current content != "". GitHub current content != "". Three-way merge: base="" + local=notion_content + remote=github_content → produces a merge of both, doubling all content in every synced document. User discovers their docs have duplicated content hours later.

**Fix**: Replace F1 criterion 6 with: "AncestorStore persists common ancestors to SQLite (same DB as SyncJournal). After `interop serve` restart, AncestorStore.Get(entityID) returns the same value as before restart for all previously-stored entities. Integration test: store N ancestors, restart daemon process, verify all N are retrievable."

---

### P1 | BSC-02 — LWW clock source for metadata conflicts not specified

**Location**: PRD § Architecture — EventBus, SyncJournal (conflict resolution strategy not explicitly stated); F4 criteria reference three-way merge but not LWW fallback

**Problem**: The brainstorm (referenced in the task context as the source of "LWW for metadata, three-way merge for content") specifies LWW for metadata fields. The PRD inherits this strategy but does not specify the clock source. Notion API timestamps, GitHub event timestamps, and local filesystem mtime are all external-system clocks with potential skew. A 3-minute skew (common on developer machines) means 3 minutes of beads updates are silently overwritten by any GitHub event that arrives during that window.

**Failure scenario**: A team member's machine clock is 4 minutes ahead. She closes a GitHub issue at wall-clock 10:00 (her machine says 10:04). The corresponding bead was closed at 10:01 (interop's clock). LWW picks GitHub's timestamp (10:04 > 10:01), overwriting the bead close with "issue closed" — but the bead was already closed. In the opposite direction: the bead close event at 10:01 is overwritten by a GitHub label change at 10:02 (real time), losing the close.

**Fix**: Add to F1 acceptance criteria: "SyncJournal records interop's receive-time (monotonic clock) alongside each event's originating-system timestamp. LWW decisions use interop receive-time, not originating-system timestamp. ConflictResolver documents which clock is used for each resolution strategy."

---

### P1 | BSC-03 — F7 migration does not populate AncestorStore from interkasten WAL

**Location**: PRD § F7 acceptance criteria — five criteria listed, none mention AncestorStore

**Problem**: interkasten maintains WAL state and conflict history (explicitly referenced in F7: "Migration tool reads interkasten's tracked databases, WAL state, conflict history"). Without converting this WAL state into interop's AncestorStore format, the first sync after migration has no ancestors for any previously-synced entity. Three-way merge degenerates to last-write-wins for every entity that was ever synced by interkasten, producing false conflicts on all of them.

**Scale of impact**: If interkasten has been running for months, this affects every synced Notion page and GitHub issue — potentially hundreds of entities, each triggering a false conflict that requires manual resolution.

**Fix**: Add to F7 acceptance criteria: "Migration tool converts interkasten WAL entries to interop AncestorStore format. After migration and before first sync run, `interop verify-ancestors` reports zero entities with missing ancestors that have a known interkasten sync history."

---

### P1 | BSC-04 — No per-adapter-pair conflict resolution policy

**Location**: PRD § Architecture — "SyncJournal: neutral conflict arbiter"; no config section for resolution policy

**Problem**: The PRD describes SyncJournal as a neutral arbiter but does not specify how it arbitrates. The correct policy differs by adapter pair: beads is authoritative for issue status (a GitHub issue close should not override a bead that was manually re-opened); Notion is authoritative for page content (local FS edits to a Notion-managed doc should be treated as drafts, not overwrites); GitHub is authoritative for repo file content (Notion edits to a file mirrored from a repo should create a PR, not a direct commit). A single global "last write wins" policy will be wrong for at least one of these pairs on every conflict.

**Fix**: Add to F1/Architecture: "SyncJournal resolution policy is configured per-adapter-pair in interop config. Default policy is `conflict_pending` (no automatic resolution). Named policies: `source_wins(adapter)`, `target_wins(adapter)`, `merge_content`. Config example must be included in the PRD or linked spec."

---

### P2 | BSC-05 — Late-arriving events after CollisionWindow TTL bypass collision detection

**Location**: PRD § F1, criterion 3: "CollisionWindow detects opposing-source events within 5s TTL"

**Problem**: The 5s TTL only catches events that arrive within 5 seconds of each other. If both sides of a conflict are edited within 10 minutes but their corresponding events arrive 6 seconds apart (e.g., due to polling interval variance), CollisionWindow does not trigger. The second event is processed as a normal update, overwriting the first. No conflict record is created.

**Fix**: Add: "Does the PRD intend CollisionWindow to be the primary conflict detector, or a fast-path supplement to the SyncJournal-based ancestor comparison? If it's supplementary, the PRD should document that the three-way merge in ConflictResolver is the definitive conflict detector, and CollisionWindow is only a latency optimization."

---

### P2 | BSC-06 — Block-level debounce (2s) can suppress one side of a 5s CollisionWindow

**Location**: PRD § F4, criterion 3: "Block-level event debouncing (2s window per entity)"; PRD § Architecture: "CollisionWindow (5s TTL)"

**Problem**: If a Notion block edit and a beads state change arrive within 5s of each other, the Notion event is debounced (held for 2s before being emitted to the bus). The debounced Notion event now arrives at the bus 2s after the beads event. CollisionWindow (5s TTL) has not yet expired, so the collision IS detected — this interaction is safe. However, if the debounce window is configurable and set above 5s (e.g., 6s debounce), the Notion event arrives after the CollisionWindow expires and the collision is missed. The current hardcoded values (2s < 5s) are safe, but this invariant is not documented.

**Fix**: Add to Architecture section: "Debounce windows for all adapters must be less than the CollisionWindow TTL (5s). If debounce is configurable, validation at startup must enforce: debounce_window < collision_window_ttl."

---

### P2 | BSC-07 — Concurrent edits within a single sync cycle have no documented policy

**Location**: PRD § Non-goals: "Real-time collaborative editing — interop syncs document state, not keystrokes. Conflicts are resolved at sync boundaries."

**Problem**: The non-goal is correctly scoped. However, "resolved at sync boundaries" implies a policy that isn't defined. If two edits arrive in the same polling cycle (e.g., both within a 30s beads poll interval), which is processed first? The EventBus priority lanes (express/urgent/routine) determine ordering for different event types, but same-priority concurrent edits from different adapters have undefined ordering.

**Fix**: Add to Architecture: "Same-priority concurrent edits within a single sync cycle are processed in EventBus receive order. The second edit will detect a conflict against the result of the first and route to ConflictResolver."

---

### P3 | BSC-08 — Deduplication store bounds not specified

**Location**: PRD § F3, criterion 6: "Webhook delivery deduplication via `X-GitHub-Delivery` header (7-day TTL)"

**Problem**: A 7-day TTL for webhook delivery IDs with no eviction policy will accumulate unboundedly for active repos. A repo with 100 webhook events/day × 7 days = 700 entries per repo — manageable, but the criterion doesn't specify the storage backend (memory, SQLite table) or the eviction strategy (background sweep, LRU, TTL index).

**Fix**: Add: "Webhook delivery deduplication uses a SQLite table with a TTL index. Background sweep runs every 6 hours to delete expired entries."

## Improvements

1. **Define an explicit "sync correctness contract"** in the Architecture section — three properties: (a) no write is lost silently, (b) no false conflict is raised for a true non-conflicting change, (c) all resolved states are auditable. Acceptance criteria should be written to verify each property.

2. **Add a reconciliation schedule criterion** to F1 — the brainstorm recommended 6-hour full-sync reconciliation. This is absent from F1 criteria. A reconciliation run is the backstop for events missed due to webhook delivery failure.

3. **Document the ancestor store schema** in the PRD or a linked spec — entity_id (string), source_adapter (string), snapshot_hash (SHA-256), synced_at (timestamp). This prevents AncestorStore from being implemented as an opaque blob store that can't be migrated.

<!-- flux-drive:complete -->
