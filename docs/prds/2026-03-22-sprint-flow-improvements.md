---
artifact_type: prd
bead: Demarch-0ztn
stage: design
---
# PRD: Sprint Flow Improvements (Iteration 1)

## Problem

The Clavain sprint flow has three concrete bugs (non-atomic artifact/advance, phase corruption in Step 9, TOCTOU in bead claiming) and structural issues where reflect is routinely skipped and failures halt instead of degrading gracefully. A 16-agent review identified 7 convergent themes; this iteration targets the 3 bugs + 2 highest-impact themes.

## Solution

Fix the three P1 bugs in clavain-cli Go code and sprint SKILL.md, then implement the two highest effort/impact improvements: hardening the reflect gate (Theme 2 minimum viable) and adding degraded mode definitions (Theme 5 minimum viable).

## Features

### F1: Bug — Make set-artifact + sprint-advance atomic
**What:** Combine `set-artifact` and `sprint-advance` into a single operation so artifact recording can't be orphaned if advance fails.
**Bead:** Demarch-2wzj
**Files:** `os/Clavain/cmd/clavain-cli/phase.go`
**Acceptance criteria:**
- [ ] New `cmdSetArtifactAndAdvance` function that writes artifact first, then advances; if advance fails, logs warning but artifact is still recorded (current behavior preserved — artifact is always recorded)
- [ ] Sprint SKILL.md updated to use the combined call where both are done sequentially
- [ ] If advance fails after artifact write, stderr explains the state (artifact recorded, phase not advanced)

### F2: Bug — Fix Step 9 sprint-advance phase corruption
**What:** Step 9 (Reflect) calls `sprint-advance "shipping"` when entering reflect, which records a "shipping" phase transition instead of letting `/reflect` own the phase advance.
**Bead:** Demarch-84sv
**Files:** `os/Clavain/skills/sprint/SKILL.md`
**Acceptance criteria:**
- [ ] Step 9 no longer calls `sprint-advance` before `/reflect`
- [ ] `/reflect` remains the sole owner of the `reflect → done` phase transition
- [ ] Phase state machine shows correct `shipping → reflect → done` progression (no duplicate "shipping" entry)

### F3: Bug — Fix TOCTOU in cmdBeadClaim
**What:** Two sessions can both read `claimed_by` as unclaimed, both pass the check, and both write their claim. The last writer wins silently.
**Bead:** Demarch-r9b5
**Files:** `os/Clavain/cmd/clavain-cli/claim.go`
**Acceptance criteria:**
- [ ] Bead claim uses locking (ic lock or fallback mkdir lock) to serialize the read-check-write sequence
- [ ] Second claimer gets an error, not a silent overwrite
- [ ] Lock timeout is short (500ms) to avoid blocking sprints
- [ ] Test: concurrent claim attempts in `claim_test.go`

### F4: Reflect gate hardening (Theme 2 minimum viable)
**What:** Change reflect from soft gate (warn but allow skipping) to firm gate requiring a minimal artifact (3 lines minimum). Show value at sprint start by surfacing recent reflect learnings.
**Bead:** Demarch-6lpp
**Files:** `os/Clavain/skills/sprint/SKILL.md`, `os/Clavain/cmd/clavain-cli/phase.go`
**Acceptance criteria:**
- [ ] Step 9 requires a reflect artifact with >= 3 non-empty lines before allowing advance to Step 10
- [ ] Gate enforcement: `enforce-gate "shipping"` checks for reflect artifact presence and minimum content
- [ ] Sprint bootstrap (Step 0) shows up to 3 recent reflect learnings from sibling beads ("Past learnings that influenced this sprint:")
- [ ] Failed sprints that produce a reflect artifact still have it recorded (no survivorship bias)

### F5: Degraded mode definitions (Theme 5 minimum viable)
**What:** Define explicit degraded modes so sprints continue at reduced capability instead of halting on subsystem failures. Replace binary running/halted with a degradation ladder.
**Bead:** Demarch-qlnk
**Files:** `os/Clavain/skills/sprint/SKILL.md`, `os/Clavain/config/degraded-modes.yaml` (new)
**Acceptance criteria:**
- [ ] `config/degraded-modes.yaml` defines capability reduction table for 5 subsystems: review fleet, test suite, intercore, routing, budget
- [ ] Sprint SKILL.md Error Recovery section references degraded modes instead of "retry once, halt"
- [ ] Each degraded mode has: trigger condition, reduced capability description, flag for downstream steps
- [ ] Sprint summary includes degradation events if any occurred during the sprint

## Non-goals (deferred to future iterations)
- Theme 1: OODARC as nested loops (deepest structural change — needs separate design)
- Theme 3: Complexity as belief distribution (cognitive overhead needs more research)
- Theme 4: Review gauntlet / Jidoka + tolerance.yaml (depends on Theme 1 orient loops)
- Theme 6: Composable sprint pipeline (Phase 2+ — needs entry/exit contract design first)
- Theme 7: Mycorrhizal sprint network (architecturally ambitious — start after composable pipeline)
- Reflect pre-commitment budget (Ulysses contract) — deferred to Theme 2 iteration 2
- Apoptosis / self-termination (deferred to Theme 5 iteration 2)

## Dependencies
- F1, F2, F3 are independent — can be done in parallel
- F4 depends on F2 (reflect phase must be clean before hardening the gate)
- F5 is independent of all others

## Open Questions
1. F3 lock scope: should the lock cover the entire `cmdBeadClaim` or just the read-check-write window? (Recommendation: just the read-check-write — minimize lock duration)
2. F4 minimum content: 3 non-empty lines is arbitrary. Should it be a structured format instead? (Recommendation: start with line count, iterate to structured later)
