# fd-proposals-schema-integrity-interlore

**Reviewer:** fd-proposals-schema-integrity
**Scope:** Task 3 proposals schema and skill state management in `docs/plans/2026-03-21-interlore.md`, cross-referenced with PRD `docs/prds/2026-03-21-interlore.md` and live `PHILOSOPHY.md`.

---

## Finding 1: "Deferred" is a phantom status — state transition diagram contradicts status display

**Severity:** Design contradiction

The proposals-schema.md declares four statuses: `pending | accepted | rejected | deferred`. The status transition section says:

> `pending` -> `deferred` (stays pending for next cycle)

And the observe skill's Review Mode says:

> **Defer**: Keep as "pending". Move to next proposal.

So "defer" never writes `status: "deferred"` -- it leaves the proposal as `status: "pending"`. But Status Mode displays `Deferred: N` as a separate line item. There is no way to count deferred proposals because they are indistinguishable from never-reviewed pending proposals.

**Options:**
1. Write `status: "deferred"` with a `deferred_at` timestamp. Scan treats deferred the same as pending (re-evaluates). Status counts them separately.
2. Remove "Deferred: N" from the status display. Accept that defer is invisible.
3. Add a `defer_count: 0` field to each proposal that increments on defer but keeps status as `pending`. Status reads this.

**Recommendation:** Option 1. It costs one enum value and makes the state machine honest. The scan's merge logic can treat `deferred` identically to `pending` for re-evaluation purposes without any ambiguity.

---

## Finding 2: No evidence_history or version field on proposals — merge is lossy

**Severity:** Data loss risk

Phase 6 says:

> Merge new proposals with existing pending ones (update evidence if tradeoff_axis matches).

This means a rescan of the same tradeoff_axis overwrites the evidence array. If scan N found evidence items A, B, C and scan N+1 finds B, C, D, the merge replaces evidence with B, C, D — silently dropping A. The `unique_decisions` count is recomputed from evidence, so the decision count can also decrease.

There is no `evidence_history`, no per-evidence `first_seen` timestamp, and no proposal-level version counter to detect this.

**Recommendation:** Evidence merge should be append-deduplicate (by `path` + `bead` composite key), not replace. Add `first_seen: "2026-03-21"` to each evidence item so the union preserves discovery provenance. This also makes `unique_decisions` monotonically non-decreasing for a given proposal, which matches the mental model of "accumulating evidence."

---

## Finding 3: rejected_patterns has no schema version — silent suppression rot

**Severity:** Long-term durability risk

`rejected_patterns` entries contain only:
```yaml
- tradeoff_axis: "integration vs reimplementation"
  rejected_at: "2026-03-20"
  reason: "Too specific to one domain"
```

Phase 5 says: "Skip any tradeoff_axis that appears in rejected_patterns." This is an exact string match on `tradeoff_axis`.

Problems:
- **Fuzzy clustering vs exact suppression.** Phase 4 uses "fuzzy match on axis description" to cluster tradeoffs, but Phase 5 uses exact match against rejected_patterns. A rescan that clusters slightly differently (e.g., "integration vs reimplementation" becomes "adopt vs rebuild") bypasses the rejection silently.
- **No schema version.** If the tradeoff_axis naming convention changes in a future schema version, all existing rejections become dead entries that suppress nothing.
- **No expiry.** A rejection from six months ago when the project had 10 artifacts may be wrong when the project has 500. There is no TTL or re-evaluation trigger.

**Recommendation:** Add `schema_version: 1` to each rejected_pattern entry. Add `original_proposal_id` to link back to the rejected proposal. Consider adding `expires_at` or `evidence_count_at_rejection` so rejections can be reconsidered when the evidence base grows substantially (e.g., 3x the evidence count at rejection time).

---

## Finding 4: proposed_section is exact string — fragile against PHILOSOPHY.md refactoring

**Severity:** Moderate

The schema uses `proposed_section: "Composition Over Capability"` as a string. The review skill's Accept action says:

> Read PHILOSOPHY.md, find the proposed_section, append proposed_text.

This is a section header lookup. The actual PHILOSOPHY.md has these H2 sections:
- `## The Core Bet`
- `## Receipts Close Loops`
- `## Earned Authority`
- `## Composition Over Capability`
- `## Memory Architecture`
- `## Strong Defaults, Replaceable Policy`
- `## Naming`
- `## End State`

