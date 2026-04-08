---
reviewed: 2026-04-06
input: docs/prds/2026-04-06-interop.md
bead: sylveste-bcok
agents:
  - fd-acceptance-criteria-quality
  - fd-adapter-interface-contracts
  - fd-bidirectional-sync-conflicts
  - fd-scope-containment
  - fd-dependency-ordering
verdict: needs-attention
p0_count: 1
p1_count: 12
p2_count: 13
p3_count: 7
---

# Flux Drive PRD Review — interop

**Reviewed**: 2026-04-06 | **Agents**: 5 | **Verdict**: needs-attention

## Verdict Summary

| Agent | Verdict | Summary |
|-------|---------|---------|
| fd-acceptance-criteria-quality | needs-attention | 4 P1s: CollisionWindow, beads incoming events, GitHub file sync, and three-way merge criteria all lack observable output definitions |
| fd-adapter-interface-contracts | needs-attention | 3 P1s: HandleEvent() blocking contract missing, identity mapping defaults to display names (silent corruption), Emit() close-on-Stop undocumented |
| fd-bidirectional-sync-conflicts | needs-attention | 1 P0 + 3 P1s: AncestorStore restart persistence not tested, LWW clock unspecified, F7 migration missing ancestor store population, no per-adapter-pair conflict policy |
| fd-scope-containment | needs-attention | 2 P1s: F3 criterion 3 requires F4+F5 complete (unstated), F7 requires all adapters complete (unstated); F4 porting scope undefined |
| fd-dependency-ordering | needs-attention | 3 P1s: same F3/F7 cross-dependencies confirmed, F1→F2-F5 integration ordering unstated; markdown entity schema drift risk for F4+F5 parallel dev |

## Critical Findings (P0)

### P0-1 — AncestorStore restart-persistence not verified by any acceptance criterion
**Agents**: fd-bidirectional-sync-conflicts (BSC-01)
**Location**: PRD § F1, criterion 6

F1 criterion 6 says "AncestorStore persists and retrieves common ancestors by entity ID" but has no criterion that survives a daemon restart. The P0 failure: interop restarts, AncestorStore re-initializes empty, the next polling cycle treats every previously-synced entity as diverged from an empty ancestor, and three-way merge combines content from both sides — doubling all synced document content with no error or conflict record. This is a silent data-loss scenario that activates on every planned restart (deploys, config changes) not just crashes.

**Fix**: Replace F1 criterion 6 with: "After daemon restart, AncestorStore.Get(entityID) returns the same value as before restart for all previously-stored entities. Integration test: store N ancestors, restart daemon process, verify all N retrievable."

---

## Important Findings (P1)

### Criteria Testability (4 P1s from fd-acceptance-criteria-quality)

**P1-ACQ-01 — CollisionWindow criterion is internal-only observable**
Criterion "routes to ConflictResolver" is not externally observable. A stub implementation passes. Fix: require a SyncJournal entry with `status=pending` observable via `GET /conflicts`.

**P1-ACQ-02 — Beads adapter "handles incoming events" has no success definition**
No latency window, no failure path, no verification method. Fix: split into (a) bead visible in `bd list` within 60s, (b) failure writes ErrTransient to SyncJournal.

**P1-ACQ-03 — GitHub↔Notion file sync criterion describes direction, not outcome**
"Bidirectional sync" is not verifiable. Fix: two criteria with explicit propagation directions and time bounds.

**P1-ACQ-04 — Three-way merge criterion specifies implementation, not outcome**
"Uses AncestorStore" is not observable. Fix: specify merged content appears in both systems AND SyncJournal records merge result type.

### Adapter Interface Behavioral Contracts (3 P1s from fd-adapter-interface-contracts)

**P1-AIC-01 — HandleEvent() blocking contract missing**
If HandleEvent() blocks during GitHub API calls, the hub's dispatch goroutine stalls, causing all other adapters to stop receiving events. Fix: add criterion "HandleEvent() must not block for more than 5s; long-running operations dispatched to a goroutine before returning."

**P1-AIC-02 — Identity mapping will default to display names (silent corruption vector)**
Open Question #1 offers "config file (YAML)" as simplest without requiring stable IDs. A username change splits the identity silently, routing future events to an unknown sink. Fix: add criterion "identity mapping config uses stable system-native IDs (GitHub numeric user ID, Notion user UUID) as primary keys."

**P1-AIC-03 — Emit() close-on-Stop semantics undocumented**
If Emit() channel is not closed when Stop() returns, hub's ranging goroutine leaks. During graceful shutdown this causes the 30s drain timeout to expire, SIGKILL to fire, and the SyncJournal flush to be skipped — losing in-flight state. Fix: add criterion "each adapter's Stop() closes its Emit() channel before returning."

### Conflict Resolution Correctness (3 P1s from fd-bidirectional-sync-conflicts)

