---
artifact_type: brainstorm
bead: sylveste-rsj.9
date: 2026-03-31
stage: discover
---

# Brainstorm: Discourse Fixative — Always-On Coherence Agent

**Date:** 2026-03-31
**Trigger:** rsj.7 shipped Sawyer Flow Envelope (health monitoring) but the health signals have no consumer — they're passive observations. The discourse fixative is the agent that acts on degraded health.
**Source:** fd-perfumery-accord research — the "sandalwood function" in perfumery: a fixative base note that retards evaporation (convergence), provides referential anchoring, and bridges volatile top notes.

## The Perfumery Insight

In perfumery, a fixative isn't a fragrance — it's a substrate that slows evaporation of volatile compounds, making the overall composition last longer and develop more richly. Sandalwood doesn't dominate; it anchors. It doesn't generate new notes; it preserves the conditions under which top and heart notes can express themselves.

Mapped to multi-agent discourse:
- **Volatile top notes** = initial agent findings (high energy, fast decay, may be superficial)
- **Heart notes** = substantive analysis (the core of the review)
- **Base notes** = persistent context, shared constraints, referential anchors
- **The fixative** = a coherence agent that doesn't produce findings itself, but preserves the conditions for productive discourse

## What the Fixative Does

The discourse fixative is NOT another review agent. It doesn't produce findings. Instead it:

1. **Retards premature convergence.** When agents agree too quickly (Sawyer: high conformity, low novelty), the fixative injects divergence prompts — questions that challenge the emerging consensus, surface unstated assumptions, or point to unexplored angles.

2. **Provides referential anchoring.** When discourse drifts (Sawyer: low response relevance), the fixative re-anchors agents to the original review question, key constraints, or prior findings from the brainstorm/PRD.

