---
bead: sylveste-rsj.3
date: 2026-03-30
type: prd
status: draft
source: brainstorm 2026-03-30-roguelike-agent-architecture-brainstorm.md
---

# PRD: Roguelike-Inspired Agent Architecture

## Problem Statement

Sylveste's core design patterns (evidence-based trust, stigmergic coordination, progressive autonomy, phase-gated sprints) were derived from software engineering intuition. External research on roguelike game environments and agent benchmarks independently validates and extends these patterns with empirical evidence we haven't yet incorporated. Three gaps:

1. **Interspect's tool/model discovery is implicit** — evidence accumulates but there's no explicit "identification phase" that uses cheap signals before expensive ones.
2. **Our evaluation story is SWE-bench-shaped** — we lack benchmarks that test long-horizon planning, irreversible consequences, and emergent complexity, which are Sylveste's actual differentiators.
3. **Evidence compounding is invisible** — the flywheel works but users can't see it, which weakens both trust and the product story.

## Features

### F1: Identification-as-Calibration in Interspect (P2)

**What:** Add an explicit tool/model identification phase inspired by NetHack's graduated item identification system.

**How:** Before routing to a model/agent, Interspect checks signals in cost order:
1. Metadata (model family, context window, known strengths) — free
2. Prior traces (same task type, similar complexity) — cheap query
3. Peer signal (what did other agents use for similar work) — medium
4. Full benchmark probe (send a calibration task) — expensive, last resort

**Success metric:** Routing decisions made at signal level 1-2 (no probe needed) ≥ 80% of the time. Probe-triggered routing changes ≥ 50% accuracy when they fire.

**Bead:** sylveste-rsj.3.1

### F2: BALROG/NetHack Evaluation Harness (P2)

**What:** Run Skaffen against the BALROG benchmark suite to test whether Sylveste's orchestration infrastructure outperforms raw models on hard agentic tasks.

**How:**
1. Set up BALROG locally (6 environments: BabyAI, Crafter, TextWorld, Baba Is AI, MiniHack, NetHack)
2. Create a Skaffen adapter that maps BALROG observations → Skaffen's OODARC loop
3. Run baseline (raw model) and Skaffen-orchestrated agents on same environments
4. Measure progression delta: does orchestration help?

**Success metric:** Skaffen-orchestrated agents exceed raw model progression by ≥ 50% on at least 3 of 6 BALROG environments. On NetHack specifically, exceed the 12.56% GPT 5.2 baseline.

**Bead:** sylveste-rsj.3.2

### F3: Stigmergic Coordination Evidence in Vision Doc (P2)

**What:** Ground Garden Salon's CRDT shared-state design in published stigmergy research.

**How:**
1. Cite the 36-41% advantage finding (arxiv 2601.08129v2) in sylveste-vision.md
2. Evaluate whether current CRDT design captures temporal decay and pressure field patterns
3. If gaps found, create design proposals for Garden Salon's coordination layer

**Success metric:** Vision doc updated with empirical grounding. Design gap analysis completed.

**Bead:** sylveste-rsj.3.3

### F4: Permaconsequence Visibility in Meadowsyn (P3)

**What:** Make evidence compounding visible so users can see the flywheel working.

**How:** Meadowsyn visualization showing:
- How a correction in session N changed routing in session N+5
- Evidence accumulation over time per agent/model
- Before/after comparisons when routing overrides activate

**Success metric:** A user can point to a specific visualization and say "this is why the system got better."

**Bead:** sylveste-rsj.3.4

### F5: Agentica SDK Evaluation (P3)

**What:** Evaluate Symbolica's Agentica SDK for specific patterns to adopt in Skaffen.

**How:** Assess three patterns: (1) stateful REPL for interleaved reasoning, (2) context compression via sub-agent summaries, (3) parallel hypothesis exploration. For each, determine whether Skaffen already has the equivalent, whether the pattern improves on what we have, and what adoption would cost.

**Success metric:** Assessment doc with adopt/adapt/skip verdict per pattern.

**Bead:** sylveste-rsj.3.5

### F6: GameDevBench Secondary Benchmark (P3)

**What:** Add GameDevBench as a secondary evaluation benchmark for complex multi-file work.

**How:** Set up GameDevBench (132 tasks, 3x SWE-bench code changes), run Clavain-orchestrated agents, compare to published baselines.

**Success metric:** Baseline established. If orchestration outperforms raw models, publish results.

**Bead:** sylveste-rsj.3.6

## Scope

**In scope:** F1-F3 (P2 items with direct design implications). F4-F6 are follow-on work.

**Out of scope:** Actually building a NetHack-playing agent (that's a research project, not a product feature). Rewriting Interspect's routing engine (F1 extends it, doesn't replace it).

## Risk

- **F2 setup complexity:** BALROG has 6 different environments with different dependencies. Mitigate: start with TextWorld + MiniHack (text-based, closest to our domain).
- **F1 over-engineering:** The identification phase could add latency to every routing decision. Mitigate: levels 1-2 must be < 10ms; level 3-4 only fire when cheap signals are ambiguous.