**P1-BSC-02 — LWW clock source not specified**
External-system timestamps (Notion API, GitHub events, FS mtime) can skew by minutes. A 3-minute clock skew means 3 minutes of valid writes are silently overwritten. Fix: LWW decisions use interop's receive-time monotonic clock, not originating-system timestamps.

**P1-BSC-03 — F7 migration does not populate AncestorStore from interkasten WAL**
Without WAL → AncestorStore conversion, the first post-migration sync triggers false conflicts on every previously-synced entity. At scale (months of interkasten history), this is hundreds of spurious conflicts requiring manual resolution. Fix: add F7 criterion for ancestor store population from interkasten WAL before first sync run.

**P1-BSC-04 — No per-adapter-pair conflict resolution policy**
SyncJournal is described as a "neutral arbiter" but its arbitration logic is unspecified. Beads-authoritative-for-status and Notion-authoritative-for-content require different policies. A single global tiebreaker will be wrong for at least one pair. Fix: conflict resolution policy must be per-adapter-pair and configurable in interop config.

### Feature Ordering (3 P1s from fd-scope-containment + fd-dependency-ordering, converging)

**P1-SC-01 / DO-01 — F3 criterion 3 silently requires F4+F5 complete (2/2 agents)**
"Repo files: bidirectional sync of markdown files with Notion pages" requires F5 (fsnotify) and F4 (Notion adapter) both running. Listed as an F3 criterion with no sequencing guard. Fix: annotate F3 criterion 3 as dependent on F4+F5 complete; F3 can close criteria 1, 2, 4-7 independently.

**P1-SC-02 / DO-02 — F7 verification requires all adapters complete (2/2 agents)**
F7 "post-migration verification" requires all adapters running. Listed after F6 with no prerequisite declaration. Teams starting F7 in parallel with F2-F5 will produce an unverifiable migration tool. Fix: add "Prerequisites: F1-F5 complete" to F7.

**P1-DO-03 — F1→F2-F5 integration test dependency not stated**
F2-F5 adapters can be unit-tested with mocked bus/journal, but cannot integration-test without F1's EventBus and SyncJournal running. Not stated. Fix: add a "Feature Ordering" section declaring F1 as the integration prerequisite for F2-F5.

---

## Key P2 Findings (Selected)

**P2-BSC-05 — CollisionWindow catches early conflicts; late-arriving events (>5s apart) bypass it entirely.** The three-way merge is the definitive conflict detector; CollisionWindow is a latency optimization. The PRD does not state this relationship, leaving the impression that CollisionWindow IS the conflict detector.

**P2-BSC-06 — Block-level debounce (2s) and CollisionWindow (5s) have an undocumented invariant**: debounce must be < collision window TTL or debounced events bypass collision detection. Currently safe (2s < 5s) but not documented as a constraint.

**P2-SC-03 — F6 bundles MCP server (infra) and Claude Code plugin (UX) into one feature** with different failure modes and different owners. A plugin naming collision (easy given monorepo autodiscovery) blocks both. Split into F6a/F6b.

**P2-SC-04 — F4 "port interkasten's Notion sync" scope is unstated.** The Problem section mentions 27 MCP handlers. Porting all 27 is potentially months of work. Day-1 scope must be enumerated explicitly.

**P2-SC-05 — Three-lane priority dispatch (express/urgent/routine) is in the Architecture section** but not in F1 acceptance criteria. Either add a criterion or move it to day-2 non-goals.

**P2-DO-04 — F4 and F5 share a markdown file entity model.** Parallel development without a shared schema definition will produce incompatible event payloads for the same entity type.

**P2-AIC-06 — Beads adapter's "CLI exclusively" constraint is a convention, not enforced.** Add a criterion: beads adapter package has no import of any Dolt library (verifiable with `go mod graph`).

---

## Missing Features Audit (from flux-review findings)

The PRD's Architecture section includes the key flux-review findings:

| Finding | Status |
|---------|--------|
| SyncJournal (neutral conflict arbiter, SQLite) | Included in Architecture + F1 |
| CollisionWindow (5s TTL) | Included in Architecture + F1 |
| AncestorStore (first-class persisted component) | Included in Architecture + F1 |
| Event type with SchemaVersion + RoutingHints | Included in Architecture |
| Three-lane priority dispatch | In Architecture only — missing from F1 criteria |
| Full-sync reconciliation (6h) | Referenced in Open Question #4 — not in any feature criteria |
| Per-adapter-pair conflict policy | **Missing** — not in Architecture or any feature |
| LWW clock source (interop receive-time) | **Missing** — not specified anywhere |
| AncestorStore migration from interkasten WAL | **Missing** — not in F7 criteria |

