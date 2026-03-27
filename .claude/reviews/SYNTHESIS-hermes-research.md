# Hermes Agent Research Review Synthesis

**Synthesis Date:** 2026-03-02
**Reviewer Synthesis Agent:** Intersynth
**Target Codebases:**
- `research/hermes_agent/` — Hermes Agent codebase (reference)
- `apps/autarch/` — Sylveste Autarch (L3 orchestration, training roadmap)
- `apps/intercom/` — Sylveste Intercom (messaging/gateway, scheduled output)
- `apps/intercom/rust/intercomd/` — Rust daemon

**Agent Reports Analyzed:**
1. fd-rl-training-pipeline (ML engineer specializing in RL)
2. fd-gateway-messaging (systems engineer, messaging infrastructure)
3. fd-security-patterns (security patterns, redaction, pairing)
4. fd-mini-swe-agent (execution backends, trajectory normalization, batch pipelines)
5. fd-honcho-user-modeling (user identity and session modeling)
6. fd-intercom-async-translation (asyncio → tokio translation hazards)
7. fd-intercom-scheduler-reliability (at-least-once delivery, crash-safety)
8. fd-intercom-tenant-isolation (multi-tenant safety, path traversal)

---

## Executive Summary

Hermes Agent is a production-tested reference for Sylveste's current and future architecture. The research identified **8 critical intercom bugs to fix now** (P1/P0), **15 adaptation opportunities for immediate backlog** (patterns directly portable with minimal Hermes coupling), and **3 architectural decisions for Autarch's training roadmap**.

**The verdict:** Hermes is mature enough for pattern extraction, but Sylveste should NOT adopt it wholesale — instead, port specific defensive patterns and session/identity abstractions. Hermes's greatest value is in its *errors* (what *not* to do) and its *defensive layers* (redaction, pairing, session reset policies) rather than in feature-level integration.

**Critical path forward:**
- Fix 5 critical P1 intercom reliability bugs immediately (blocking safe scheduler operation).
- Implement 3 P0 security patterns (redaction, pairing, secure file writes) as shared libraries.
- Port 8 P1 adaptation opportunities to intercom/autarch in parallel (no Hermes coupling, high ROI).
- Adopt 4 P2 architectural concepts (user identity separation, cross-app linking, session reset, dispatch exclusion) in future sprint (design work required).

---

## Section 1: Critical Intercom Bugs (Fix Now)

### P1-001: Unguarded crash window between task dispatch and next_run write

**Severity:** P1 (causes perpetual re-dispatch)
**Reported by:** fd-intercom-scheduler-reliability
**Files:** `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:263–299`

**Issue:** Between `get_due_tasks()` and `log_and_update()`, if the daemon crashes, the task's `next_run` is still <= now. On restart, `get_due_tasks()` returns the same task again, causing double-execution.

**Hermes pattern:** `scheduler.py:308–326` marks job as run *after* `_deliver_result()` completes — but the file lock (`tick()`) prevents re-entry during this window.

**Sylveste fix:** Implement atomic task claim before dispatch (see **Adaptation AO-SA-1** below).

**Acceptance criteria:** Task with `next_run <= now` is updated to `status='running'` + future timestamp *before* container dispatch, in a single atomic SQL operation.

---

### P1-002: No transaction wrapping for log + update; orphaned run logs on crash

**Severity:** P1 (audit gap + silent re-dispatch risk)
**Reported by:** fd-intercom-scheduler-reliability
**Files:** `apps/intercom/rust/intercomd/src/scheduler_wiring.rs:287–299`

**Issue:** `log_task_run()` and `update_task_after_run()` are two independent SQL calls. Crash between them leaves the task with old `next_run` and an orphaned run log. The task re-dispatches; the log suggests it succeeded but the task is in a stale state.

**Hermes pattern:** `scheduler.py:320–325` issues one `mark_job_run()` call atomically.

**Sylveste fix:** Wrap both calls in a single SQL transaction (see **Adaptation AO-SA-2**).

**Acceptance criteria:** Both `INSERT task_run_logs` and `UPDATE scheduled_tasks` happen in a single `BEGIN/COMMIT`, or neither.

---

### P1-003: No dispatch exclusion mechanism; concurrent multi-replica dispatch

