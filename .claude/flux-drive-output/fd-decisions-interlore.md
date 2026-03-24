---
artifact_type: flux-drive-review
domain: decision-quality
reviewer: fd-decisions-interlore
reviewed_documents:
  - docs/prds/2026-03-21-interlore.md
  - docs/brainstorms/2026-03-21-interlore-brainstorm.md
review_date: 2026-03-21
---

# Flux Drive: Decision Quality Review — interlore PRD

## Summary

interlore proposes a philosophy observer plugin to detect emerging patterns and drift in decision-making. The PRD is **well-aligned with Demarch's core principles** and the design decomposition is sound. However, there are **4 significant decision blindspots** that need exploration before committing to the "propose, never auto-apply" model and the 3+ artifact threshold for "established" patterns.

---

## Findings

### P2: "Propose, Never Auto-Apply" Is Anchoring on Status Quo Without Exploring Reversibility

**Location:** Brainstorm "interlore output model" + PRD Non-Goals section

**Issue:** The decision to always require human review for philosophy changes is framed as safety-first and philosophically grounded ("philosophy changes need human review"), but it doesn't examine the reversibility asymmetry.

**The trap:** Proposals that are *easy to undo* (e.g., "we consistently choose composition over monoliths in 5 recent PRDs") may benefit from auto-application with post-hoc auditing. Proposals that are *hard to undo* (e.g., "all new agent code must use model X") need review gates. The current model treats all philosophy updates as irreversible, creating friction where there shouldn't be any.

**Missing analysis:**
- What would happen if interlore auto-applied low-confidence EMERGING patterns (confidence <0.6) and deferred high-confidence ones (>0.8) to a review queue?
- How long does the current propose-review-apply cycle take, and what decisions get deferred indefinitely?
- Are there patterns that are so obvious in retrospect (e.g., "we never pick tool X anymore") that auto-applying them would save cognitive load?

**Consequence if wrong:** Friction will accumulate; humans will defer proposals; the feedback loop inverts and philosophy drifts more, not less. The tool becomes a suggestion box rather than a closed-loop system.

**Lens:** **Reversibility/Undo Cost** — Distinguish decisions by how easily they can be undone. **Explore vs Exploit** — Current model is pure exploit (preserve status quo). Is there a threshold where exploring auto-apply (on low-cost reversible changes) yields faster philosophy iteration?

---

### P2: The 3+ Artifact Threshold for "Established" Is Unjustified and Risks False Negatives

**Location:** PRD F3 acceptance criteria, Brainstorm "Open Questions" (pattern storage), evidence model description

**Issue:** Interlore classifies patterns as:
- **Established:** 3+ artifacts, 2+ weeks
- **Emerging:** 2+ artifacts
- **Nascent:** 1 artifact

The 3+ threshold appears arbitrary. The 2-week time span is never mentioned again. The PRD provides no evidence that 3 is the right threshold.

**Anchoring bias:** The number "3+" mirrors the interspect model ("require ≥3 evidence sessions per agent before scoring" in other PRDs), but interspect's threshold was calibrated for *agent routing signals* (where noise is high, stakes are medium). Philosophy patterns are different:

- **Interspect domain:** Agent performance in code. Highly noisy, frequent false positives from outlier sessions, reverting a routing override is free.
- **Interlore domain:** Architectural and process decisions. Lower-frequency events, signal is cleaner, reverting a philosophy update has social cost.

The evidence quality is fundamentally different, yet the threshold is identical.

**Missing analysis:**
- What is the false-negative rate if the threshold is 3? (E.g., "we chose integration in 2 recent PRDs" — could be early signal of a pattern shift.)
- What is the false-positive rate? (E.g., how often do 3 artifacts suggest a pattern that reverses in the 4th?)
- If the brainstorm draft MISSION statement is right — "compounding evidence is the path to earned trust" — shouldn't philosophy updates require *more* evidence, not equal to agent routing?

**Consequence if wrong:** Either:
1. Threshold too low → philosophy churn, proposals that reverse next month clutter the review queue.
2. Threshold too high → real emerging patterns get ignored until they're so obvious nobody learns anything.

**Lens:** **Cone of Uncertainty** — As decisions accumulate, confidence ranges should narrow. The 3-artifact rule is a point estimate; interlore should emit confidence ranges and let humans decide acceptance thresholds. **Theory of Change** — What causal chain connects "3 artifacts" to "this is a real pattern we should encode in philosophy"?

