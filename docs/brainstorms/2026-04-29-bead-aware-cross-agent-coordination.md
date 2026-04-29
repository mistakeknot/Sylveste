---
artifact_type: brainstorm
bead: sylveste-kgfi
date: 2026-04-29
status: draft
thread: GSV Discord #agent-ops / Hermes Agents aware of other agents' beads
---

# Bead-aware cross-agent coordination

## Decision

Bead-aware cross-agent coordination is **Interverse / Sylveste canon**. Hermes' operator-facing view over that substrate is an **Athenverse adapter**.

Working names:

- **Substrate:** extend `intermux` + `intermute` + `interlock` first. Do not mint a new `Inter*` plugin yet.
- **Hermes adapter:** `Athenmesh`.
- **Future substrate name:** reserve `Intermesh` or `Interlink` only if this outgrows the existing `intermux` / `intermute` / `interlock` split.

Alignment: supports Sylveste's composition-over-capability principle by wiring small existing coordination tools around a shared Beads work-state handle.

Conflict/Risk: risks creating a parallel task tracker if presence/messages begin owning task state. The rule is explicit: Beads remains the source of truth for work status, dependency, priority, and claim state.

## Problem

Hermes, Claude Code, and Codex can all use Beads, but they still need a common way to answer:

- Who is currently working on this bead?
- Which repo and files are they touching?
- Is another agent blocked, idle, or stuck?
- Can I safely dispatch another body here?
- How do I message or nudge the relevant agent without losing the Beads thread?

The current answer is scattered across Beads, tmux panes, CASS, Discord, Intermute, and occasional handoff docs. Agents discover collisions late, often when git diffs collide or a human notices two live sessions in the same repo.

## Canonical source-of-truth split

| Concern | Owner | Notes |
|---|---|---|
| Work status, priority, dependencies, claim | Beads | Canonical. Presence layers never redefine task state. |
| Live tmux/session observation | `intermux` | Derive status, cwd, branch, touched files, active bead when visible. |
| Agent registry, messages, topics, ack/read, metadata | `intermute` | Durable coordination bus and live/deferred peer messages. |
| File reservations and release negotiation | `interlock` / Agent Mail | Advisory early warning, terminal enforcement when configured. |
| Hermes/Discord operator view | `Athenmesh` | Query/summarize/route/nudge; no canonical substrate ownership. |

## Minimum presence record

Every agent body should be representable by this record, whether it is Hermes, Claude Code, Codex, Zaka-spawned, or a future Skaffen runner:

```json
{
  "agent_id": "codex-zklw-20260429-001",
  "agent_kind": "codex|claude-code|hermes|zaka|skaffen|oracle|other",
  "host": "zklw",
  "surface": "tmux:zklw:session.window.pane|discord:thread|telegram|cli",
  "repo": "/home/mk/projects/Sylveste",
  "beads_authority": "/home/mk/projects/Sylveste/.beads",
  "bead_id": "sylveste-kgfi",
  "thread_id": "sylveste-kgfi",
  "objective": "short sentence",
  "status": "starting|working|blocked|reviewing|idle|stuck|complete|unknown",
  "branch": "main",
  "files_planned": ["interverse/intermux/**", "core/intermute/**"],
  "files_touched": ["docs/brainstorms/2026-04-29-bead-aware-cross-agent-coordination.md"],
  "last_seen": "2026-04-29T03:00:00Z",
  "confidence": "reported|observed|inferred|stale",
  "links": {
    "mail_thread": "sylveste-kgfi",
    "handoff": null,
    "cass_query": null
  }
}
```

Rules:

1. `bead_id` is the join key across systems.
2. `thread_id` defaults to `bead_id`.
3. Presence may be stale or inferred; task state still comes from Beads.
4. File intent should come from reservations when available, otherwise from observed touched files or declared planned files.
5. Any exact external platform IDs, Discord snowflakes, or auth tokens must remain out of public docs and be stored only in appropriate local metadata if needed.

## Expected operator queries

Athenmesh should make these questions cheap from Hermes/Discord:

```text
/who <repo-or-bead>
/collide <bead-or-paths>
/nudge <agent-or-bead> <message>
/handoff <bead> --to codex|claude
/presence <repo>
```

These commands are illustrative, not committed first-party Hermes commands. The v0 Athenmesh skill can produce a compact card before any slash command exists.

## Build order

### Wave 0 — conventions only

- Add this design note.
- Use `bead_id` as the shared thread handle in Hermes, Claude Code, and Codex prompts.
- When launching a coding agent, include: objective, bead, repo/path, planned files, and expected closeout.

### Wave 1 — `intermux` metadata enrichment

Goal: observe live sessions and publish a presence record when possible.