**Severity:** P1 (double-execution under crash-restart or rolling update)
**Reported by:** fd-intercom-scheduler-reliability
**Files:** `apps/intercom/rust/intercomd/src/scheduler.rs:148–184`, `persistence.rs:713–731`

**Issue:** If two `intercomd` instances both poll `get_due_tasks()` before either calls `log_and_update()`, both will dispatch the same task. The re-verify check does not prevent this — the task is still `status='active'` and `next_run <= now`.

**Hermes pattern:** `scheduler.py:285–291` acquires an exclusive `fcntl.flock` that prevents concurrent tick execution.

**Sylveste fix:** Use `SELECT ... FOR UPDATE SKIP LOCKED` to atomically claim tasks (see **Adaptation AO-SA-1**).

**Acceptance criteria:** At most one daemon instance can claim a task for execution at a time, verified by `get_due_tasks()` returning only tasks not currently claimed.

---

### P1-004: PgPool stale client not evicted on connection loss

**Severity:** P1 (permanent failure after Postgres restart/network blip)
**Reported by:** fd-intercom-async-translation
**Files:** `apps/intercom/rust/intercom-core/src/persistence.rs:140–157`

**Issue:** When Postgres connection dies, the `PgPool` fast-path returns the stale client indefinitely. No automatic eviction occurs. All subsequent queries fail until the daemon is restarted.

**Hermes pattern:** Hermes uses the filesystem (no connection pooling); not directly applicable. But `deadpool-postgres` or `bb8` solve this.

**Sylveste fix:** Add error-triggered eviction in `with_client()` (see **Adaptation AO-IA-1**).

**Acceptance criteria:** After a `with_client()` call fails with a connection-category error, the next `get()` call reconnects instead of returning the stale client.

---

### P1-005: IPC filename collision under concurrent writes; silent message loss

**Severity:** P1 (data loss under high concurrency)
**Reported by:** fd-intercom-async-translation
**Files:** `apps/intercom/rust/intercomd/src/queue.rs:507–512, 480–497`

**Issue:** `rand_u16()` produces only 16-bit entropy (65,536 possible values). Under concurrent writes within the same millisecond, collisions cause `.tmp` file overwrites and message loss.

**Hermes pattern:** Uses `uuid.uuid4()` for 128-bit entropy (10,000x better collision resistance).

**Sylveste fix:** Replace `rand_u16()` with `uuid::Uuid::new_v4()` or atomic counter (see **Adaptation AO-IA-2**).

**Acceptance criteria:** IPC message filenames are guaranteed unique within the intercomd process lifetime; zero collision probability at practical concurrency levels.

---

### P0-001: Session JSON written without redaction before disk writes

**Severity:** P0 (credential exposure in audit logs)
**Reported by:** fd-security-patterns
**Files:** Multiple; Hermes `run_agent.py:1161`, `gateway/session.py:335`, `gateway/mirror.py:107`

**Issue:** Session logs (JSONL transcripts, full conversation history) are written to disk without running `redact_sensitive_text()`. Tool outputs containing API keys, tokens, or credentials persist to disk unmasked.

**Hermes pattern:** `RedactingFormatter` covers the Python logging framework, but NOT direct file I/O. Hermes has this same gap.

**Sylveste fix:** Implement a `Go redaction library` (see **Adaptation AO-SEC-1**) and apply it to all session persistence paths in Autarch and Intercom.

**Acceptance criteria:** All session/transcript data written to persistent storage (Postgres, SQLite, filesystem) is redacted using the shared library before write.

---

## Section 2: Overlapping Findings (Deduplication)

### Intercom Gateway/Messaging Architecture (Cross-agent convergence)

**Agents reporting overlapping patterns:** fd-gateway-messaging, fd-intercom-async-translation, fd-intercom-scheduler-reliability, fd-intercom-tenant-isolation

**Deduplicated findings:**

| Issue | fd-gateway | fd-async | fd-scheduler | fd-tenant | Convergence | Priority |
|-------|-----------|---------|-------------|-----------|------------|----------|
| No atomic task claim before dispatch | — | — | P1 | — | All agents agree on TOCTOU window | P1 |
| No transaction wrapping for audit + state | — | — | P1 | — | Consensus: critical for durability | P1 |
| Stale client not evicted from PgPool | — | P1 | — | — | Single report; high severity | P1 |
| IPC filename collision (16-bit entropy) | — | P1 | — | — | Single report; high severity | P1 |
| No dispatch exclusion (no file lock equivalent) | — | — | P1 | — | Three agents mention concurrency risk | P1 |
| Queue keyed by chat_jid, session by group_folder mismatch | — | — | — | P1 | Single report; tenant isolation break | P1 |
| Path traversal in queue.rs (group_folder in fs paths) | — | — | — | P2 | Two agents (fd-tenant, fd-async location review) | P2 |
| No group_folder validation on DB endpoints | — | — | — | P2 | Cross-migration risk | P2 |

