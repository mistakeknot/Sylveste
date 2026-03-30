---
artifact_type: reflection
bead: sylveste-rsj.1.8
stage: reflect
---

# Reflect: Compound Autonomy Guard (rsj.1.8)

## What worked
- The multiplication model (tier × level) is simple enough to implement in bash and reason about
- Adding capability_level to the fleet registry is additive — no existing behavior changes
- The test fixture pattern (inline YAML + policy file) made tests easy to write and fast to run

## Design decisions
- Chose dispatch-time gating over runtime monitoring — avoids the monitoring paradox (who watches the watcher?)
- Used return codes (0/1/2/3) for machine-readable classification while printing human-readable verdicts to stdout
- Defaulting unset agents to L2 (local mutations) is conservative — won't block review agents but won't let unknown agents push code

## What to watch
- Mycroft doesn't yet set `mycroft_tier` as bead state — the session-start.sh check reads it but it won't fire until Mycroft writes it. This is expected; Mycroft integration is a separate track.
- The schema JSON was not updated (fleet-registry.schema.json) — it's not enforced at runtime so skipped to keep scope tight. Should be added when the schema is next touched.
