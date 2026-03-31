---
artifact_type: brainstorm
bead: sylveste-rsj.7
date: 2026-03-31
stage: discover
---

# Brainstorm: Composable Discourse Protocols

**Date:** 2026-03-31
**Trigger:** Garden Salon brainstorm identified 5 formal discourse protocols but left Open Question #2 unresolved: "How do the 5 formal discourse protocols compose in practice?" This bead operationalizes the answer.
**Context:** Reaction round (rsj.2) shipped — agents can now see and respond to peer findings. This is the substrate the protocols operate on.

## The Five Protocols

Each protocol controls a different layer of multi-agent discourse:

| # | Protocol | Layer | Controls | Source |
|---|----------|-------|----------|--------|
| 1 | **Pressing Cycle** | Macro structure | Shared constraints that mutate with each accepted contribution; referent-drift mechanism | Jazz improvisation theory |
| 2 | **Conduction Protocol** | Turn structure | 7 typed structural signals: sustain/develop/superimpose/literal/enter/exit/cut | Butch Morris |
| 3 | **Lorenzen Dialogue Game** | Generation rules | Challenge/defense turn structure — formalized dialogue games | Paul Lorenzen |
| 4 | **Yes-And with Degeneration Guards** | Contribution operator | Theatrical improv acceptance with safeguards against runaway premise accumulation | Keith Johnstone / Del Close |
| 5 | **Sawyer Flow Envelope** | Health monitor | Measurable flow state preservation: participation Gini < 0.3, novelty_rate > ε, response_relevance > 0.7 | R. Keith Sawyer |

## Composition Model: Five Layers, Bottom-Up

The protocols compose as a **stack**, not a pipeline. Each layer constrains the layer above it:

```
┌─────────────────────────────────────────────┐
│ 5. Sawyer Flow Envelope  (health monitor)   │  ← Continuous. Vetoes/throttles all layers.
├─────────────────────────────────────────────┤
│ 4. Yes-And + Guards  (contribution operator)│  ← Per-contribution. Shapes each response.
├─────────────────────────────────────────────┤
│ 3. Lorenzen Dialogue  (generation rules)    │  ← Per-turn. Validates move legality.
├─────────────────────────────────────────────┤
│ 2. Conduction Protocol  (turn structure)    │  ← Per-round. Selects who speaks and how.
├─────────────────────────────────────────────┤
│ 1. Pressing Cycle  (macro structure)        │  ← Per-session. Evolves shared constraints.
└─────────────────────────────────────────────┘
```

**Reading direction:** Layer 1 sets the session-level constraint space. Layer 2 selects agents and assigns structural roles per round. Layer 3 validates each agent's move as legal within the dialogue game. Layer 4 shapes the content of each contribution. Layer 5 monitors all of the above and vetoes/throttles when health degrades.

## How Each Protocol Maps to Interflux

### 1. Pressing Cycle → Session-Level Constraint Evolution

**What it does:** A "press" is a shared constraint (question, assumption, frame) that all agents must engage with. After each round, accepted contributions mutate the press — the referent drifts.

**Interflux mapping:** The `reaction-prompt.md` template currently fixes the frame. With Pressing, the frame would evolve:
- Round 1: Original review/research prompt = initial press
- Round 2 (reaction): Synthesis of Round 1 findings = mutated press
- Round N: Each synthesis produces a new press incorporating drift

**Implementation surface:** `config/flux-drive/discourse/pressing.yaml` + modification to `phases/reaction.md` to inject evolved press into reaction prompts.

**Parameters:**
- `d_min` — minimum referent distance per round (prevents stagnation)
- `d_max` — maximum referent distance per round (prevents runaway divergence)
- `press_history_depth` — how many prior presses agents can see (default: 2)

**Architectural question (from garden-salon brainstorm Q3):** Press evolution is mechanism (domain-agnostic), but d_min/d_max are policy (domain-specific). Resolution: mechanism in Intercore config schema, defaults in interflux, overrides per domain profile.

### 2. Conduction Protocol → Agent Selection & Role Assignment

**What it does:** Morris's conduction uses 7 typed signals to orchestrate an ensemble without dictating content:
- **sustain** — continue current line of inquiry
- **develop** — extend/deepen a finding
- **superimpose** — layer a new perspective over existing
- **literal** — reproduce/confirm exactly
- **enter** — bring in a new agent or topic
- **exit** — remove an agent or close a topic
- **cut** — sharp transition, reset

