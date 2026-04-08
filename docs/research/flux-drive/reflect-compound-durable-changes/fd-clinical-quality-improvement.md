---
agent: fd-clinical-quality-improvement
track: orthogonal
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No explicit no-change decision path — learnings are either routed or silently dropped

**Issue:** The brainstorm's Option E escape hatch states "'no actionable learnings' is valid if explicitly stated (not just an empty reflect)." But the design does not specify what "explicitly stated" means structurally — there is no documented disposition record for no-change decisions. In CQI methodology, "no change needed" is a valid M&M outcome but it requires written justification filed with the case record. Without this, the distinction between "we reflected and decided no change was needed" and "we skipped the reflect step" is invisible in the audit trail.

**Failure scenario:** Sprint ends cleanly. The reflect step produces no output because the agent determines there are no learnings. The escape hatch fires. Six sprints later, the same problem occurs. When investigating, there is no record of whether each of those six sprints explicitly decided "no change" or whether the reflect step was silently skipped due to time pressure. The "no-learning sprint" disposition is indistinguishable from the "skipped reflect" failure mode.

**Fix:** The reflect step's escape hatch must write a disposition record to the lightweight audit log regardless of outcome. Format: `{date, sprint_id, outcome: "no_actionable_learnings", justification: "<one sentence>"}`. The ship gate (Option B's durable change gate) should check for the presence of either a routing record or a no-change disposition record — not just for "any file modification."

---

### [P1] Symptom vs root-cause classification is absent — learnings default to advisory targets

**Issue:** The brainstorm's routing taxonomy (`claude-md | agents-md | memory | code | hook | philosophy`) does not include a dimension for root-cause depth. The evidence table shows that "Close child beads when parent ships" is routed to CLAUDE.md — but the root cause is likely that the bead-close workflow (lib-sprint.sh or Clavain's sprint phase) does not check for open children. CLAUDE.md addresses the symptom (tell the agent to remember). A hook or code change addresses the root cause (enforce the check). Without a root-cause classification dimension, learnings default toward the softest target.

**Failure scenario:** The reflect step classifies "check build before committing" as `claude-md`. This is a symptom-level classification: the agent forgot to check the build, so we tell the agent to remember. The root cause is that no pre-commit hook enforces the check. CLAUDE.md is appended. The next agent forgets under workload (as every agent does). The learning has been routed at the wrong level — an M&M finding addressed by "remind the nurse" instead of "fix the checklist."

**Fix:** Add a root-cause question to the reflect classification prompt before routing: "Is this learning a behavioral reminder (symptom-level: route to claude-md or memory) or a systemic gap (root-cause: route to hook or code)?" The prompt should provide examples matching the project's existing patterns — e.g., "close child beads" is root-cause level, route to hook; "check docs before implementing" is behavioral, route to claude-md. This maps directly to the CQI distinction between individual competence interventions (advisory) and system redesign interventions (structural).

---

### [P2] No outcome measurement loop — no mechanism to verify routed learnings prevent recurrence

**Issue:** The brainstorm's desired flow is "learning → code/config/CLAUDE.md change → future sessions behave differently." But there is no mechanism in any of the five options to close the loop: measure whether a routed learning actually reduced the target event rate in subsequent sessions. This is the CQI outcome measurement gap. The brainstorm notes the same mistakes repeat ("~80% of learnings are 1-2 sentence items") but does not propose any instrument to detect whether the new routing approach changes this rate.

**Failure scenario:** Option E is implemented. Over 3 months, 45 learnings are routed to CLAUDE.md, hooks, and code. At month 3, a review finds that 12 of the original 18 dead-reflection learnings have been re-surfaced in subsequent reflects. The routing is happening, but the recurrence rate is unchanged. Without an outcome measurement loop, this is invisible until someone manually audits the reflect history. The system has no self-correcting signal.

**Fix:** Add a recurrence check to the reflect step: before extracting new learnings, search the last 10 sprint reflect records for overlapping topics. If a topic matches a previously routed learning, flag it as a potential recurrence event — not necessarily an escalation (that's the aviation lens), but a measurement point. Monthly, `recent-reflect-learnings` (or its replacement) should report recurrence rate: "3 of 8 learnings this month matched previously routed topics." This data exists in the audit log if disposition records are structured (see P1 finding above).

---

### [P2] Event classification captures only topic, not severity or preventability

**Issue:** The brainstorm's routing taxonomy classifies learnings by target type (`claude-md`, `hook`, `code`, etc.) but not by severity or preventability. In CQI, adverse events are classified on multiple dimensions: severity (how bad was the outcome), preventability (was this avoidable given current systems), and contributing factors (what conditions enabled it). Without these dimensions, all learnings are treated as equivalent — a minor process inefficiency gets the same routing weight as a repeated production failure. This flattens the priority signal.

**Failure scenario:** Two learnings emerge from a sprint: (1) "regex splits compound words at hyphens in generate-agents.py" (minor bug, easily fixed with a code comment) and (2) "DISPATCH_CAP=1 mutates global state for rest of session" (session-corrupting bug that caused 3 failures). Both get classified as `code` and routed as equivalent. The DISPATCH_CAP issue gets a code comment; the regex issue gets a code comment. Neither gets a bead to track the actual fix. The severity dimension that would distinguish "add a comment" from "fix and add a regression test" is absent.

**Fix:** Add a severity dimension to the reflect classification prompt alongside the routing target: `severity: low | medium | high`. High-severity learnings (`high`) should require a bead in addition to the durable change — the bead tracks whether the underlying issue was actually fixed, not just documented. This matches the CQI practice of escalating high-severity adverse events to a formal improvement project rather than routing them through the standard documentation flow.

---

### [P3] Action item decay is untracked — routed learnings have no lifecycle after the write

**Issue:** The brainstorm's Option E describes routing as a terminal operation: classify → write to target → log to audit trail. There is no mechanism to track whether routed items that require follow-up (e.g., a code change that wasn't made in the same session, a hook that needs to be authored and tested) actually complete. CQI tracks action item completion rates and flags programs where items age without closure.

**Failure scenario:** The reflect step routes "DISPATCH_CAP=1 mutates global state" to `code` with the intent that a code comment and assertion will be added to lib-dispatch.sh. The session ends before the code change is made. The routing is logged as complete (the classification and routing decision happened). The actual code change never occurs. Next session, the agent has no visibility into the outstanding code-change action item from the previous reflect.

**Fix:** Learnings routed to `code` or `hook` that were not executed in the same session should be written to the lightweight audit log with status `pending_implementation` and cross-linked to a bead. The reflect step should check for pending-implementation items at session start (or sprint start) and surface them before extracting new learnings. This keeps the action item lifecycle visible without requiring a separate tracking system.
