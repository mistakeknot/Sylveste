# fd-honcho-user-modeling: Hermes Agent Honcho Integration Review

**Reviewer:** fd-honcho-user-modeling
**Date:** 2026-03-02
**Target:** `research/hermes_agent/honcho_integration/`, `research/hermes_agent/hermes_cli/config.py`, and honcho/peer/workspace call sites
**Decision Lens:** Patterns addressing gaps in Demarch's current session/memory model; architectural concepts over Honcho-specific API details

---

## Executive Summary

Hermes Agent implements a complete, production-tested user modeling layer on top of a standard chat gateway. Its core insight is that **user identity and conversation session are different primitives** and should be tracked separately. This cleanly maps onto gaps Demarch has in both intercom (which currently tracks `chat_jid` → `session_id` but loses user identity across resets) and Autarch (which has project-scoped sessions but no cross-project user representation). Four patterns are immediately adaptable; the linked-workspaces pattern requires platform-layer commitment.

---

## Review Area 1: Peer/Session/Workspace Primitive Model

### Finding 1.1 — User identity vs. session identity are explicitly separated [P0]

**File:** `research/hermes_agent/honcho_integration/session.py:19-35`

```python
@dataclass
class HonchoSession:
    key: str                   # channel:chat_id  — the conversation slot
    user_peer_id: str          # Honcho peer ID for the user — stable identity
    assistant_peer_id: str     # Honcho peer ID for the assistant — stable per deployment
    honcho_session_id: str     # Honcho session ID — one per conversation window
```

The `key` is a mutable session slot (`telegram:123456`). The `user_peer_id` is a stable identity that persists across session resets. This is the foundational primitive. Hermes derives `user_peer_id` from config (`peer_name`) or from the channel+chat_id combination when config is absent (`user-{channel}-{chat_id}`).

**Gap in Demarch:** intercom's `db.ts` has `sessions` (keyed on `group_folder`) and `messages` (keyed on `chat_jid`), but no stable user-identity column. When a session resets via `deleteSession(groupFolder)`, all modeling state disappears. The `sender` field in `messages` is platform-local (WhatsApp phone number, Telegram user ID), not a normalized identity.

### Finding 1.2 — Asymmetric observe_me/observe_others controls modeling scope [P1]

**File:** `research/hermes_agent/honcho_integration/session.py:129-133`

```python
user_config = SessionPeerConfig(observe_me=True, observe_others=True)
ai_config = SessionPeerConfig(observe_me=False, observe_others=True)
```

The user peer is modeled (observe_me=True) — Honcho builds a persistent representation from the user's messages. The assistant peer is NOT self-modeled (observe_me=False), but it observes the user (observe_others=True). This is asymmetric by design: you want user representations to accumulate, but you don't want self-referential loops in the assistant's model.

**Architectural concept:** This maps to a general principle — in any session memory system, distinguish between "things that should accumulate into a persistent user model" and "things that describe agent state for a single session." Demarch's current intercom stores both symmetrically as messages.

### Finding 1.3 — workspace_id namespaces multiple agents [P1]

**File:** `research/hermes_agent/honcho_integration/client.py:35, 195`

```python
workspace_id: str = "hermes"   # default: agent name
...
_honcho_client = Honcho(workspace_id=config.workspace_id, ...)
```

Each agent deployment gets its own workspace. Peers and sessions are scoped to a workspace, so users interacting with `hermes` and users interacting with `cursor` (another agent) do not collide unless linked (see Finding 4.2). In Demarch terms: Autarch and intercom would be separate workspaces, with an opt-in bridge.

---

## Review Area 2: context() Semantic Prefetch

### Finding 2.1 — Single API returns peer_representation, peer_card, and semantically-searched message history [P0]

**File:** `research/hermes_agent/honcho_integration/session.py:338-376`

```python
def get_prefetch_context(self, session_key: str, user_message: str | None = None) -> dict[str, str]:
    ctx = honcho_session.context(
        summary=False,
        tokens=self._context_tokens,
        peer_target=session.user_peer_id,
        search_query=user_message,          # semantic search anchor
    )
    card = ctx.peer_card or []
    card_str = "\n".join(card) if isinstance(card, list) else str(card)
    return {
        "representation": ctx.peer_representation or "",
        "card": card_str,
    }
```

This is called once per user turn before the LLM call (`run_agent.py:2829`). The `search_query=user_message` argument means Honcho returns message history semantically relevant to the current user utterance, not just the N most recent messages. The `peer_representation` is a synthesized prose summary of the user built by Honcho's reasoning model.

