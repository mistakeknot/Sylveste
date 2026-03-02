# fd-intercom-tenant-isolation — Security Review

**Reviewer:** fd-intercom-tenant-isolation
**Date:** 2026-03-02
**Scope:** Multi-tenant isolation, session boundary violations, path traversal, state bleed
**Codebases:** `apps/intercom/` (Rust/Node) and `research/hermes_agent/gateway/` (Python reference)

---

## Executive Summary

The intercom codebase has a well-designed tenant isolation architecture at several layers (group_folder path validation in Node, IPC message authorization in Rust). However, five concrete issues were found across the two codebases, ranging from a P1 scheduler routing bug that can cause task output delivery to the wrong group's JID, to a P2 race window in the GroupRegistry sync that could allow unauthorized IPC sends, to P3 informational gaps. No P0 issues were found — the critical path traversal defenses in `group-folder.ts` are correct and the HashMap key usage in `queue.rs` is sound.

---

## Area 1: GroupQueue HashMap — group_jid normalization and aliasing

**Files:** `apps/intercom/rust/intercomd/src/queue.rs`, `apps/intercom/src/group-queue.ts`

### Finding 1.1 — P3: No JID normalization before insertion (informational)

**Severity:** P3

The Rust `GroupQueue.get_or_insert()` (queue.rs:64) and the TypeScript `GroupQueue.getGroup()` (group-queue.ts:38) both insert JIDs verbatim into the backing `HashMap`/`Map`. There is no normalization (e.g., lowercase, trim, canonical form) before the key is stored or looked up.

```rust
// queue.rs:64
fn get_or_insert(&mut self, jid: &str) -> &mut GroupState {
    self.groups
        .entry(jid.to_string())
        .or_insert_with(GroupState::default)
}
```

For currently observed JID patterns (`tg:123456`, `wa:+49...@s.whatsapp.net`) this is not an issue — the upstream message loop feeds them raw from Postgres where they were stored normalized. However, if a future caller supplies a JID with trailing whitespace or a mixed-case prefix, a second independent entry would be created, allowing two concurrent containers for the same chat — breaking the serialization guarantee.

**Recommendation:** Add a `normalize_jid()` helper that lowercases the prefix component and trims whitespace, called at every entry point (`enqueue_message_check`, `enqueue_task`, `register_process`, `send_message`, `notify_idle`, `kill_group`, `is_active`, `close_stdin`).

---

### Finding 1.2 — P3: `waiting_groups` deduplication uses linear scan

**Severity:** P3

`waiting_groups: VecDeque<String>` (queue.rs:57) uses `contains()` to deduplicate (queue.rs:126, 199). If `max_concurrent` is hit frequently with many groups, this is O(n) per enqueue. Not a security issue, but combined with a JID normalization bug (1.1) could cause a group to appear twice in the waiting queue.

---

## Area 2: Hermes pairing approval vs. intercom unregistered group task output

**Files:** `research/hermes_agent/gateway/pairing.py`, `apps/intercom/rust/intercomd/src/scheduler_wiring.rs`, `apps/intercom/rust/intercomd/src/message_loop.rs`

### Finding 2.1 — P1: Scheduler dispatches tasks to `chat_jid` without verifying group is still registered

**Severity:** P1

In `scheduler_wiring.rs`, the `build_task_callback` closure (scheduler_wiring.rs:64) enqueues the task keyed by `chat_jid`:

```rust
// scheduler_wiring.rs:64-66
tokio::spawn(async move {
    queue_for_enqueue.enqueue_task(&chat_jid, &task_id, task_fn).await;
});
```

But the `GroupQueue` in `queue.rs` is keyed by JID and has **no concept of registered groups** — it accepts any JID passed to it. The group membership check only happens _inside_ `run_scheduled_task` (scheduler_wiring.rs:87):

```rust
// scheduler_wiring.rs:85-98
let group = {
    let g = groups.read().await;
    match g.values().find(|g| g.folder == task.group_folder) {
        Some(group) => group.clone(),
        None => {
            error!(..., "scheduled task references unknown group folder");
            log_and_update(pool, &task, ...Some("Unknown group folder")...).await;
            return;
        }
    }
};
```

