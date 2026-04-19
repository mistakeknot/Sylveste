# Track B — OSS Foundation / Contributor Ladder

> Lens: CNCF / Apache Incubator graduation. Governance artifacts, contributor ladders, SIG structure, downstream adoption proof.
> Target: Sylveste ecosystem external-visibility review.
> Date: 2026-04-16.

## TL;DR

Sylveste has strong engineering discipline (PHILOSOPHY.md, canon/, layered architecture) but zero foundation-grade governance artifacts at the repo root. No `GOVERNANCE.md`, no `MAINTAINERS.md`, no `SECURITY.md`, no `CODE_OF_CONDUCT.md`. `CONTRIBUTING.md` is 23 lines of fork-and-PR boilerplate. The project has 58 Interverse plugins — CNCF-scale sub-scope complexity — but no SIG/working-group structure, no charter, no decision-making process documented. It reads as a solo-or-small-team project with deep internal discipline, which is exactly the shape CNCF sandbox reviewers disqualify on sight. The dependency-lock-in candidate (Interverse plugin spec as a substrate — akin to OpenMetrics) is real but undeclared. Stage 2 should deep-dive the PLUGIN-SUBSTRATE layer (`docs/canon/plugin-standard.md` + the 58 plugin reference implementation) — it is the one scope where governance could be bolted on first without rewriting the rest of the project.

## Findings

### F1 [P0] — No foundation-grade governance files at repo root

**Where it lives:** Repo root — confirmed absent via `ls CITATION* CODE_OF_CONDUCT* GOVERNANCE* SECURITY* MAINTAINERS* CHANGELOG*` (zero matches). Only `CONTRIBUTING.md` exists, 23 lines, containing essentially "fork + PR + one review" (`CONTRIBUTING.md` lines 1-23). `PHILOSOPHY.md` and `docs/canon/` are strong internal doctrine but not governance artifacts.

**Why it fails the foundation-reviewer bar:** CNCF Sandbox acceptance checklist requires `CODE_OF_CONDUCT.md` (CNCF uses Contributor Covenant), `CONTRIBUTING.md` with decision-making process, `GOVERNANCE.md` with maintainer criteria, `MAINTAINERS.md` with current maintainer list, `SECURITY.md` with vulnerability reporting. Apache Incubator is stricter. A lab procurement team running a vendor-security review checks these files in the first 5 minutes. Their absence is a disqualifier — not because the project is insecure, but because absence signals "not yet serious OSS". This is a one-day content-creation task masquerading as a maturity ceiling.

**Failure scenario:** Meta's internal-tooling team evaluates Sylveste for internal adoption. Their security review template checks for `SECURITY.md` + vulnerability reporting process. It doesn't exist. The evaluation halts at the procurement gate. The team never even gets to the technical review.

**Fix (smallest viable, 1-2 days total):**
1. `CODE_OF_CONDUCT.md` — verbatim Contributor Covenant 2.1, email to maintainer for reports.
2. `SECURITY.md` — vulnerability reporting email, 48h ack SLA, coordinated disclosure policy.
3. `GOVERNANCE.md` — initial BDFL model (honest about solo/small-team state), path to lazy consensus as contributor count grows, amendment process.
4. `MAINTAINERS.md` — current maintainers (even if n=1), criteria for becoming a maintainer, criteria for stepping down.
5. Expand `CONTRIBUTING.md` from 23 lines to the full CNCF pattern (already referenced via `docs/guide-contributing.md` — just needs the governance section).

### F2 [P1] — No contributor ladder, no path from "tried it" to "committer"

**Where it lives:** `CONTRIBUTING.md` (23 lines) and `docs/guide-contributing.md`. Neither defines a progression. AGENTS.md line 40 says "Owner/agents commit directly to `main` (trunk-based). External contributors: Fork + PR (branch protection enabled)." This is a two-tier binary (owner vs. stranger) — no member, reviewer, approver, maintainer, or SIG-lead rungs.

**Why it fails the foundation-reviewer bar:** Kubernetes scales because `sig-apps/OWNERS` can approve `sig-apps/` PRs independent of the kernel maintainers. Prometheus, Envoy, Istio all use similar OWNERS-based delegation. Without a ladder, every PR needs the BDFL's attention — which caps drive-by contributions at "tiny bugfix the BDFL has time for" and prevents the project from compounding external effort. The ladder is the mechanism by which OSS projects scale past the founder.

**Failure scenario:** A motivated external contributor lands a good 200-LOC PR to `interverse/interweave`. It sits awaiting review because the BDFL is deep in another epic. The contributor's PR #2 never comes. This pattern repeats silently across every external contribution attempt; the project never develops contributor #2.

