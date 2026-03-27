# Internal Consistency Review: CUJ Documents

**Scope:** `docs/cujs/first-install.md`, `docs/cujs/running-a-sprint.md`, `docs/cujs/code-review.md`
**Reviewer:** fd-internal-consistency
**Date:** 2026-03-13

---

## Summary

7 inconsistencies found: 2 high (contradictory terminology), 3 medium (phase sequence drift), 2 low (actor/prerequisites gaps). The bead reference (`Sylveste-9ha`) is valid. Cross-document links resolve correctly. The most damaging inconsistencies are in severity terminology and phase naming, where two documents describing the same system use different vocabularies.

---

## Findings

### 1. [HIGH] Severity scale differs between code-review.md and clavain-quality-gates.md

**code-review.md line 29:**
> ranks by severity (blocking, important, suggestion, nit)

**clavain-quality-gates.md line 27:**
> findings tagged with severity levels: P0 (critical -- blocks merge), P1 (important -- should fix), P2 (suggestion), IMP (improvement -- optional)

These describe the same system (the synthesis layer that processes review agent output) but use incompatible severity vocabularies. code-review.md uses word labels (`blocking`, `important`, `suggestion`, `nit`). quality-gates uses P-codes with different labels (`P0/critical`, `P1/important`, `P2/suggestion`, `IMP/improvement`). Notable conflicts:
- "blocking" vs "critical" for the highest severity
- "nit" vs "IMP/improvement" for the lowest -- and these have different semantics ("nit" = trivial stylistic point; "improvement" = optional enhancement)
- quality-gates has 4 levels, code-review has 4 levels, but they don't map 1:1

**Impact:** A reader who reads code-review.md first and then encounters quality-gates.md will wonder if these are different systems or the same system described inconsistently. Trust erosion.

**Fix:** Canonicalize on one severity vocabulary across both documents. The P-code system in quality-gates is more precise and should likely be the canonical one.

---

### 2. [HIGH] Verdict options differ between code-review.md and clavain-quality-gates.md

**code-review.md line 29:**
> a verdict (approve, request changes, or needs discussion) and a confidence score

**clavain-quality-gates.md line 30:**
> Verdict: needs-changes / Gate: FAIL

And earlier in quality-gates line 30 (original version):
> Verdict: APPROVE with suggestions

These describe different verdict taxonomies for the same review synthesis:
- code-review.md: three-value (`approve`, `request changes`, `needs discussion`) plus confidence score
- quality-gates.md: binary gate pass/fail (`PASS`/`FAIL`) plus a verdict string (`needs-changes`, `APPROVE with suggestions`)

The confidence score mentioned in code-review.md does not appear anywhere in quality-gates.md. The "needs discussion" verdict from code-review.md has no equivalent in quality-gates.md.

**Impact:** These documents describe overlapping review systems. A developer reading both will not know which verdict taxonomy to expect.

**Fix:** Align verdict terminology. If quality-gates and code-review describe the same synthesis output, use the same verdict values.

---

### 3. [MEDIUM] Sprint phase names inconsistent: "Execute" vs "work"

**running-a-sprint.md line 31** uses the phase heading:
> **Execute.**

**first-install.md line 44** uses:
> brainstorm -> strategy -> plan -> **work** -> ship

The canonical phase list in running-a-sprint.md (the self-declared "canonical description of the sprint lifecycle") uses six bold headings: **Brainstorm**, **Strategy**, **Plan**, **Execute**, **Ship**, **Reflect**. But first-install.md calls the fourth phase "work" in its success signal table.

**Impact:** "Execute" and "work" are close enough to guess at, but inconsistent naming in a success signal table (which should be precise and testable) creates ambiguity about what the state machine actually calls this phase.

**Fix:** Use "Execute" in first-install.md line 44 to match the canonical names in running-a-sprint.md.

---

### 4. [MEDIUM] Sprint phase list in first-install.md omits "Reflect"

**first-install.md line 44:**
> brainstorm -> strategy -> plan -> work -> ship

This five-phase sequence omits "Reflect", which running-a-sprint.md (the canonical source) lists as the sixth and final phase. The same document's line 23 correctly lists six phases:
> brainstorm, strategy, plan, review, ship, reflect

So first-install.md contradicts itself: line 23 lists 6 phases (with "review" instead of "execute"), line 44 lists 5 phases (with "work" instead of "execute", missing "reflect").

**Impact:** The success signal on line 44 claims the sprint "reaches Ship phase" and lists phases ending at ship. This could be intentional (the assertion is about reaching ship, not completing reflect), but the omission makes it look like reflect isn't part of the lifecycle.

**Fix:** Either extend line 44 to include reflect (`brainstorm -> strategy -> plan -> execute -> ship -> reflect`) or add a note that the assertion covers reaching Ship, with Reflect following.

---

### 5. [MEDIUM] first-install.md line 23 lists "review" as a phase; running-a-sprint.md does not