The vulnerability window: between when a task is created in Postgres and when it runs, the registered group can be deleted. The task is already enqueued in `GroupQueue` keyed to `chat_jid`. When `run_scheduled_task` exits early (unknown group), it calls `log_and_update` — but `queue.reset_group(&chat_jid)` is still called via the `run_task` wrapper (queue.rs:464). This means the task _slot_ was consumed for the deleted group's JID. Critically, if that JID was subsequently re-registered for a _different group folder_, the queue entry is now under a JID owned by a different tenant. The task output (which already returned early here) would not bleed, but the queue occupancy for that JID does.

More critically: Hermes has an explicit pairing/approval model in `pairing.py` that gates which users/groups can trigger agent runs. Intercom has no equivalent gate on scheduled task dispatch — any row in `scheduled_tasks` with `status='active'` and `next_run <= now()` will fire, regardless of whether the group is still pairable/trusted. There is no intercom equivalent of Hermes's `is_approved()` check at task fire time.

**Recommendation:** Before enqueuing a task into GroupQueue, verify the group_folder exists in the registered groups map. Fail fast in `build_task_callback` before `tokio::spawn`, not inside `run_scheduled_task`. This ensures no queue slot is consumed for orphaned tasks.

---

### Finding 2.2 — P2: Node dual-write path creates tasks with caller-supplied group_folder without server-side validation

**Severity:** P2

The `/v1/db/tasks` endpoint (db.rs:220-232, main.rs:437) accepts `ScheduledTask` from the Node host and calls `pool.create_task(&task)` without validating that `task.group_folder` matches a registered group:

```rust
// db.rs:220-232
pub async fn create_task(
    State(pool): State<Option<PgPool>>,
    Json(task): Json<ScheduledTask>,
) -> impl IntoResponse {
    let pool = match require_pool(&pool) { ... };
    match pool.create_task(&task).await {
        Ok(()) => (StatusCode::OK, ...).into_response(),
        ...
    }
}
```

If the Node host is compromised or a client sends a crafted request to intercomd, a task can be created referencing any `group_folder`. When the scheduler fires it, `run_scheduled_task` will fail with "Unknown group folder" (safe), but the entry exists in the DB and could be used to probe group folder names by observing whether the error path fires.

**Recommendation:** Add validation in `create_task` (db.rs) that the `group_folder` exists in the registered groups list, or document that intercomd's HTTP endpoints are trusted only from localhost.

---

## Area 3: `write_ipc_message` / `write_close_sentinel` — path traversal via group_folder

**Files:** `apps/intercom/rust/intercomd/src/queue.rs`, `apps/intercom/src/group-queue.ts`, `apps/intercom/src/group-folder.ts`

### Finding 3.1 — P2: Rust queue.rs uses group_folder from GroupState without path validation

**Severity:** P2

In `queue.rs`, the `group_folder` stored in `GroupState` (queue.rs:48) is set via `register_process()` (queue.rs:244):

```rust
pub async fn register_process(
    &self,
    group_jid: &str,
    container_name: &str,
    group_folder: Option<&str>,
) {
    let mut inner = self.inner.lock().await;
    let state = inner.get_or_insert(group_jid);
    state.container_name = Some(container_name.to_string());
    if let Some(folder) = group_folder {
        state.group_folder = Some(folder.to_string());  // no validation here
    }
}
```

This `group_folder` is then used directly in `write_ipc_message` (queue.rs:279) and `write_close_sentinel` (queue.rs:500-503) to construct filesystem paths:

```rust
// queue.rs:279
inner.data_dir.join("ipc").join(folder).join("input")

// queue.rs:500-503
fn write_close_sentinel(data_dir: &Path, group_folder: &str) {
    let input_dir = data_dir.join("ipc").join(group_folder).join("input");
    ...
}
```

There is **no path traversal check** in `write_ipc_message` or `write_close_sentinel`. If `group_folder` contains `../other_group` or `../../etc`, the path join will escape the `data/ipc/` base directory.

By contrast, the Node TypeScript side has strong protection in `group-folder.ts`:

