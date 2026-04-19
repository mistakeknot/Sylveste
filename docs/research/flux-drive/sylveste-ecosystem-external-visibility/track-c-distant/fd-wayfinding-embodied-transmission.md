# Track C — Wayfinding Embodied Transmission

**Lens:** Caroline Islands pwo navigator. A wayfinding tradition lives or dies by whether each apprentice completes a **witnessed first voyage** — a landfall observed by elders. Star-compass pebble diagrams rehearsed on land; etak reference-island held abeam; chants encode directions as rhythmic checklists; pwo-initiation lineage traces each navigator to a founding master. A tradition with no witnessed voyages is a rumor.

## TL;DR

Sylveste's tacit knowledge — claim-the-bead, write-the-receipt, close-and-sync, review-phases-matter — is encoded almost entirely as prose in PHILOSOPHY.md, AGENTS.md, and the canon docs. There is **no star-compass pebble-diagram rehearsal surface** (no hosted playground, no toy project), **no reference-island worked example** (`apps/` has Meadowsyn which is research-phase-only, Autarch which is TUI-only, no "empty-repo-to-receipts" demo), and most critically **no witnessed-first-voyage definition or mechanism** — the project cannot name a single external adopter who has run a sprint end-to-end, produced a receipt, and been acknowledged as a voyager. The self-building claim (PHILOSOPHY.md:286 "Clavain builds Clavain") is the *project's own* voyage — that is not the pwo mechanism. The pwo mechanism requires a second canoe, a new apprentice, and an elder on the shore. **L2 (OS + Drivers) deserves Stage 2** because L2 is where the tacit knowledge (phase discipline, plugin composition, bead-receipt rhythms) actually lives and where first-voyage witnessing would be cheapest to define: "run `/clavain:project-onboard` on an empty repo, produce one bead-close, tweet the receipt" is a concrete minimum landfall.

## Findings

### P0 — No witnessed-first-voyage mechanism for external adopters (the tradition is self-sailed)

The pwo mechanism: a student becomes a navigator only after completing a landfall **observed by elders**. Sylveste has zero apparatus for this:

- No "first sprint completion" celebration or acknowledgement mechanism
- No external-adopter counter, no named-adopter list, no witnessed-landfall registry
- No Discord / GitHub-discussions / mailing list where an external user could announce "I ran my first Clavain sprint, here is my bead receipt"
- `docs/sylveste-vision.md:352-357` names "three concentric circles" (Platform, Proof by demonstration, Personal rig) — all three are *internal* audiences. The "Proof by demonstration" circle is explicitly self-building: `rsj.1 — the autonomous epic execution track`. Not an external-adopter mechanism.

AGENTS.md:3 declares "Open-source autonomous software development agency platform" — but the only voyages visible in the codebase are Sylveste's own (1,456 beads tracked, 1,239 closed, per vision.md:370). Every receipt is internal. Every voyage is the master's own. No student has made a witnessed landfall.

The pwo elder knows: a tradition with no external apprentices is not yet a tradition — it is a personal practice.

**Failure scenario:** Six months from now, an AI-lab researcher reads Sylveste's "64 plugins, 1,456 beads" claim and asks "who besides the founder is using this?" There is no answer. The infrastructure works, the thesis is coherent, but the transmission has not happened — which is the exact P0 scenario in the agent's severity calibration. The tradition remains self-sailed no matter how good the canoe.

**Smallest viable fix:** Define a minimum-landfall artifact: `/clavain:project-onboard` run in an empty repo, produces a bead-close event with receipts in `.beads/backup/issues.jsonl`. Publish `docs/first-voyages.md` as a running list of external adopters who have produced that artifact (self-attestation + git SHA of their receipt). One doc, one commit per voyage. The mechanism is lightweight; the missing piece is the *definition* of what counts as landfall.

### P0 — No pebble-diagram rehearsal surface (no on-land compass practice)

