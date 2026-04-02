# Flux-Drive Review: Interflux Reaction Round Activation Plan

**Reviewed:** 2026-04-01 (Round 2 — esoteric-domain focus)
**Input:** `docs/plans/2026-04-01-interflux-reaction-round-activation.md`
**Bead:** sylveste-g3b
**Round 1 Agents:** 8 (fd-architecture, fd-quality, fd-systems, fd-evidence-pipeline-integrity, fd-japanese-sword-polishing-togishi, fd-ottoman-waqf-endowment, fd-tibetan-terma-concealment, fd-raga-melodic-grammar)
**Round 2 Agents:** 5 (fd-talmudic-machloket-preserved-dissent, fd-ice-core-multiproxy-reconciliation, fd-shipibo-kene-synesthetic-convergence, fd-reaction-prompt-semantics, fd-synthesis-deduplication)
**Verdict:** needs-changes
**Gate:** FAIL (6 P1, 6 P2 after dedup across both rounds)

## Agent Summary

| Agent | Category | Round | Verdict | Findings |
|-------|----------|-------|---------|----------|
| fd-architecture | Technical | 1 | needs-changes | 1 P1, 1 P2 |
| fd-quality | Technical | 1 | needs-changes | 1 P1, 1 P2 |
| fd-systems | Cognitive | 1 | safe | 1 P2 |
| fd-evidence-pipeline-integrity | Adjacent | 1 | needs-changes | 1 P1, 1 P2 |
| fd-japanese-sword-polishing-togishi | Distant-Domain | 1 | safe | 1 P2 |
| fd-ottoman-waqf-endowment | Distant-Domain | 1 | safe | 1 P2 |
| fd-tibetan-terma-concealment | Distant-Domain | 1 | safe | 1 P2 |
| fd-raga-melodic-grammar | Distant-Domain | 1 | safe | 0 |
| **fd-talmudic-machloket-preserved-dissent** | **Esoteric-Priority** | **2** | **needs-changes** | **2 P1, 1 P2** |
| **fd-ice-core-multiproxy-reconciliation** | **Esoteric-Priority** | **2** | **needs-changes** | **1 P1, 2 P2** |
| **fd-shipibo-kene-synesthetic-convergence** | **Esoteric-Priority** | **2** | **needs-changes** | **2 P1, 1 P2** |
| fd-reaction-prompt-semantics | Project | 2 | needs-changes | 1 P1, 1 P2 |
| fd-synthesis-deduplication | Project | 2 | needs-changes | 2 P1, 1 P2 |

---

## Round 2 — New P1 Findings (esoteric-domain and project agents)

The following findings are NEW from Round 2 agents, not found in Round 1. They are presented first because they represent genuinely novel perspectives from maximally distant domains.

### NEW-P1-01: Sycophancy detection thresholds are inert for typical agent populations [TALMUDIC-01]

**Agent:** fd-talmudic-machloket-preserved-dissent
**File:** `interverse/interflux/config/flux-drive/reaction.yaml:18-19`
**Convergence:** Round 2 only (talmudic, reaction-prompt-semantics)
**Lens:** Prohibition against mere assent — a sage who says "I agree" without independent reasoning is not counted as a second voice

The sycophancy detection uses `agreement_threshold: 0.8` and `independence_threshold: 0.3`. With 5-10 agents in a typical flux-drive review, even a single dissent drops the agreement rate below 0.8. For 7 agents: 6 agree + 1 disagree = 0.857 (barely triggers). 5 agree + 2 disagree = 0.714 (does not trigger). The threshold only fires when literally every agent agrees, which is the trivial case the convergence gate already handles.

**Talmudic diagnosis:** In the sugya structure, a sage's agreement "counts" only when accompanied by independent reasoning. The Talmud's counting rules are calibrated for the actual population size of the academy. The sycophancy thresholds were designed for a population that does not exist in practice.

**Failure scenario:** Agents systematically defer to high-confidence peers (e.g., fd-safety P0 findings attract reflexive agreement), but detection never flags it because one or two agents always produce unrelated findings, keeping the global agreement_rate below 0.8.

**The plan does not validate these thresholds.** No task computes actual agreement_rate from historical reviews.

**Fix:** Calibrate thresholds for the actual population (5-10 agents). Consider per-finding sycophancy (fraction of reactions to a specific finding that are hearsay) rather than per-review global sycophancy. With 7 agents, a threshold of 0.6-0.7 would be sensitive to actual deference patterns.

---

### NEW-P1-02: Plan does not verify minority finding preservation in synthesis [TALMUDIC-02]

