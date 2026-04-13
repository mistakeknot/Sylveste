---
artifact_type: plan
bead: none
stage: plan
sources:
  - docs/brainstorms/2026-04-09-sylveste-vision-v5-brainstorm.md
  - docs/research/flux-review/sylveste-vision-v5-brainstorm/2026-04-09-synthesis.md
---

# Plan: Sylveste Vision v5.0 — Compounding Evidence, Earned Trust

**Date:** 2026-04-11
**Scope:** Rewrite `docs/sylveste-vision.md` (v4.0 -> v5.0), update `PHILOSOPHY.md`, update `MISSION.md`
**Inputs:** Brainstorm (2026-04-09), 4-track flux-review synthesis (35 agents, 8 P0, 10 P1)

---

## Overview

The v5.0 vision rewrite reframes Sylveste around "Compounding Evidence, Earned Trust" — replacing the three-axis pitch (autonomy/quality/efficiency) with an evidence thesis, replacing the L0-L4 autonomy ladder with a capability mesh, and incorporating 5 new P0/P1 epics launched since March 29. The flux-review surfaced 8 P0 findings that must be addressed in the rewrite, not deferred. The highest-leverage single fix is defining an ordinal maturity scale (M0-M4) that makes the capability mesh operational.

**Files modified:**
- `docs/sylveste-vision.md` — full rewrite (328 lines -> ~400-450 lines)
- `PHILOSOPHY.md` — add 2 principles/expansions (~20-30 lines added to 224-line file)
- `MISSION.md` — update paragraph (5 lines -> ~6-8 lines)

**Files read (not modified):**
- `docs/brainstorms/2026-04-09-sylveste-vision-v5-brainstorm.md`
- `docs/research/flux-review/sylveste-vision-v5-brainstorm/2026-04-09-synthesis.md`
- Current `docs/sylveste-vision.md` v4.0

---

## Phase 1: Design Decisions (pre-write)

These are mechanism decisions that the flux-review identified as P0 gaps. They must be resolved before writing because multiple sections of the vision reference them. Each task produces a design artifact (inline in this plan) that Phase 2 writes into the vision.

### Task 1: Define ordinal maturity scale (M0-M4)

**Why:** P0-6 (commensurability). Without this, the "minimum of subsystem maturities" rule is inoperable. Unblocks P0-6, P1-1, P1-2, P1-3.

Define 5 named maturity levels with observable criteria:

| Level | Name | Criteria | Evidence |
|-------|------|----------|----------|
| M0 | Planned | Design exists, no code | Brainstorm/PRD artifact |
| M1 | Built | Code shipped, not operationally tested | Tests pass, features merged |
| M2 | Operational | Running under real conditions, evidence flowing | Evidence signals yielding data for >30 days |
| M3 | Calibrated | Evidence thresholds defined and tested, promotion/demotion criteria met | Threshold hit rate, calibration history |
| M4 | Adaptive | Self-improving based on evidence, minimal human intervention needed | Interspect proposals applied, metrics improving autonomously |

Each subsystem publishes a factor-to-maturity mapping converting its raw signals to M0-M4. The minimum rule operates on maturity levels, not raw metrics.

**Addresses:** P0-6, P1-1, P1-3

### Task 2: Draw subsystem dependency DAG

**Why:** P0-3 (hidden dependency chains), P0-8 (no prerequisite ordering).

Map which subsystems depend on which for maturity advancement:

```
Phase 1 (independent roots):
  Persistence (Intercore) — no upstream deps
  Coordination (Interlock) — no upstream deps
  Discovery (Interject) — no upstream deps

Phase 2 (first-order deps):
  Integration (Interop) — deps: Persistence
  Review (Interflux) — deps: none (works standalone)
  Execution (Hassease) — deps: none (works standalone)

Phase 3 (second-order deps):
  Ontology (Interweave) — deps: Integration
  Measurement (Factory Substrate + FluxBench) — deps: Persistence

Phase 4 (convergence):
  Governance (Ockham) — deps: Ontology, Measurement
  Routing (Interspect) — deps: Measurement, Governance
```

