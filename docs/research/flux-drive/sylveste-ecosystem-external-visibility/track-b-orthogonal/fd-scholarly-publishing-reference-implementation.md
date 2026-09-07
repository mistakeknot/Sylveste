# Track B — Scholarly Publishing / Reference Implementation

> Lens: PyTorch / Stan / Jupyter playbook. Labs adopt reference implementations and benchmark suites, not platforms.
> Target: Sylveste ecosystem external-visibility review.
> Date: 2026-04-16.

## TL;DR

Sylveste has an abundance of citable claims and almost zero citable artifacts. The headline `$2.93/landable-change` figure (PHILOSOPHY.md, roadmap-v1.md C:L1) is quoted everywhere but has no runnable harness, no fixed commit hash, no Zenodo DOI, and no `CITATION.cff`. Vision v5.0 is a strategy memo, not a technical report. The 6-pillar architecture ("5 pillars" in README.md line 76, "six pillars" in AGENTS.md line 3 — the count itself is inconsistent) means no single artifact is the PyTorch-analog that a FAIR researcher could clone in 30 minutes. Interspect is the closest candidate to artifact-evaluation readiness: it is the one subsystem at M2 ("Operational"), has a defined event schema, and owns the measurable outcomes that underlie every quotable stat. Stage 2 should deep-dive the observability layer (Interspect + interstat + FluxBench) because that is where the one reproducible benchmark lives.

## Findings

### F1 [P0] — The $2.93/landable-change claim is not reproducible from a clean clone

**Where it lives:** `PHILOSOPHY.md` (the closed-loop table), `docs/roadmap-v1.md` line 115 (C:L1 baseline), `README.md` does not even mention it, `MEMORY.md` quick reference, multiple brainstorms.

**Why it fails the lab-reviewer bar:** The number is cited as "measured 2026-03-18, 800+ sessions, via interstat/cost-query.sh" — but a third-party reviewer who clones Sylveste cannot reproduce this. There is no frozen dataset, no `scripts/reproduce-293.sh`, no `data/sessions-baseline-20260318.jsonl`, no method-of-measurement doc explaining which sessions were included, what "landable" means operationally, how token cost was priced, and which pricing-source revision (`core/intercore/config/costs.yaml`) was active. ACM/NeurIPS artifact evaluation rejects on less. HumanEval ships `HumanEval.jsonl.gz`. SWE-bench ships `swebench/harness/run_evaluation.py` + a frozen instance set. Sylveste ships a number in a memo.

**Failure scenario:** A Hamilton Ai-Lab researcher drafts a systems-paper section citing Sylveste's cost figure. They clone the monorepo to rerun the measurement, can't find the data, can't pin a commit, and drop the citation. The quotable stat leaks out of every downstream narrative.

**Fix (smallest viable):**
1. Freeze the baseline cohort as `data/baseline/2026-03-18-sessions.jsonl.zst` with a manifest (`baseline-manifest.yaml`: commit SHA, pricing version, N, inclusion rule).
2. Ship `scripts/reproduce-landable-change-cost.sh` that reads the cohort and emits the same number (tolerance +/- $0.05).
3. Add a `docs/benchmarks/landable-change-cost.md` that is the method section (what counts as landable, how sessions are attributed, how cache tokens are priced).

### F2 [P1] — No single pillar is designated the reference implementation

**Where it lives:** README.md "5 pillars" table (lines 76-85), AGENTS.md "Six pillars" line 3, sylveste-vision.md describes 6 pillars + 5 cross-cutting evidence systems = 11 top-level objects. Capability Mesh table has 10 subsystems. `interverse/` has 58 plugins.

**Why it fails the lab-reviewer bar:** PyTorch is the reference implementation of autograd tensors. Stan is the reference implementation of HMC for probabilistic programming. Jupyter is the reference implementation of the literate-notebook protocol. Each is ONE artifact that embodies ONE thesis. Sylveste presents labs with a surface area of 6 pillars + 58 plugins + Garden Salon + Meadowsyn and says "pick". That is an adoption cliff, not a reference implementation. Pre-1.0 platforms with this many concurrent pillars cannot all be citation anchors simultaneously — citation graphs fragment across names.

**Failure scenario:** A grad student wants to cite "the Sylveste approach to evidence-based agent routing". They don't know whether to cite Intercore (kernel), Clavain (OS), Interspect (profiler), or the umbrella. The bibliometric signal disperses to zero.