3. **Bridges disparate contributions.** When agent findings are siloed (Sawyer: high participation Gini, findings don't cross-reference), the fixative identifies potential connections between isolated findings and prompts agents to consider them.

4. **Monitors for discourse collapse.** AMOC tipping monitor (from oceanography research): rising variance + increasing autocorrelation + declining novelty ratio = early warning that discourse is about to collapse into echo chamber or noise.

## Where It Fits in the Pipeline

```
Phase 1: Triage → Phase 2: Launch → Phase 2.5: Reaction → Phase 3: Synthesize
                                         ↑
                                    FIXATIVE
                                    (reads Phase 2 output,
                                     injects into reaction prompts)
```

The fixative operates between Phase 2 (agent findings) and Phase 2.5 (reaction round). It reads Sawyer health metrics from Phase 2 output and, if health is degraded, modifies the reaction prompts to include corrective signals.

**Key constraint:** The fixative NEVER adds its own findings. It shapes the discourse environment, not the discourse content. This is the sandalwood principle — the fixative should be invisible when the discourse is healthy.

## Implementation Options

### Option A: Pre-Reaction Prompt Injection (Recommended)

The fixative runs as a lightweight step between Phase 2 completion and Phase 2.5 reaction dispatch. It:
1. Reads Sawyer health metrics (computed from Phase 2 agent outputs)
2. If healthy: no-op, proceed to reaction round unchanged
3. If degraded/unhealthy: adds corrective context to reaction prompts

Corrective injections (appended to reaction-prompt.md template slots):
- **High conformity (Gini > 0.3):** "Note: Agent participation is imbalanced. If you have a perspective that differs from the dominant viewpoint, prioritize expressing it over confirming existing findings."
- **Low novelty (rate < ε):** "Note: Most findings overlap. Focus your reaction on what's MISSING from peer findings rather than confirming what they found."
- **Low relevance (< 0.7):** "Note: Some findings lack specific evidence. Anchor your reactions to concrete file:line references."
- **Collapse warning (variance↑ + autocorrelation↑ + novelty↓):** "Note: Discourse quality is declining. Before reacting, re-read the original review prompt and ensure your response addresses it directly."

**Cost:** Zero additional agent dispatches. Only adds ~50-100 tokens to reaction prompts when health is degraded.

### Option B: Separate Fixative Agent

A dedicated agent that runs in parallel with Phase 2 agents, producing a `fixative-context.md` that the reaction round reads. More powerful but adds a dispatch + wait cycle.

### Option C: Post-Synthesis Fixative

After synthesis, if Sawyer health is degraded, trigger a second round with corrective prompts. Most powerful but doubles the review cost.

## Decision: Option A

Option A is the right choice for Phase 1:
- Zero additional cost when discourse is healthy (no-op)
- Minimal cost when degraded (~50-100 tokens per agent prompt)
- No new agent type, dispatch, or wait cycle
- The fixative is literally invisible when not needed — the sandalwood principle
- It piggybacks on the existing reaction round infrastructure (rsj.2)
- It consumes the Sawyer health metrics we just shipped (rsj.7)

Options B and C are future work if prompt injection proves insufficient.

## Detailed Design

### Health Assessment

Before the reaction round dispatches, compute a quick health snapshot from Phase 2 outputs. This mirrors what discourse-health.sh does but runs inline, before synthesis:

```python
# Simplified pre-synthesis health check (inline, not full discourse-health.sh)
agent_finding_counts = count_findings_per_agent(phase2_outputs)
gini = compute_gini(agent_finding_counts)
overlap = count_overlapping_findings(phase2_outputs)  # existing convergence gate logic
novelty_estimate = 1 - (overlap / total_findings)  # rough proxy before full dedup
```

Note: This is a rough pre-synthesis estimate. The authoritative Sawyer metrics live in findings.json (computed by synthesis). The fixative uses approximate metrics because it runs before synthesis.

### Fixative Injection Protocol

```yaml
# config/flux-drive/discourse-fixative.yaml
fixative:
  enabled: true
  # Trigger thresholds (same as Sawyer degraded state)
  triggers:
    participation_gini_above: 0.3
    novelty_estimate_below: 0.1
    relevance_estimate_below: 0.5
  # Maximum injection size (tokens)
  max_injection_tokens: 150
  # Injections are additive — multiple can fire simultaneously
  injections:
    imbalance: "Your perspectives differ in depth. Agents with fewer findings: focus on what you uniquely see. Agents with more findings: prioritize your most distinctive insight over comprehensive coverage."
    convergence: "Most agents found similar issues. Your reaction should focus on what is MISSING rather than confirming what peers found. What didn't anyone check?"
    drift: "Some findings lack specific evidence. Anchor your reactions to concrete file:line references from the codebase."
    collapse: "Discourse quality indicators suggest echo-chamber risk. Before reacting, re-read the original review prompt. Challenge at least one peer finding you initially agreed with."
```

### Integration with Reaction Phase

Modify `phases/reaction.md` Step 2.5.3 (Build Per-Agent Reaction Prompts):

After building the standard reaction prompt, check fixative health:
1. Read Phase 2 agent output files (already done for the convergence gate)
2. Compute approximate health metrics (gini, novelty estimate)
3. If any metric triggers the fixative, append the corresponding injection text to `{fixative_context}` template slot
4. If no triggers fire, `{fixative_context}` is empty — reaction prompts are unchanged

### New Template Slot

Add `{fixative_context}` to reaction-prompt.md after the Instructions section:

```markdown
{fixative_context}
```

When empty, this adds nothing. When populated, it adds 1-3 contextual notes that nudge agents toward healthier discourse patterns.

## Relationship to Other Beads

- **rsj.7 (composable protocols):** Just shipped. Fixative consumes Sawyer metrics and operates within the Lorenzen move framework.
- **rsj.2 (reaction round):** Shipped. Fixative piggybacks on the reaction round infrastructure.
- **rsj.8 (stigmergic substrate):** Open. Stigmergy is the document-as-coordination-signal model. The fixative's prompt injections are a lightweight form of stigmergy — environmental signals that shape behavior without direct communication.
- **rsj.11 (sparse communication):** Open. If the fixative detects imbalance, a future version could use Conduction signals to redistribute attention.

## Open Questions

1. **Should the fixative log its interventions?** If it injects corrective context, should this appear in the synthesis report? Recommendation: yes, as a one-line note: "Fixative active: imbalance, convergence (2 injections)."

2. **Adaptive thresholds?** Should the fixative thresholds evolve based on Interspect feedback? e.g., if reviews with fixative injections consistently produce better outcomes, lower the trigger thresholds. This is Phase 2.

3. **Per-agent tailoring?** Should the fixative inject different messages to different agents? e.g., tell the dominant agent to be more concise, tell the quiet agent to be more assertive. This risks manipulative framing — keep injections uniform for now.