The pwo apprentice memorizes the 32-house star compass on land, with pebbles, **before any voyage**. Sylveste offers no equivalent:

- `docs/guide-power-user.md` assumes Claude Code is installed and working (line 4 explicit prerequisite) — not a rehearsal surface, a committed voyage
- `docs/guide-full-setup.md` requires Go 1.24+, Node 20+, Python 3.10+, jq, tmux — five prerequisites before first contact
- There is no hosted playground (no `try.sylveste.dev`, no Docker image, no binder/colab notebook)
- `install.sh` downloads and installs the full platform — it is the first voyage, not the rehearsal
- `docs/canon/plugin-standard.md` describes what a plugin must look like — but there is no "pretend plugin" demo where an external reader can trace the 6-pillar × 3-layer structure without committing to an install

The mechanism: pebble diagrams let apprentices internalize the 32-house compass before the ocean tests them. Sylveste asks external readers to go straight to the ocean.

**Failure scenario:** An academic researcher wants to understand the Clavain phase chain (brainstorm → strategy → plan → execute → review → ship) to write a comparative paper. They read PHILOSOPHY.md and guide-power-user.md but cannot *try* the phases without installing Claude Code + Go + jq and running `/clavain:project-onboard`. The rehearsal surface is missing; they write about the phases from prose-only reading, which produces misunderstanding.

**Smallest viable fix:** Create `docs/walkthroughs/empty-repo-to-first-receipt.md` — a narrated-screenshots pebble-diagram of a full voyage. Not runnable, but shows exactly what each command outputs. This is the minimum rehearsal surface: the pilot can trace the voyage mentally before committing to install. Effort: 2 hours of narration + screenshots of an existing session.

### P1 — Tacit patterns are prose-only, never chant-level (no memorable short sequences)

Sylveste's durable patterns should be carriable in working memory under load. They are not. Examples of patterns that exist only as prose:

- `PHILOSOPHY.md:56-63` "Closed-loop by default" — four stages (hardcoded defaults → collect actuals → calibrate from history → defaults become fallback). Named, numbered, but not chant-compressed. A practitioner under load will not recall "four-stage calibration pattern" — they will forget one stage. The pwo chant-mechanism would compress this to a 4-word sequence: e.g. `default, collect, calibrate, fallback` — memorable under stress.
- `PHILOSOPHY.md:77` "Wired or it doesn't exist" — this one IS chant-compressed (5 words). This is the exemplar for what the other patterns should look like.
- `AGENTS.md:93-114` "MANDATORY WORKFLOW" — 7 numbered steps, 22 lines of prose. A practitioner will execute 4 of the 7 from memory. The chant compression: `file, gate, close, push, clean, verify, handoff` (7 words).
- Memory notes shows the user already chants some patterns: `claim-the-bead, write-the-receipt, close-and-sync` — three compressed phrases that work. But these are *in user memory*, not in the public docs.

The pwo mechanism: chants encode sailing directions as rhythmic sequences. Memory notes has the chants; public docs do not.

**Failure scenario:** External adopter runs a sprint, hits the reflect-phase gate (PHILOSOPHY.md:56 4-stage calibration pattern), cannot recall which stage they are missing, gives up and ships without closing the loop. The infrastructure works but the pattern-under-load fails because the prose was too long to carry.

**Smallest viable fix:** Add a `## Chants` section to AGENTS.md and PHILOSOPHY.md with the 5-10 compressed sequences. Pull the compressions from memory file (already in working memory of the founder). One doc-sweep.

### P1 — No reference-island worked example (dead-reckoning adoption)

The pwo etak mechanism: a third island held imagined-abeam, whose relative motion gives the navigator their position. The adopter equivalent: a complete worked-example project showing "empty repo → project-onboard → first bead → first sprint → first reflection → first landed change" with every receipt visible.

