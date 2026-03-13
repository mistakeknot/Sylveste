---
artifact_type: cuj
journey: interwatch-drift-detection
actor: regular user (developer maintaining documentation accuracy)
criticality: p2
bead: Demarch-2c7
---

# Interwatch Drift Detection

## Why This Journey Matters

Documentation that describes what the code used to do is worse than no documentation — it actively misleads. Every refactor, every feature addition, every renamed function creates potential drift between what the docs say and what the code does. The larger the codebase, the faster docs decay.

Interwatch automates drift detection. It monitors registered documents, evaluates freshness via 17 signal types (bead closures, file changes, commit activity, test results), and dispatches to generators for refresh when confidence drops. The developer doesn't need to remember which docs might be stale — Interwatch tells them.

## The Journey

The developer sets up Interwatch for their project. Auto-discovery scans for watchable documents by convention: `docs/cujs/*.md`, `docs/prds/*.md`, `docs/roadmaps/*.md`, `CLAUDE.md`, `AGENTS.md`, `README.md`. The scan writes `.interwatch/watchables.yaml` — a registry of every monitored document with its discovery path and signal configuration.

The developer runs a scan: `/interwatch:watch`. Interwatch evaluates each document against its freshness signals. Feature-change signals are cheap — did a related bead close since the doc was last updated? Were new brainstorms created in the same domain? Did the referenced files change? Test-result signals are more expensive — do the success assertions in a CUJ still pass?

Each document gets a confidence score across four tiers:
- **Certain** (auto-fixable drift) — e.g., a version number changed
- **High** (auto-fix with note) — e.g., a referenced file was renamed
- **Medium** (suggest update) — e.g., multiple beads closed since last update
- **Low** (report for review) — e.g., test signals changed but cause is unclear

The developer sees a dashboard: `/interwatch:status`. Documents are color-coded by staleness. Stale docs (>14 days since meaningful update with feature-change signals firing) are flagged. The developer can trigger a refresh: `/interwatch:refresh <doc>` dispatches to the appropriate generator (interpath for product docs, interdoc for code docs).

For correctness beyond freshness, `/interwatch:audit` runs a stranger-perspective audit — reading the document as if encountering it for the first time, checking every claim against the actual codebase, and flagging contradictions. This catches drift that signal-based detection misses: "The doc says the API returns JSON, but the handler returns plain text."

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| Auto-discovery finds all convention-placed docs | measurable | Watchables count matches `find docs/ -name '*.md'` count |
| Drift detected within one scan of causing change | measurable | Bead closure triggers staleness flag in next scan |
| Confidence scores match manual assessment | qualitative | Developer agrees with High/Medium/Low ratings ≥80% of time |
| Refresh produces an updated document, not a broken one | measurable | Post-refresh document passes interwatch audit |
| Staleness threshold (14 days) is configurable | measurable | Config allows custom threshold per doc type |
| Audit catches factual errors in documentation | measurable | Audit flags known-wrong claims when seeded |
| Status dashboard loads in under 5 seconds | measurable | Wall time from command to full output ≤ 5s |

## Known Friction Points

- **Signal noise** — some commits touch many files but don't affect documentation accuracy. Interwatch may flag docs as stale when they're fine.
- **No incremental scan** — each scan re-evaluates all watchables. For large doc sets, this is slow. Should support delta scans.
- **Audit is expensive** — stranger-perspective audit reads the full codebase around each claim. Token cost scales with doc size.
- **Generator quality varies** — refreshed docs are only as good as the generator. interpath/interdoc output needs human review.
- **No CI integration** — drift detection is on-demand, not part of the build pipeline. Future: GitHub Action that runs scan on PR.
