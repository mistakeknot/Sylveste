# Track C — Distant-Domain Structural Isomorphisms: Summary

**Task:** External-visibility prioritization for the Sylveste ecosystem targeting AI labs, academic researchers, and practitioner developers. Four agents applied far-field lenses — portolan cartography, Benedictine scriptoria, Polynesian wayfinding, and early-20th-c. European repertoire formation — each mapping a specific named mechanism to a specific Sylveste artifact.

## Cross-Agent Convergence

The four lenses converge on one diagnosis from four independent angles: **Sylveste is optimized for a powerful internal practice, not for external reception**. The four agents describe the same underlying gap with four different mechanisms:

| Lens | Named mechanism | Sylveste gap | P0 finding |
|---|---|---|---|
| Portolan | First-landfall test | No coast-walking enumeration of 64 plugins on the landing surface | Plugin count disagrees across four public surfaces (55+ / 58 / 64) |
| Scriptoria | Colophon chain | Receipts carry no external-citable shelf-marks beyond the monorepo | Beads, sessions, solution docs have no DOI-equivalent for 2029 citation |
| Wayfinding | Witnessed first-voyage | No external adopter has been acknowledged as having completed landfall | No `docs/first-voyages.md`, no minimum-landfall definition, no lineage |
| Repertoire | Second performance | No mechanism by which first adoption seeds second independent adoption | No replication kit, no teaching apparatus, no named soloist première |

These four P0s are not four independent problems. They are four views of one problem: **Sylveste's internal receipts/beads/cass/solution-docs infrastructure is rich, but none of that infrastructure is shaped for export**. Bead IDs don't resolve externally (scriptoria). The 64 plugins don't appear on the landing surface (portolan). There's no first-voyage mechanism (wayfinding). There's no second-performance path (repertoire). The receipts stack inward; the reception stack is nearly absent.

### The four agents also converge on one specific diagnostic observation

Three of four agents independently flagged the **plugin-count inconsistency** (55+ / 58 / 64) as a visible symptom:
- **Portolan** called it "a chart with four different scale bars"
- **Scriptoria** implied it in the "scriptorium rule of hands" finding about bead-prefix drift (same failure mode: local inconsistency visible externally)
- **Wayfinding** noted that external observers cannot read platform health because internal signals don't surface

Fix that single inconsistency (generate `docs/ecosystem-manifest.json` as single source of truth) and three agents' findings improve simultaneously — a high-leverage single-diff intervention.

### One mechanism no other agent catches: Meadowsyn as recording medium

The repertoire agent uniquely identifies Meadowsyn (apps/Meadowsyn/) as the under-leveraged **recording-medium anchor**. The Cybersyn ops-room-photograph traveled farther than the political program that built it; a Meadowsyn dashboard screenshot of the flywheel-in-practice could do the same for Sylveste's infrastructure thesis. None of the other three lenses can see this because it depends on the commissioning-to-recording-lag mechanism specific to canon-formation.

## Stage-2 Layer Consensus

| Agent | Layer recommendation | Reason |
|---|---|---|
| Portolan | L2 (OS + Drivers) | 64 unnamed harbors; legibility ROI maximal per diff |
| Scriptoria | L2 (OS + Drivers) | 64 manuscripts with inconsistent hands; colophon-pass cheapest per artifact |
| Wayfinding | L2 (OS + Drivers) | Sprint lifecycle is the ocean adopters sail; tacit knowledge most concentrated here |
| Repertoire | **L3 (Apps)** | Recording-medium artifacts (Meadowsyn dashboards, Autarch screencasts) live here |

**Three-of-four consensus: L2.** The portolan, scriptoria, and wayfinding agents all identify L2 as the highest-leverage Stage-2 target. They agree because L2 is where the 64 plugins live, where the sprint-lifecycle tacit knowledge lives, and where the inconsistent-hand / missing-colophon / missing-pebble-diagram / missing-reference-island gaps are all concentrated.

