---
bead: sylveste-rsj.1.3
type: reflection
date: 2026-03-28
---

# Reflection: Review Queue Backpressure (sylveste-rsj.1.3)

## What worked
- The proportional penalty (5 points per excess review) is a softer response than a binary gate — dispatch continues at reduced priority rather than halting entirely
- "In the weeds" cap reduction at 2x threshold is the circuit breaker for flow — when the system is deeply backed up, producing one more piece of work per session is the right response
- Single-file change with clear boundaries — all backpressure logic lives in lib-dispatch.sh

## What we learned
- **Review detection is the weak point.** We're counting `needs-review` labels + beads in shipping phase, but there's no formal "review queue" data structure. This works for now but `/campaign` will need a real review tracking mechanism.
- **Backpressure is computed per-dispatch, not cached.** Each call to `_dispatch_review_pressure` does two `bd list` calls. In a high-dispatch session this could be slow. Acceptable for now (dispatch cap is 5/session max) but worth monitoring.

## Risks to watch
- The `DISPATCH_CAP=1` override in "in the weeds" mode mutates a global variable for the rest of the session. This is intentional (session-scoped) but could surprise if dispatch_attempt_claim is called in a context where DISPATCH_CAP should be preserved.
