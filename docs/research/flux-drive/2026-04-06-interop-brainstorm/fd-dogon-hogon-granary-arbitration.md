# fd-dogon-hogon-granary-arbitration Review: interop Integration Fabric Brainstorm

**Source:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`
**Reviewed:** 2026-04-06
**Agent:** fd-dogon-hogon-granary-arbitration (Hogon — bidirectional sync, cross-adapter state reconciliation, atomic rollback)
**Track:** D (Esoteric)
**Bead:** sylveste-bcok

---

## Findings Index

- P0 | DHG-01 | Key Decisions #8 / Conflict Resolution | No atomic rollback (bulu): cross-adapter sync partial failure leaves permanent split state with no recovery mechanism
- P0 | DHG-02 | Key Decisions #8 / Three-Way Merge | No independent reconciliation ledger: reconciliation state lives inside adapters, making each adapter both party and judge in its own disputes
- P1 | DHG-03 | Key Decisions #8 / Conflict Resolution | Three-way merge unresolvable path undefined: brainstorm specifies no arbitration path when automatic merge fails
- P1 | DHG-04 | Open Questions #3 / Identity Mapping | Identity mapping is static config: no drift detection for unmapped identities, no reconcilable entity with update protocol
- P2 | DHG-05 | Day-1 Data Flows / Multi-Adapter | Three-party coordination not addressed: Notion → beads AND Notion → GitHub repo simultaneous sync is pairwise sequential with no atomicity across three parties

---

## DHG-01 — No Atomic Rollback for Cross-Adapter Partial Failure (P0)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #8": "three-way merge for content (ported concept from interkasten), last-write-wins for metadata, configurable per-adapter."

**Severity:** P0 — The brainstorm specifies bidirectional sync for all four Day-1 flows (beads↔GitHub, Notion↔beads, Notion↔local FS, Notion↔GitHub repo files). It describes conflict resolution (three-way merge, last-write-wins) but is entirely silent on partial failure: what happens when a sync operation succeeds at the source adapter but the destination adapter fails mid-write?

**The Hogon parallel:**
The hogon's bulu (reversal ceremony) is the most expensive protocol in Dogon grain-transfer governance, requiring all parties present, for a reason: atomicity across three independent ledgers is hard. The bulu exists because the hogon knows from centuries of practice that partial transfers — grain left the source granary but never arrived at the destination — are the most dangerous state in the system. The hogon would rather refuse a transfer than permit a partial one. A system that makes transfers cheap without making rollback equally robust is, in the hogon's accounting, building a tab that compounds interest.

**Concrete failure scenario:** A user closes bead `sylveste-bcok` via `bd close`. The beads adapter processes the close and emits `Event{Type: "beads.state", EntityID: "sylveste-bcok", NewState: "done"}` to the event bus. The GitHub adapter receives the event and begins updating the corresponding GitHub issue. The GitHub API call returns a 503 after timing out (GitHub is rate-limiting). The GitHub adapter logs the error and drops the event — the circuit breaker notes the failure. The bead is closed in beads, the GitHub issue remains open. There is no bulu: no mechanism to roll back the beads close, no mechanism to retry the GitHub close, no mechanism to surface the split state as a pending action. The user discovers the discrepancy when they check GitHub three days later.

**Evidence:** The brainstorm specifies "panic recovery and circuit breakers" for fault isolation, but circuit breakers isolate crashes — they do not provide cross-adapter rollback. The brainstorm does not contain the words "rollback," "compensating transaction," "two-phase," "retry queue," or "split state." The concept does not exist in the document.

**Smallest fix:** Introduce a `SyncJournal` — a persistent log of in-progress cross-adapter sync operations. Before any cross-adapter event is dispatched:

```go
// bus.go, in event routing
journal.Begin(event.ID, event.EntityID, sourceAdapter, destAdapter)
```

On destination adapter success:
```go
journal.Complete(event.ID)
```

On destination adapter failure:
```go
journal.MarkFailed(event.ID, err)
// enqueue for retry or surface as unresolved
```

On daemon startup, scan journal for `MarkFailed` entries and either retry or surface to the operator. The `SyncJournal` is the hogon's master ledger — independent of both adapters. Cost: one SQLite/BoltDB table (or a JSONL append log) + Begin/Complete/MarkFailed methods. No two-phase commit required for Day-1 because the adapters have no pre-commit hooks — retry-until-success with the journal as the audit record is sufficient.

---

## DHG-02 — No Independent Reconciliation Ledger: Adapters Are Party and Judge (P0)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Architecture Sketch": the diagram shows only the Event Bus and adapter goroutine pools. No reconciliation layer is depicted. "Key Decisions #8": conflict resolution is "configurable per-adapter."

**Severity:** P0 — The brainstorm's conflict resolution is "configurable per-adapter." This means the adapter that is a *party to the conflict* also determines *how the conflict is resolved*. In the hogon model, this is structurally prohibited: the hogon (arbiter) is never a party to the transfer. If the beads adapter resolves a beads↔GitHub conflict using a beads-internal last-write-wins policy, the beads adapter is acting as both party and judge — its own timestamp wins.

**The Hogon parallel:**
The hogon's master reconciliation ledger is maintained by the hogon, not by either granary. Its neutrality is architectural, not just procedural. A system where each granary resolves disputes by referring to its own ledger produces outcomes that systematically favor the granary with the most recent write timestamp — which is the granary that last touched the entity, not necessarily the granary with the authoritative state.

**Concrete failure scenario:** A Notion page and its corresponding GitHub file are both edited within a 10-second window. The Notion adapter applies last-write-wins using the Notion page's `last_edited_time` field (2026-04-06T14:23:01Z). The GitHub adapter applies last-write-wins using GitHub's `updated_at` field (2026-04-06T14:23:00Z). Both timestamps are system-generated — neither reflects the user's actual intent. Notion's timestamp is 1 second newer. Last-write-wins: Notion wins. The GitHub edit (a corrected code example) is silently overwritten by the Notion edit (a title change). The user who edited the GitHub file sees their change vanish with no notification.

**Evidence:** The brainstorm says "last-write-wins for metadata, configurable per-adapter." "Configurable per-adapter" explicitly places the reconciliation decision inside each adapter, with no independent arbiter.

**Smallest fix:** The `SyncJournal` from DHG-01 doubles as the independent reconciliation ledger. When a conflict is detected (two adapters both emitting events for the same `EntityID` within a configurable window — see Song yizhan's bingjuan), the conflict resolution decision is written to the `SyncJournal` with both values, the resolution strategy applied, and the winning value. The individual adapters report to the journal; they do not resolve independently. The journal is the hogon. Cost: add a `ResolveConflict(entityID, strategyName, value1, value2, winner) ConflictRecord` method to `SyncJournal`. The adapters call this instead of resolving locally.

---

## DHG-03 — Three-Way Merge Unresolvable Path Undefined (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Key Decisions #8": "three-way merge for content (ported concept from interkasten)."

**Severity:** P1 — Three-way merge can fail. When the common ancestor has diverged such that both sides have made conflicting structural changes to the same section, three-way merge produces a conflict marker (`<<<<<<<`, `=======`, `>>>>>>>`), not a resolution. The brainstorm specifies three-way merge as the content conflict strategy but does not specify what happens when three-way merge produces an unresolvable conflict. There is no "disputed transfer" queue, no user-surfacing path, no merge-conflict artifact.

**The Hogon parallel:**
The hogon's arbitration process has an explicit outcome for unresolvable disputes: the transfer is suspended, both ledgers are frozen at their last-agreed state, and the parties are brought to the toguna (village council) for a hearing. There is no path through the hogon system that produces a permanently ambiguous state without human resolution. The hogon is the last resort before the council, but even the hogon has a path for cases that exceed their authority.

**Concrete failure scenario:** A user edits a Notion page (adds a new section in the middle of the document). Simultaneously, a collaborator edits the corresponding local markdown file (also adds a new section in the same location, with different content). Three-way merge runs against the last-synced common ancestor. Both sides added content at the same anchor point — three-way merge cannot determine which addition comes first. The merge produces conflict markers in the output. The brainstorm does not specify: does interop write the conflict-marked file to local FS? Does it refuse the sync? Does it notify the user? Does it queue the conflict for manual resolution? Without a defined path, the implementation will choose one of these arbitrarily — most likely writing the conflict-marked file to local FS, creating a broken markdown file that silently propagates to Notion on the next sync.

**Evidence:** The brainstorm's Open Questions do not include "What happens when three-way merge cannot resolve automatically?" The brainstorm specifies the happy path (three-way merge produces a merged result) but not the unhappy path (three-way merge produces a conflict).

**Smallest fix:** Add to the brainstorm's Open Questions section: "Three-way merge unresolvable path: when merge produces conflict markers, does interop (a) write conflict-marked artifact to local FS and surface as a pending conflict in MCP status, (b) refuse the sync and queue both versions as a 'disputed transfer' in SyncJournal pending manual resolution, or (c) prefer one side (source or destination) and record the discarded side in SyncJournal? Option (b) is recommended — it preserves both versions without corrupting either system's state." This is a design decision that must be made before implementation, not after.

---

## DHG-04 — Identity Mapping Is Static Config with No Drift Detection (P1)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Open Questions #3": "GitHub user ↔ Notion user ↔ beads assignee. Where does the mapping live? Config file? Separate identity service?"

**Severity:** P1 — The brainstorm raises identity mapping as an open question and proposes "config file" as one answer. A static config file has no drift detection: it cannot detect when a GitHub username appears in events that maps to no known identity. It cannot detect when a beads assignee is unclaimed but the corresponding GitHub issue remains assigned. It cannot detect when a Notion user's email changes.

**The Hogon parallel:**
The hogon's master reconciliation ledger maintains a registry of all families (ginna) authorized to participate in cross-granary transfers. When an unregistered family attempts a transfer — a family that has moved to the village but not yet been formally registered — the hogon flags the attempt before executing it. The registry is a live document: new families are added through ceremony, departing families are marked inactive. A static registry that was accurate at founding but drifts from reality is the hogon's most dangerous failure mode — transfers that should be rejected (unregistered party) are accepted because the registry is stale.

**Concrete failure scenario:** A new team member joins and creates a GitHub account `@sarah-eng`. She submits a PR that closes bead `sylveste-new-bead`. The beads↔GitHub sync processes the PR close event. The event includes `assignee: sarah-eng`. The identity config file has no mapping for `sarah-eng`. The adapter's behavior is unspecified: does it drop the assignee field? Does it log a warning and continue? Does it fail the sync? If it drops the assignee field, the bead is closed with `assignee: ""` in beads — the work attribution is lost. If it fails the sync, the bead is not closed even though the GitHub PR was merged.

**Evidence:** The brainstorm's Open Question #3 leaves this genuinely open. But "config file" as the proposed answer is static and has no update protocol beyond manual editing.

**Smallest fix:** Define identity mappings as reconcilable entities in the `SyncJournal` (or a separate `IdentityMap` table), not as static YAML. The `IdentityMap` has an `unknown_actors` table where unrecognized GitHub/Notion usernames are logged with the first event that contained them. An MCP tool (`interop_identity_unknown_actors()`) surfaces these to the operator. The operator maps them via a command or config update. Critically: the system never silently drops identity information — it queues unknown identities for resolution and uses `(unknown)` as a sentinel value in the interim. Cost: one `IdentityMap` table + one `unknown_actors` log + one MCP tool to surface them.

---

## DHG-05 — Three-Party Coordination Is Pairwise Sequential Without Cross-Party Atomicity (P2)

**Location:** `docs/brainstorms/2026-04-06-interop-brainstorm.md`, "Day-1 Data Flows": flows 3 and 4 both involve Notion as source — "Notion pages ↔ local files" and "Notion ↔ GitHub repo file system." A Notion page change must sync to both local FS and GitHub repo files. The architecture has no mechanism for coordinating these two simultaneous syncs.

**Severity:** P2 — The event bus routes a Notion page update event to the local FS adapter and the GitHub adapter independently. Both adapters process the event concurrently. If the local FS sync succeeds but the GitHub sync fails, local FS and GitHub are now in different states with respect to the Notion page. Neither adapter knows about the other's failure.

**The Hogon parallel:**
The hogon's three-party coordination protocol (source granary, destination granary A, destination granary B) requires that when one transfer target receives the grain successfully but the other does not, the hogon oversees a partial-bulu that reverts only the successful transfer while preserving the failed one's pending state. Sequential pairwise transfers — source to A, then source to B — have no mechanism to coordinate the A failure with the B success. The hogon would never permit this as the protocol: the three-party coordination must be atomic, or it must be explicitly sequenced with a known rollback path.

**Evidence:** The brainstorm's architecture shows a single event bus routing to independent adapter goroutine pools. There is no concept of an "event group" or "coordinated dispatch" where multiple adapters must all succeed before the originating event is marked complete.

**Question (not assertion):** For Day-1 flows 3 and 4, does interop intend pairwise independent sync (Notion → local FS is independent of Notion → GitHub), or does it intend coordinated sync (both must succeed before the Notion event is marked processed)? The brainstorm does not specify. If independent (acceptable for Day-1), the `SyncJournal` should record both legs independently and surface the partial-failure case (local FS succeeded, GitHub failed) as a pending reconciliation item rather than silently accepting partial success.

**Smallest fix:** Add to the brainstorm: "Multi-target events: a Notion event that targets both local FS and GitHub repo files is dispatched as a coordinated event group. All legs must complete before the event is marked processed. If any leg fails, the failed leg is queued for retry. The SyncJournal records the group as partially-complete until all legs succeed. Day-1 acceptance: sequential pairwise is acceptable if both legs are journaled independently and partial failure is surfaced."

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| DHG-01 | P0 | Cross-adapter atomic rollback | BLOCKING — no bulu; partial sync failures produce permanent split state |
| DHG-02 | P0 | Independent reconciliation ledger | BLOCKING — adapters are party and judge; no neutral arbiter |
| DHG-03 | P1 | Three-way merge unresolvable path | BLOCKING — unresolvable merges have no defined path; implementation will choose arbitrarily |
| DHG-04 | P1 | Identity mapping drift detection | BLOCKING — static config with no unknown-actor detection; attribution silently lost |
| DHG-05 | P2 | Three-party coordination atomicity | Important — multi-target events are pairwise independent with no cross-leg failure surfacing |

**Verdict: needs-revision** — two P0 architectural gaps and two P1 design gaps. The brainstorm describes a bidirectional sync fabric but has no reconciliation layer. The SyncJournal (a persistent, independent, neutral log of cross-adapter operations) is the single structural addition that addresses DHG-01, DHG-02, and DHG-05. DHG-03 and DHG-04 require explicit design decisions before implementation begins.
