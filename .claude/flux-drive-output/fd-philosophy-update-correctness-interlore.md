---
artifact_type: flux-drive-review
domain: philosophy-update-correctness
reviewer: fd-philosophy-update-correctness
reviewed_documents:
  - docs/prds/2026-03-21-interlore.md
  - docs/brainstorms/2026-03-21-interlore-brainstorm.md
  - PHILOSOPHY.md
review_date: 2026-03-21
---

# Flux Drive: Philosophy Update Correctness Review -- interlore PRD

## Reviewer Stance

This review is written from a position of skepticism toward automated insight generation. The central question is: can interlore distinguish signal from noise when operating on natural-language design artifacts, and does the PRD build in the epistemic safeguards needed when a tool proposes changes to a project's foundational beliefs?

---

## Findings

### P0: The Primary Signal Source (Alignment/Conflict Lines) Barely Exists in the Corpus

**Location:** PRD F3 acceptance criteria, brainstorm "What interlore scans"

**Issue:** The PRD says interlore "extracts decision patterns from Alignment/Conflict lines and recurring tradeoff resolutions." The brainstorm says the tool scans brainstorms and PRDs for these lines. The interdoc AGENTS.md (line 83-85) instructs authors to add `**Alignment:**` and `**Conflict/Risk:**` lines to brainstorm/planning outputs.

**The reality:** Across the actual artifact corpus:
- 167 brainstorm files: **3** contain `**Alignment:**` lines. **0** contain `**Conflict:**` lines.
- 116 PRD files: **0** contain either.
- 67 flux-drive outputs: **1** contains an `**Alignment:**` line.

The interdoc protocol is almost entirely unenforced. interlore's primary structured signal source does not exist in practice. The PRD designs a pattern detection engine around a metadata format that covers <2% of the corpus.

**Consequence:** If shipped as designed, interlore's scan will find almost nothing through its intended primary mechanism and will fall back entirely to "recurring keywords, section headers" -- the Non-Goals section's explicit fallback, not the main approach. This means pattern detection quality is undefined: the PRD specifies no algorithm for keyword/header-based extraction, no precision/recall targets, and no false-positive tolerance for the fallback path.

**Recommendation:** Either (a) make interlore's first job to enforce/backfill Alignment/Conflict annotations (turning interdoc's protocol from aspirational to mandatory), or (b) redesign F3 around the signals that actually exist in the corpus -- section structure, decision language patterns, PHILOSOPHY.md references (found in 20 of 167 brainstorms). The PRD must specify what "extract decision patterns" means concretely when operating on unstructured prose.

---

### P0: "Latent Design Pattern" Is Not Defined Precisely Enough for Consistent Detection

**Location:** PRD F3, brainstorm "interlore scope: discover + drift"

**Issue:** The core concept -- "latent design pattern" -- lacks an operational definition. The PRD says interlore detects "recurring patterns" and "design patterns not yet captured in PHILOSOPHY.md." The brainstorm calls them "recurring decision tradeoffs." Neither document defines:

1. **What constitutes a "pattern" vs. a "decision"?** If three PRDs each choose Go over Python, is "prefer Go" a design pattern or three implementation decisions?
2. **At what abstraction level do patterns live?** PHILOSOPHY.md operates at the level of "composition over capability" and "evidence earns authority." Individual PRDs operate at "use SQLite vs flat files." How does interlore bridge these levels?
3. **What makes two occurrences of similar language a "pattern" vs. coincidence?** If three brainstorms mention "fail-open," is that a pattern or a recurring technical term?

The Non-Goals section says "v1 uses structural patterns: Alignment/Conflict lines, recurring keywords, section headers." But "recurring keywords" is not a pattern detection algorithm -- it is a vague gesture toward one. Without a definition of what keywords count, what recurrence threshold applies per-keyword, and how keywords map to philosophy-level concepts, the scan engine's output is non-deterministic across implementations.

**Consequence:** Two different implementations of F3 (or two different LLM sessions running the same scan) could produce completely different proposal sets from the same corpus. This makes the tool's output unreproducible and uncalibratable.

**Recommendation:** Define "latent design pattern" operationally as a structured tuple: (tradeoff axis, chosen pole, artifact evidence, counter-evidence). For example: (storage format, flat files over databases, [PRD-A, PRD-B, brainstorm-C], [brainstorm-D chose SQLite]). This forces precision and makes the diff against PHILOSOPHY.md tractable: either the tradeoff axis already appears in PHILOSOPHY.md or it does not.

---

### P1: No Mechanism to Distinguish "Recapitulates Existing Principle" from "Reveals New Principle"

**Location:** PRD F3 ("Diffs against current PHILOSOPHY.md sections to detect both EMERGING and DRIFT")

