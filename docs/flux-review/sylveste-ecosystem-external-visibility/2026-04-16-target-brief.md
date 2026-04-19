---
artifact_type: flux-review-target
review_method: flux-review
slug: sylveste-ecosystem-external-visibility
date: 2026-04-16
quality: max
tracks: 4
---

# Target Brief — Sylveste External Visibility Prioritization

## The Question Under Review

**Ruthless prioritization pathway to get Sylveste on the radar of the technically serious AI community (researchers, framework builders, senior practitioners, tool-builders) as efficiently and effectively as possible. Focus on what we should ship / polish / cancel to maximize legibility, adoption, and external signal — not internal completeness.**

Reviewers: your job is not to catalog everything Sylveste has. Your job is to apply your lens and identify:

1. **What is the single most legible wedge** — the one artifact, claim, or demo that most efficiently earns a second click from a technically serious reader encountering Sylveste cold?
2. **What should be polished vs shipped vs cancelled** — for each track, name specific items in the inventory below that either (a) deserve polish-to-publishable now, (b) should ship in unfinished form because the claim is strong enough, or (c) should be cancelled/deprecated/hidden because they dilute the signal.
3. **What positioning or sequencing move would unlock the most attention per unit of work** — the single highest-leverage external-facing action.

Avoid generic startup/open-source advice. Apply the distinct lens of your role.

---

## What Sylveste Is (Factual Inventory)

Sylveste is an open-source autonomous software-development agency platform. Currently v0.6.229 on the path to v1.0. The project was renamed from "Demarch" in March 2026. All repos live at `github.com/mistakeknot/*`. License: MIT.

### Tagline in README

> A monorepo for building software with agents, where the review phases matter more than the building phases, and the point is not to remove humans from the loop but to make every moment in the loop count.

### Install story

One curl-to-bash command. ~2 min power-user install, ~30 min full platform. Prereqs: jq, Go 1.22+, git. Optional: Python 3.10+, Node 20+, yq v4.

### Architecture — Three Layers, Six Pillars, Cross-Cutting Systems

**Layer 1 (Kernel):**
- **Intercore** — Go CLI `ic`, SQLite-backed durable kernel. Runs, phases, gates, dispatches, events. Mechanism, not policy. "Every `ic` invocation opens the database, does its work, and exits." Separate GitHub repo.

**Layer 2 (OS + drivers):**
- **Clavain** — opinionated agent rig. Phases (brainstorm → strategy → plan → execute → review → ship), gates, model routing, dispatch. Ships today as a Claude Code plugin. Separate GitHub repo.
- **Skaffen** — sovereign Go agent runtime. Standalone binary, OODARC loop, multi-provider. Auraken's intelligence layer (lens library, style fingerprinting, profile generation) is migrating into Go packages within Skaffen.
- **Zaka / Alwe** — universal CLI agent driver split: Zaka (steering), Alwe (observation). Epic in progress.
- **Ockham** — L2 factory governor. Intent → dispatch weights, algedonic signals (Stafford Beer VSM tier 1/2/3), graduated authority. Observation bridge to Alwe just shipped.
- **Interspect** — agent performance profiler + routing optimizer. Reads kernel events, proposes routing overrides, runs canary windows. The *only* cross-cutting evidence system currently at operational maturity (M2+).

**Layer 3 (Apps):**
- **Autarch** — TUI apps: Bigend (monitoring), Gurgeh (PRD generation), Coldwine (task orchestration), Pollard (research).
- **Intercom** — multi-runtime AI assistant bridging Claude, Gemini, Codex.
- **Auraken, Khouri, interblog, intersite, Meadowsyn** — additional app surfaces.

