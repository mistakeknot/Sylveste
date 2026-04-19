# Track C — Repertoire Canon Entry

**Lens:** 1920 European orchestra programming-committee director. A work enters the standard repertoire by: commissioning house of reputation (Donaueschingen, RPS), named-soloist première (Hubermann, Heifetz), **second performance by an independent ensemble within three seasons**, critical edition (Bärenreiter-style) that conservatories adopt, programmatic coherence as an oeuvre. A brilliant score with no second performance is a footnote; a competent score with ten second performances is canon.

## TL;DR

Sylveste is optimized for **brilliant première, not canon entry**. The platform has no identified commissioning houses (no AI-lab collaborations, no academic citations, no conference presentations visible in the public artifacts), no named-soloist demonstration artifact, no critical-edition-ready plugin with teaching apparatus, **and most critically no second-performance mechanism** — there is no path by which "AI lab X adopts interflux" seeds "AI lab Y adopts interflux." The three target audiences (AI labs / academics / practitioners) encounter three different surfaces (README thesis / MISSION.md / PHILOSOPHY.md) with no audience-specific entrypoint. Meadowsyn is the interesting exception: a visualization layer (Donella Meadows + Cybersyn) that, uniquely, could function as a critical-edition-equivalent because visualizations travel in slide decks and conference talks — a recording-medium advantage the kernel and plugins lack. **L3 (Apps) deserves Stage 2** because L3 is where recording-medium artifacts can exist (Meadowsyn screenshots, Autarch TUI demos) that become the première-and-second-performance substrate; shipping a critical-edition plugin (interflux) packaged with a teaching apparatus is the single highest-leverage canon-entry move.

## Findings

### P0 — No second-performance mechanism defined (the single sharpest canon-entry predictor)

The repertoire mechanism: a work enters canon only when a second independent ensemble performs it within roughly three seasons of the première. The second-performance is orthogonal to première quality — a brilliant score with zero second performances is a footnote.

Sylveste has no identified second-performance mechanism. Searched for:

- Referral path from first adopter to second (none)
- Case-study template that documents adoption replicability (none)
- Replication kit for institutional adopters (none)
- Teaching apparatus — workshop, tutorial repo, course materials (none)
- Ambassador / advocate program (none)
- Conference-talk recording / demo video (none)

The platform has extensive self-recordings (1,456 beads, cass session index) but no artifact shaped to help a *second* institution adopt what a *first* institution demonstrated. `docs/sylveste-vision.md:358-364` "Open Source Strategy" asserts ecosystem effects as the bet ("If the kernel is good enough, people will build their own agencies on top of it") — but this is the première-only mental model. The repertoire mechanism demands *active* second-performance plumbing, not passive "good enough will spread."

**Failure scenario:** An AI lab (say, Anthropic Applied Research) runs Clavain on one internal project, produces positive results, writes no replication document, loses the adoption when that team's members rotate. Six months later a different Anthropic team wants to try it and finds no internal or external replication path — they restart from README. No compounding. No second performance. The work never enters repertoire regardless of how strong the première was — this is exactly the P0 in the agent's severity calibration.

**Smallest viable fix:** Create `docs/replication-kit/` with a single artifact: `adopt-interflux.md` — a 2-page replication guide targeted at a team that has seen interflux work once and wants to run it themselves. Structure: prerequisite context (what they should already know), deployment checklist, measurement setup (what receipts to collect), evaluation criteria (how to tell it worked). One document, one plugin — but it creates the mechanism. Extend to other plugins once proven.

### P1 — Oeuvre incoherence across the three audiences (three pitches, three entry-points, no unified narrative)

The three target audiences encounter three different pitches:

- **AI labs** (vision.md:343-348, "for developers and platform builders") → pitched on **infrastructure thesis** ("the bottleneck is infrastructure, not intelligence"). Entry-point: README.md's install.sh one-liner.
- **Academic researchers** → pitched on **orchestration-beats-raw-capability** (vision.md:246-249 cites Arcgentica 36% on ARC-AGI-3). Entry-point: nowhere obvious. No `docs/for-researchers.md`. No preprint.
- **Practitioner developers** → pitched on **faster safe shipping** (`docs/guide-power-user.md:51` "disciplined lifecycle"). Entry-point: power-user guide.

