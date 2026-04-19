# fd-preprint-venue-sequencer — Findings

Lens: ML publication strategist. The order of venue-touch matters more than total venues. A workshop acceptance earns more citation-weight than a dozen blog posts. An HN post without a citable handle burns the attention with no credential accrual.

## Verdict

Ship a 4-8 page methods-style preprint on the Closed-Loop cost-calibration pipeline BEFORE any HN post. The preprint gets a DOI/arXiv ID. The HN post and blog post link to it. That sequence converts a one-shot attention event into a citation handle that accumulates.

## Findings

### P0 — HN submission drafted without preprint is one-shot burn
**Location:** target-brief §"User CAN" (line 151).

"Post once to HN / Lobsters / X." Without an arXiv ID to link, the post is a monorepo drop. Technically-serious readers index by citation handle. They will not cite a GitHub URL in their own work. The attention event evaporates with no credential accrual.

**Fix:** sequence is preprint → HN, never HN → preprint. The preprint is the thing HN links to. The HN post then also links to the monorepo as a secondary bearing. But the primary URL is the preprint.

### P0 — Only one of twelve distinctive claims is eligible to be preprinted
**Location:** PHILOSOPHY.md twelve claims (target-brief lines 76-89), `estimate-costs.sh` existence proof (target-brief line 90).

Audit:
- Claim #1 "Infrastructure unlocks autonomy" — opinion, no table.
- Claim #2 "Review phases matter more" — opinion, no measurement.
- Claim #3 "Evidence earns authority" — real but requires Ockham/Interspect full-stack; partially ready.
- Claim #4 OODARC — primitive specification, preprintable as a methods note.
- Claim #5 "Wired or it doesn't exist" — definitional, no table.
- Claim #6 "Progressive trust ladder L0-L5" — framework, needs data.
- Claim #7 "Graduated authority M0-M4" — framework, needs data.
- Claim #8 "Disagreement is highest-value signal" — empirical, no experiment.
- Claim #9 "Zollman sparse topology" — empirical citation but no Sylveste experiment yet.
- Claim #10 "Self-building" — verifiable but not a single measured claim.
- Claim #11 "Pre-1.0 means no stability" — meta-claim.
- Claim #12 "Composition over capability" — cliché.

PLUS: the Closed-Loop pattern + $2.93/landable baseline is a measured claim with a reproducible pipeline.

The preprintable candidates are:
- **Primary:** Closed-Loop cost calibration pipeline. One table. 785-session baseline. Reproducible. Ships immediately.
- **Secondary:** OODARC specification as a methods note. No experiment needed — it is a protocol spec.

**Fix:** write the methods preprint on the Closed-Loop pipeline this week. 4-8 pages. One table (cost per landable change across sessions). One algorithm box (the four stages: hardcoded defaults → collect actuals → calibrate from history → defaults become fallback). One reproducibility appendix (the commands).

### P1 — Twelve equal-weight claims read as manifesto; cut the unevidenced
**Location:** PHILOSOPHY.md (target-brief lines 76-89).

Equal-weight claims without receipts read as a manifesto. Technically-serious readers file manifestos under "grandiose; skip."

**Fix:** cut from the public distinctive-claims list every claim without a companion artifact. Keep only #4 OODARC (if preprinted) and #10 Self-building (if the factory page ships) and the Closed-Loop pattern (if the preprint lands). Three claims with three artifacts beats twelve claims with one.

### P2 — "Disagreement is highest-value signal" is venue-ready IF someone runs the experiment
**Location:** PHILOSOPHY.md claim #8.

This is a workshop-paper-shaped claim. A small experiment (route 100 tasks through Claude↔Codex, measure disagreement rate, show the high-disagreement subset drives more calibration updates) would produce a venue-eligible paper. Without the experiment, the claim dilutes the other work.

**Fix:** either run the experiment in Q3 (workshop-track submission) or cut the claim from the public list until then.

### P3 — No canonical citable identifier exists for any primitive
**Location:** Current public repos (target-brief §"Public repos" lines 96-102).

GitHub URLs are not citation handles in the serious-ML community. Without arXiv ID, DOI, or Zenodo release, adopters cannot credit Sylveste in their own papers or posts. Reputation does not accrue.

**Fix:** once the preprint is written, submit to arXiv. Also tag a Zenodo release of the monorepo for DOI. Both take <2 hours once the preprint exists. The DOI is the citation handle.

## The sequence, named

**Week 1:** Write 4-8 page preprint: "Closed-Loop Cost Calibration for Autonomous Software-Development Agents." One table. One reproducibility appendix. Zenodo release for DOI. arXiv submission (cs.SE + cs.AI).

**Week 2:** Preprint appears on arXiv. Build the factory page (Arsenal finding). Prepare HN draft with preprint as hero link.

**Week 3:** HN Show HN: title names the preprint ("Show HN: Closed-Loop Cost Calibration — $2.93/landable change baseline for autonomous agents"). Primary URL is the arXiv ID. Secondary link is the monorepo. Blog post the same day citing the preprint. Ping the 3-5 named practitioners (per Hokulea finding) 48 hours before submission.

**Week 4+:** Workshop-paper preparation on either OODARC or the disagreement experiment. Target: NeurIPS workshop cycle.

This sequence converts a one-shot attention event into a citation handle that accrues. The HN post becomes cumulative, not evaporative.

<!-- flux-drive:complete -->
