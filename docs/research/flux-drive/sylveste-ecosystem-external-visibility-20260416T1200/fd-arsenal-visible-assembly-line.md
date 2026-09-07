# fd-arsenal-visible-assembly-line — Findings

Lens: Venetian Arsenal proto, c. 1570. The political-economic instrument is not the ship but the line — the visible unbroken chronological sequence that converts raw material to deployed galley within a diplomatic visit. Ambassador's report: "they launch one per day." That claim carried Venetian naval credit for two centuries.

## Verdict

Build the viewing-line, not the demo video. A video is a single witnessing that ends. A live always-on page showing the Closed-Loop pipeline running on Sylveste's own bead workload is the line that produces the ambassador's report "they calibrate one cost baseline per N landable changes."

## Findings

### P0 — Self-building claim exists in prose but has no viewing-line
**Location:** PHILOSOPHY.md claim #10 "Sylveste builds Sylveste" (target-brief line 86), target-brief §"Cost baseline" (line 134).

The strongest non-obvious claim in the inventory — that Sylveste runs its own factory on itself — has no public canal for a visitor to walk. Bead history exists internally. Session trail exists internally. Cost baseline exists via CLI. But a cold reader cannot watch it happen. The Arsenal has ships but no canal.

**Fix:** build a public always-on page at `sylveste.dev/factory` (or mistakeknot.github.io/sylveste-factory) showing:
- Station 1: recent `bd list --status=in_progress` (dispatch).
- Station 2: recent `bd list --status=closed --since=24h` (landable changes produced).
- Station 3: last Interspect evidence emission.
- Station 4: last calibration write (what cost estimate changed, when, why).
- Station 5: current $/landable-change as live-updated field.
- Station 6: next-run default, updated from calibration.

The visitor walks the canal and sees each station producing visible output. No station may be idle — if a station is M0-M1 and would show emptiness, hide it from the public tour.

### P0 — The Closed-Loop pipeline is a one-shot CLI invocation, not a live visible line
**Location:** target-brief line 90 (`estimate-costs.sh` existence proof).

The pipeline works. It is claimed as the existence proof of the Closed-Loop pattern. But it is a CLI artifact — single-station demonstration. Ambassador sees a finished galley (a cost estimate) but not the line that produced it. Credibility transfer does not happen.

**Fix:** wire `estimate-costs.sh` to run on a cron, write results to a timestamped log, publish the log as an Atom/RSS feed. Every calibration is a public event. This converts the single station into a chronological line.

### P1 — No visual cadence claim rigged
**Location:** target-brief §"Cost baseline" (line 134): "$2.93/landable change, 785 sessions."

"785 sessions" is a cumulative number — a total, not a rate. The Arsenal's power was "one galley per day" — a rate. Sylveste's equivalent would be "one calibrated default update per N landable changes" or "one evidence-epoch reset per M sessions." A rate is repeatable; a total is a one-time artifact.

**Fix:** compute and publish one rate claim. Candidate: "Sylveste lands N changes per week at $2.93 mean cost, recalibrating the default every K changes." The rate is the ambassador's report.

### P1 — Stations that must be hidden from the public tour
**Location:** target-brief §"Cross-cutting evidence systems" (lines 57-63).

These are M0-M1 and would show idleness if included in the public line:
- Ockham (early) — dashboards empty.
- Interweave (early, epic in progress) — no wired triggers.
- Interop Phase 1 executing — partial.
- FluxBench planned — not built.

Including them in the canal shows back-canal work visitors were never meant to see. Empty stations collapse the "unbroken chronological" effect that is the entire mechanism.

**Fix:** the public factory page shows only stations that actually produce evidence today: bead dispatch → evidence emit (Interspect only) → calibration write (cost pipeline only) → default update → next-run consumption. Four stations visibly productive. Hide the rest.

### P2 — Interchart diagram is topology, not flow-through-time
**Location:** target-brief line 114.

Static map — the viewer inspects but does not witness. Useful for an architecture reference, but does not do the Arsenal's political-economic work. Keep it, but do not make it the hero artifact.

## The ambassador's one-sentence report

"Sylveste publishes a calibrated cost estimate after every N bead sessions — it has landed 785 sessions at $2.93/change so far, and the calibration updates in public."

One sentence. Rate claim. Verifiable via the public feed.

## The viewing-line, named

`sylveste.dev/factory` — five visible stations, updated continuously, four actually producing evidence. The calibration feed is an RSS. The cost-baseline value is a live number. The bead dispatch list is a rolling view. Any visitor can walk the canal in under 3 minutes. Cold reader from HN clicks, walks the line, feels the cadence, leaves with the ambassador's sentence.

Built this week. Before the HN post. Before the preprint. Before the video. The video is a recording OF the line, not a replacement for it.

<!-- flux-drive:complete -->