Redefine "independent" in the mesh to mean "independently measurable" — each cell has its own evidence signals — not "independently maturable" — some cells cannot advance until upstream cells reach M2+.

**Addresses:** P0-3, P0-8

### Task 3: Define the trust lifecycle

**Why:** P0-1 (no demotion), P0-7 (no staleness mechanism).

Replace "authority ratchet" terminology with "graduated authority" throughout. Define a 4-phase trust lifecycle per subsystem:

1. **Earn** — accumulate evidence against pre-specified thresholds. Evidence has quality tiers: Tier 1 (controlled experiments, human-resolved disagreements), Tier 2 (observational: gate pass rates, metrics), Tier 3 (anecdotal: ambient scanning, promotions).
2. **Compound** — trust level advances when threshold is met. Trust persists as long as evidence remains fresh and regression indicators are absent.
3. **Epoch** — when environmental conditions shift (major model change, architecture migration, subsystem replacement), trust is partially reset. The subsystem retains its maturity tier but must re-demonstrate at that tier under new conditions. Epochs are triggered by defined events, not time.
4. **Demote** — when evidence shows sustained degradation (regression indicators exceed threshold for defined window), trust drops one level. Demotion propagates to dependent subsystems. In-flight work continues at the lower trust level.

Key constraint from the vakif insight: evidence thresholds are revisable by human authority regardless of accumulated evidence. The evidence thesis earns trust for autonomous operation, but the right to redefine trust criteria remains with humans.

**Addresses:** P0-1, P0-7, P1-7

### Task 4: Define interface evidence signals

**Why:** P0-4 (no interface monitoring).

Define signals for critical pairwise subsystem interfaces (not all 45):

| Interface | Signal | What It Detects |
|-----------|--------|-----------------|
| Ontology / Governance | Entity identity agreement rate | Schema divergence |
| Routing / Measurement | Attribution chain integrity | Broken evidence pipeline |
| Integration / Ontology | Sync-to-entity success rate | Data representation mismatch |
| Review / Routing | Finding parse success rate | Format compatibility |
| Measurement / Governance | Evidence-to-policy latency | Feedback loop delay |

State the principle: "individual subsystem maturity is necessary but not sufficient; critical cross-subsystem interfaces are monitored as first-class evidence signals."

**Addresses:** P0-4, P1-4

### Task 5: Specify independent verification architecture

**Why:** P0-5 (self-reporting).

Clarify Interspect's dual role: it is both a subsystem in the mesh (Routing cell) AND the independent verification layer that observes other subsystems. State the structural separation:
- Interspect observes subsystem behavior through its own instrumentation (kernel events, gate outcomes, dispatch results), not through subsystem-reported metrics.
- No subsystem reports its own maturity score. Maturity is assessed by Interspect reading evidence from the kernel event surface.
- This is the "assay office" principle: the entity that stamps the hallmark must be independent of the entity being assayed.

**Addresses:** P0-5

---

## Phase 2: Write Vision Doc v5.0

Sequential tasks, each modifying a section of `docs/sylveste-vision.md`. Read current v4.0, preserve what's still valid, rewrite what's changed.

### Task 6: Rewrite "The Pitch" section

**Current:** Lines 1-20. Three-axis framing (autonomy/quality/efficiency).
**New:** Evidence thesis from brainstorm. Address P0-2 (aspirational vs operational) and P1-5 (no audience).

Content:
- Open with "the bottleneck is infrastructure, not intelligence" (borrowed from Approach A).
- Core thesis: trust earned through compounding evidence.
- Name the 4 evidence infrastructure systems (Ontology, Governance, Integration, Measurement).
- One sentence of audience identification: "For developers and platform builders who want autonomous agencies that earn trust through receipts."
- Distinguish current from planned: "Today, the flywheel operates on Interspect evidence. The v5.0 architecture expands to four upstream evidence sources, each in early operational phases."