**Companion plugins (Interverse, ~64 modules):** intercache, intercept, interchart, intercheck, intercraft, interdeep, interdeploy, interdev, interdoc, interfer, interfluence, interflux, interform, interhelm, interject, interkasten, interknow, interlab, interlearn, interleave, interlens, interline, interlock, interlore, intermap, intermem, intermix, intermonk, intermux, intername, internext, interop, interpath, interpeer, interphase, interplug, interpub, interpulse, interrank, interscout, interscribe, intersearch, interseed, intersense, intership, intersight, intersite, interskill, interslack, interspect, interstat, intersynth, intertest, intertrace, intertrack, intertree, intertrust, interwatch, interweave, tldr-swinton, tool-time, tuivision, and others. 18 of these ship MCP servers.

**Cross-cutting evidence systems** (most are M0-M1, early):
- Interspect (profiler) — operational
- Ockham (governor) — early
- Interweave (ontology) — early, "generative ontology graph" epic in progress
- Interop (integration) — Go daemon replacing interkasten, Phase 1 executing
- Factory Substrate + FluxBench (measurement) — planned

### Two brands, one architecture

- **Sylveste** (SF-literature register, from Reynolds' *Revelation Space*) — infrastructure: kernel, OS, plugins, CLI. For developers and platform builders.
- **Garden Salon** (organic register) — the experience layer where humans and agents think together on shared projects. CRDT shared state is stigmergic. Not yet publicly launched.
- **Meadowsyn** (bridge) — Donella Meadows + Cybersyn. Real-time systems visualization. Domain registered at meadowsyn.com, Cloudflare.
- **inter-\*** (neutral register) — ~64 companion plugins.

---

## Distinctive Claims (the parts that could earn external attention)

These are the non-obvious claims in MISSION.md and PHILOSOPHY.md. They are either the wedge or they are noise:

1. **"Infrastructure unlocks autonomy, not model intelligence."** The bottleneck for agent capability is infrastructure — durability, coordination, feedback loops. Better plumbing → better agents.
2. **"Review phases are where the leverage is."** Most agent tools skip brainstorm, strategy, spec. Clavain makes these first-class. Thinking phases > building phases.
3. **"Every action produces evidence. Evidence earns authority. Authority is scoped and composed."** A recursive flywheel. Receipts, not narratives. Content-addressed, replayable.
4. **"OODARC, not OODA."** Boyd's OODA extended with two phases: Reflect (extract the lesson) + Compound (persist it as calibration that changes future behavior). Reflect without Compound is journaling; Compound without Reflect is cargo-culting.
5. **"Wired or it doesn't exist."** The completion bar for any feature is: code exists AND is wired to a runtime trigger AND emits evidence AND that evidence feeds calibration. Shipping steps 1-2 without 3-4 is "the most common form of incomplete work in agent-built codebases."
6. **"Progressive trust ladder (L0–L5)."** Human delegation is a dial, not a binary. Each level requires demonstrated safety at the previous level.
7. **"Graduated authority as mechanism (M0–M4)."** Subsystem maturity scale with pre-specified evidence thresholds, evidence-epoch resets when environment shifts.
8. **"Disagreement between models is the highest-value signal."** Agreement is cheap (consensus bias). Disagreement drives the learning loop.
9. **"Sparse topology in multi-agent collaboration (Zollman effect)."** Fully-connected agent networks converge faster but to worse answers. Default to sparse/ring topologies.
10. **"Self-building: Sylveste builds Sylveste with its own tools."** Trust-earning mechanism + transparency artifact + "agent friction IS the signal for technical debt."
11. **"Pre-1.0 means no stability guarantees. Premature stability commitments freeze wrong abstractions."**
12. **"Composition over capability (Unix heritage)."** Keep splitting plugins. Each plugin does one thing well.

The 4-stage Closed-Loop pattern is operationalized (hardcoded defaults → collect actuals → calibrate from history → defaults become fallback), with an existence proof: the `estimate-costs.sh` pipeline that reads interstat historical actuals and writes calibrated estimates back.

---

## Current Public Surface

**Public repos:**
- `mistakeknot/Sylveste` — the monorepo
- `mistakeknot/intercore` — L1 kernel
- `mistakeknot/Clavain` — L2 agent rig
- `mistakeknot/interagency-marketplace` — plugin marketplace
- `mistakeknot/Autarch` — L3 TUI apps
- Plus intermute, interbase, interbench, interband

**Public artifacts inside the monorepo:**
- `README.md` — install + what-you-get + architecture table + philosophy pointer
- `MISSION.md` — one paragraph + two-brand framing
- `PHILOSOPHY.md` — long doc with all 12 distinctive claims above
- `AGENTS.md` — agent development guide, links out to topic guides
- `docs/sylveste-vision.md` — v5.0 vision doc with flywheel diagram + capability mesh
- `docs/roadmap-v1.md` — parallel track model (Autonomy / Safety / Adoption), version gates
- `docs/guide-power-user.md`, `docs/guide-full-setup.md`, `docs/guide-contributing.md`
- `docs/cujs/*`, `docs/canon/*` (plugin-standard, doc-structure), ~30 PRDs, ~100 brainstorms

**Interactive ecosystem diagram** at mistakeknot.github.io/interchart/ — shows plugin/skill/agent/MCP graph.

**No public artifacts currently:**
- No landing page, no blog, no Twitter/X account, no HN submission, no tweet thread
- No recorded demo (no video, no screencast, no screenshots)
- No benchmark result published externally
- No blog post on any distinctive claim
- No academic paper (even as a preprint)
- No talk, podcast, or conference mention
- No Show HN, no Lobsters post, no Reddit discussion
- `garden salon` / `meadowsyn.com` — domain registered, not launched

---

## Current Velocity / Resource Context

- **One principal developer** (the user). Sylveste is self-built using its own agents.
- **Currently v0.6.229** marching to v1.0. Three tracks: Autonomy (A), Safety (B), Adoption (C).
  - Current levels: A ≈ L2, B ≈ L1, C ≈ L0. v0.7 gate needs A:L3 + B:L2 + C:L1.
  - v1.0 requires all three tracks at L4.
- **Cost baseline:** $2.93/landable change (Mar 2026 baseline, 785 sessions).
- **Bead tracker (`bd`) records every task.** The self-building loop runs constantly.
- **Most cross-cutting evidence systems are M0–M1.** Only Interspect is operational.
- **Garden Salon is not yet public.** Meadowsyn has a domain but no site.

## The Ruthless-Prioritization Constraint

The user does not have bandwidth to:
- Launch a marketing campaign
- Maintain a blog cadence
- Attend conferences
- Build a community team
- Polish 58 plugins for public consumption

The user CAN:
- Write one blog post per week, at most
- Record one demo video
- Post once to HN / Lobsters / X
- Polish 1–2 subsystems to publishable quality
- Cancel / deprecate / hide anything that dilutes signal

## What "External Signal" Means Here

The audience is *technically serious readers who evaluate AI/agent infrastructure for a living*. They skim fast. They have seen every framework pitch. They are allergic to "we built a platform" slideware. They respond to:

- A reproducible benchmark result with a novel method
- A working demo that shows a non-obvious capability
- A sharp concept or primitive (e.g. "wired or it doesn't exist," "OODARC Compound step," "progressive trust ladder") used to frame a real artifact
- A blog post that teaches them something they didn't know
- A codebase whose README gets out of the way and shows the specific thing

They do *not* respond to:
- "We're building the Linux of AI agents"
- Marketing-register claims without receipts
- Monorepos where the first 10 minutes don't produce a value moment
- 64-plugin inventories

---

## What Reviewers Should Produce

For each finding, be specific about:

- **Which part of the inventory** (a specific pillar, plugin, claim, doc, diagram, etc.)
- **Verdict:** ship / polish / cancel / sequence-later / hide
- **Why** (framed in your lens)
- **Severity** (P0 blocks external attention / P1 required for v1.0 positioning / P2 quality dilution / P3 polish)
- **Concrete action** the user could take this week

Prioritize *legibility per unit of work*. Ruthlessly. Most findings should be subtractive (what to cancel, what to hide) rather than additive (what else to build). The goal is not more Sylveste — it is the *visible* Sylveste.
