# fd-gateway-messaging: Hermes Agent Gateway & Messaging Review

**Reviewer role:** fd-gateway-messaging (systems engineer, multi-platform messaging infrastructure, webhook routing, async delivery pipelines)

**Target:** `research/hermes_agent/` — gateway/, cron/, hermes_cli/

**Date:** 2026-03-02

**Out of scope:** RL training pipeline (Atropos), pairing security in depth, session identity/user modeling

---

## Area 1: DeliveryTarget / DeliveryRouter — Address Scheme and Three-Tier Model

### Finding 1.1 — P1: Address scheme is clean and directly portable

**File:** `gateway/delivery.py:28-96`

The `DeliveryTarget` dataclass encodes a three-tier address space using a string DSL:

```
"origin"            → back to the originating chat/platform
"local"             → write to local filesystem only
"telegram"          → platform home channel (resolved at runtime)
"telegram:123456"   → explicit platform:chat_id pair
```

Parsing lives in a single `DeliveryTarget.parse()` classmethod (lines 43–86). The `is_origin` and `is_explicit` flags are separate booleans rather than embedded in the platform value, which keeps serialisation and comparison clean. The `to_string()` method (lines 88–96) is a lossless round-trip for all three tiers.

**Sylveste verdict:** This DSL is a strong candidate for intercom's scheduled-output routing. Intercom currently hardwires delivery to the originating Telegram chat. Adding `"local"` and `"platform:chat_id"` tiers with explicit home-channel resolution would enable cron-style agent outputs to reach arbitrary targets without coupling the scheduler to a running Telegram connection.

### Finding 1.2 — P2: Home-channel fallback silently drops delivery

**File:** `gateway/delivery.py:144-150`

```python
home = self.config.get_home_channel(target.platform)
if home:
    target.chat_id = home.chat_id
else:
    # No home channel configured, skip this platform
    continue
```

When a bare platform name is specified (e.g. `"telegram"`) and no home channel is configured, the target is silently skipped with no log line and no error in the returned `results` dict. This is a silent failure: callers get a success-shaped result with fewer entries than requested.

**Sylveste note:** In a Rust async context, this should be a `Result::Err` variant in the delivery result map, not a silent `continue`. The caller can then surface a warning to the user or fall through to `"local"`.

### Finding 1.3 — P0: `always_log_local` flag is the only delivery safety net

**File:** `gateway/delivery.py:158-163` and `gateway/config.py:151`

```python
if self.config.always_log_local:
    local_key = (Platform.LOCAL, None)
    if local_key not in seen_platforms:
        targets.append(DeliveryTarget(platform=Platform.LOCAL))
```

The `always_log_local = True` default means every cron delivery is written to disk even when it also goes to a messaging platform. This is the only mechanism guaranteeing output is never fully lost. The local write happens inside `_deliver_local()` which is synchronous and never raises; the platform delivery is async and can fail.

**Sylveste verdict:** This "local shadow copy" pattern is a P0 design principle worth preserving in intercom's scheduler. Any scheduled agent output should be persisted to Postgres before attempting platform delivery, giving the system a retry surface.

---

## Area 2: Channel Directory — Lazy-Built Capability Registry

### Finding 2.1 — P1: Dual enumeration strategy cleanly separates API-capable from history-inferred platforms

**File:** `gateway/channel_directory.py:24-60`

```python
for platform, adapter in adapters.items():
    if platform == Platform.DISCORD:
        platforms["discord"] = _build_discord(adapter)
    elif platform == Platform.SLACK:
        platforms["slack"] = _build_slack(adapter)

# Telegram & WhatsApp can't enumerate chats -- pull from session history
for plat_name in ("telegram", "whatsapp"):
    if plat_name not in platforms:
        platforms[plat_name] = _build_from_sessions(plat_name)
```

Discord and Slack expose guild/channel enumeration APIs that return all accessible channels at startup. Telegram and WhatsApp have no such API: the bot only knows about chats it has received a message from. The fallback `_build_from_sessions()` (lines 110–138) mines the sessions.json origin fields for past contacts.

The directory is written to `~/.hermes/channel_directory.json` on first build (startup) and refreshed every 5 minutes by the cron ticker (`gateway/run.py:2123-2128`).

