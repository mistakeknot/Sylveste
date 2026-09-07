---
artifact_type: flux-drive-synthesis
method: flux-drive
target: docs/prds/2026-04-21-persona-lens-ontology.md
target_type: prd
date: 2026-04-21
bead: sylveste-b1ha
agents_triaged: 10
agents_ran: 10
findings_total: 18
p0: 2
p1: 7
p2: 6
p3: 3
verdict: ship-to-write-plan-with-patches
---

# Flux-Drive Synthesis — Persona/Lens Ontology PRD Review

Ten agents, eighteen findings. The PRD is a **largely faithful** translation of the 11 gates from the brainstorm review into 7 features with acceptance criteria that encode most gate language verbatim. The six focus areas surfaced two P0s (one dependency-graph correctness issue, one Epic-DoD rigor hole) and seven P1s (mostly translation-fidelity softening and one sizing problem). Scope creep is minimal; non-goals hold. Write-plan can proceed after P0 patches land in the PRD or on the affected feature beads at filing time.

## Findings Summary

| Severity | Count | Nature |
|---|---|---|
| P0 | 2 | Dependency graph missing F5→F6 edge; Epic DoD can be satisfied without measuring graph quality |
| P1 | 7 | Gate-softening (G2 regression, G5 module-gap, G10 pre-registration timing), F6 sizing, DoD #1 verification artifact, F3 coupling, Domain/Discipline decision deferral impact on F3 |
| P2 | 6 | Acceptance-criterion testability, open-question timing, non-goal scope seams |
| P3 | 3 | Minor documentation, cross-reference polish |

## Critical Findings (P0)

### P0-1. Dependency graph omits F5→F6 edge; F5 priority-P2 contradicts epic DoD

**Agents:** fd-semantic-dedup-calibration, fd-triage-lift-measurement, fd-noh-kata-canonical-form-drift (convergent)

**Finding.** The PRD's stated dependency graph per the user framing is `F3→F4→F5→F6→F7` with F6 depending on F2+F5. But the PRD text itself is ambiguous: F5 is labeled **P2** priority ("blocks F6 A/B since triage depends on graph health"), while F6 is labeled **P1** MVP. The acceptance criteria of F6 do not cite F5 as a hard precondition — they cite F2 (for `ontology-queries` scaffold) but not the calibrated same-as graph. Meanwhile Epic DoD #4 requires *"every same-as edge has source_independence set"* which can only be true after F5 runs curator promotion.

**Failure scenario.** A sprint planner reads F6 priority=P1 / F5 priority=P2 and begins F6 before F5 ships. Triage A/B runs on a graph with zero `same-as` edges (or with uncurated `candidate-same-as` only). Review-coverage-per-diff measurement is then against a **structurally incomplete** graph, and the ship/abandon decision in `f6-ab-decision.md` is made on data that cannot reflect the post-dedup steady state. G10 pre-registration was meant to prevent exactly this class of mis-measurement.

**Recommendation.** Patch PRD in two places before write-plan:
1. F5 priority → **P1 (blocks F6 A/B)**, matching its description.
2. F6 acceptance criterion: add *"F5 curator promotion pass has completed on the held-out corpus before A/B day 1; OR pre-registration doc explicitly declares the A/B runs against `candidate-same-as`-only graph and Epic DoD #4 is deferred to a post-F6 verification bead."* Pick one — do not leave ambiguous.

**Blocks write-plan?** Yes, lightly. Write-plan must know whether F5 is upstream or sibling of F6 before it can topo-sort children beads.

---

### P0-2. Epic DoD is satisfiable without positive triage lift

**Agents:** fd-triage-lift-measurement, fd-noh-kata-canonical-form-drift (primary), fd-isnad-chain-integrity (secondary)

**Finding.** Epic DoD criterion #1 says *"Triage lift is measured and positive. Per G10, the pre-registered primary metric … shows ≥ 15% improvement."* But F6 acceptance criterion allows a **ship/abandon/redesign** outcome: *"If ship: flag default flips to `ontology`; if abandon: feature closes with findings documented, epic re-evaluates."* The "epic re-evaluates" language means F6 can **close as abandon** and the epic can still close all 7 children. DoD #1 then becomes unmeasurable — it says "triage lift is measured and positive" but if F6 abandons, there is no positive lift, only a measurement-of-non-lift. DoD and F6 acceptance are inconsistent about what epic success means.