If anyone renames a section (e.g., "Composition Over Capability" becomes "Composition Over Monoliths"), every pending proposal targeting that section silently fails to find its target. The skill has no fallback behavior specified.

**Recommendation:** The accept action should: (1) attempt exact match on `## {proposed_section}`, (2) if no match, attempt fuzzy match (substring, Levenshtein), (3) if still no match, present the user with the list of actual sections and ask where to place it. This fallback should be specified in the skill, not left to LLM improvisation.

---

## Finding 5: conforming_patterns in scan_stats but absent from proposals array — accounting gap

**Severity:** Minor, but auditable gap

`scan_stats` includes:
```yaml
conforming_patterns: 3
```

The proposals array only contains `type: "emerging" | "drift"`. Conforming patterns are "logged in stats, not proposed." But there is no `conforming_patterns` array anywhere in the schema — just a count. This means:
- Status mode cannot report which patterns are conforming (only how many).
- There is no way to verify the count is correct.
- A subsequent scan cannot determine whether a pattern was already classified as conforming, so it must re-derive from scratch.

**Recommendation:** Add a lightweight `conforming` array to the schema:
```yaml
conforming:
  - tradeoff_axis: "composition over monolith"
    philosophy_section: "Composition Over Capability"
    evidence_count: 5
```
This costs minimal space and makes conforming patterns verifiable, reportable, and diffable across scans.

---

## Finding 6: No scan_id or run provenance — multiple scans are ambiguously merged

**Severity:** Moderate

The schema has `last_scan: "2026-03-21T17:00:00Z"` but no scan ID. When Phase 6 says "merge new proposals with existing pending ones," there is no way to distinguish:
- Which evidence items came from which scan.
- Whether a proposal's evidence was entirely refreshed or incrementally grown.
- Which scan generated a particular proposal (for debugging false positives).

If two scans run in quick succession (e.g., user runs scan, notices a missing artifact, adds it, runs scan again), the merge silently overwrites with no audit trail.

**Recommendation:** Add `scan_id: "scan-001"` (incrementing) and `last_scan_id` to both the root and each proposal/evidence item. This is cheap and makes the provenance chain reconstructable:
```yaml
scan_history:
  - scan_id: "scan-001"
    timestamp: "2026-03-21T17:00:00Z"
    artifacts_scanned: 12
  - scan_id: "scan-002"
    timestamp: "2026-03-21T17:30:00Z"
    artifacts_scanned: 14
```
Each evidence item gets `added_in: "scan-001"`. This also enables Finding 2's append-deduplicate to be auditable.

---

## Finding 7: PRD schema and plan schema diverge on scan_stats

**Severity:** Minor inconsistency

The PRD (docs/prds) proposals schema does NOT include `scan_stats` or `conforming_patterns`:
```yaml
version: 1
last_scan: "..."
proposals: [...]
rejected_patterns: [...]
```

The plan (docs/plans) proposals-schema.md reference adds:
```yaml
scan_stats:
  artifacts_scanned: 12
  patterns_detected: 5
  proposals_generated: 2
  conforming_patterns: 3
```

The plan is authoritative for implementation, but the PRD acceptance criteria for F3 say:
> `/interlore:status` shows: last scan date, proposal count by type and classification, **pre-threshold candidate count, conforming pattern count**

"Pre-threshold candidate count" (nascent patterns below the 2-decision threshold) appears in neither schema. It is expected in status output but has no field to source from.

**Recommendation:** Reconcile: add `nascent_count` to `scan_stats` in the plan schema. Either update the PRD to match the plan's scan_stats block, or note that the plan supersedes the PRD schema.

---

## Summary

| # | Finding | Severity | Fix complexity |
|---|---------|----------|----------------|
| 1 | Deferred is phantom status | Design contradiction | Low (add enum value) |
| 2 | Evidence merge is lossy | Data loss risk | Low (append-dedup + first_seen) |
| 3 | rejected_patterns has no version/expiry | Durability risk | Low (add fields) |
| 4 | proposed_section is fragile exact match | Moderate | Low (specify fallback) |
| 5 | conforming_patterns is count-only | Minor | Low (add lightweight array) |
| 6 | No scan provenance | Moderate | Medium (add scan_id chain) |
| 7 | PRD/plan schema divergence | Minor | Low (reconcile) |

None of these block implementation. Findings 1 and 2 should be addressed before Task 3 implementation begins, as they affect the core state machine correctness. Findings 3-7 can be addressed during or after implementation.
