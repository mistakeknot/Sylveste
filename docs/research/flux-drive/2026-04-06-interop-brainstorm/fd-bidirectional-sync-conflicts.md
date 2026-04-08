### Findings Index
- P0 | SYN-1 | "Key Decisions" | Common ancestor store persistence not specified — in-memory loss on restart causes silent data loss
- P1 | SYN-2 | "Key Decisions" | LWW clock source not specified — external system timestamps have skew
- P1 | SYN-3 | "Key Decisions" | Conflict resolution policy is global, not per-adapter-pair
- P1 | SYN-4 | "Key Decisions" | No structured conflict record for unresolvable conflicts — silent tiebreaking
- P2 | SYN-5 | "Open Questions" | interkasten WAL migration planned as open question, not requirement
- P2 | SYN-6 | "Day-1 Adapters" | Four-system bidirectional sync creates O(N^2) adapter pair conflicts without priority hierarchy
Verdict: risky

## Summary

Bidirectional sync across four systems is the core value proposition of interop, and the brainstorm correctly identifies three-way merge for content and LWW for metadata as the resolution strategy (line 41). However, the document treats conflict resolution as a ported concept from interkasten without addressing the fundamental assumptions that make these strategies correct: persisted ancestors, trusted clocks, per-pair policies, and explicit conflict surfacing. The brainstorm says "configurable per-adapter" (line 41) but the actual configuration surface, default policies, and failure modes are all unspecified. The most dangerous gap is the ancestor store — if it's in-memory only and lost on daemon restart, the next sync cycle will silently discard writes from whichever system loses the tiebreaker.

## Issues Found