**Dissenting voice: Repertoire picks L3.** The dissent is substantive, not noise. L3 is the layer where *recording-medium* artifacts naturally exist — and the repertoire mechanism is fundamentally a recording-and-distribution problem, not an infrastructure problem. This dissent points at a gap the L2-focused majority misses: **fixing L2 alone would produce an excellent but invisible platform** — legible chart, citable colophons, transmissible patterns — with no recording medium to carry the message outward. The repertoire agent is saying: do L2 *and* invest proportionally in L3 recording-medium work, because a platform with every colophon in order but no dashboard screenshot on a conference slide still fails the canon-entry mechanism.

### Recommended Stage-2 scope (synthesizing the consensus and the dissent)

**Primary (L2 deep-dive):** One schema change — extend plugin-README frontmatter to include `colophon:` (scribe, date, exemplar, version, status) and `entrypoint:` (slash-command or CLI invocation) fields. This single change:
- gives the portolan agent named harbors with rhumb-line entrypoints
- gives the scriptoria agent the four-mark colophon on every plugin
- gives the wayfinding agent version-pinned reference-points
- enforced by `interscribe` (already in canon) and CI
- produces `docs/ecosystem-manifest.json` as the machine-readable source-of-truth that resolves the 55+/58/64 contradiction

**Secondary (L3 recording-medium work):** Pair the L2 schema change with one recording-medium anchor — a single Meadowsyn dashboard screenshot (or Autarch TUI screencast) published alongside a short blog post titled "The flywheel in practice." This is the première event the repertoire agent demands; without it, L2 fixes are invisible.

## Distant-Domain Mechanism Library (Track C contribution)

The four lenses surfaced **eight named mechanisms** that are specific enough to guide concrete action and far-field enough to be non-obvious to an insider:

1. **Named-port density** (portolan) — every plugin gets a one-line purpose on the landing surface before any architectural narrative appears
2. **Sea-monster convention** (portolan) — speculative/planned coastline marked distinctly from shipped infrastructure
3. **Rhumb-line network** (portolan) — pillar → plugin → entrypoint traversable in one diagram
4. **Exemplar-chain stemma** (scriptoria) — upstream-source frontmatter, not just downstream `synthesized_into`
5. **Scriptorium rule of hands** (scriptoria) — one bead-prefix, one README template, one colophon schema across all 64 plugins
6. **Witnessed first-voyage** (wayfinding) — minimum-landfall definition + public list of external adopters
7. **Chant-as-checklist** (wayfinding) — 3-7 word compressions of the 5-10 core tacit patterns
8. **Second performance** (repertoire) — replication kit that lets a second team adopt after a first demonstration

All eight are cheap individually. Five of them (named-port density, exemplar-chain, rule-of-hands, first-voyage, second-performance) can be shipped by the same Stage-2 schema + docs sweep on L2.

## Concrete Ship List (Track C consensus, ranked by leverage × inverse effort)

1. **Generate `docs/ecosystem-manifest.json`** as single source of truth for plugin count + per-plugin colophon. Resolves three agents' P0/P1 findings. (Effort: 2 hours.)
2. **Write `docs/first-voyages.md`** with minimum-landfall definition and a running list. Enables the pwo witnessing mechanism. (Effort: 1 hour.)
3. **Write `docs/replication-kit/adopt-interflux.md`** as the first second-performance artifact. Targets the canon-entry P0. (Effort: 2 hours.)
4. **Add audience-specific entry rows** to README.md §Guides: for-ai-labs.md and for-researchers.md. Resolves the oeuvre-incoherence finding. (Effort: 3 hours.)
5. **Extend plugin README frontmatter** with `colophon:` block. Single schema change fixing citability + legibility + consistency. (Effort: 3 hours + CI.)
6. **Add `## Chants` section** to AGENTS.md and PHILOSOPHY.md. Compress 5-10 core patterns from prose into carriable sequences. (Effort: 1 hour.)
7. **Record one Meadowsyn screenshot or Autarch screencast** as first recording-medium anchor. (Effort: depends on Meadowsyn readiness.)

**Total effort for items 1-6: ~12 hours.** These six ships, done together, would change the answer to every agent's P0 question from "no" to "yes" and resolve three of the four P0 findings outright.

## One-Line Takeaway

Sylveste has built an excellent internal practice and needs to build — deliberately, with specific named mechanisms from distant domains — the export infrastructure that lets that practice become visible, citable, replicable, and canon-entering outside the founding crew.
