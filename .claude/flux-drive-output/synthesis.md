# CUJ Review Synthesis Report

**Date:** 2026-03-13
**Documents Reviewed:** `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`
**Agents:** 6 review dimensions (product-accuracy, signal-quality, internal-consistency, guardrail-fitness, friction-completeness, user-product)

**Verdict:** `needs-changes` — The CUJs are well-structured and honest about friction, but contain 14 critical gaps that would cause user confusion or failure if left unaddressed.

---

## Executive Summary

| Metric | Value |
|--------|-------|
| **Validation** | 6/6 agents produced valid output |
| **Top-Severity Issues** | 14 blocking issues across all three CUJs |
| **Critical Gaps** | CLI command accuracy (install), success signal precision, current-state vs. Phase 2 boundaries |
| **Gate** | **FAIL** — Requires fixes before publishing for external use |

---

## Findings by Severity

### BLOCKING: Must Fix Before Publish

#### 1. [P1] **CLI install command is incorrect** — Product Accuracy + User Experience
- **Affected:** first-install.md, line 25
- **Issue:** Document states `claude install clavain` as the actual command. Reality: `claude plugins marketplace add` + `claude plugins install clavain@interagency-marketplace` (two commands, per install.sh and plugin-troubleshooting.md).
- **Impact:** Users attempting to follow the documented command will fail immediately. Trust erosion.
- **Agents reporting:** fd-product-accuracy, fd-user-product
- **Fix:** Replace command with the correct two-step process, or reference the install script in the README.

---

#### 2. [P1] **"Complexity-based model routing" presented as current when it is shadow-mode only** — Product Accuracy + Signal Quality + Guardrail Fitness
- **Affected:** running-a-sprint.md, lines 31-38
- **Issue:** Journey claims routing is "guided by the routing table, which Interspect adjusts based on outcome data" in present tense. Reality: complexity-based routing operates in `mode: shadow` (logs only, does not enforce); calibration-based adjustment is also shadow-mode. Base routing (phase/category-level) is active, but per-subtask complexity routing is not.
- **Impact:** Agents and users will expect behavior that does not exist. Guardrails fail because agents cannot verify claims.
- **Agents reporting:** fd-product-accuracy (3 findings), fd-signal-quality, fd-guardrail-fitness
- **Fix:** Add caveat: "*(Complexity-aware model routing is active in shadow mode — the system classifies tasks and logs recommended models, but base routing is applied. Enforced routing is planned.)*"

---

#### 3. [P1] **"Interspect adjusts routing" claimed as shipped in two locations without Phase 2 annotation** — Product Accuracy
- **Affected:** running-a-sprint.md line 38, code-review.md line 52
- **Issue:** Both documents present routing adjustment as observable success signals without noting they require Phase 2 work (manual propose/approve steps, not automated).
- **Impact:** Two different agents and users reading different documents will have incompatible expectations about automation level.
- **Agents reporting:** fd-product-accuracy (2 distinct findings merged), fd-signal-quality
- **Convergence:** 4/6 agents identified this as a cross-document inconsistency
- **Fix:** Add annotation to both: "*(Adjustment requires manual `/interspect:propose` + `/interspect:approve`; automated feedback loop is Phase 2.)*"

---

#### 4. [P1] **Status value casing error in two success signals** — Product Accuracy + Signal Quality
- **Affected:** first-install.md line 47, running-a-sprint.md line 69
- **Issue:** Both signals claim `bd show` reports status as uppercase "CLOSED". Actual output: lowercase `"closed"`. Human-readable and JSON output both use lowercase.
- **Impact:** Agent guardrails fail when they check for exact-match casing. Users see different text than documented.
- **Agents reporting:** fd-product-accuracy, fd-signal-quality (same underlying finding, two angles)
- **Convergence:** 2/6 agents
- **Fix:** Change both to lowercase: "`closed`". Also specify exact fields for "all state fields populated": status, claimed_by, claimed_at, closed_at.

---

#### 5. [HIGH] **Current-state vs. Phase 2 boundary not clearly drawn in code-review.md** — Product Accuracy + User Experience
- **Affected:** code-review.md (scattered throughout narrative)
- **Issue:** Multiple Phase 2 features are described in present tense throughout the narrative without clear demarcation. "Over time, the review gets better" and "Interspect adjusts routing" are aspirational but read as current. The parenthetical notes are scattered, creating a choppy experience. A reader forming expectations based on the narrative will be surprised.
- **Impact:** Product promise problem. Users will expect learning loops and automated routing that are not yet shipped.
- **Agents reporting:** fd-product-accuracy, fd-user-product, fd-guardrail-fitness
- **Convergence:** 3/6 agents
- **Fix:** Add a "Current State vs. Planned" table early in code-review.md that explicitly marks which features ship today and which are Phase 2.

