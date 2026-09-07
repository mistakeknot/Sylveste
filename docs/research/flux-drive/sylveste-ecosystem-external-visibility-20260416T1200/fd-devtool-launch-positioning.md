# fd-devtool-launch-positioning — Findings

Lens: 15 years watching OSS dev-tools find or fail their wedge. Docker, Prisma, Rails, Astro, Deno as pattern library. Skeptical of projects that lead with architecture diagrams and multi-brand frameworks instead of a single-frame capability claim.

## Verdict

Sylveste currently fails the 'one-frame claim' test. A first-time technical reader cannot articulate what Sylveste does in one sentence after 60 seconds on the repo. Lead with a capability, not a taxonomy.

## Findings

### P0 — README leads with "monorepo for building software with agents" and architecture table
**Location:** README.md.

This is the textbook dev-tool launch failure. The first screen says "monorepo" (org-chart-word), "software with agents" (generic category), and then an architecture table (internal-organization-leaking-out). No capability is named. No specific thing the reader might want is offered. The reader exits within 30 seconds.

Compare: Rails launched with "build a blog in 15 minutes." Docker launched with "ship any app, any environment." Astro launched with "islands architecture." Deno launched with "TypeScript runtime." Each is a one-frame capability, not a taxonomy.

**Fix:** rewrite README first screen. Candidate: "Sylveste is an agent platform where every run's lesson gets written back as calibration. Current baseline: $2.93 per landable change across 785 sessions. [link to factory page]." This is a capability frame with a specific receipt.

### P0 — Two-brand architecture is visible pre-v1.0
**Location:** target-brief §"Two brands, one architecture" lines 66-69, MISSION.md two-brand framing.

Docker did not launch with "dotCloud + Docker." Prisma did not launch with "Prisma + Nexus + Photon." The pivot-to-single-brand moves came before breakout. Sylveste is pre-1.0 and presenting four register levels simultaneously: Sylveste (SF lit), Garden Salon (organic), Meadowsyn (bridge), inter-* (neutral).

Every one of those brand surfaces is attention-tax on a reader who has not yet earned the product's second click.

**Fix:** consolidate to one public brand until v1.0. "Sylveste" is the platform. Everything else stays internal. Garden Salon and Meadowsyn do not exist for external readers.

### P0 — 64-plugin Interverse inventory surfaced in README
**Location:** target-brief line 55, README architecture section.

No breakout dev-infra tool launched with its full component catalog visible. Docker had components but led with the daemon + client. Rails had 20+ components but led with scaffolding. The inventory triggers the "we built a platform" allergy in the technically-serious reader.

**Fix:** remove all Interverse enumeration from README. If a plugin list must exist, put it in `docs/plugins.md` with no link from the top of README. Top of README names at most three systems.

### P1 — Pillar/layer taxonomy as external-facing scaffolding
**Location:** target-brief §"Three Layers, Six Pillars" lines 38-55.

"Three layers, six pillars, cross-cutting systems" is internal organization leaking outward. This is the language of a team talking to itself. A technically-serious reader does not care about the layering model until they already care about the product.

**Fix:** demote the pillar/layer taxonomy to an internal design doc. Do not use that vocabulary on README or MISSION. External-facing surface says what it does, not how it is organized.

### P1 — No canonical demo artifact
**Location:** target-brief §"No public artifacts currently" lines 116-124.

No video, no screencast, no benchmark, no Show HN, no blog. The launch physics are: no launch is possible from here. A demo is the unit of attention exchange. Without one, even a successful HN hit has nothing for the reader to exchange their 60 seconds for.

**Fix:** a demo must exist before any launch. Candidate: 60-90 second screencast of the Closed-Loop pipeline running end-to-end on the user's own monorepo, with the $2.93 baseline visible updating. This is the minimum viable artifact for a launch.

### P2 — SF-literature naming is a branding tic without payoff
**Location:** Sylveste, Clavain, Skaffen, Ockham, Auraken, Khouri.

The names are distinctive (good for retelling per Vedic finding) but the register demands a reader who is already in. For cold discovery, the names are load without payoff. Docker/Rails/Astro all use shape-of-thing names. Sylveste's SF-character names impose meta-fiction overhead.

**Fix:** on public-facing surface, prefix the first mention with role: "Sylveste (an agent platform)," "Clavain (the phase-gate rig)." After the reader has earned the register, drop the gloss.

## The one-sentence claim test

Current: cannot pass. A reader cannot articulate Sylveste after 60 seconds.

Target: "Sylveste is a Git-native agent platform where every run's lesson gets compounded into the next run's calibration — we publish the cost baseline live at $2.93 per landable change." Or: "Sylveste wires Boyd's OODA loop with two extra steps (Reflect + Compound) so agent loops actually learn."

Pick one. Put it on the first line of README. Everything else subordinates or hides.

## Smallest viable fix, this week

1. Rewrite README first screen to one capability sentence + one receipt number + one demo link.
2. Remove Interverse plugin inventory from README.
3. Hide Garden Salon and Meadowsyn from all public surfaces.
4. Record one 60-90 second demo of the Closed-Loop pipeline.
5. Link README → demo video → factory page → preprint (once preprint exists).

That sequence passes the 'one-frame claim' test.

<!-- flux-drive:complete -->
