# fd-technical-claim-survivability — Review

## Findings Index

- P0: "Wired or it doesn't exist" — the meta-claim fails its own test; no enforcement artifact visible
- P0: "Sparse topology (Zollman effect)" — zero wired implementation; pure academic name-drop
- P1: No designated lead claim — three claims (self-building, OODARC, infra-unlocks-autonomy) compete for first position with no wedge declared
- P2: SF-literature naming load — seven proper nouns imposed before any claim lands

## Verdict

**mixed** — one claim (self-building) has a publicly visible receipt in the git log; two claims should be cut immediately for failing their own proof standards; the rest are either polish candidates or deferrals pending implementation.

---

## Receipts Audit

| # | Claim (abbreviated) | Smallest Concrete Receipt | Externally Visible? | Survives 'Prove It'? | Verdict |
|---|---|---|---|---|---|
| 1 | Infrastructure unlocks autonomy | Intercore public repo (ic, SQLite kernel, phases, gates) | Yes — public repo | Partial — shows infra exists, not that it improved agent output | polish |
| 2 | Review phases are where the leverage is | Clavain repo with 6-phase structure | Yes — public repo | No — architectural assertion, no measurement | hide |
| 3 | Evidence earns authority | Interspect at M2+ (routing overrides, canary windows) | No — internal system, no external demo or API | No | sequence-later |
| 4 | OODARC not OODA | `estimate-costs.sh` pipeline: actuals → calibrate → fallback | Yes — file in monorepo, $2.93 output cited | Partial — the Compound step is wired; needs surfacing as the story | polish |
| 5 | Wired or it doesn't exist | PHILOSOPHY.md (a doc) | Yes — but a doc asserting a doctrine is not itself wired | **No** — the meta-claim fails its own test; no CI gate, no linter | **cancel** |
| 6 | L0–L5 trust ladder | roadmap-v1.md (current: A ≈ L2) | Yes — roadmap is public | No — framework, not wired mechanism | hide |
| 7 | M0–M4 graduated authority | Promotion Criteria Registry (recent commit); Interspect explicitly at M2+ | Partially — registry is in docs/, Interspect claim is in PHILOSOPHY | No external URL with thresholds per subsystem | polish |
| 8 | Disagreement = highest-value signal | interflux parallel agents (implicit divergence) | No — no routing rule wired to disagreement metric | No | hide |
| 9 | Sparse topology (Zollman effect) | Research session folder in docs/research/flux-drive/ | No — a brainstorm folder is not implementation | **No** | **cancel** |
| 10 | Self-building | Git log (Claude Code as committer); $2.93/change from 785 sessions; bd tracker in public repo | **Yes** — git history is publicly auditable | **Yes** | **ship** |
| 11 | Pre-1.0 means no stability | v0.6.229 in README | Yes — trivially verifiable | Yes (defensive, not distinctive) | ship as context |
| 12 | Composition over capability | 64 inter-* plugins in interagency-marketplace | Yes — visible, but the brief says "64-plugin inventories" trigger negative reaction | No — triggers exactly the wrong response | hide |

---

## Summary

Two claims have public receipts that survive cold scrutiny: **self-building** (git log is auditable, $2.93 is a real number, 785 sessions is a real count) and **pre-1.0 stability** (trivially verified from the version string). OODARC and graduated authority have real receipts but buried ones — they require reading deep into the monorepo to find `estimate-costs.sh` or the Promotion Criteria Registry. Four claims (review phases, L0–L5, model disagreement, composition) are architectural assertions without empirical backing; hide them. Two claims — "wired or it doesn't exist" and "sparse topology" — should be cut immediately: the first fails its own test (a PHILOSOPHY.md entry is not wired), and the second has a research folder but no wired ring-topology implementation anywhere in the architecture. Shipping either claim to a skeptical technical audience hands them the debunk on a platter.

---

## Issues Found

