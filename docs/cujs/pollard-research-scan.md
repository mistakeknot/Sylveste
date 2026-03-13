---
artifact_type: cuj
journey: pollard-research-scan
actor: regular user (developer or researcher tracking a domain)
criticality: p3
bead: Demarch-2c7
---

# Pollard Research Intelligence Scan

## Why This Journey Matters

Staying current in a technical domain — or any domain — requires constant scanning across multiple sources: GitHub trending repos, academic papers, patent filings, competitor announcements, regulatory changes. Pollard automates this scan, turning a daily 30-minute browsing ritual into a structured intelligence pipeline.

The value isn't just finding things — it's finding things *first* and *in context*. A new research paper on code generation matters differently to someone building an agent platform than to someone building a web app. Pollard's hunters are domain-aware, and its reports are structured so the developer can triage quickly: "This is relevant, this isn't, this needs deeper investigation."

## The Journey

The developer initializes Pollard for their project: `go run ./cmd/pollard init`. This creates `.pollard/` with default source configuration — GitHub trending, OpenAlex academic search, and optionally domain-specific hunters (PubMed for medical, CourtListener for legal, USDA for agriculture).

They run a scan: `go run ./cmd/pollard scan`. Each hunter queries its sources — GitHub Scout checks trending repos and new releases in relevant ecosystems, OpenAlex searches recent papers matching configured keywords. Results are deduplicated, scored for relevance, and stored locally.

The developer generates a report: `go run ./cmd/pollard report`. Pollard produces a structured landscape report — new entries grouped by source, ranked by relevance, with brief summaries. For competitive intelligence: `go run ./cmd/pollard report --type competitive` focuses on direct competitors and alternatives.

For ongoing monitoring, `go run ./cmd/pollard watch` runs continuous scans at configured intervals, alerting when high-relevance items appear. The developer can also target specific hunters: `go run ./cmd/pollard scan --hunter github-scout` for just GitHub, or `--hunter openalex` for just academic papers.

The Pollard API server (`go run ./cmd/pollard serve --addr 127.0.0.1:8090`) exposes results for integration with Autarch's TUI dashboard or external tools.

## Success Signals

| Signal | Type | Assertion |
|--------|------|-----------|
| First scan completes in under 2 minutes | measurable | Wall time from `scan` to completion ≤ 120s |
| Scan uses free API tiers only (no auth required for core hunters) | measurable | Core hunters succeed without API keys |
| Report groups results by source with relevance scores | measurable | Report output has source headers and numeric scores |
| Watch mode detects new high-relevance items within one interval | measurable | Alert latency ≤ configured watch interval |
| Developer finds at least one actionable insight per week | qualitative | Self-reported utility in regular use |
| API server starts and responds at /health | measurable | HTTP 200 at configured address |

## Known Friction Points

- **Free API rate limits** — GitHub and academic APIs have rate limits. Large scans may need throttling or pagination.
- **Relevance scoring is keyword-based** — no semantic understanding. Domain-specific hunters help but aren't perfect.
- **No integration with beads or Interject** — Pollard findings don't automatically become beads or Interject discoveries. Manual bridge required.
- **Some hunters require API keys** — USDA, CourtListener, and domain-specific sources need configuration. Core (GitHub, OpenAlex) works without keys.