**Injection site:** `run_agent.py:1250-1273` formats as `"# Honcho User Context\n"` and injects into the system prompt for that turn. The system prompt itself is cached (`_cached_system_prompt`), but the Honcho context is turn-local.

**Gap in Demarch:** intercom's `getRecentConversation()` (`db.ts:305-322`) returns raw N-most-recent messages. There is no semantic retrieval, no user representation, and no per-turn prefetch. The agent receives raw history without synthesis.

### Finding 2.2 — context_tokens budget controls prefetch size [P2]

**File:** `research/hermes_agent/honcho_integration/client.py:45-46, 122`

```python
context_tokens: int | None = None   # in config
...
context_tokens=raw.get("contextTokens") or host_block.get("contextTokens")
```

The `context_tokens` parameter sets a hard token ceiling on what `context()` returns. This prevents the prefetch from consuming too much of the LLM's context window. In Demarch: this directly maps to the "how much history to inject" parameter that intercom currently hardcodes via the `limit` arg in `getRecentConversation`.

### Finding 2.3 — User observations are routed from memory tool to user model [P1]

**File:** `run_agent.py:2349-2350, 1275-1294`

```python
if self._honcho and flush_target == "user" and args.get("action") == "add":
    self._honcho_save_user_observation(args.get("content", ""))
```

When the agent writes to its memory tool with `target=user`, Hermes additionally routes that content to Honcho as a user-peer message tagged `[observation]`. This means structured agent observations (e.g., "user prefers short replies") accumulate in the Honcho model alongside raw conversational history.

**Architectural concept:** There is a dual-write pattern here: memory tool writes go to the local file (MEMORY.md/USER.md) AND to the user model. The local file is authoritative for the current session; the remote model accumulates across sessions. Demarch could apply this to intercom's future memory tooling.

---

## Review Area 3: new_session() vs. delete() Behavior

### Finding 3.1 — new_session() creates a fresh conversation slot without destroying modeling history [P0]

**File:** `research/hermes_agent/honcho_integration/session.py:287-313`

```python
def new_session(self, key: str) -> HonchoSession:
    """Create a new session, preserving the old one for user modeling."""
    # Remove old session from caches (but don't delete from Honcho)
    old_session = self._cache.pop(key, None)
    if old_session:
        self._sessions_cache.pop(old_session.honcho_session_id, None)
    # Create new session with timestamp suffix
    timestamp = int(time.time())
    new_key = f"{key}:{timestamp}"
    session = self.get_or_create(new_key)
    # Cache under both original key and timestamped key
    self._cache[key] = session
    self._cache[new_key] = session
```

The `delete()` method (`session.py:280-285`) only removes the session from local in-process cache; it does not call any Honcho API. The data in Honcho is never deleted. `new_session()` explicitly documents this: "preserving the old one for user modeling."

**Contrast with intercom:** `deleteSession(groupFolder)` (`db.ts:549-551`) deletes the session row from SQLite. The session ID is gone. The messages remain in the `messages` table keyed by `chat_jid`, but there is no linkage back to a persistent user model. A "clear history" command by the user today destroys context that could have been used to model their preferences.

**Gap in Demarch:** intercom needs a conceptual separation between "reset the conversation context the LLM sees" (clear session window) and "discard accumulated user modeling" (a much rarer and more intentional operation). Currently these are conflated.

### Finding 3.2 — Session key sanitization is explicit [P2]

**File:** `research/hermes_agent/honcho_integration/session.py:170-172`

```python
def _sanitize_id(self, id_str: str) -> str:
    """Sanitize an ID to match Honcho's pattern: ^[a-zA-Z0-9_-]+"""
    return re.sub(r'[^a-zA-Z0-9_-]', '-', id_str)
```

intercom's JIDs contain `@`, `.`, `:` (e.g., `123456@s.whatsapp.net`, `tg:123456`). Any external system that consumes these as identifiers needs normalization. The Hermes pattern of explicit sanitization with a clear target regex is a model.

---

## Review Area 4: migrate_local_history() and migrate_memory_files()

### Finding 4.1 — XML-wrapped transcript upload bootstraps external model from local history [P1]

**File:** `research/hermes_agent/honcho_integration/session.py:378-452`