**Fix:** Designate **Interspect** as the reference implementation for the next 6 months. It is the only M2 operational evidence subsystem, it has the clearest thesis (closed-loop routing via canary evidence), it has its own vision/roadmap doc (`docs/interspect-vision.md`, `docs/interspect-roadmap.md`), and it owns the mechanism that produces the quotable stat. Everything else becomes "optional substrate around Interspect" in external-facing docs.

### F3 [P1] — No benchmark harness exists for any Sylveste claim

**Where it lives:** `interverse/interlab/` has `scripts/agent-quality-benchmark.sh` and `scripts/plugin-benchmark.sh` (per AGENTS.md lines 50-53), but these are internal scoring scripts, not a public harness. No `benchmarks/` top-level directory. No `sylveste-bench`. FluxBench is still at M0-M1 ("~80% implemented" per Capability Mesh). SWE-bench is listed as a P1 target in sylveste-roadmap.md but is a *consumer* of SWE-bench, not a producer of a Sylveste benchmark.

**Why it fails the lab-reviewer bar:** SWE-bench became a standard because labs could run it against their own systems and get a number that is commensurable with published scores. Sylveste's thesis — "review phases matter more than building phases," "closed-loop calibration compounds" — is testable, but there is no harness another lab could run against Aider/LangGraph/Claude Code bare to produce comparable numbers. Without a harness, the thesis stays a claim.

**Failure scenario:** Anthropic's Agent Team wants to validate whether closed-loop calibration meaningfully outperforms static routing. They have no harness to run, so they build one in-house and cite their own result. Sylveste loses the category-defining moment.

**Fix:** Extract a `benchmarks/closed-loop-routing-bench/` with: a fixed set of decomposed tasks (drawn from FluxBench 3,515 LOC Go harness), a runner that produces `{phase, model, outcome, cost}` tuples, and a scorer that emits the same cost-per-landable-change metric. This is a 2-4 week polish task on top of existing interlab + FluxBench code — not a rewrite.

### F4 [P2] — No DOI-bearing release, no CITATION.cff, no release notes

**Where it lives:** Repo root — `CITATION.cff` does not exist (confirmed via `ls`). `CHANGELOG.md` does not exist at root. v0.6.236 (per sylveste-roadmap.md ecosystem snapshot) is not cut as a Zenodo-archived release. No `docs/releases/` with dated release notes a researcher could cite.

**Why it fails the lab-reviewer bar:** PyTorch 0.2 (the pre-1.0 release that became cited) shipped with version-pinned tutorials, a `CITATION` file, and an arXiv preprint with matching version number. Stan's manual carries a version number on the title page that matches the codebase tag. Sylveste v0.6.236 is a floating target — any citation to it has a half-life of weeks.

**Failure scenario:** A workshop paper cites "Sylveste (v0.6.236)". Six months later the reviewer clones the repo, sees v0.7.2, and cannot reconstruct what the paper used. The citation decays to a broken URL.

**Fix:**
1. Add `CITATION.cff` at repo root now — name "Sylveste", authors, version, date, URL. (15 minutes.)
2. Cut v0.7.0 as the "first citable release" — tag, Zenodo archive (via the GitHub-Zenodo integration), release notes in `docs/releases/v0.7.0.md`.
3. Pin the preprint: a 20-page landmark PDF with `v0.7.0` on the title page, uploaded to arXiv (cs.SE) and co-linked from the release.

### F5 [P2] — Vision v5.0 reads as strategy memo, not publishable technical report

**Where it lives:** `docs/sylveste-vision.md` — 5.0 dated 2026-04-11, "Status: Active". Strong structure (Pitch, Two Brands, Stack, Flywheel, Capability Mesh, Trust Architecture). Weak on the things a JOSS paper or MLSys systems-paper reviewer checks: no explicit contributions list, no related-work section, no evaluation section, no threats-to-validity, no reproducibility statement.

**Why it fails the lab-reviewer bar:** Stan's manual reads like a textbook because each chapter has a worked example with executable code. Jupyter's JOSS paper is 2 pages but every claim points to a demonstrable notebook. Vision v5.0 makes strong claims ("the flywheel compounds", "evidence earns authority") but none map to a specific test, dataset, or benchmark row. A reviewer who takes the doc seriously has nothing to check against.