Three audiences, three pitches, three entry-points. No cross-audience narrative that lets one committee's contact compound into another's. An AI lab reading the README learns the infrastructure thesis; an academic skimming vision.md learns the ARC-AGI validation; a practitioner reading the guide learns the sprint lifecycle. Each sees a different work by a different composer.

The repertoire mechanism: committees program *composers* not *pieces* — an oeuvre must read as coherent. Sylveste's oeuvre reads as: "the one with the flywheel" to labs, "the one with the 340× cost improvement citation" to academics, "the one with the disciplined phase gates" to practitioners. These are all true but the unifying oeuvre-level narrative is absent.

**Failure scenario:** An AI-lab engineer who reads the README and likes the infrastructure thesis forwards the link to an academic colleague. The colleague reads the same README and does not see anything citable — no preprint pointer, no benchmark claim, no dataset. The forward dead-ends. Two audiences touched, zero canon advancement.

**Smallest viable fix:** Add three audience-specific quickstart pointers to README.md §Guides (currently 3-row table at README.md:50-54). Add a fourth row: `For AI labs → docs/for-ai-labs.md | infrastructure thesis + replication kit | 15 min`. Add a fifth: `For researchers → docs/for-researchers.md | benchmark claims + citations | 10 min`. The current three-row table addresses Power User / Full Setup / Contributing — all practitioner-developer subdivisions. The two non-practitioner audiences have zero entrypoints.

### P1 — No named-soloist première candidate identified

The repertoire mechanism: a première by Hubermann or Heifetz creates recordable events that travel. Sylveste has no named external user, no named researcher who has run it, no named lab that has cited it publicly. The only named voyagers are internal (the founder, arouth1@gmail.com per env context).

Searched for named externals:
- `docs/sylveste-vision.md` — names Symbolica AI's Arcgentica as a *validating citation* (line 247), not as a user
- `docs/sylveste-vision.md:249` cites arxiv.org/abs/2601.08129 (stigmergy research) — a citation, not an adopter
- `README.md` — zero named externals
- `docs/brainstorms/2026-04-13-ockham-alwe-observation-bridge.md` and similar recent brainstorms — all internal
- No `docs/adopters.md`, no `docs/case-studies/`, no "Who uses Sylveste" section

The platform reads as self-played. Overlaps with the wayfinding agent's lineage finding but differs: the repertoire mechanism is about *commissioning events that travel*, not teaching chains. A named-soloist première is a one-time high-visibility event (e.g., "Anthropic's applied team uses Clavain to ship X"). A teaching chain is many small events.

**Failure scenario:** An academic writing a 2026 coding-agent survey looks for platforms with documented institutional adoption. Sylveste has 1,456 closed beads (impressive!) but no named external user. The survey omits Sylveste because "self-use is not adoption." The work doesn't enter canon because the première never happened.

**Smallest viable fix:** Reach out to one AI-lab or one academic lab willing to run a named pilot with a documented outcome. Until that exists, there is no actionable fix within the docs — this is a **business-development** gap, not a documentation gap. Flag for the founder's roadmap, not for this review cycle.

### P2 — No critical-edition-equivalent plugin with teaching apparatus

The critical-edition mechanism: a stable, editorially-curated score with teaching apparatus that a conservatory can adopt. The Sylveste equivalent: a single plugin that is version-pinned, editorially-frozen, documented for teaching, and packaged with course materials suitable for a CS department or agent-dev training program.

Candidates assessed:
- **interflux** (roadmap: v0.2.52, active) — the strongest candidate. Public-facing reviewers, multi-agent synthesis, reaction rounds. But no teaching apparatus: no workshop script, no assignment handouts, no progression-of-examples from simple to advanced. Version-pinning is continuous (0.2.52 today, 0.2.53 tomorrow) — no "critical edition v1.0 frozen for pedagogy" release.
- **interspect** (0.1.18, active) — "agent performance profiler and routing optimizer." Would require the kernel to teach effectively; not standalone.
- **tldr-swinton** — code-context plugin. Narrow-enough scope to be teachable. No course materials.