**Agent:** fd-talmudic-machloket-preserved-dissent
**File:** `interverse/intersynth/agents/synthesize-review.md:39`, plan Task 4
**Convergence:** Round 2 only (talmudic, synthesis-dedup)
**Lens:** Preserved dissent as load-bearing — Beit Shammai's opinions are recorded not as curiosities but as legal elements that future courts can reinstate

Task 4 checks whether `synthesis.md` contains "Reaction Analysis / Contested Findings sections" and whether `findings.json` has `reactions` arrays. It does NOT verify the critical semantic property: that minority findings (net-negative reaction scores) are preserved with `verdict: contested` rather than suppressed.

The synthesize-review.md spec (Step 3.7) says divergent findings get `verdict: contested`, but there is no minimum-severity floor. A P0 finding from Phase 2 that receives three "disagree" reactions could be demoted below the inclusion threshold.

**Failure scenario:** A legitimate P0 from fd-safety is contested by three agents lacking safety expertise. Synthesis weights majority reaction and buries the finding. The safety issue ships.

**Fix:** Add to Task 6 checklist: "Verify that a P0/P1 finding with net-negative reaction score appears in synthesis.md with contested status and is not dropped from findings.json." Verify synthesize-review.md has a severity floor for P0/P1.

---

### NEW-P1-03: Lorenzen move taxonomy lacks partial-distinction (shinnuy) [TALMUDIC-03]

**Agent:** fd-talmudic-machloket-preserved-dissent
**File:** `interverse/interflux/config/flux-drive/discourse-lorenzen.yaml:6-10`, `reaction-prompt.md:40-44`
**Convergence:** Round 2 only (talmudic — unique finding)
**Lens:** The Talmudic shinnuy (distinction that narrows scope) has no equivalent in the move taxonomy

Move types are: attack, defense, new-assertion, concession. The reaction prompt's Move Type Assignment section maps disagree->attack, agree-with-evidence->defense, missed-this->new-assertion, agree-withdrawing->concession. There is no mapping for `partially-agree`, which means "I agree with part of this finding but its scope should be narrower."

Agents choosing `partially-agree` stance have no guidance on move type. The prompt says they may omit it, producing `move_legality: null` in Lorenzen validation.

**Fix:** Add `partially-agree` mapping to reaction-prompt.md (e.g., "partially-agree with scope narrowing -> defense if you provide narrowing evidence, attack if you dispute the broader claim") or add a `distinction` move type to discourse-lorenzen.yaml.

---

### NEW-P1-04: Fixative timing not validated — LLM orchestrator may parallelize [SHIPIBO-01]