Searched:
- `apps/Meadowsyn/` — web viz frontend, research-phase only (CLAUDE.md:13 "Research phase complete"), not a worked example of using the Sylveste stack
- `apps/Autarch/` — TUI for kernel state, for people already deep in the system
- `apps/Intercom/` — Rust/Postgres multi-runtime assistant
- `apps/interblog/`, `apps/Khouri/`, `apps/intersite/` — each is a product, not a demo
- No `examples/` directory at the root

There is no "here is what a first-time Sylveste voyage looks like, replayable, with all the receipts visible" artifact. Adopters voyage on dead-reckoning — they install, they try something, they have no reference against which to check their progress.

**Failure scenario:** Practitioner developer installs Sylveste via `install.sh`, runs `/clavain:project-onboard` on their own codebase, sees it do a lot of things, but has no "this is what it should have done" reference. They cannot tell whether their onboarding is healthy. They give up because their dead-reckoning provides no confirmation.

**Smallest viable fix:** Create `examples/hello-sylveste/` — a complete repo-in-a-repo showing the full voyage from empty → first-shipped-change, with the bead/session/reflection artifacts committed. Reference-island that adopters can hold abeam. Effort: 4 hours to record a real session and commit the artifacts.

### P2 — No pwo-initiation lineage (no named voyagers to trace)

The pwo mechanism: each navigator traces their teaching back through named masters. Sylveste has the founding master (arouth1@gmail.com, per env context) but no visible lineage — no "apprentices of Sylveste" roster, no contributor recognition beyond git commits, no named human whose trust-ladder progression is visible.

The vision doc § Audience (line 344-357) names audiences in the abstract but no named person. The memory file notes the user's long-term goal ("major name in AI/agent space") — but there is no externally-visible second-voyager whose adoption the platform has witnessed.

This overlaps with the repertoire agent's "named-soloist première" mechanism but differs: the pwo lineage is about *teaching chain*, the repertoire première is about *commissioning event*. Different mechanisms, adjacent gap.

**Observation not urgent:** First fix the witnessed-first-voyage mechanism (P0 above); lineage builds on top of it. Cannot trace a lineage that has not yet had its first apprentice.

## Wave-Refraction Reading: Externally-Readable Health Signals

The pwo detects unseen islands by reading swell refraction. Can a distant observer read Sylveste's health without insider access?

| Signal | Readable externally? | Source |
|---|---|---|
| Commit velocity | yes | `git log` (public) |
| Plugin version bumps | yes | marketplace.json on GitHub |
| Bead close rate | **no** (local Dolt) | P0 above — would fix with public bead-snapshot pages |
| Cost-per-landable-change | **no** (local cass/interstat) | high-value signal, completely invisible externally |
| Gate pass rate | **no** (local kernel events) | invisible externally |
| External-adopter count | **no** (does not exist) | P0 above — would fix with first-voyages.md |

Four of six health signals are invisible to a distant observer. The pwo mechanism is largely broken — a distant observer cannot tell whether Sylveste is thriving, coasting, or stalled. Cross-references the scriptorium agent's P0 about external-citable receipts.

## Wayfinding-Transmission Audit

For each of Sylveste's core tacit claims: is there (a) pebble-diagram, (b) reference-island, (c) first-landfall, (d) witnessing, (e) chant-encoding?

| Core tacit claim | Pebble-diagram | Reference-island | First-landfall | Witnessing | Chant |
|---|---|---|---|---|---|
| composition-over-capability | none | none | none | none | partial (PHILOSOPHY.md:120 heading only) |
| review-phases-matter | none | none | none | none | none — "brainstorm → strategy → plan → execute → review → ship" is 6-word prose |
| receipts-earn-authority | none | none | none | none | partial (memory: "write-the-receipt") |
| close-the-loop | none | none | none | none | partial (memory: "close-and-sync") |
| wired-or-doesn't-exist | none | none | none | none | **yes** — PHILOSOPHY.md:77 is chant-compressed |
| infrastructure-unlocks-autonomy | none | none | none | none | partial |
| self-building-as-proof | none | **yes** (Sylveste itself) | n/a (internal-only) | n/a | none |

