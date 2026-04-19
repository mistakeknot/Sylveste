# fd-hokulea-noninstrument-wayfinding — Findings

Lens: Polynesian non-instrument wayfinding, Hōkūleʻa 1976 revival lineage, Mau Piailug / Nainoa Thompson star compass. Mechanism: hold position by simultaneous reference to primary star, backup zenith-passing star at destination latitude, dominant swell direction, and pattern of manu-o-Ku (land-finding terns) — never a single indicator. The decision is which redundant bearings to rig before departure, because mid-voyage you cannot invent new ones.

## Verdict, one line

The bandwidth constraint permits one HN shot, one demo, one blog post per week. The current plan treats each of those as a single independent bearing — serial bets. A wayfinder pairs them as simultaneous bearings on the same destination. Do not sail until primary + zenith-backup + swell + bird are all rigged. Right now only the primary bearing is partially visible.

## Findings

### P0 — One HN shot planned with only the primary star rigged
**Location:** target-brief §"User CAN" (lines 148-153).

The user has one HN/Lobsters/X post. If it links only to the monorepo README and the HN algorithm misses the window (wrong day, wrong hour, upvote cycle miss), there is no backup bearing — the voyage is over with no recovery path. That is a cloud-obscured primary star with nothing alongside.

**Failure scenario:** HN post goes live. Front page cycles faster than expected. 40 upvotes, drops off within 4 hours. Nothing else for a technically-serious reader to click to. The "Sylveste" token they saw is associated with "another framework post that didn't break through." Subsequent reintroduction is harder because reputation penalty attaches to the name.

**Action:** do not spend the HN shot until at least three simultaneous bearings exist at the destination:
- **Primary star:** HN submission.
- **Zenith-passing backup:** a preprint on arXiv (cost-calibration methods note, or OODARC specification) with DOI/arXiv ID. Even if HN misses, the preprint sits in the serious-ML indexing and accrues slow citation. Same destination, different visibility mechanism.
- **Swell cross-check:** one reproducible command a skeptic runs in <60 seconds. Candidate: `curl ... | bash && sylveste cost-baseline` that returns "$2.93/landable change across N sessions." The reader feels the swell under the hull — the system is real regardless of what the launch-star is doing.
- **Manu-o-Ku:** three to five specific named technically-serious practitioners who have been personally pinged and know the submission is coming. Their attention is the land-finding tern.

Until all four bearings are rigged, the voyage cannot depart.

### P1 — No manu-o-Ku identified
**Location:** target-brief §"What 'External Signal' Means Here" (lines 156-168).

The brief names the audience abstractly ("technically serious readers who evaluate AI/agent infrastructure for a living") but names zero specific practitioners. A wayfinder cannot spot land-finding birds if the bird species has not been identified before the voyage. Specific-named humans are the most reliable landfall signal — their public engagement (blog post citation, repo star, reply thread) is worth more than any algorithmic distribution.

**Failure scenario:** launch succeeds by algorithmic metrics (HN front page). Receives 2,000 upvotes. Zero of the 2,000 are from the specific senior practitioners whose citation would compound. The signal is noise — lots of attention, no directional pull toward the destination audience.

**Action:** name 3-5 specific people this week whose attention would confirm landfall. Criteria: active on Twitter/X or blog, have written about agent infrastructure in the last 6 months, would plausibly engage with a specific technical primitive (OODARC, closed-loop calibration, progressive trust). Example categories (name real people per category):
- An ML infra researcher who works on agent tooling publicly.
- A framework-building practitioner (not a vendor; a maintainer).
- A senior staff engineer at a lab who reads agent infrastructure for a living.
- An OSS developer known for reproducibility discipline.
- A writer-practitioner whose essays get cited in the serious community.

Reach out to one of them privately BEFORE the public launch. A private heads-up with the preprint link is how wayfinders confirm the birds are in the expected direction before committing to the course.

### P1 — No swell-pattern artifact in place as continuous positional evidence
**Location:** target-brief §"Public artifacts" (lines 116-124) — "No recorded demo... No benchmark result published externally."