**Agent:** fd-shipibo-kene-synesthetic-convergence
**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md:27-42`, plan Task 3
**Convergence:** Round 2 only (shipibo, reaction-prompt-semantics)
**Lens:** Melodic capture — a shaman who hears a neighbor's icaro before stabilizing their own vision risks perceptual contamination; the meraya redirects attention to unsung regions, but only if the redirect happens before others have committed their melodies

Phase ordering in reaction.md is correct: Step 2.5.2b (fixative) -> Step 2.5.3-4 (dispatch). But reaction.md is interpreted by an LLM, not executed as code. If the orchestrator parallelizes steps (tempting since 2.5.2a/2.5.2b/2.5.3-4 appear independent), fixative context may be empty when reactions dispatch.

**Shipibo diagnosis:** The meraya's redirect must happen DURING the group ceremony but BEFORE individual shamans commit their icaros. If the redirect arrives after commitment, it is ignored. The fixative is the computational meraya, and its timing relative to reaction dispatch is the critical ordering constraint.

**Fix:** Add to Task 3: "Verify fixative_context is non-empty when it should be (create a test case with high Gini / low novelty). Verify fixative text appears in the reaction prompt sent to agents." Consider adding an explicit sequencing note in reaction.md: "Step 2.5.2b MUST complete before Step 2.5.3 begins — do not parallelize."

---

### NEW-P1-05: No validation of single-pass enforcement [ICE-CORE-01]

**Agent:** fd-ice-core-multiproxy-reconciliation
**File:** `interverse/interflux/scripts/findings-helper.sh:69`, `phases/reaction.md`
**Convergence:** Round 2 only (ice-core — unique finding)
**Lens:** Reconciliation paradox — each reconciliation cycle erodes the independence it exploits; ice core labs minimize revision cycles

The `read-indexes` function correctly skips `*.reactions` files, preventing reaction outputs from being included in a subsequent convergence gate computation. This is the single-pass enforcement mechanism. However, the plan does not test this property. The `max_reactions_per_agent: 3` config limits volume but not cycles.

**Ice-core diagnosis:** In multi-institutional core analysis, the reconciliation meeting is explicitly limited to a single pass. The plan should verify that no mechanism exists for reactions to trigger counter-reactions. If `.reactions.md` outputs were placed in a path that `read-indexes` would scan (e.g., named without the `.reactions` suffix), a recursive loop could form.

**Fix:** Add a negative test to Task 3: after reactions complete, run the convergence gate again and verify reaction files are NOT included. This confirms single-pass enforcement.

---

### NEW-P1-06: Synthesis may count reaction count instead of weighted reaction score [SYNTHESIS-01]

**Agent:** fd-synthesis-deduplication
**File:** `interverse/intersynth/agents/synthesize-review.md:37-43`
**Convergence:** Round 2 only (synthesis-dedup, talmudic)
**Lens:** Deduplication integrity — do hearsay-tagged reactions actually get zeroed in convergence computation, or just tagged?

The hearsay rule (reaction.yaml `convergence_weight_hearsay: 0.0`) correctly specifies zero weight for echo-confirmations. Step 3.7b in synthesize-review.md tags reactions as `hearsay: true/false`. Step 3.7 applies conductor scoring where convergent = ">50% agree" gives confidence boost.

The question is whether the ">50% agree" computation uses raw reaction count or weighted reaction score. If it counts `agree` reactions regardless of hearsay tag, a finding with 3 hearsay "agree" and 1 independent "disagree" shows 75% agreement — convergent. With hearsay weighting, it should show 0/1 = 0% independent agreement — divergent.

The synthesize-review.md spec is ambiguous. It says "Convergent (>50% agree)" without specifying whether this means raw count or weighted count. The plan (Task 4) does not test this distinction.

**Fix:** Add to Task 4: "Verify that a finding with 2 hearsay-agree reactions and 1 independent-disagree reaction is classified as divergent/contested, not convergent."

---

## Round 2 — New P2 Findings

### NEW-P2-01: Agent identity in reaction prompts enables reputation-anchoring [ICE-CORE-02]

**Agent:** fd-ice-core-multiproxy-reconciliation
**File:** `interverse/interflux/config/flux-drive/reaction-prompt.md:1-3`
**Lens:** Blind reconciliation protocols — some ice core reconciliation meetings use anonymous first passes to prevent proxy-reputation bias

The reaction prompt begins "You are **{agent_name}**" and peer findings are extracted from `{agent-name}.md` files. Agents see whether a finding comes from fd-safety vs fd-perception and may defer to authority rather than evidence.

**Fix:** Consider stripping agent names from peer findings in the reaction prompt. Not blocking, but relevant for reaction quality measurement.

---

### NEW-P2-02: Convergence gate uses title matching, not evidence overlap [ICE-CORE-03]

**Agent:** fd-ice-core-multiproxy-reconciliation, fd-shipibo-kene-synesthetic-convergence
**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md:9`
**Lens:** Common-depth-scale problem — proxy interpretations mapped to a common scale inherit systematic errors in that scale

The convergence gate computes `findings_with_2plus_agents / total_p0_p1_findings` but the matching algorithm for "same finding across agents" is undefined. The `read-indexes` output contains finding titles, not evidence references. Agents using different words for the same issue appear divergent; agents using similar words for different issues appear convergent.

**Convergent with Round 1 ARCH-01** — both identify the same gap (undefined matching algorithm) but the ice-core lens adds the common-reference-frame problem: if agents parse different intent from the document, their findings exist on different coordinate systems and title-based overlap is meaningless.

**Fix:** Same as ARCH-01: add a `convergence-gate` subcommand with evidence-overlap matching (Jaccard on file:line references).

---

### NEW-P2-03: No mechanism to detect convergence degradation after reactions [SHIPIBO-02]

