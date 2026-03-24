---
artifact_type: prd
bead: Demarch-4wm
stage: design
---

# PRD: Token-Efficient Conversation Resumption

## Problem

When an intercom container session resets (size overflow, planned restart, or crash), the next session starts with zero conversational context. The agent loses all knowledge of what it was working on, decisions made, and pending tasks. This causes repeated work, lost context, and degraded user experience — especially for long-running tasks that span multiple session resets.

## Solution

A three-tier conversation resumption mechanism that injects structured context into the system prompt at session startup. The agent writes a handoff note at PreCompact time (best quality); if unavailable, the system reconstructs context from ambient state (decent quality); if nothing is available, the session starts with just CLAUDE.md (baseline).

## Features

### F1: Handoff Note Writer (PreCompact Hook)

**What:** When the SDK fires the PreCompact hook (context window filling up), the agent writes a structured `handoff.json` to the workspace group directory before compaction proceeds.

**Acceptance criteria:**
- [ ] PreCompact hook handler added to agent-runner that prompts the agent to write a handoff note
- [ ] handoff.json written atomically (write to temp file, rename) to `/workspace/group/handoff.json`
- [ ] Schema includes: version, created_at, source, session_id, task (bead_id + summary), decisions[], pending[], gotchas[]
- [ ] Total handoff note size capped at 500 tokens (truncate oldest decisions/pending items first)
- [ ] handoff.json survives container restart (workspace is a bind mount — verify this is true)

### F2: Handoff Note Reader (Session Startup)

**What:** On session startup, agent-runner checks for a `handoff.json` in the workspace group directory. If found, it formats the content as a "Previous Session Context" section and prepends it to the system prompt.

**Acceptance criteria:**
- [ ] agent-runner reads `handoff.json` on startup before constructing the system prompt
- [ ] Formats handoff content into a structured markdown block (Task, Decisions, Pending, Gotchas)
- [ ] Prepended to the system prompt after CLAUDE.md but before group-specific instructions
- [ ] Gracefully handles malformed/corrupt handoff.json (log warning, skip injection)
- [ ] Old handoff.json is not deleted after reading (kept for debugging; overwritten on next PreCompact)

### F3: Ambient State Reconstructor (Crash Fallback)

**What:** When no `handoff.json` exists (crash/timeout), the agent-runner reconstructs minimal context from ambient state: active beads, git diff, and conversation archive metadata.

**Acceptance criteria:**
- [ ] Checks for `handoff.json` first; only reconstructs if missing
- [ ] Reads active beads from workspace (via `bd list --status=in_progress` or equivalent file check)
- [ ] Reads `git diff --stat` from the workspace to show what files changed
- [ ] Reads the most recent conversation archive filename from `conversations/` for topic context
- [ ] Reconstructed context is ~100-200 tokens and clearly marked as "reconstructed (no handoff note available)"
- [ ] All reconstruction is deterministic — no LLM calls

### F4: Protocol Extension (ContainerInput.previousContext)

**What:** Add an optional `previousContext` field to the `ContainerInput` protocol so the Rust host can pass pre-computed context to the container. This enables host-side reconstruction (where Postgres session history is available) in future iterations.

**Acceptance criteria:**
- [ ] `previousContext?: string` added to `ContainerInput` in `protocol.ts`
- [ ] `process_group.rs` updated to populate `previousContext` when available (initially empty — host-side reconstruction is a future feature)
- [ ] agent-runner prefers `previousContext` over self-reconstructed context when both are available
- [ ] Backward-compatible: existing containers without `previousContext` continue to work

## Non-goals

- **LLM-generated summaries**: No LLM calls for reconstruction. All paths are deterministic.
- **Full conversation replay**: Not replaying conversation history — just structured context.
- **Cross-provider resumption**: Not converting sessions between Claude/Codex/Gemini (that's CASR's domain).
- **Host-side reconstruction logic**: F4 adds the protocol field but the Rust host logic to populate it is deferred.
- **Multi-handoff chains**: Not keeping a history of handoff notes — just the latest one.

## Dependencies

- Intercom agent-runner (`apps/intercom/container/agent-runner/src/index.ts`) — primary implementation surface
- Intercom protocol (`apps/intercom/container/shared/protocol.ts`) — schema extension
- Intercom daemon (`apps/intercom/rust/intercomd/src/process_group.rs`) — protocol field threading
- Workspace bind mount must persist `/workspace/group/` across container restarts (believed to be true, needs verification)

## Open Questions

- **Token budget cap enforcement**: How to count tokens in the handoff note? Approximate by character count (÷4) or use a tokenizer?
- **Handoff note rotation**: Should we keep last 3 handoff notes for debugging, or just overwrite?
