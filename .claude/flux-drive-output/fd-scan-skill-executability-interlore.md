---
agent: fd-scan-skill-executability
mode: review
target: docs/plans/2026-03-21-interlore.md
timestamp: 2026-03-21
---

# Scan Skill Executability Review: interlore observe SKILL.md

## CRITICAL: Phase 3 "Read first 100 lines" truncates decisions from 40%+ of long artifacts

**Severity: High — silent recall loss**

The SKILL.md instructs: "For each artifact (Read first 100 lines)". Empirical analysis of the actual corpus:

- **9 brainstorms** have their `## Key Decisions` section starting *past* line 100 (e.g., skaffen-sovereign at line 144, mycroft-fleet at line 139, oodarc-loops at line 384, plugin-synergy-catalog at line 302).
- **27 individual `**Decision:**` entries** in brainstorms appear past line 100. The skaffen-sovereign brainstorm alone has 12 decisions past line 100.
- **20+ tradeoff-language matches** in flux-drive outputs appear past line 100 (files range up to 866 lines).
- The ai-factory-orchestration brainstorm (259 lines) contains 9 key decisions (numbered list at line 62-80) that *are* within 100 lines, but its detailed rationale and tradeoff language ("Hybrid pull + intent, not pure push, not pure pull") starts at line 41 and continues well past 100.

**The 100-line limit will miss approximately 30-40% of decision content in longer artifacts.** Short brainstorms (<100 lines, e.g., khouri-domain-model at 33 lines, interlore at 79 lines) are fully captured, but the richest decision artifacts are the long ones.

**Fix:** Replace the fixed 100-line limit with a two-pass strategy:

1. Read first 100 lines to extract frontmatter, bead ID, and initial signals.
2. For artifacts >100 lines, also `Grep` for `**Decision:`, `## Key Decisions`, and the tradeoff language patterns. Read 10-line context windows around matches.

This keeps token cost bounded (grep is cheap, targeted reads are small) while recovering the lost signals.

---

## MODERATE: Phase 6 merge logic underspecified for classification upgrades

**Severity: Moderate — data corruption risk on re-scan**

The plan says: "Merge new proposals with existing pending ones (update evidence if tradeoff_axis matches)." This covers the common case but does not address:

1. **Classification upgrade:** A pattern was `emerging` (2 decisions) on the first scan. A re-scan finds a third decision, making it `established`. The plan says "update evidence" but does not say to update the `classification` field or `unique_decisions` count. An executing agent might preserve the stale classification.

