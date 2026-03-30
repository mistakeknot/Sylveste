---
bead: sylveste-rsj.5
title: "Brainstorm: Synthesis as diversity archive (QDAIF)"
date: 2026-03-30
---

# Brainstorm: QDAIF-Inspired Diversity Archive in Synthesis

## Problem

Intersynth currently converges N agent reports into one merged findings list. This loses:
1. **Unique framings** — fd-safety and fd-architecture may both find the same auth issue, but fd-safety frames it as "credential exposure" while fd-architecture frames it as "trust boundary violation." The merged version picks one.
2. **Agent-specific insight chains** — an agent may connect 3 findings into a narrative ("A causes B which enables C"). Merging breaks the narrative into disconnected items.
3. **Minority perspectives** — if 4/5 agents agree on severity, the dissenting view is preserved as a `severity_conflict` annotation but not as a first-class alternative perspective.

## What QDAIF Suggests

QDAIF (Quality-Diversity through AI Feedback, ICLR 2024): instead of converging to one "best" output, maintain a portfolio of high-quality diverse outputs. Each output occupies a different niche in the quality-diversity space. Consumers choose which perspective best fits their context.

Applied to synthesis: preserve the top N distinct agent perspectives alongside the merged verdict. Each perspective is a compact summary from one agent's viewpoint.

## What Already Exists

Intersynth already does partial QDAIF:
- **Rule 5** preserves conflicting recommendations (both fixes kept, keyed by agent)
- **severity_conflict** records all severity positions
- **Contested Findings** section (from reaction round) highlights disagreements
- **Sycophancy Analysis** flags agents that may be conforming

What's missing: a **Perspectives section** that preserves each agent's unique viewpoint as a coherent mini-narrative, not just conflict annotations on merged findings.

## Scoped Design

### Add "Diverse Perspectives" section to synthesis.md

After the merged Findings section, add a new section that preserves distinct agent viewpoints:

```markdown
### Diverse Perspectives

**fd-safety** (trust boundary focus):
> Auth middleware rewrite is fundamentally a trust boundary redesign. The three findings
> (SAFE-01, SAFE-02, SAFE-03) form a chain: session tokens stored in cookies (SAFE-01)
> enables CSRF without SameSite (SAFE-02) which exposes the admin panel (SAFE-03).
> Fix the root cause (SAFE-01) and the others resolve.

**fd-architecture** (coupling focus):
> The auth module has grown to couple session management, route protection, and user
> lookup into a single middleware. ARCH-01 and ARCH-03 both stem from this coupling.
> Suggest: split into three modules before fixing individual issues.
```

Rules:
- Only include perspectives that **differ materially** from the merged findings
- Skip agents whose perspective is fully captured by the merged version (no unique framing)
- Each perspective is 2-4 sentences max — a mini-narrative, not a full report
- Use the agent's own words from their Findings Index + Summary section

### Add "perspectives" to findings.json

```json
"perspectives": [
  {
    "agent": "fd-safety",
    "domain": "trust boundaries",
    "narrative": "Auth middleware rewrite is fundamentally...",
    "key_findings": ["SAFE-01", "SAFE-02", "SAFE-03"],
    "unique_framing": true,
    "quality_score": 0.85
  }
]
```

The `quality_score` is derived from:
- Convergence of the agent's findings (how many were confirmed by others)
- Reaction stance (were the agent's findings contested or confirmed?)
- Independence (from sycophancy scoring — high independence = more valuable perspective)

### Where it goes

New Step 6.5 in synthesize-review.md (between Deduplicate and Categorize). This step:
1. For each agent with NEEDS_ATTENTION verdict, extract their Summary + narrative
2. Compare narratives for distinctness (do they frame things differently?)
3. Keep top 3 most distinct perspectives
4. Compute quality_score from convergence + reaction + independence data

### What NOT to do

- Don't replace the merged findings — the merged list is still the primary output
- Don't keep all perspectives — only materially distinct ones (2-4 typically)
- Don't make this blocking — perspectives are informational, not gate-affecting