### [P0] "Wired or it doesn't exist" is itself not wired
**Target claim:** 5  
**Verdict:** cancel  
**Why (your lens):** This is the most rhetorically dangerous claim in the set. A skeptical reader will immediately ask: what prevents a developer from shipping steps 1–2 without steps 3–4? The answer is: nothing. No CI check gates on evidence emission. No linter enforces it. The smallest concrete receipt is a paragraph in PHILOSOPHY.md — which is exactly what the claim says is insufficient. The claim creates an expectation of mechanical enforcement and then delivers a philosophy document. That inversion earns the opposite of trust. Cut it from external surfaces until enforcement is actually implemented.  
**Concrete action this week:** Remove from MISSION.md and README; retain internally in PHILOSOPHY.md as aspiration. OR: wire a minimal check (e.g., a pre-commit hook or `ic` gate that requires at least one event emission for a task close) and add that artifact as the receipt before shipping.

---

### [P0] "Sparse topology (Zollman effect)" — zero wiring
**Target claim:** 9  
**Verdict:** cancel  
**Why (your lens):** There is a research session folder (`sparse-communication-topology`) in docs/research/flux-drive/ and an academic citation. There is no ring-topology configuration, no multi-agent dispatch that defaults to sparse connections, no runtime artifact of any kind. Naming Zollman without implementation is the textbook definition of cargo-cult: borrow the prestige of a real result, ship the vocabulary without the mechanism. A technically serious reader who knows Zollman's original paper will find this in under five minutes. Cut immediately.  
**Concrete action this week:** Delete from PHILOSOPHY.md and all external-facing docs. File a bead if and when a ring-topology dispatch is implemented; it can come back then.

---

### [P1] No designated lead claim — three compete silently
**Target claim:** 1, 4, 10  
**Verdict:** polish  
**Why (your lens):** Self-building (#10), OODARC (#4), and infrastructure-unlocks-autonomy (#1) are all roughly equal in the current document hierarchy. None is called out as the wedge. A reader encountering the README gets the architecture table before any of these. The result is diffusion: no single hook lands with enough force to earn the second click. Self-building is the clear winner — its receipt is in the git log, not in a doc. Designate it as the opening claim and subordinate the others.  
**Concrete action this week:** Rewrite the first paragraph of README to lead with the self-building fact: "Sylveste builds itself. Every task is tracked as a bead. Every commit is made by an agent. The current cost is $2.93 per landable change across 785 sessions." That sentence earns the second click.

---

## Terminology Load Verdict

Seven proper nouns appear before any claim can land: Sylveste, Clavain, Skaffen, Ockham, Auraken, Khouri, Zaka/Alwe. Each is a Reynolds novel character. The SF-literature register is a calculated identity signal — it communicates "this project has a point of view" — but it imposes a tax on first-time readers who are evaluating the claim, not the aesthetic. The tax is non-trivial: "Ockham is an L2 factory governor implementing graduated authority" requires the reader to simultaneously parse a novel reference, an architectural layer label, and a governance concept. That is three decoding steps before the claim even starts. At current external visibility (no blog, no HN post, no social presence), the reader has no prior orientation to amortize the load.

**Recommendation:** For the first year of external surface — README, any HN post, any blog — use the plain-name first and the SF name parenthetically: "the agent rig (Clavain)", "the kernel (Intercore)", "the governor (Ockham)." Reserve the SF-first register for the architecture docs and the dedicated "what's in a name" post after there is an audience that has already been earned. Garden Salon and Meadowsyn should stay entirely off external surfaces until they launch — they currently appear as additional naming debt with zero artifact backing.

---

## Improvements

- **P3:** The $2.93/landable-change number should appear in README, not buried in memory/context. It is the most quotable number in the project.
- **P3:** The Promotion Criteria Registry (M0–M4 thresholds, recent commit) should be linked from PHILOSOPHY.md's graduated-authority section so the claim has a navigable receipt.
- **P3:** Claim #3 ("evidence earns authority") and claim #7 (M0–M4) are the same flywheel described at two levels of abstraction. Merge them into one claim with Interspect as the named example.

---

## The One Claim That Leads

**"Sylveste builds itself."**

The one public artifact: the git log at `mistakeknot/Sylveste`, where the committer is Claude Code, the commit count reflects 785 agent sessions, and a specific cost ($2.93/landable change) is on record. No other claim in the set has a receipt that is this immediately, externally auditable without reading any documentation.

<!-- flux-drive:complete -->
