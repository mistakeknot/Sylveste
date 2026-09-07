# fd-cooperage-stave-tension — Findings

**Lens:** Allier-forest tonnelier. Mechanism: a barrel holds liquid only because iron hoops apply continuous radial compression across every stave. Adding staves past the minimum viable count does not increase capacity — it reduces reliability by introducing fissure surface and distributing hoop tension across more interfaces. The fix for a bowed stave is removal, not repair.

## Findings Index

- P0 — Six pillars at equal visual weight exceed the minimum-stave count for one principal developer's output
- P1 — 64-plugin Interverse enumeration in public inventory dilutes the containment hoop
- P1 — Two brands + bridge brand = three staves where the barrel holds with one
- P2 — Claims #11 (pre-1.0) and #12 (composition over capability) are redundant staves
- P2 — Three-layer architecture framing is structurally redundant with six-pillar framing
- P3 — "Inter-\*" naming convention amplifies stave count cognitively

## Verdict

**Ship 3 staves: intercore + Clavain + Interspect. One truss-hoop claim: "Wired or it doesn't exist."** Remove all other pillars, layers, plugin enumerations, and brand registers from the external barrel. Keep them internally; strip them from the public face.

## Summary

The Sylveste public barrel currently presents 3 layers × 6 pillars × ~5 cross-cutting evidence systems × 64 plugins × 3 brand registers. That is, geometrically, a barrel built at ~80-stave count around a hoop that must compress one principal developer's velocity and one operational evidence system (Interspect). The minimum viable count for this capacity is 3 staves. Every stave past that number reduces reliability of the containment claim.

The technically-serious reader's 60-second fissure test is: "Which of these load-bearing pieces would I actually inspect to verify the thesis?" The answer must exist. Currently the reader has no way to identify it — the barrel shows too many staves. They will conclude the barrel is hollow and walk away before finding the one stave that holds (Interspect's closed-loop).

## Issues Found

### P0-1: Six pillars presented at equal visual weight

- **File:** `README.md` architecture section (brief lines 38-55, restated as the public README format)
- **Failure scenario:** On a single principal developer's velocity ($2.93/landable-change baseline, 785 sessions over ~6 weeks), six L2 pillars cannot carry equal radial tension. Clavain ships today. Intercore ships today. Skaffen is migrating-in. Zaka/Alwe is an in-progress epic. Ockham is early. Interspect is operational. A serious reader reading this list applies the 60-second fissure test — visits two or three of the six GitHub repos — and will find empty READMEs, stale last-commit dates, or sparse test coverage on at least three of the six. The containment claim ("we built an OS") cracks at the first inspected empty stave.
- **Smallest viable fix:** README lists **two** L2 pillars: Clavain and Interspect. Add a single sentence: "Skaffen, Zaka/Alwe, and Ockham are under development and not yet part of the public surface." Remove the three-layer / six-pillar table. Radial tension is now compressed across staves that can all bear it.

### P1-1: 64-plugin Interverse enumeration at README or architecture-level prominence

- **File:** Brief line 55 (the full list of ~64 plugin names); CLAUDE.md references "58 Interverse plugins" in the kernel summary
- **Failure scenario:** The technically-serious reader sees the plugin inventory and performs pattern recognition: "a platform that ships 64 modules where I have seen the pattern of 'the first 5 do the actual work.'" They will not audit all 64 — they will assume 55 of them are empty or vestigial, which is structurally correct (most are M0-M1 per brief line 57). The enumeration is extra-stave accumulation: every plugin past the minimum raises fissure probability of the whole barrel without adding containment. The response is "I cannot tell what this project actually is."
- **Smallest viable fix:** Do not enumerate plugin names in any public surface. Replace with: "Sylveste is extensible via companion plugins; see the marketplace for available extensions." Move the full list behind a `docs/marketplace/` link. The external face presents a barrel with uniform staves; plugins are interior fittings, not load-bearing.

### P1-2: Three-brand framing (Sylveste + Garden Salon + Meadowsyn)

- **File:** `MISSION.md` (brief lines 64-69)
- **Failure scenario:** The brand-register split ("SF-literature register" + "organic register" + "bridge") is presented as load-bearing identity architecture when Garden Salon has no public artifact and Meadowsyn has only a registered domain. The technically-serious reader reads register theory, clicks through to verify the bridges, finds empty pages, and concludes this is aspirational branding scaffolding rather than shipped identity. Two of three staves are hairline-fissured — visible to the cooper but not (yet) to the external observer; they will crack under first pressure.
- **Smallest viable fix:** One brand on the external face: Sylveste. Delete Garden Salon + Meadowsyn references from MISSION.md and PHILOSOPHY.md. Keep internal notes, but do not surface them until one of the two has a live artifact carrying load.

