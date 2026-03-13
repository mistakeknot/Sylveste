---
artifact_type: cuj
journey: knowledge-compound
actor: regular user (developer building institutional knowledge)
criticality: p2
bead: Demarch-2c7
---

# Knowledge Compounding

## Why This Journey Matters

Every debugging session, every architectural decision, every "oh, that's how it works" moment creates knowledge that's valuable beyond the current task. Without a compounding system, this knowledge evaporates when the session ends — the next developer (or the same developer next week) rediscovers the same things from scratch.

Knowledge compounding turns ephemeral session insights into durable, searchable institutional knowledge. It spans multiple tools: **Clavain's `/compound` and `/reflect`** (capture), **Interkasten** (knowledge base), **Intersearch** (retrieval), and **CASS** (session intelligence). The compound loop is what makes Demarch smarter over time — not just faster.

## The Journey

The developer finishes a tricky debugging session. They found that SQLite's `PERCENTILE_CONT` doesn't exist and the workaround is `ORDER BY + LIMIT 1 OFFSET`. This took 20 minutes to figure out. They run `/clavain:compound` — Clavain asks what they solved, why it was non-obvious, and where the solution lives. It writes a `docs/solutions/` entry with the problem, solution, and tags.

Later, another developer (or the same one, three weeks later) hits a similar SQLite limitation. They run `/clavain:recall "sqlite percentile"` — the recall system searches across compound docs, session history (via CASS), and auto-memory. It surfaces the previous solution: "Use ORDER BY + LIMIT 1 OFFSET for percentile approximation in SQLite."

For broader knowledge, Interkasten provides the structured knowledge base. The developer can add notes, link them to beads, and query them later. Interkasten bridges to Notion for team-wide knowledge sharing.

The `/reflect` command at sprint end captures meta-learnings: what went well, what was surprising, what should change in process. Reflections feed back into Clavain's `docs/solutions/` and inform future sprint planning.

CASS provides the raw data layer: 10K+ indexed sessions across all agent providers. `cass search "mycroft tier demotion"` finds sessions where that topic was discussed. `cass context selector.go` shows which sessions recently touched that file. This is the archaeological record that compound docs are built from.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| `/compound` creates a docs/solutions/ entry in under 2 minutes | measurable | Time from command to saved file ≤ 120s |
| `/recall` surfaces relevant prior solutions | measurable | Recall returns matching entry for known-solved problem |
| CASS search finds sessions by content | measurable | `cass search` returns relevant sessions for known queries |
| Compound docs are tagged and categorized | measurable | docs/solutions/ files have frontmatter with tags |
| Next session benefits from prior compound | qualitative | Developer doesn't re-derive previously solved problem |
| Reflection insights change future behavior | qualitative | Process improvements from reflect show up in next sprint |

## Known Friction Points

- **Compounding requires discipline** — developers must remember to run `/compound` after solving something. It's not automatic.
- **Search quality depends on tagging** — poorly tagged compound docs don't surface in recall. Tags are manual.
- **CASS indexing is async** — recent sessions may not be indexed yet. SessionStart hook auto-indexes when stale >1hr.
- **No deduplication** — multiple compound docs can cover the same topic. Manual cleanup needed.
- **Interkasten ↔ Notion sync is optional** — without Notion token configured, knowledge stays local.