The 64 plugins are all at composer's-manuscript stage, not critical-edition stage. None has a `docs/teaching/` directory, a workshop handout, or a "cite this version when using this plugin in a course" anchor.

**Failure scenario:** A CS professor wants to include an agent-orchestration module in a graduate course. They evaluate Sylveste, find the infrastructure compelling, but cannot find any plugin pinned-and-teachable. They use a competitor's more pedagogically-ready platform. Sylveste loses the generational compounding that academic adoption enables — exactly the P2 in the agent's severity calibration.

**Smallest viable fix:** Pick **interflux** (already the most-cited plugin, already the "proof of composition thesis" exemplar). Tag a `v1.0-edition` release with: frozen code at that SHA, `docs/teaching/` containing a 3-example progression (simple review → reaction round → cross-model synthesis), a handout PDF, a "cite this edition" anchor. Effort: 8 hours. One plugin, not all 64 — critical-edition status earned by one.

### P3 — Meadowsyn is the recording-medium opportunity (under-leveraged)

The commissioning-to-recording-lag mechanism: works reach canon faster when the première is documented in a durable medium that travels (score publication, recording, radio broadcast). Sylveste's recording-medium stack:

| Medium | Status | Travels? |
|---|---|---|
| README + vision docs | shipped | yes |
| Blog posts | none visible | - |
| Conference talks / recordings | none visible | - |
| Videos / screencasts | none visible | - |
| Academic preprints | none visible | - |
| **Dashboards / real-time visualizations (Meadowsyn)** | research-phase | **yes — very well** |

Meadowsyn is uniquely positioned as a recording medium. `apps/Meadowsyn/CLAUDE.md:5` describes it as "A Cybersyn-style ops room for monitoring autonomous agent dispatch" — and Cybersyn's ops room is one of the most durable recording-medium-for-political-economy artifacts of the 20th century. Photos of the ops room traveled far beyond the regime that built it. Meadowsyn could do the same for Sylveste's flywheel claim.

But `apps/Meadowsyn/CLAUDE.md:13` says "Research phase complete... Architecture (Proposed)." The artifact is not yet shipped. The experiments/ directory (18 sketches) has many candidate visualizations but no canonical single public screenshot.

The repertoire programming-committee director would say: *take one screenshot, publish it, turn it into a conference talk*. The cost of a recording that travels is tiny compared to its leverage on canon entry.

**Observation not urgent** — depends on Meadowsyn shipping at least a static screenshot, which is blocked on upstream data sources per the CLAUDE.md. But when it ships, treat the first public screenshot as a repertoire event, not a launch announcement. Budget the recording-medium work (blog post with the screenshot, conference-talk abstract, paper figure) *before* the technical launch.

## Repertoire-Entry Audit

For each of the three target audiences:

### AI labs

| Element | Status | Location |
|---|---|---|
| Commissioning houses | none identified | — |
| Named-soloist première candidates | none | — |
| Second-performance mechanism | none | P0 above |
| Critical-edition-ready artifacts | interflux partially | partial — no teaching apparatus |
| Recording-medium outputs | README, vision.md | text-only, no video/dashboard |

### Academic researchers

| Element | Status | Location |
|---|---|---|
| Commissioning houses | none identified | — |
| Named-soloist première candidates | none | — |
| Second-performance mechanism | none | P0 above |
| Critical-edition-ready artifacts | none | P2 above |
| Recording-medium outputs | vision.md cites others' papers, no Sylveste paper | — |

### Practitioner developers

| Element | Status | Location |
|---|---|---|
| Commissioning houses | none identified (possibly Claude Code itself as hosting venue) | — |
| Named-soloist première candidates | none | — |
| Second-performance mechanism | marketplace install (passive) | roadmap:148-150 |
| Critical-edition-ready artifacts | none | P2 above |
| Recording-medium outputs | guide-power-user.md | text-only |