**Failure scenario.** F6 ships `f6-ab-decision.md` reading "primary metric improved 4% at 1.4x cost-per-finding → abandon per threshold." F6 bead closes (acceptance criteria met: pre-registration done, A/B ran, decision memo written). F7 ships (interlens MCP adapter works regardless of triage lift). Epic `sylveste-b1ha` has 7 closed children, but the project that was supposed to demonstrate graph-triage lift failed. Bead closer looks at DoD and is unsure: is #1 satisfied because lift was *measured* (even negatively), or unsatisfied because lift was not *positive*? Different readers close differently.

**Recommendation.** Patch Epic DoD #1 to be **falsifiable** under both branches:
- "Either: (a) F6 A/B shipped with ≥ 15% lift at constant-or-lower cost-per-finding, flag defaulted to ontology; OR (b) F6 A/B abandoned, epic abandons and is formally reopened as redesign, **DoD #1 is recorded as NOT MET** — the epic does not close via DoD."

Keep the abandon branch as a valid F6 outcome but make it a **non-closing** outcome for the epic. Otherwise the epic has an escape hatch.

**Blocks write-plan?** No, but filing the Epic bead with this DoD creates latent ambiguity. Fix in the PRD now.

## P1 Findings

### P1-1. G2 regression test condition translated incompletely to F4

**Agent:** fd-multi-store-ingestion-safety

**Finding.** G2 brainstorm language: *"assert node count stable, assert no `same-as` edges at cosine 1.0 between self-and-self."* F4 acceptance criterion 8: *"Regression test: fresh DB, run each importer twice, assert (a) stable node count, (b) no cosine-1.0 same-as edges between self-and-self, (c) manifest log shows 'idempotent-skip' on second run."* Good — this one is actually **faithful**. BUT: F4 runs *before* F5 (which is where `same-as` edges get created). A fresh ingestion importer run produces **zero same-as edges** regardless of idempotence correctness, so check (b) passes trivially and proves nothing. The check belongs in F5's regression suite, not F4.

**Recommendation.** Move check (b) from F4 to F5 acceptance criteria. F4 keeps (a) and (c). F5 adds: *"Run ingestion F4 twice followed by dedup F5; assert no cosine-1.0 same-as edges between any node and itself (i.e., the importer did not create a ghost duplicate that dedup then paired with the original)."*

### P1-2. G5 "adapters don't reimplement" softens to "surfaces as module gap" in F7

**Agent:** fd-noh-kata-canonical-form-drift

**Finding.** G5 language: *"Hermes view and Catalog view are **adapters** over this module — they MUST NOT reimplement selection logic."* F7 acceptance criterion 6: *"Any tool that cannot be expressed as an `ontology-queries` function surfaces as a module gap for V2 (not a reimplementation — per G5, adapters don't reimplement)."* This is correct in letter but permissive in spirit — it allows interlens F7 to ship with some MCP tools *not routed through `ontology-queries`* as long as they're filed as "gaps." There's no acceptance threshold (e.g., "≤ N tools may be gap-deferred; gap-deferred tools must have a V2 bead filed"). The iemoto principle degrades by leaks, not by explicit violation.

**Recommendation.** Add F7 acceptance criterion: *"If any of the 16 MCP tools cannot dispatch through `ontology-queries`, a follow-up bead is filed under epic `sylveste-b1ha` (V2 scope) per tool, with the missing query function specified. Gap count is reported in F7 closure; if gap count > 4 of 16, F7 closes as **redesign-required** and ontology-queries module API is revisited."*

### P1-3. G10 "before any triage code is written" translated to F6 acceptance but not enforced

**Agent:** fd-triage-lift-measurement

**Finding.** G10 brainstorm: *"Before any triage code is written for Epic child #4 (flux-drive view)."* F6 acceptance criterion 1: *"Pre-registration doc committed BEFORE any triage code is written (G10)."* Faithful language. BUT: write-plan step will file F6 as one bead with all acceptance criteria; there's no enforcement that the pre-reg doc commit precedes the triage-code commit in chronology. A motivated (or rushed) implementer can write the triage code locally, read the results, *then* author the pre-reg doc and commit it first. The commit ordering enforces nothing unless the pre-reg is a separate bead that must close first.

