---
artifact_type: flux-drive-review
domain: module-boundary-integrity
reviewer: fd-module-boundary-integrity
reviewed_documents:
  - docs/prds/2026-03-21-interlore.md
  - docs/brainstorms/2026-03-21-interlore-brainstorm.md
  - interverse/interdoc/AGENTS.md
  - interverse/interwatch/AGENTS.md
  - interverse/interwatch/config/watchables.yaml
  - interverse/interpath/AGENTS.md
  - interverse/interpath/skills/artifact-gen/references/source-catalog.md
  - PHILOSOPHY.md
review_date: 2026-03-21
---

# Flux Drive: Module Boundary Integrity Review -- interlore PRD

## Summary

interlore introduces a philosophy-observation capability that sits between three existing plugins: interwatch (drift detection), interdoc (doc generation), and interpath (artifact discovery + synthesis). The Unix decomposition stated in the brainstorm is sound in principle -- interlore detects patterns, interdoc checks alignment, interwatch monitors drift. In practice, the PRD has **2 boundary violations, 1 undefined interface contract, and 2 scope ambiguities** that will cause ownership confusion and duplicated pipelines if shipped as-is.

---

## Findings

### P0: interlore Duplicates interpath's Artifact Discovery Pipeline

**Location:** PRD F3, acceptance criteria bullet 1: "Scans: `docs/brainstorms/*.md`, `docs/prds/*.md`, `docs/prd/*.md`, `.claude/flux-drive-output/fd-*.md`, `docs/plans/*.md`"

**The violation:** interpath already owns artifact discovery. Its `references/source-catalog.md` (line 14-21 of source-catalog.md) defines glob patterns for exactly these paths:

- `docs/brainstorms/*.md` -- Source catalog row "Brainstorms"
- `docs/prds/*.md` -- Source catalog row "Monorepo PRDs"
- `docs/plans/*.md` -- Source catalog row "Plans" and "Monorepo plans"
- Flux-drive summaries -- Source catalog row "Flux-drive summaries" (different subpath but same domain)

interlore's F3 hardcodes its own discovery globs instead of consuming interpath's source catalog or a shared discovery contract. This creates two independent crawlers walking the same directories with slightly different glob patterns (`docs/prd/*.md` in interlore vs `docs/PRD.md` in interpath; `.claude/flux-drive-output/fd-*.md` in interlore vs `docs/research/flux-drive/*/summary.md` in interpath).

**Failure scenario:** When artifact directory conventions change (e.g., `docs/prd/` merges into `docs/prds/`), interpath's source-catalog gets updated but interlore's hardcoded globs do not. interlore silently stops finding artifacts. No signal is emitted because the dirs still exist but are empty from interlore's perspective.

**Fix:** interlore should either (a) import interpath's source-catalog.md glob patterns at scan time, or (b) declare its own `references/source-catalog.md` that explicitly documents which paths it crawls and why they differ from interpath's. Option (a) is cleaner -- interlore calls interpath's discovery phase (or reads the catalog) and then applies its own pattern-extraction logic on top of the discovered artifacts. This matches PHILOSOPHY.md "Composition Over Capability": discovery is interpath's job, pattern detection is interlore's job.

**Concrete diff:** In F3 acceptance criteria, replace the hardcoded glob list with: "Consumes artifact paths from interpath's source-catalog or a shared discovery contract. Applies pattern extraction to discovered brainstorms, PRDs, flux-drive outputs, and plans."

---

### P1: interlore's Output Schema Is Undefined -- Downstream Consumers Cannot Parse Proposals

**Location:** PRD F3 bullet 5: "Writes proposals to `.clavain/interlore/proposals.md` with evidence links"; PRD Open Questions #3: "Should interdoc call interlore during generation, or just read the staging file?"

**The violation:** The PRD defines interlore's output as a markdown file (`.clavain/interlore/proposals.md`) but never specifies a schema. Downstream consumers are identified:

1. **interwatch** (F5): needs to read `interlore_patterns_pending` signal -- requires knowing how to count pending proposals.
2. **interdoc** (F5): needs to read staging file during generation -- requires knowing where proposals are and their structure.
3. **/interlore:review** (F4): needs to parse proposals for accept/reject/defer -- requires frontmatter or structured sections.

Without a schema, each consumer will parse the markdown differently. interwatch will regex-count `## Proposal` headers, interdoc will look for `Status: pending` lines, and `/interlore:review` will expect a third format. Three parsers for one file is a maintenance trap.

**Failure scenario:** interlore changes proposal formatting (e.g., switches from `## Proposal: <name>` to `### <name>` with YAML frontmatter). interwatch's signal evaluator breaks silently -- it still reads 0 pending proposals, so it never fires the drift signal. interdoc reads stale proposals because its regex no longer matches the new format.

