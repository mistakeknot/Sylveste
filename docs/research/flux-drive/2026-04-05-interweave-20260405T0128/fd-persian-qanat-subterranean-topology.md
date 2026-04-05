### Findings Index
- P1 | QANAT-1 | "F3: Connector Protocol" | Observation contract specifies entity existence but not operational depth per connector
- P1 | QANAT-2 | "F5: Named Query Templates" | causal-chain query (3 hops) traverses subsystems with undefined observation depth — cannot guarantee causal reasoning across boundary
- P2 | QANAT-3 | "F2: Identity Crosswalk" | Identity chain recording captures rename lineage but not split/merge — function split creates orphan chains
- P2 | QANAT-4 | "F4: Confidence Scoring" | Staleness detection uses TTL but lacks flow-rate proxy — cannot distinguish stale-but-stable from stale-and-changed
- P2 | QANAT-5 | "F7: Gravity-Well Safeguards" | Finding-aid audit deletes and rebuilds but does not verify subsystem function degradation during the gap
Verdict: needs-changes

## Summary

The PRD demonstrates strong structural awareness of the observation-versus-inference problem (the qanat pattern). The connector protocol's observation contract (F3, line 52) and the confidence scoring system (F4) show that the brainstorm's "observation shaft density" insight was heard. However, the acceptance criteria do not close the loop: the contract specifies *what* a connector captures (entities_indexed, granularity, properties) but never requires a connector to declare *how deep* its observation reaches into the source system. This is the difference between a qanat shaft that shows water level and one that shows flow direction.

## Issues Found

### QANAT-1 (P1): Connector observation contract lacks depth declaration

**File**: `docs/prds/2026-04-05-interweave.md`, lines 51-58 (F3 acceptance criteria)

The observation contract format specifies: `entities_indexed, granularity, properties (captured/inferred), refresh_cadence, freshness_signal`. This tells interweave *what* a connector observes and *how often*, but not *how deeply*. 

**Concrete failure scenario**: The cass connector indexes `sessions, tool calls (nested), files_touched`. But does it index the *content* of tool calls (which file edits were made, which lines changed) or only tool call *metadata* (tool name, timestamp, duration)? An agent queries `causal-chain parseConfig` and gets back "session S touched parseConfig via tool_call T" — but cannot answer "what did session S do to parseConfig?" because the observation stopped at the tool_call level.

The qanat analogy: you built a shaft at kilometer 5 and can see water level. But you cannot tell whether the water is flowing or pooled. The shaft needs a flow gauge, not just a level gauge.

**Recommended fix**: Add `observation_depth` to the observation contract — a per-entity-type declaration of what properties are directly observed vs inferred. Example: `cass: {sessions: [id, model, tokens, start, end], tool_calls: [name, timestamp, target_file], file_edits: NOT_OBSERVED}`. This makes it explicit that the cass connector is a "level gauge" for file edits, not a "flow gauge."

### QANAT-2 (P1): causal-chain query traverses unverified observation boundaries

**File**: `docs/prds/2026-04-05-interweave.md`, lines 83-84 (F5 acceptance criteria)

The `causal-chain <entity>` query traverses `blocks/caused-by/discovered-from` relationships up to 3 hops with max 20 results. This is the most ambitious query template — it promises backward causal reasoning across subsystem boundaries.

**Concrete failure scenario**: An agent queries `causal-chain bead-xyz` (why did this bead stall?). Hop 1: bead-xyz blocks bead-abc (from beads connector — rich, reliable). Hop 2: bead-abc was discovered-from review finding R (from flux-drive connector — moderate depth). Hop 3: review finding R was triggered by session S touching function F (from cass connector — shallow depth, tool-call metadata only). The agent receives a 3-hop chain that *looks* causal but the hop 2→3 link is speculative: the connector observed temporal co-occurrence, not causation.