The only tacit claim with a reference-island is self-building — and it is the project's own self-reference, which the pwo mechanism does not count (a navigator who sails in circles is not witnessed). The only chant-compressed pattern is "wired or it doesn't exist." Five of seven columns are near-empty.

## Transmission-Leverage Ranking

Gaps ranked by how much adoption-probability each mechanism unlocks:

1. **Witnessed first-voyage definition** — P0. Highest unlock: defines what counts as adoption. Without it, no other mechanism can fire. Lowest effort: one markdown doc + first-voyages list.
2. **Reference-island (`examples/hello-sylveste/`)** — P1. High unlock: adopters gain the etak against which to check their progress. Medium effort: record a real session, commit artifacts.
3. **Chant compression of 5-10 core patterns** — P1. Medium unlock: patterns carry under load. Low effort: one doc-sweep pulling from founder's working memory.
4. **Pebble-diagram walkthrough** (narrated screenshots) — P1. Medium unlock: readers can trace the voyage without installing. Low effort: 2-hour narration.
5. **External health signals** (public bead snapshots, cost-per-change page) — P2. Slow unlock: distant observers can infer health. Overlaps with scriptorium-agent P0; same diff fixes both.

## Stage-2 Layer Recommendation

**Layer for Stage 2: L2 (OS + Drivers) — specifically the Clavain sprint lifecycle and the 64-plugin composition surface.**

Questions answered:

- **Which layer's tacit knowledge is most transmissible today?** L1 (Intercore) — it is one Go binary with SQLite, one `--help` away from legibility. The mechanism is simple enough that chant-encoding is trivial (`runs, phases, gates, dispatches, events`).
- **Which layer has the largest gap between insiders and outside voyagers?** L2 — the sprint lifecycle (brainstorm → ship), the phase gates, the plugin composition patterns. These are the patterns the founder runs daily from memory and that are invisible to outsiders without a rehearsal surface.

The specific transmission gap in L2: **the Clavain sprint** has no pebble-diagram, no reference-island, no first-landfall definition, no witnessing mechanism. Fix L2 first because L2 is where adopters would *actually spend most of their time* after install — the kernel (L1) is opaque-and-fine-like-a-database, apps (L3) are interfaces over L2 logic. L2 is the ocean the voyager sails.

**Justification in one sentence:** L2 carries the review-phases-matter thesis — the most novel claim in Sylveste — and currently transmits it through 4,000 lines of prose and zero witnessed voyages, so any increase in embodied-transmission mechanisms at L2 has an outsized unlock on whether the thesis propagates beyond the founding crew.

## Concrete Actions

1. **Define first-landfall + publish the first-voyages list.** Create `docs/first-voyages.md`: the minimum-landfall definition ("`/clavain:project-onboard` on an empty repo + one bead closed + one reflection artifact"), the submission mechanism (PR adding your entry), and the running list. Seed with one synthetic entry documenting the founder's own first voyage as the master's reference mark. (Effort: 1 hour. Unlock: the pwo mechanism can now fire at all.)

2. **Commit `examples/hello-sylveste/` as the reference-island.** Record a real `/clavain:project-onboard` session on a fresh repo, commit all artifacts (bead backup JSONL, session transcript, reflection doc), document the voyage in a README. This is the etak adopters hold abeam. (Effort: 4 hours. Unlock: dead-reckoning adoption becomes referenced-adoption.)

3. **Add `## Chants` section to PHILOSOPHY.md and AGENTS.md.** Compress the 5-10 core patterns from prose into 3-7-word sequences: `default, collect, calibrate, fallback` | `brainstorm, strategy, plan, execute, review, reflect, ship` | `claim, receipt, close, sync` | `wired or doesn't exist` | `receipts, not narratives` | `evidence earns authority` | `composition over capability`. Pull compressions from the founder's working memory (memory file). (Effort: 1 hour. Unlock: patterns carry under load.)