```typescript
// group-folder.ts:5-6
const GROUP_FOLDER_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/;
const RESERVED_FOLDERS = new Set(['global']);

export function isValidGroupFolder(folder: string): boolean {
    if (!folder) return false;
    if (folder !== folder.trim()) return false;
    if (!GROUP_FOLDER_PATTERN.test(folder)) return false;
    if (folder.includes('/') || folder.includes('\\')) return false;
    if (folder.includes('..')) return false;
    if (RESERVED_FOLDERS.has(folder.toLowerCase())) return false;
    return true;
}
```

And `ensureWithinBase()` (group-folder.ts:24) provides defense-in-depth.

The Rust queue does not have an equivalent of either check.

**Attack path during migration period:** The `/v1/db/sessions/set` endpoint (db.rs:444-458, main.rs:448) accepts `group_folder` from the Node host. If a group_folder value of `../other_group` is passed in a `SetSessionRequest`, it gets stored in Postgres's `sessions` table. When that session is later loaded in `scheduler_wiring.rs` (line 104-108) and passed into a container via `ContainerInput`, the container itself uses it to write to its IPC input directory. The Rust queue's `write_close_sentinel` would then write `_close` outside the intended namespace.

**Recommendation:** Add an `is_valid_group_folder(folder: &str) -> bool` function to `intercom-core` mirroring the TypeScript logic, and call it in:
- `queue.rs::register_process()` before storing `group_folder`
- `write_ipc_message()` before constructing the path
- `write_close_sentinel()` before constructing the path
- `db.rs::set_session()` before storing the value
- `db.rs::create_task()` before storing the value

---

### Finding 3.2 — P3: `write_close_sentinel` and `write_ipc_message` lack `ensureWithinBase` style confirmation

**Severity:** P3

Even after adding `is_valid_group_folder()` validation, the Rust path construction should add a defense-in-depth check equivalent to the TypeScript `ensureWithinBase()` — verifying that `canonical(data_dir.join("ipc").join(folder))` starts with `canonical(data_dir.join("ipc"))`. This prevents canonicalization-based bypasses (symlinks, Unicode normalization differences) that pass the regex but escape at the OS level.

---

## Area 4: Hermes mirror.py session collision — DM vs. group chat

**Files:** `research/hermes_agent/gateway/mirror.py`, `research/hermes_agent/gateway/session.py`

### Finding 4.1 — P2: `_find_session_id` picks most-recently-updated session for a (platform, chat_id) pair — no chat_type discrimination

**Severity:** P2

`mirror.py::_find_session_id()` (mirror.py:64-99) matches sessions by `origin.chat_id == chat_id` for a given platform, returning the most recently updated match:

```python
# mirror.py:82-98
for _key, entry in data.items():
    origin = entry.get("origin") or {}
    entry_platform = (origin.get("platform") or entry.get("platform", "")).lower()
    if entry_platform != platform_lower:
        continue
    origin_chat_id = str(origin.get("chat_id", ""))
    if origin_chat_id == str(chat_id):
        updated = entry.get("updated_at", "")
        if updated > best_updated:
            best_updated = updated
            best_match = entry.get("session_id")
```

There is no check on `chat_type` ("dm" vs. "group"). In Telegram, a user's DM `chat_id` (e.g., `1108701034`) is a distinct positive integer from group `chat_id` values (negative integers like `-100...`). However:

1. On Discord and Slack, DM channel IDs and server channel IDs are drawn from the same numeric namespace (snowflake IDs).
2. If a future platform adapter stores `chat_id` as a human-readable name rather than numeric ID (already seen in WhatsApp where `chat_type` is used in the session key), two sessions could share the same `chat_id` string with different `chat_type`s.

The result: a cron job delivering to `platform:chat_id` could write a mirror record to the _wrong_ session (the DM session when the target was a group, or vice versa) if those sessions happen to have matching `chat_id` values. The actual message delivery via the platform adapter goes to the correct target (the bug only affects session mirroring/transcript coherence), but contaminating a session transcript with another group's output constitutes session bleed.

**Recommendation:** Add `chat_type` as a tiebreaker in `_find_session_id`. When `chat_id` matches but `chat_type` differs, prefer the entry whose `chat_type` matches the expected type for the context (e.g., favor "group" when `chat_id` is negative for Telegram). In the intercom port, this should be encoded in the session key itself rather than relying on post-hoc matching.

