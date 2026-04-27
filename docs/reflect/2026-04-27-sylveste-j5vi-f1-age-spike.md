---
artifact_type: reflection
bead: sylveste-j5vi
date: 2026-04-27
sprint_outcome: shipped
---

# Reflection — F1 AGE Cypher Benchmark Spike (sylveste-j5vi)

## What worked

- **Pre-registered decision rule with thresholds + scope language.** Forced the spike to produce a binding verdict instead of a "we ran some benchmarks, looks promising" report. The 100k p95 = 782ms result mapped mechanically onto AGE-viable; no judgment-call wiggle room. The verdict-scope sentence (triage *read* query only, not ingestion / migration / driver) protects future-us from over-extending the result.
- **Parallel plan reviewers (fd-correctness + fd-decisions) before execute.** Caught 4 P0s and 6 P1s. Two of them (vacuous valid_to filter + OPTIONAL MATCH/WHERE footgun) interacted catastrophically — fixing one alone would have produced a *worse* outcome than fixing neither. That's why parallel reviewers > sequential: different agents see different facets.
- **Hard timeouts pre-committed.** The 90-min generator timeout never tripped (actual 158s with batched UNWIND), but the discipline of stating the timeout in the plan removed sunk-cost reasoning before the executor could fall into it.
- **Container-based scratch DB.** Zero-risk reset between scales (`docker compose down -v`) made the 10k → 100k progression friction-free.

## What I'd do differently

- **The pre-registered Seq-Scan rule was honestly applied but conceptually flawed.** It targeted an implementation detail (index selection) instead of a behavior (query speed). At 5790-row Lens table, Seq Scan IS the optimal plan; the rule mechanically failed even though the actual outcome was good. **Lesson:** future spike pre-registrations should target *outcomes* (latency thresholds, plan correctness), not *means* (which index gets picked). I documented this transparently in the transcript as a qualifier rather than gaming the rule away.
- **Six F3-relevant findings emerged during execution that the plan didn't anticipate.** AGE Cypher map syntax, GIN-not-BTREE, agtype null-key omission, OPTIONAL MATCH/WHERE semantics, UNWIND batching, bridges variance. These are exactly the kind of "you only learn it by trying" things spikes are for. The plan was right to bias toward concrete fast steps over heavy upfront design.
- **Auraken-pgvector caveat could have surfaced earlier.** I caught it during plan-writing prior-art search (auraken's docker-compose), elevated it during plan review (the plan-reviewer agent agreed), and it became a P1 follow-up bead at spike completion. But ideally this kind of "the framing assumes existing infra that doesn't exist" check should be Phase 0 of any epic-scoping brainstorm, not a plan-review finding.

## What to remember (compound-engineering candidates)

- **AGE 1.6.0 idiosyncrasies for F3 / F4 / F7:** the six findings in the transcript are the load-bearing knowledge for the rest of the epic. Anyone starting F3 must read them before writing migration 001. Consider compounding into `docs/solutions/ontology/` after F3 lands.
- **Pre-registration anti-pattern:** the Seq-Scan rule taught me to write outcome-targeted thresholds, not means-targeted ones. Worth a brief addition to writing-plans guidance.
- **Spike discipline note for `/clavain:sprint --scoping` mode:** the Sprint protocol's Steps 1-2 (brainstorm + strategy) were correctly skipped because the epic-level brainstorm + PRD already existed. Confirm the `--from-step plan` flag works for child beads of already-scoped epics — it did here.