---

### P1: "Extending interspect" vs "Building interlore" — The Boundaries Are Never Examined

**Location:** PRD "Solution" narrative, dependencies section

**Issue:** The PRD presents interlore as a standalone plugin because it "detects patterns, proposes philosophy updates" — different domain from interspect's "agent performance profiling." But the actual architectures are nearly identical:

- Both scan artifacts and classify them
- Both write proposals to staging files
- Both require human review/approval
- Both integrate with interwatch
- Both follow the "evidence → classification → proposal → action" pipeline

The decision to build a new plugin is treated as obvious ("three connected pieces"), but there's no analysis of the coupling cost vs. the architectural simplicity gain.

**Hidden assumptions:**
- interlore's artifact scanning is sufficiently different that sharing code with interspect would be brittle
- The interspect SQL schema can't extend to philosophy patterns
- Operating two similar systems is cheaper than unifying them

None of these are stated or tested.

**Missing analysis:**
- Could interspect's "signal source" system (which already emits "ready/growing/emerging" classifications) be extended to cover "philosophy patterns"?
- If interspect owned philosophy pattern detection, what would break? What would improve?
- The `interspect-evidence.md` command already reads SQLite and emits classification reports — could the same structure serve both agent evidence and philosophy evidence?

**Consequences if wrong:**
- Maintenance burden doubles (two systems to keep in sync as patterns emerge)
- Operators need to learn two separate evidence models
- Future signals (e.g., "interlore patterns pending" in interwatch) create cross-plugin coupling anyway

**Lens:** **Composition Architecture** — PHILOSOPHY.md teaches "Authority is scoped and composed. Many small controllers with explicit scope. Composition over capability." The decision to build interlore as standalone is *against* this principle, not for it. **Dissolving the Problem** — Could the "philosophy evolution" problem be solved by extending an existing system (interspect) rather than building a new one?

**Note:** This is not necessarily a blocker. If the decision is to build interlore, state the assumption explicitly: "interspect's agent evidence model is sufficiently orthogonal to philosophy patterns that coupling them would create more maintenance debt than benefit." But don't treat the decision as obvious.

---

### P2: The "3+ Independent Decisions" Test Is Circular — How Do You Detect Independence?

**Location:** Brainstorm, evidence model; PRD F3 acceptance criteria

**Issue:** The evidence model says patterns must appear in "3+ artifacts" to be ESTABLISHED. But the scan engine is built on syntactic pattern matching (Alignment/Conflict lines, keywords, section headers). There is no semantic understanding of *whether decisions are independent*.

**Example:**
- Brainstorm A: "We should use composition over monoliths"
- PRD B: References Brainstorm A and agrees
- PRD C: References Brainstorm A and agrees

This counts as 3 artifacts. But they're not 3 independent decisions — they're 1 decision with 2 echoes.

**Missing definition:** What makes two decisions "independent" in interlore's evidence model?

The brainstorm mentions "3+ independent decisions" but the F3 acceptance criteria says "3+ artifacts, 2+ weeks" — no mention of independence. The scan engine doesn't validate it.

**Consequence if wrong:** Interlore will misclassify decisions that have been cited repeatedly (high visibility, not high evidence of pattern) as established patterns. Users will learn to ignore the EMERGING classification, treating it as noise.

**Lens:** **Survivorship Bias** — Decisions that are cited and agreed upon survive in memory and documentation; dissenting views disappear. The 3+ threshold may be measuring "how well-remembered is this decision" rather than "is this a real pattern." **N-Ply Thinking** — Before shipping the evidence model, trace through scenarios: what happens when a decision propagates through PRDs? Is that evidence or echo?

---

### P3: Cross-Project interlore Is Deferred Without Boundary Definition

**Location:** PRD Open Questions #3, Brainstorm section on cross-project scope

**Issue:** The PRD scopes interlore to project root only in v1, deferring cross-project detection. But PHILOSOPHY.md exists at both root and subproject level (e.g., `os/Clavain/PHILOSOPHY.md`). The decision to defer this is reasonable, but the *boundary* is undefined.

**Missing analysis:**
- If interlore operates on project root only, does it still scan `.claude/flux-drive-output/fd-*.md`? These files are at project root but may discuss subproject-level decisions.
- When a subproject has its own PHILOSOPHY.md, should interlore warn about divergence with the root philosophy?
- Is there a version of this tool that runs per-subproject and feeds up to the monorepo root?