**Fix:** Define a 3-rung ladder in `GOVERNANCE.md`:
- **Contributor**: anyone whose PR has landed.
- **Reviewer** (scoped): after 5 landed PRs in a specific plugin, granted LGTM authority for that plugin. Listed in `interverse/<plugin>/MAINTAINERS.md`.
- **Maintainer** (scoped): after 3 months as reviewer + demonstrated judgment, granted merge authority for that plugin. Kernel (`core/intercore/`) and Clavain (`os/Clavain/`) stay BDFL-only until v1.0.

This is a proposal, not a commitment — publish it and let it guide external contributor expectations.

### F3 [P1] — No SIG / working-group structure for 58-plugin ecosystem

**Where it lives:** `interverse/` directory (58 plugins). README.md lists 5 pillars (kernel, OS, profiler, plugins, apps). `docs/canon/plugin-standard.md` is the structural quality bar — good internal doctrine. But no per-pillar charter, no working-group scope definition, no designated owner per plugin, no per-plugin `MAINTAINERS.md`.

**Why it fails the foundation-reviewer bar:** 58 plugins is CNCF-scale complexity (Kubernetes has ~40 SIGs, Prometheus has ~10 working groups). Foundation reviewers check whether the project has structured its sub-scope such that growth is absorbable. Without SIGs, every plugin question routes to one person, creating single-point-of-failure ownership. This is explicitly a "cannot graduate" signal. AGENTS.md line 36 ("One canonical owner per command/skill — when extracted from Clavain, remove from Clavain's plugin.json") acknowledges the need for ownership boundaries internally, but has not externalized them.

**Failure scenario:** The CNCF Technical Oversight Committee asks "who is the maintainer of interweave, and who steps in if they are unavailable?" There is no answer. The review ends.

**Fix:** Publish `docs/sigs/` with one file per pillar:
- `docs/sigs/sig-kernel.md` — charter for core/intercore, persistence-track owner.
- `docs/sigs/sig-orchestration.md` — Clavain + Skaffen OS-layer scope.
- `docs/sigs/sig-evidence.md` — Interspect + FluxBench + interstat evidence infrastructure.
- `docs/sigs/sig-plugins.md` — Interverse plugin substrate + canon.
- `docs/sigs/sig-apps.md` — Autarch + Meadowsyn surfaces.

Each file: scope, current maintainer(s), review criteria for new maintainers, meeting cadence (can be "async via bead comments" — that is legitimate), decision record location. This is 2-3 days of content creation; it does not require new process, only documenting what is already implicit.

### F4 [P1] — Dependency-lock-in candidate is undeclared

**Where it lives:** `docs/canon/plugin-standard.md` is the plugin substrate spec (what every Interverse plugin must look like — 6 required root files, specific directories, SKILL.md convention). `docs/canon/mcp-server-criteria.md` is the MCP server bar. `PHILOSOPHY.md` line 130-142 distinguishes standalone vs kernel-native plugins.

**Why it fails the foundation-reviewer bar:** Prometheus won because OpenMetrics became the exposition format everyone implemented. Kubernetes won because CRDs became the extension substrate. CNCF explicitly evaluates projects on "what becomes indispensable after adoption" — the lock-in artifact is the permanence mechanism. Sylveste's candidate is the **Interverse plugin spec**: 58 working plugins already conform to it, the canon doc is explicit, and the substrate is general enough that a plugin written for Sylveste could run on other agent platforms. But this is treated as internal tooling, not positioned as a specification others could implement.

**Failure scenario:** Three years from now, if Sylveste wants to claim "the plugin spec is the standard for agent tooling," it has no RFC, no spec version, no conformance tests, and no third-party implementations. The standardization window closes because nobody was invited to the substrate.

**Fix:**
1. Promote `docs/canon/plugin-standard.md` to `docs/specs/interverse-plugin-spec-v1.md` with an RFC-style cover (version, status, conformance language, change process).
2. Add a conformance test suite (`scripts/test-plugin-conformance.sh`) that can run against any plugin repo and emit PASS/FAIL on each clause.
3. Publish the spec as a standalone page at `sylveste.dev/spec` when the docs site ships.
4. Open an RFC process (`docs/rfcs/`) for spec evolution — the first RFC is "plugin spec v1.1 additions".

This is how Prometheus made OpenMetrics a category — it is 2-3 weeks of re-framing existing doctrine as an external-facing spec.

### F5 [P2] — Zero named downstream users

**Where it lives:** `docs/roadmap-v1.md` C:L1-C:L4 tracks are explicit about this ("Track C: Adoption" — L1 is self-building, L2 is one external project, L3 is multi-external). The roadmap honestly acknowledges zero named external adopters. MISSION.md claims the thesis but has no production case study.

**Why it fails the foundation-reviewer bar:** CNCF Incubation requires 3 named end-users in production. Apache requires named downstream distributions. Even CNCF Sandbox reviewers look for "is anyone outside the author's team using this?" The honest answer is "not yet", which is acceptable for a pre-M1 project but capped at sandbox-level credibility. One named external adopter willing to co-author a "we ran Sylveste against our codebase for 30 days" case study shifts every external narrative.

