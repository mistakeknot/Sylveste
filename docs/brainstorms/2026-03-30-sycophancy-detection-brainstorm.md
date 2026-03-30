---
bead: sylveste-rsj.6
title: "Brainstorm: Runtime sycophancy detection + adversarial agent parameter"
date: 2026-03-30
---

# Brainstorm: Runtime Sycophancy Detection

## Context

The reaction round (rsj.2, just shipped) gives agents explicit stances on peer findings: `agree`, `partially-agree`, `disagree`, `missed-this`. Combined with `independent_coverage: yes|partial|no`, this provides the raw signal for sycophancy detection. But the signal isn't computed, reported, or acted on yet.

## What Exists

1. **Reaction round** (Phase 2.5) — agents state their stance + independent coverage on peer findings
2. **Conductor score** in synthesis — convergent reactions boost confidence, divergent flag as contested
3. **Convergence gate** — skip reactions if >60% P0/P1 overlap
4. **Findings timeline** — peer-findings.jsonl with timestamps for discovery attribution
5. **Anti-anchoring prompt** — "reported claims" framing reduces sycophancy risk

## What's Missing (3 layers)

### Layer 1: Sycophancy Scoring (in synthesis)

Compute per-agent metrics from reaction data:
- `agreement_rate = (agree + partially_agree) / total_reactions` — high values (>0.8) flag conformism
- `independent_rate = count(independent_coverage=yes) / total_reactions` — low values flag anchoring
- `novel_finding_rate = count(reactive_additions) / total_reactions` — agents who find new things via peer context aren't sycophantic

Report these in synthesis output. Flag agents with `agreement_rate > 0.8 AND independent_rate < 0.3` as potential sycophants.

### Layer 2: Capitulation Detection (Free-MAD trajectory analysis)

Compare an agent's initial findings with their reaction stance:
- If agent found X in Phase 2 but said `missed-this` for a peer's similar finding → possible capitulation (they had it but didn't prioritize)
- If agent's initial finding at P1 and peer's same finding at P2, agent says `agree` with P2 → severity capitulation

This requires matching agent findings to peer findings by semantic similarity (fuzzy title match, same file:line).

### Layer 3: Lambda Parameter (adversarial temperament)

Per-agent `lambda` value (0.5–1.5) controlling challenge propensity:
- `lambda < 0.8`: conservative, tends to agree → useful for consensus confirmation
- `lambda = 1.0`: neutral baseline
- `lambda > 1.2`: adversarial, tends to challenge → useful for finding hidden issues

Lambda adjusts:
- Reaction prompt framing (high lambda agents get "look for flaws in peer reasoning")
- `max_reactions_per_agent` (high lambda gets more slots)
- Synthesis weighting (high lambda disagreements carry more signal)

**Nemeth's finding:** Assigned devil's advocacy reinforces initial views. Lambda must produce *genuine* adversarial reasoning — the agent actually believes its disagreement, not role-playing contrarianism. Implementation: lambda adjusts the agent's **system prompt** during initial Phase 2 review (not just reactions), biasing toward finding issues peers might miss.

## Scoping Decision

**For this bead:** Implement Layer 1 only (sycophancy scoring in synthesis). It's:
- Directly computable from reaction data that already exists
- Zero new infrastructure — extends synthesize-review.md
- Immediately useful — surfaces conformism signal in every reaction-enabled review
- Foundation for Layers 2-3 (scoring feeds into future lambda calibration)

Layers 2 and 3 are future beads (create as rsj.6.1, rsj.6.2 if needed).

## Design

### Where it goes

Extend `interverse/intersynth/agents/synthesize-review.md` Step 3.7 (reaction ingestion) with a new scoring step.

### Output

New section in `synthesis.md`:

```markdown
## Sycophancy Analysis

| Agent | Reactions | Agreement Rate | Independent Rate | Novel Findings | Flag |
|-------|-----------|---------------|-----------------|----------------|------|
| fd-safety | 3 | 0.67 | 1.00 | 0 | — |
| fd-quality | 2 | 1.00 | 0.00 | 0 | ⚠ High agreement, low independence |
```

Thresholds (configurable in reaction.yaml):
- `sycophancy_flag`: agreement_rate > 0.8 AND independent_rate < 0.3
- `contrarian_flag`: agreement_rate < 0.2 (almost never agrees — different problem)

### findings.json extension

```json
"sycophancy_analysis": {
  "agents": {
    "fd-quality": {
      "agreement_rate": 1.0,
      "independent_rate": 0.0,
      "novel_findings": 0,
      "flagged": true,
      "flag_type": "sycophancy"
    }
  },
  "overall_conformity": 0.75,
  "flagged_agents": ["fd-quality"]
}
```

### Config extension (reaction.yaml)

```yaml
sycophancy_detection:
  enabled: true
  agreement_threshold: 0.8
  independence_threshold: 0.3
  contrarian_threshold: 0.2
  report_section: true  # add Sycophancy Analysis section to synthesis.md
```