**Fix:** Define a proposal schema in the PRD. Minimum viable schema:

```yaml
# .clavain/interlore/proposals.md -- structured frontmatter per proposal
# Each proposal is a YAML-frontmatter-delimited section:
---
id: interlore-001
status: pending|accepted|rejected|deferred
classification: established|emerging|nascent
confidence: 0.0-1.0
evidence:
  - path: docs/prds/2026-03-21-interlore.md
    pattern: "composition over monolith"
  - path: docs/brainstorms/2026-03-20-foo.md
    pattern: "composition over monolith"
proposed_section: "Composition Over Capability"
proposed_change: |
  Add: "Integration over reimplementation when mature tools exist."
created: 2026-03-21
reviewed: null
---
```

Alternatively, emit proposals as individual YAML files in `.clavain/interlore/proposals/` -- one file per proposal, machine-parseable, git-diffable.

---

### P1: interwatch Integration Creates a New Signal Type Without Defining Its Evaluator Contract

**Location:** PRD F5 bullet 2: "interwatch `watchables.yaml` includes PHILOSOPHY.md with `interlore_patterns_pending` signal type"

**The violation:** interwatch has 14 existing signal types (listed in AGENTS.md lines 97-108), each with a defined evaluator in `scripts/interwatch-scan.py` via the `SIGNAL_EVALUATORS` dispatch table. The PRD proposes adding `interlore_patterns_pending` as a new signal type but does not define:

1. **Who implements the evaluator.** Does interlore ship a signal evaluator that interwatch calls? Or does interwatch implement the evaluator by reading `.clavain/interlore/proposals.md`?
2. **The evaluator contract.** interwatch's existing evaluators follow a pattern: `(watchable, state, project_root) -> score`. Is the new signal consistent with this?
3. **Threshold semantics.** Other signals use `weight`, `threshold`, `threshold_min`, `checker` fields. The PRD specifies none of these for the new signal.

This is not just a missing detail -- it determines which plugin owns the evaluation logic for PHILOSOPHY.md drift detection. If interwatch owns it, interwatch gains a dependency on interlore's output format. If interlore owns it, interlore reaches into interwatch's evaluator pipeline.

**Failure scenario:** The signal is added to watchables.yaml but no evaluator exists in `SIGNAL_EVALUATORS`. interwatch's scan encounters an unknown signal type and either (a) crashes, (b) silently skips it, or (c) logs a warning that nobody reads. In all cases, PHILOSOPHY.md drift detection is dead on arrival.

**Fix:** The PRD should specify: "interlore ships a `checker` function (or script) that interwatch can call via the existing `checker` field in watchables.yaml signal definitions. The checker reads `.clavain/interlore/proposals.md`, counts proposals with `status: pending`, and returns a score. interwatch does not parse interlore's internal format -- it delegates to the checker." This follows the existing pattern used by `roadmap_bead_coverage` (checker: `_watch_roadmap_bead_coverage`) and `unsynthesized_doc_count` (checker: `_watch_unsynthesized_count`).

---

### P2: Sprint Stop Hook Reaches Beyond Event Emission Into Active Scanning

**Location:** PRD F5 bullet 1: "Sprint Stop hook runs `interlore scan --quiet` after sprint completion"

**The concern:** PHILOSOPHY.md's "Wired or it doesn't exist" principle says hooks should emit evidence. The brainstorm correctly frames the hook as "passive accumulation." But `interlore scan --quiet` is not passive -- it actively crawls artifact directories, runs pattern classification, diffs against PHILOSOPHY.md, and writes proposals to the staging file. This is a full computation triggered synchronously in a sprint stop path.

Compare with interwatch's design: "No hooks -- drift detection is on-demand, not event-driven" (interwatch CLAUDE.md). interwatch made the explicit architectural choice NOT to run detection from hooks because it is expensive and blocking.

**Failure scenario:** Sprint stop takes 30+ seconds because interlore scans 50+ brainstorms and flux-drive outputs. The user learns to Ctrl-C sprint stops, which skips other post-sprint hooks (bead close, budget reconciliation). Alternatively, `--quiet` suppresses errors, and a broken scan silently corrupts the proposals file on every sprint stop.

**Fix:** Two options, both cleaner:

1. **Event-only hook:** The sprint Stop hook emits an `interlore.sprint_completed` event (or writes a timestamp to `.clavain/interlore/last-sprint-stop`) that interlore's next on-demand scan picks up as a trigger. The hook itself does zero scanning.
2. **Background scan:** If active scanning from the hook is desired, run it in background (`interlore scan --quiet --background`) so it does not block sprint completion. Write results asynchronously.