**Failure scenario:** A Brookings-AI-lab adjacent reviewer reads Vision v5.0 and finds it stimulating but unfalsifiable. It stays on their reading list, not their citation list.

**Fix:** Produce a companion `docs/sylveste-technical-report-v1.md` (20-30 pages, PDF-exportable) restructured as: Abstract / Contributions / Architecture / Evaluation (with the reproducible $2.93 harness) / Related Work (Aider, LangGraph, Cline, Devin, MetaGPT, SWE-agent) / Threats to Validity / Reproducibility Appendix. Vision v5.0 stays as the vision; the technical report is what gets cited.

### F6 [P2] — Brand trinity (Sylveste / Garden Salon / Meadowsyn) fragments citation graph

**Where it lives:** `MISSION.md` (line 5: "Two brands, one architecture" — but then names three), PHILOSOPHY.md Naming section enforces "layer boundary IS the brand boundary", README.md mentions only Sylveste, `apps/Meadowsyn/CLAUDE.md` still says "Demarch AI factory" (line 3 — unmigrated from the pre-Sylveste name).

**Why it fails the lab-reviewer bar:** Bibliometric tracking keys on a single string. If Sylveste gets cited as "Sylveste", Meadowsyn as "Meadowsyn", and Garden Salon as "Garden Salon", three papers citing the same underlying system produce three orphan entries in Google Scholar. PyTorch + torchvision + torchaudio works because "PyTorch" is the umbrella citation and the submodules inherit authority from it. Sylveste has not designated its umbrella citation.

**Failure scenario:** A systems researcher finds Meadowsyn via a Cybersyn-lineage paper, cites it alone, and misses the fact that it is the visualization layer of Sylveste. The cross-citation never happens.

**Fix:** Adopt the convention "Sylveste (Garden Salon, Meadowsyn)" for citation purposes — Sylveste is the umbrella string in BibTeX, the sub-brands are module identifiers. Codify in `CITATION.cff` (`identifiers:` with `type: other`, `value: Sylveste-Meadowsyn`). Update `apps/Meadowsyn/CLAUDE.md` line 3 to remove "Demarch" (this is a lingering stale reference that leaks into any future paper).

## Layer-for-Stage-2 Recommendation

**Stage 2 should deep-dive the OBSERVABILITY layer** — specifically the `Interspect + interstat + FluxBench` triad plus the cost-query pipeline.

Rationale:
1. Interspect is the only subsystem at M2 "Operational" per Capability Mesh — it is the only candidate where a reference implementation could be extracted within a quarter without shipping new architecture.
2. It owns the mechanism that produces the headline `$2.93/landable-change` stat — making the harness reproducible here unlocks external citation for the whole project.
3. It has the clearest single-thesis framing ("closed-loop routing via canary evidence feedback") that maps to a publishable systems paper.
4. FluxBench (measurement, ~80% implemented, 3,515 LOC Go) is the benchmark-harness substrate — polishing it to public-runnable state is 2-4 weeks, not 2 quarters.
5. Intercore (kernel) and Clavain (OS) are either too general or too opinionated to be the reference implementation; they make more sense as "the substrate Interspect runs on" in a paper.

## Concrete Actions

1. **Ship `CITATION.cff` and freeze v0.7.0 as first citable release** (this week, 1-2 days). Zenodo DOI via GitHub integration. This unblocks every downstream citation regardless of what else happens.

2. **Extract `benchmarks/closed-loop-routing-bench/` from interlab + FluxBench** (2-4 weeks). Public runner, frozen task set, reproducible `$2.93` output. This is the PyTorch-0.2-moment artifact — the one thing labs can actually run.

3. **Write `docs/sylveste-technical-report-v1.md`** (20-30 pages, 2-3 weeks, co-authored with Claude). Structure: Abstract / Architecture / Evaluation-on-the-bench / Related-Work / Reproducibility-Appendix. Upload to arXiv cs.SE. This is the landmark-report spine scholarly-publishing demands — it is what gets cited, not Vision v5.0.

## Decision-Lens Self-Check

Would a DeepMind or FAIR researcher cite Sylveste in a paper within 12 months given the current state? **No.** There is nothing citable. After F1+F4+F3 are shipped? **Yes** — the closed-loop routing bench would become the natural citation for any paper discussing calibration-based agent routing, and the archived v0.7.0 + technical report would give the umbrella citation authority.
