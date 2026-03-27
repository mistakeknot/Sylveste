---
artifact_type: cuj
journey: interject-discovery
actor: regular user (developer staying current in their domain)
criticality: p3
bead: Sylveste-2c7
---

# Interject Ambient Discovery

## Why This Journey Matters

The tools, techniques, and research that could improve your project are published every day — on arXiv, Hacker News, GitHub, Anthropic's docs, and across the web. Missing a relevant paper or a new library that solves your exact problem means reinventing the wheel. But manually scanning these sources daily is unsustainable.

Interject turns ambient scanning into a structured pipeline. It scans sources, scores relevance against your project's interest profile, creates beads with briefings for high-scoring discoveries, and learns from your feedback to improve future recommendations. The closed-loop model means Interject gets better at finding what matters to you specifically — not just what's trending generally.

## The Journey

The developer starts with `/interject:profile` to see and tune their interest profile. Interject has inferred interests from the project's beads, brainstorms, and code — "autonomous agents", "fleet coordination", "TUI frameworks", "Go concurrency patterns". The developer adjusts: add "sqlite optimization", remove "blockchain" (not relevant).

They run a scan: `/interject:scan`. Interject's source adapters query in parallel — arXiv for recent papers, Hacker News for discussions, GitHub for trending repos and new releases, Anthropic docs for API changes, Exa for web-wide semantic search. Each result is scored against the interest profile using the recommendation engine.

Results arrive in the inbox: `/interject:inbox`. Discoveries are tiered:
- **High relevance** — auto-creates a bead with a brainstorm doc. "New paper on multi-agent coordination with OODARC-like phases" → bead created, brainstorm at `docs/brainstorms/`.
- **Medium relevance** — creates a briefing. "New Go TUI library claims 2x rendering speed" → briefing visible in inbox.
- **Low relevance** — digest entry only. Scanned, scored low, available if the developer wants to browse.

The developer reviews the inbox. For each discovery: **promote** (create a bead if not auto-created, investigate further), **dismiss** (not relevant, feeds negative signal to the model), or **skip** (maybe later). Promotes and dismisses close the feedback loop — the recommendation engine adjusts weights.

For deep dives: `/interject:discover "sqlite WAL mode performance"` runs a targeted search across all sources on a specific topic, returning a curated reading list with relevance scores.

Over weeks, Interject's recommendations sharpen. The developer gets fewer false positives (things they dismiss) and more true positives (things they promote). The conversion rate — what percentage of discoveries become actual work items — is the key health metric.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Scan completes across all sources in under 3 minutes | measurable | Wall time from `/scan` to results ≤ 180s |
| Interest profile reflects actual project focus | qualitative | Developer agrees with ≥80% of inferred interests |
| High-relevance discoveries include at least one actionable item per week | qualitative | Weekly promote rate ≥ 1 |
| Feedback improves future relevance scores | measurable | Dismiss rate decreases over 4+ weeks of use |
| Auto-created beads have accurate titles and descriptions | qualitative | Developer edits <20% of auto-created bead text |
| Source adapters degrade gracefully when APIs are down | measurable | Scan completes (with partial results) even if one source fails |
| Intercore integration records discoveries in kernel | measurable | `ic discovery` shows recent scan results |

## Known Friction Points

- **Cold start** — new projects have no feedback history. First scans are noisy until the developer trains the model with promote/dismiss signals.
- **Source rate limits** — arXiv and Hacker News have rate limits. Aggressive scanning can hit throttling.
- **Relevance scoring is keyword + embedding based** — semantic gaps exist. A paper using different terminology for the same concept may score low.
- **Auto-bead creation can be noisy** — high-relevance threshold needs calibration per project. Too low = bead spam, too high = missed discoveries.
- **Requires Intercore for full feedback loop** — without `ic` CLI, scans work but feedback signals aren't persisted for model improvement.
