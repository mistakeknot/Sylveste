---
agent: fd-ar-rollout-cadence-strategist
tier: generated
category: project
model: sonnet
lens: A&R strategist — release cadence, support-act slots, embargo discipline
---

# Review — A&R Rollout Cadence Strategist

## Findings Index

- P0-CADENCE-1: Any single HN submission for "all of Sylveste" is an album-without-single launch — will burn the one shot
- P1-CADENCE-1: Clavain's existing Claude Code plugin marketplace slot is the support-act opportunity and is being underutilized for audience pre-cultivation
- P1-CADENCE-2: Meadowsyn.com domain is registered with no audience-capture surface — every future single plays to a cold audience
- P2-CADENCE-1: Multiple subsystems (Interweave, Ockham, Zaka/Alwe) being polished in parallel dilutes attention per reveal
- P3-CADENCE-1: No press-embargo discipline — no plan for coordinating preprint + demo + HN + thread on a single lift day

## Verdict

**No full-Sylveste reveal before v1.0. Ship a single, then an EP, then the album.** The lead single is a blog post on Interspect cost-calibration with the $2.93 number. The EP is a three-post vertical slice on the closed-loop cost pipeline with a preprint anchor. The album is the v1.0 reveal, 6-8 weeks out, coordinated across preprint + demo video + HN + thread on one embargo-lift day. Clavain's existing plugin marketplace slot is the support-act — do not waste it.

## Summary

The target brief constraint is one HN post, one demo video, one blog post per week, one or two polished subsystems. This is a release-cadence problem, not an artifact problem. An indie artist with one single's worth of budget does not drop an album — they drop a single, cultivate an audience, drop a second single with the same audience plus new listeners, and save the full reveal for the moment the audience is warm enough to catch it.

Sylveste's current posture is "we will drop the album" — the monorepo, 55+ plugins, 12 distinctive claims, two brands, all surfaced simultaneously. Album-without-single launches die because no audience was pre-cultivated. Worse: HN and X both reward a single sharp artifact over a sprawling announcement, so even a successful full-reveal gets filtered down to one cherry-picked claim that the reader may not have picked.

The fix is calendar discipline. 6-8 weeks. Three scheduled drops. Each subsequent drop plays to a warmer audience. The v1.0 reveal happens when the audience is already listening, not when it is being asked to listen for the first time.

## Issues Found

### P0-CADENCE-1: Album-without-single HN submission will burn the one shot

- **File:** target-brief lines 148-152 ("one HN post")
- **Failure scenario:** The user drops a Show HN for "Sylveste — an autonomous software development agency platform." The submission has: a monorepo, 55+ plugins, 12 distinctive claims, two brand surfaces (Sylveste + Garden Salon), no preceding blog post, no preprint, no demo video. HN front-pages it for 6 hours. Commenters cherry-pick: one person defends the self-building claim, one dismisses the plugin inventory, the thread becomes a referendum on "is this vaporware." The post sunsets. Nothing compounds. The user does not get a second HN shot at Sylveste for 12+ months. This is the 3am-wake-up scenario: HN-post-without-pre-cultivation is the launch that ends launches.
- **Smallest viable fix:** Schedule the HN post for week 6 of the 6-week calendar. Pre-seed weeks 1-5: one blog post per week, each building to the HN moment. See "The Calendar" below.

### P1-CADENCE-1: Clavain's Claude Code plugin slot is the support-act, underutilized

- **File:** `Clavain/` — target-brief line 44 (ships today as a Claude Code plugin)
- **Failure scenario:** Clavain is already installed in Claude Code users' toolchains. Those users are the ideal pre-seed audience — they are technically serious, they already adopted one Sylveste-adjacent artifact, they have the install surface. Every Clavain release note, every `/clavain:help` output, every onboarding flow is a touchpoint that currently does not mention Sylveste or point to the preprint / blog. This is the "opening for a bigger tour" slot the A&R discipline exists to exploit. Leaving it empty means the lead single drops to a cold audience even though a warm one is literally within `~/.claude/plugins/cache/`.
- **Smallest viable fix:** Add one line to Clavain's post-install banner ("you're using Clavain — see the methods behind it at sylveste.ai/cost-calibration"). Add one line to `/clavain:help` header. Use Clavain changelog entries to tease upcoming Sylveste posts. This costs nothing and converts a zero-friction warm audience.

### P1-CADENCE-2: No audience-capture surface for the lead single

- **File:** `meadowsyn.com` — registered, no site (target-brief line 124)
- **Failure scenario:** Week 1 blog post drops. Traffic arrives. No email capture, no RSS feed, no "subscribe for the next one." Week 3 EP drops to the same cold audience (minus whoever happened to bookmark). Week 6 HN post fires and there is still no accumulated warm list. The audience never compounds across drops. Each single plays to strangers.
- **Smallest viable fix:** Stand up a minimal landing at `sylveste.ai` (or whichever domain is chosen — meadowsyn.com is branded for the visualization layer, should not be the capture surface). One page: tagline, the number, email signup ("I'll send the next post when it drops"), link to the lead-single post. Deployable in an hour. Without this, the A&R calendar has no compounding mechanism.

