# Track C — Portolan Cartography Legibility

**Lens:** 14th-c. Genoese portolan chart-maker. A chart is judged by whether a foreign pilot can make first landfall alone, in fog, at night, with no one to ask. Named ports first; decorated interior last; sea-monsters only over genuine blanks; every copy carries the scribe-colophon.

## TL;DR

Sylveste's public cartography is a beautiful interior map with barely any named coast. The README opens with a thesis ("review phases matter more than building phases") and a flywheel, then jumps to installation, then offers a 5-pillar table where only **5 of the 64 interverse/ directories** are named. An AI-lab researcher cannot look at the public surface and locate any of the 64 harbors by purpose. The three brand registers (Sylveste / Garden Salon / inter-*) exist without the sea-monster convention — speculative apps (Garden Salon MVP, Meadowsyn) are presented on the same coastline as shipped infrastructure (Intercore, Clavain) with no visual status marker. Plugin-count numerals contradict across surfaces: README says "55+", AGENTS.md says "58", vision doc says "~64", roadmap table shows 55 active — this is a portolan with four different scales engraved on the same chart. **L2 (OS/Drivers) deserves Stage 2** because a single named-port enumeration of the 64 plugins with one-line purposes would collapse the first-landfall distance from "read five docs and triangulate" to "read one table and pick a harbor."

## Findings

### P0 — No named-port enumeration for the 64 Interverse plugins (first-landfall mechanism failure)

`/home/mk/projects/Sylveste/README.md:76-93` presents architecture as a 5-row pillar table + a diagram link, then says "All plugins are installed from the interagency-marketplace." **The 64 interverse/ directories** (confirmed by `ls /home/mk/projects/Sylveste/interverse/ | wc -l` = 64) are not named anywhere on the landing surface. A foreign pilot who wants to use `interflux` for multi-agent review, `tldr-swinton` for code context, or `interlock` for file coordination — the three plugins PHILOSOPHY.md explicitly names at line 133 as standalone exemplars — cannot discover from README that these exist, let alone what they do.

The portolan mechanism says: name every harbor around the coast *before* depicting any interior. Sylveste's README has the interior (thesis, flywheel, philosophy) richly painted and the coast nearly blank. `docs/sylveste-roadmap.md:85-150` carries the one-line ecosystem table — but it is buried in a roadmap doc, not on the landing surface, and the table's "Status" column reads `early / active / planned` without explaining what "early" means to a pilot trying to decide whether to dock.

**Failure scenario:** An AI-lab researcher arrives via a Twitter link, reads the README in 90 seconds, and leaves. They saw "55+ companion plugins" and a broken-link promise ("interactive ecosystem diagram"). They cannot cite Sylveste in a paper because they cannot name a single plugin with a one-line description. The marketing surface blocks the chart-reading surface.

**Smallest viable fix:** Add a §What's in Interverse section to README between "Architecture" and "Plugin ecosystem" — a 64-row table with columns `name | one-line purpose | status (M0-M4) | layer`. Source of truth: `docs/sylveste-roadmap.md:85-150`, re-keyed. Estimated 40 minutes to generate from the existing table plus plugin.json descriptions.

### P0 — Plugin-count disagreement across four surfaces (chart has four different scale bars)

Four public surfaces publish different plugin counts:
- `README.md:44` — "55+ companion plugins ... 43 installed by default, 14 optional"
- `README.md:82` — "51 companion plugins"
- `AGENTS.md:3` — "58 Interverse plugins, 18 with MCP servers"
- `docs/sylveste-vision.md:86,376` — "~58 more" and "64 companion plugins, 81 total modules"
- Actual count: `ls interverse/ | wc -l` = 64

The portolan mechanism says: a chart with two scale bars is not a chart — it is a rumor. An outside researcher reads README (55+), opens AGENTS.md (58), and opens the vision doc (64) and discovers the platform does not know its own coastline. This damages the "evidence earns authority" thesis asymmetrically: if Sylveste cannot count its own plugins consistently, the receipts claim weakens before any technical scrutiny begins.

**Failure scenario:** A reviewer at an AI lab checks three documents in 10 minutes (standard due-diligence) and finds three different totals. They conclude the platform is pre-stabilization and deprioritize it — not because it is pre-1.0 (PHILOSOPHY.md:197 openly admits that), but because the internal accounting disagrees with itself.

**Smallest viable fix:** Add a single generated source of truth — `docs/ecosystem-manifest.json` generated from `interverse/*/plugin.json` — and make all four surfaces cite it by transclusion or with the exact same integer. One bash script, checked by CI.