Option 1 is more consistent with the ecosystem (interwatch avoids hooks for the same reason). Option 2 is acceptable if scan latency is demonstrably low (<5s).

---

### P2: Boundary Between interlore (Pattern Detection) and interwatch (Drift Detection) for PHILOSOPHY.md Is Ambiguous

**Location:** PRD F3 bullet 4: "Diffs against current PHILOSOPHY.md sections to detect both EMERGING (new pattern) and DRIFT (contradiction)"; PRD F5 bullet 2: interwatch `interlore_patterns_pending` signal

**The ambiguity:** interlore detects two things: EMERGING patterns and DRIFT from philosophy. interwatch also detects drift -- that is literally its job. The PRD says interlore's DRIFT detection is "decisions that contradict stated philosophy," while interwatch's drift detection is "has the world changed since this doc was written?" These are different but overlapping:

- interwatch can detect that PHILOSOPHY.md is stale (20 commits since last update, 3 PRDs contradict it).
- interlore can detect that PHILOSOPHY.md is contradicted (PRD chose monolith over composition).

Who owns "PHILOSOPHY.md has drifted"? Both plugins can legitimately claim this signal. The PRD wires interlore into interwatch as a signal source (F5), but interlore also does its own drift detection independently (F3). This creates two paths to the same conclusion with no deconfliction.

**Fix:** Draw a hard line: interwatch owns "is this doc stale?" (staleness signals, commit counts, bead changes). interlore owns "does project behavior contradict this doc?" (semantic pattern analysis). interlore emits its findings as a signal that interwatch consumes -- but interlore does NOT independently flag PHILOSOPHY.md as needing refresh. interlore proposes philosophy changes; interwatch decides when PHILOSOPHY.md needs regeneration. The PRD's F3 should split "DRIFT" into "contradiction" (interlore's domain: the pattern contradicts a stated principle) and "staleness" (interwatch's domain: the doc hasn't been updated despite project changes). The current PRD conflates them under "DRIFT."

---

### P3: `.clavain/interlore/` Directory Ownership Is Novel and Unvetted

**Location:** PRD F3 bullet 5, F4 bullet 1: `.clavain/interlore/proposals.md`

**The concern:** The `.clavain/` directory currently contains kernel-owned state: `intercore.db`, `interspect/`, `quality-gates/`, `reviews/`, `verdicts/`. These are all kernel-native or L2 subsystem stores. interlore is proposed as a standalone Interverse plugin (not kernel-native), yet it writes to `.clavain/`.

No other standalone plugin writes to `.clavain/`. Standalone plugins write to their own directory (`.interwatch/`, plugin-local state). Writing to `.clavain/` implies kernel-native status that the PRD does not claim.

**Fix:** Either (a) interlore writes to `.interlore/` (consistent with `.interwatch/` convention for standalone plugins), or (b) the PRD explicitly argues for kernel-native designation per PHILOSOPHY.md's three criteria (feeds/consumes kernel subsystem, standalone mode would require duplicating kernel state, downstream consumers depend on kernel integration). interlore does not obviously meet these criteria -- its proposals file has no kernel dependency.

---

## What Is Clean

1. **interlore does not generate docs.** F4 modifies PHILOSOPHY.md on human accept, but generation of AGENTS.md, roadmaps, etc. stays with interdoc/interpath. Good boundary.
2. **interdoc fix is scoped correctly.** F5 makes interdoc actually Read PHILOSOPHY.md during generation. This closes a real gap without expanding interdoc's responsibility.
3. **Non-goals are well-drawn.** "Not replacing interdoc's AGENTS.md generation" and "not cross-project" keep interlore from creeping into adjacent domains.
4. **Review is interactive, not automated.** `/interlore:review` keeps humans in the loop for philosophy changes, consistent with the trust ladder (currently Level 1-2).

---

## Summary Table

| ID | Priority | Finding | Fix |
|----|----------|---------|-----|
| 1 | P0 | Duplicates interpath's artifact discovery pipeline | Consume interpath's source-catalog instead of hardcoding globs |
| 2 | P1 | Output schema undefined -- downstream consumers cannot parse proposals | Define YAML schema for proposals (frontmatter per proposal or individual files) |
| 3 | P1 | New interwatch signal type has no evaluator contract | Specify checker function pattern, consistent with existing `_watch_*` evaluators |
| 4 | P2 | Sprint Stop hook runs full scan synchronously | Emit event only; let on-demand scan pick it up |
| 5 | P2 | DRIFT detection boundary between interlore and interwatch is ambiguous | Split "drift" into "contradiction" (interlore) vs "staleness" (interwatch) |
| 6 | P3 | `.clavain/` directory write from a standalone plugin | Use `.interlore/` or explicitly justify kernel-native designation |