**Interflux mapping:** These map to Phase 2 dispatch decisions and reaction round orchestration:
- Triage scoring already does implicit conduction (score = relevance to topic)
- Explicit conduction would let the orchestrator assign roles: "Agent X: develop finding F-003. Agent Y: superimpose your domain perspective on finding F-007."
- The `enter`/`exit` signals map to the dynamic agent expansion the launch phase already supports

**Implementation surface:** Extend `phases/reaction.md` Step 2.5.3 (prompt building) to include a conduction signal per agent. Add `config/flux-drive/discourse/conduction.yaml` for signal vocabulary.

### 3. Lorenzen Dialogue Game → Move Validation

**What it does:** Formal dialogue game where each move must be a valid attack or defense. An attack challenges a claim; a defense provides evidence. Invalid moves (non-sequiturs, circular reasoning) are rejected.

**Interflux mapping:** The reaction round currently allows any stance (agree/disagree/missed-this). Lorenzen adds move legality:
- A "disagree" must name the specific claim being attacked and provide counter-evidence
- An "agree" that doesn't add evidence is a valid but low-value move (literal in conduction terms)
- A "missed-this" is an uncontested new assertion — becomes attackable in the next round

**Implementation surface:** Add move validation to the reaction prompt output contract. The synthesis agent can score moves by legality (valid attack, valid defense, invalid/non-sequitur). Findings with more valid attack-defense exchanges have higher confidence.

**Key insight:** Lorenzen doesn't need a new phase — it refines the EXISTING reaction phase's output contract.

### 4. Yes-And with Degeneration Guards → Contribution Shaping

**What it does:** Each contribution must accept ("yes") the prior contribution's frame and extend ("and") it. Guards prevent:
- **Premise accumulation** — accepting too many unvalidated premises
- **Sycophantic convergence** — "yes-and" degenerating into agreement without challenge
- **Scope drift** — extensions wandering away from the original prompt

**Interflux mapping:** This is the per-contribution operator that shapes how agents write their findings:
- Currently agents write free-form findings with severity ratings
- Yes-And would require each finding to reference what it builds on (provenance chain)
- Guards map to existing mechanisms: CONSENSAGENT sycophancy detection (rsj.6 shipped), QDAIF diversity archive (rsj.5 shipped)

**Implementation surface:** Modify the agent prompt template to include "build-on" references. Add guard thresholds to `config/flux-drive/discourse/yes-and.yaml`:
- `max_unvalidated_premises` — cap on accepted-but-untested claims
- `min_challenge_rate` — minimum fraction of findings that challenge rather than confirm
- `scope_drift_threshold` — maximum semantic distance from original prompt

### 5. Sawyer Flow Envelope → Health Monitor

**What it does:** Continuous monitoring of discourse health with measurable thresholds:
- **Participation Gini < 0.3** — no single agent dominates
- **novelty_rate > ε** — fresh thinking continues entering
- **response_relevance > 0.7** — contributions stay on-topic

**Interflux mapping:** This is a cross-cutting monitor that runs alongside all phases:
- Participation Gini: computed from findings counts per agent (already available in synthesis)
- Novelty rate: fraction of findings not duplicated by any other agent (dedup already runs in synthesis)
- Response relevance: semantic similarity to original prompt (would need embedding or heuristic)

**Implementation surface:** Add `scripts/discourse-health.sh` or a health-check step in synthesis. Output a `discourse-health.json` alongside the synthesis:
```json
{
  "participation_gini": 0.24,
  "novelty_rate": 0.41,
  "response_relevance": 0.83,
  "flow_state": "healthy",
  "warnings": []
}
```

Sawyer is the only protocol that doesn't need the reaction round — it operates on Phase 2 output directly.

## Composition Rules

### Which protocols are always-on vs. opt-in?

| Protocol | Default | Rationale |
|----------|---------|-----------|
| Sawyer Flow Envelope | **Always-on** | Pure monitoring, no behavior change, no cost |
| Lorenzen Dialogue | **Always-on** | Refines existing reaction output contract, no extra dispatch |
| Yes-And Guards | **On with reaction** | Guards only meaningful when agents build on each other |
| Conduction | **Opt-in** | Requires orchestrator intelligence to assign signals meaningfully |
| Pressing Cycle | **Opt-in** | Multi-round sessions only; single-round reviews don't benefit |