### P1 — No sea-monster convention separating Sylveste / Garden Salon / Meadowsyn registers

`MISSION.md:5` and `docs/sylveste-vision.md:21-31` declare three brand registers. PHILOSOPHY.md:224 enforces language separation ("Garden-salon language... does NOT appear in kernel docs"). But on the public landing surface:

- Garden Salon has zero shipped code (vision doc: "Horizons... depends on Interop M2, Interweave M2, Ockham M2")
- Meadowsyn has an experiments/ directory with 18 sketches (`apps/Meadowsyn/experiments/`) but the CLAUDE.md (26 lines total) says "Research phase complete... Architecture (Proposed)"
- Intercore has "8 of 10 epics shipped" and is operationally M2 (vision doc line 162)

These three live on the same coast with the same typographic weight in README.md:76-86 (pillar table) and vision.md §The Stack. The portolan mechanism says: decorative monsters go **only** over genuinely unknown regions — so the pilot knows where the known coast ends. Sylveste paints both coastlines the same color.

**Failure scenario:** A researcher cites Garden Salon's stigmergic CRDT claim (vision.md:249 cites arxiv.org/abs/2601.08129) in a paper, attempts to examine the implementation, discovers it does not exist, and publishes a correction. Reputation cost is asymmetric — the correction travels further than the original citation.

**Smallest viable fix:** Add a `Status:` row to every pillar and app in the README architecture table with one of four tokens: `Shipped (M2+) | Operational (M1) | Built (M1) | Planned (M0)`. Populate from vision.md:159-170 (Current Mesh State table) — the data already exists, it just isn't on the landing page.

### P1 — No periplus keyed to the chart (docs/canon/ and docs/guides/ are freestanding essays)

The portolan mechanism pairs chart + pilot-book (periplus); neither is usable without the other. `docs/canon/plugin-standard.md` and `docs/canon/doc-structure.md` are excellent interior essays — but they reference bead IDs (`iv-ho3`, `Sylveste-6i0`), internal paths (`os/Clavain/scripts/install-codex-interverse.sh`), and abandoned experiments (Demarch, Hermes pivot) without a glossary keyed to the public chart.

Example: `docs/guide-full-setup.md:75` references `bash os/Clavain/scripts/install-codex-interverse.sh install` — but `os/Clavain/` is capitalized while AGENTS.md:34 says "All module names are lowercase... Pillar directories use proper casing (`os/Clavain/`, `apps/Autarch/`). Never create lowercase duplicates." A foreign pilot who types `os/clavain/` (lowercase) hits a script-not-found error with no pointer to the convention.

**Failure scenario:** Practitioner developer follows Full Setup Guide, hits case-sensitivity issue on step 4, gives up. This is the exact scenario Memory notes warn about ("we rebuilt... when CASS was already assessed as 'adopt'") — but inverted: the docs assume insider knowledge that is documented only in commit history.

**Smallest viable fix:** Add a 10-line "Pilot Glossary" section to CONTRIBUTING.md (currently 23 lines, plenty of room) that defines: bead ID format, pillar casing rule, `ic` vs `bd` vs `clavain-cli`, Sylveste vs Garden Salon vs inter-\*. First-landfall pilots stop here before reading canon.

### P2 — No rhumb-line diagram connecting pillar → layer → plugin entrypoint

README.md:91 links `https://mistakeknot.github.io/interchart/` for an "interactive ecosystem diagram." This is the rhumb-line mechanism: 16-wind compass rose overlaid on harbors. But:

1. The diagram is an external dependency (GitHub Pages) — if it 404s during a reading session, the chart has no compass rose at all
2. No static fallback diagram is in the README itself
3. The diagram is not exportable in a paper figure or a screenshot that would travel in a slide deck

The PHILOSOPHY.md:147 principle says "The current decomposition (6 pillars, 3 layers) reflects where we are, not a permanent structure." A single svg/mermaid showing the 6-pillar × 3-layer × ~64-plugin arrangement with rhumb-lines (pillar → plugin → slash-command entrypoint) would be the canonical chart.

**Smallest viable fix:** Add a Mermaid diagram to README.md §Architecture showing the 6 pillars, 3 layers, and named entrypoints per pillar (e.g. `Clavain → /clavain:route`, `Interflux → /interflux:flux-drive`). 30 lines of mermaid, no external dependency.

## Coast-Audit Table

For each externally-visible doc, classify sections as **harbor** (named entrypoint), **rhumb-line** (navigable connection), **sea-monster** (admitted unknown), or **uncharted-interior** (prose-only).