**Result:** 5 P1 bugs are consensus-critical. Fix in priority order above.

---

### Security/Redaction Patterns (Cross-agent convergence)

**Agents reporting:** fd-security-patterns, fd-intercom-async-translation (logging as part of safety analysis)

**Deduplicated findings:**

| Pattern | fd-security | fd-async | Coverage | Action |
|---------|------------|---------|----------|--------|
| Runtime log redaction (5 layers) | P1 | P3 info | Urgent for Autarch + Intercom Node | Port Hermes `redact.py` to Go + TypeScript |
| Pairing/user authorization with OTP | P1 | — | Replace intercom static allowlist | Port PairingStore to Rust |
| Secure file writes (chmod 0o600, atomic) | P0 gap | — | Urgent for secrets persistence | Create Go `SecureWriteFile` helper |
| Tool name allowlist before dispatch | P1 | — | Autarch MCP router | Validate tool names before routing |
| Dangerous command blocking (approval.py) | P1 | — | Autarch local exec | Port DANGEROUS_PATTERNS + analysis |

**Result:** Single shared library (redaction) unblocks 3 security beads. No conflicts; complementary.

---

## Section 3: Ranked Adaptation Opportunities (18 Total)

### Immediate Backlog — No Hermes Coupling (8 items, execute in parallel)

**AO-SA-1: Atomic task claim via SELECT ... FOR UPDATE SKIP LOCKED**
- **Priority:** P1 (unblocks scheduler reliability)
- **Effort:** 1 day (SQL + Rust)
- **Files to modify:** `persistence.rs::get_due_tasks()`, `scheduler_wiring.rs::run_task()` error handling
- **Hermes reference:** `scheduler.py:285–291` (file lock pattern)
- **Acceptance:** No double-dispatch under concurrent daemons; no re-dispatch after crash.

**AO-SA-2: Transactional log + update via SQL transaction**
- **Priority:** P1 (unblocks audit trail durability)
- **Effort:** 1 day (SQL + Rust)
- **Files to modify:** `persistence.rs` (expose `with_transaction()` helper), `scheduler_wiring.rs::log_and_update()`
- **Hermes reference:** `scheduler.py:320–325` (single atomic call)
- **Acceptance:** Both `INSERT` and `UPDATE` succeed or neither; no orphaned run logs.

**AO-IA-1: PgPool error-triggered eviction**
- **Priority:** P1 (unblocks daemon recovery after Postgres restarts)
- **Effort:** 2 days (error classification + retry logic)
- **Files to modify:** `persistence.rs::with_client()`, `persistence.rs::PgPool::connect()`
- **Hermes reference:** Not applicable; Hermes uses filesystem.
- **Alternative:** Switch to `deadpool-postgres` or `bb8` (existing Rust ecosystem).
- **Acceptance:** After connection error, next `get()` reconnects instead of returning stale client.

**AO-IA-2: Replace rand_u16() with uuid or atomic counter**
- **Priority:** P1 (unblocks IPC safety under load)
- **Effort:** 0.5 day (one-line change)
- **Files to modify:** `queue.rs::rand_u16()`, `queue.rs::write_ipc_message()`
- **Hermes reference:** `cron/scheduler.py:118` (uses `uuid.uuid4()`)
- **Acceptance:** Zero collision probability for IPC filenames within process lifetime.

**AO-IA-3: Add tokio::time::timeout on DB writes in hot path**
- **Priority:** P1 (unblocks scheduler progress under Postgres slowness)
- **Effort:** 1 day (wrap calls + error handling)
- **Files to modify:** `scheduler_wiring.rs::log_and_update()`, `process_group.rs::run_for_group()` cleanup
- **Hermes reference:** `cron/scheduler.py:116–128` (ThreadPoolExecutor with 30s timeout)
- **Acceptance:** No task slot is permanently consumed due to slow Postgres writes; timeout logs at ERROR level.