**Agent:** fd-shipibo-kene-synesthetic-convergence
**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md`
**Lens:** Ceremony closure — when shamans' icaros harmonize spontaneously (not through mimicry), the ceremony approaches completion; kene corruption is when convergence happened through a dominant singer overwhelming weaker perceivers

**Convergent with Round 1 TOGISHI-01 and EVIDENCE-01** — all three identify the missing post-reaction measurement, but the Shipibo lens adds: convergence degradation after reactions signals kene corruption. If overlap_ratio DECREASED after the reaction round, agents talked past each other or the fixative actively disrupted healthy convergence. This is not just a missing metric — it is a diagnostic signal that should trigger human review.

**Fix:** Same as TOGISHI-01/EVIDENCE-01: add post-reaction convergence re-measurement. Flag reviews where `convergence_after < convergence_before - 0.2`.

---

## Round 1 P1 Findings (retained from prior review)

### P1-01: `convergence_after` has no computation step [EVIDENCE-01]

**Agent:** fd-evidence-pipeline-integrity
**File:** `interverse/interflux/skills/flux-drive/phases/reaction.md` (Step 2.5.5)

The plan's Task 5 specifies `convergence_after` in the Interspect context JSON, but the reaction phase never recomputes `overlap_ratio` after reactions complete. Step 2.5.0 computes `overlap_ratio` as the convergence gate input (`convergence_before`), and Step 2.5.5 (Report) only counts dispatched/produced/empty/errors. There is no step that re-runs `findings-helper.sh read-indexes` after reactions to compute a post-reaction overlap figure.

**Failure scenario:** The `interspect-reaction` evidence event is emitted with either a null `convergence_after` or a fabricated value, making before/after convergence comparison impossible. The Interspect flywheel cannot measure whether reaction rounds actually change convergence.

**Fix:** Add a Step 2.5.4b between dispatch completion (2.5.4) and report (2.5.5) that re-runs `findings-helper.sh read-indexes`, incorporates reactive additions from `.reactions.md` files into the overlap computation, and stores the result as `convergence_after`. Alternatively, defer evidence emission to after synthesis (Phase 3) where sycophancy data is also available, but document the ordering dependency.

---

### P1-02: Sycophancy data unavailable at emission time [EVIDENCE-02]

**Agent:** fd-evidence-pipeline-integrity, fd-architecture (convergent)
**File:** `docs/plans/2026-04-01-interflux-reaction-round-activation.md` (Task 5)

The plan's Task 5 places evidence emission at "the end of Phase 2.5" (Step 2.5.5) with context JSON including `sycophancy_flags` and `discourse_health`. However, sycophancy scoring (Step 3.8) and discourse health (Step 6.6 Sawyer Flow) are computed during Phase 3 synthesis. At the end of Phase 2.5, neither value exists.

**Failure scenario:** Evidence is emitted with empty/null sycophancy_flags and discourse_health, or the implementer guesses that these should be pre-computed, creating a divergence between what the plan says and what the synthesis agent expects.

**Fix:** Either (a) split evidence emission into two events -- a Phase 2.5 event with reaction mechanics only (`agents_dispatched`, `reactions_produced`, `convergence_before`) and a Phase 3 event with quality metrics (`sycophancy_flags`, `discourse_health`, `convergence_after`), or (b) move all evidence emission to the end of Phase 3 and update Task 5 accordingly.

---

### P1-03: findings-helper.sh `read-indexes` output format mismatch with convergence gate [ARCH-01]

**Agent:** fd-architecture, fd-quality (convergent)
**File:** `interverse/interflux/scripts/findings-helper.sh` lines 63-79

The plan's Task 1 says: "Verify it parses Findings Index blocks from agent `.md` files and outputs structured data." But the actual `read-indexes` command outputs tab-separated lines (`$base\t$line`) -- not structured JSON or a format directly consumable for computing `overlap_ratio`. The convergence gate (Task 2, reaction.md Step 2.5.0) needs to:

1. Parse the tab-separated output
2. Extract severity from each line (the format is `- SEVERITY | ID | "Section" | Title`)
3. Filter to P0/P1
4. Compute which findings appear in 2+ agents
5. Divide by total P0/P1 findings

None of this parsing logic exists in `findings-helper.sh` or anywhere else. The convergence gate computation is described in prose (reaction.md Step 2.5.0) but must be executed by the LLM host agent at runtime, not by a script. This means the convergence gate is an LLM-interpreted algorithm, not a deterministic computation.

**Failure scenario:** Different LLM sessions may compute `overlap_ratio` differently depending on how they parse the tab-separated output and determine "same finding across agents." Without a deterministic implementation, the gate is non-reproducible.

**Fix:** Either (a) add a `convergence-gate` subcommand to `findings-helper.sh` that outputs a JSON `{"overlap_ratio": 0.42, "p0_p1_count": 7, "overlapping": 3}`, making the gate deterministic, or (b) explicitly document in the plan that the convergence gate is LLM-interpreted and accept the variance, with a test in Task 2 that verifies the LLM computes the same ratio as a manual computation.

---

## P2 Findings (should fix before activation)

### P2-01: No lifecycle management for reaction artifacts [WAQF-01]

**Agent:** fd-ottoman-waqf-endowment
**Lens:** Institutional perpetuity -- the waqf endowment problem of self-enforcement

The plan creates `.reactions.md` files that are consumed by synthesis (Step 3.7) but there is no lifecycle defined for these artifacts. The `rm -f` in Step 2.5.1 cleans reactions from a previous run, but:

- If a flux-drive review is interrupted between Phase 2 (agent dispatch) and Phase 2.5 (reactions), stale agent outputs will have no corresponding reactions. A subsequent re-run of Phase 2.5 would produce reactions against the new agents' findings, not the stale ones, creating a mismatch.
- The plan has no "resume" semantics. If the reaction round itself is interrupted (e.g., 3 of 5 reactions produced), there is no mechanism to re-run only the failed ones.

**Fix:** Add a Step 2.5.0.5 that verifies agent output timestamps are from the current run before proceeding. For partial failures, consider a `--retry-reactions` flag that re-dispatches only agents without valid `.reactions.md` files.

---

### P2-02: The `*.reactions` glob exclusion pattern is incorrect in bash case statement [QUALITY-01]

**Agent:** fd-quality
**File:** `interverse/interflux/scripts/findings-helper.sh` line 69

The case pattern `*.reactions` uses shell glob matching, but `basename "$f" .md` strips the `.md` extension first. So a file named `fd-architecture.reactions.md` becomes `fd-architecture.reactions` after basename, which correctly matches `*.reactions`. However, the `*.reactions.error` pattern matches files like `fd-architecture.reactions.error.md` (which becomes `fd-architecture.reactions.error`). This works.

But: reaction files are named `{agent-name}.reactions.md` (per Step 2.5.3-4), while the `read-indexes` loop processes `*.md` files. The basename strip produces `{agent-name}.reactions`. The case `*.reactions` uses bash glob `*` which matches any prefix. This is correct.

**Actual issue:** The exclusion uses a case statement where patterns are `*.reactions` and `*.reactions.error`, but in bash `case`, the `*` glob only works if the case branch uses the right syntax. In fact, `*.reactions.error` is tested AFTER `*.reactions` in the same branch (separated by `|`), and `*.reactions` would already match `fd-architecture.reactions.error` because `*` is greedy in case patterns. Wait -- no, bash case patterns are non-greedy, and `*.reactions` requires the string to END with `.reactions`. The string `fd-architecture.reactions.error` does NOT end with `.reactions`, so it falls through to `*.reactions.error`. This is correct.

**Real issue is different:** The `case` patterns on line 68-69 are:
```
summary|synthesis|findings) continue ;;
*.reactions|*.reactions.error) continue ;;
```

This is correct syntax. However, the plan's Task 1 says to "verify it parses Findings Index blocks" but does not mention verifying the exclusion patterns. The exclusion is already correct, but the plan should explicitly note it as a verification checkpoint, not leave it implicit.

**Fix:** Add to Task 1: "Verify that `read-indexes` correctly excludes `*.reactions.md` and `*.reactions.error.md` files."

---

### P2-03: Missing convergence_after creates a broken before/after signal [TOGISHI-01]

**Agent:** fd-japanese-sword-polishing-togishi
**Lens:** Progressive irreversibility -- the uchigumori stage

The togishi tradition places the classification/judgment crystallization point at the penultimate polishing stage (uchigumori), where accumulated understanding crystallizes into final decisions. The plan's convergence gate (Step 2.5.0) is the PRE-reaction measurement, analogous to early-stage polishing where the blade's characteristics are only partially revealed.

The plan lacks the equivalent uchigumori moment -- the point of maximum understanding where the reaction round's impact is measured. The convergence gate fires before reactions, but there is no post-reaction assessment. This means the system makes irreversible decisions (emit evidence, proceed to synthesis) without the benefit of the information revealed by the reactions themselves.

This is structurally isomorphic to the P1-01 finding but the togishi lens adds: the post-reaction measurement is not just a nice-to-have metric -- it is the crystallization point where the system should decide whether to proceed to synthesis or flag the review as needing human intervention (if convergence got WORSE after reactions, something is wrong with the discourse).

**Fix:** Add a convergence re-measurement after reactions complete. If `convergence_after < convergence_before - 0.2` (convergence degraded significantly), flag the review as anomalous. This catches pathological reaction rounds where agents talk past each other.

---

### P2-04: No external audit of reaction quality [WAQF-02]

**Agent:** fd-ottoman-waqf-endowment
**Lens:** Judicial oversight (qadi role)

The plan has no separation between the agent that produces a reaction and the system that evaluates that reaction's quality. In waqf terms, the mutawalli (trustee/executor) is also the qadi (judge). The hearsay rule and sycophancy detection partially address this, but they operate in synthesis (Phase 3) -- AFTER the reactions have already been produced and consumed.

More concretely: Task 4 checks whether synthesis "contains Reaction Analysis / Contested Findings sections" but does not check whether the reactions themselves are well-formed. A reaction that says "agree" without evidence passes into synthesis and gets tagged as hearsay (weight 0.0), but a reaction with fabricated evidence (hallucinated file:line refs) passes with full weight.

**Fix:** Add to Task 4 or Task 6: verify that evidence fields in reactions reference real files and real line numbers. This could be a lightweight validation step in synthesis or a pre-synthesis check.

---

### P2-05: Feedback loop delay renders reaction evidence potentially stale [SYSTEMS-01]

**Agent:** fd-systems
**Lens:** Feedback loop timing

The plan's Task 5 creates an Interspect evidence pipeline: reaction outcomes -> interspect.db -> routing calibration -> future triage. But the plan does not document the feedback loop timing:

1. Interspect has a 48-hour quarantine (`INTERSPECT_QUARANTINE_HOURS=48`)
2. Routing overrides require counting-rule thresholds (multiple observations)
3. Reaction rounds are infrequent (only run when convergence is below 60%)

Combined delay: the first reaction evidence emitted today will not influence routing for days or weeks. If the reaction round is producing garbage (all sycophantic agreement, or all hearsay), the feedback loop is too slow to catch it before many reviews pass through.

**Fix:** Document the expected feedback loop latency in the plan. Consider a shorter quarantine for reaction evidence (e.g., 24h) or a "fast feedback" mode where the first 3 reaction rounds are manually reviewed for quality before relying on the automated pipeline.

---

### P2-06: Terma catalog gap -- no index of placed reactions [TERMA-01]

**Agent:** fd-tibetan-terma-concealment
**Lens:** Kha byang (prophetic catalog)

The terma tradition maintains a catalog (kha byang) of all concealed treasures with their retrieval conditions. The plan creates `.reactions.md` files and expects synthesis to consume them, but there is no manifest or index file that lists which agents produced reactions, which were skipped (convergence gate or empty peer findings), and which errored.

Step 2.5.5 produces a report line, but this is an inline log message, not a structured artifact. If synthesis needs to debug why a reaction is missing, it must infer from file absence (no `{agent}.reactions.md` = skipped or errored).

**Fix:** Write a `reactions-manifest.json` at the end of Step 2.5.4 with entries for each agent: `{agent, status: produced|skipped-empty-peers|skipped-convergence|error|timeout, output_path, dispatch_time, completion_time}`. Synthesis can then read this manifest instead of inferring state from file presence.

---

## Cross-Round Convergence Analysis

The most striking finding from this two-round review is the independent convergence across maximally distant epistemological frames on the same core gaps:

### Convergence Cluster 1: Undefined Matching Algorithm for Convergence Gate
- **Round 1:** ARCH-01 (fd-architecture, fd-quality) — "output format mismatch, LLM-interpreted steps"
- **Round 2:** NEW-P2-02 (fd-ice-core) — "common-depth-scale problem, proxy interpretations on different reference frames"
- **Round 2:** Implicit in fd-shipibo (kene field has multiple layers no single shaman perceives fully)
- **Confidence:** HIGH (5/13 agents across both rounds, 3 independent frames)

### Convergence Cluster 2: Missing Post-Reaction Measurement
- **Round 1:** EVIDENCE-01 (fd-evidence-pipeline-integrity) — "convergence_after has no computation step"
- **Round 1:** TOGISHI-01 (fd-togishi) — "missing uchigumori crystallization point"
- **Round 2:** NEW-P2-03 (fd-shipibo) — "no ceremony closure detection, kene corruption signal"
- **Confidence:** HIGH (3/13 agents, 3 independent frames)

### Convergence Cluster 3: Sycophancy/Authority Deference
- **Round 1:** Not flagged
- **Round 2:** NEW-P1-01 (fd-talmudic) — "prohibition against mere assent, thresholds inert"
- **Round 2:** NEW-P2-01 (fd-ice-core) — "blind reconciliation protocols, reputation-anchoring"
- **Novel to Round 2:** This cluster was entirely invisible to Round 1's agent pool. The esoteric-domain agents found it because their epistemological frameworks have explicit theories of authority contamination.

### Convergence Cluster 4: Minority Finding Preservation
- **Round 1:** Not flagged
- **Round 2:** NEW-P1-02 (fd-talmudic) — "Beit Shammai opinions are load-bearing legal elements"
- **Round 2:** NEW-P1-06 (fd-synthesis-dedup) — "hearsay count vs weighted score"
- **Novel to Round 2:** Also invisible to Round 1. The Talmudic lens treats preserved dissent as structurally necessary, not optional.

**Meta-observation:** Round 2's esoteric-domain agents produced 6 NEW P1 findings that Round 1's technical + general distant-domain agents missed entirely. The novelty rate from the three priority agents (talmudic, ice-core, shipibo) is notably higher than from Round 1's distant-domain agents (togishi, waqf, terma), suggesting that agents generated specifically for this task's domain outperform general-purpose esoteric agents.

---

## P3 Findings (suggestions)

### P3-01: The convergence gate threshold of 0.6 may be too low for typical reviews

Baseline data missing. Add to Task 2: run `read-indexes` on 3-5 existing flux-drive outputs and compute overlap_ratio.

### P3-02: Malformed agent files (flux-gen v5 character-per-line bug)

fd-raga-melodic-grammar and fd-session-memory-architecture have character-per-line corruption in "What NOT to Flag" and "Success Criteria" sections. Fix before use.

---

## Structural Isomorphisms (Distant-Domain Synthesis)

### Togishi: Progressive Irreversibility Gradient

The togishi lens reveals that the plan treats the reaction round as a single-pass process, but the sword-polishing tradition encodes a crucial insight: each stage reveals information that recontextualizes everything before it. The convergence gate (Step 2.5.0) is an early-stage measurement. Reactions are a middle stage that reveals new information. But the plan has no late stage where accumulated reaction evidence crystallizes into a judgment. The fix (P2-03) adds this missing stage.

The togishi also highlights that the plan's Task 3 ("test reaction dispatch end-to-end") should observe not just whether reactions fire, but whether the reactions reveal compound insights that no single agent found. This is the multi-source synthesis gap: reactions may individually be low-value, but their intersection may reveal a pattern.

### Waqf: Self-Enforcement vs. Memory-Dependent Mechanisms

The waqf lens asks: is the reaction round self-enforcing or does it depend on agents choosing to participate honestly? The hearsay rule (reaction.yaml) and sycophancy detection are enforcement mechanisms, but they are passive -- they tag bad reactions after the fact rather than preventing them. The waqf tradition preferred structural enforcement (automatic revenue allocation) over behavioral enforcement (trustee good faith).

The strongest structural enforcement mechanism in the plan is the convergence gate itself -- it prevents the reaction round from running when it would be vacuous. But within the reaction round, there is no structural enforcement against low-quality reactions. The hearsay rule is the closest analog, but it operates in synthesis, not during dispatch.

### Terma: Knowledge Placement Modalities

The terma lens highlights that reactions serve two distinct purposes that the plan conflates:

1. **Sa gter (earth treasure)**: Reactions that anchor to specific code locations (file:line evidence) -- discovered when you encounter that code again
2. **Dgongs gter (mind treasure)**: Reactions that add contextual understanding (severity assessments, rationale) -- activated when reviewing similar patterns

The plan's reaction-prompt.md template supports both modalities (Evidence field for sa gter, Rationale field for dgongs gter), but the synthesis agent treats them identically. Reactions with strong file:line evidence should carry more weight than those with only rationale, because the former is independently verifiable while the latter depends on the reaction agent's judgment quality.

---

## Missing Plan Steps (consolidated across both rounds)

1. **Baseline convergence measurement** (before Task 1): Run `read-indexes` on 3-5 existing review outputs to establish the normal overlap_ratio range. This grounds the 0.6 threshold.

2. **Post-reaction convergence recomputation** (between Task 3 and Task 4): After reactions fire, recompute overlap_ratio including reactive additions. Compare before/after. Flag anomalous reviews where convergence degraded.

3. **Reaction evidence validation** (in Task 4 or Task 6): Check that file:line references in reactions point to real files and real lines.

4. **Reactions manifest** (in Task 3): Write structured metadata about dispatch outcomes.

5. **Sycophancy threshold calibration** (in Task 2 or Task 6): Compute actual agreement_rate values from historical reviews. Calibrate thresholds for 5-10 agent populations.

6. **Minority preservation test** (in Task 6): Create a test case where a P0 finding receives majority-disagree reactions. Verify it survives in synthesis with contested status.

7. **Hearsay weighting integration test** (in Task 4): Verify that hearsay-tagged agrees are truly zeroed in conductor score computation, not just tagged.

8. **Single-pass negative test** (in Task 3): After reactions, re-run convergence gate and verify reaction files are excluded.

9. **Fixative timing test** (in Task 3): Create high-Gini/low-novelty test case. Verify fixative text appears in dispatched reaction prompts.

10. **Flux-gen agent quality check** (before any task): Fix character-per-line corruption in malformed agents.

---

## Execution Order Amendment (consolidated)

```
[Agent QA] ────────────────────────────────────────────────────────────┐
[Baseline] ─┐                                                          │
[Task 1] ───┼──┐                                                       │
[Task 2    ]│  │                                                       │
[+threshold]┘  ├─→ [Task 3 + manifest + fixative + single-pass tests]  │
               │    → [Task 4 + evidence val + hearsay + minority]  ───┼─→ [Task 6]
               │                                                       │