2. **Type transition:** A pattern was `emerging` (no PHILOSOPHY.md match) on scan 1. Between scans, the user manually added text to PHILOSOPHY.md that matches. On re-scan, the pattern should become `conforming` (log, don't propose) — but the merge logic says "preserve existing proposals with status != pending" and "update evidence if tradeoff_axis matches". The pending proposal should be *removed* (or status changed to `superseded`), but no status value or transition covers this.

3. **Evidence accumulation direction:** "Update evidence" does not specify whether new evidence *replaces* or *appends*. For proposals, append is correct (more evidence strengthens the case). But the schema's `unique_decisions` and `time_span` fields must also be recalculated, not just the evidence list.

**Fix:** Add explicit merge rules:

```
When tradeoff_axis matches an existing pending proposal:
- Append new evidence entries (deduplicate by path)
- Recalculate unique_decisions from the full evidence list
- Recalculate time_span from the full evidence list
- Reclassify based on new counts
- If reclassification changes type to conforming: set status to "superseded"
```

---

## MODERATE: Routing string-match has collision between scan and review

**Severity: Moderate — misrouting possible**

The routing rule is:
- Contains "scan" or "pattern" -> Scan mode
- Contains "review" -> Review mode
- Contains "status" -> Status mode

The review command sends: "Review pending proposals interactively. For each proposal, present evidence and ask to accept, reject, or defer."

This instruction does *not* contain "scan" or "pattern", so it routes correctly to Review mode. However:

1. **scan command instruction:** "Run a full scan for design patterns and philosophy drift." — contains both "scan" AND "pattern". Scan wins because it's checked first, which is correct. But if the check order were reversed or made parallel, "pattern" would also match.

2. **Future-proofing:** If a user types `/interlore:scan --review-after`, the instruction might contain both "scan" and "review". The plan specifies no priority rule for multi-match. The implicit first-match-wins from the bullet order works but is fragile.

3. **"status" in scan output:** The scan mode output includes "status: pending". If the skill's own output is somehow fed back as instruction (unlikely but not impossible in skill chaining), "status" would match.

**Fix:** Use prefix-anchored or exact-match routing rather than substring contains. E.g., check if the instruction *starts with* "Run a full scan" / "Review pending" / "Show interlore status". Or add a mode marker: "MODE=scan", "MODE=review", "MODE=status" as the first word of each instruction.

---

## MODERATE: Review Mode per-decision YAML writes — insufficient specification

**Severity: Moderate — incorrect output likely**

The Review Mode says:
- "Use AskUserQuestion with options: Accept, Reject, Defer."
- On Accept: "Read PHILOSOPHY.md, find the proposed_section, append proposed_text. Update proposal status to 'accepted', set decided_at. Write both files."
- On Reject: "Update proposal status to 'rejected', set rejection_reason and decided_at. Add tradeoff_axis to rejected_patterns."
- "Update `.interlore/proposals.yaml` after EACH decision"

**Issues:**

1. **YAML write method unspecified.** The skill tells the agent to "update" the YAML file but doesn't specify whether to use Read/Edit or Read/Write. For YAML modifications, the agent must read the entire file, modify the in-memory structure, and write the whole file back. If the agent tries to use Edit (string replacement) on YAML, field ordering, quoting, and multi-line values will cause failures. The skill should explicitly say: "Read the full proposals.yaml, modify the target proposal in memory, write the entire file back using the Write tool."

2. **`decided_at` format unspecified.** The schema shows `decided_at: null` but doesn't specify the datetime format. Should it be ISO 8601? Unix epoch? The `last_scan` field shows ISO 8601 with timezone (`2026-03-21T17:00:00Z`), but `decided_at` has no example.

3. **PHILOSOPHY.md append location underspecified.** "Find the proposed_section, append proposed_text" — what if `proposed_section` is "Composition Over Capability" and the section has 30 lines? Does "append" mean after the last line of that section (before the next `##`)? After the section header? The agent needs to know the insertion point precisely.

4. **rejected_patterns entry structure.** When adding to `rejected_patterns`, the schema shows `rejected_at` and `reason` fields. The skill says to "add tradeoff_axis to rejected_patterns" but doesn't say to also write `rejected_at` (current timestamp) and `reason` (from the AskUserQuestion response). An executing agent might write only the axis string.

**Fix:** Add explicit instructions for each write operation, including tool choice (Write, not Edit), datetime format (ISO 8601 UTC), insertion point ("before the next `---` or `##` heading after the matched section"), and rejected_patterns entry structure (all three fields).

---

## LOW: rejected_patterns suppression vs fuzzy clustering — axis string match will fail

**Severity: Low-Moderate — rejected patterns will resurface**

Phase 5 says: "Skip any tradeoff_axis that appears in `rejected_patterns`."
Phase 4 says: "Group extracted tradeoffs by tradeoff_axis (fuzzy match on axis description)."

The rejected_patterns list stores a `tradeoff_axis` string (e.g., "integration vs reimplementation"). On the next scan, Phase 4 generates tradeoff axes via fuzzy clustering from raw artifact text. The new axis string might be "integration over reimplementation" or "adopt vs build" or "compose external tools vs rebuild". Phase 5 then checks whether this new axis string "appears in" rejected_patterns.

This is an exact-string-match check against fuzzy-generated strings. The same underlying pattern will produce different axis descriptions across scans because:
1. Different artifacts use different phrasing for the same concept
2. The clustering agent will generate a representative label, which may differ from the previously rejected label
3. No normalization or canonicalization is specified

**Fix:** Either:
- (a) Normalize axis strings to a canonical form (lowercase, sort poles alphabetically, strip articles) before comparison, OR
- (b) Use the same fuzzy matching from Phase 4 for Phase 5 suppression (does the rejected axis fuzzy-match any new cluster?), OR
- (c) Store rejected patterns as keyword pairs (e.g., `[integration, reimplementation]`) rather than prose strings, and match on keyword overlap.

---

## LOW: --dry-run flag in review command but no skill-side handling

**Severity: Low — dead feature**

The review command (Task 4) says: "If `--dry-run` is in the arguments, add: 'Dry-run mode — show what would be proposed without writing.'"

This appends text to the instruction sent to the observe skill. However, the observe skill's Review Mode section has no mention of "dry-run", no conditional logic for "show what would be proposed without writing", and no branch that skips writes. The instruction text will be present in the skill invocation, but the skill has no handling for it.

An executing agent *might* interpret "show what would be proposed without writing" as a natural language instruction and skip the writes anyway (LLMs are good at this). But this is relying on emergent behavior rather than specified behavior. The skill should have an explicit dry-run branch.

**Fix:** Add a dry-run check at the top of Review Mode:

```
If the instruction contains "dry-run":
- Present all proposals as in normal review mode
- Skip AskUserQuestion (don't prompt for decisions)
- Skip all file writes
- Output: "Dry-run complete. N proposals would be presented for review."
```

Alternatively, dry-run might make more sense on scan (show what would be proposed without writing proposals.yaml), not review. Review is inherently interactive — a "dry-run review" that doesn't ask for input is just `/interlore:status` with more detail. Clarify the intended semantics.

---

## LOW: Tradeoff language patterns miss the dominant decision format in this corpus

**Severity: Low — reduced signal coverage, not incorrect signal**

The skill specifies these tradeoff language patterns:
- "chose X over Y", "preferred X to Y", "decided against Y"
- "default to X", "always X unless", "never Y"
- "X over Y because", "tradeoff: X vs Y"

Empirical grep across the actual brainstorm corpus found:
- Only **6 matches** for the specified tradeoff patterns across all 90+ brainstorms
- **27+ instances** of `**Decision:**` (the actual dominant format)
- **90+ brainstorms** have a `## Key Decisions` section with numbered or bulleted choices
- Decision language in practice uses patterns like "Decision: X", "We chose X because", or inline rationale without explicit "over Y" framing

The flux-drive outputs are slightly better: "chose" appears more often in analytical review text. But even there, the dominant pattern is "the system does X" or "X is preferred" rather than the explicit "X over Y" frame.

**Fix:** Expand the pattern list to include:
- `**Decision:**` or `**Decision**:` (explicit decision markers)
- `## Key Decisions` section content (structural marker)
- "We chose", "we went with", "we picked"
- Numbered decision lists under `## Key Decisions`

This would increase recall from ~6 matches to ~120+ matches across the corpus.

---

## INFORMATIONAL: Alignment/Conflict line coverage is even sparser than estimated

The plan estimates Alignment/Conflict lines exist in "<2% of existing artifacts." Actual count:
- **3 brainstorms** have `**Alignment:**` lines (interlore, intercom-h2-last-mile, intercom-outbox)
- **4 brainstorms** have `**Conflict/Risk:**` lines
- 0 plans, 0 PRDs, 0 flux-drive outputs have these lines

Out of ~90 brainstorms, that's 3.3%, and across all artifact types it's closer to 1%. The "<2%" estimate in the plan is approximately correct. The skill correctly treats these as enrichment-only, which is appropriate.

---

## Summary

| Finding | Severity | Category |
|---------|----------|----------|
| 100-line truncation misses 30-40% of decisions | High | Silent data loss |
| Merge logic on re-scan underspecified | Moderate | Data corruption |
| Routing substring collision potential | Moderate | Misrouting |
| Review YAML write method unspecified | Moderate | Incorrect output |
| rejected_patterns exact-match vs fuzzy-generated axes | Low-Moderate | Suppression bypass |
| --dry-run in command but not in skill | Low | Dead feature |
| Tradeoff language patterns miss dominant decision format | Low | Reduced recall |
| Alignment/Conflict coverage confirmed sparse | Info | Validated |

**Recommendation:** The 100-line truncation is the only finding that would make the scan produce materially wrong results. The rest are correctness-under-edge-cases issues that an implementer could work around. Fix the truncation before implementation; the others can be addressed during Task 3 implementation without plan revision.