**Recommendation.** Split F6 into **F6a: Pre-registration + held-out corpus** (1 week) and **F6b: Triage backend + A/B run + decision memo** (1.5 weeks). F6b blocks on F6a closed. This also addresses the F6 sizing concern below (P1-4).

### P1-4. F6 at 2.5 weeks is the largest feature and compounds three risks

**Agent:** fd-triage-lift-measurement

**Finding.** F6 bundles: (i) pre-registration doc + 30-diff labeled corpus (the hardest honesty test — requires ground-truth labels), (ii) triage-logic extraction to `ontology-queries` module (first real consumer of the G5 pattern), (iii) A/B harness wiring, (iv) cost-per-finding measurement infra, (v) ship/abandon decision memo. 2.5 weeks is tight; if corpus labeling slips (the dependency lists "~2 hours human task" but 30 labeled diffs with paired ground-truth agent selections is more realistically 4-8 hours of focused labeling), triage code starts before pre-reg — violating G10.

**Recommendation.** Split per P1-3 above. F6a is 1 week (corpus + pre-reg, mostly human labeling time). F6b is 1.5 weeks (backend + A/B). Total same.

### P1-5. F3 at 1.5 weeks is tight given 6 gates land in one migration

**Agent:** fd-ontology-schema-discipline

**Finding.** F3 carries G3 (same-as fields + curator stub), G4 (bridges three-way spec + transform), G6 (schema_version + partial index), G7 (Evidence grading + cites tier), G8 (Lens immutable + supersedes + UUID), G9 (Transmission chain replaces Source). Plus rollback migration, partial indexes, curator-promotion stored procedure stub. That's **6 gates, 1 identity model change, 1 provenance model change, 2 index strategies, 1 stored procedure** in 1.5 weeks. One schema review round that pushes back on any one of these (e.g., Transmission chain shape debate) eats 3-4 days. The effort estimate assumes one-shot success.

**Recommendation.** Either (a) raise F3 to 2 weeks, or (b) pre-land the Transmission-chain shape as an errata to the PRD *before* F3 starts so the feature can focus on mechanical DDL rather than design debate. Option (b) is cheaper — add "G9 Transmission chain ER diagram" to F2's deliverables (F2 already has capacity for it).

### P1-6. F2 audit verdict can change F3 schema; F3 effort estimate assumes verdict=keep-separate

**Agents:** fd-sibu-classification-fit-check, fd-ontology-schema-discipline

**Finding.** F2 acceptance criterion 3: *"Decision ratified in PRD errata (update this doc's `## Solution` if collapse decided)."* F3 acceptance criterion 2: *"Migration 001 creates: Persona, Lens, Domain, Discipline, Source, Evidence, Concept **(or collapsed Domain+Discipline per F2 verdict)** as AGE vertex labels."* The collapse case changes the schema significantly: one fewer label, a `kind: enum` + `formalization_level: float` property, different in-domain/in-discipline edge semantics (collapse or keep two edges?), different partial-index shape. F3's 1.5-week estimate does not price the collapse path. F2 must therefore land its verdict **before** F3 DDL work begins, not concurrently.

**Recommendation.** Explicit serialization: F2 → F3 (not F2 ∥ F3 even partially). F2 acceptance criterion 3 becomes a gate: *"F3 cannot start until this PRD has been updated with collapse-or-keep decision."* Also: F3 acceptance criterion 1 currently gates on F1 verdict; add *"AND F2 Domain/Discipline verdict is ratified in PRD."*

### P1-7. DoD #1 verification artifact pointer is fragile

**Agent:** fd-triage-lift-measurement

**Finding.** DoD #1 verification: *"`packages/ontology-queries/tests/ab-triage.test.ts` or equivalent runnable."* The "or equivalent" escape softens the commitment. If the A/B runs via a shell script + JSON log rather than a TS test file, DoD is satisfied but the artifact is harder to re-run in CI. The brainstorm review's whole TLM package was about pre-commitment to measurable artifacts.

**Recommendation.** Pre-commit to the artifact form in the PRD. Replace "or equivalent runnable" with *"runnable via `pnpm --filter ontology-queries test:ab-triage` that re-executes the A/B against the frozen baseline SHA and prints pass/fail against pre-registered thresholds."* Being this specific costs nothing now and prevents artifact-form drift during F6.

