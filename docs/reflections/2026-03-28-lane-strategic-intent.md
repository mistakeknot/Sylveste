---
bead: sylveste-rsj.1.1
type: reflection
date: 2026-03-28
---

# Reflection: Lane Strategic Intent (sylveste-rsj.1.1)

## What worked
- Plan review caught 2 P0 bugs before any code was written — the metadata-as-string serialization issue would have been a silent failure in production
- Dedicated column was the right call over metadata JSON — simpler queries, no TOCTOU race, no JSON parsing in shell
- `bd set-state` for intent delivery is zero-migration on the run side — pragmatic choice that works today

## What we learned
- **Schema reviews > code reviews for data model changes.** The JSON-string-not-object bug was invisible in the plan's pseudocode but obvious once you trace the data through `json.NewEncoder → jq`. Plan reviews that trace data through serialization boundaries catch this class of bug.
- **"No migration needed" is not always a virtue.** The plan's original justification for metadata JSON was "no schema migration needed" — but the migration was trivial (one ALTER TABLE) while the metadata approach had 3 correctness issues.
- **Intent delivery is the hardest part of intent storage.** Storing intent on the lane was straightforward. Getting it to the agent's briefing required choosing between 3 options (ic run flag, bd set-state, goal-string injection), none of which were specified in the original plan.

## Risks to watch
- Lane intent is currently free text with no validation. If we add LLM-as-judge evaluation at sprint boundaries (open question #1 from brainstorm), the intent needs to be structured enough for that.
- The `bd set-state` delivery means intent is only injected at sprint creation time. If intent changes mid-epic, existing sprints keep the old value. This is probably fine for now but `/campaign` (rsj.1.11) may need a refresh mechanism.
