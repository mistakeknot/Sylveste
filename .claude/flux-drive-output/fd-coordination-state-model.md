# fd-coordination-state-model: Hyperspace AGI Coordination Patterns for Demarch

**Reviewer**: Distributed systems engineer (CRDT, consistency, failure recovery)
**Scope**: Coordination state model, file reservation architecture, bead claim semantics, convergence properties
**Exclusions**: Research pipeline, snapshot publishing, plugin evolution (covered by other reviewers)

---

## Finding 1: Interlock Is Already a Single-Writer CRDT — Loro Would Add Complexity Without Eliminating the Real Failure Mode

**Verdict: SKIP replacing interlock with Loro CRDTs**
**Priority: N/A (not recommended)**

### Analysis

The ANALYSIS.md proposes replacing interlock's file-based reservation system with Loro CRDTs. After reading the actual interlock implementation, this recommendation is based on a misunderstanding of the current architecture.

Interlock is NOT file-based. It is an HTTP API backed by SQLite:

- `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/sqlite.go` — SQLite with pure Go driver (no CGO), embedded schema, migration chain
- `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/resilient.go` — `ResilientStore` wrapping every operation with `CircuitBreaker + RetryOnDBLock`
- `/home/mk/projects/Demarch/interverse/interlock/internal/client/client.go` — HTTP client connecting to intermute at `127.0.0.1:7338` or via Unix socket

The reservation model (`Reserve`, `CheckConflicts`, `ReleaseReservation`, `SweepExpired`) is a centralized lock manager with TTL-based expiration. This is fundamentally a single-writer problem on a single machine. CRDTs solve multi-writer convergence across network partitions — a problem Demarch does not have.

**What CRDTs would actually cost:**
1. Loro is a Rust library. Integrating it into intermute (Go) requires either CGO bindings or a sidecar process, adding build complexity and a new failure mode.
2. The existing SQLite store already handles concurrent access via `RetryOnDBLock` (exponential backoff on `SQLITE_BUSY`) and `CircuitBreaker` (threshold=5, reset=30s). These are the correct primitives for single-machine concurrency.
3. CRDTs would require giving up read-your-writes consistency, which the negotiation protocol depends on (e.g., `pollNegotiationThread` in `tools.go` line 935 polls for thread responses expecting them to appear after being written).

**What actually breaks:**
The only documented failure in interlock is intermute being unavailable (`"intermute unavailable"` errors in the client). This is a process lifecycle issue, not a state convergence issue. The `fallbackLock` in `claim.go` (lines 323-345) already handles this with `os.Mkdir`-based atomic locking — a proven pattern for single-machine coordination.

### The Real Problem

The sweeper in `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/sweeper.go` runs a background goroutine with TTL-based cleanup. If intermute crashes and restarts, reservations survive in SQLite and the sweeper resumes cleanup. This is correct behavior. The issue is when intermute is not running at all — then interlock falls back to polling an unreachable HTTP server. This is a process supervision problem, not a CRDT problem.

---

## Finding 2: Beads Claim State IS Semantically a CRDT, but Replacing Dolt Is Wrong — Fix the Process Management Instead

**Verdict: SKIP replacing Dolt with CRDTs. ADAPT the claim protocol to be more crash-resilient.**
**Priority: P1 (fix the real zombie problem)**

### Analysis

The ANALYSIS.md correctly identifies that bead claim/close/unclaim operations are convergent:
- `claimed_by` is a Last-Writer-Wins Register (LWW-Register)
- `claimed_at` is a timestamp that acts as a version vector
- `status` transitions (in_progress -> closed) are monotonic (a G-Counter pattern)

But the semantic fit with CRDTs does not mean CRDTs are the right implementation. The real failure mode documented in MEMORY.md:

```
# [2026-03-12] Migrated to v0.60 --shared-server mode
- v0.58 idle-monitor zombie bug (#2367) was recurring despite systemd mitigations
```

The problem chain is:
1. Dolt's `idle-monitor` spawns a background process
2. The idle-monitor becomes a zombie (PID still running, not accepting connections)
3. `bd` commands hang trying to connect to the zombie server
4. Recovery requires: kill zombie, kill dolt servers, re-init from JSONL backup