**Issue:** PHILOSOPHY.md already contains "composition over capability." If interlore scans 5 PRDs that choose composition over monoliths, it will detect this as a pattern. But this is not an EMERGING pattern -- it is artifacts conforming to an existing principle. The PRD says the scan "diffs against current PHILOSOPHY.md sections," but:

- The diff algorithm is not specified. Is it keyword overlap? Semantic similarity? Section-header matching?
- PHILOSOPHY.md principles are stated abstractly ("many small controllers with explicit scope"). Artifacts instantiate them concretely ("use separate plugins instead of a monolith service"). The abstraction gap means naive keyword matching will miss the connection.
- If the diff is LLM-based (which is the only way to bridge abstraction levels), the diff itself is stochastic and the PRD provides no guidance on how to handle cases where the LLM is uncertain whether a pattern is novel or existing.

**Consequence:** Without this distinction, the proposal queue will be dominated by re-discoveries of existing philosophy -- "we keep choosing composition" surfaces as a proposal even though composition is already a core principle. This noise will cause reviewers to skim or ignore proposals, defeating the feedback loop.

**Recommendation:** Before scanning for new patterns, run an explicit "coverage check" that maps each existing PHILOSOPHY.md principle to its instantiations in the artifact corpus. Only patterns that fall outside existing principle coverage should become EMERGING proposals. This inverts the approach: instead of "find patterns, then diff," do "map existing principles, then find gaps."

---

### P1: No Closed-Loop Calibration for Accept/Reject Decisions

**Location:** PRD F4 acceptance criteria

**Issue:** PHILOSOPHY.md's own "Closed-loop by default" principle (the most detailed section, lines 58-78) requires four stages for any system that makes judgments: hardcoded defaults, collect actuals, calibrate from history, defaults become fallback. The PRD addresses only stages 1-2:

- **Stage 1 (defaults):** The 3-artifact threshold, established/emerging/nascent classification.
- **Stage 2 (collect actuals):** F4 records accept/reject with dates and reasons.
- **Stage 3 (calibrate from history):** Not addressed. There is no mechanism to ask: "Of the patterns interlore classified as ESTABLISHED, how many were accepted? How many were rejected? Should the threshold change?"
- **Stage 4 (defaults become fallback):** Not addressed. If calibration data exists, the system should use it; the 3-artifact threshold should be a fallback, not permanent.

The PRD says "excluded from future scans" for rejected proposals, but this is a blacklist, not calibration. It prevents the same proposal from recurring but does not adjust the system's pattern detection based on what kinds of proposals humans find valuable.

This is ironic: interlore is explicitly designed to close the philosophy feedback loop, but its own internal feedback loop is open.

**Recommendation:** Add to F4 or as a new F6: after N review cycles (e.g., 10 proposals reviewed), interlore computes acceptance rate by classification tier, proposes threshold adjustments, and records the calibration as a durable artifact. This is the same pattern as interspect's canary monitoring applied to interlore itself.

---

### P1: The "Independence" Problem Makes the 3-Artifact Threshold Unreliable

**Location:** PRD F3 acceptance criteria ("3+ artifacts, 2+ weeks"), also flagged in fd-decisions-interlore.md

**Issue:** The 3-artifact threshold counts artifacts, not independent decisions. The fd-decisions review already identified the echo problem (brainstorm A spawns PRD B and PRD C, counting as 3 artifacts for 1 decision). But the problem goes deeper:

The artifact corpus has natural citation chains. A brainstorm becomes a PRD, which spawns a plan, which produces a flux-drive review. These are 4 artifacts from 1 decision. The bead system links them (same bead ID), but the PRD's F3 acceptance criteria make no mention of bead-aware deduplication.

Even the "2+ weeks" time span guard does not help: the brainstorm-to-PRD-to-plan pipeline for a single bead often spans 2+ weeks.

**The 3+ threshold is simultaneously:**
- **Too low** for citation-chain artifacts (1 decision easily produces 3+ linked artifacts)
- **Too high** for genuinely independent but infrequent decisions (a project might make a significant architectural bet only twice across 2 months)

**Recommendation:** Replace artifact count with a bead-aware decision count. Artifacts sharing a bead ID count as one decision. This is cheap to implement (bead IDs are in artifact frontmatter), directly addresses the independence problem, and is consistent with Sylveste's own work-tracking architecture.

---

### P2: Conflicting Patterns Across Sources Are Not Addressed

**Location:** PRD F3 (absent from acceptance criteria and open questions)

**Issue:** The PRD does not address what happens when the artifact corpus contains conflicting signals. Real examples from the Sylveste corpus:

- Some artifacts favor flat files for simplicity; others favor SQLite for queryability. Both positions recur.
- The philosophy says "composition over capability," but the dual-mode plugin brainstorm acknowledges that the three-layer model creates "testing complexity" and "upgrade friction" -- implicit costs of composition.