---

### Finding 4.2 — P3: `_generate_session_key` in session.py does not include `chat_type` for non-WhatsApp DMs — collision possible between DM and group sessions sharing a chat_id

**Severity:** P3

`session.py::_generate_session_key()` (session.py:338-349):

```python
def _generate_session_key(self, source: SessionSource) -> str:
    platform = source.platform.value
    if source.chat_type == "dm":
        if platform == "whatsapp" and source.chat_id:
            return f"agent:main:{platform}:dm:{source.chat_id}"
        return f"agent:main:{platform}:dm"  # all non-WA DMs share one key
    else:
        return f"agent:main:{platform}:{source.chat_type}:{source.chat_id}"
```

Non-WhatsApp DM sessions use the key `agent:main:telegram:dm` (no `chat_id`). This is intentional (single DM bot owner). But a Telegram group with `chat_id = "dm"` would collide with this key. The `source.chat_id = "dm"` case is unlikely to arise from the Telegram adapter, but worth noting since the intercom port should not reproduce this pattern.

---

## Area 5: SessionResetPolicy (Hermes) vs. intercom per-group session reset

**Files:** `research/hermes_agent/gateway/config.py`, `research/hermes_agent/gateway/session.py`, `apps/intercom/rust/intercomd/src/scheduler_wiring.rs`, `apps/intercom/rust/intercomd/src/message_loop.rs`

### Finding 5.1 — P2: Intercom has no per-group session reset policy; sessions persist indefinitely unless explicitly deleted

**Severity:** P2

Hermes implements `SessionResetPolicy` (config.py:59-87) with four modes — `daily`, `idle`, `both`, `none` — configurable per-platform and per-session-type. The `_should_reset()` check (session.py:351-390) enforces these policies on every `get_or_create_session()` call, and critically checks `_has_active_processes_fn` to avoid resetting a session mid-task.

Intercom's session model (persistence.rs:244-247, main.rs:258-261) is a flat `group_folder → session_id` map with no TTL or reset policy:

```rust
// persistence.rs — sessions table
CREATE TABLE IF NOT EXISTS sessions (
    group_folder TEXT PRIMARY KEY,
    session_id TEXT NOT NULL
);
```

Sessions are only reset by explicit `/reset` command (via `CommandEffect::ClearSession`, main.rs:800-808). There is no idle timeout, no daily reset boundary, and no per-group reset policy. This means:

1. A long-lived session accumulates context indefinitely, leaking older messages and tool results to future container invocations from the same group.
2. If group ownership changes (a JID is re-registered to a different tenant under the same folder name — possible during migration), the new tenant inherits the old session ID. The container will load the previous tenant's conversation history from the Claude session store.
3. The `max_concurrent` idle container blocking check in Hermes (`_has_active_processes_fn`, session.py:356-360) has no equivalent in intercom — the session can be reset even while a container is active (via `/reset` command → `kill_group` → `delete_session`). This creates a race where the container's final output writes a new `session_id` (scheduler_wiring.rs:162-165) after the session was deleted, resurrecting a stale session entry.

**Recommendation:** Port Hermes's `SessionResetPolicy` to intercom: add `reset_policy`, `idle_minutes`, and `last_active` columns to the `sessions` table (or a separate `session_policies` table keyed by `group_folder`). Enforce reset checks in `process_group.rs` and `scheduler_wiring.rs` before loading session. Add a guard in `CommandEffect::ClearSession` that checks `is_active(&chat_jid)` before deleting.

---

### Finding 5.2 — P1: Scheduler uses `chat_jid` as GroupQueue key but `group_folder` as session key — they are not the same thing

**Severity:** P1

In `scheduler_wiring.rs` (line 64-66), the task is enqueued into `GroupQueue` keyed by `chat_jid`:

```rust
queue_for_enqueue.enqueue_task(&chat_jid, &task_id, task_fn).await;
```

But inside `run_scheduled_task`, the session is loaded by `group_folder` (line 104-108):

