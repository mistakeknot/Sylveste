---
agent: fd-workflow-automation-idempotency
track: adjacent
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P0] CLAUDE.md append is not idempotent — repeated runs produce duplicate entries

**Issue:** Option A (line 70-78) describes a "classification + routing step" that writes learnings to targets, and Option E recommends this as the core mechanism. The write operation for CLAUDE.md is described as "append" (line 73: "append to CLAUDE.md"). Running the reflect step twice on the same sprint — or running it on two sprints that independently surface the same lesson — appends the same content twice. There is no content-addressable check or upsert semantic.

**Failure scenario:** A session crashes after the reflect step writes to CLAUDE.md but before the bead is closed. The next session re-runs reflect on the same sprint. CLAUDE.md now has two identical entries: "Never use `which` for binary detection — use `command -v`." Over 3 months of occasional re-runs and similar learnings, CLAUDE.md accumulates 15+ duplicate or near-duplicate lines. This directly matches the P0 calibration scenario in the agent spec.

**Fix:** The write step must be upsert, not append. Before writing any entry, grep the target file for the core assertion (the "what to do" clause). If a semantic match exists, update the existing entry's date/context rather than appending. For CLAUDE.md specifically, require that each routed entry has a unique identifier comment (e.g., `# [2026-03-29] binary-detection`) that enables exact-match dedup.

### [P1] No conflict detection between contradictory learned rules

**Issue:** The brainstorm does not address what happens when two sessions produce contradictory learnings. The classification step (Option A, line 72) routes each learning independently without comparing against existing rules. The six targets are all append-only stores with no consistency validation.

**Failure scenario:** Sprint 41 learns "always pin dependency versions in CI" and routes it to CLAUDE.md. Sprint 58 learns "use floating versions to get security patches automatically" and routes it to CLAUDE.md. Both entries coexist. An agent encountering both follows whichever it reads last (position-dependent behavior), or attempts to satisfy both and produces an incoherent result. This matches the P1 calibration scenario.

**Fix:** Before writing a new rule to any target, the router must check for semantic contradiction with existing entries. If a conflict is detected, the router should either (a) present both to the user for resolution, or (b) replace the older entry with the newer one and note the supersession in the audit log. Add a `# Conflict check` step to the router prompt.

### [P1] No provenance metadata for rollback

**Issue:** Option A step 4 mentions "optionally append a one-liner to a lightweight log file for audit trail" (line 74). The word "optionally" means provenance is not guaranteed. None of the options describe what metadata accompanies a CLAUDE.md or code write — no session ID, no date, no source bead, no author. The existing MEMORY.md convention (line pattern `# [date] lesson`) provides a date but no session or bead reference.

**Failure scenario:** A CLAUDE.md rule introduced by the router causes a subtle behavioral regression (e.g., agents now over-aggressively use hooks for trivial preferences). The operator wants to identify and revert the problematic entry but cannot determine which session or sprint introduced it. Manual git blame is possible but requires knowing which line to blame. Without inline provenance, the search space is the entire CLAUDE.md history.

**Fix:** Make provenance mandatory, not optional. Every router-written entry must include: date, source bead ID, and a one-line rationale. Follow the existing MEMORY.md convention but extend it: `# [2026-03-29:sylveste-b49] binary-detection: use command -v not which`. This enables targeted rollback via grep for the bead ID.

### [P2] Durable change gate (Option B) has no idempotent escape hatch

**Issue:** Option B (line 82-85) requires "at least 1 file outside docs/reflections/ was modified by the reflect step." The brainstorm notes the need for an escape hatch for "no-learning sprints" but does not specify how it works. If the escape hatch is "explicitly state no learnings," what prevents an agent from gaming it by always stating "no actionable learnings" to skip the gate?

**Failure scenario:** After three sprints where the gate forces low-value writes to CLAUDE.md (because the agent needs to pass the gate but has no genuine learning), agents learn that the path of least resistance is to write a trivial entry like "# [date] sprint went well" or to always trigger the escape hatch. The gate becomes cargo cult — formally satisfied but producing noise rather than signal. This is the bypass culture pattern.

**Fix:** The escape hatch should require a specific format: "No durable changes needed because: [concrete reason]." The gate should also track escape-hatch frequency — if more than 30% of sprints use the escape hatch, flag it as a signal that either the threshold is too low or learnings are being suppressed. Rate-limiting the escape hatch prevents gaming without eliminating legitimate use.

### [P2] Configuration drift between router-written and manually-written CLAUDE.md entries

**Issue:** CLAUDE.md is currently hand-maintained (the existing project CLAUDE.md has carefully organized sections with specific formatting). The router will append entries in its own format. Over time, CLAUDE.md will contain two "voices" — hand-crafted sections and machine-appended entries — with no unified maintenance strategy.

**Failure scenario:** A human reorganizes CLAUDE.md, moving sections around and consolidating. The router's entries are scattered, some orphaned from their original context. The next router append writes to a section that no longer exists or duplicates content that was consolidated. The file drifts into an inconsistent state where neither the human nor the router can maintain it cleanly.

**Fix:** Designate a specific section in CLAUDE.md for router-written entries (e.g., `## Learned Rules` at the bottom). The router only writes within this section. Human-maintained content stays in its existing structure. This creates a clear boundary and prevents interleaving. The consolidation step (from the P0 finding) operates only on this section.