```python
def migrate_local_history(self, session_key: str, messages: list[dict]) -> bool:
    content_bytes = self._format_migration_transcript(session_key, messages)
    honcho_session.upload_file(
        file=("prior_history.txt", content_bytes, "text/plain"),
        peer=user_peer,
        metadata={"source": "local_jsonl", "count": len(messages)},
        created_at=first_ts,
    )
```

The transcript format (`_format_migration_transcript`) wraps messages in `<prior_conversation_history>` / `<prior_memory_file>` XML tags with an explicit `<context>` block explaining provenance: "This conversation history occurred BEFORE the Honcho memory system was activated." The receiving model is primed to treat these as foundational context rather than recent turns.

**File:** `research/hermes_agent/honcho_integration/session.py:454-526`

`migrate_memory_files()` does the same for MEMORY.md and USER.md, wrapping each file with a `<prior_memory_file>` tag plus a description string. This is a clean bootstrapping pattern for any "activate new memory system on existing deployment" scenario.

**Demarch relevance:** When Demarch adds any external user modeling system (Honcho or a Demarch-native equivalent), intercom's existing SQLite message history and any exported memory files need this migration path. The XML-wrap-with-provenance approach is directly reusable. The design principle: **when injecting old data into a new model, always add metadata explaining why the data exists and its relationship to live data**.

### Finding 4.2 — Migration is gated on session cache availability [P2]

**File:** `research/hermes_agent/honcho_integration/session.py:391-405`

```python
honcho_session = self._sessions_cache.get(sanitized)
if not honcho_session:
    logger.warning("No Honcho session cached for '%s', skipping migration", session_key)
    return False
```

Migration silently skips if the Honcho session hasn't been initialized yet. This is intentional but means `migrate_local_history()` can only be called after `get_or_create()`. **Implication for Demarch:** migration must be sequenced after session initialization, not during cold boot.

---

## Review Area 5: HonchoClientConfig Resolution Chain

### Finding 5.1 — host-block > flat global > defaults resolution is unambiguous [P1]

**File:** `research/hermes_agent/honcho_integration/client.py:85-127`

```python
# ~/.honcho/config.json structure:
# {
#   "apiKey": "...",          <- flat global
#   "workspace": "global-ws", <- flat global
#   "hosts": {
#     "hermes": {
#       "workspace": "hermes-ws",  <- host block (wins)
#       "linkedHosts": ["cursor"]
#     }
#   }
# }

workspace = (
    host_block.get("workspace")   # 1. Host block (always wins)
    or raw.get("workspace")       # 2. Flat global
    or host                       # 3. Default: host name as workspace
)
```

The resolution is explicit and tested at `tests/honcho_integration/test_client.py:107-135`. One config file services multiple agent hosts on the same machine, each getting host-specific overrides without duplicating shared settings.

**Gap in Demarch:** Autarch's config is per-tool (`.coldwine/`, `.gurgeh/`, `.pollard/`). There is no shared config namespace for cross-tool or cross-agent settings. Any future user modeling layer for Autarch would need a comparable resolution chain, likely using `~/.autarch/config.yaml` or `~/.demarch/config.json` as the root.

### Finding 5.2 — Auto-enable when API key is present avoids dead config [P2]

**File:** `research/hermes_agent/honcho_integration/client.py:102-110`

```python
explicit_enabled = raw.get("enabled")
if explicit_enabled is None:
    # Not explicitly set in config -> auto-enable if API key exists
    enabled = bool(api_key)
else:
    # Respect explicit setting
    enabled = explicit_enabled
```

This eliminates the common DX failure mode where a user sets an API key but forgets to also set `enabled: true`. The feature activates when the credential is present, disabled when it's absent. Explicit `enabled: false` overrides the auto-detection.

**Demarch relevance:** Any optional integration in intercom or Autarch should follow this pattern. Currently intercom relies entirely on env vars being set; there is no graceful degradation or auto-detection at config load time.

### Finding 5.3 — `session_strategy` decouples session naming from platform topology [P2]

**File:** `research/hermes_agent/honcho_integration/client.py:48, 129-146`

```python
session_strategy: str = "per-directory"   # also: "per-project"
session_peer_prefix: bool = False

def resolve_session_name(self, cwd: str | None = None) -> str | None:
    manual = self.sessions.get(cwd)          # 1. Manual override
    if manual:
        return manual
    base = Path(cwd).name                    # 2. Derive from directory basename
    if self.session_peer_prefix and self.peer_name:
        return f"{self.peer_name}-{base}"    # 3. Optional peer prefix
    return base
```

