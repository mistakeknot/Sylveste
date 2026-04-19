# fd-togishi-stone-sequence — Findings

**Lens:** Honami-lineage togishi; progressive stone sequence (arato → binsui → kaisei → chu-nagura → koma-nagura → uchigumori → hazuya → jizuya → nugui → migaki). Mechanism: finishing grit on un-shaped steel *creates* the scratch; hadori is the act of deliberately dulling adjacent surfaces so the intended hamon shows cleanly.

## Findings Index

- P0 — Polish-grade prose over M0 steel (PHILOSOPHY.md)
- P0 — Three brands shown at uchigumori-equivalent presentation while two have no hamon yet (MISSION.md "two brands" + Meadowsyn bridge)
- P1 — Interspect's hamon is un-hadori'd (no adjacent dulling)
- P1 — Roadmap tracks named at A:L2/B:L1/C:L0 published at migaki-finish while only Interspect has reached kaisei
- P2 — Interchart diagram presents 64 plugins at uniform hazuya gloss
- P3 — README tagline has migaki verbal polish with arato structural claim

## Verdict

**Hold 9 of the 12 distinctive claims from public surface until their referent subsystems pass kaisei.** Promote Interspect + Closed-Loop pipeline (`estimate-costs.sh`) to uchigumori. Dull everything adjacent.

## Summary

The Sylveste public surface has been polished at nagura-to-migaki grit across documents whose underlying subsystems are still at arato. Every unreinforced PHILOSOPHY claim is a light-catching scratch — not because the claim is wrong, but because the finishing stone's own geometry reveals how un-shaped the steel is beneath. A technically-serious reader does not infer "the claim is bold," they infer "every claim on this page is similarly under-constructed."

The single surface at genuine uchigumori stage is the Closed-Loop existence proof: `estimate-costs.sh` reading interstat actuals, writing calibrated estimates back. That is hamon-revealing work. But it sits visually flat with Ockham (early), Interweave (early), Interop (Phase 1), and Factory Substrate + FluxBench (planned) in the same architecture table — the reader cannot see the edge line.

## Issues Found

### P0-1: PHILOSOPHY.md ships all 12 claims at uchigumori-prose grade

- **File:** `PHILOSOPHY.md` (referenced in target brief lines 73-91)
- **Failure scenario:** Reader arrives via a link to claim #5 ("Wired or it doesn't exist") — a genuinely sharp claim with receipts possible via interstat. On the same page they read claim #10 ("Self-building: Sylveste builds Sylveste") which requires a viewing-line artifact that does not exist publicly, and claim #8 ("Disagreement between models is highest-value signal") which requires either published benchmarks or a running peer-comparison trace, neither of which ships externally. The reader's credence on *all* claims collapses to the weakest observable one.
- **Smallest viable fix:** Move claims 1, 2, 5, 7, and 10 into a new `PHILOSOPHY-operational.md` that cites the specific artifact/file/path confirming each one. Leave claims 4, 6, 8, 9, 11, 12 in a separate `PHILOSOPHY-roadmap.md` clearly marked "under construction." The single file at current prose grade is finishing grit applied uniformly.

### P0-2: Three-brand / two-register framing (Sylveste + Garden Salon + Meadowsyn) published at strategic-positioning grade

- **File:** `MISSION.md` (brief lines 64-69); `docs/sylveste-vision.md`
- **Failure scenario:** Reader sees "Sylveste (SF register) + Garden Salon (organic register) + Meadowsyn (bridge)" and immediately performs the test: click `meadowsyn.com`. Site does not exist. Click for Garden Salon public surface. Does not exist. The framework has been described at migaki polish; two of the three brands have arato-level public surface (domain registered only). The polish calls attention to the absence.
- **Smallest viable fix:** Remove Garden Salon and Meadowsyn from MISSION.md entirely until one of them has a live page. A one-brand statement with a working artifact beats a three-brand statement with two missing artifacts. The hadori move: deliberately dull these two references so Sylveste alone shows the edge line.

### P1-1: Interspect's hamon is not separated from un-shaped adjacent steel