---

#### 6. [HIGH] **"Write-behind protocol" presented as infrastructure but does not exist** — Product Accuracy
- **Affected:** running-a-sprint.md line 81
- **Issue:** CUJ claims "The write-behind protocol (raw output to kernel, summaries to context) mitigates this" as shipped infrastructure. Reality: this is a brainstorm proposal from 2026-02-16. The sprint does write artifacts to disk and read summaries (behavioral rule #2), but there is no "write-behind protocol" subsystem.
- **Impact:** Readers expect a formal mitigating infrastructure that does not exist. Misrepresentation of guardrails.
- **Agents reporting:** fd-product-accuracy
- **Fix:** Replace: "The convention of writing agent output to files and reading summaries into context mitigates this, but very long sprints may still hit quality degradation in later phases."

---

#### 7. [HIGH] **Severity and verdict vocabularies conflict across documents** — Internal Consistency + Guardrail Fitness
- **Affected:** code-review.md line 29 vs. clavain-quality-gates.md line 27
- **Issue:** code-review.md uses severity labels `blocking`, `important`, `suggestion`, `nit`. quality-gates.md uses P-codes: `P0/critical`, `P1/important`, `P2/suggestion`, `IMP/improvement`. No mapping provided. Also differs on verdict format.
- **Impact:** Reader/agent confusion when moving between documents. No way to programmatically validate that findings are correctly classified.
- **Agents reporting:** fd-internal-consistency (HIGH severity finding #1-2)
- **Convergence:** 2/6 agents
- **Fix:** Canonicalize on P-code vocabulary in code-review.md. Map severity labels: blocking→P0, important→P1, suggestion→P2, nit→IMP.

---

### HIGH: Address Before First User Testing

#### 8. [HIGH] **Success signals lack measurement commands and preconditions** — Signal Quality + Guardrail Fitness
- **Affected:** All three CUJs (6 measurable signals across the set)
- **Issue:** Signals specify assertions but not how agents/CI systems can execute them. Examples: "Install and onboard complete within 10 minutes" — no timestamp collection method specified. "Complexity classification matches actual effort" — no single-sprint bounds check provided.
- **Impact:** Agents reading these as guardrails have no way to execute them. Signals are aspirational, not verifiable.
- **Agents reporting:** fd-signal-quality (6 distinct findings), fd-guardrail-fitness (Finding #1)
- **Convergence:** 4/6 agents identified this as systemic
- **Fix:** For each measurable signal, add: precondition, command, and scope labels.

---

#### 9. [HIGH] **Observable signals don't name hooks, events, or file paths** — Signal Quality + Guardrail Fitness
- **Affected:** All three CUJs (7 observable signals)
- **Issue:** Signals describe what a human would notice but don't tell agents where the data lives. Examples: "First `/route` presents actionable options" — no hook ID or output format specified.
- **Impact:** Agents cannot implement these as automated checks. Signals are only human-evaluable.
- **Agents reporting:** fd-signal-quality (7 findings), fd-guardrail-fitness (Finding #2)
- **Convergence:** 2/6 agents
- **Fix:** For each observable signal, add at least one of: hook ID, file path/glob, event type name, database table, or command returning structured output.

---

#### 10. [HIGH] **Failure signals are completely absent** — Guardrail Fitness
- **Affected:** All three CUJs
- **Issue:** All three documents define success but zero failure cases. Agents don't know what constitutes a "sprint stuck" vs. "sprint failed," when to block vs. warn, or how to recover from partial failures.
- **Impact:** Agents have no decision tree for failure states. Users have no documented recovery paths.
- **Agents reporting:** fd-guardrail-fitness (Finding #3)
- **Severity:** high for agent use
- **Fix:** Add a "Failure Signals" table for each CUJ. Each failure should specify: condition, agent action (block/warn/retry/escalate), and recovery path.

---

#### 11. [HIGH] **First-install has no coverage for the most common failure: partial install** — Guardrail Fitness + User Experience
- **Affected:** first-install.md
- **Issue:** Signals jump from "install succeeds" to "onboard produces structure" to "sprint reaches Ship phase" — three large gaps. Most likely failure is partial success (Clavain installs, companion fails; CLAUDE.md created, beads init fails).
- **Impact:** New users hitting partial failure have no documented diagnosis or recovery path.
- **Agents reporting:** fd-guardrail-fitness (Finding #7), fd-user-product
- **Convergence:** 2/6 agents
- **Fix:** Add "Checkpoint Assertions" subsection with intermediate checks at each handoff point.

---

#### 12. [HIGH] **Phase 2 signals mixed with active signals without status markers** — Guardrail Fitness + Product Accuracy
- **Affected:** code-review.md signal table
- **Issue:** "Interspect adjusts routing based on review outcomes" and "Verdict confidence correlates with quality" are Phase 2 features, but the signal table does not carry a `status: planned` marker.
- **Impact:** False guardrails. Agents test for behavior that does not exist and report spurious failures.
- **Agents reporting:** fd-guardrail-fitness (Finding #6)
- **Fix:** Add `status` column to signal table: `active` (checkable now), `recording` (collect data but not gate), `planned` (skip).

---

### MEDIUM: Address Before Next Revision

#### 13. [MEDIUM] **Phase naming inconsistency: "Execute" vs. "work" vs. "review"** — Internal Consistency
- **Affected:** first-install.md lines 23, 44; running-a-sprint.md (canonical)
- **Issue:** first-install self-contradicts on phase names. Neither matches running-a-sprint's canonical names.
- **Impact:** Reader confusion about which phase names are official.
- **Agents reporting:** fd-internal-consistency (Finding #3, #4, #5)
- **Convergence:** 3/6 agents
- **Fix:** Align first-install to canonical names from running-a-sprint. Use "Execute" not "work," include "Reflect" in all phase lists.

---

#### 14. [MEDIUM] **18 of 20 friction points lack workarounds, mitigations, or tracking references** — Friction Completeness + User Experience
- **Affected:** All three CUJs
- **Issue:** Friction points state problems without solutions. "Error recovery on first run" identifies bad error messages but gives no guidance.
- **Impact:** Friction points are diagnostic but useless for developers hitting them. Users learn the system is broken but not how to work around it.
- **Agents reporting:** fd-friction-completeness (Finding F3)
- **Severity:** high for user satisfaction
- **Fix:** For each friction point, add one of: (a) a current workaround, (b) a link to a tracking bead/issue, (c) explicit "no mitigation yet, planned for Phase 2."

---

## Cross-Cutting Patterns

### Pattern 1: **Aspirational Architecture Mixed with Current State**
- **Documents:** code-review.md (most acute), running-a-sprint.md
- **Symptom:** Phase 2 features described in narrative without clear boundary markers
- **Impact:** Users form expectations about shipped capability, encounter Phase 2 work, feel misled
- **Recommendation:** Canonicalize on a single "current-state vs. planned" representation (table format preferred).

### Pattern 2: **Success Signals More Precise Than Narratives**
- **Documents:** All three
- **Symptom:** Signal tables are measurable/observable/qualitative; narratives are vague
- **Impact:** Developers reading narratives form intuitions that conflict with what signals actually verify
- **Recommendation:** Treat signal table as source of truth for testable claims.

### Pattern 3: **Signals Assume Instrumentation That Doesn't Exist Yet**
- **Documents:** All three
- **Symptom:** Signals reference "events," "hooks," "persistent storage" without specifying schemas or file paths
- **Impact:** Signals are unverifiable until instrumentation exists.
- **Recommendation:** Separate "current-state verifiable signals" from "planned-state signals that need instrumentation."

---

## Recommendations by Document

### first-install.md
**Priority fixes:**
1. Fix install command (blocking)
2. Add partial-install checkpoint signals
3. Align phase names to running-a-sprint's canonical list
4. Add shell/OS and git prerequisites to friction list

### running-a-sprint.md
**Priority fixes:**
1. Add shadow-mode caveat to complexity/calibration routing claims
2. Replace non-existent "write-behind protocol" with honest description
3. Provide concrete complexity classification examples
4. Add ship-phase gate failure recovery scenario

### code-review.md
**Priority fixes:**
1. Add "Current State vs. Planned" table early in document
2. Fix Interspect routing claim to note manual steps (Phase 2)
3. Canonicalize severity and verdict vocabularies with quality-gates.md
4. Add edge cases: agent timeout handling, zero-findings verdict, parallel dispatch failures

---

## Files for Correction

- `/home/mk/projects/Demarch/docs/cujs/first-install.md` (7 issues)
- `/home/mk/projects/Demarch/docs/cujs/running-a-sprint.md` (8 issues)
- `/home/mk/projects/Demarch/docs/cujs/code-review.md` (9 issues)

---

## Summary

The CUJs are well-intentioned, honestly written, and structured for both human and agent use. The primary issues are:

1. **Factual errors** (CLI command, casing, non-existent infrastructure) that make following the docs fail
2. **Phase 2 / current-state boundary confusion** that creates wrong user expectations
3. **Incomplete instrumentation** in success signals that prevents agents from implementing guardrails
4. **Missing recovery paths** for the most likely failure scenarios

Addressing the blocking issues (#1-7) and high-severity issues (#8-12) would make these documents suitable for publication and agent use.

**Gate Recommendation:** `FAIL` — Do not publish for external use until blocking and high-severity issues are resolved. These documents would cause user confusion or product promise violations in their current form.