| File | Section | Classification |
|------|---------|----------------|
| README.md | §Quick start | harbor (one entrypoint: install.sh) |
| README.md | §What you get | uncharted-interior (prose, no named plugins) |
| README.md | §Architecture table | harbor (5 pillars named) — but only 5 of 64 plugins are legible |
| README.md | §Plugin ecosystem | uncharted-interior (points to external diagram) |
| README.md | §Troubleshooting | harbor (6 named failure modes) |
| MISSION.md | full doc | uncharted-interior (1 page thesis, no names) |
| PHILOSOPHY.md | §Composition Over Capability | rhumb-line (names interlens/interlock/interkasten/tldr-swinton as standalone exemplars) |
| PHILOSOPHY.md | §Brand Registers | rhumb-line (good — names the three registers explicitly) |
| AGENTS.md | §Quick Reference | harbor (bash commands) |
| AGENTS.md | §Topic Guides | rhumb-line (links to 10 topic files) |
| CONTRIBUTING.md | whole doc | rhumb-line (short, points to guide-contributing.md) |
| install.sh | --help block | harbor (4 named flags) |
| docs/sylveste-vision.md | §Capability Mesh | harbor (10 subsystems named with maturity) — best chart in the project |
| docs/sylveste-vision.md | §Two Brands | sea-monster MISSING (brand status not marked shipped vs planned) |
| docs/sylveste-roadmap.md | §Ecosystem Snapshot | harbor (64-row plugin table) — but buried; should be on landing page |
| docs/canon/plugin-standard.md | whole doc | periplus (great sailing directions, but not keyed to visible chart) |
| docs/solutions/INDEX.md | whole doc | harbor (73 docs by subproject) — per plugin, adequate |

## Top-Three Harbors to Label This Month

Rank by "which plugin's labeling would most shorten first-landfall for an external AI-lab researcher":

1. **interflux** — already the most-cited plugin across docs (vision.md:376, roadmap §Review engine), and the public-facing entry to the "589 review agents" claim. If one harbor proves the composition thesis, this is it. README.md today has zero mention. Label with: `interflux — multi-agent code review: triages agents, dispatches in parallel, synthesizes findings. Validates the "review phases matter" thesis.` File: `interverse/interflux/README.md:1` exists but is invisible from the landing surface.
2. **interspect** — the "assay office" (vision.md:223). Operating at M2 and the only evidence system that already closes the loop. Without labeling it, the "evidence earns authority" thesis has no public receipt. Label with: `interspect — agent performance profiler: reads kernel events, proposes routing overrides, operates at M2. The flywheel's current closed loop.`
3. **intercore** — the kernel. PHILOSOPHY and vision ground everything here but the README architecture table only says "orchestration kernel: runs, dispatches, gates, events" — four nouns. Label with the 5 nouns plus the survival property from vision.md:61-66: `intercore (ic) — Go CLI + SQLite database. If everything above disappears, the kernel and its receipts survive.`

## Stage-2 Layer Recommendation

**Layer for Stage 2: L2 (OS + Drivers).**

Reason in one sentence: L2 is where 64 of the 64 interverse plugins + Clavain + Skaffen live, and it is the layer whose named-port density is closest to zero on the public chart — so the legibility ROI of one Stage-2 deep-dive is maximal. L1 (kernel) is already adequately labeled in both README and vision.md (it is one binary, one database — naturally a single harbor). L3 (Apps) has only two members (Autarch, Intercom) and is not the bottleneck. **L2 is the continent with 64 unnamed harbors — Stage 2 should produce the single canonical plugin-manifest table that resolves the 55+ / 58 / 64 contradiction and becomes the README's §What's in Interverse section.**

## Concrete Actions

1. **Generate `docs/ecosystem-manifest.json`** from `interverse/*/plugin.json` (name, version, description, status-inferred-from-roadmap, mcp-server-present). Wire into README.md as a rendered markdown table. Single source of truth for the plugin count. (Effort: 2 hours. Owner: scripts/ directory.)

2. **Add §Status column to the README Architecture table** (README.md:76-86) using the four-token scale (Shipped / Operational / Built / Planned) sourced from vision.md:159-170. Same column added to `/home/mk/projects/Sylveste/docs/sylveste-roadmap.md` ecosystem table. Eliminates the sea-monster-convention gap. (Effort: 30 minutes.)

3. **Create `docs/ecosystem-chart.md`** — a static mermaid diagram showing 6 pillars × 3 layers × top-20 plugins with slash-command entrypoints. Link from README.md §Architecture as the static fallback for the external interchart diagram. (Effort: 1 hour. Diagram text: 40 lines.)