- **File:** Brief lines 44-48 (architecture table); PHILOSOPHY.md claim #7 (graduated authority M0-M4)
- **Failure scenario:** Interspect is the one cross-cutting evidence system at M2+ — the only one whose closed-loop is demonstrable. In the architecture table it is listed fifth, after Clavain/Skaffen/Zaka-Alwe/Ockham, adjacent to Interspect's own less-mature neighbors. A reader scanning the table does not see "here is the one that works." They see "six equally-weighted bullet points." The uchigumori surface is not differentiated from the arato surfaces around it; no edge line visible.
- **Smallest viable fix:** Promote Interspect out of the bullet list. In the README architecture section, write a separate three-paragraph block: "What works today: Interspect reads kernel events, proposes routing overrides, runs canary windows, and has a published override-rate trend. This is the single M2+ cross-cutting system." The hadori move: remove Ockham/Interweave/Interop/Factory-Substrate/FluxBench from the public architecture table entirely and list them under a `docs/roadmap-cross-cutting.md` link.

### P1-2: Track-level claims (A≈L2, B≈L1, C≈L0) shown at migaki grade

- **File:** Brief lines 132-133; referenced `docs/roadmap-v1.md`
- **Failure scenario:** Publishing precise ladder positions ("A ≈ L2, B ≈ L1, C ≈ L0") on a public roadmap at v1.0 polish grade implies the evaluation rubric is calibrated and replayable. But "Currently v0.6.229" with C=L0 means there is no external-signal track operating yet. The published level is finishing-stone metadata on arato shaping — the reader infers the level numbers are aspirational, which costs more credibility than publishing no levels at all.
- **Smallest viable fix:** Collapse the three tracks to a single capability statement for public v0.6.x surface: "v1.0 requires three tracks (Autonomy/Safety/Adoption) to reach L4. We are pre-1.0 on all three; see internal roadmap for current positions." Remove the numeric levels from any public-facing doc until there is a published rubric with worked examples.

## Improvements

### P2-1: Interchart diagram at uniform hazuya gloss

- **Site:** `mistakeknot.github.io/interchart/`
- **Observation:** The interactive diagram presents 64 plugins at equal visual weight. This is hazuya-level surface treatment applied uniformly — every node reflects the same gloss, so no node stands above others. The polish effort produces flatness, not legibility.
- **Fix:** Render the diagram with three visual tiers: (1) operational (M2+), (2) in progress (M1), (3) planned (M0). Only Interspect and the L1 kernel should sit in tier 1. A reader glancing at the diagram should immediately see which 3-5 nodes carry the claim.

### P3-1: README tagline has finer prose polish than structural shaping

- **Text:** "A monorepo for building software with agents, where the review phases matter more than the building phases, and the point is not to remove humans from the loop but to make every moment in the loop count."
- **Observation:** The sentence is 42 words with three clauses and one negation. At current migaki verbal polish it reads as careful positioning prose. The underlying subject — what review-phase infrastructure actually is — has not been shaped at arato. A reader who likes the sentence still cannot say what Sylveste does. The prose reveals the shaping gap.
- **Fix:** Rewrite to 12-14 words stating the single operational claim. Example grade: "Sylveste makes agent work produce replayable evidence, then calibrates from it." One subject; no compound clauses.

## Deliverable

**Uchigumori candidate worth finishing publicly:** Closed-Loop pipeline (`estimate-costs.sh` + interstat actuals + calibrated defaults). It is the one artifact whose foundation stones are complete (kaisei reached: measurement works, calibration works, fallback works) and whose finishing would reveal the hamon — the visible shape of "evidence earns authority."

**Hadori moves (deliberately dull):**
1. Remove Garden Salon + Meadowsyn from MISSION.md until at least one has a live site.
2. Remove Ockham/Interweave/Interop/Factory-Substrate/FluxBench from README architecture table — link them from a single sub-page.
3. Remove the 64-plugin Interverse enumeration from any README-equivalent surface; link to an internal roster.

**Surfaces whose polish exceeds shaping (require regression or withdrawal):**
- PHILOSOPHY.md claims 3, 4, 8, 9, 10 (polished prose, no publishable receipt)
- `docs/roadmap-v1.md` track levels (precision without rubric)
- The three-brand register framing (two brands absent)

<!-- flux-drive:complete -->