Likely changes:

- Parse active bead IDs from tmux pane content, prompts, environment variables, and Beads commands in recent output.
- Track cwd, branch, touched files, and status.
- Emit confidence: `reported`, `observed`, `inferred`, `stale`.
- Push metadata into `intermute` under a stable agent/session key.

### Wave 2 — `intermute` read model

Goal: make presence and bead-thread messages queryable.

Likely changes:

- Store/merge agent metadata fields needed for presence.
- Add or document query paths for:
  - agents by `project` / `repo`
  - agents by `bead_id`
  - messages by `thread_id == bead_id`
  - stale ack / blocked thread summaries
- Preserve cursor-based pagination and existing ack/read semantics.

### Wave 3 — `interlock` / Agent Mail file intent

Goal: make collision checks path-aware.

Likely changes:

- Standardize reservation `reason = <bead_id>`.
- Include `bead_id` in release negotiation threads.
- Provide a collision summary suitable for Hermes: holder, bead, path pattern, expiry, release/nudge path.

MCP Agent Mail may be used as prior art or an isolated bridge, but do not run its installer in a way that replaces the canonical zklw `bd` CLI. Use `--skip-beads` / `--skip-bv` if experimenting.

### Wave 4 — `Athenmesh` Hermes adapter

Goal: give Hermes a compact operator surface over the substrate.

Athenmesh v0 should be a skill/adapter, not a dispatching controller:

- Inputs: bead ID, repo path, path patterns, or vague user prompt.
- Reads: Beads, intermute/intermux metadata, interlock reservations, CASS when historical context matters.
- Output: compact coordination card with current workers, collision risk, stale/stuck signals, and suggested next action.
- Does not claim canonical task state.
- Does not create or close beads unless explicitly asked as part of backlog management.

### Wave 5 — only then consider `Intermesh`

Mint a new `Inter*` plugin only if at least two of these become true:

- Cross-repo / cross-host agent presence needs a substrate beyond `intermux` metadata.
- Coordination requires a stable public API that is not naturally owned by `intermute`, `intermux`, or `interlock`.
- Multiple non-Hermes clients need the same coordination read model.
- The integration starts accumulating code that would otherwise be duplicated across existing plugins.

Until then, `Intermesh` / `Interlink` remains a reserved future name, not a repo.

## Follow-up beads

1. **`sylveste-kgfi.1` — `[intermux] Publish active_bead_id and files_touched in agent metadata`**
   - Parse/reconcile bead ID from environment, recent pane output, and working directory Beads context.
   - Push confidence-scored metadata to Intermute.

2. **`sylveste-kgfi.2` — `[intermute] Add bead presence read model and queries`**
   - Query live agents by bead and repo.
   - Return agent id, kind, status, last_seen, and metadata confidence.
   - Blocked by `sylveste-kgfi.1` so the read model follows the published metadata contract.

3. **`sylveste-kgfi.3` — `[interlock] Standardize bead-keyed reservation summaries`**
   - Ensure reservations carry bead ID in reason/metadata.
   - Add an agent-readable collision card.

4. **`sylveste-kgfi.4` — `[Athenverse] Bootstrap Athenmesh Hermes coordination adapter`**
   - Hermes-facing coordination card: workers, collisions, stale/stuck signals, suggested next action.
   - Dogfood on a real Sylveste bead before any first-party Hermes slash command.
   - Blocked by `sylveste-kgfi.2` and `sylveste-kgfi.3`.

5. **`sylveste-kgfi.5` — `[Hermes] Evaluate prompt-style /presence command after Athenmesh dogfood`**
   - Only after Athenmesh dogfood.
   - Prompt-style read/summarize behavior first; no direct dispatch in v1.
   - Blocked by `sylveste-kgfi.4`.

## Non-goals

- Do not replace Beads.
- Do not make Discord channel history the coordination source of truth.
- Do not require every agent to use Hermes.
- Do not require every coding agent to run in tmux forever; tmux observation is a high-value v0 path, not the universal identity model.
- Do not build a new `Inter*` plugin before the existing trio proves insufficient.

## Open questions

1. Should `active_bead_id` be primarily reported by launch wrappers (`Zaka`, Hermes handoff packets) or inferred by `intermux` from pane output?
   - Recommendation: both. Reported beats inferred; inferred keeps old sessions visible.
2. Should presence records live as `intermute` agent metadata or as first-class records?
   - Recommendation: metadata in v0; first-class table only if query pressure justifies it.
3. Should Athenmesh expose `/mesh`, `/presence`, or no command initially?
   - Recommendation: no first-party command until skill dogfood. If later needed, prefer `/presence` for read-only clarity.