### Interaction patterns

1. **Pressing + Conduction:** Pressing evolves the constraint; Conduction assigns who engages with which aspect of the evolved constraint. They don't conflict — Pressing is what changes, Conduction is who responds how.

2. **Lorenzen + Yes-And:** Potential tension. Lorenzen allows pure attacks; Yes-And requires acceptance before extension. Resolution: Yes-And operates on the session frame (accept the review exists, extend it), while Lorenzen operates on individual claims within findings (challenge specific assertions).

3. **Sawyer monitors everything:** Sawyer is the only protocol that can veto other protocols. If participation Gini > 0.3, Conduction should reassign roles. If novelty_rate < ε, Pressing should increase d_min. Sawyer's vetoes are soft (warnings in health output) — the orchestrator decides whether to act.

4. **Convergence gate interaction:** The existing convergence gate (overlap_ratio > 0.6 → skip reaction) is a proto-Sawyer mechanism. When Sawyer is active, the convergence gate becomes one of its health checks rather than a separate mechanism.

## Implementation Strategy

### Phase 1: Sawyer + Lorenzen (always-on, zero new dispatch cost)

1. Add discourse health computation to synthesis phase
2. Tighten reaction output contract with Lorenzen move types
3. Emit `discourse-health.json` alongside synthesis output
4. No new files in `phases/` — modifications to existing reaction and synthesis phases

### Phase 2: Yes-And Guards (enabled with reaction round)

1. Add provenance/build-on references to agent prompt templates
2. Implement guard thresholds in `discourse/yes-and.yaml`
3. Synthesis reports guard violations (premise count, challenge rate, scope drift)

### Phase 3: Conduction + Pressing (opt-in, multi-round)

1. Implement Conduction signal vocabulary and role assignment in reaction dispatch
2. Implement press evolution across rounds (requires multi-round reaction support)
3. These are the most impactful but highest-effort protocols

### Complexity ordering vs. value ordering

- **Highest value, lowest effort:** Sawyer (monitoring) + Lorenzen (output contract)
- **High value, medium effort:** Yes-And guards (prompt modification + guard computation)
- **Highest value, highest effort:** Conduction + Pressing (new orchestration logic, multi-round)

This matches the phased rollout: always-on monitors first, then contribution shaping, then full orchestration.

## Open Questions

1. **Multi-round support:** Pressing and Conduction assume multiple reaction rounds. Currently interflux does one round. Should we extend to N rounds? The convergence gate already handles "when to stop" — it could also decide "need another round."

2. **Where does Sawyer veto go?** Sawyer monitoring is pure observation. But should Sawyer be able to force a Conduction reassignment or increase d_min? This turns a monitor into a controller — Garden Salon brainstorm specifically warned about this distinction.

3. **Discourse configuration per domain:** Should domain profiles (e.g., `domains/claude-plugin.md`) include discourse configuration? A game-design review might benefit from more Pressing (creative drift), while a safety review needs strict Lorenzen (formal argumentation).

4. **Testing strategy:** How do you test discourse protocol composition? Unit tests on health metrics are straightforward. But testing "does Pressing + Conduction produce better outcomes than either alone?" requires evaluation infrastructure (rsj.3.14 BALROG baseline).

## Relationship to Other Beads

- **rsj.2 (reaction round):** Shipped. Provides the substrate for all protocols except Sawyer.
- **rsj.5 (QDAIF diversity archive):** Shipped. Sawyer's novelty_rate is related to QDAIF's diversity measure.
- **rsj.6 (sycophancy detection):** Shipped. Yes-And guards' min_challenge_rate overlaps with CONSENSAGENT.
- **rsj.8 (stigmergic substrate):** Open. The document-as-coordination-signal model. Complementary — protocols shape the discourse, stigmergy shapes the shared workspace.
- **rsj.9 (discourse fixative):** Open. The "always-on coherence agent" (sandalwood function). This IS Sawyer Flow Envelope + a lightweight always-on agent.
- **rsj.10 (stemma hallucination tracing):** Shipped. Provenance tracking that Yes-And's build-on references depend on.
- **rsj.11 (sparse communication topology):** Open. Conduction's enter/exit signals are the mechanism for sparse topology.
- **rsj.12 (hearsay rule):** Shipped. Lorenzen's evidence requirements align with hearsay provenance enforcement.
