---
artifact_type: brainstorm
bead: none
stage: discover
---

# Brainstorm: Sylveste Vision v5.0 — Compounding Evidence, Earned Trust

**Date:** 2026-04-09
**Sources:** `docs/sylveste-vision.md` (v4.0), `MISSION.md`, `PHILOSOPHY.md`, 18 brainstorms + 13 PRDs from April 1-9, CASS session search, `bd stats`

---

## What We're Building

A v5.0 rewrite of `docs/sylveste-vision.md` plus sync of `PHILOSOPHY.md` and `MISSION.md`, reframed around the thesis: **trust in autonomous systems is earned through observable evidence that compounds over time.**

### The Pitch (v5.0)

The bottleneck to autonomous knowledge work isn't intelligence — it's infrastructure. But infrastructure alone is table stakes. What makes the system improve is **evidence that compounds**.

Sylveste builds the evidence infrastructure that lets AI agents earn progressively more authority:

- **Ontology** (Interweave) to track what's known across systems
- **Governance** (Ockham) to gate what's allowed based on earned trust
- **Integration** (Interop) to verify across system boundaries
- **Measurement** (Interspect + FluxBench) to prove what worked

Every sprint produces evidence. Evidence compounds. Trust ratchets. The system that ships the most sprints learns the fastest, and the system that learns the fastest earns the most authority.

Not a coding assistant. Not an agent framework. A platform for autonomous agencies that earn trust through receipts.

### Why v5.0, Not v4.1

In the 11 days since v4.0 (March 29), Sylveste launched 5 new P0/P1 epics not mentioned in the vision: Interop (Go integration fabric), Ockham (factory governor), Interweave (generative ontology), Hassease (multi-model execution), and Auraken→Skaffen migration (Go replatforming). These aren't feature additions — they represent an expanded understanding of the flywheel's upstream preconditions. A patch wouldn't capture the shift.

---

## Why This Approach

### Compounding Evidence as the Through-Line

The three alternative framings considered:

| Approach | Thesis | Rejected Because |
|---|---|---|
| A: Infrastructure That Learns | Bottleneck is infrastructure, not intelligence | "Infrastructure" undersells the experience layer; too platform-builder-specific |
| B: Agency That Understands Itself | Self-knowledge precedes self-improvement | Anthropomorphic; risks sounding like vaporware |
| **C: Compounding Evidence** | **Trust earned through observable evidence** | **Selected — philosophically coherent, aligns with PHILOSOPHY.md, concrete** |

Approach C wins because:
1. **Already established vocabulary.** PHILOSOPHY.md's "Earned Authority" and "Receipts Close Loops" principles directly express this thesis. The vision should amplify the philosophy, not contradict it.
2. **Evidence is concrete.** Unlike "self-knowledge" or "learning infrastructure," evidence can be pointed at: gate pass rates, override proposals, model qualification scores, dispatch outcomes. Keeps the pitch grounded.
3. **Natural home for all new systems.** Interweave indexes evidence relationships. Ockham gates on evidence. Interop verifies evidence across boundaries. Interspect learns from evidence. FluxBench qualifies models with evidence. One thesis, five expressions.

### The Flywheel (Retained, Expanded)

The Interspect flywheel remains the central mechanism. What changes in v5.0: the flywheel's input stage is now explicitly multi-source rather than Interspect-only.

```
v4.0 flywheel:  Interspect → routing → cost reduction → more autonomy → more data → Interspect
                 (single source)

v5.0 flywheel:  Interweave (what's known) ─┐
                 Ockham (what's allowed) ───┤
                 Interop (what's verified) ──┼→ Interspect → routing → cost → autonomy → evidence
                 FluxBench (model quality) ──┘                                          ↓
                                              ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
```

The flywheel didn't stall — its upstream precondition stack expanded. v4.0 assumed routing was the chokepoint. Reality: you need ontology, governance, and integration *before* you can route adaptively.

---

## Key Decisions

### 1. Pitch: "Compounding Evidence, Earned Trust"

Replace the three-axis framing (autonomy/quality/efficiency) with the evidence thesis. The three axes become *outcomes* of the evidence loop, not the framing itself. They still appear in the metrics section but no longer headline the pitch.

### 2. Capability Mesh Replaces L0–L4 Ladder

The linear autonomy ladder (L0: Record → L4: Auto-ship) is replaced by a capability mesh where different subsystems mature independently:

| Subsystem | Owner | Capability | Current State | Evidence Signal |
|---|---|---|---|---|
| Routing | Interspect | Model selection per task | Static + complexity-aware | Gate pass rate, model cost ratio |
| Governance | Ockham | Policy enforcement | F1-F7 shipped | Authority ratchet events, INFORM signals |
| Ontology | Interweave | Cross-system entity tracking | F1-F3 shipped, F5 in progress | Query hit rate, confidence scores |
| Integration | Interop | External system sync | Phase 1 shipped | Conflict resolution rate, sync latency |
| Review | Interflux | Multi-agent quality | Reaction round + 49 agents | Finding precision, false positive rate |
| Measurement | Factory Substrate + FluxBench | Outcome attribution | ~80% implemented (3,515 LOC Go) | Attribution chain completeness |
| Discovery | Interject | Ambient research & scanning | Shipped, kernel-integrated | Promotion rate, source trust scores |
| Execution | Hassease + Codex | Multi-model code execution | Brainstorm/plan phase | Task completion rate, model utilization |
| Persistence | Intercore | Durable system of record | 8/10 epics shipped | Event integrity, query latency |
| Coordination | Interlock | Multi-agent file locking | Shipped | Conflict rate, reservation throughput |

Each subsystem earns trust independently. The *system's* overall autonomy is the *minimum* of its subsystem maturities — the weakest link constrains the whole. This naturally explains why "autonomy stalled" (one subsystem isn't there yet) without claiming regression.

### 3. Garden Salon to Horizons

Remove Garden Salon from "What's Next." Move to a new "Horizons" section alongside other future-facing commitments (domain-general north star, L4 auto-ship, cross-project federation). Rationale: P0 without discovery artifacts is a false priority signal. Garden Salon depends on Interop (data), Interweave (ontology), and Ockham (governance) reaching sufficient maturity. Making the dependency chain explicit is more honest than a stale priority label.

### 4. "What's Next" Reflects Actual April Work

Replace the 5 themes from v4.0 with what's actually in flight:

1. **Integration fabric** (Interop) — P0. Event-driven hub replacing fragmented sync.
2. **Factory governance** (Ockham) — P0. Intent→weights, algedonic signals, authority ratchet.
3. **Generative ontology** (Interweave) — P1. Finding-aid for entities across systems. Never owns data.
4. **Intelligence replatforming** (Auraken→Skaffen + Hassease) — P0. Go packages, multi-model execution.
5. **Model qualification** (FluxBench) — P1. Closed-loop discovery, 8 scores/model.
6. **Evidence pipeline closure** (Interspect Phase 2) — P1. The flywheel's missing link. Blocked on measurement hardening.

### 5. PHILOSOPHY.md Additions

Two new principles or expansions needed:

- **Sparse topology by default.** Research on the Zollman effect (fully-connected networks converge faster but on wrong answers) justifies shifting interflux from fully-connected reaction rounds to sparse/ring topologies. This is a philosophy-level claim about how agents should collaborate, not just an implementation detail.
- **Authority ratchet as mechanism.** Ockham's graduated authority model (evidence-gated promotions/demotions) generalizes the "Earned Authority" principle from a guideline into a concrete mechanism. PHILOSOPHY.md should acknowledge the mechanism, not just the principle.

### 6. MISSION.md Update

Current mission is 6 lines. Update to reflect:
- The evidence thesis ("compounding evidence is the path to earned trust" — already partially there as "compounding evidence")
- The expanded infrastructure scope (ontology, governance, integration, measurement — not just kernel/OS/profiler)
- Keep it short — mission is a paragraph, not a page

---

## Resolved Questions

1. **Measurement hardening**: Both paths, converge later. Factory Substrate (sylveste-5qv9, iv-ho3 successor) is in_progress with 3,515 lines Go, 518 tests, ~80% implemented — provides cross-subsystem evidence pipeline via CXDB. FluxBench handles model-specific measurement via AgMoDB. They converge when Interspect reads both. Vision names both as complementary evidence streams, not competing approaches.

2. **Sparse topology timing**: Vision principle, roadmap execution. PHILOSOPHY.md gets "sparse-by-default" as a principle referencing the Zollman effect research. The vision references it in design principles. Actual implementation (ring/small-world topology in interflux) is a roadmap item, not a v5.0 deliverable.

3. **Capability mesh granularity**: Expanded to match actual systems. Beyond the core 6 (Routing, Governance, Ontology, Integration, Review, Measurement), add Discovery (Interject), Execution (Hassease/Codex), Persistence (Intercore), Coordination (Interlock). Every major system gets a mesh cell. The mesh should reflect real systems, not a simplified abstraction — accuracy over communicability at the vision level.

4. **Khouri (scenario planning)**: Out of scope for v5.0. Defer to its own brainstorm. Vision stays focused on the evidence thesis and infrastructure.

5. **Two-brand operationalization**: Out of scope for v5.0. Leave as aspirational; enforcement mechanisms are premature with Garden Salon in Horizons.

6. **Intercom as execution plane**: Out of scope for v5.0. Defer to Intercom's own vision doc. Keep the Apps layer description as-is for now.