All three audiences score three zeros and two partials on a five-element rubric. The gap is not prioritization; it is that the repertoire-entry infrastructure is missing wholesale.

## Leverage-to-Effort Gap Ranking

1. **Second-performance mechanism** (P0) — canonical highest leverage per the repertoire mechanism. Lowest effort: one 2-page replication-kit document. **Fix first.**
2. **Audience-specific quickstart pointers** (P1) — unlocks two currently-zero entrypoints (AI labs, academics). Effort: 2 hours to write `docs/for-ai-labs.md` and `docs/for-researchers.md`, point README.md §Guides at them.
3. **interflux critical-edition release** (P2) — unlocks the generational academic-adoption path. Effort: 8 hours (frozen release + 3-example teaching handout).
4. **Meadowsyn first screenshot as recording-medium anchor** (P3, blocked) — unlocks dashboard-as-canon-artifact. Blocked on upstream. Budget the recording-medium work in parallel with the technical ship.
5. **Named-soloist première** (P1, business-dev) — requires outbound outreach to an AI lab or academic lab. Not a docs fix. Flag for the founder.

## Stage-2 Layer Recommendation

**Layer for Stage 2: L3 (Apps — specifically Meadowsyn + Intercom + Autarch).**

Questions answered:

- **Which layer is closest to a viable première-and-second-performance path?** L3. The apps are the only layer where the recording-medium problem has natural solutions: Meadowsyn produces dashboards (which travel in slide decks), Autarch produces TUI sessions (which travel as screencasts), Intercom is a multi-runtime assistant (which travels as a product demo). L1 (kernel) is a CLI — invisible in recordings. L2 (plugins) are pre-stabilization with inconsistent hands — hard to produce a critical edition of.
- **Which layer's critical edition is most teachable?** L3. A Meadowsyn screenshot on a conference slide with the flywheel claim overlaid teaches more about Sylveste's thesis in 3 seconds than 3 pages of PHILOSOPHY.md can teach in 10 minutes. The *infrastructure* thesis teaches best through the *visualization* of its outputs.

**Candidate premièrist:** A working Meadowsyn dashboard showing the current fleet's cost-per-landable-change against time, screenshotted and published alongside a blog post titled "The flywheel in practice." This is the première event — small, specific, recordable.

**Candidate second-performance mechanism:** Open-source the Meadowsyn dashboard code as a "dashboard template for your own agent factory" — a second team can clone it, point it at their own beads database, and reproduce the visualization. The second performance is: *another team's dashboard exists*.

**Justification in one sentence:** L3 is the only layer where recording-medium artifacts (dashboards, TUI screencasts, demo videos) naturally exist, and the repertoire mechanism is primarily a recording-and-distribution problem, not an infrastructure problem — so Stage 2 should deep-dive L3 with explicit attention to Meadowsyn as the first recording-medium anchor and interflux (L2) as the first critical-edition release paired alongside.

## Concrete Actions

1. **Write `docs/replication-kit/adopt-interflux.md`** — 2-page replication guide for a second team adopting interflux after seeing it work once. Structure: prerequisite context, deployment checklist, measurement setup (which receipts to collect), evaluation criteria. This is the minimum second-performance mechanism. (Effort: 2 hours. File: `docs/replication-kit/adopt-interflux.md` — new.)

2. **Add audience-specific entry rows to README.md §Guides table** (README.md:50-54). Add `docs/for-ai-labs.md` (15-min read: infrastructure thesis + Arcgentica validation + replication kit pointer) and `docs/for-researchers.md` (10-min read: benchmark claims + citable artifacts + teaching pointers). Three audiences → three entrypoints. (Effort: 3 hours total.)

3. **Tag `interflux v1.0-edition` as a critical-edition release** with frozen SHA, `docs/teaching/` containing a 3-example progression (simple review → reaction round → cross-model synthesis), and a "cite this edition" anchor (DOI-like, even if just a permalink). One plugin earns critical-edition status; the rest follow later. (Effort: 8 hours. Owner: `interverse/interflux/` repo.)
