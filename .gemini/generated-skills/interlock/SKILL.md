---
name: interlock
description: "MCP server for intermute file reservation and agent coordination. 12 tools: reserve, release, conflict check, messaging, agent listing, negotiation, escalation. Companion plugin for Clavain."
---
# Gemini Skill: interlock

You have activated the interlock capability.

## Base Instructions
# interlock — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Sylveste's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


MCP server for intermute-backed file reservation and agent coordination. Companion plugin for Clavain.

## Quick Reference

| Item | Value |
|------|-------|
| Namespace | `interlock:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 11 tools, 4 commands, 2 skills, 3 hooks |
| Binary | `bin/interlock-mcp` |

## MCP Tools (11 total)

| Tool | Purpose |
|------|---------|
| `reserve_files` | Reserve one or more file patterns before editing. |
| `release_files` | Release reservations by reservation ID. |
| `release_all` | Release all active reservations for the current agent. |
| `check_conflicts` | Dry-run conflict check for file patterns. |
| `my_reservations` | List current active reservations for this agent. |
| `send_message` | Send a direct message to another agent. |
| `fetch_inbox` | Fetch inbox messages and run negotiation-timeout checks. |
| `list_agents` | List active agents in the current project. |
| `request_release` | Legacy release request tool (deprecated; use negotiation tools). |
| `negotiate_release` | Start a release negotiation with urgency + optional blocking wait. |
| `respond_to_release` | Resolve negotiation by releasing now or deferring with ETA. |
| `force_release_negotiation` | Escalation: force-release after negotiation timeout (requester-initiated). |

## Negotiation Protocol

- `negotiate_release` sends a `release-request` message with `urgency` (`normal` or `urgent`) and a generated `thread_id` for tracking.
- `wait_seconds` on `negotiate_release` enables blocking-wait mode: the tool polls the negotiation thread and returns `release`, `defer`, or `timeout` status. On timeout, the response includes `can_escalate: true` with a hint to use `force_release_negotiation`.
- `respond_to_release` handles both actions:
  - `action='release'` releases matching reservations and sends `release-ack`.
  - `action='defer'` keeps reservation, includes `eta_minutes`/`reason`, and sends `release-defer`.
- `force_release_negotiation` is the escalation path: when `negotiate_release` times out, the requester can explicitly force-release the holder's reservation. Validates pre-conditions (timeout exceeded, no existing ack) before releasing. Sends `release-ack` with `forced: true` to the thread and notifies the holder.
- `INTERLOCK_AUTO_RELEASE=1` enables advisory mode in `hooks/pre-edit.sh`: pending release requests are surfaced as context with suggested `respond_to_release(...)` calls.
- Timeout escalation uses advisory-only enforcement: `CheckExpiredNegotiations` (called from `fetch_inbox`) identifies expired negotiations and returns advisory information — it does NOT force-release reservations. Holder agents see timeout context on their next edit via `pre-edit.sh` (when `INTERLOCK_AUTO_RELEASE=1`). Thresholds: `urgent` at 5 minutes, `normal` at 10 minutes. Constants exported from `internal/client`: `NormalTimeoutMinutes`, `UrgentTimeoutMinutes`, `NegotiationPollInterval`.
- `/interlock:status` includes a pending negotiations table showing requester, holder, file, urgency, age, and current status.



