# fd-technical-claim-survivability — Findings

Lens: veteran technical editor, red-teams launch copy. Every distinctive claim must resolve "what specifically is wired up that demonstrates this?" within one paragraph, or it is slogan debt.

## Verdict

Of twelve distinctive claims in PHILOSOPHY.md, two have receipts (Closed-Loop + Interspect). Ten do not. Shipping the ten publicly creates credibility debt that will compound. Cut the ten. Keep the two. Ship the two loud.

## Findings

### P0 — "Wired or it doesn't exist" is itself not wired to a visible enforcement check
**Location:** PHILOSOPHY.md claim #5 (target-brief lines 81-82).

The meta-claim is its own best test. For the claim to survive skeptical reading, there must be a public artifact where a feature was refused because it was unwired. Currently there is none visible externally. The claim is prose only.

**Failure scenario:** senior practitioner reads "wired or it doesn't exist" and asks "show me a bead closed as incomplete because the feature was unwired." Answer is "it happens internally." Instant credibility hit — the claim is stronger than the receipt.

**Fix:** publish one artifact. Candidate: a public log of beads that were blocked from closing because Clavain's completion-gate detected unwired triggers. Or: a PR description where the review phase refused to pass until evidence was wired. This converts the meta-claim from slogan to receipt.

### P0 — "Every action produces evidence. Evidence earns authority."
**Location:** PHILOSOPHY.md claim #3.

Only Interspect is M2+. The claim presupposes a full evidence flywheel across multiple systems. Four of the five evidence systems are M0-M1. The claim as stated is aspirational framing.

**Fix:** rewrite the public claim as narrow fact: "Interspect routes agents based on evidence, not policy. See [link]." Drop the flywheel language until the flywheel spins.

### P0 — "Disagreement between models is the highest-value signal"
**Location:** PHILOSOPHY.md claim #8.

No public artifact shows this being operationalized. Reader test: show me one calibration update that was triggered by model disagreement. Answer: not visible externally.

**Fix:** either pair with one `/interpeer` transcript (Claude↔Codex disagreement + what changed in routing) or cut the claim entirely. Do not ship as pure opinion.

### P0 — "Sparse topology (Zollman effect)"
**Location:** PHILOSOPHY.md claim #9.

Academic citation without a Sylveste experiment showing Sylveste uses sparse topologies. In the absence of the experiment, the claim reads as name-dropping.

**Fix:** cut from the public list until an experimental artifact exists.

### P1 — Twelve claims with no designated lead
**Location:** PHILOSOPHY.md (target-brief lines 76-89).

The reader cannot identify which claim Sylveste stakes its reputation on. Equal-weight claim lists read as manifesto. Every claim dilutes the others.

**Fix:** designate one lead claim. Candidate: "OODARC — Boyd's OODA with Reflect and Compound steps wired to durable calibration." Or: "Closed-Loop cost calibration with $2.93/landable baseline across 785 sessions." Place the lead on every public surface. Demote the others to supporting observations or cut.

### P1 — Graduated authority M0-M4 is aspirational framing
**Location:** PHILOSOPHY.md claim #7.

Claim: "subsystem maturity scale with pre-specified evidence thresholds." For this to be a receipt rather than a framework, the public surface must show: the thresholds, which subsystem is at which level, and the evidence that moved the most recent subsystem from M1 to M2. Currently only the scale exists; the specific thresholds and per-subsystem placements are internal.

**Fix:** publish a one-page "M-level dashboard": for each cross-cutting system, its current M-level, the threshold for advancing, and the evidence last collected. Without this page, the M-scale is decorative.

### P2 — SF-literature naming register imposes cognitive load before claims land
**Location:** target-brief §"Two brands" lines 66-69 + plugin names.

"Sylveste," "Clavain," "Skaffen," "Ockham," "Auraken," "Khouri" — the SF-literature register is distinctive (good) but forces a register-shift the reader must perform before absorbing the claim. Compounds with unfamiliar concept density.

**Fix:** in public-facing surfaces, substitute role names for character names on first mention. "Sylveste (the monorepo)" — first mention. "Clavain (the agent rig)" — first mention. Once the reader has anchored, subsequent mentions can drop the gloss.

### P2 — "$2.93/landable change" is a receipt but is buried
**Location:** target-brief line 134, cost baseline.

This is the single strongest externally-verifiable receipt in the inventory. It is a specific number with a specific session count and a reproducible command. Currently it appears only in AGENTS.md pointers and an internal script.

**Fix:** this number should be on the README first screen. It should be in the preprint title. It should be on the factory page. It is the single most defensible claim and it is getting no oxygen.

## Claims to cut from the public list

Cut entirely (from PHILOSOPHY.md or demote to internal-only notes):
- #1 "Infrastructure unlocks autonomy" — opinion, unreceiptable.
- #2 "Review phases matter more" — keep as tagline theme but do not list as distinctive claim.
- #6 "Progressive trust ladder" — until per-level evidence is published.
- #8 "Disagreement is highest-value" — until interpeer artifact exists.
- #9 "Zollman sparse topology" — until Sylveste experiment exists.
- #11 "Pre-1.0 means no stability" — meta-claim; keep but not as distinctive.
- #12 "Composition over capability" — cliché.

## Claims to keep and ship loud

- **#4 OODARC** — ship with the methods preprint as anchor.
- **#5 "Wired or it doesn't exist"** — ship with one visible enforcement artifact.
- **Closed-Loop cost calibration + $2.93/landable** — not currently listed as a distinctive claim but IS the strongest one. Add it to the list. Ship as preprint. Put on README first screen.
- **#3 evidence-earns-authority, narrowed to Interspect** — ship with the Interspect M-level receipt.

Three to four claims with receipts beats twelve without.

<!-- flux-drive:complete -->
