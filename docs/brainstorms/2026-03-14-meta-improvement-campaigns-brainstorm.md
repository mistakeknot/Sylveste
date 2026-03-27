---
artifact_type: brainstorm
bead: Sylveste-7xm8
stage: discover
---

# Meta-Improvement Campaigns: Agents Improving the Agent Toolchain

**Bead:** Sylveste-7xm8
**Date:** 2026-03-14
**Source:** research/agi-hyperspace/ANALYSIS-EXTENDED.md section 3 (Causes domain)

## What We're Building

A self-improvement infrastructure where Sylveste's own plugins optimize themselves through interlab campaigns. Inspired by Hyperspace's "Causes" domain, where agents optimized the research process itself (search ranking, literature analysis, skill forging) and rediscovered scientific breakthroughs through mutation search.

**Two deliverables:**

1. **Mutation history store** — SQLite database owned by interlab that tracks every approach (mutation) an agent tries, with provenance chains (`inspiredBy` links to the session that inspired the approach) and monotonic progress guarantees (`isNewBest` flag prevents regression). Exposed via 3 new MCP tools: `mutation_record`, `mutation_query`, `mutation_genealogy`.

2. **Pilot campaign: interflux self-review** — flux-drive review agents review each other's `.md` definitions for quality, completeness, and consistency. Validates the end-to-end loop: agent runs campaign -> mutations recorded with provenance -> future campaigns query prior mutations to seed better hypotheses.

## Why This Approach

### Mutation store first, campaigns second

interlab campaigns already work without provenance tracking (the `reconstruct-speed` campaign achieved 22x improvement). But without the mutation store, each campaign starts from scratch — no memory of what was tried before, no ability to build on prior approaches, no cross-campaign learning.

Hyperspace's key insight: `inspiredBy` provenance chains enabled dramatically better search efficiency than random mutation. The store is the foundation that makes meta-improvement *compound* rather than *episodic*.

### SQLite over JSONL

Cross-campaign queries are the core value prop ("what approaches worked for plugin-quality tasks?"). JSONL per campaign would match interlab's existing pattern but can't efficiently answer cross-campaign questions. SQLite adds one dependency but enables:
- Query best approaches by task type across all campaigns
- Trace genealogy trees (which idea led to which improvement)
- Aggregate quality signals for dashboard/analytics
- Future: Skaffen Orient phase reads mutation history before generating hypotheses

### interlab owns the store

Single owner, clear API boundary. interlab already owns the experiment lifecycle — mutations are a natural extension. Other plugins (Skaffen, interflux) query via interlab's MCP tools rather than direct DB access.

### New MCP tools, not extended existing ones

Experiments and mutations are conceptually different:
- An experiment is a single run of a benchmark with a hypothesis
- A mutation is a provenance-tracked approach that may span multiple experiments

Separating them avoids conflating experiment logs with mutation genealogy and makes cross-campaign queries straightforward.

### interflux as the pilot

Highest leverage: improving the review agents makes ALL future reviews better. The metric is concrete (agent audit score from flux-drive's own quality criteria). And it's poetic — the review system reviewing itself.

## Key Decisions

1. **Scope:** Mutation store + one pilot campaign. Future campaigns (interskill, intercheck, interlab-self) are separate beads.
2. **Storage:** SQLite database, owned by interlab, located at `~/.local/share/interlab/mutations.db` (shared across projects).
3. **API:** 3 new MCP tools on interlab's server — `mutation_record`, `mutation_query`, `mutation_genealogy`.
4. **Integration:** `/autoresearch` skill calls `mutation_record` after each experiment. Campaign startup calls `mutation_query` to seed hypotheses from prior approaches.
5. **Pilot campaign:** interflux agents reviewing their own `.md` definitions. Metric: composite agent quality score (structure, completeness, trigger accuracy, tool appropriateness).
6. **Provenance model:** `inspiredBy` links to session IDs (queryable via CASS). `isNewBest` is computed automatically by comparing quality signal to current best for the same task type.

## Open Questions

1. **Mutation store schema:** Exact columns, indexes, and constraints for the SQLite DB. Needs design during planning.
2. **Agent quality metric:** What specific scoring rubric should the interflux self-review campaign optimize? The 19-point interskill audit is one option but was designed for skills, not agents.
3. **Campaign template:** Even though we're not shipping a formal template this iteration, the pilot campaign's structure should be designed to be replicable. Document patterns as we build.
4. **Skaffen integration timeline:** Skaffen's Orient phase should eventually read mutation history before generating hypotheses. Not in scope for this bead but should inform the mutation_query API design (make it Skaffen-friendly).
5. **isNewBest semantics:** Single-dimensional (scalar quality) or multi-dimensional (Pareto dominance)? Start simple (scalar), upgrade later if needed.

## Candidates for Future Campaigns (Not In Scope)

| Campaign | Self-improves | Metric | Leverage |
|----------|--------------|--------|----------|
| interskill self-audit | 19-point checklist | Audit pass rate on own skills | Medium |
| intercheck self-improvement | syntax-check.sh, auto-format.sh | False positive/negative rate | Low |
| interlab benchmark optimization | plugin-benchmark.sh | PQS accuracy vs manual review | High (circular risk) |
| interpath doc quality | Generated PRDs, roadmaps | Doc completeness score | Medium |