### P2-CADENCE-1: Parallel subsystem polishing dilutes attention

- **File:** target-brief lines 45-50 (Skaffen, Zaka/Alwe, Ockham, Interspect, Interweave all active)
- **Failure scenario:** The user is pre-1.0 with limited bandwidth. If three subsystems get simultaneous polish and a joint reveal, each one gets one-third the airtime. The reader who would have loved Interspect-as-standalone now has to parse the relationship between Interspect and Ockham and Interweave in the same breath. Each subsystem deserves its own release window. Degradation is slow — attention per reveal halves with each additional parallel subsystem surfaced.
- **Smallest viable fix:** Sequence. Week 1-2: Interspect is the only subsystem surfaced publicly. Week 3-5: cost-calibration pipeline EP (three posts, one preprint). Week 6+: only then consider adding Ockham / Interweave to the public surface. The other subsystems continue being built, but do not ship to the public calendar until their slot arrives. "B-sides" stay on the monorepo, not on the landing page.

### P3-CADENCE-1: No embargo-lift coordination

- **File:** absent
- **Failure scenario:** The user drops a preprint on arXiv Tuesday, a demo video on YouTube Wednesday, an HN post Thursday, a tweet thread Friday. Each is a separate event. None reinforces the others. The HN commenters do not have the preprint in hand. The preprint readers do not find the demo. The tweet thread is a standalone. No compounding.
- **Smallest viable fix:** One embargo-lift day. All four artifacts drop within 2 hours. HN post links to arXiv preprint AND demo video. Tweet thread is timed to fire 30 minutes after the HN post with the same links. Cross-pollination is the compounding mechanism.

## Improvements

- Save one plugin release (pick the sharpest: intercept, interspect, interflux) as a dedicated mid-window single if the user has extra bandwidth — it re-warms the audience between the EP and the album.
- The self-building demo video doubles as the "music video" for the lead single. Same asset, two surfaces.
- Consider Lobsters as a lower-stakes dry-run venue for the lead single before HN — the Lobsters crowd is technically serious, smaller, and won't consume the HN shot.

## The 6-Week Calendar

**Week 1 — Lead Single** (blog post)
- Title: "What Happens When Agents Track Their Own Friction: $2.93 Per Landed Change"
- Hosted on sylveste.ai (standing up the audience-capture surface IS the week-1 work)
- Content: the self-building claim, the Interspect cost-calibration pipeline as existence proof, the number
- Support-act leverage: announced via Clavain release notes + /clavain:help banner
- Drops Tuesday. Post to Lobsters. Soft-post to X (no thread yet, just the link).

**Week 2 — Audience Warming**
- Email signup list cleaned, minimal weekly "what's shipping" note (1 paragraph, 1 link)
- No public launches. Clavain v0.7 patch release mentions "more on the cost pipeline next week."

**Week 3 — EP, track 1** (blog post)
- Title: "The 4-Stage Closed-Loop Pattern: Calibration from Hardcoded Defaults to Earned Evidence"
- Builds on week 1 with the methodology detail
- Preprint draft starts this week in parallel

**Week 4 — EP, track 2** (blog post)
- Title: "Every Action Produces Evidence: The Compound Step Boyd's OODA Was Missing"
- Covers OODARC specifically, references the calibration post
- Tweet thread here (first thread — audience now has 3 weeks of context)

**Week 5 — EP, track 3** (blog post + preprint live)
- Title: "A Methods Note on Measuring Agent Infrastructure Cost" (the preprint)
- Preprint on arXiv / Zenodo with DOI
- Blog post points to preprint, preprint cites blog posts 1-3

**Week 6 — Album Drop / Embargo Lift**
- Single day, coordinated within 2 hours:
  - Demo video live on YouTube (the self-building screencast)
  - Show HN post: title "Show HN: Sylveste — Agents that build their own scaffolding [preprint]"
  - Tweet thread (longer this time, narrative arc across the 6 weeks)
  - Clavain v1.0-eligible release
- Garden Salon and Meadowsyn still silent. They get their own singles later.

**Post-week-6**: normal 1-post-per-week cadence resumes. Each post is a b-side that the now-warm audience will catch.

## What Gets Moved to B-Side (or Cut)

Of the 55+ plugins, most are b-sides — cataloged on a separate page reached only after first-contact conversion. Specifically:

- **Sequence-later**: Ockham, Zaka/Alwe, Interweave, Skaffen, Auraken (these deserve their own singles post-1.0)
- **Cut from the album entirely**: Garden Salon and Meadowsyn as first-contact brand surfaces — these are post-1.0 albums of their own, not tracks on this one
- **B-sides on the catalog page**: 50+ of the inter-* plugins — available, not foregrounded
- **Keep as headline tracks**: Clavain (support act), Interspect (lead single instrument), intercore (credited as rhythm section)

<!-- flux-drive:complete -->
