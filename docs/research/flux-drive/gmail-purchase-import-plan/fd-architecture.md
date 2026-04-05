---
agent: fd-architecture
target: docs/plans/2026-04-05-gmail-purchase-import.md
date: 2026-04-05
---

# Architectural Review: Gmail Purchase Import Plan

## F1 — ORM Pattern Mismatch (P0)

The plan's model stubs use the legacy `Column(Integer, primary_key=True)` style with bare `class GmailToken(Base)` declarations. Every existing Auraken model uses SQLAlchemy 2.0 `Mapped` / `mapped_column` with `UUID(as_uuid=True)` primary keys (see `models.py` lines 36–48, 60–80, 100–115). The migration file stubs must be rewritten to match: `id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)`, `user_id` as a `UUID` FK to `users.id`, and `LargeBinary` replaced with `BYTEA` via `mapped_column(LargeBinary)`. Using `Integer` PKs and `String` user IDs will create a type mismatch with every FK that points into `users`.

## F1 — `gmail_auth.py` / `gmail_oauth.py` Placement (P2)

The plan places token management at `auraken/gmail_auth.py` and OAuth flow at `auraken/gmail_oauth.py` — top-level flat files alongside `telegram.py`, `recommendations.py`, etc. Given that F3/F4/F5/F6/F7 all live under `auraken/gmail_import/`, the token manager and OAuth helpers are cohesive with that subpackage and should live at `auraken/gmail_import/auth.py` and `auraken/gmail_import/oauth.py`. The existing flat module pattern (`agent.py`, `signals.py`) is for cross-cutting concerns; Gmail OAuth is feature-scoped.

## F3/F5/F6 — `gmail_import/` Subpackage Structure (P1)

The `gmail_import/` subpackage introduces a second `models.py` (`gmail_import/models.py` for `ParseResult`) alongside the canonical `auraken/models.py` (ORM models). This naming collision will confuse import resolution — `from auraken.gmail_import.models import ParseResult` vs `from auraken.models import User` works syntactically but the divergent naming creates persistent confusion. Rename the dataclass module to `auraken/gmail_import/types.py` or `auraken/gmail_import/results.py` to reserve `models.py` for ORM definitions per the project's established convention.

## F6 — MCP Client Wrapper Abstraction (P1)

`InterjawnClient` in `mcp_client.py` is proposed as a "wrapper for MCP stdio calls" but the plan gives no implementation for how it actually invokes the MCP subprocess. Auraken already has two precedents for subprocess-based external calls: `asyncio.to_thread(subprocess.run, ...)` in `bridge.py` and `checkpoint.py`. For interjawn, the correct approach is to call the `interjawn` MCP binary via `mcp` SDK's `StdioServerParameters` (the same pattern Auraken uses when acting as an MCP server via `mcp_server.py`), not raw subprocess — otherwise the plan owns MCP protocol framing manually. The client wrapper should use `mcp.client.stdio.stdio_client` with `StdioServerParameters` to get proper JSON-RPC framing; raw subprocess with custom JSON encoding is a reimplementation of what the SDK provides.

## F6 — asyncio Queue + Single Worker for stdio Transport (P2)

The bounded asyncio queue (maxsize=100) with a single consumer worker is correct reasoning: stdio MCP transport is inherently single-threaded (one active call at a time) so serializing writes through a single worker avoids interleaving JSON-RPC frames. However, the plan does not address queue backpressure: if the parser outruns the MCP worker (likely for large historical imports), `put()` will block the parse coroutine inside the same event loop, stalling the entire import. The queue should be consumed with `asyncio.gather` only on the worker side; the producer should use `put_nowait` with an explicit `QueueFull` handler that writes to `failed_extractions` rather than blocking.

## F5 — `BrandMatcher` Reuses Nothing from Existing Recommendations Module (P2)

`auraken/recommendations.py` exists and handles preference-based matching. The plan creates `BrandMatcher` entirely from scratch with its own `mcp_client` and `db_session` arguments. Before implementing a new fuzzy matcher, `recommendations.py` should be checked for any existing brand or preference entity lookup that could be composed. At minimum, `BrandMatcher` should write resolved brands as `PreferenceEntity` rows (domain="fashion", type="brand") rather than only into `brand_match_precedents` — otherwise F7's context extraction cannot pick them up via the existing preference pipeline already wired into `agent.py`.

## F7 — Staleness Check Target File Incorrect (P1)

The plan modifies `apps/Auraken/src/auraken/recommendations.py` for staleness detection, but F7 adds brand affinity context that feeds the preference system, not the recommendation system. The preference staleness check belongs in `agent.py` or the `CoreProfile` loading path (alongside `profile_dirty_since`) so it gates every response, not just explicit recommendation calls. Putting it only in `recommendations.py` means the staleness flag is silently ignored during normal conversation.

## F8 — `telegram.py` Already Exists (P3)

The plan says "Add `/import` command handler" to `telegram.py` without noting the file already exists and uses `register_command()` from the `Transport` protocol. The handler should use `transport.register_command("import", ...)` consistent with existing command registration (see `transport.py` `CommandFn` type), not direct Telegram API bot handler wiring. If the import command needs progress streaming (multiple messages), it should use the `Context`/`Response` mechanism or a background task that calls `telegram.send_message` directly — both paths exist, but the plan should specify which to avoid implementing it against the wrong layer.