The brief confirms: no video, no screencast, no benchmark published, no reproducible command visible. There is nothing a skeptic can feel under the hull. The voyage has a primary-star plan but no swell cross-check.

**Failure scenario:** reader visits from HN, does not find any runnable artifact within 30 seconds. Closes tab. The primary star delivered them to the harbor, but without swell under the hull they cannot confirm the harbor is real, so they drift.

**Action:** the swell must exist before the primary star is fired. Candidate swell (build this week):
- Public page at `sylveste.dev/closed-loop` (or mistakeknot.github.io/sylveste) showing a live-updating readout of the Closed-Loop pipeline: last calibration timestamp, last $/landable-change value, last N bead sessions. One curl command reproduces it locally. Under 60 seconds to verify.

This is the one artifact that lets the reader feel the system is moving regardless of what HN shows that hour.

### P2 — No dead-reckoning record visible between launch events
**Location:** target-brief §"Cost baseline" (line 134); self-building loop.

Sylveste has internal dead-reckoning (the bead tracker, the cost query script) but none of it is publicly visible between launch events. Etak is the Polynesian mental position-estimate method that lets the voyage continue between stars. Without public etak, the time between HN shot and blog post is dark — no way for a late arriver to confirm the voyage is still on course.

**Action:** make the bead tracker queryable in read-only mode via a public URL. Even a CSV dump updated daily of `bd list --status=closed --since=7d` is enough. This is the etak — continuous low-fidelity positional evidence that persists between the discrete visibility events.

### P2 — Demo video treated as independent move rather than paired zenith bearing
**Location:** target-brief §"User CAN" (line 151).

The current framing treats "record one demo video" and "post once to HN" as two independent bets. A wayfinder rigs them as paired bearings on the same week:
- The HN post's hero link should be the preprint.
- The preprint's hero figure should be a frame from the demo video.
- The demo video's last 10 seconds should show the arXiv ID.
- The blog post (same week) should cite the preprint and embed the video.

If any one of these visibility events is cloud-obscured, the others still point to the same destination. Serial posting is single-star navigation — four independent low-probability shots. Paired posting is four bearings on one destination.

**Action:** sequence the week so that preprint + video + blog + HN all ship within a 48-hour window and all cross-link. No one artifact is allowed to ship without pointing to the others.

## Departure Readiness Checklist

Do not sail until all four bearings are rigged simultaneously:

- [ ] **Primary star:** HN/Lobsters/X draft post (written but not submitted).
- [ ] **Zenith-passing backup:** arXiv preprint live with DOI, methods note pinned to one measured claim (cost-calibration + $2.93 baseline is the obvious candidate).
- [ ] **Swell cross-check:** public page with a reproducible 60-second command that any skeptic can run to feel the system under the hull.
- [ ] **Manu-o-Ku:** three named practitioners contacted privately with the preprint link at least 48 hours before public submission.
- [ ] **Etak / dead-reckoning:** public read-only view of the bead tracker state (CSV or dashboard), updated at least daily.

If any of these is missing, the departure readiness condition is not met. Do not spend the HN shot. Wait one week. Rig the missing bearing first.

## The specific bearings, named

- **Primary star:** HN Show HN submission titled "Show HN: OODARC — calibrated agent loops with receipts ($2.93/landable change baseline)."
- **Zenith-passing backup:** 4-8 page arXiv preprint: "Closed-Loop Cost Calibration for Autonomous Software-Development Agents." Single reproducible table. Same destination as the HN post — "Sylveste has shippable rigor" — but via the peer-indexed mechanism instead of the algorithmic one.
- **Swell:** `sylveste.dev/closed-loop` public page with live calibration readout and the one curl command.
- **Manu-o-Ku:** three specific practitioners (names to be identified by the user this week — the agent cannot select strangers on the user's behalf, but the category list in P1 above constrains the search).

The voyage is conceptually possible from today's inventory. The bearings are not yet rigged. Rigging them is the work of the next week; sailing is the week after.

<!-- flux-drive:complete -->