The qanat analogy: the tunnel crosses from clay (beads — well-observed) through grite (flux-drive — moderate) into sand (cass — shallow). The muqanni builds the tunnel the same way in all three terrains, but sand requires a different technique. The tunnel collapses in the sand section because the construction method was not adapted to the terrain.

**Recommended fix**: Add a `max_confidence_hop` constraint to causal-chain queries. The traversal should stop (or flag) when it crosses from a "confirmed" link to a "speculative" link. This respects F4's confidence scoring but applies it *during traversal*, not just at result display time. Acceptance criterion: "causal-chain traversal degrades gracefully at observation boundaries — when a hop crosses from confirmed to speculative confidence, the result includes an explicit boundary marker."

### QANAT-3 (P2): Identity chain does not handle function splits

**File**: `docs/prds/2026-04-05-interweave.md`, lines 40-41 (F2 acceptance criteria)

The identity chain records `fn_v1 → renamed_to → fn_v2`. This handles renames and moves well. But functions also *split* (one function becomes two) and *merge* (two functions become one). A split creates a 1:N relationship that the `renamed_to` chain cannot represent — fn_v1 becomes fn_v2a and fn_v2b. The chain would need to track fn_v1 → split_into → [fn_v2a, fn_v2b].

**Failure scenario**: Developer extracts a helper function from parseConfig. The original parseConfig still exists (modified) and a new validateConfig exists. The crosswalk tracks parseConfig v1 → parseConfig v2 but does not link parseConfig v1 to validateConfig. Agents querying "who touched validateConfig" miss all pre-split history.

**Recommended fix**: Extend identity chain types from `renamed_to` to include `split_into` and `merged_from`. This is a P2 because the body-similarity heuristic (>80% match) will catch some splits organically, but not the common case where extracted code is <80% of the original body.

### QANAT-4 (P2): Staleness TTL is binary — no flow-rate signal

**File**: `docs/prds/2026-04-05-interweave.md`, lines 71, 107 (F4 and F7)

The staleness model is TTL-based: entities not re-verified within TTL are flagged stale (F4 line 71), and entities not refreshed within 30 days are excluded (F7 line 107). This treats all entities equally, but entity change velocity varies enormously: a function definition may be stable for months (TTL-stale but actually current), while a session list changes every hour (within-TTL but potentially stale).

**Recommended fix**: Add an optional `expected_churn` property to the observation contract. Connectors can declare per-entity-type change velocity. The staleness check becomes: `time_since_refresh > TTL * churn_factor`. Low-churn entities (code structure) tolerate longer refresh windows. High-churn entities (sessions) need tighter windows. This is P2 because the 30-day TTL is a reasonable default, but it will cause false exclusions for stable entities and false currency for volatile ones.

### QANAT-5 (P2): Finding-aid audit has a visibility gap during rebuild

**File**: `docs/prds/2026-04-05-interweave.md`, lines 108-109 (F7)

The `interweave audit` command "deletes the entire index, verifies all subsystems still function, and rebuilds." During the delete→rebuild window, agents cannot query interweave. The acceptance criterion verifies that subsystems still function without interweave (good — this is the finding-aid test). But it does not verify that agents *know* interweave is unavailable during the audit.

**Recommended fix**: Add to F7 acceptance criteria: "During audit, interweave health returns `status: rebuilding` with estimated completion time. Query templates return `{status: unavailable, fallback: [direct subsystem instructions]}` rather than empty results or errors."

## Improvements

1. **Observation contract visualization**: Add an acceptance criterion to F8 (documentation) requiring a table showing each connector's observation depth per entity type. This makes the "shaft placement" visible at a glance rather than buried in connector implementations.

2. **Connector observation tests**: Add to F3 a requirement that each connector includes a test verifying its observation_depth declaration is accurate — that the properties it claims to capture are actually present in harvested data. This prevents "phantom shafts" — declared observations that the connector cannot actually make.

<!-- flux-drive:complete -->
