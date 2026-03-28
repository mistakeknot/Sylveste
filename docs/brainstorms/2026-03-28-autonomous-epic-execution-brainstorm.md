---
artifact_type: brainstorm
bead: sylveste-80y.49
stage: discover
---

# Brainstorm: Autonomous Epic Execution

**Date:** 2026-03-28
**Bead:** sylveste-80y.49
**Method:** 10-agent parallel analysis — 5 close-domain (CI/CD, SAFe, SAE robotics, lean manufacturing, military C2) + 5 maximally distant (haute cuisine, winemaking, cathedral construction, epidemiology, textile programming).

## What We're Building

A composition layer that connects existing Sylveste subsystems (Mycroft fleet dispatch, Discovery pipeline, Thematic Lanes, Interspect learning loop, Self-dispatch, Skaffen) into end-to-end autonomous epic execution:

```
Human: "I want X" (theme + success criteria)
  → RESEARCH (Discovery + autoresearch)
  → DESIGN (auto-brainstorm → strategy → plan)
  → DECOMPOSE (plan → epic with child beads)
  → EXECUTE (Mycroft dispatch → self-dispatch → sprint)
  → SHIP (L3/L4 confidence-gated merge)
  → COMPOUND (Interspect feeds back into next epic)
  → Human: validates epic outcome
```

## Cross-Agent Convergence: What All 10 Agree On

### C1: Intent Decays Through Every Delegation Layer (6 agents)

The most consistent finding across both fleets. Strategic intent is a write-once artifact that loses fidelity at every hop:

| Sprint | Intent Remaining | Source Agents |
|--------|-----------------|---------------|
| Sprint 0 | 100% | (all agree) |
| Sprint 1 | ~70% | fd-scaled-agile, fd-mission-command |
| Sprint 2 | ~40% | fd-mission-command, fd-scaled-agile |
| Sprint 3 | ~20% | fd-mission-command ("system optimizes throughput on a plan whose premises may be stale") |

The fix converges from multiple domains:
- **Military C2**: Lane-level `strategic_intent` field (the Schwerpunkt in written form)
- **Cathedral**: Lodgebook as cold-start spec with generative rules, not exhaustive instructions
- **Textile**: Threading draft as type system — plan specifies possible structures, not steps
- **Cuisine**: The plate spec is the interface contract; stations don't need the chef's full vision
- **SAFe**: Every bead needs `context_ref` linking to root ancestor's brainstorm/PRD

### C2: The System Optimizes for Agent Utilization, Not Flow (4 agents)

- **Lean**: "The system treats human attention as the bottleneck but optimizes for agent utilization rather than human throughput"
- **CI/CD**: Self-dispatch keeps producing when review queue is full — no backpressure
- **Cuisine**: "In the weeds" protocol — reduce parallelism to recover, don't pile on more work
- **Wine**: The négociant model — thin orchestration + strong quality gates over command-and-control

### C3: Silent Failure Is the P0 Risk, Not Noisy Failure (5 agents)

- **CI/CD**: "The biggest 2am risk is a sprint that ships logically wrong code that passes all gates and compounds bad learnings"
- **SAE**: "The system behaves at L5 but has only validated L3 failure handling"
- **Epidemiology**: "Asymptomatic transmission" — defects present but not manifesting until later integration
- **Lean**: No quality andon cord — circuit breaker for infra failures but not quality failures
- **Wine**: "The corked bottle problem — TCA contamination undetectable until uncorking"

### C4: Every Intermediate State Must Be Independently Stable (3 agents)

- **Cathedral**: "Beauvais anti-pattern" — never depend on the next phase for stability. Each completed phase was liturgically usable.
- **Wine**: Barrel vs tank — classify tasks as transformative (commit fully) or preservative (stay flexible)
- **Textile**: Forward-only recovery — don't re-execute completed beads, splice from failure point

## Key Findings by Domain

### Close Domain Fleet

**CI/CD (fd-cicd-pipeline-autonomy)**
- Risk matrix: L0-L1 safe (gate rejection). L3 HIGH (no post-merge canary, Interspect records bad sprints as success). L4-L5 CRITICAL (policy changes have no rollback, can disable monitoring).
- Top recs: Post-merge canary gate, Interspect evidence quarantine (48h), evidence retraction, fleet-level circuit breaker.

**SAFe (fd-scaled-agile-epic-integrity)**
- No epic-level "definition of done" beyond "all beads closed" — system can assert completion but not outcome satisfaction.
- Theme drift is higher risk than scope creep — system stays in right category but may miss the specific problem.
- Decomposition quality is not a calibrated parameter in the Interspect loop.

**SAE Robotics (fd-autonomy-level-certification)**
- Autonomy cliff at Capability L2→L3 and Delegation DL3→DL4.
- Compound autonomy: Mycroft T2 dispatching to L3-capable agent = higher compound autonomy than either alone.
- No formal Operational Design Domains. Human attentiveness assumed, never verified (monitoring paradox).

