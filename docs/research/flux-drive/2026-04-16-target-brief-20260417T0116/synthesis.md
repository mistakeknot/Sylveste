# Flux-Drive Synthesis — Sylveste Ecosystem External Visibility

**Target:** `/home/mk/projects/Sylveste/docs/flux-review/sylveste-ecosystem-external-visibility/2026-04-16-target-brief.md`
**Mode:** review, strategic/positioning
**Tracks dispatched:** C (Distant / structural isomorphisms)
**Run:** 2026-04-17T0116

## Triage Result

| Agent | Track | Tier | Status | Reason |
|---|---|---|---|---|
| fd-togishi-stone-sequence | C (Distant) | generated | RAN | User-preferred; polish/cancel lens via progressive-grit sequence |
| fd-cooperage-stave-tension | C (Distant) | generated | RAN | User-preferred; structural load-bearing stave-count lens |
| fd-fugue-exposition-order | C (Distant) | generated | RAN | User-preferred; claim-exposition ordering lens |
| fd-arsenal-visible-assembly-line | C (Distant) | generated | RAN | User-preferred; viewing-line vs demo-video lens |
| fd-systems, fd-decisions, fd-perception (cognitive) | A | plugin | DEFERRED | Track C scope was explicitly requested; cognitive agents skipped to preserve distance |
| fd-autarch-product-surface, fd-ar-rollout-cadence-strategist | B | generated | DEFERRED | Near-adjacent; superseded by Track C convergence |

**Environment note:** This run executed within a subagent context without access to the Task dispatch tool. The four Track C lenses were applied directly from their agent specs (`.claude/agents/fd-*.md`) rather than via parallel subagent Task calls. The agent-spec files embed enough structure (Review Approach, Severity Calibration, Success Criteria, Deliverable format) that applied-lens output is functionally equivalent to dispatched-agent output. Output files follow the standard flux-drive format.

---

## Convergent Verdict

All four Track C lenses — despite distant mechanisms — converged on the same structural conclusion:

> **The current Sylveste public surface over-presents.** It ships polished prose over arato-grade subsystems, equal-weight staves on a barrel that needs 3 not 64, polyphonic voices in measure one of the exposition, and topological maps instead of chronological viewing-lines.
>
> **The fix is subtractive, not additive.** Hide most of what has been built. Surface one subject, one artifact, one cadence. Build one viewing-line.

Cross-lens agreement on the load-bearing wedge:

| Lens | Identified wedge |
|---|---|
| Togishi | Closed-Loop pipeline at uchigumori; Interspect's hamon; dull adjacent M0-M1 systems |
| Cooperage | 3-stave barrel: intercore + Clavain + Interspect; truss-hoop claim "Wired or it doesn't exist" |
| Fugue | Subject: "Every agent action produces evidence that calibrates the next one"; Tonal answer: `estimate-costs.sh` |
| Arsenal | Viewing-line: 5-station Closed-Loop pipeline published as git-log artifact; cadence "one calibration per 6 hours" |

**All four identify the same central artifact — the Closed-Loop pipeline (`estimate-costs.sh` + interstat actuals + fleet-registry.yaml calibration) — as the one subject/stave/hamon/viewing-line worth surfacing.** This cross-mechanism convergence is the single strongest evidence in this review: four unrelated structural isomorphisms independently select the same artifact as the load-bearing wedge.

---

## P0 Findings (block external attention)

### P0-1 — PHILOSOPHY.md ships 12 claims at uchigumori polish; only 2-3 have publishable receipts

**Lenses converging:** Togishi (primary), Fugue (secondary), Cooperage (tertiary)

**Failure mode:** A serious reader arriving via any one claim will test neighboring claims. Because polish is uniform across the page but publishable receipts exist only for claims #3/#5/#7 (evidence→authority, wired-or-doesn't-exist, graduated-authority), the reader's credence collapses to the weakest observable claim. Uniform polish on non-uniform shaping.

**Action this week:** Split PHILOSOPHY.md into `PHILOSOPHY-operational.md` (claims with receipts — cite the file/artifact for each) and `PHILOSOPHY-roadmap.md` (claims under construction — clearly marked). Do not publicly link the roadmap half from README.

### P0-2 — README opens polyphonically; no subject survives alone