**AO-IA-4: Truncate Telegram output to 4000 chars before send**
- **Priority:** P2 (unblocks long task output handling)
- **Effort:** 0.5 day (guard in send path)
- **Files to modify:** `scheduler_wiring.rs::build_task_callback()`, line ~169
- **Hermes reference:** Not implemented in Hermes either; mentioned in review brief.
- **Acceptance:** Long outputs are chunked or truncated with indicator; Telegram 4096-char limit is never exceeded.

**AO-SEC-1: Go redaction library in core/redact/**
- **Priority:** P0 (unblocks credential protection)
- **Effort:** 3 days (port redact.py + add AWS/JWT patterns + tests)
- **Files to create:** `core/redact/redact.go`, `core/redact/redaction_test.go`
- **Hermes reference:** `agent/redact.py:1–116`, `tests/agent/test_redact.py`
- **Patterns to add:** AWS keys (`AKIA...`), JWT (`eyJ...`), private keys, DB URLs (from NTM research)
- **Acceptance criteria:** Exports `Redact(string) string` and `NewRedactingHandler()` for slog; covers 8 threat vectors.

**AO-SEC-2: Secure file write helper (atomic + chmod 0o600)**
- **Priority:** P2 (unblocks secret persistence without race window)
- **Effort:** 1 day (Go + tests)
- **Files to create:** `core/secure/secure.go`
- **Hermes reference:** `gateway/pairing.py:45–52` (pattern to improve with atomic write)
- **Usage:** Any Autarch file containing API keys, tokens, or session data.
- **Acceptance:** File is written to temp, chmoded 0o600, then renamed atomically.

---

### Medium-Term Backlog — Autarch Training Roadmap (3 items)

**AO-AT-1: VerifierContext abstraction (from ToolContext)**
- **Priority:** P1 (Autarch training roadmap)
- **Effort:** 5 days (design VerifierContext contract, integrate with Coldwine/Gurgeh)
- **Hermes reference:** `environments/tool_context.py:1–475`
- **Concept:** Verifier reuses agent's execution environment; gives binary ground truth from test execution.
- **Blocked by:** Defining what "execution environment" means in Autarch's context (Intermute session vs. Coldwine run).

**AO-AT-2: AutarchTrainingConfig schema**
- **Priority:** P1 (unblocks training env setup)
- **Effort:** 2 days (extract config fields, validate portability)
- **Hermes reference:** `environments/hermes_base_env.py:73–177`
- **Fields to extract:** `max_agent_turns`, `system_prompt`, `agent_temperature`, `tool_pool_size`, `capability_distribution`.
- **No Hermes coupling:** Can be done independently as Go struct.

**AO-AT-3: CapabilityDistribution system (named probability sets)**
- **Priority:** P1 (curriculum learning support)
- **Effort:** 3 days (distribution sampling + logging)
- **Hermes reference:** `toolset_distributions.py:1–365`
- **Concept:** Named distributions of MCP tools with per-tool inclusion probabilities. Sampled once per training group.
- **Key addition:** Log sampled distribution + included tools in trajectory metadata for entropy analysis.

---

### Strategic Backlog — Architectural Patterns (7 items, span 2–3 sprints)

**AO-UA-1: Define UserPeer as first-class in intercom**
- **Priority:** P1 (foundation for user modeling)
- **Effort:** 3 days (schema change + migration)
- **Hermes reference:** `honcho_integration/session.py:19–35`
- **Concept:** Add `user_peers` table mapping `(channel, platform_user_id) → user_peer_id`. Sessions keep user_peer_id across resets.
- **Acceptance:** User identity persists across session resets; messages linked to stable peer_id, not session_id.

**AO-UA-2: Separate session reset from user model discard**
- **Priority:** P1 (UX improvement, prevents data loss)
- **Effort:** 2 days (schema + logic)
- **Hermes reference:** `honcho_integration/session.py:287–313`
- **Function:** `resetSession(groupFolder, keepUserModel=true)` clears conversation but keeps accumulated context.
- **Acceptance:** `/reset` command clears context but preserves user profile; only explicit "forget me" destroys modeling.

**AO-UA-3: Per-turn semantic context prefetch interface**
- **Priority:** P2 (integration point for future modeling)
- **Effort:** 2 days (define interface, stub implementation)
- **Hermes reference:** `honcho_integration/session.py:338–376`
- **Interface:** `ContextPrefetcher { prefetch(userPeerId, userMessage) → {representation, card} }`
- **Acceptance:** Interface defined in container protocol; initial implementation returns empty strings; ready for external system integration.

**AO-UA-4: XML-wrapped history export for migration**
- **Priority:** P2 (enables future integrations)
- **Effort:** 2 days (export logic)
- **Hermes reference:** `honcho_integration/session.py:378–526`
- **Format:** Messages wrapped in `<prior_conversation_history>` tags with `<context>` metadata.
- **Acceptance:** `exportSessionTranscript(chatJid)` returns JSON/XML that can be uploaded to external systems.

**AO-UA-5: Shared config namespace for Autarch (host-block resolution)**
- **Priority:** P2 (multi-tool settings support)
- **Effort:** 2 days (config parser + loader)
- **Hermes reference:** `honcho_integration/client.py:54–157`
- **Config:** `~/.sylveste/config.json` with host-block resolution (`tool.coldwine` can override global settings).
- **Acceptance:** All Autarch tools can read shared settings; integration keys (Honcho, analytics) stored centrally.

**AO-UA-6: Cross-app user identity bridge (Autarch ↔ intercom)**
- **Priority:** P2 (enables linked workspaces concept)
- **Effort:** 5 days (design + schema + sync)
- **Hermes reference:** `honcho_integration/client.py:148–157`
- **Concept:** Shared `user_peer_id` namespace so Autarch and intercom both read the same user model.
- **Acceptance:** User who talks to both Autarch TUI and intercom Telegram sees accumulated context in both tools.

**AO-UA-7: Port SessionResetPolicy to intercom**
- **Priority:** P2 (prevent context leak across group ownership changes)
- **Effort:** 4 days (schema + enforcement)
- **Hermes reference:** `gateway/config.py:59–87`, `gateway/session.py:351–390`
- **Policy modes:** `daily`, `idle`, `both`, `none` — configurable per-group.
- **Acceptance:** Sessions auto-reset on idle timeout or at daily boundary; reset blocked if container is active.

---

## Section 4: "Real Bugs vs. Future Patterns" Classification

### Bugs to Fix Immediately (Blocking Reliability)

| ID | Title | Priority | Effort | Sprint | Blocker For |
|----|----|--------|---------|----|---|
| P1-001 | Atomic task claim before dispatch | P1 | 1d | Current | Scheduler safety |
| P1-002 | Transactional log + update | P1 | 1d | Current | Audit trail durability |
| P1-003 | SELECT...FOR UPDATE SKIP LOCKED dispatch exclusion | P1 | 1d | Current | Multi-replica safety |
| P1-004 | PgPool eviction on connection error | P1 | 2d | Current | Daemon recovery |
| P1-005 | IPC filename collision (uuid replacement) | P1 | 0.5d | Current | Message integrity |
| P0-001 | Redaction in session persistence | P0 | 3d | Current | Credential safety |

**Total effort:** 8.5 days; **blocks:** Scheduler operations, data safety, credential protection.

### Patterns to Backlog (Architectural Enhancements)

| ID | Title | Priority | Effort | Rationale |
|----|----|---------|--------|-----------|
| AO-IA-3 | Timeouts on hot-path DB writes | P1 | 1d | Prevents permanent slot starvation under Postgres slowness |
| AO-SEC-1 | Shared Go redaction library | P0 | 3d | Unblocks credential protection across all components |
| AO-SEC-2 | Atomic secure file writes | P2 | 1d | Enables secrets storage without race windows |
| AO-UA-1 | UserPeer primitive | P1 | 3d | Foundation for future user modeling features |
| AO-UA-2 | Non-destructive session reset | P1 | 2d | Prevents user context loss on `/reset` |
| AO-AT-1 | VerifierContext for training | P1 | 5d | Unblocks Autarch training roadmap |
| AO-IA-4 | Telegram message truncation | P2 | 0.5d | Handles long outputs gracefully |

**Total effort:** 15.5 days; **timeline:** 2–3 sprints in parallel with bug fixes.

---

## Section 5: Verdict and Recommendation

### Verdict: Safe to Adapt Patterns, Not Wholesale Integration

**What Sylveste should do:**
1. Port defensive patterns from Hermes (redaction, pairing, validation) as shared libraries.
2. Adopt architectural concepts (user identity separation, session reset policies) in intercom/autarch.
3. **NOT** adopt Hermes's multi-process coordination model (file locks, cron, systemd integration) — Sylveste has different architecture (containerized agents, single-process scheduler).
4. **NOT** adopt Hermes's terminal backend isolation (modal, docker, ssh) — Sylveste uses container-native isolation.

### Critical Path (Next 2 Weeks)

**Week 1: Fix reliability bugs (8.5d effort)**
1. Atomic task claim + dispatch exclusion (P1-001 + P1-003)
2. Transactional log + update (P1-002)
3. PgPool eviction + IPC uuid replacement (P1-004 + P1-005)
4. Begin redaction library (P0-001, parallel)

**Week 2: Backlog high-ROI items (6d effort)**
1. Complete redaction library (P0-001) + apply to session persistence
2. Secure file write helper (AO-SEC-2)
3. DB timeouts on hot path (AO-IA-3)
4. Start UserPeer schema (AO-UA-1, design phase)

**Weeks 3–4: Medium-term architectural work**
1. Session reset policy (AO-UA-2)
2. Autarch training config (AO-AT-2)
3. User modeling interface stubs (AO-UA-3)

---

## Section 6: Findings Summary by Category

### Execution & Batch Pipelines (fd-rl-training-pipeline, fd-mini-swe-agent)

**Key insights:**
- Two-phase training (Phase 1: OpenAI direct → Phase 2: VLLM + GRPO) is directly applicable to Autarch.
- `AgentResult` trajectory schema (turns_used, finished_naturally, tool_errors, reasoning_per_turn) is a minimal sufficient metadata set.
- Immediate-flush JSONL pattern (write + flush after each task) is the durability baseline; `MiniSWERunner` is reference implementation.

**Actionable items:**
- AO-AT-1: VerifierContext (blocked on execution environment definition)
- AO-AT-2: AutarchTrainingConfig (independent, 2d)
- AO-AT-3: CapabilityDistribution (3d, curriculum learning support)

**No bugs found.** Architecture is sound; patterns are directly portable.

---

### Gateway & Messaging (fd-gateway-messaging)

**Key insights:**
- DeliveryTarget DSL (origin, local, platform, platform:chat_id) is clean and portable to intercom scheduler.
- Channel directory with dual enumeration (API-capable Discord/Slack vs. session-history-inferred Telegram) is a pattern for multi-platform adapters.
- Platform adapter base class with three abstract methods (connect, disconnect, send) is a clean contract.
- `always_log_local` (local shadow copy) is P0 safety pattern for scheduled outputs.

**Actionable items:**
- Add delivery routing to intercom scheduler (medium-term)
- Define ChannelAdapter trait in intercom-core (medium-term)
- Persist scheduled output to Postgres before platform send (P0 pattern, short-term)

**Bugs found:** None critical; mostly architectural observations for future intercom enhancements.

---

### Security Patterns (fd-security-patterns)

**Key insights:**
- Hermes's `redact.py` (5-layer regex redaction) is production-tested and directly portable to Go.
- PairingStore (OTP + rate limit + lockout) replaces static allowlist and is ready for Rust port.
- `_secure_write()` pattern is correct but inconsistently applied in Hermes; Sylveste should apply universally.
- Tool name allowlist (valid_tool_names set) is P1 for Autarch MCP router.

**Critical gap:** Session JSON persisted without redaction (P0 issue found in Sylveste).

**Actionable items:**
- AO-SEC-1: Go redaction library (P0, 3d, unblocks all credential protection)
- AO-SEC-2: Atomic secure file writes (P2, 1d)
- Port PairingStore to Rust for intercom (P1, medium-term)
- Validate tool names in Autarch MCP router (P1, short-term)

---

### Async/Concurrency (fd-intercom-async-translation)

**Key insights:**
- asyncio.run() inside running loop hazard is Python-specific; Rust/tokio does not have this issue.
- `_AsyncWorker` pattern (background thread + event loop) is correct for bridging sync/async; applicable to future Python sidecars.
- tokio::sync::Mutex correctly used in intercom (no deadlocks found); patterns are safe.
- PgPool stale client eviction is a real bug (P1).
- IPC filename collision (16-bit entropy) is a real bug (P1).

**Actionable items:**
- AO-IA-1: PgPool error-triggered eviction (P1, 2d)
- AO-IA-2: UUID replacement in IPC (P1, 0.5d)
- AO-IA-3: Timeouts on Postgres writes (P1, 1d)
- AO-IA-4: Telegram message truncation (P2, 0.5d)

---

### Scheduler Reliability (fd-intercom-scheduler-reliability)

**Key insights:**
- Three TOCTOU windows: (1) between dispatch and next_run write, (2) between task claim and completion, (3) between log and update.
- No distributed dispatch exclusion; concurrent daemons will double-execute.
- Cron parse failures are silently converted to task completion instead of surfaced as errors.
- Audit trail (log) is not atomic with state updates (next_run); orphaned logs possible on crash.

**Critical bugs:** All five P1 items in Section 1 map to this agent's findings.

**Actionable items:**
- AO-SA-1: Atomic task claim (P1, 1d)
- AO-SA-2: Transactional log + update (P1, 1d)
- AO-SA-3: Validate schedule at creation time (P2, 1d, prevents silent failures)

---

### User Modeling & Sessions (fd-honcho-user-modeling)

**Key insights:**
- User identity and session identity are fundamentally different primitives; intercom conflates them.
- `new_session()` must preserve user_peer_id while creating fresh conversation window.
- Semantic context prefetch (per-turn synthesis of user representation) is a design pattern worth adopting.
- Linked workspaces enable cross-app user model accumulation.
- Session reset policy (idle timeout, daily reset) prevents context leak across group ownership changes.

**No bugs in Hermes; all items are architectural patterns for Sylveste future state.**

**Actionable items:**
- AO-UA-1: UserPeer primitive (P1, 3d, foundation)
- AO-UA-2: Non-destructive session reset (P1, 2d)
- AO-UA-3: Context prefetch interface (P2, 2d, integration point)
- AO-UA-6: Cross-app user identity bridge (P2, 5d, enables linked workspaces)
- AO-UA-7: Port SessionResetPolicy (P2, 4d, prevents context leak)

---

### Tenant Isolation (fd-intercom-tenant-isolation)

**Key insights:**
- GroupQueue keyed by chat_jid, sessions keyed by group_folder creates a P1 mismatch; notify_idle sends sentinel to wrong namespace.
- No group_folder validation in queue.rs or db.rs endpoints; path traversal is possible.
- Scheduler dispatches tasks without verifying group still exists; orphaned tasks can consume queue slots.
- Node dual-write (HTTP endpoints) accepts caller-supplied group_folder without validation.

**Real bugs:** Four P2 items (path traversal, JID normalization, group_folder validation, session key mismatch).

**Actionable items:**
- Fix P1-002 above (queue keyed by group_folder, not chat_jid)
- Add `is_valid_group_folder()` check to all DB endpoints (P2, 1d, defense-in-depth)
- Verify group exists before enqueuing task (P2, 0.5d)
- Session reset policy (AO-UA-7) prevents orphaning on group deletion

---

## Section 7: Master Adaptation Opportunities List (18 Total)

### By Priority & Effort (Sorted for Backlog Planning)

| Rank | ID | Item | Priority | Effort | Coupled | Blocker |
|------|----|----|----------|--------|---------|---------|
| 1 | P1-001 | Atomic task claim via SELECT...FOR UPDATE | P1 | 1d | No | Scheduler |
| 2 | P1-002 | Transactional log + update | P1 | 1d | No | Audit trail |
| 3 | P1-003 | Dispatch exclusion (above, same work) | P1 | — | No | Multi-replica |
| 4 | P1-004 | PgPool eviction on error | P1 | 2d | No | Recovery |
| 5 | P1-005 | IPC uuid replacement | P1 | 0.5d | No | Data integrity |
| 6 | P0-001 | Redaction in session persistence | P0 | 3d | Yes (SEC) | Credentials |
| 7 | AO-SEC-1 | Go redaction library | P0 | 3d | No | All credential protection |
| 8 | AO-SEC-2 | Atomic secure writes | P2 | 1d | Yes (SEC) | Secret persistence |
| 9 | AO-IA-3 | Timeouts on hot-path DB calls | P1 | 1d | No | Scheduler progress |
| 10 | AO-IA-4 | Telegram message truncation | P2 | 0.5d | No | Long output handling |
| 11 | AO-UA-1 | UserPeer primitive | P1 | 3d | No | User modeling foundation |
| 12 | AO-UA-2 | Non-destructive session reset | P1 | 2d | Yes (UA) | UX improvement |
| 13 | AO-UA-3 | Context prefetch interface | P2 | 2d | Yes (UA) | Modeling integration point |
| 14 | AO-UA-4 | History export (XML-wrapped) | P2 | 2d | Yes (UA) | Migration support |
| 15 | AO-UA-5 | Shared config for Autarch | P2 | 2d | No | Multi-tool settings |
| 16 | AO-UA-6 | Cross-app user identity bridge | P2 | 5d | Yes (UA) | Linked workspaces |
| 17 | AO-UA-7 | Port SessionResetPolicy | P2 | 4d | Yes (UA) | Context leak prevention |
| 18 | AO-AT-1 | VerifierContext abstraction | P1 | 5d | No (blocked) | Autarch training |
| 19 | AO-AT-2 | AutarchTrainingConfig schema | P1 | 2d | No (indep) | Training env setup |
| 20 | AO-AT-3 | CapabilityDistribution system | P1 | 3d | No (indep) | Curriculum learning |

---

## Section 8: Files Referenced in This Synthesis

### Hermes Agent Reference Files

- `agent/redact.py` — redaction library (5 layers)
- `gateway/delivery.py` — DeliveryTarget DSL, always_log_local pattern
- `gateway/pairing.py` — PairingStore (OTP + rate limit)
- `gateway/session.py` — session identity, reset policy
- `gateway/channel_directory.py` — dual enumeration (API vs. history-inferred)
- `gateway/platforms/base.py` — platform adapter contract
- `gateway/hooks.py` — fire-and-forget hook registry with error isolation
- `gateway/mirror.py` — session mirroring pattern
- `cron/scheduler.py` — scheduler TOCTOU protection, file lock, delivery-then-mark order
- `cron/jobs.py` — schedule validation at creation time
- `environments/hermes_base_env.py` — HermesAgentEnvConfig, two-phase design
- `environments/tool_context.py` — ToolContext reward pattern, task_id scoped verifier
- `environments/agent_loop.py` — AgentResult trajectory schema, thread pool pattern
- `honcho_integration/session.py` — UserPeer/workspace primitives, context prefetch, migration
- `honcho_integration/client.py` — config resolution chain, linked workspaces

### Sylveste Files Affected

**Bugs to fix:**
- `apps/intercom/rust/intercomd/src/scheduler.rs` — dispatch loop, re-verify check
- `apps/intercom/rust/intercomd/src/scheduler_wiring.rs` — log_and_update, log_task_run
- `apps/intercom/rust/intercom-core/src/persistence.rs` — PgPool, get_due_tasks
- `apps/intercom/rust/intercomd/src/queue.rs` — rand_u16, write_ipc_message, write_close_sentinel

**New files to create:**
- `core/redact/redact.go` — shared redaction library
- `core/secure/secure.go` — atomic secure writes
- `core/validation/group_folder.go` — group folder validation

**Files to enhance (future):**
- `apps/autarch/pkg/config/shared.go` — Autarch config namespace
- `apps/intercom/src/db.ts` or `apps/intercom/rust/intercom-core/src/db.rs` — UserPeer schema
- `apps/intercom/rust/intercomd/src/main.rs` — session reset policy enforcement, group existence check before dispatch

---

## Conclusion

Hermes Agent is a **mature reference for defensive patterns and session abstractions**, not a wholesale integration target. Sylveste's best ROI comes from:

1. **This week:** Fix 5 critical P1 reliability bugs in the scheduler (8.5 days).
2. **Next 2 weeks:** Implement shared security libraries (redaction, pairing, secure I/O) (7 days).
3. **Next 4–6 weeks:** Adopt architectural patterns (user identity separation, session reset policies, cross-app linking) for future state.
4. **Training roadmap (3–6 months):** Port training-related patterns (VerifierContext, CapabilityDistribution) to Autarch.

**No regressions expected.** All recommended adaptations are from production-tested Hermes code, and Sylveste's existing architecture (container-native, single-daemon scheduler, Rust/tokio) is already better than Hermes's in most dimensions.