[Task 5*] ─────┘  (* split: Phase 2.5 event + Phase 3 event)  ────────┘
```

---

## Consolidated Findings Index (both rounds, deduplicated)

### P1 (6 findings — blocks activation)

| ID | Title | Source Agents | Round |
|----|-------|--------------|-------|
| ARCH-01 / NEW-P2-02 | Convergence gate matching algorithm undefined (LLM-interpreted, no deterministic impl) | fd-architecture, fd-quality, fd-ice-core | 1+2 |
| EVIDENCE-01 | convergence_after has no computation step | fd-evidence-pipeline-integrity | 1 |
| EVIDENCE-02 | Sycophancy/discourse data unavailable at Phase 2.5 emission time | fd-evidence-pipeline-integrity, fd-architecture | 1 |
| TALMUDIC-01 | Sycophancy detection thresholds inert for typical agent populations (5-10) | fd-talmudic, fd-reaction-prompt-semantics | 2 |
| TALMUDIC-02 / SYNTHESIS-01 | Minority finding preservation not verified; hearsay weighting may not be enforced in conductor score | fd-talmudic, fd-synthesis-dedup | 2 |
| TALMUDIC-03 | Lorenzen move taxonomy lacks partial-distinction (partially-agree has no mapping) | fd-talmudic | 2 |

### P2 (6 findings — should fix)

| ID | Title | Source Agents | Round |
|----|-------|--------------|-------|
| SHIPIBO-01 | Fixative timing not validated; LLM may parallelize Steps 2.5.2b and 2.5.3 | fd-shipibo, fd-reaction-prompt-semantics | 2 |
| ICE-CORE-01 | Single-pass enforcement not tested; no negative test for recursive reactions | fd-ice-core | 2 |
| ICE-CORE-02 | Agent identity in reaction prompts enables reputation-anchoring | fd-ice-core | 2 |
| WAQF-01 | No lifecycle management for reaction artifacts (no resume semantics) | fd-waqf | 1 |
| TERMA-01 | No manifest/catalog of reaction dispatch outcomes | fd-terma | 1 |
| SYSTEMS-01 | Feedback loop delay: 48h quarantine + counting rules = weeks before evidence influences routing | fd-systems | 1 |

### P3 (2 findings — suggestions)

| ID | Title | Source Agents | Round |
|----|-------|--------------|-------|
| QUALITY-01 | Plan does not verify reaction file exclusion patterns in read-indexes | fd-quality | 1 |
| TOGISHI-01 / SHIPIBO-02 | Post-reaction convergence degradation should trigger human review | fd-togishi, fd-shipibo | 1+2 |

---

## Verdict

**FAIL** — 6 P1 findings across two review rounds must be addressed before activation.

**Round 1 core gaps** (3 P1): Interspect evidence references data unavailable at emission time; convergence gate has no deterministic implementation; convergence_after is never computed.

**Round 2 core gaps** (3 P1, all NEW): Sycophancy thresholds are inert for real populations; minority findings may be silently dropped; Lorenzen move taxonomy is incomplete for the most common reaction stance (partially-agree).

**Round 2 added significant value.** The three priority esoteric-domain agents (talmudic, ice-core, shipibo) produced 6 NEW findings that Round 1 entirely missed, including 3 P1s. The Talmudic lens on preserved dissent and authority deference, the ice-core lens on single-pass enforcement and reputation-anchoring, and the Shipibo lens on fixative timing and perceptual sovereignty all identified failure modes that technical and general-purpose agents are structurally unable to see because they lack explicit theories of multi-perceiver independence.

**Recommended path:** Address the 6 P1 items in the plan document, add the 10 missing steps enumerated above, then execute the revised plan.