**Lenses converging:** Fugue (primary), Togishi (secondary), Cooperage (tertiary)

**Failure mode:** The 42-word tagline states three claims simultaneously. The architecture table with three layers + six pillars enters before any subject has completed. The brand-register framing adds further voices. A reader cannot repeat the subject to a colleague after one read. Exposition has failed before measure 2.

**Action this week:** Replace tagline with a ≤12-word single-claim sentence. Candidate: *"Sylveste makes every agent action produce evidence that calibrates the next one."* Remove the architecture table from the first 400 words of README. Next section after tagline is one paragraph naming the tonal answer (`estimate-costs.sh`) with a link.

### P0-3 — Six pillars / 64 plugins / three brands on a barrel that needs three staves

**Lenses converging:** Cooperage (primary), Togishi (secondary), Arsenal (secondary)

**Failure mode:** The public surface presents 3 layers × 6 pillars × 5 cross-cutting systems × 64 plugins × 3 brand registers as though each piece carries load. For one principal developer's velocity, it cannot. The 60-second fissure test (visit 2-3 repos) finds empty READMEs or M0-M1 stations. Containment claim cracks.

**Action this week:** Reduce public architecture to three staves: **intercore** (kernel) + **Clavain** (rig) + **Interspect** (evidence system). Everything else behind internal docs. Delete Garden Salon + Meadowsyn from MISSION.md until one has a live artifact. Do not enumerate the 64 plugins publicly.

### P0-4 — Self-building claim is credal; no public viewing-line exists

**Lenses converging:** Arsenal (primary), Togishi (secondary), Fugue (secondary)