1. **[P0] SYN-1: Common ancestor store persistence not specified**
   The brainstorm mentions "three-way merge for content (ported concept from interkasten)" (line 41) but does not specify where the common ancestor (the last successfully synced version of each entity) is stored. Three-way merge requires three inputs: version A (local), version B (remote), and version O (common ancestor). Without O, the merge degenerates to a two-way diff that cannot distinguish "A added a line" from "B deleted a line."
   
   **Risk**: If the ancestor store is in-memory (the default for a Go struct), a daemon restart resets all sync state. The next sync cycle sees the current state of GitHub and the current state of Notion with no common ancestor. It treats them as diverged from an empty base. Depending on the merge implementation:
   - Best case: false conflicts on every previously-synced entity (hundreds of manual resolutions)
   - Worst case: the merge combines all content from both sides (creating duplicates) or silently picks one side (losing the other's changes)
   
   This is a P0 because data loss is permanent and invisible. The user discovers it days later when a bead's description doesn't match the GitHub issue.
   
   **Recommendation**: Add to Key Decisions: "The common ancestor store is persisted to disk (SQLite or flat JSON file) and is a first-class component, not a cache. It is written on every successful sync completion and read on daemon startup. Loss of the ancestor store is treated as a critical failure requiring manual reconciliation, not a soft reset."

2. **[P1] SYN-2: LWW clock source not specified**
   The brainstorm states "last-write-wins for metadata" (line 41) but does not specify whose clock is used for the "last write" determination. There are at least four clocks in play: GitHub's event timestamp, Notion's `last_edited_time`, beads' event timestamp, and the local filesystem's mtime.
   
   **Risk**: These clocks are not synchronized. GitHub event timestamps use GitHub's server clock. Notion uses Notion's server clock. A developer's local machine clock may be skewed by minutes. If LWW uses the originating system's timestamp, a 3-minute clock skew means any update from the lagging system will be silently overwritten by the leading system for those 3 minutes.
   
   Example: Beads close event fires at 09:57:30 (real time). A developer closes the GitHub issue from a machine with clock 3 minutes ahead, timestamped 10:00:00. LWW picks GitHub (10:00:00 > 09:57:30). But the beads close happened first in real time. The beads-side metadata update is silently discarded.
   
   **Recommendation**: Add to Key Decisions: "LWW for metadata uses interop's own receive-time monotonic clock (`time.Now()` at event ingestion), not the originating system's timestamp. This ensures a consistent ordering regardless of external clock skew. The original system timestamps are preserved as metadata for audit but not used for conflict resolution."

3. **[P1] SYN-3: Conflict resolution policy is global, not per-adapter-pair**
   The brainstorm says "configurable per-adapter" (line 41) but the actual configuration described is a single strategy: "three-way merge for content, last-write-wins for metadata." There is no specification of per-adapter-pair policies.
   
   **Risk**: The correct policy for Beads<->GitHub (beads is authoritative for issue tracking) is different from Notion<->local FS (local edits are authoritative for drafts) and different from Notion<->GitHub repo files (repo is source of truth for code docs). A single global policy cannot be correct for all pairs.
   
   Example: If beads is authoritative for issue state, then a GitHub close should propagate to beads but a beads close should NOT be overridden by GitHub reopening. This requires a directional authority policy, not symmetric LWW.
   
   **Recommendation**: Add to Key Decisions: "Conflict resolution is configured per-adapter-pair with directional authority. Each pair specifies: (a) which system is authoritative for which fields, (b) whether content uses three-way merge or one-side-wins, (c) how unresolvable conflicts are surfaced. Default policy: symmetric LWW. Beads<->GitHub: beads authoritative for state, GitHub authoritative for labels."

4. **[P1] SYN-4: No structured conflict record for unresolvable conflicts**
   The brainstorm does not mention what happens when both sides changed the same field and no common ancestor exists (or both sides changed differently from the ancestor). Three-way merge can detect this case but the brainstorm does not specify how it is surfaced.
   
   **Risk**: Silent tiebreaking means the user never knows data was overwritten. A content change made in Notion could be silently replaced by a GitHub-side edit with no record that a conflict occurred. This is worse than not syncing at all — at least with no sync, the user knows the systems are independent.
   
   **Recommendation**: Add: "Unresolvable conflicts (both sides changed the same content from the same ancestor, or no ancestor exists) are written to a structured conflict log before any resolution is applied. The conflict record includes: entity ID, field, both versions, ancestor version (if any), chosen resolution, timestamp. Conflicts are exposed via the MCP server so Claude Code sessions can prompt the user to resolve manually."

5. **[P2] SYN-5: interkasten WAL migration is an open question, not a requirement**
   Open Question 5 (line 76) asks "how do we migrate interkasten's existing sync state (WAL, conflict history, tracked databases) into interop?" This should be a day-1 requirement, not an open question.
   
   **Risk**: Without migrating interkasten's sync state, the first sync after migration treats all existing Notion<->beads relationships as new. Every previously-synced page triggers a false conflict. With the current interkasten tracking ~50+ databases, this could generate hundreds of spurious conflicts that bury real issues.
   
   **Recommendation**: Elevate from Open Questions to Key Decisions: "Migration of interkasten's WAL, conflict history, and sync-state database is a day-1 requirement, not a future consideration. The migration tool converts interkasten's TypeScript sync state into interop's ancestor store format. Without migration, the first sync run produces false conflicts on every previously-synced entity."

6. **[P2] SYN-6: Four-system bidirectional sync creates O(N^2) conflict surface without priority hierarchy**
   The brainstorm describes 4 adapters with bidirectional sync, creating 6 potential adapter pairs (4 choose 2). The brainstorm's data flows (lines 14-18) specify 4 specific flows, but the event-driven hub architecture means any adapter can potentially emit events that reach any other adapter.
   
   **Risk**: Without a clear entity-to-adapter ownership model, a change to a Notion page could propagate to local FS, which triggers an fsnotify event, which propagates back to Notion, creating an infinite sync loop. The brainstorm's event-driven architecture is vulnerable to cycles unless explicitly prevented.
   
   **Recommendation**: Add: "Each entity has a declared home adapter. Events are routed only to the home adapter's configured sync pairs, not broadcast to all adapters. Cycle detection: the event bus tags each event with an originating adapter and a hop count. Events that return to their originating adapter are discarded."

## Improvements

1. **Add a sync state visualization command**: An MCP tool that shows the last-sync timestamp, ancestor version hash, and conflict count for each entity across all adapter pairs. This is the first thing an operator reaches for when debugging sync divergence.

2. **Document the entity identity model**: How is "the same entity" identified across systems? A GitHub issue #42 corresponds to beads issue sylveste-xyz and Notion page UUID abc-123. The mapping must be persisted and versioned alongside the ancestor store.

3. **Consider eventual consistency guarantees**: Specify the maximum expected sync latency (webhook: <5s, polling fallback: <60s) and the consistency model (eventual, not strong). Users need to know that a change in GitHub may take up to 60s to appear in Notion during degraded webhook delivery.

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 6 (P0: 1, P1: 3, P2: 2)
SUMMARY: The brainstorm correctly identifies three-way merge and LWW as the conflict resolution strategy but omits the critical implementation requirements — persisted ancestor store, trusted clock source, per-pair policies, and conflict surfacing — that prevent silent data loss in bidirectional sync.
---

<!-- flux-drive:complete -->