**Keep:** "Not a coding assistant. Not an agent framework." differentiators. The "two brands" section. The "open source" statement.

### Task 7: Rewrite "The Stack" section

**Current:** Lines 42-85. Six pillars in three layers.
**New:** Same architecture, updated to reflect new systems.

- Add Ockham, Interweave, Interop, Hassease to their respective layers.
- Update Skaffen description for Auraken migration.
- Keep survival properties framing.
- Update module count commands.

### Task 8: Write "The Flywheel" section (new)

**Current:** Flywheel is scattered across pitch, frontier, and what's-next.
**New:** Dedicated section with causal loop diagram.

Content:
- v4.0 flywheel (operational, Interspect-only) shown with solid lines.
- v5.0 expansion (4 upstream sources) shown with dashed lines for planned sources.
- Explicitly name the closing link: "increased autonomy means more sprints complete without intervention; each sprint produces evidence; autonomy increases evidence production rate."
- Name at least 2 balancing loops (B1: weakest-link limits-to-growth, B2: evidence saturation / diminishing returns). Address P1-2.
- Scope sparse topology to agent collaboration (interflux), not system evidence flow. Address P1-8.
- Name the prerequisite ordering DAG from Task 2. Address P0-8.

### Task 9: Write "Capability Mesh" section (replaces autonomy ladder)

**Current:** Lines 192-208. L0-L4 autonomy ladder.
**New:** 10-cell capability mesh with maturity scale.

Content:
- M0-M4 ordinal scale from Task 1.
- 10-cell mesh table with columns: Subsystem, Owner, Capability, Dev State, Operational State, Evidence Signal, Maturity Level, Criticality (DAL-inspired from aviation insight).
- Dependency DAG from Task 2.
- Interface evidence signals from Task 4.
- Minimum rule stated clearly: "system-level trust = min(M level across mesh cells). This is a step function: the system advances when the weakest subsystem catches up."
- Address P1-2 tension: "Evidence compounds per-subsystem. System-level trust is a non-compounding step function gated on the weakest link."
- Mark untested subsystems honestly: "Untested (M1)" not "Shipped." Address P1-3.

### Task 10: Rewrite "Design Principles" section

**Current:** Lines 109-152. Seven principles.
**New:** Keep all 7, modify 2, add 1.

Modifications:
- Principle 6 ("Gates enable velocity"): add reference to graduated authority and demotion triggers.
- Principle 7 ("Self-building as proof"): update with current self-building evidence.

Addition:
- **Principle 8: Evidence is independently verified.** The "assay office" principle from Task 5. No subsystem self-reports its maturity. Interspect observes through its own instrumentation. Trust requires independent assessment.

### Task 11: Write "Trust Architecture" section (new)

**Current:** No equivalent section.
**New:** The central mechanism section — how trust actually works.

Content:
- Trust lifecycle from Task 3 (earn, compound, epoch, demote).
- Evidence quality taxonomy (Tier 1/2/3 from clinical trials insight).
- Threshold structure: "[evidence type] measured over [time window] evaluated by [authority], with pre-specified thresholds." Address P1-1.
- Evidence temporality: freshness dimension, epoch triggers (model changes, architecture migrations, subsystem replacements).
- Human authority reservation: "evidence thresholds are revisable by human authority regardless of accumulated evidence." Address vakif "dead founder" problem.
- Trust transfer protocol for subsystem replacement (istibdal): "replacement inherits trust conditionally, with probationary period + interface re-verification." Relevant for Auraken→Skaffen.

### Task 12: Rewrite "Where We Are" section

**Current:** Lines 270-284. Dated "late March 2026."
**New:** Dated "April 2026."

- Update all bullet points with April status.
- Add Ockham (F1-F7 shipped), Interweave (F1-F3), Interop (Phase 1), Hassease (brainstorm/plan), FluxBench (brainstorm/plan).
- Use Development State vs Operational State distinction from P1-3.
- Add current maturity levels per mesh cell.
- Update bead counts via `bd stats`.

### Task 13: Rewrite "What's Next" + add "Horizons" section