## P2 Findings

### P2-1. F4 acceptance criterion 9 audit query is not spelled out as Cypher
**Agent:** fd-multi-store-ingestion-safety. The criterion *"every imported node has ≥ 1 `derives-from` Transmission chain ending at an origin Source"* is testable in principle but F4 doesn't commit to the actual Cypher. Recommend pre-committing the audit query in F4 deliverables alongside the regression test.

### P2-2. F5 calibration corpus ≥ 50 pairs may underpower cross-store precision estimate
**Agent:** fd-semantic-dedup-calibration. 50 pairs across four buckets (fd×fd, A×A, fd×A, interlens×others) yields ~12 per bucket. Precision estimates at 0.75 cosine have ±15% CI at this size. Either raise to ≥ 100 or acknowledge CI width in F5 dedup report.

### P2-3. F1 Cypher spike schema is "draft, not canonical" — but F3 may discover the draft was wrong
**Agent:** fd-age-cypher-query-economics. F1 explicitly uses a mirror schema. If F1 says "AGE-viable" but F3's canonical schema differs (e.g., collapsed Domain+Discipline, bi-temporal indexes), the F1 benchmark may not hold. Recommend F3 acceptance criterion: *"Re-run F1's 100k-edge benchmark against the canonical schema; document delta."* Cheap if F1 scripts are preserved.

### P2-4. "Fixative-triad schema" non-goal has an exit criterion that isn't actually defined
**Agent:** fd-perfumery-base-accord-composition. Non-goal says *"Revisit after F5 reveals whether triadic stabilization relationships are common in the real corpus."* No threshold, no detection mechanism. F5 is dyadic (same-as between pairs) — it won't naturally surface triads. Recommend either removing the "revisit after F5" language (defer unconditionally to V2) or adding a specific F5-side observability hook.

### P2-5. Concept residual-category risk not addressed in F3
**Agent:** fd-sibu-classification-fit-check. The brainstorm review surfaced Concept as the likely 雜家 residual. F3 creates Concept as a vertex label but PRD has no admission criteria for Concept. Post-ingestion, any noun phrase becomes a candidate Concept. Recommend F3 acceptance criterion: *"Concept entity has documented admission rule (e.g., 'a named idea referenced by ≥ 2 distinct lenses')."*

### P2-6. Open Question "curator promotion workload estimate" is timed wrong
**Agents:** fd-semantic-dedup-calibration, fd-isnad-chain-integrity. PRD says the dry-run estimate happens *as part of F5 acceptance.* If dry-run says "3000 candidates," F5 discovers it needs batch-review tooling mid-feature. Move the dry-run to F2 (cheap — uses existing 100-sample) so F5 plans its tooling correctly upfront.

## P3 Findings

### P3-1. Gates Index table cross-reference is good but omits DoD mapping
Add a third column: *"Epic DoD criterion honored."* G1→DoD#5, G2→DoD#2, G3→DoD#4, G10→DoD#1, etc. Makes the translation visible.

### P3-2. "Estimated effort" total doesn't add up cleanly to 10-11 weeks
1+1+1.5+2+1.5+2.5+1 = 10.5 weeks serial. If F1 ∥ F2 as stated, 9.5 weeks. Dependency P1-6 forces F2→F3 serialization, back to 10.5. Fine, but Dependencies section says *"total ~10-11 weeks on one focused lane"* — should be "~10.5 weeks serial; F1∥F2 saves ~1 week if F2 audit finishes before F3 needs it, but that parallelism is fragile per P1-6."

### P3-3. Open Question "Plugin home" has a recommendation in the PRD — promote it
The PRD already recommends `packages/ontology-queries/` standalone. That's a decision, not an open question. Move to Solution or Key Decisions section.

## Non-Goals Discipline Check

Non-goals list is **solid**. Spot-check:
- Hermes view: explicitly deferred, must be adapter. ✓ No F3/F4 criterion accommodates it.
- Catalog: deferred to V3. ✓ No surface in F1-F7.
- Fixative-triad: deferred but with weak revisit criterion. See P2-4.
- TerminusDB: deferred. ✓ No auxiliary-layer scaffolding in F3.
- Authoring UI: deferred. ✓ F5 curator tool is CLI, not UI.
- Automatic same-as without curator: prohibited. ✓ F5 enforces this.
- Reimplementing selection logic: prohibited by G5. ✓ Minor softening per P1-2.
- fd-agent retirement: deferred. ✓ F4 is additive-only.