**Current state:** The tool will work fine for v1 (root level only), but the lack of explicit boundary definition will make the v2 scope-expansion painful. This is a soft issue — not a blocker, but creates downstream friction.

**Lens:** **Scope Containment** — Define what "project-scoped" means precisely. "All artifacts under project root dir" vs "only the top-level PHILOSOPHY.md" have different implications.

---

## What Is Strong in This PRD

**Good decisions that are well-reasoned:**

1. **Unix decomposition is right.** interlore observes and proposes; interdoc reviews and generates; interwatch monitors drift. Excellent separation of concerns (if the boundaries hold).

2. **Staging file model is sound.** `.clavain/interlore/proposals.md` is readable, git-trackable, and can be reviewed like a PR. Better than SQLite for philosophy decisions that should be auditable.

3. **MISSION.md hierarchy is grounded.** The doc hierarchy (MISSION → {VISION, PHILOSOPHY}) with all artifacts deriving from it addresses a real gap (no root document), and the hierarchy is justified by the philosophy itself (evidence-based, principled decomposition).

4. **Parallel with interspect is useful.** Using a similar evidence model (artifact count → classification) creates consistency across the ecosystem. The analogy is explicitly stated and justified.

5. **Feature set is minimal and focused.** F1-F5 ship the essentials (detect patterns, review proposals, wire integration) without scope creep. Non-goals are explicitly stated.

---

## Recommendations

### Before Committing to "Propose, Never Auto-Apply"

**Explore:** Define a decision matrix for when philosophy updates can auto-apply vs. require review. Example:

```
| Confidence | Reversibility | Action |
|-----------|---------------|--------|
| >0.9      | High          | Auto-apply, audit trail |
| >0.8      | Medium        | Review queue (fast track) |
| 0.5-0.8   | Any           | Review queue (standard) |
| <0.5      | Low           | Reject, rerun with more data |
```

This keeps the "propose, human decides" philosophy while recognizing that not all proposals have equal stakes.

### Before Shipping the 3+ Threshold

**Validate:**
1. Run interlore in "dry run" mode on the last 3 months of artifacts. Count false positives (patterns that disappeared) and false negatives (real patterns caught with <3 artifacts).
2. Define "independent decision" operationally: "appears in different beads," "makes different tradeoff choice," "not cited by subsequent decision."
3. Consider tiered thresholds: ESTABLISHED (3+ independent, 2+ weeks), EMERGING (2+ independent OR 1 independent + 2+ citations from different beads), NASCENT (1 standalone decision).

### On interspect vs interlore

**Decision to make explicit:** Document the decision to build interlore as a separate plugin, including:
- Why interspect's evidence model doesn't extend to philosophy patterns
- Why maintaining two similar systems is justified
- How they will remain decoupled (or when coupling is acceptable)

If the answer is "interspect is agent-specific and philosophy is project-wide," state that. Don't leave it implicit.

### On Cross-Project Scope

**Define boundaries now:**
- Does interlore scan subproject PHILOSOPHY.md files? (Probably yes in v2.)
- When a subproject PHILOSOPHY.md diverges from root PHILOSOPHY.md, is that flagged? (Probably yes, with "inherited" vs "local" classification.)
- Document the planned v2 scope in the PRD Open Questions section as a follow-up epic, not a soft TODO.

---

## Risk Assessment

| Risk | Probability | Severity | Mitigation |
|------|------------|----------|-----------|
| Philosophy churn from auto-application | Medium | Medium | Explore reversibility-based approval thresholds before shipping |
| False positives from 3+ threshold | Medium | Low | Dry-run validation on 3mo of artifacts; refine threshold if >20% false positive rate |
| Maintenance burden (two similar systems) | Low | Medium | Document interspect-vs-interlore decision explicitly |
| Deferring cross-project scope causes v2 rework | Low | Low | Define boundary now, ship MVP per-project only |

---

## Decision Quality Score

**Overall:** **7/10** — Sound architecture grounded in philosophy, but premature commitment to specific thresholds and "never auto-apply" without exploring reversibility.

**Recommend:** Proceed to design review with P2 findings incorporated. The three P2 issues (reversibility, threshold justification, semantic independence detection) are solvable and should be addressed in the design phase, not deferred to v2.