Session names can be explicitly mapped (`sessions: {"/home/user/proj": "custom-session"}`), derived from directory, or prefixed with the user's peer name. This design anticipates multi-user deployments where the same directory may be worked on by different users.

---

## Review Area 6: Linked Workspaces Pattern

### Finding 6.1 — linkedHosts enables single user model spanning multiple agent hosts [P1]

**File:** `research/hermes_agent/honcho_integration/client.py:98, 148-157`

```python
linked_hosts: list[str] = field(default_factory=list)
# config: "linkedHosts": ["cursor", "windsurf"]

def get_linked_workspaces(self) -> list[str]:
    """Resolve linked host keys to workspace names."""
    for host_key in self.linked_hosts:
        block = hosts.get(host_key, {})
        ws = block.get("workspace") or host_key
        if ws != self.workspace_id:
            workspaces.append(ws)
    return workspaces
```

**Tests:** `tests/honcho_integration/test_client.py:181-213`

A single `~/.honcho/config.json` with `linkedHosts: ["cursor"]` means Hermes can query the user model accumulated from the user's Cursor IDE sessions. The resolved workspaces list is then used to query additional context sources at prefetch time.

**Demarch relevance:** The L3 agents (Autarch and intercom) are separate applications with distinct session histories. A user who talks to Autarch's TUI and also uses intercom's Telegram bot is the same person. Without linked workspaces (or a Demarch-native equivalent), those two streams of user context are siloed. This is the highest-priority architectural concept in the review.

**Current state:** intercom has no cross-application user identity at all. Autarch's session model is project-scoped (`lastSessionId` per project directory in `.claude.json`), not user-scoped.

---

## Synthesis: What Demarch's Current Model Lacks

| Capability | Hermes Agent | intercom (current) | Autarch (current) |
|---|---|---|---|
| Stable user identity across session resets | user_peer_id | None (only sender/chat_jid) | None |
| Semantic history retrieval | context(search_query=...) | N most recent rows | N/A — in-process only |
| Synthesized user representation | peer_representation | None | None |
| Session reset preserves modeling history | new_session() (non-destructive) | deleteSession() destroys context | N/A |
| Migration path for existing history | migrate_local_history() | None | None |
| Cross-tool user identity | linkedHosts | None | None |
| Config auto-enable on key presence | auto-enable | Env-var only | N/A |
| Per-host config with global fallback | host-block resolution | None | Per-tool isolated |

---

## Adaptation Opportunities

The following items are concrete enough for Demarch bead creation. Ordered by prerequisite dependency — earlier items unblock later ones.

### AO-1 [P0]: Define UserPeer as a first-class type in intercom

**What:** Add a `user_peers` table to intercom's SQLite schema (or as a Postgres table in intercomd) that maps `(channel, platform_user_id)` → `user_peer_id`. The `messages` table gains a `user_peer_id` foreign key. Session resets keep the `user_peer_id`; they only rotate the `session_id`.

**Why:** This is the foundational primitive everything else depends on. Without stable user identity, you cannot accumulate a user model, migrate history, or link cross-tool sessions.

**Files to modify:** `apps/intercom/src/db.ts`, `apps/intercom/src/types.ts`
**Model:** `research/hermes_agent/honcho_integration/session.py:19-35, 186-199`

---

### AO-2 [P0]: Separate "reset conversation window" from "discard user model"

**What:** Add a `resetSession(groupFolder: string, keepUserModel: boolean)` function to intercom's db layer. When `keepUserModel=true` (the default for `/reset` commands), a new `session_id` is generated but the `user_peer_id` and accumulated context are preserved. Only an explicit "forget me" command destroys user model state.

**Why:** The current `deleteSession()` is too destructive. Users expect `/reset` to clear the conversation, not to be forgotten entirely.

**Files to modify:** `apps/intercom/src/db.ts`, wherever `/reset` is handled in the router
**Model:** `research/hermes_agent/honcho_integration/session.py:287-313`

---

### AO-3 [P1]: Add per-turn semantic context prefetch interface to intercom's runner

**What:** Define a `ContextPrefetcher` interface in intercom's container-runner or IPC layer that takes `(userPeerId, userMessage)` and returns `{ representation: string, card: string }`. The initial implementation can be a no-op stub (returns empty strings). This interface is the integration point for any user modeling backend — Honcho, a Demarch-native system, or a simple embedding search over SQLite history.

