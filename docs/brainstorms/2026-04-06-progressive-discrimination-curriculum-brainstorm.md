---
artifact_type: brainstorm
bead: sylveste-uais
stage: discover
---

# Progressive Discrimination Curriculum for Auraken

## What We're Building

A system that uses Forge Mode calibration findings (near-miss lens pairs, distinguishing questions, lens stacks, contraindications) to build users' problem-structure recognition ability over time. The calibration data becomes a curriculum, not an internal routing table. Auraken presents distinguishing questions to users as Socratic dialogue, tracks their discrimination ability, and graduates them through increasing difficulty — functioning as a systems-thinking consultant that trains the user's eye, not a chatbot that applies frameworks on their behalf.

## Why This Approach

### Evidence base

- **12-model Forge stress test**: 454 contested lens pairs identified from daily_dilemmas dataset. 30 top pairs enriched with distinguishing questions and contraindications. 16 stress tests: 12 RESOLVED (DQ correctly discriminated), 4 PARTIAL (lens-stack scenarios needing sequential application).
- **4-track flux-review** (16 agents across adjacent, orthogonal, distant, esoteric domains): 6 cross-track convergences, all pointing toward "calibration as curriculum."

### Cross-track convergences (ranked by confidence)

1. **Calibration data is a curriculum, not a routing table** (4/4 tracks). Sommelier discrimination training, OD consulting capacity-building, Keju civil examinations, sommelier client development. Present DQs to the user — their answer IS the cognitive work.

2. **Lens stacks are reference-frame inversions, not additive filters** (3/4 tracks). Etak navigation (canoe stationary, islands move), Venetian glassblowing (irreversible gather transforms), lens-stack sequencing. Each lens redefines the problem, not adds analysis.

3. **User development ladder is missing** (3/4 tracks). OD consulting milestones, sommelier progressive palate, Keju xiucai-to-jinshi progression. Track DQ resolution rates. Graduate from high-contrast to near-identical pairs.

4. **Concealment depth should be calibrated per-user** (3/4 tracks). Ethiopian Wax-and-Gold (8 Qene forms with varying concealment depth), consulting conversation model, organ registration voicing. Replace binary invisible/visible with graduated disclosure.

5. **Near-miss pairs have emergent combinatorial properties** (2/4 tracks). Organ registration (two stops that clash as solos produce rich composite), Etak (reference frame shifts create new spaces). Near-miss pairs may be powerful in combination, not just hazardous.

6. **Pacing/annealing between lens phases** (2/4 tracks). Physical therapy (between-session practice), glassblowing (annealing prevents thermal stress). Don't rush lens stacks.

### Alignment with Auraken principles

- **Camera not engine**: DQs reveal problem structure; user does the recognition
- **Preserve cognitive struggle**: Graduated difficulty ensures challenge without frustration
- **Questions are the product**: DQs are literally the product
- **Anti-dependency**: Track and celebrate user's growing independence
- **Invisible lenses, discoverable on request**: Wax-and-gold depth model replaces binary toggle

## Key Decisions

### 1. DQs are user-facing, not internal-only

The distinguishing questions surface in conversation as Socratic prompts. The user's answer navigates lens selection. Auraken doesn't select silently — it coaches the user to see the structural difference.

### 2. Three-depth disclosure model (Wax-and-Gold)

- **Deep gold** (early): Embody the lens without naming it. Ask questions that ARE the framework without meta-language.
- **Shallow gold** (intermediate): Name the lens after the user has already applied it. "What you just did has a name — Chesterton's Fence."
- **Wax** (advanced): Teach the vocabulary directly. "This looks like a Trilemma. Which constraint would you sacrifice?"

### 3. Lens stacks as phase transitions, not checklists

Each lens in a stack redefines the problem. Auraken makes transitions explicit: "Your answer just changed what this problem is about." The output of Phase N is the input redefinition for Phase N+1.

### 4. Difficulty ladder from stress test data

Order the 30 enriched pairs by discrimination difficulty using Forge test results as signal. RESOLVED pairs (12) are "easy" — high-contrast pairs for beginners. PARTIAL pairs (4) are "hard" — subtle distinctions for advanced users. Track user resolution rates to advance.

### 5. Judicial holdings format for DQs

Structure each DQ as: operative condition ("When the constraints are structural...") + rationale ("...because rejecting real constraints leads to magical thinking...") + scope ("...use Trilemma, not Kobayashi Maru"). Makes DQs durable and independently revisable.

## Open Questions

1. **How to measure user discrimination ability** without explicit testing that breaks the conversational flow. The sommelier model uses blind tastings — what's the analog for problem-structure recognition?

2. **What's the MVP scope?** Full curriculum system or just surfacing DQs in conversation as a first step?

3. **How does this interact with OODARC?** DQ presentation likely maps to the Orient phase. Lens stack transitions map to nested OODARC loops. Needs concrete integration spec.

4. **Compensatory pattern detection**: When a user consistently avoids certain problem types (always picks Trilemma, never engages Reckoning vs. Judgment), how aggressively should Auraken challenge that?

5. **Near-miss composition**: Should Auraken ever deliberately apply two near-miss lenses together? Under what conditions? The organ registration insight suggests yes, but needs testing.

## Source Material

- `apps/Auraken/data/calibration/near_miss_analysis.json` — 30 enriched pairs
- `apps/Auraken/data/calibration/near_miss_forge_ready.json` — DistinguishingFeature records for 19 lenses
- `apps/Auraken/data/calibration/forge_stress_test_log.jsonl` — 16 stress test entries
- `docs/research/flux-review/auraken-systems-consultant-approaches/2026-04-06-synthesis.md` — full synthesis
- `apps/Auraken/VISION.md`, `apps/Auraken/PHILOSOPHY.md` — design principles