No scope creep detected in F3 or F4. The two soft seams are P1-2 (F7 "module gap" permissiveness) and P2-4 (fixative-triad revisit trigger) — both patchable in acceptance criteria.

## Open Questions Deferability Check

| Open Question | Deferable? | Gates write-plan? |
|---|---|---|
| Plugin home | YES — PRD has recommendation | NO |
| Curator promotion workload | NO — per P2-6, move to F2 | YES (mildly) |
| Hermes dependency gating | YES | NO |
| Embedding re-run policy | YES (V2) | NO |

Only one open question (curator workload) affects decomposition and should be resolved pre-write-plan by moving the 100-sample dry-run to F2.

## Dependency Graph Correctness

User-stated graph: `F1, F2 (parallel) → F3 (deps F1+F2) → F4 (dep F3) → F5 (dep F4) → F6 (dep F2+F5) → F7 (dep F6)`.

**Assessment:**
- F1 ∥ F2: PRD says so, but per P1-6, F2→F3 serialization is tight. F1∥F2 is fine because F1 is scratch-only.
- F3 deps F1+F2: correct.
- F4 deps F3: correct.
- **F5 deps F4: correct, but F5 priority is wrong (P2-1 above — should be P1).**
- **F6 deps F2+F5: PRD text does not name F5 as a hard F6 dep. Per P0-1, add it or declare the A/B runs pre-dedup.**
- F7 deps F6: the PRD doesn't explicitly block F7 on F6 passing A/B. F7 only needs the `ontology-queries` module and the AGE graph — it can run in parallel with F6 once F5 completes. Recommend stating F7 depends on F5 (graph health) + F2 (module), **not** F6. This parallelizes F7 with F6 and could save ~1 week.

**Corrected graph (post-review):**
```
F1 ─┐
    ├─→ F3 ─→ F4 ─→ F5 ─┬─→ F6a ─→ F6b
F2 ─┘                   └─→ F7
```
F6b = triage backend + A/B (blocks on F6a pre-reg). F7 runs in parallel with F6. Total ~9 weeks serial critical path, down from 10.5.

## Synthesis Assessment

**Overall quality.** The PRD is a **faithful-with-soft-spots** translation. All 11 gates appear in at least one feature's acceptance criteria; most appear verbatim. The 7-feature decomposition is reasonable but has two sizing issues (F3 tight, F6 should split) and one priority mislabel (F5=P2 should be P1). The dependency graph is mostly right but under-serializes F2→F3 and misses F5→F6 as a hard edge. Epic DoD is the weakest section — criterion #1 has an escape hatch per P0-2.

**Highest-leverage single patch.** Split F6 into F6a (pre-registration + corpus) and F6b (backend + A/B). This enforces G10 commit ordering, relieves the 2.5-week sizing risk, and creates a natural gate for labeling-ground-truth slippage without blocking the rest of the epic.

**Verdict: SHIP-TO-WRITE-PLAN with patches.** The PRD is close enough that write-plan can proceed after the 2 P0 patches + the F5 priority fix + the F6 split land as PRD errata (or are recorded as write-plan amendments on the relevant bead). The 7 P1s can be absorbed into feature-bead acceptance criteria at filing time without re-opening the PRD. The 6 P2s are write-plan-step concerns, not PRD-step.

**What shipping means here:** file the 7 feature beads under `sylveste-b1ha` with the corrected dependency graph (F1∥F2 → F3 → F4 → F5 → {F6a→F6b, F7}), priority labels (F5=P1), and the PRD patches for DoD #1 falsifiability and the curator-workload pre-audit moved to F2.

## Cross-Reference

- PRD: `docs/prds/2026-04-21-persona-lens-ontology.md`
- Brainstorm (post-gate revision): `docs/brainstorms/2026-04-21-persona-lens-ontology-brainstorm.md`
- Brainstorm review synthesis (61 findings, 9 P0): `docs/research/flux-review/persona-lens-ontology-brainstorm/2026-04-21-synthesis.md`
- Prior-art assessment: `docs/research/assess-ontology-stores-2026-04-21.md`
- Triage matrix: `./triage-matrix.md`
