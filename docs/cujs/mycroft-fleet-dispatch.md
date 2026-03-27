---
artifact_type: cuj
journey: mycroft-fleet-dispatch
actor: regular user (developer running multi-agent fleet)
criticality: p1
bead: Sylveste-2c7
---

# Mycroft Fleet Dispatch

## Why This Journey Matters

Running five agent sessions in parallel is powerful but chaotic. Without coordination, the developer becomes a human message bus — checking which agent needs work, mentally ranking beads, copy-pasting bead IDs into tmux sessions, watching for stalls. This is the bottleneck that Mycroft exists to eliminate.

Fleet dispatch is the core Mycroft loop: observe what's happening across the fleet, rank what needs doing, and either suggest or autonomously assign work based on the current trust tier. At T0 this is purely informational. At T3 it's fully autonomous. The journey must feel safe at every tier — the developer should never wonder "what did Mycroft just do?" or "why did it pick that agent?"

## The Journey

The developer starts `mycroft run` in a dedicated tmux pane. Mycroft's patrol loop begins scanning — checking the fleet registry for active agent sessions, reading open beads from the work queue, and watching interlock for file reservation conflicts.

The first patrol cycle prints a status line: `[14:32:05] patrol: 3 agents, 7 beads, tier: T0`. At T0, Mycroft only observes. It ranks the 7 beads by priority, age, and complexity (with any user-configured priority boosts applied), filters out beads with unresolved dependencies, and logs shadow suggestions — what it *would* assign if it had authority. The developer reviews these with `mycroft shadows`, sees "would assign bug-fix-123 to grey-area", and thinks "yeah, that's right."

After a few cycles of correct shadow suggestions, the developer decides to promote: `mycroft promote --reason "shadow suggestions consistently correct for 2 days"`. Mycroft moves to T1. Now patrol cycles produce real suggestions in the dispatch log. The developer runs `mycroft shadows` (which also shows T1 suggestions) and either approves by running the dispatch manually or ignores the suggestion. Each approval or rejection feeds the track record.

At T2, things change. The developer has configured an allowlist:

```yaml
tier2_dispatch_allowlist:
  - type: task
    max_priority: 3
    max_complexity: medium
  - type: docs
    max_priority: 2
    max_complexity: any
```

When a P3 simple task comes in, Mycroft auto-dispatches: it claims the bead, spawns an agent session, generates a briefing doc, and logs the action. When a P1 complex feature arrives, Mycroft recognizes it's outside the allowlist and escalates — logging a suggestion instead, waiting for the developer to act.

At T3, Mycroft dispatches everything within the daily budget. The developer checks in with `mycroft status` or `mycroft tier` to see the summary, not individual decisions. They trust the system because it earned that trust through hundreds of correct lower-tier decisions.

If things go wrong — three consecutive failures, or a 20% failure rate over the last day — Mycroft automatically demotes itself and alerts the developer. The developer investigates, fixes the root cause, and re-promotes when confident.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Shadow suggestions match what developer would choose | qualitative | >80% agreement in post-hoc review |
| T1 suggestions have >90% approval rate before promotion | measurable | dispatch_log approval rate ≥ 0.9 |
| T2 auto-dispatches stay within allowlist | measurable | No dispatch_log entries with action=auto_dispatch for beads outside allowlist |
| Demotion triggers fire within one patrol cycle of threshold breach | measurable | Time from threshold breach to demotion ≤ patrol interval |
| `mycroft status` shows accurate fleet state | observable | Agent count, work queue, conflicts match reality |
| `mycroft tier` shows complete audit trail | measurable | All transitions have timestamp, trigger, and evidence |
| Developer never wonders "why did Mycroft do that?" | qualitative | Every dispatch is explainable from the log |

## Known Friction Points

- **No notification channel yet** — T1 suggestions only visible via `mycroft shadows`, not pushed to the developer. Future: desktop notifications, Telegram via Intercom, or Autarch TUI badge.
- **Promotion is manual-only** — developer must remember to check if criteria are met. Future: `ShouldPromote` could print a nudge during patrol.
- **Allowlist is type/priority/complexity only** — can't gate on labels, file paths, or agent capabilities yet. Good enough for v0.2 but will need extension.
- **Single fleet only** — Mycroft assumes one project. Multi-project coordination is Autarch/Bigend territory.
