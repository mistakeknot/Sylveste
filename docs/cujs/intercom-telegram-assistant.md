---
artifact_type: cuj
journey: intercom-telegram-assistant
actor: regular user (developer chatting with AI assistants via Telegram)
criticality: p2
bead: Sylveste-2c7
---

# Intercom Telegram Assistant

## Why This Journey Matters

Not every interaction with AI agents belongs in a terminal. Sometimes the developer is on their phone, away from their desk, or just wants to fire off a quick question without opening a code editor. Intercom bridges this gap — it puts Claude, Gemini, and Codex into Telegram group chats, each with isolated containers, persistent context, and the full lifecycle of message handling.

The stakes are different from terminal-based tools. Telegram is asynchronous, mobile-first, and conversational. Messages arrive at any time. Responses must be timely but not instant — the developer accepts that container spin-up takes a moment. The key is reliability: messages must never be lost, responses must never be silently dropped, and the developer must always know which model is answering.

## The Journey

The developer has `intercomd` running on their server (systemd service). They open a Telegram group where Intercom is a member. Each group is bound to a runtime: one group for Claude, one for Gemini, one for Codex. The developer sends a message: "What's the current state of the Mycroft tier FSM?"

Intercom's Telegram poller picks up the message. It routes to the correct runtime based on the group. The container orchestrator spins up a sandboxed container (or reuses an existing one for the group), passes the message through the IPC protocol, and waits for the response. The response streams back to Telegram, split into chunks if it exceeds the message length limit.

The developer uses slash commands for control:
- `/model` — see or switch the active model
- `/status` — check container health, memory usage, message counts
- `/reset` — clear the conversation context (start fresh)
- `/help` — list available commands

Each group maintains its own conversation history in Postgres. The developer can switch between groups (models) freely, and each maintains independent context. Media handling works too — sending an image triggers vision analysis, sending a file triggers document parsing.

For longer tasks, the developer can ask Codex to run code: the container has filesystem access scoped to the group's sandbox. Results come back as formatted messages. For quick questions, Claude responds in seconds. For research, Gemini searches and summarizes.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Message-to-response latency under 10 seconds for cached containers | measurable | Time from Telegram update to response delivery ≤ 10s |
| Messages never lost (poll → process → respond is atomic) | measurable | No orphan messages in Postgres without responses |
| Slash commands respond within 2 seconds | measurable | Command processing latency ≤ 2s |
| Each group maintains independent conversation context | measurable | Reset in one group doesn't affect others |
| Container sandbox isolation holds | measurable | File writes in one group not visible in another |
| Service survives restart without losing state | measurable | `systemctl restart intercomd` → messages resume |
| Media (images, files) processed correctly | measurable | Vision and document parsing return relevant content |

## Known Friction Points

- **Container cold-start latency** — first message in a group may take 15-30 seconds while the container image loads. Subsequent messages are faster.
- **Telegram message length limits** — long responses must be split. Splitting can break code blocks or formatting.
- **No streaming in Telegram** — responses arrive as complete messages, not streaming tokens. The developer waits for the full response.
- **Postgres dependency** — the daemon requires a running Postgres instance. Docker Compose handles this but adds operational complexity.
- **Node host archived** — WhatsApp support (via Baileys) is dormant. Only Telegram is active.
- **No multi-user awareness** — all messages in a group are treated as from the same user. Group chats with multiple humans may confuse context.
