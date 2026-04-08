---
agent: fd-retrospective-facilitation
track: adjacent
status: NEEDS_ATTENTION
finding_count: 5
---

## Findings

### [P1] No specificity test in the classification step

**Issue:** Option A (line 70-78) describes extracting 1-5 learnings and classifying each by target. There is no quality gate on the learning itself before routing. The brainstorm identifies this as a known failure mode — "learnings are too generic" (line 55) — but the proposed solution (routing to durable targets) addresses placement, not content quality. A vague learning routed to CLAUDE.md is still vague.

**Failure scenario:** A sprint produces the learning "we should plan better for large refactors." The router classifies it as `claude-md` and appends: "Plan more carefully for large refactors." This entry fails the specificity test — it has no when (trigger condition), no where (which workflow step), and no what (specific check to perform). An agent reading this in a future session cannot translate it into action. The entry occupies space in CLAUDE.md and provides zero behavioral change. After 20 such entries, the "Learned Rules" section is noise.

**Fix:** Add a specificity gate before the routing step. Each learning must pass the when/where/what test: "When [trigger condition], do [specific action] in [specific location] because [consequence of not doing it]." Learnings that fail the test are sent back for refinement, not routed. This is a prompt change to the reflect command, not a code change.

### [P1] No per-session or per-target capacity limit

**Issue:** Option A step 1 says "Extract 1-5 learnings from the sprint" (line 71), suggesting a soft cap of 5. But this is descriptive, not prescriptive — the brainstorm does not enforce a cap. A particularly eventful sprint could produce 8-12 learnings, all routed to different targets. This matches the P1 calibration scenario: "Compound routes 12 learnings from a single session to 4 different targets, overwhelming all of them."

**Failure scenario:** A sprint that involved debugging a complex multi-system issue produces 9 learnings: 3 for CLAUDE.md, 2 for code comments, 2 for hooks, 1 for AGENTS.md, 1 for memory. The CLAUDE.md entries dilute existing content. The hooks are hastily specified without considering trigger frequency. The code comments are added to files that were only tangentially involved. None of the 9 receive enough attention to be well-crafted. Retro research consistently shows that >5 action items per session results in none being completed well.

**Fix:** Enforce a hard cap of 3 routed learnings per session. If the extraction step produces more than 3, require prioritization: rank by severity of the failure that would recur, keep top 3, archive the rest in the lightweight log. This forces the agent to think about which learnings matter most rather than capturing everything.

### [P2] Root cause vs. symptom distinction is absent from classification

**Issue:** The classification taxonomy (line 72) routes by target type, not by learning quality. There is no step that distinguishes root-cause learnings ("add a pre-commit hook to validate X") from symptom descriptions ("X broke during deploy"). The evidence table (lines 37-44) shows both types: "Close child beads when parent ships" is root-cause (actionable), while "Review detection is the weak point" is a symptom observation (not actionable without further analysis).

**Failure scenario:** The router accepts "the build failed because of a typo" and routes it to CLAUDE.md as "be careful with typos in build files." This is a symptom-level observation, not a root cause. The root cause might be "add YAML linting to the pre-commit hook." The CLAUDE.md entry is unactionable and persists indefinitely.

**Fix:** Add a root-cause filter to the extraction step. After extracting learnings, each must answer: "What systemic change prevents this class of failure?" If the answer is "be more careful," the learning is a symptom and must be refined to identify the structural fix before routing. This is a prompt change, not a code change.

### [P2] Compound's timing advantage is not exploited in the design

**Issue:** The brainstorm notes that compound captures learnings "while context is fresh" (implicit in the immediate-after-sprint timing). This is the core advantage over traditional retros where details are forgotten. But the proposed router (Option A) reduces learnings to abstract classifications before writing. The rich session context — specific error messages, file paths, command sequences — is discarded during classification.

**Failure scenario:** A learning about a subtle beads migration issue is captured as "check Dolt server status before migration" in CLAUDE.md. The original session had the specific error message, the exact command sequence that triggered it, and the recovery steps. None of this survives routing. When the issue recurs, the CLAUDE.md one-liner is insufficient to diagnose or fix it — the agent must rediscover the solution from scratch.

**Fix:** The router should preserve context-rich encoding in the target write. For CLAUDE.md entries, use the existing convention: `# [date] lesson-title` followed by a 1-2 line explanation with specific triggers and consequences. For code comments, include the failure scenario inline. The router prompt should explicitly instruct: "Include the specific error, command, or condition — not just the abstract rule."

### [P3] No follow-through verification after routing

**Issue:** None of the five options describe a verification step that confirms routed learnings are actually present and correctly formatted in their targets after writing. The durable change gate (Option B) checks that a file was modified, but not that the modification is correct or well-placed.

**Failure scenario:** The router appends a learning to CLAUDE.md, but a formatting error (missing newline, broken markdown) causes it to merge with the previous entry and become unreadable. Or the router writes a code comment to the wrong function. The gate passes (file was modified) but the learning is not retrievable.

**Fix:** Add a post-write verification step: after routing each learning, read back the target file and confirm the entry is present, correctly formatted, and in the right location. This is lightweight (one read per write) and catches formatting and placement errors.