**Lean (fd-lean-production-flow)**
- Full value stream map. No global WIP limit. No backpressure from review queue. Hidden WIP in decomposition (theme spawning 15 beads = committed future work invisible to accounting).
- Core fix: self-dispatch scoring should include review-queue-depth as negative factor.

**Mission Command (fd-mission-command-authority)**
- "The system grants more autonomy while holding intent richness constant — this violates Auftragstaktik."
- Five specific gaps: lane `strategic_intent`, briefing includes intent, `strategic_contradiction` escalation type, cross-bead visibility, strategic alignment gate.

### Distant Domain Fleet

**Haute Cuisine (fd-haute-cuisine-brigade)**
- Mise en place as pre-computation with spoilage boundary (anything depending on runtime state is deferred).
- The pass as assertion checkpoint, not review (verify assembly, not technique).
- "In the weeds" protocol: reduce parallelism, honest estimates, 86 features (scope reduction > quality degradation).

**Winemaking (fd-wine-terroir-assemblage)**
- Late-binding assemblage: defer integration until workstreams reveal true character.
- Barrel vs tank: classify tasks as transformative (irreversible, time-locked) or preservative (interruptible).
- Malolactic fermentation: some dependencies are observable but non-commandable. Never hard-code duration estimates.

**Cathedral Construction (fd-medieval-cathedral-construction)**
- Lodgebook: encode proportional rules (generative grammars), not absolute measurements. Dense, not verbose.
- Guild autonomy at structural interfaces: glaziers and masons never needed to understand each other.
- "The agents are mortal; the lodge is immortal." Repository > session transcripts.

**Epidemiology (fd-epidemiological-contact-tracing)**
- Rt estimation: rework reproduction number. Rt > 1.0 for 2 batches = halt and trace. Rt > 2.0 = immediate intervention.
- Backward tracing 2-3x more efficient than forward (transmission is overdispersed).
- Superspreader detection (k parameter): when k < 0.5, ~20% of decisions cause ~80% of rework.
- Ring vs mass intervention: targeted rollback first, escalate to full re-review if ring leaks.

**Textile Programming (fd-jacquard-textile-programming)**
- Warp/weft two-level: plan-time decisions (structural, immutable) vs bead-time (local, adaptive).
- Threading draft as type system: plan specifies possible structures, not steps.
- Temple as continuous invariant enforcer running alongside execution, not just at gates.
- Jacquard card chain: plan as inspectable, portable, machine-independent artifact.

## Open Questions

1. **How to implement the `strategic_intent` field?** Natural language? Structured acceptance criteria? LLM-as-judge evaluation at sprint boundaries?
2. **What is the right Interspect evidence quarantine period?** 48h (CI/CD agent) or longer?
3. **How to detect compound autonomy?** Mycroft T2 + agent L3 = unaddressed risk. Need a compound autonomy calculator.
4. **Where does the "temple" (continuous invariant checker) run?** As a hook? As a background agent? As a kernel primitive?
5. **What is the Rt threshold for the specific Sylveste context?** Epidemiology suggests Rt > 1.0, but calibration needed.

## Prioritized Actions

### P0 (Do First)
1. **Lane-level `strategic_intent` field** + briefing includes it at dispatch — fixes the intent decay problem that 6 agents converge on
2. **Post-merge canary gate** — highest-value addition for silent failure detection
3. **Review queue backpressure in self-dispatch scoring** — fixes the flow inversion the lean agent identified
4. **Interspect evidence quarantine (48h)** — prevents bad sprints from corrupting the learning baseline

### P1 (Do Next)
5. **`strategic_contradiction` escalation type** — distinct from task failure, triggers lane pause
6. **Epic-level "definition of done"** (outcome-based, not completion-based)
7. **Provenance vectors on all agent outputs** (enables stemma-based backward tracing)
8. **Compound autonomy guard** (Mycroft tier × agent capability level check)
9. **Decomposition quality as calibrated Interspect parameter**
10. **Temple-style continuous invariant checker** alongside bead execution

### P2 (Strategic)
11. Rt estimation for rework cascade detection
12. Superspreader analysis (k parameter) for architectural decision review
13. Formal Operational Design Domains per delegation level
14. Human attentiveness verification (monitoring paradox)
15. Cross-bead visibility within a lane (strategic finding broadcast)

## Supporting Analysis

Full agent reports from both fleets:
- Close domain: fd-cicd-pipeline-autonomy, fd-scaled-agile-epic-integrity, fd-autonomy-level-certification, fd-lean-production-flow, fd-mission-command-authority
- Distant domain: fd-haute-cuisine-brigade, fd-wine-terroir-assemblage, fd-medieval-cathedral-construction, fd-epidemiological-contact-tracing, fd-jacquard-textile-programming
