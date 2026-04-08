---
agent: fd-construction-commissioning
track: orthogonal
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P0] Paper closure without physical inspection — write confirmation does not verify content

**Issue:** The brainstorm's Option B "Durable Change Gate" checks that "at least 1 file outside docs/reflections/ was modified by the reflect step." This confirms that a write operation was attempted, not that the target file contains the intended content. It is the commissioning equivalent of signing off a punch list based on the contractor's work order, not physical inspection of the installed item. A write that succeeds at the OS level but produces malformed or truncated content, appends to the wrong section, or overwrites an adjacent rule passes the gate.

**Failure scenario:** The reflect step appends a new rule to CLAUDE.md using an Edit tool call with an incorrect `old_string` match that lands the new content in the wrong section — inside a code block, after a section header it was supposed to precede, or duplicating an existing entry. The write API call returns success. The gate checks for "any modification outside docs/reflections/" — the modification happened, the gate passes. The rule is now in CLAUDE.md in a location where it is either invisible to the agent (inside a fenced code block) or contradicts a nearby rule. The learning is marked closed.

**Fix:** After each CLAUDE.md write, the reflect step should read back the specific line(s) it appended and verify: (1) the content appears verbatim, (2) it appears exactly once, (3) it is not inside a fenced code block. For hook writes to settings.json, verify the hook appears in the JSON structure with correct keys. This is the inspector's physical sign-off. Log the verification result alongside the routing record. Verification failure should reopen the item and trigger a re-attempt.

---

### [P1] Learnings are batched without individual tracking — a failed write loses all items

**Issue:** The brainstorm does not specify whether learnings extracted per sprint are processed individually (one routing operation per learning) or batched (all learnings in a single CLAUDE.md append). Option A describes "write each to its target" which implies individual operations, but the implementation detail is absent. If the reflect step extracts 4 learnings and batches them into a single append block, a write failure loses all 4 items simultaneously with no record of which were attempted. Commissioning requires each deficiency item to have its own traceable identity through the lifecycle.

**Failure scenario:** The reflect step extracts learnings L1, L2, L3, L4 from a sprint and appends them as a single block to CLAUDE.md. The Edit tool call fails on the second attempt (CLAUDE.md was concurrently modified by the user). The gate check finds no modification outside docs/reflections/. All four learnings are lost. The audit trail shows "reflect attempted" but not which individual items were in flight. There is no recovery path because item identity was never established.

**Fix:** Before routing, assign each extracted learning a stable identity (a UUID or sprint-scoped index: `sprint-abc-L1`, `sprint-abc-L2`). Process and verify each learning individually as a separate write operation. Log each item's status (`classified → routed → written → verified`) separately. If write fails for L3, L1/L2/L4 retain their verified status and only L3 is flagged for retry. This is the commissioning punch list principle: each deficiency item has its own status, not the batch.

---

### [P1] No session-end sign-off — no verification that all classified learnings are dispositioned

**Issue:** The brainstorm's Option E escape hatch ("no actionable learnings" is valid if explicitly stated) addresses the case where no learnings exist. But there is no explicit sign-off procedure at session or sprint end that verifies every extracted learning is in a final state (routed+verified, explicitly deferred, or explicitly skipped with justification). Commissioning requires a handover sign-off that all punch list items are dispositioned before the project changes hands. The reflect step in Option E can end without this verification.

**Failure scenario:** The reflect step extracts 3 learnings. Routes L1 and L2 successfully. L3 is classified as `code` but the sprint ends before the code change is made. There is no deferred-learning mechanism (the brainstorm notes this as an open question under Option E). L3 is neither routed nor explicitly deferred — it simply falls out of the session. The sprint handoff proceeds. L3 is lost without record.

**Fix:** The reflect step's final action should be a disposition check: for each learning extracted, assert one of: `(a) routed+verified`, `(b) deferred to next sprint with reason logged`, `(c) explicitly skipped with justification`. The ship gate (Option B) should verify this disposition check ran and passed, not just that "a file was modified." The deferred-learning mechanism (currently absent from all options) should write deferred items to the sprint's bead state so they surface at next sprint start.

---

### [P2] No severity-based priority affecting routing verification requirements

**Issue:** The brainstorm's routing taxonomy treats all learnings as equivalent in terms of verification rigor. A one-liner CLAUDE.md append for a minor gotcha goes through the same (currently unspecified) verification as a hook that prevents session-corrupting behavior. Commissioning distinguishes life-safety items (require inspection before occupancy) from cosmetic items (can be verified during warranty period). The brainstorm has no equivalent — a learning about a session-corrupting dispatch bug and a learning about a regex edge case get the same routing treatment.

**Failure scenario:** The learning "DISPATCH_CAP=1 mutates global state for rest of session" is classified as `code` and a code comment is added to lib-dispatch.sh. Verification: the comment appears in the file. Closed. But the underlying bug — the global mutation — was not fixed, only documented. A high-severity learning about session corruption warranted a code fix and a regression test, not just a comment. The routing target was appropriate but the verification requirement should have been higher: for severity=high, verification must confirm the behavioral change, not just the documentation change.

**Fix:** Add a severity dimension (low/medium/high) to the routing classification. For `severity: high` learnings routed to `code`, the verification requirement should be: the code change was actually made (not just a comment), and a test or hook confirms the behavior. For `severity: high` learnings routed to `hook`, verification should include running the hook in a test scenario. The reflect prompt should document severity → verification requirement mapping.

---

### [P2] No deferred-learning mechanism — items that can't be routed immediately are silently lost

**Issue:** The brainstorm explicitly leaves open: "What about compound's auto-trigger from hooks — does it still write to solutions/ in that mode?" This hints at a category of learnings that arise outside the sprint lifecycle and may not have an obvious immediate routing target. More concretely: learnings routed to `code` frequently require code changes that aren't made in the same session (the change is in a different subproject, requires a bead, or needs design discussion first). There is no deferred-learning mechanism in any of the five options.

**Failure scenario:** The reflect step routes a learning to `code` in os/Clavain/lib-dispatch.sh. The session is focused on apps/Autarch/ and the Clavain change is out of scope. The reflect step appends to CLAUDE.md instead as a fallback ("workaround: route to claude-md if code change not feasible"). Next sprint, the CLAUDE.md entry is loaded but the actual lib-dispatch.sh fix is never made. The pattern repeats: document the workaround instead of fixing the system, because the fix requires a context switch.

**Fix:** Introduce a `deferred` routing status. When a learning is classified as `code` or `hook` but the implementation can't happen in the current session, the reflect step creates a bead (`bd create`) with the learning content, target file, and classification, and records the bead ID in the audit log alongside status `deferred`. The sprint-start step (`recent-reflect-learnings` or its replacement) should surface deferred items before new work begins. This is the commissioning warranty item: tracked, assigned, not lost.
