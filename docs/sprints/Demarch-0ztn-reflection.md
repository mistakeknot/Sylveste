---
artifact_type: reflection
bead: Demarch-0ztn
stage: reflect
---
# Reflection: Sprint Flow Improvements (Iteration 1)

## What We Did

Fixed 3 P1 bugs and delivered 2 theme increments to the Clavain sprint orchestration flow. The brainstorm was pre-existing (16-agent review), so this sprint started at strategy and ran through ship.

## Key Learnings

### 1. Plan review agents catch real bugs that save hours of debugging

The 3-agent plan review (correctness, architecture, quality) found 17 issues before a single line of code was written. The most valuable catches:

- **Phase state machine misunderstanding (P0):** The initial plan proposed removing `sprint-advance "shipping"` from Step 9, which would have broken every sprint by removing the `shipping → reflect` transition. The `currentPhase` argument to `sprint-advance` is a calibration label, not a transition target — the ic kernel computes transitions independently. This subtlety was non-obvious from reading the code.
- **Artifact type mismatch (P1):** `reflect.md` registered artifacts as `"reflect"` but `knownArtifactTypes` uses `"reflection"`. The hardened gate would have blocked every sprint. Pre-existing bug surfaced by adding enforcement.
- **Config placement convention (P1):** `config/` files are always Go-loaded via `configDirs()`. Placing a Claude-read-only YAML there would have been the first violation.

### 2. The correctness agent disagrees with itself across passes — verify independently

The plan review correctness agent said "removing the sprint-advance breaks the state machine." The quality gates correctness agent said "reflect-entry is not a recognized phase — the advance will fail." Both were partially right but reached different conclusions. The resolution required reading `cmdSprintAdvance` directly to confirm that `currentPhase` is never passed to `ic run advance`.

Lesson: when two review passes disagree, go to the source code rather than choosing the more recent opinion.

### 3. Advisory locking is the honest answer for bd claims

The TOCTOU in `cmdBeadClaim` can't be fully closed with Go-side locking because `bd` CLI calls bypass it. Rather than pretending the lock provides strong guarantees, we documented it as advisory and made error handling transparent. This is more useful than a false sense of safety — downstream consumers now know to tolerate contested claims.

### 4. Degraded modes as a Claude-read reference (not Go config) is a valid pattern

Placing `degraded-modes.yaml` in `commands/` (alongside the SKILL.md that references it) rather than `config/` (where Go reads it) established a new pattern: LLM-read reference docs that live near the consuming prompt. This may be reusable for other decision tables that Claude consults during execution.

## What Surprised Us

- The `"reflect"` vs `"reflection"` artifact type mismatch was pre-existing and would have silently blocked reflect forever once the gate was hardened. The soft gate had been masking this bug.
- The phase `"reflect"` was missing from `phaseToAction` — beads resumed during the reflect phase would route incorrectly. Also pre-existing.
- The `isClaimStale` doc comment still said "45-minute" despite the threshold being changed to 10 minutes months ago.

## What to Do Differently Next Time

- When a plan review finds a P0, verify the finding against the actual code before accepting OR rejecting it. Both the plan review and quality gates caught real issues, but their framings conflicted.
- For the calibration double-recording bug (Demarch-84sv), the full fix requires changing `recordPhaseTokens` to use phase-transition keys rather than phase-name keys. This wasn't possible within this sprint's scope but should be a follow-up bead.
