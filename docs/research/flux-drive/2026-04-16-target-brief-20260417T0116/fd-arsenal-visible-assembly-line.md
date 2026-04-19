# fd-arsenal-visible-assembly-line — Findings

**Lens:** Proto del' Arsenale, Venetian Arsenal circa 1570. Mechanism: the Arsenal's political-economic instrument was not the galley but the *line* — a visible, unbroken, chronologically legible sequence of stations that converted raw material to deployed ship within the duration of one diplomatic visit. The ambassador's report home — "they launch one per day" — was the signal that justified Venetian naval credit for two centuries. The line was designed so the ambassador never waited and never saw idle stations.

## Findings Index

- P0 — No viewing-line exists: self-building claim has no public chronological artifact
- P0 — The only candidate line (Closed-Loop pipeline) is a one-shot CLI, not a live page
- P1 — Back-canal stations (M0-M1 cross-cutting systems) are in the public inventory
- P1 — No visual cadence claim; no stated rate
- P2 — Interchart shows topology but not flow-through-time
- P3 — Bead tracker produces the right raw material but has no public viewing surface

## Verdict

**Build one always-on public page that shows the Closed-Loop pipeline running live on Sylveste's own bead workload.** Stations labeled: dispatch → evidence emit → calibration write → default update → next-run consumption. Ambassador's report: "Sylveste calibrates its own cost estimates from last week's sessions, and you can watch the defaults change." Cadence: "one calibration update per day."

## Summary

Sylveste has the ships. It does not have the canal. Every distinctive claim in the target brief can in principle be demonstrated end-to-end — but no public surface lets a cold visitor walk the demonstration chronologically in one unbroken viewing. The self-building claim, the evidence-earns-authority claim, the Closed-Loop pattern — these are credal assertions on the current public surface, not witnessed events.

The Arsenal's insight: a demo video is a single viewing that ends. A viewing-line is an ongoing condition that converts every diplomatic visit into a report home. The demo-video scales linearly with promotion effort; the viewing-line produces ambassador reports for decades of subsequent visits.

The one candidate chronological flow that Sylveste has already implemented is the Closed-Loop pipeline: `ic` dispatch → events.jsonl → interstat ingest → estimate-costs.sh calibration → fleet-registry.yaml update → next dispatch consumes the new defaults. Every station exists and works. No public surface assembles them into a walkable line.

## Issues Found

### P0-1: Self-building loop is credal, not witnessed

- **File:** PHILOSOPHY.md claim #10 ("Self-building: Sylveste builds Sylveste with its own tools"); referenced in brief line 86
- **Failure scenario:** The most distinctive claim in the Sylveste philosophy is that the platform builds itself. For the Arsenal metaphor this is the galley-launch claim — the one that would carry ambassador-reports-home for decades. But there is no public surface where a cold reader can watch a bead move from created → claimed → executed → reviewed → shipped, with session IDs, model assignments, cost actuals, and downstream calibration updates visible. No timelapse. No live dashboard. No continuously-updating page. The ambassador visits the Arsenal, is told "we launch one per day," and asks to see a launch — there is no canal to walk down.
- **Smallest viable fix:** Deploy a single static page (or cron-generated markdown) at a public URL — candidate: `sylveste.mistakeknot.com/live/` — showing: last 24h of bead events as a chronological stream, with columns for (bead_id, claimed_by session, dispatched model, cost actual, calibration-update triggered). This is one query over interstat + beads JSONL, rendered as markdown, regenerated every hour. Does not require a frontend framework or a blog. Requires only: one cron, one static page.

### P0-2: Closed-Loop pipeline is a one-shot CLI, not a live pipeline

- **File:** `interverse/interstat/scripts/cost-query.sh`; `estimate-costs.sh` (referenced in brief line 90)
- **Failure scenario:** The target brief identifies `estimate-costs.sh` as the existence proof of the Closed-Loop pattern. But it exists only as a shell script invoked from a terminal. An ambassador cannot watch it run. They can be told "this script reads interstat actuals and writes calibrated estimates," but that is a claim about a line, not a visible line. Single-station demonstration — the ambassador sees a finished artifact (the current fleet-registry.yaml) but not the line that produced it; the unbroken chronological effect is lost.
- **Smallest viable fix:** Wrap the script in a GitHub Actions workflow scheduled every 6 hours. Workflow runs `estimate-costs.sh`, commits the updated `fleet-registry.yaml`, and the commit log becomes the visible line. The public surface is now: `git log fleet-registry.yaml` — a chronological sequence of calibration updates, each commit message showing which agents/models had their estimates shifted, by how much, based on how many new sessions. Zero additional infrastructure. The commit log IS the Arsenal canal.

### P1-1: Back-canal stations in the public inventory