This is documented in `/home/mk/projects/Demarch/.beads/recover.sh` (lines 12-21):
```bash
# 1. Kill all idle-monitors across all projects
ps aux | grep "bd dolt idle-monitor" | grep -v grep | awk '{print $2}' | xargs -r kill
# 2. Kill all dolt sql-servers
ps aux | grep "dolt sql-server" | grep -v grep | awk '{print $2}' | xargs -r kill
```

**Why CRDTs would not fix this:**
The zombie problem is in the Dolt process manager, not in the state model. Replacing Dolt with a CRDT data structure means you still need a process to serve that CRDT state. If that process zombies, you have the same problem. The solution is fixing process supervision, which the v0.60 `--shared-server` migration already attempted.

### Concrete Recommendation: Watchdog + Direct SQLite

Instead of CRDTs, consider:

1. **Make beads state queryable without a running server.** The JSONL backup (`/home/mk/projects/Demarch/.beads/backup/issues.jsonl`) is already the recovery fallback. Make it the primary read path for `bd state` and `bd show`. Reserve the Dolt server for writes only. This eliminates the "query hangs on zombie" failure mode.

2. **Add a health-check wrapper to `bd` invocations.** In `clavain-cli` (`claim.go` lines 214-215), the `runBD("state", beadID, "claimed_by")` call can hang if the Dolt server is zombied. Add a 2-second timeout and fall back to JSONL parsing.

3. **Make claim state dual-write.** Write `claimed_by` and `claimed_at` to both Dolt and a flat file (e.g., `.beads/claims/<bead_id>.json`). The flat file survives Dolt crashes. The close-and-sync script (`/home/mk/projects/Demarch/.beads/close-and-sync.sh`) already does dual-write to JSONL — extend this pattern to claims.

---

## Finding 3: The 3-Layer Stack (GossipSub -> CRDT -> GitHub) Maps to Demarch as (intermute WebSocket -> SQLite -> git)

**Verdict: ADAPT — Demarch already has an analogous 3-layer stack, but the real-time layer is underutilized**
**Priority: P2**

### Analysis

Hyperspace's stack:
```
GossipSub (~1s)  ->  CRDT Leaderboard (~2min)  ->  GitHub Archive (~5min)
  real-time           convergent state              durable record
```

Demarch's existing stack:
```
intermute WebSocket  ->  SQLite (intermute)    ->  git (beads JSONL + code)
  real-time               immediate                 ~manual push
```

The architecture at `/home/mk/projects/Demarch/core/intermute/internal/ws/gateway.go` shows intermute already has a WebSocket gateway (`Broadcaster` interface used by the sweeper). This is the equivalent of GossipSub for a single machine — agents can subscribe to reservation events in real time.

**What Demarch is missing vs. Hyperspace:**

1. **The real-time layer is fire-and-forget.** The `emitSignal` function in `tools.go` (line 968) runs `bash script eventType text` in the background and ignores the result. Agents don't subscribe to coordination events — they poll (`negotiateRelease` polls with `time.Sleep(negotiationPollInterval)` at line 577). Hyperspace agents react to GossipSub events immediately.

2. **The convergent state layer is not queryable by topic.** `TopicMessages` exists but is a pull API. Hyperspace's CRDT leaderboard is a shared data structure that all agents read from. Demarch's equivalent would be a shared "coordination state" document that agents read before starting work — like Hyperspace's `snapshots/latest.json`.