**Why:** Without this interface, adding user modeling later requires changes throughout the message dispatch pipeline. Defining the interface now as a stub costs little and makes the integration boundary explicit.

**Files to modify:** `apps/intercom/src/container-runner.ts`, `apps/intercom/src/types.ts`
**Model:** `research/hermes_agent/honcho_integration/session.py:338-376`, `run_agent.py:1250-1273`

---

### AO-4 [P1]: Add XML-wrapped history export to intercom's session tools

**What:** Add a `exportSessionTranscript(chatJid: string, format: 'xml-wrapped' | 'jsonl')` function that exports message history with provenance metadata. The XML-wrapped format matches Hermes's `_format_migration_transcript` pattern, enabling future upload to any external memory system.

**Why:** If/when intercom integrates an external user modeling backend, the existing years of SQLite conversation history needs a migration path. Writing the export function before the integration makes the migration path testable independently.

**Files to modify:** `apps/intercom/src/db.ts` (add export function)
**Model:** `research/hermes_agent/honcho_integration/session.py:423-452`

---

### AO-5 [P1]: Add shared config namespace for Autarch cross-tool settings

**What:** Define a `~/.demarch/config.json` (or `~/.autarch/config.json`) with a host-block resolution chain similar to Hermes's `~/.honcho/config.json`. This config governs settings shared across Autarch's tools (Bigend, Gurgeh, Coldwine, Pollard) and is the home for any future user-modeling integration key. Individual tools consult host blocks for overrides.

**Why:** Autarch's current per-tool config directories (`.coldwine/`, `.gurgeh/`) cannot express cross-tool settings. Adding user modeling later requires a config root that all tools can read.

**Files to modify:** new file `apps/autarch/pkg/config/shared.go`
**Model:** `research/hermes_agent/honcho_integration/client.py:54-157`

---

### AO-6 [P2]: Implement auto-enable pattern for optional integrations in intercom

**What:** Refactor intercom's config loading to follow the auto-enable pattern: any optional integration (memory backend, analytics, future user modeling) that has an API key configured in the environment or config file activates automatically; setting `enabled: false` disables it regardless of key presence.

**Why:** Reduces config friction for ops. Currently intercom requires careful env-var coordination; activating a new feature requires knowing which env vars to set AND that the feature exists.

**Files to modify:** `apps/intercom/src/config.ts` (if it exists) or the config section of `rust/intercom-core/src/config.rs`
**Model:** `research/hermes_agent/honcho_integration/client.py:102-110`

---

### AO-7 [P1]: Define cross-application user identity bridge (Autarch ↔ intercom)

**What:** Design a shared `user_peer_id` namespace that Autarch and intercom can both read. Concretely: a `~/.demarch/peers/` directory or a shared Postgres table (reusing intercomd's connection) where `(source_app, platform, platform_user_id) → user_peer_id`. Both applications write to this registry when they encounter a new user; both read from it when building context for a session.

**Why:** The linked-workspaces pattern's value is in cross-application user model accumulation. Without a shared identity registry, Autarch and intercom users are permanently siloed even if they are the same person.

**Files to create:** design doc or bead for the registry schema
**Model:** `research/hermes_agent/honcho_integration/client.py:148-157`, test at `tests/honcho_integration/test_client.py:181-213`

---

### AO-8 [P2]: Implement session_peer_prefix for multi-user Autarch deployments

**What:** Add an optional `peer_prefix` to Autarch's session naming so that sessions for user A and user B in the same project directory get distinct session names (`alice-autarch-project` vs `bob-autarch-project`). This requires AO-1/AO-5 as prerequisites.

**Why:** Autarch's current session naming is project-scoped only. In team deployments where multiple people use the same Bigend/Coldwine workspace, their context would collide into a single session.

**Model:** `research/hermes_agent/honcho_integration/client.py:129-146`

---

## Notes on Scope Boundaries

- All Honcho-specific API details (SDK version, `upload_file()` signature, `peer.chat()` dialectic endpoint) are intentionally excluded. The adaptation opportunities reference architectural patterns only.
- Credential handling in `HonchoClientConfig` (`api_key`, env fallback) is excluded per the fd-security-patterns boundary.
- The RL training loop integration with Honcho (trajectory logging) is excluded per the fd-rl-training-pipeline boundary.
- The gateway platform routing (how `session_key` is derived from `source.platform`) is excluded per the fd-gateway-messaging boundary.
