---
artifact_type: cuj
journey: mycroft-failure-recovery
actor: regular user (developer managing fleet under stress)
criticality: p2
bead: Demarch-2c7
---

# Mycroft Failure Recovery and Intervention

## Why This Journey Matters

Autonomous systems are only as trustworthy as their failure modes. A fleet coordinator that works perfectly 95% of the time but fails silently the other 5% is worse than manual coordination — at least with manual, the developer knows when they missed something. Mycroft must make failures visible, recoverable, and educational (each failure informs the trust model).

This journey covers what happens when things go wrong: an agent stalls, a dispatch fails, the failure rate spikes, or the developer needs to intervene directly. The developer's confidence in Mycroft depends not on zero failures but on transparent, predictable failure handling.

## The Journey

The developer has Mycroft running at T2. Three agents are active, each working on a bead. The patrol cycle reports normally: agents healthy, work progressing. Then agent "grey-area" stops heartbeating. The next patrol cycle detects the stale claim — the bead is stuck.

At T2, Mycroft can auto-retry recoverable failures. It logs the detection, unclaims the bead, and re-dispatches to a different available agent. The developer sees this in the next `mycroft shadows` output: "reassigned bug-fix-456 from grey-area (stale 15min) to mistake-not." If the re-dispatch succeeds, the incident is logged and the track record updated.

But sometimes failures cascade. Two dispatches fail in a row — the agent can't clone the repo, or the bead's dependencies weren't actually resolved. Then a third fails. Mycroft's consecutive-failure trigger fires: three failures on different beads trips the circuit breaker. Mycroft demotes itself from T2 to T1, logs the demotion with evidence ("3 consecutive failures"), and stops auto-dispatching.

The developer notices the tier change via `mycroft tier`:

```
Current tier: T1

Recent transitions:
  TIME        FROM  TO  TRIGGER               REASON
  03-13 14:45 T2    T1  consecutive_failures  3 consecutive failures
  03-12 09:00 T1    T2  manual                earned T2 after 25 successful suggestions
```

They investigate: `mycroft shadows --limit 10` shows the three failed dispatches with reasons. The developer fixes the underlying issue (a git auth problem affecting all agent sessions), verifies it's resolved, and manually re-dispatches the stuck beads with `mycroft override bug-fix-456 mistake-not --reason "git auth fixed"`.

Once satisfied, the developer re-promotes: `mycroft promote --reason "root cause fixed, git auth issue"`. The track record resets — Mycroft must re-earn T2 through a fresh run of successful suggestions.

For immediate interventions, the developer can:
- `mycroft pause` — stop all dispatching while investigating (in-flight agents continue)
- `mycroft pause --drain` — also signal agents to checkpoint and stop (future)
- `mycroft resume` — re-enable dispatching
- `mycroft override <bead> <agent>` — manually assign specific work
- `mycroft demote --reason "lost confidence"` — manually drop a tier

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Stale agents detected within 2 patrol cycles | measurable | Detection latency ≤ 2× patrol interval |
| Consecutive failure demotion fires correctly | measurable | 3 failures → tier drops by 1 within next cycle |
| Rate-based circuit breaker fires at threshold | measurable | T2 demotes at >15% failure rate, T3 at >25% |
| `mycroft tier` shows demotion reason and evidence | measurable | Transition record includes trigger + evidence JSON |
| Manual override bypasses normal ranking | measurable | `override` command logs to dispatch_log with action=override |
| Pause/resume stops and restarts dispatching cleanly | measurable | No dispatches logged between pause and resume |
| Developer can diagnose root cause from Mycroft output alone | qualitative | Failure reasons in dispatch log are actionable |

## Known Friction Points

- **No watchdog yet** — stale agent detection is planned (v0.2 watchdog bead) but not implemented. Currently relies on patrol seeing stale claims.
- **Recovery is manual** — Mycroft can demote itself but can't auto-fix the underlying problem. Future: retry with exponential backoff, auto-unclaim stale beads.
- **`--drain` flag is not yet wired** — pause works but drain (checkpoint + stop agents) needs spawn/agent protocol work.
- **No alerting** — demotion only visible via `mycroft tier`. No push notification. Same friction as the dispatch journey.
- **Track record resets fully on re-promotion** — could be more nuanced (partial credit for pre-demotion history).