3. **The durable layer requires manual push.** `push.sh` uses `dolt sql -q "CALL dolt_push('origin', 'main')"`. Hyperspace uses GitHub Actions for automated archival. Demarch should auto-push beads state on every close (the close-and-sync script does this, but it's not the default path — agents often just run `bd close`).

### Concrete Recommendation

- **P2**: Make intermute WebSocket subscriptions available to interlock clients. When agent A reserves a file, agent B should receive a push notification without polling. The infrastructure exists (`Broadcaster` in the sweeper) but is not exposed to MCP tool consumers.
- **P3**: Create a periodic "coordination snapshot" (agent list, active reservations, active sprints) as a JSON file that agents read at session start. This is Hyperspace's `snapshots/latest.json` adapted for local use.

---

## Finding 4: "No Cold Start" Is Already Solved by sprint-find-active, but the Recovery Path Has Race Conditions

**Verdict: ADAPT the existing recovery to be idempotent**
**Priority: P1**

### Analysis

Loro's "no cold start" means: a new node reads the full CRDT state on connect. In Demarch, the equivalent is:

1. `cmdSprintFindActive` in `/home/mk/projects/Demarch/os/Clavain/cmd/clavain-cli/sprint.go` (line 228) queries intercore for active runs
2. For each run, it checks `isBeadClosed` and auto-cancels stale runs (line 261-263)
3. It resolves titles from `bd show` (line 271)

This is a "catch up on startup" pattern — the new session discovers what's already in progress. But the implementation has race conditions:

**Race 1: Concurrent sprint-find-active calls.** Multiple sessions starting simultaneously can both find the same stale run and both try to cancel it. `runIC("run", "cancel", runID)` at line 263 is not idempotent — the second call may fail or produce unexpected state.

**Race 2: Claim-then-register is not atomic.** In `cmdSprintClaim` (claim.go lines 49-150):
```go
// Acquire lock
_, lockErr := runIC("lock", "acquire", "sprint-claim", beadID, "--timeout=500ms")
// ... check agents, register new session agent ...
// Also set bd claim for cross-session visibility (ignore errors)
_ = cmdBeadClaim([]string{beadID, sessionID})
```
The `ic lock` acquisition and the `bd set-state` write are two separate systems. If the process crashes between them, the ic lock is held but no bead claim exists (or vice versa). The `fallbackLock` (mkdir-based) at line 73 makes this worse — it can leave orphan lock directories in `/tmp/intercore/locks/`.

**Race 3: Heartbeat refresh window.** `isClaimStale` in `claim.go` (line 22) uses a 2700-second (45-minute) threshold. But `cmdBeadHeartbeat` (line 287) only refreshes if the caller owns the claim. If the heartbeat fails (bd unavailable), the claim appears stale even though the session is still active. Another session can steal it.

### Concrete Recommendation

**P1**: Make `cmdSprintClaim` use a single-system claim check instead of dual-system (ic + bd). Currently it:
1. Acquires ic lock (or fallback mkdir lock)
2. Queries ic run agents
3. Sets bd state

All three are separate failure domains. Consolidate to: check intermute reservation (single HTTP call) + set bd state (single bd call). The ic agent tracking is useful metadata but should not gate the claim.

**P1**: Add idempotent cancellation to `sprint-find-active`. Before calling `runIC("run", "cancel", runID)`, check the run's current status. If already cancelled, skip.

---

## Finding 5: Commit-Reveal and Cryptographic Verification Are Overkill, but TTL-Based Heartbeat Verification Is Valuable

**Verdict: SKIP cryptographic verification. KEEP and improve TTL-based heartbeats.**
**Priority: P3**

### Analysis

Hyperspace's pulse verification is a 7-step commit-reveal protocol designed to prove that agents on untrusted machines actually performed computation. This solves the Sybil problem in a multi-party network where operators have incentives to fake work.

Demarch has none of these problems:
- All agents run on a single machine under one operator's control
- There is no incentive to fake work (the operator pays for compute)
- Session identity is established by `CLAUDE_SESSION_ID` environment variable, not cryptographic keys

**What IS valuable from the "proof of work" concept:**

The current heartbeat system in `cmdBeadHeartbeat` (claim.go line 287) only proves the agent is alive and can execute `bd set-state`. It does not prove the agent is making progress. Hyperspace's pulse proves compute happened, not just liveness.

Demarch already has a richer signal: token spend tracking in `cmdSprintReadState` (sprint.go lines 426-429):
```go
var tokensSpent int64
if tokenErr == nil {
    tokensSpent = tokenAgg.InputTokens + tokenAgg.OutputTokens
}
```

If `tokensSpent` has not increased since the last heartbeat, the agent is alive but not working. This is a stronger liveness signal than pure heartbeat.

### Concrete Recommendation

**P3**: Add a "progress heartbeat" that reports `tokensSpent` delta alongside the timestamp refresh. If an agent has been claimed for >15 minutes with zero token delta, flag it as potentially stuck (not just stale). This is the single-operator equivalent of Hyperspace's compute verification — proving the agent is working, not just resident.

---

## Finding 6: Per-Agent Branches Would Create Git Merge Conflicts That Worktrees Already Avoid

**Verdict: SKIP per-agent branches for code. ADAPT for experiment/artifact isolation only.**
**Priority: P3**

### Analysis

Hyperspace's "never merge to main" model works because agent outputs are independent data files (`run-NNN.json`, `best.json`, `JOURNAL.md`). No agent modifies another agent's data, so branches never conflict.

Demarch agents modify the SAME codebase. Agent A editing `masaq/viewport/viewport.go` and Agent B editing `masaq/breadcrumb/breadcrumb.go` can cause merge conflicts if both agents also update shared imports, go.sum, or test fixtures. Worktrees (Clavain's current isolation model) avoid this by giving each agent a separate working directory on the same branch — conflicts are detected at merge time, not branch time.

The interlock reservation system in intermute is specifically designed to prevent this:
- `CheckConflicts` in `client.go` (line 209) uses glob overlap detection
- `PatternsOverlap` (line 824) checks prefix-based overlap between file patterns
- The negotiation protocol (`negotiate_release`, `respond_to_release`, `force_release_negotiation`) handles the case where two agents need the same file

Per-agent branches would bypass all of this infrastructure. Two agents could both modify `viewport.go` on their respective branches without any conflict detection until merge time, when the damage is already done.

### Where Per-Agent Branches DO Work

For non-code artifacts that Demarch agents produce (experiment results, brainstorm documents, review reports), per-agent branches would provide clean isolation. The flux-drive output at `.claude/flux-drive-output/` is a good candidate — each reviewer's findings are independent files that never need merging.

### Concrete Recommendation

**P3**: For artifact-heavy workflows (interlab campaigns, flux-drive reviews), consider agent-namespaced directories (not branches) within the repo: `.claude/flux-drive-output/fd-<agent-name>.md` already follows this pattern. Keep code changes on trunk. Do not adopt per-agent branches for code modifications.

---

## Finding 7: Interlock's Negotiation Protocol Is More Sophisticated Than Hyperspace's Coordination, but Has an Unrecoverable State

**Verdict: FIX the unrecoverable negotiation state**
**Priority: P0**

### Analysis

The negotiation protocol in `/home/mk/projects/Demarch/interverse/interlock/internal/tools/tools.go` implements a 4-phase protocol:

1. **negotiate_release** (line 448): Send release request with urgency + optional blocking wait
2. **respond_to_release** (line 607): Holder acknowledges (release) or defers with ETA
3. **force_release_negotiation** (line 716): Requester escalates after timeout
4. **CheckExpiredNegotiations** (client.go line 572): Advisory check for timed-out negotiations

This is more sophisticated than anything in Hyperspace (which has no file-level coordination — agents work on independent projects).

**The Unrecoverable State:**

If a negotiation times out and `force_release_negotiation` is called, it releases the holder's reservation and sends a `release-ack` message (tools.go line 751-764). But the holder agent may have already completed its work and released the reservation itself — in which case `ReleaseByPattern` returns 0 (client.go line 556), and the function reports `"already_released"` (tools.go line 769).

The problem: if the holder crashed (session died), its reservations have TTLs that will eventually expire via the sweeper. But the requester doesn't know whether to wait for TTL expiration or force-release. The `CheckExpiredNegotiations` method (client.go line 572) pages through the entire inbox looking for `release-request` messages — this is O(inbox_size) per check. With many agents and many negotiations, this becomes slow.

Worse: if the holder's session is dead and the inbox was never read, the `release-request` message sits unread. The `AckRequired: true` flag on urgent requests (tools.go line 522) means the requester expects an ack. But dead sessions never ack. The stale-ack detection (`FetchStaleAcks`) catches this, but only if the requester polls.

### Concrete Recommendation

**P0**: Add a "session liveness check" to `force_release_negotiation`. Before iterating through threads:
1. Look up the holder's agent registration in intermute
2. Check `LastSeen` timestamp against a liveness threshold (e.g., 5 minutes)
3. If the holder is dead (no heartbeat), skip the timeout validation and release immediately

This avoids the 10-minute normal timeout for agents that have already crashed. The intermute agent `Heartbeat` method (storage.go line 246) already tracks `LastSeen` — it just needs to be queried during force-release.

---

## Summary Table

| # | Hyperspace Technique | Verdict | Priority | Rationale |
|---|---|---|---|---|
| 1 | Loro CRDT for file reservations | **SKIP** | N/A | Interlock already uses centralized SQLite with circuit breaker + retry. CRDTs solve a multi-writer problem Demarch doesn't have. |
| 2 | CRDT for beads issue state | **SKIP** | N/A | Zombie failures are process management bugs, not state convergence bugs. Fix Dolt lifecycle, don't replace the data model. |
| 3 | 3-layer coordination stack | **ADAPT** | P2 | Demarch has the same 3 layers but the real-time layer (WebSocket) is underutilized. Enable push notifications for reservation events. |
| 4 | No cold start / full state on connect | **ADAPT** | P1 | sprint-find-active does this but has race conditions in concurrent startup and non-atomic claim-then-register. |
| 5 | Commit-reveal proof of work | **SKIP** | P3 | Overkill for single operator. Instead, add token-delta tracking to heartbeats to distinguish "alive" from "making progress." |
| 6 | Per-agent branches | **SKIP** | P3 | Would bypass interlock's conflict detection. Keep trunk-based for code. Agent-namespaced directories (already used) are sufficient for artifacts. |
| 7 | N/A (interlock-specific) | **FIX** | P0 | Negotiation force-release should check holder liveness via intermute Heartbeat before waiting for timeout. Dead agents should not block the living. |

## Beads Claim State: Crash-Resilience Recommendations

| Change | Priority | Effort |
|---|---|---|
| Add 2-second timeout to `runBD` calls in `claim.go` | P1 | Low |
| Dual-write claim state to flat file alongside Dolt | P1 | Medium |
| Make `sprint-find-active` cancellation idempotent | P1 | Low |
| Consolidate claim check to single system (drop ic lock requirement) | P2 | Medium |
| Add token-delta to heartbeat for progress tracking | P3 | Low |

## Key Codebase References

- Interlock MCP tools: `/home/mk/projects/Demarch/interverse/interlock/internal/tools/tools.go`
- Interlock HTTP client: `/home/mk/projects/Demarch/interverse/interlock/internal/client/client.go`
- Intermute SQLite storage: `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/sqlite.go`
- Intermute resilience layer: `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/resilient.go`
- Intermute sweeper (TTL cleanup): `/home/mk/projects/Demarch/core/intermute/internal/storage/sqlite/sweeper.go`
- Clavain claim logic: `/home/mk/projects/Demarch/os/Clavain/cmd/clavain-cli/claim.go`
- Clavain sprint management: `/home/mk/projects/Demarch/os/Clavain/cmd/clavain-cli/sprint.go`
- Clavain routing: `/home/mk/projects/Demarch/os/Clavain/scripts/lib-routing.sh`
- Beads recovery script: `/home/mk/projects/Demarch/.beads/recover.sh`
- Beads close-and-sync: `/home/mk/projects/Demarch/.beads/close-and-sync.sh`
- Beads push (Dolt): `/home/mk/projects/Demarch/.beads/push.sh`
- Hyperspace analysis: `/home/mk/projects/Demarch/research/agi-hyperspace/ANALYSIS.md`
- Hyperspace README: `/home/mk/projects/Demarch/research/agi-hyperspace/README.md`