### P2-1: Redundant claim-staves in PHILOSOPHY.md

- **File:** PHILOSOPHY.md, specifically claims #11 ("Pre-1.0 means no stability guarantees") and #12 ("Composition over capability (Unix heritage)")
- **Failure scenario:** These are standard open-source positioning statements. Every mature open-source project has a pre-1.0 disclaimer; every Unix-heritage project cites composition. They exert no radial tension the reader has not already felt from other projects, and they dilute attention from the novel claims (#4 OODARC, #5 Wired or it doesn't exist, #7 graduated authority M0-M4). Including them on the public claim-list is extra-stave accumulation in the claim-hoop.
- **Smallest viable fix:** Remove claims #11 and #12 from the public face. They survive correctly in contribution docs or internal engineering guides, where they belong.

### P2-2: Three-layer framing structurally redundant with pillar framing

- **File:** Brief lines 38-53; architecture language in README
- **Failure scenario:** "Three layers (kernel/OS/apps) with six pillars distributed across them" is doubly-indexed containment scaffolding: layer identity plus pillar identity. Pick one. Currently both are presented, which means the reader must hold two orthogonal taxonomies in working memory before they know what the project does — every additional scaffolding axis past the first is extra-stave geometry.
- **Smallest viable fix:** Choose layers (most standard, most legible) or pillars (more specific, more project-distinctive). Keep one; remove the other from public surface. Recommend layers, because "kernel + rig + apps" maps to reader mental models already.

## Improvements

### P3-1: `inter-*` naming convention amplifies cognitive stave count

- **Observation:** 60+ plugins sharing the `inter-` prefix trigger name-blindness in skimmers. The reader cannot distinguish `intercache` from `intercept` from `interchart` on first read; they collapse into a blurred mass. The prefix was designed for coherent family identity but presents as visual repetition of stave count.
- **Fix:** On any external-facing list (if plugins are listed at all), group by function rather than name prefix: "Knowledge: intercache, interknow, intersearch. Review: interflux, interscribe. Observability: interspect, interwatch." The family naming is fine internally; externally, group by load-bearing role.

## Deliverable

### Minimum-stave Sylveste (the 3-stave barrel)

- **Stave 1 — intercore (L1):** Go CLI `ic`, SQLite-backed durable kernel. Mechanism-not-policy. One sentence of what it does. One code snippet of `ic` in action.
- **Stave 2 — Clavain (L2):** Opinionated agent rig with phased execution. One sentence. One screenshot or command-transcript showing the brainstorm→strategy→plan→execute→review→ship loop.
- **Stave 3 — Interspect (cross-cutting):** The one operational evidence system. One sentence. One link to a published override-rate trend or canary report.

### Truss-hoop claim (the one statement that compresses all three staves)

**"Wired or it doesn't exist."** This claim cross-stretches intercore (kernel events as evidence substrate), Clavain (phases as wiring points), and Interspect (evidence-to-calibration feedback loop). It is the single claim whose tension is felt across every kept stave.

### Staves to drop from the public face (not cancelled internally — just not surfaced)

1. Skaffen (L2) — still migrating in
2. Zaka/Alwe (L2) — epic in progress
3. Ockham (L2) — early
4. Autarch TUI apps (L3) — non-core to the wedge
5. Intercom, Auraken, Khouri, interblog, intersite, Meadowsyn (L3) — dilute the barrel
6. All ~58 remaining Interverse plugins (link to marketplace, don't enumerate)
7. Three-layer architecture framing (keep pillars OR keep layers, not both)
8. Two-brand register framing (Sylveste + Garden Salon + Meadowsyn)
9. Cross-cutting evidence systems Ockham/Interweave/Interop/Factory-Substrate/FluxBench (M0-M1, surface later)
10. PHILOSOPHY claims #11 and #12 (standard OSS positioning, no distinctive tension)

**Note:** Dropping staves from the external face does not cancel them internally. The cooper is not demanding the developer stop building Ockham or Skaffen — only that these staves not appear in the barrel presented to customers until they carry radial tension.

<!-- flux-drive:complete -->