**Current:** Lines 286-310. Five themes + track diagram.
**New:** Six current themes + horizons section.

"What's Next" (active work):
1. Integration fabric (Interop) — P0
2. Factory governance (Ockham) — P0
3. Intelligence replatforming (Auraken→Skaffen + Hassease) — P0
4. Generative ontology (Interweave) — P1
5. Model qualification (FluxBench) — P1
6. Evidence pipeline closure (Interspect Phase 2) — P1

"Horizons" (future, with explicit dependencies):
- Garden Salon MVP — deps: Interop M2, Interweave M2, Ockham M2
- Domain-general north star — deps: Measurement M3
- Cross-project federation — deps: Interweave M3, Interop M3
- L4 auto-ship — deps: Governance M3, Routing M3

Remove stale track convergence diagram.

### Task 14: Update remaining sections

- "What This Is Not" (lines 312-318): keep, minor wording updates.
- "Origins" (lines 320-328): keep, update module count.
- "External Validation" (lines 99-107): keep if still current, or update with newer research.
- Footer links: verify all paths still exist.

---

## Phase 3: Update PHILOSOPHY.md

### Task 15: Add sparse topology principle

Scope to agent-to-agent collaboration, not system architecture. Add after existing collaboration guidance.

```
**Sparse topology in multi-agent collaboration.** Fully-connected agent networks
converge faster but to worse answers (Zollman effect). Default to sparse or ring
topologies for multi-agent review and discourse. Shift to full connectivity only
when rapid convergence is worth the diversity cost.
```

Note per nuclear safety insight: add maturity qualifier if appropriate ("at early maturity stages, default to full information sharing").

### Task 16: Add graduated authority mechanism

Distinguish the permanent principle from the revisable mechanism (per vakif insight).

Add under "Earned Authority" section:

```
**Graduated authority as mechanism.** Trust levels are tracked per-subsystem
using an ordinal maturity scale (M0-M4). Promotion requires pre-specified
evidence thresholds. Demotion is triggered by sustained regression indicators.
Evidence epochs reset trust when environmental conditions shift.

The principle (evidence earns authority) is permanent. The mechanism
(specific thresholds, epoch triggers, demotion criteria) is revisable by
human authority regardless of accumulated evidence.
```

---

## Phase 4: Update MISSION.md

### Task 17: Update mission paragraph

Keep to one paragraph (~6-8 lines). Update to reflect:
- Evidence thesis: "compounding evidence is the path to earned trust"
- Expanded infrastructure scope: ontology, governance, integration, measurement
- Keep two-brand architecture mention
- Keep "software engineering is the proving ground" framing

---

## Phase 5: Consistency Review

### Task 18: Cross-document consistency check

Read all three modified files. Verify:
- PHILOSOPHY.md three core principles still match vision's flywheel description
- MISSION.md mentions align with vision pitch
- "Earned Authority" in PHILOSOPHY.md is consistent with "Trust Architecture" in vision
- Maturity scale (M0-M4) is consistently defined across vision and philosophy
- No aspirational/operational conflation remaining (P0-2 addressed)
- Sparse topology scoped consistently (agent collaboration, not system architecture)
- Authority direction is unambiguous: philosophy → vision → roadmap

---

## Execution Notes

- **Parallelism:** Tasks 1-5 can be done in a single pass (they're design decisions, not file edits). Tasks 6-14 are sequential (each modifies a different section of the same file). Tasks 15-17 can run in parallel. Task 18 runs last.
- **Risk:** The biggest risk is aspirational/operational conflation (P0-2). Every section must distinguish what's shipped from what's planned.
- **Word budget:** Target ~400-450 lines for the vision (v4.0 is 328). The new sections (Flywheel, Capability Mesh, Trust Architecture) add ~150 lines; pruning the old ladder and stale track diagram removes ~80 lines.
- **Terminology:** "Authority ratchet" is replaced by "graduated authority" throughout all three documents. "Evidence epoch" is a new term introduced in the Trust Architecture section.