Three of the nine core flux-review primitives are absent from acceptance criteria. The reconciliation schedule (Open Question #4) is deferred but should be added to F1 or F2 as a criterion.

---

## Recommended PRD Amendments

### Must-fix before implementation begins (P0 + P1s)

1. **F1 criterion 6**: Replace with restart-persistent AncestorStore test (P0-1)
2. **F1 acceptance criteria**: Add HandleEvent() ≤5s blocking contract (P1-AIC-01)
3. **F1 acceptance criteria**: Add Emit() closes-on-Stop contract (P1-AIC-03)
4. **F1 acceptance criteria**: Add LWW uses interop receive-time (P1-BSC-02)
5. **F1 acceptance criteria or Architecture**: Add per-adapter-pair conflict policy config (P1-BSC-04)
6. **F2 acceptance criteria**: Add identity mapping requires stable IDs (P1-AIC-02)
7. **F2 criterion 3**: Split into (a) bead visible in 60s + (b) failure writes ErrTransient (P1-ACQ-02)
8. **F3 criterion 3**: Add sequencing annotation (requires F4+F5 complete) (P1-SC-01/DO-01)
9. **F3 criterion 3**: Split into explicit GitHub→Notion and Notion→GitHub propagation criteria (P1-ACQ-03)
10. **F4 criterion 5**: Replace "uses AncestorStore" with observable outcome definition (P1-ACQ-04)
11. **F7**: Add "Prerequisites: F1-F5 complete" (P1-SC-02/DO-02)
12. **F7**: Add ancestor store population from interkasten WAL (P1-BSC-03)
13. **PRD**: Add "Feature Ordering" section with explicit dependency graph (P1-DO-03)

### Should-fix before sprint planning (P2s)

14. **F4**: Enumerate day-1 Notion handler scope vs deferred (P2-SC-04)
15. **F6**: Split into F6a (MCP server) + F6b (Claude Code plugin) (P2-SC-03)
16. **Architecture / F1**: Clarify three-lane dispatch as day-1 or day-2 (P2-SC-05)
17. **F4+F5**: Define shared MarkdownFileEntity schema before parallel development (P2-DO-04)
18. **Architecture**: Document debounce < CollisionWindow TTL invariant (P2-BSC-06)
19. **F1**: Add SyncJournal WAL mode + durability criterion (P2-ACQ-08)
20. **F1**: Add reconciliation schedule (6h full-sync) as a criterion (Open Question #4 resolution)

### Optional polish (P3s)

21. Add GitHub App creation as a setup step with owning feature (P2-DO-06)
22. Define Notion multi-workspace token resolution order (P3-ACQ-10)
23. Add `interop conflicts list` CLI criterion to F6 (P3-SC-08)

---

## Section Heat Map

| PRD Section | P0 | P1 | P2 | Agents Reporting |
|-------------|----|----|-----|------------------|
| F1 — Core Daemon | 1 | 4 | 4 | all 5 |
| F2 — Beads Adapter | 0 | 2 | 1 | ACQ, AIC, DO |
| F3 — GitHub Adapter | 0 | 2 | 1 | ACQ, SC, DO |
| F4 — Notion Adapter | 0 | 1 | 2 | ACQ, BSC, SC, DO |
| F5 — Filesystem | 0 | 0 | 2 | ACQ, DO |
| F6 — MCP + Plugin | 0 | 0 | 2 | ACQ, SC, DO |
| F7 — Migration | 0 | 2 | 1 | BSC, SC, DO |
| Architecture | 0 | 2 | 3 | AIC, BSC, SC |
| Open Questions | 0 | 1 | 1 | AIC, SC |

F1 is the heaviest single point of risk — it has the only P0 and 4 of the 12 P1s. Most of these are criteria gaps rather than design flaws: the right components are named (AncestorStore, SyncJournal, CollisionWindow) but their behavioral contracts are not captured in verifiable acceptance criteria.

---

## Conflicts Between Agents

**F3 criterion 3 dependency** — fd-scope-containment (SC-01) and fd-dependency-ordering (DO-01) independently identified the same issue: F3 criterion 3 requires F4+F5 complete without stating it. Finding is confirmed by 2/5 agents; treat as P1 with high confidence.

**F7 ordering constraint** — fd-scope-containment (SC-02) and fd-dependency-ordering (DO-02) independently confirmed F7 cannot be verified in parallel with adapters. Same convergence, same P1 classification.

No agent conflicts detected — no agent downgraded a finding from another.

---

## Individual Agent Reports

- [fd-acceptance-criteria-quality](./fd-acceptance-criteria-quality.md) — 4 P1s, 4 P2s, 2 P3s: criteria testability across all features
- [fd-adapter-interface-contracts](./fd-adapter-interface-contracts.md) — 3 P1s, 3 P2s, 2 P3s: Go interface behavioral contracts and identity mapping
- [fd-bidirectional-sync-conflicts](./fd-bidirectional-sync-conflicts.md) — 1 P0, 3 P1s, 3 P2s, 1 P3: sync correctness, LWW clocks, ancestor store, migration
- [fd-scope-containment](./fd-scope-containment.md) — 2 P1s, 4 P2s, 2 P3s: implicit feature scope, F4 porting scale, F6 bundling
- [fd-dependency-ordering](./fd-dependency-ordering.md) — 3 P1s, 3 P2s, 2 P3s: F1→F2-F5 ordering, shared entity schema, infrastructure ownership