When interlore detects both "prefer flat files" (3 artifacts) and "prefer SQLite" (3 artifacts), what happens? Both become ESTABLISHED proposals? One cancels the other? The PRD is silent.

**Consequence:** Conflicting proposals will surface as independent findings with no indication that they contradict each other. The reviewer sees "Proposal: we prefer flat files" and "Proposal: we prefer databases" in the same queue and must resolve the tension manually without interlore providing context about the conflict.

**Recommendation:** Add conflict detection to F3. When a proposed pattern has counter-evidence in the corpus (artifacts that chose the opposite pole of the same tradeoff), surface both together as a "tension" rather than as independent proposals. This is architecturally consistent with PHILOSOPHY.md's "disagreement is signal" principle.

---

### P2: LLM-Based Pattern Detection Can Produce Plausible but Semantically Incorrect Updates

**Location:** PRD Non-Goals ("Natural language understanding of decision semantics"), F3

**Issue:** The Non-Goals section says interlore v1 does not attempt NLU -- it uses "structural patterns." But the structural patterns available (Alignment/Conflict lines, keywords, headers) are insufficient for philosophy-level reasoning (see P0 findings above). In practice, any useful implementation of F3 will require LLM-mediated interpretation of artifact content.

This creates the core epistemic risk: LLMs are fluent pattern-completers. They excel at producing plausible-sounding summaries of recurring themes. They are poor at:

1. **Distinguishing correlation from causation.** "Three PRDs chose Go" does not mean "our philosophy favors Go." It might mean "Go was pragmatically available for those tasks."
2. **Recognizing context-dependent decisions.** "Use flat files" in a v1 plugin scaffold context and "use flat files" in a data pipeline context are different decisions. An LLM summarizing both as "our philosophy prefers flat files" loses the context that made each decision correct.
3. **Avoiding sycophantic reinforcement.** If the current PHILOSOPHY.md emphasizes composition, the LLM is biased toward interpreting ambiguous artifact language as supporting composition -- producing DRIFT signals that are actually alignment signals, and missing genuine drift.

The PRD does not acknowledge these failure modes or specify mitigations.

**Recommendation:** Add explicit quality gates for proposals before they enter the review queue:
- Each proposal must include the specific text excerpts from artifacts (not LLM summaries) that constitute the evidence.
- Each proposal must state the counter-argument -- why this might NOT be a real pattern.
- Each proposal must specify the abstraction level and scope (project-wide philosophy vs. domain-specific heuristic).

These gates force the system to show its work and give reviewers the raw material to evaluate correctness.

---

### P3: The 2-Week Time Span Requirement Is Mentioned Once and Never Operationalized

**Location:** PRD F3 acceptance criteria

**Issue:** The classification says "established (3+ artifacts, 2+ weeks)" but the 2-week span is never mentioned again. The scan engine description does not specify how time span is measured (artifact creation dates? bead creation dates? file modification times?). The brainstorm does not mention it at all.

**Consequence:** Minor -- the time span is either a vestigial requirement that will be silently dropped, or an unstated dependency on artifact date metadata that may not be consistently available.

**Recommendation:** Either operationalize it (specify the date source, define what "2+ weeks" means -- first to last artifact? earliest to scan date?) or remove it and rely on bead-aware deduplication instead.

---

## Summary

The interlore PRD identifies a real and important gap: PHILOSOPHY.md has no feedback loop. But the proposed solution has foundational epistemic problems that would make its output unreliable.

**The most critical issues (P0):**
1. The primary signal source (Alignment/Conflict annotations) covers <2% of the artifact corpus. The fallback mechanism is unspecified.
2. "Latent design pattern" has no operational definition, making detection non-deterministic.

**Structural issues (P1):**
3. No mechanism distinguishes recapitulation of existing principles from discovery of new ones. Expect a noise-dominated proposal queue.
4. The tool violates its own project's closed-loop principle by not calibrating from accept/reject history.
5. The 3-artifact threshold counts artifacts, not independent decisions. Bead-aware deduplication is the obvious fix.

**Design gaps (P2):**
6. Conflicting patterns are not surfaced as tensions.
7. LLM-based pattern detection will produce plausible-sounding but potentially incorrect philosophy proposals. No quality gates exist for proposals.

**Minor (P3):**
8. The 2-week time span is unoperationalized.

The fd-decisions-interlore.md review (which exists in the flux-drive output directory) already flagged the independence problem and the threshold justification gap. This review corroborates those findings and adds the more fundamental concern: the PRD has not established that its pattern detection can produce correct output at all, given the current state of the artifact corpus and the absence of an operational definition for its core concept.