- **File:** Brief lines 57-63 (cross-cutting evidence systems); README architecture table
- **Failure scenario:** The Arsenal hid its unready back-canal work because a visitor who saw an idle station would collapse the credibility of the whole line. Sylveste currently presents five cross-cutting evidence systems in its public architecture — Interspect (operational), Ockham (early), Interweave (early), Interop (Phase 1 executing), Factory Substrate + FluxBench (planned). Four of five are idle stations. A visitor walking the public surface passes four empty workbenches before reaching the one where work is visible. The credibility of the one working station is diluted by proximity to the four idle ones.
- **Smallest viable fix:** On the public architecture page, show only Interspect. Move the other four to an internal `docs/cross-cutting-roadmap.md`, clearly labeled "planned / in progress." The ambassador's tour shows the one working line; the back-canal workshops remain out of sight until they carry their own work-evidence.

### P1-2: No visual cadence claim

- **File:** None — absence is the finding
- **Failure scenario:** The Arsenal's most-cited claim was a rate: "one galley per day." This is the visual cadence — the number that converts a series of events into a witnessed rhythm. Sylveste has all the raw material to make a rate claim: $2.93/landable change × 785 sessions over ~6 weeks = roughly 20 landable changes per day. But no public surface states this rate, and no public surface shows the rate as a running cadence (a ticker, a graph, a commit-log frequency). The ambassador has no single-number report to carry home.
- **Smallest viable fix:** Pick one cadence claim and state it on the public face. Candidates: "~20 landable changes per day, each with a published cost actual and a calibration trace" OR "One cost-calibration cycle per 6 hours, driven by Sylveste's own session workload." State it in numbers. Point to the underlying evidence (the fleet-registry.yaml commit log). One sentence; one rate; one link.

## Improvements

### P2-1: Interchart shows topology, not flow-through-time

- **Site:** `mistakeknot.github.io/interchart/`
- **Observation:** The interactive diagram is a map, not a canal. A visitor can hover, click, inspect nodes and edges. They cannot witness events moving through the graph. Static-map demonstration is useful but does not do the Arsenal's specific political-economic work of converting a visit into an ambassador's report on a rate.
- **Fix:** Overlay live events on the existing diagram. When a bead transitions state, light up the corresponding node for 2 seconds. When a calibration fires, animate the edge from interstat to fleet-registry. Single SSE stream reading from beads JSONL + fleet-registry.yaml git log. Transforms map-with-topology into line-with-flow.

### P3-1: Bead tracker is the right raw material, no public surface

- **File:** `/home/mk/projects/Sylveste/.beads/` (internal only, per CLAUDE.md)
- **Observation:** The bead tracker records every task, every claim, every state transition, every close. This is the Arsenal's actual work log — the document that would prove the rate claim. But it is internal. Nothing public derives from it.
- **Fix:** One daily cron that produces `docs/live/beads-24h.md` — a markdown table of bead events from the last 24 hours, published to the public Sylveste repo. No new infrastructure; uses `bd list` + jq + commit. The ambassador can now walk the git log of `beads-24h.md` and witness a full week of rate-continuous evidence.

## Deliverable

### The one chronological viewing-line (buildable this week)

**Public URL (or public repo path):** `github.com/mistakeknot/Sylveste/blob/main/docs/live/closed-loop.md`

**Station-by-station walkthrough (what the ambassador sees, in order):**

1. **Station 1 — Dispatch.** Last 5 `ic dispatch` events with timestamp, agent, model, session ID.
2. **Station 2 — Evidence emission.** For each dispatch, the corresponding `events.jsonl` entries showing tool calls, token counts, cost actuals.
3. **Station 3 — Calibration write.** The most recent `estimate-costs.sh` run, showing which agent/model estimates were updated and by how much.
4. **Station 4 — Default update.** The git diff on `fleet-registry.yaml` produced by station 3.
5. **Station 5 — Next-run consumption.** The next `ic dispatch` event whose estimate matched the value written in station 4.

All five stations visible on one page. Each regenerated every 6 hours via GitHub Actions cron. Total new infrastructure: one workflow file, one markdown template.

### Ambassador's one-sentence report

> **"Sylveste calibrates its own cost-estimates from its own agent sessions every 6 hours, and you can watch the defaults change in a public git log."**

One sentence. Testable claim (visit the commit log; the claim is either true or false). Carries home.

### Visual cadence claim

> **"One calibration cycle per 6 hours. ~20 landable changes per day, each with published cost actuals."**

Numeric. Citable. Matches the shape of the Arsenal's "one galley per day" claim.

### Back-canal stations to hide from the public tour

1. **Ockham** (L2 factory governor, early) — no working public demo; visitors would see an idle workshop.
2. **Interweave** (ontology graph, early) — M0-M1; idle.
3. **Interop** (Go daemon replacing interkasten, Phase 1 executing) — in-progress; visitors would see disassembly.
4. **Factory Substrate + FluxBench** (planned) — not yet a station at all.
5. **Garden Salon** — no public artifact.
6. **Meadowsyn** — domain registered, no site.
7. **Skaffen** (sovereign Go agent runtime, migrating) — under construction.
8. **Zaka/Alwe** (universal CLI driver split, epic in progress) — scaffolding visible.
9. **Autarch TUI apps (Bigend, Gurgeh, Coldwine, Pollard)** — not the wedge; back-canal workshops.

These are not cancelled. They remain in the internal roadmap. They are removed from the public tour until each has its own station producing visible work.

<!-- flux-drive:complete -->