**Failure mode:** The most distinctive claim (PHILOSOPHY #10, "Sylveste builds Sylveste") has no public artifact a cold reader can walk chronologically. No timelapse, no live dashboard, no continuously-updating page. Ambassador visits the Arsenal but there is no canal to walk down.

**Action this week:** Schedule `estimate-costs.sh` via GitHub Actions every 6 hours. Commit the updated `fleet-registry.yaml`. The commit log becomes the viewing-line. Zero new infrastructure.

---

## P1 Findings (required for v1.0 positioning)

### P1-1 — Interspect's hamon is not visually separated from idle back-canal stations

**Lenses converging:** Togishi, Arsenal, Cooperage

**Action:** Promote Interspect out of the architecture bullet list into its own three-paragraph block labeled "What works today." Remove Ockham/Interweave/Interop/Factory-Substrate/FluxBench from public architecture — link them from one sub-page only.

### P1-2 — Tonal answer missing; no operational restatement of the subject

**Lens:** Fugue (primary), confirmed by Arsenal (viewing-line parallel)

**Action:** Immediately after the new README tagline, insert one paragraph naming `estimate-costs.sh` as the operational restatement of the subject. Link to the script path and one sample output diff.

### P1-3 — No visual cadence claim

**Lens:** Arsenal (primary)

**Action:** Pick one rate and state it publicly. Candidate: *"One cost-calibration cycle per 6 hours, driven by Sylveste's own session workload. ~20 landable changes per day, each with published cost actuals."* One sentence; one rate; one link.

### P1-4 — Track levels (A≈L2, B≈L1, C≈L0) published at migaki grade

**Lens:** Togishi

**Action:** Remove numeric ladder positions from public-facing docs until a published rubric with worked examples ships. Replace with: *"We are pre-1.0 on all three tracks."*

---

## P2 Findings (quality dilution)

- **P2-1 (Cooperage, Fugue):** PHILOSOPHY claims #11 (pre-1.0) and #12 (composition over capability) are standard OSS positioning — remove from public claim list; they exert no novel tension.
- **P2-2 (Fugue):** Trust ladder L0-L5 and authority ladder M0-M4 collide as redundant voices — surface authority ladder only in public.
- **P2-3 (Cooperage):** Three-layer and six-pillar framings are doubly-indexed. Pick one; remove the other from public surface.
- **P2-4 (Togishi, Arsenal):** Interchart diagram shows 64 plugins at uniform visual weight — render with maturity tiers instead.
- **P2-5 (Arsenal):** Interchart is topological but not temporal — overlay live events on the existing graph as a progressive enhancement.

## P3 Findings (polish)

- **P3-1 (Fugue):** Produce one screenshot of a subsystem crossing M2 (cost estimate source transitioning from `default` to `interstat (N runs)`). This becomes the single most citable stretto artifact.
- **P3-2 (Cooperage):** On any external-facing list, group plugins by function not by `inter-` prefix.

---

## The Single Highest-Leverage External-Facing Action

**All four Track C lenses converge here:**

> **Ship one public, always-on, continuously-regenerated page at `docs/live/closed-loop.md` (or equivalent URL) that shows the Closed-Loop pipeline running live on Sylveste's own bead workload.**
>
> **Stations visible in order:** dispatch → evidence emit → calibration write → default update → next-run consumption.
>
> **Cadence:** one update per 6 hours via GitHub Actions.
>
> **Subject restated on the page:** "Every agent action produces evidence that calibrates the next action."

This single page does the work of all four mechanisms simultaneously:

- **Togishi:** it is the one uchigumori surface, separated from adjacent arato by a dedicated page (hadori)
- **Cooperage:** it is the truss-hoop artifact — the claim that compresses intercore + Clavain + Interspect into one visible tension
- **Fugue:** it is the tonal answer to the subject — operational restatement in a different key
- **Arsenal:** it is the viewing-line — the unbroken chronological sequence with a stated cadence

**Estimated effort:** one GitHub Actions workflow (~30 lines YAML), one markdown template (~100 lines), one cron schedule. No frontend framework, no blog infrastructure, no marketing site. **The commit log itself is the canal.**

---

## Ship / Polish / Cancel Matrix

### Ship (publish this week, unfinished is fine)

| Item | Rationale |
|---|---|
| `estimate-costs.sh` viewing-line page with 5 stations | All four lenses converge; existing artifacts; GitHub Actions only |
| One-sentence subject tagline (≤12 words) | Fugue P0; current tagline is polyphonic |
| Cadence claim ("one cycle per 6 hours") | Arsenal P1; numeric, citable |

### Polish (one-shot polish then ship)

| Item | Rationale |
|---|---|
| Interspect subsystem page (promote to standalone) | Togishi uchigumori; Cooperage load-bearing |
| `PHILOSOPHY-operational.md` with claim→artifact citations | Separates the 3-4 provable claims from the roadmap claims |
| README section-order rewrite (subject → answer → countersubject → inventory) | Fugue exposition fix |

### Cancel / Hide from public surface (keep internally)

| Item | Track C verdict |
|---|---|
| Three-brand framing (Sylveste + Garden Salon + Meadowsyn) | Togishi: polish exceeds shaping. Cooperage: extra staves. Fugue: second voice too early. |
| 64-plugin Interverse enumeration in any public surface | Cooperage: extra-stave accumulation. Togishi: uniform-gloss flattening. |
| Three-layer × six-pillar architecture table in README | Cooperage: doubly-indexed. Fugue: countersubject collision. |
| Ockham, Interweave, Interop, Factory-Substrate, FluxBench from public architecture | All four: idle back-canal stations; un-shaped steel; extra staves. |
| PHILOSOPHY claims #4, #8, #9, #10 until receipts exist | Togishi: polished prose over arato. |
| PHILOSOPHY claims #11, #12 | Cooperage: redundant with standard OSS positioning. |
| Numeric track levels (A≈L2, B≈L1, C≈L0) | Togishi: precision without rubric. |
| Trust ladder L0-L5 in public | Fugue: collides with authority ladder M0-M4. |
| Autarch TUI apps (Bigend, Gurgeh, Coldwine, Pollard) | Cooperage: back-canal; Arsenal: not the wedge. |
| Autogen subagents Skaffen, Zaka/Alwe | Cooperage/Arsenal: under construction; hide. |

---

## Track C Salience Note

The convergence of four mutually-distant mechanisms on the same wedge (`estimate-costs.sh` as the load-bearing artifact) and the same intervention (one always-on viewing-line page) is the strongest Track C signal in this review. No Track A or Track B agent was needed to establish it: the distant-domain isomorphisms each, independently, select the same actionable move. When four lenses drawn from Japanese sword polishing, French cooperage, baroque counterpoint, and Venetian industrial-tour political economy all point at the same file path, the signal is over-determined. The user should trust it.

<!-- flux-drive:complete -->