**Sylveste verdict:** The two-strategy pattern is directly applicable to intercom. Discord/Slack adapters can eagerly enumerate; Telegram (already intercom's primary platform) and any future WhatsApp integration must build from session history. The 5-minute refresh cycle is reasonable and should be driven by the Rust scheduler rather than a Python `threading.Event`.

### Finding 2.2 — P2: Slack directory build is a stub

**File:** `gateway/channel_directory.py:91-107`

```python
def _build_slack(adapter) -> List[Dict[str, str]]:
    channels = []
    client = getattr(adapter, "_app", None) or getattr(adapter, "_client", None)
    if not client:
        return _build_from_sessions("slack")
    # ...
    return _build_from_sessions("slack")  # always falls through to sessions
```

Both branches of `_build_slack` return `_build_from_sessions("slack")` — the eager enumeration path for Slack is unimplemented. The `import asyncio / from tools.send_message_tool import _send_slack` comment block is dead code.

**Sylveste note:** Not a concern for intercom (no Slack adapter planned), but flags the principle: any channel directory builder must be proven before being promoted above the session-history fallback.

### Finding 2.3 — P1: `resolve_channel_name` implements a useful three-level fuzzy match

**File:** `gateway/channel_directory.py:156-190`

Exact match → guild-qualified match (`GuildName/channel-name`) → unambiguous prefix match. Critically, the partial match only resolves if it is unique — it returns `None` rather than a wrong guess on ambiguous prefixes. This prevents routing errors from typos in channel names.

**Sylveste verdict:** The resolution hierarchy is worth replicating in intercom for human-readable delivery target specs in scheduled tasks. Currently intercom only accepts numeric IDs.

---

## Area 3: Platform Adapter Base Class — Minimal Contract and Plugin Portability

### Finding 3.1 — P1: Three abstract methods define the minimal contract

**File:** `gateway/platforms/base.py:366-401`

```python
@abstractmethod
async def connect(self) -> bool: ...

@abstractmethod
async def disconnect(self) -> None: ...

@abstractmethod
async def send(self, chat_id: str, content: str,
               reply_to: Optional[str] = None,
               metadata: Optional[Dict[str, Any]] = None) -> SendResult: ...
```

Every platform must implement exactly these three methods. All richer behaviour (`send_image`, `send_voice`, `send_animation`, `send_typing`, `format_message`, `truncate_message`) is implemented in the base class with documented defaults that subclasses override as needed.

**Sylveste verdict:** This is a workable pattern for intercom's plugin model. The intercom Node layer currently has two channel implementations (`channels/telegram.ts`, `channels/whatsapp.ts`) with no shared base type. Defining a `ChannelAdapter` trait in the Rust core with `connect`, `disconnect`, and `send` as the required surface would enable WhatsApp and future Discord adapters to be added without modifying orchestration logic.

### Finding 3.2 — P1: `handle_message` background-task dispatch + interrupt model is architecturally sound

**File:** `gateway/platforms/base.py:563-730`

The base class manages session-level concurrency entirely via `asyncio.Task`. A new message while a handler is active is stored in `_pending_messages[session_key]` and processed after the current handler finishes:

```python
if session_key in self._active_sessions:
    self._pending_messages[session_key] = event
    self._active_sessions[session_key].set()  # interrupt signal
    return
asyncio.create_task(self._process_message_background(event, session_key))
```

The pending message model means at most one queued message per session: a second interrupt while one is already pending would overwrite the earlier queued message (line 582 overwrites `self._pending_messages[session_key]`). This is appropriate for a personal assistant (not a message bus) but is a potential message-loss vector for group chats.

**Sylveste verdict:** Intercom's current model spawns a container per message with no interrupt support. The base-class interrupt model is worth adopting for the IronClaw Rust message loop — especially the `asyncio.Event` interrupt signal, which translates cleanly to a `tokio::sync::Notify`.

### Finding 3.3 — P2: `truncate_message` code-block boundary preservation is production-quality

**File:** `gateway/platforms/base.py:779-867`

The `truncate_message` method splits long responses at word/line boundaries and tracks whether a split falls inside an open triple-backtick code fence. If so, it closes the fence at the chunk boundary and reopens it (with the original language tag) in the next chunk. Chunk indicators `(1/3)` are appended to all chunks when a response spans multiple messages.

This is not trivial to implement correctly; the carry_lang tracking (lines 838-856) handles nested or mismatched fences gracefully by re-scanning each chunk line-by-line.

**Sylveste verdict:** Intercom's streaming accumulator (`StreamAccumulator`) handles real-time Telegram message editing but does not handle message splitting for long final responses. This `truncate_message` implementation should be ported to the Rust Telegram bridge for the non-streaming case and for WhatsApp (which has no edit API).

### Finding 3.4 — P2: `MessageEvent` normalization is a clean inbound abstraction

**File:** `gateway/platforms/base.py:264-309`

```python
@dataclass
class MessageEvent:
    text: str
    message_type: MessageType
    source: SessionSource
    raw_message: Any
    media_urls: List[str]
    reply_to_message_id: Optional[str]
    timestamp: datetime
```

All platform-specific message shapes are normalized to `MessageEvent` before reaching the handler. The `raw_message` field preserves the original for platform-specific edge cases without polluting the normalized type.

**Sylveste verdict:** Intercom currently passes raw Telegram `Update` objects through to the Node layer without normalization. Defining an equivalent `IncomingMessage` struct in `intercom-core` would decouple the orchestration logic from Telegram specifics and simplify adding WhatsApp.

---

## Area 4: HookRegistry Event System — HOOK.yaml Discovery, Wildcard Matching, Error Isolation

### Finding 4.1 — P1: File-system-discovered hooks with HOOK.yaml + handler.py is a clean plugin pattern

**File:** `gateway/hooks.py:53-116`

Hook discovery scans `~/.hermes/hooks/` for directories containing a `HOOK.yaml` manifest and a `handler.py` module. The manifest declares which events the hook subscribes to; the module is loaded with `importlib.util.spec_from_file_location` and `handle` function extracted. Hooks are registered per-event in a `Dict[str, List[Callable]]`.

```yaml
# HOOK.yaml
name: "my_hook"
events: ["agent:start", "command:*"]
```

The dynamic module loading means hooks are sandboxed to their own module namespace (no accidental shared state), and the discovery loop skips malformed hooks with a warning rather than failing the gateway.

**Sylveste verdict:** Intercom's plugin model currently uses Interverse plugins loaded at container build time. The HOOK.yaml discovery pattern is a lightweight alternative for host-side (non-container) event hooks — e.g. notifying a monitoring endpoint on `session:start` or routing specific commands without spawning a container. This is closer to what Interspect does. The two systems address different layers and should not be conflated.

### Finding 4.2 — P1: Wildcard matching uses `base:*` prefix convention, not glob patterns

**File:** `gateway/hooks.py:118-150`

```python
if ":" in event_type:
    base = event_type.split(":")[0]
    wildcard_key = f"{base}:*"
    handlers.extend(self._handlers.get(wildcard_key, []))
```

The wildcard is a single level (`command:*` matches `command:reset` and `command:new`) but does not match deeper nesting (`agent:step:tool` would not match `agent:*`). This is a deliberate simplification — the event taxonomy is shallow (two levels: `category:name`).

**Sylveste verdict:** The `category:name` event taxonomy and single-level wildcard pattern map cleanly to intercom's existing event taxonomy. The pattern is directly adoptable for a host-side event bus if one is added.

### Finding 4.3 — P0: Error isolation is correct — handler exceptions never block the pipeline

**File:** `gateway/hooks.py:143-150`

```python
try:
    result = fn(event_type, context)
    if asyncio.iscoroutine(result):
        await result
except Exception as e:
    print(f"[hooks] Error in handler for '{event_type}': {e}", flush=True)
```

Each handler is individually wrapped in try/except. An exception in one handler does not prevent subsequent handlers from running and does not propagate to the caller of `emit()`. Sync and async handlers are both supported via the `asyncio.iscoroutine` check.

**Sylveste verdict:** The error-isolation principle is P0 for any event system integrated into a message delivery path. This pattern should be replicated verbatim in any Rust event bus using `tokio::task::spawn` per handler with error logging via `tracing::warn`.

---

## Area 5: Session Mirroring and Pairing System

### Finding 5.1 — P1: Mirror-to-session pattern solves cross-origin context coherence

**File:** `gateway/mirror.py:24-61`

```python
def mirror_to_session(
    platform: str, chat_id: str, message_text: str, source_label: str = "cli"
) -> bool:
```

When a cron job or CLI command delivers a message to a Telegram chat, `mirror_to_session` appends a `role: "assistant", mirror: true` record to that session's JSONL transcript and SQLite DB. The next time the user messages that chat, the agent sees the cron-delivered message in its conversation history and can respond coherently.

The lookup `_find_session_id()` (lines 64–99) scans `sessions.json` and selects the most-recently-updated session for the platform+chat_id pair, handling the case where multiple sessions exist for the same chat (e.g. after a reset).

**Sylveste verdict:** This is a P1 pattern for intercom. Currently, when intercomd delivers a scheduled output to a Telegram group, the container session for that group has no record of what was sent. The next message from the user would arrive with a gap in context. Mirroring outbound delivery into the session record (Postgres `messages` table) would close this gap.

### Finding 5.2 — P1: Pairing system provides a cryptographically sound OOB approval flow

**File:** `gateway/pairing.py:1-283`

Key security properties (lines 8-17):
- 8-character codes from a 32-char unambiguous alphabet (no `0/O/1/I`)
- `secrets.choice()` for cryptographic randomness
- 1-hour code TTL with eager cleanup on every code-generation call
- Max 3 pending codes per platform (backpressure against code exhaustion)
- Per-user rate limit: 1 request / 10 minutes (`RATE_LIMIT_SECONDS = 600`)
- Per-platform lockout: 5 failed approvals → 1-hour lockout (`LOCKOUT_SECONDS = 3600`)
- File permissions: `chmod 0600` on all JSON data files via `_secure_write()`

The approval flow: unknown user messages bot → bot generates code and displays it to user → user communicates code to bot owner out-of-band → owner runs `hermes pairing approve <code>` in CLI → user is added to `{platform}-approved.json`.

**Sylveste verdict:** Intercom uses a static allowlist of Telegram user IDs (`config.allowedUsers`). The pairing system is a meaningfully better UX for adding new users and is worth adopting. The crypto primitives (`secrets.choice`, unambiguous alphabet, lockout after failed attempts) are correct and should be ported to Rust using `rand::rngs::OsRng`. The file-based storage is simple and appropriate for a single-node deployment; intercom's Postgres backend could store pairing state in a `pairing_codes` table instead.

### Finding 5.3 — P2: Failed approval attempts are counted per-platform, not per-code

**File:** `gateway/pairing.py:244-255`

```python
def _record_failed_attempt(self, platform: str) -> None:
    fail_key = f"_failures:{platform}"
    fails = limits.get(fail_key, 0) + 1
    limits[fail_key] = fails
    if fails >= MAX_FAILED_ATTEMPTS:
        lockout_key = f"_lockout:{platform}"
        limits[lockout_key] = time.time() + LOCKOUT_SECONDS
        limits[fail_key] = 0  # Reset counter
```

The lockout granularity is per-platform. A single attacker trying random codes on Telegram will lock out all Telegram pairing for 1 hour — including legitimate new users. For a high-user-count deployment, per-code or per-source-IP failure tracking would be more appropriate.

**Sylveste note:** For the personal assistant use case (1-3 users per platform), this is acceptable. Document the limitation explicitly if adapting for multi-tenant use.

---

## Area 6: Cron Job Delivery Routing — How Scheduled Agent Outputs Route to Messaging Targets

### Finding 6.1 — P1: Cron delivery is a two-phase system: run then route

**File:** `cron/scheduler.py:57-139`

Phase 1: `run_job()` (lines 142-259) spawns an `AIAgent` with `quiet_mode=True` and injects origin context via environment variables (`HERMES_SESSION_PLATFORM`, `HERMES_SESSION_CHAT_ID`). The agent runs to completion and returns `final_response`.

Phase 2: `_deliver_result()` (lines 57-139) resolves the delivery target from the job's `deliver` field and routes the `final_response` (not the full output doc) to the platform. The full output doc (including prompt, metadata, error traces) is always written to disk by `save_job_output()` regardless of platform delivery success.

The separation of "run" and "route" into distinct phases, with the full output always persisted first, is the correct reliability pattern: if platform delivery fails, the output is not lost.

**Sylveste verdict:** Intercom's scheduler (`rust/intercomd/src/scheduler.rs`) currently queues container spawns but has no delivery routing tier for scheduled outputs. The two-phase pattern maps cleanly: (1) spawn container and capture result, (2) route result to configured delivery targets. Autarch's task dispatcher should own phase 1; intercomd's scheduler_wiring should own phase 2.

### Finding 6.2 — P1: asyncio.run() collision is handled with a ThreadPoolExecutor fallback

**File:** `cron/scheduler.py:116-128`

```python
try:
    result = asyncio.run(_send_to_platform(platform, pconfig, chat_id, content))
except RuntimeError:
    # asyncio.run() fails if there's already a running loop in this thread
    import concurrent.futures
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(asyncio.run, _send_to_platform(...))
        result = future.result(timeout=30)
```

The cron ticker runs in a background `threading.Thread` (see `gateway/run.py:2205-2212`) but platform sends are async. The `asyncio.run()` fallback via a new thread is a well-known workaround for the "no running event loop in this thread" problem in Python's mixed sync/async model.

**Sylveste verdict:** This problem does not exist in Rust/tokio: the scheduler runs as a tokio task, and platform sends can be `await`ed directly. This is a Python-specific workaround with no equivalent needed in intercomd.

### Finding 6.3 — P2: Schedule parsing supports four independent formats with a single parser

**File:** `cron/jobs.py:64-146`

The `parse_schedule()` function handles: duration strings (`30m`, `2h`, `1d`), interval strings (`every 30m`), standard cron expressions (`0 9 * * *`), and ISO timestamps (`2026-02-03T14:00`). All four produce a normalised `{"kind": ..., ...}` dict consumed by `compute_next_run()`.

The cron expression path requires `croniter` and degrades gracefully if not installed (raises `ValueError` with install hint). One-shot schedules auto-set `repeat=1` (line 244-246 in `jobs.py`).

**Sylveste verdict:** Intercom's scheduler accepts only cron expressions (`scheduler.rs`). Adding duration and interval formats would meaningfully improve UX for users scheduling tasks via conversational commands like "run this every 2 hours". The `parse_schedule` logic is straightforward to port to Rust using `chrono` and a cron expression library.

### Finding 6.4 — P2: Origin context is injected via environment variables, not function arguments

**File:** `cron/scheduler.py:160-165`

```python
if origin:
    os.environ["HERMES_SESSION_PLATFORM"] = origin["platform"]
    os.environ["HERMES_SESSION_CHAT_ID"] = str(origin["chat_id"])
    if origin.get("chat_name"):
        os.environ["HERMES_SESSION_CHAT_NAME"] = origin["chat_name"]
```

The `AIAgent` is constructed without passing origin directly; it reads these env vars at tool-call time. This is a process-global side effect: if two cron jobs ran concurrently in the same process, their origin contexts would collide. The `finally` block (lines 262-264) cleans up, but there is no locking.

**Sylveste verdict:** This is a Python-specific design limitation. In Rust, origin context should be passed as a typed argument through the call stack, not via environment mutation. The cleanup `finally` block pattern should not be ported.

### Finding 6.5 — P1: File-based lock prevents concurrent tick execution

**File:** `cron/scheduler.py:283-336`

The `tick()` function acquires an exclusive `fcntl.flock` on `.tick.lock` before polling for due jobs. If another tick is running (gateway in-process ticker + standalone `hermes cron tick` + systemd timer), the second tick skips with `return 0`.

This is a correct cross-process mutual exclusion mechanism for the single-node case. The lock is released in the `finally` block regardless of errors.

**Sylveste verdict:** Intercom's Rust scheduler does not need an external file lock because it runs as a single tokio task inside a single process. However, the principle — idempotent tick function that is safe to call from multiple entry points — should be preserved. `scheduler_wiring.rs` should be designed so calling `tick()` twice concurrently is harmless (e.g. using `tokio::sync::Mutex` or a `AtomicBool` guard).

---

## Architectural Boundaries Summary

### Platform-specific vs. platform-agnostic

| Component | Boundary |
|-----------|----------|
| `DeliveryTarget` / DSL parsing | Platform-agnostic: works without any live adapter |
| `DeliveryRouter.resolve_targets()` | Agnostic: resolves home channels from config |
| `DeliveryRouter.deliver()` | Crossing point: dispatches to platform-specific `adapter.send()` |
| `BasePlatformAdapter` | Agnostic contract; `connect/disconnect/send` are the seam |
| `TelegramAdapter` / `DiscordAdapter` | Platform-specific: library bindings, format escaping |
| `ChannelDirectory` | Hybrid: Discord/Slack use platform API; Telegram/WhatsApp use session history |
| `HookRegistry` | Fully agnostic: filesystem discovery, no platform concepts |
| `PairingStore` | Conceptually agnostic; storage is filesystem-specific |
| `SessionMirror` | Platform-agnostic interface; storage is SQLite/JSONL |
| `cron/jobs.py` | Agnostic: schedule parsing and storage |
| `cron/scheduler.py` `_deliver_result()` | Crossing point: routes to platform adapters |

### Delivery reliability assessment

Strengths:
1. `always_log_local` ensures output is never fully lost (P0 pattern)
2. Two-phase run-then-route in cron separates compute from delivery
3. File lock on `tick()` prevents double-execution
4. `mirror_to_session` closes the outbound context gap for conversational continuity

Weaknesses:
1. Platform delivery has no retry mechanism — one attempt, log on failure
2. Silent skip on missing home channel (Finding 1.2)
3. No delivery status feedback to the originating user on cron job failure
4. Session mirror write is best-effort (failures silently swallowed)

---

## Adaptation Opportunities for Sylveste

Items suitable for bead creation, ordered by priority:

**1. [P0] intercom: Persist scheduled output to Postgres before platform delivery**
Port the "always_log_local" principle to intercomd: write agent output to a `scheduled_outputs` table before attempting Telegram/WhatsApp delivery. Enables retries and audit.
File ref: `gateway/delivery.py:158-163`, `cron/scheduler.py:308-319`

**2. [P1] intercom: Add DeliveryTarget address scheme to scheduled task routing**
Define a `DeliveryTarget` enum/struct in `intercom-core` supporting `Origin`, `Local`, `Platform(name)`, `PlatformChat(name, chat_id)`. Wire into `scheduler_wiring.rs` and the container output protocol.
File ref: `gateway/delivery.py:27-96`

**3. [P1] intercom: Define ChannelAdapter trait in intercom-core**
Extract a `ChannelAdapter` Rust trait with `connect`, `disconnect`, `send` as required methods. Move Telegram and WhatsApp implementations behind this trait. Enables Discord/Slack as future adapters with no orchestration changes.
File ref: `gateway/platforms/base.py:325-400`

**4. [P1] intercom: Implement session mirror for outbound scheduled delivery**
After `_deliver_result()` succeeds, write a synthetic `role: assistant, mirror: true` message to the target session's Postgres `messages` table. Closes the context gap between cron outputs and the next user message.
File ref: `gateway/mirror.py:24-61`

**5. [P1] intercom: Port pairing system as alternative to static allowlist**
Implement OTP pairing in Rust: 8-char code, `OsRng`, 1-hour TTL, per-user rate limit (10 min), per-platform lockout after 5 failures. Store pairing state in Postgres `pairing_codes` table. Expose `hermes pair approve <code>` in the CLI.
File ref: `gateway/pairing.py:55-283`

**6. [P2] intercom: Add truncate_message with code-fence boundary tracking to Rust Telegram bridge**
Port `BasePlatformAdapter.truncate_message()` to `telegram.rs` for the non-streaming send path and for WhatsApp. Handles long agent outputs that exceed per-platform message size limits without breaking markdown fences.
File ref: `gateway/platforms/base.py:779-867`

**7. [P2] intercom: Add duration/interval schedule format to scheduler**
Extend `scheduler.rs` schedule parsing to accept `"every 30m"`, `"2h"`, `"1d"` formats in addition to cron expressions. Use `chrono::Duration` for interval scheduling. Improves UX for conversationally-scheduled tasks.
File ref: `cron/jobs.py:43-146`

**8. [P2] intercom: Add channel directory for name-to-ID resolution**
Implement a channel directory in `intercomd` that enumerates Discord/Slack channels at startup and infers Telegram/WhatsApp contacts from session history. Store in Postgres `channels` table with a 5-minute refresh. Enables human-readable delivery targets.
File ref: `gateway/channel_directory.py:1-238`

**9. [P2] autarch: Adopt MessageEvent normalization for inbound message abstraction**
Define an `IncomingMessage` struct in `intercom-core` that all channel adapters produce, decoupling orchestration from Telegram/WhatsApp specifics. Maps to `BasePlatformAdapter.MessageEvent`.
File ref: `gateway/platforms/base.py:264-309`

**10. [P3] autarch: Evaluate HookRegistry pattern for host-side lifecycle events**
If intercomd gains an event bus, model it on `HookRegistry`: manifest-declared subscriptions, error-isolated handlers, `category:name` taxonomy with single-level wildcard matching. Does not replace Interspect (different layer); targets host-process hooks only.
File ref: `gateway/hooks.py:1-151`

---

*No overlap with fd-rl-training-pipeline (Atropos), fd-security-patterns (pairing security depth), or fd-honcho-user-modeling (session identity).*