```rust
let session_id = if task.context_mode == "group" {
    let s = sessions.read().await;
    s.get(&task.group_folder).cloned()
} else {
    None
};
```

And the `notify_idle` callback (line 185-188) calls:
```rust
queue.notify_idle(&chat_jid).await;
```

This is a **tenant isolation bug**: `chat_jid` is the Telegram/WhatsApp chat identifier (e.g., `tg:123`). `group_folder` is the logical group identifier (e.g., `team-eng`). They are different namespaces. Multiple groups can theoretically share a `chat_jid` (two different `RegisteredGroup` rows with the same `jid` are prevented by the `PRIMARY KEY` constraint, but the queue itself has no such constraint). More importantly:

- The session is stored under `group_folder` in Postgres.
- The queue slot (and `notify_idle`) is indexed by `chat_jid`.
- `queue.is_active(&chat_jid)` returning `true` says "a container is running for this chat JID" — but that container may be serving a _different task/group_ than what `run_scheduled_task` is processing if two groups share the same JID (impossible with current DB schema, but possible if the DB constraint is relaxed or during migration).

More practically: after container completion, `notify_idle(&chat_jid)` writes a `_close` sentinel to `data/ipc/{group_folder}/input/` (via `GroupState.group_folder` which was set by `register_process()`). The `group_folder` in `GroupState` comes from the container runner, not from the task record. If `register_process()` is called with a `group_folder` that doesn't match the task's `group_folder` (because the JID maps to a different group now), the `_close` sentinel is written to the wrong directory.

**Recommendation:** The queue should be keyed by `group_folder`, not `chat_jid`. `chat_jid` can be stored in `GroupState` for Telegram send operations but must not be the primary key. This is the root cause of the `notify_idle` mismatch.

---

## Area 6: Migration-period dual-write — group_folder='../other_group' bypass

**Files:** `apps/intercom/rust/intercomd/src/db.rs`, `apps/intercom/rust/intercomd/src/main.rs`

### Finding 6.1 — P2: All DB endpoints accept group_folder from Node host without server-side sanitization

**Severity:** P2

During the migration period, the Node host dual-writes session and task entries via HTTP to intercomd's `/v1/db/` routes. The following endpoints accept a caller-supplied `group_folder` string and pass it directly to Postgres without any validation:

- `POST /v1/db/sessions/set` → `SetSessionRequest { group_folder, session_id }` → `pool.set_session(&req.group_folder, ...)` (db.rs:444-458)
- `POST /v1/db/sessions/get` → `GetSessionRequest { group_folder }` → `pool.get_session(&req.group_folder)` (db.rs:424-436)
- `POST /v1/db/sessions/delete` → `DeleteSessionRequest { group_folder }` → `pool.delete_session(&req.group_folder)` (db.rs:477-489)
- `POST /v1/db/tasks` → `ScheduledTask { group_folder, ... }` → `pool.create_task(&task)` (db.rs:220-232)
- `POST /v1/db/tasks/group` → `GetTasksForGroupRequest { group_folder }` → `pool.get_tasks_for_group(&req.group_folder)` (db.rs:258-270)

All persistence queries use parameterized Postgres queries (safe from SQL injection), but the `group_folder` value is stored verbatim. When the scheduler later fires a task with `group_folder='../other_group'`, `run_scheduled_task` will fail to find a registered group with that folder name (safe) — but the session lookup at line 104 will use the crafted folder name to look up a session that may belong to a different group. Additionally, any write that does succeed (e.g., `set_session('../other_group', sid)`) creates a Postgres row that can pollute unrelated lookups via `get_all_sessions()`.

The intercomd HTTP server binds to a localhost port and is only called by the trusted Node host (per architecture docs). However:
1. If the Node host itself has a code path that reflects user-supplied input into group_folder (e.g., via a WhatsApp message payload that influences folder selection), this becomes remotely exploitable.
2. During migration, the Node host has its own `isValidGroupFolder()` check (group-folder.ts:8-16), but this is a client-side guard; intercomd should not rely on it.

**Recommendation:** Add a Rust `is_valid_group_folder(folder: &str) -> bool` validation function in `intercom-core` and call it in all DB endpoint handlers that accept `group_folder`. Return HTTP 400 on invalid input. This creates defense-in-depth regardless of Node host behavior.