**Failure scenario:** At YC/Techstars/any-investor pitch, "we have 0 external users" ends the conversation. At a CNCF Sandbox application, "we have 0 external users" caps the ceiling at sandbox. The project cannot graduate past its current ceiling without this signal.

**Fix:** This is the bead iv-6376 / Track C:L2 concern — the v0.8 gate requires one external project with 50+ sprints. Suggest the "shortest path to 3 named adopters" playbook:
1. Identify 3 developers in the author's network running active side-projects.
2. Offer white-glove onboarding + weekly pairing for 30 days.
3. Agree in advance that success = case study + logo on `sylveste.dev/users`.
4. This produces the N=3 signal CNCF Incubation requires, within ~60 days of focused outreach.

### F6 [P2] — v0.6.229+ signals pre-1.0 churn, no semver commitment posture

**Where it lives:** `docs/roadmap-v1.md` sets v0.7 = autonomy loops closed, v1.0 = stability declaration. `README.md` line 71 says "Pre-1.0 means no stability guarantees" (actually that's PHILOSOPHY.md line 197). The ecosystem snapshot in sylveste-roadmap.md shows plugins at 0.1.x, 0.2.x, 0.6.x — heterogeneous and unco-ordinated versioning.

**Why it fails the foundation-reviewer bar:** Pre-1.0 signals to foundation reviewers that the project is "not yet serious about external stability contracts." v0.6.229 is a particularly bad tell — high minor-minor-patch depth signals churn without semver discipline. CNCF Sandbox accepts pre-1.0 but Incubation requires at least a documented stability policy. Foundation-credible projects either ship semver discipline aggressively (every minor is a promise) or cut a 1.0 line.

**Failure scenario:** A downstream distributor (package maintainer for a Linux distro, or an enterprise internal-mirror team) wants to ship Sylveste. They need to know "if we pin v0.7.3, what is the support story?" There is no documented answer. The distribution doesn't happen.

**Fix:** Add `docs/stability-policy.md` with one section per component (kernel stable/unstable, OS stable/unstable, plugin spec v1 stable, individual plugins pre-1.0). Honest is fine — the `CLAUDE.md` + `AGENTS.md` discipline is already pedagogically valuable; just externalize the posture.

## Layer-for-Stage-2 Recommendation

**Stage 2 should deep-dive the PLUGIN-SUBSTRATE layer** — the Interverse plugin spec + `docs/canon/` + the 58-plugin conformance landscape.

Rationale:
1. This is the one scope where governance can be bolted on first without refactoring the kernel or OS. Standardizing the plugin spec does not require touching `core/intercore/` internals.
2. It is the candidate dependency-lock-in artifact (analogous to OpenMetrics for Prometheus). Hardening it into a formal spec creates the permanence mechanism CNCF graduation requires.
3. It is the widest surface where external contributors can legitimately participate — the kernel and Clavain OS are too opinionated and BDFL-dependent to accept external contribution today, but a new plugin or a conformance fix is exactly the scale that onboards contributor #2 through #10.
4. `docs/canon/plugin-standard.md` already exists as the doctrine — the delta to a CNCF-grade spec is formatting + versioning + conformance suite, not new thinking.
5. Makes the most sense as the scope for the first `SIG` charter (`docs/sigs/sig-plugins.md`) because the ownership boundaries are cleanest.

## Concrete Actions

1. **Ship the governance artifact bundle this week** (1-2 days). `CODE_OF_CONDUCT.md`, `SECURITY.md`, `GOVERNANCE.md`, `MAINTAINERS.md`, expand `CONTRIBUTING.md`. All copy-pasteable from CNCF templates + 10% Sylveste-specific customization. This moves the project from "absent at procurement gate" to "passes procurement gate" overnight.

2. **Promote `docs/canon/plugin-standard.md` to `docs/specs/interverse-plugin-spec-v1.md`** (2-3 weeks). Add version, status, conformance language. Ship `scripts/test-plugin-conformance.sh`. Open `docs/rfcs/` process. Land one RFC for spec v1.1 as the example. This turns the plugin substrate into an adoptable specification — the lock-in artifact.

3. **Define contributor ladder + first SIG charter** (2-3 days). `GOVERNANCE.md` gets the 3-rung ladder (Contributor / Reviewer-scoped / Maintainer-scoped). `docs/sigs/sig-plugins.md` is the first SIG with a real charter, scope, current maintainer. This is the structural scaffolding that lets contributor #2 through #10 arrive without overloading the BDFL.

## Decision-Lens Self-Check

Would Sylveste survive a CNCF Sandbox-to-Incubation review today? **No.** Governance-artifact absence is disqualifying at the Sandbox gate; contributor-ladder absence and zero named external users cap the ceiling at Sandbox. After F1+F2+F3+F4 are shipped? **Yes for Sandbox**, with a clear 12-18 month path to Incubation gated on F5 (named external adopters) and F6 (semver commitment).