**first-install.md line 23:**
> brainstorm, strategy, plan, review, ship, reflect

**running-a-sprint.md phase headings:**
> Brainstorm, Strategy, Plan, Execute, Ship, Reflect

In the canonical sprint lifecycle, "review" is not a named phase -- it happens within Ship (quality gates run during Ship) and optionally during Plan (review fleet examines the plan). first-install.md elevates "review" to a top-level phase name and drops "Execute" entirely. This is a different phase taxonomy.

**Impact:** A reader of first-install.md who then reads running-a-sprint.md will look for a "Review" phase heading and not find it. They will find an "Execute" phase heading that first-install.md never mentions.

**Fix:** Align the lifecycle list in first-install.md line 23 to match the canonical six phases: brainstorm, strategy, plan, execute, ship, reflect. Review is an activity within phases, not a phase itself.

---

### 6. [LOW] Actor gap: first-install "stranger" prerequisites vs code-review "regular user"

**first-install.md line 4:**
> actor: stranger (new platform user, no prior Sylveste exposure)

**first-install.md line 53:**
> Prerequisite sprawl. Claude Code is the baseline requirement, but Go (for beads/intercore), and optional tools (Codex CLI, Node for some plugins) add up.

**code-review.md line 4:**
> actor: regular user (developer reviewing code or documents)

first-install.md says its stranger needs only Claude Code as the "baseline requirement." But the journey narrative (line 25) shows the stranger installing `clavain` and companion plugins, running `/clavain:project-onboard`, and completing a sprint that includes quality gates review. After first-install, this stranger becomes a "regular user."

The gap: code-review.md (for regular users) doesn't mention any prerequisite beyond having code ready for review. But the review system uses interflux (flux-drive) and quality-gates, which first-install says are companion plugins that must be separately installed. If first-install's stranger skipped installing interflux, the code-review journey wouldn't work.

**Impact:** Low -- most readers will infer that "regular user" implies successful completion of first-install. But the prerequisite chain is implicit, not stated.

**Fix:** Add a one-line prerequisite note to code-review.md: "Assumes the developer has completed [first-install](first-install.md) and has interflux installed."

---

### 7. [LOW] Review entry point description inconsistency across documents

**code-review.md line 23:**
> The most common entry point is `/clavain:quality-gates`. [...] For direct control, developers can also invoke `/interflux:flux-drive`

**first-install.md line 45:**
> Quality gates or flux-drive produces a finding that changes the implementation

**running-a-sprint.md lines 29, 35:**
> the review fleet examines the plan before execution begins
> Quality gates run: tests pass, linting passes, and for risky changes, the review fleet examines the final diff

code-review.md establishes `/clavain:quality-gates` as the primary entry point and `/interflux:flux-drive` as the direct-control alternative. running-a-sprint.md never mentions either command by name -- it refers only to "the review fleet" and "Quality gates" (without the slash-command prefix). first-install.md uses both terms but as alternatives ("Quality gates or flux-drive").

The README.md table (line 41) describes code-review.md as covering "Quality-gates / flux-drive review, synthesis, Interspect learning" -- treating them as co-equal. But code-review.md itself describes a clear hierarchy (quality-gates is primary, flux-drive is the direct-control escape hatch).

**Impact:** Minor -- the terms are used loosely but not incorrectly. Running-a-sprint's omission of the actual command names means a reader can't go from reading about Ship phase to invoking the review.

**Fix:** running-a-sprint.md Ship phase could name the command: "Quality gates (`/clavain:quality-gates`) run: tests pass, linting passes..."

---

## Verified (No Issues)

- **Bead reference:** All three documents reference `bead: Sylveste-9ha`. Confirmed via `bd show Sylveste-9ha` -- it exists as an OPEN epic titled "CUJ program: maintain and expand Critical User Journey documents."
- **Cross-document links:** first-install.md links to `running-a-sprint.md` (line 29). running-a-sprint.md links to `first-install.md` (line 17) and `code-review.md` (lines 29, 35). code-review.md links to `running-a-sprint.md` (line 21). All links use relative paths and resolve correctly.
- **"Review fleet" terminology:** Used consistently across running-a-sprint.md and code-review.md to mean the set of specialized review agents dispatched during code review. No conflicting definition found.
- **"Triage layer" terminology:** Used only in code-review.md (line 25). Not contradicted elsewhere.
- **"Synthesis agent" terminology:** Used only in code-review.md (line 29). quality-gates.md calls it "synthesis layer" (line 27) and delegates to `intersynth:synthesize-review`. Minor naming difference ("agent" vs "layer") but scoped to different documents with different bead references.
- **running-a-sprint.md self-declaration as canonical:** Line 17 states "This CUJ is the canonical description of the sprint lifecycle. Other CUJs cross-reference this document rather than duplicating the phase narrative." first-install.md and code-review.md do cross-reference it appropriately.