---

## Summary Table

| # | Area | Severity | File:Line | Description |
|---|------|----------|-----------|-------------|
| 2.1 | Scheduler/pairing | P1 | `scheduler_wiring.rs:64`, `scheduler.rs:153` | Tasks dispatched without verifying group is still registered; no pairing-equivalent gate |
| 5.2 | Session key mismatch | P1 | `scheduler_wiring.rs:64`, `queue.rs:244` | Queue keyed by chat_jid, session keyed by group_folder — notify_idle sends close to wrong namespace |
| 2.2 | Dual-write task creation | P2 | `db.rs:220` | No group_folder validation on create_task endpoint |
| 3.1 | Path traversal | P2 | `queue.rs:279`, `queue.rs:500` | group_folder from GroupState used in fs path joins without traversal check |
| 4.1 | Mirror session collision | P2 | `mirror.py:64` | DM vs. group session collision on (platform, chat_id) match |
| 5.1 | No session reset policy | P2 | `persistence.rs:244`, `main.rs:800` | Intercom has no per-group idle/daily session reset; session persists across group ownership changes |
| 6.1 | Dual-write group_folder | P2 | `db.rs:444`, `db.rs:220`, `db.rs:258` | All session/task DB endpoints accept group_folder without sanitization |
| 1.1 | JID normalization | P3 | `queue.rs:64`, `group-queue.ts:38` | No JID normalization at insert — whitespace/case variants create duplicate entries |
| 3.2 | Missing ensureWithinBase | P3 | `queue.rs:471`, `queue.rs:500` | No canonical path comparison after group_folder validation |
| 4.2 | Session key DM collision | P3 | `session.py:347` | Non-WA DMs share one session key; group with chat_id="dm" would collide |

---

## Adaptation Opportunities

The following patterns from Hermes gateway are worth porting to intercom:

### 1. `isValidGroupFolder()` as a shared Rust function

The TypeScript `group-folder.ts:isValidGroupFolder()` is the single most portable and high-value defensive primitive. A Rust equivalent in `intercom-core/src/lib.rs` would benefit queue.rs, db.rs, and any future endpoint that accepts folder names. The regex pattern `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` plus the `..` and `/` rejection is directly translatable.

### 2. Hermes `SessionResetPolicy` → intercom per-group policy table

Hermes's three-layer reset priority (`platform override > type override > default`) with `at_hour`, `idle_minutes`, and `mode` fields (config.py:59-87) maps cleanly onto intercom's `registered_groups` table. Adding `session_reset_mode TEXT DEFAULT 'none'` and `session_idle_minutes INTEGER DEFAULT NULL` columns to `registered_groups` would allow the message loop and scheduler wiring to enforce idle resets without a full Hermes-style config system.

### 3. `_has_active_processes_fn` guard pattern

Hermes blocks session resets when a container is active (session.py:357-360). Intercom already has `queue.is_active(jid)` (queue.rs:298). The `/reset` command handler in `main.rs` (apply_command_effects, line 799-808) should check `queue.is_active(&chat_jid).await` before clearing the session, returning an error to the user instead of silently racing with the active container.

### 4. Pairing approval gate for scheduled tasks

Hermes's `PairingStore.is_approved(platform, user_id)` (pairing.py:90-93) is a whitelist gate. Intercom's equivalent would be a `group.allowed` or `group.active` flag in `registered_groups` that the scheduler checks before firing. Currently intercom fires all `status='active'` tasks unconditionally. A `group.pairing_approved BOOLEAN DEFAULT TRUE` column with a scheduler check would close the Hermes parity gap.

### 5. Queue keyed by group_folder, not chat_jid

The Hermes gateway keying model is instructive: sessions in `session.py` are keyed by `session_key` which encodes `platform:type:chat_id` — a stable, normalized identifier that does not change when group metadata changes. Intercom's queue should adopt a similar approach: key `GroupQueue` by `group_folder` (which is stable and validated) and store `chat_jid` as metadata on `GroupState`. This eliminates the P1 notify_idle mismatch and makes the authorization model coherent.
