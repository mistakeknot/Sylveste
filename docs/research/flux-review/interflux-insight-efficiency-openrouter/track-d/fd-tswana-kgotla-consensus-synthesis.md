### Findings Index
- P0 | TKC-1 | "Current Architecture / Synthesis" | Synthesis reads agent outputs incrementally — chief speaks before all voices finish
- P1 | TKC-2 | "Deduplication / Rule 1" | Dedup Rule 1 silences minority findings without attribution — uniquely cross-model findings are dropped
- P1 | TKC-3 | "Question / Model diversity as a signal" | Graduated speaking order not enforced — cheap/fast models complete first and their outputs are read first, biasing synthesis
- P2 | TKC-4 | "Synthesis / Verdict Computation" | Verdict computation uses unanimity (most severe wins) not consensus — productive cross-model disagreement is not preserved
- P3 | TKC-5 | "Reaction round" | Reaction round creates sycophancy pressure on cheaper models toward Claude's preliminary findings

Verdict: risky

---

## Agent: fd-tswana-kgotla-consensus-synthesis

**Persona:** A Tswana dikgosi (chief) who has presided over hundreds of kgotla assemblies and understands that a verdict which ignores dissent is illegitimate — the chief's authority comes from demonstrating that every voice was heard and weighed, not from imposing a majority view.

---

## Summary

The interflux synthesis phase has a legitimacy problem that will become critical when non-Claude models are added. In a single-family (all Claude) review, the homogeneous training biases mean that convergence and divergence patterns are not particularly informative — every voice at the kgotla comes from the same village. When Claude and DeepSeek agents sit together in the kgotla, their disagreements become the most valuable signal in the review. But the current synthesis architecture has no structural protection for minority findings, allows incremental reading (chief decides before all voices are heard), and applies a unanimity rule (most severe wins) instead of a consensus rule (every position is attributed). The kgotla will be illegitimate by the time the multi-model integration is complete.

---

## Findings

### P0 | TKC-1 | Synthesis reads agent outputs incrementally — chief speaks before all voices finish

**Location:** `interverse/interflux/docs/spec/core/synthesis.md` §Step 1-2 — the orchestrator validates and collects agent outputs as they complete, building the findings map progressively.

**Kgotla diagnosis:** The dikgosi of a kgotla does not speak until the last speaker finishes. This is not courtesy — it is structural protection against the dikgosi's status influencing speakers who have not yet spoken. The synthesis algorithm in flux-drive collects findings as agents complete. In the current single-family architecture this is low-risk: all Claude agents complete within a similar time window. With OpenRouter integration, the dispatch timing becomes asymmetric: Haiku-tier and OpenRouter models (DeepSeek V3) complete faster than Opus. The synthesis orchestrator will have received and partially processed fast-model findings before slow-model (Opus structural) findings arrive.

**Failure scenario:** A review dispatches 4 agents: fd-architecture (Opus, slow), fd-correctness (Haiku, fast), DeepSeek-coverage (OpenRouter, fast), fd-safety (Sonnet, medium). The orchestrator receives findings in order: DeepSeek → fd-correctness → fd-safety → fd-architecture. The orchestrator begins building the findings map as DeepSeek completes. It notes 3 P2 findings from the coverage agent. When fd-architecture completes with a P0 structural finding, the synthesis is already partially formed. The P0 is added, but the orchestrator's framing (shaped by the 3 P2s seen first) influences how the P0 is contextualized in the summary. The chief spoke before the last voice was heard.

**Concrete implementation risk:** `synthesis.md` §Step 2 uses "two-tier collection strategy" with index-first reading. If the orchestrator implements this as a streaming loop (read each agent's findings index as they complete, process immediately), the incremental bias exists. If implemented as a barrier (wait for all agents to complete, then read all indexes in one pass), the bias does not exist.

**Does the current implementation use a streaming loop or a barrier?** This is the P0 question. If the answer is "streaming loop," the fix is a one-line change: move the findings collection loop after an explicit barrier that waits for all agents to complete.

**Smallest viable fix:** Add a documented barrier requirement to `synthesis.md` §Step 1:
```
MUST: Collect all agent outputs completely before beginning findings processing.
MUST NOT: Process any agent's findings before all agents have completed or timed out.
```

---

### P1 | TKC-2 | Deduplication Rule 1 silences minority findings without attribution

**Location:** `interverse/interflux/docs/spec/core/synthesis.md` §Step 3 "Rule 4: Conflicting severity → Use highest" and the deduplication merge behavior

**Kgotla diagnosis:** A kgotla verdict that ignores a dissenting position is illegitimate. The dissenting voice does not need to prevail — it needs to be explicitly addressed and weighed. The synthesis deduplication rules handle within-family disagreement through severity conflicts (Rule 4) and recommendation conflicts (Rule 5). But Rule 1 (merge same issue, same file:line) uses a merge function that, for the `agents` array and descriptions, preserves all agent attributions. This looks correct until cross-family integration reveals the gap: what happens when Claude flags a finding as P1 and DeepSeek flags the same finding as P3? Rule 4 uses the most severe (P1). The DeepSeek P3 position is recorded in `severity_conflict`. This part is correctly kgotla-like.

**The legitimacy failure:** The synthesis summary report (`synthesis.md` §Step 7) does not require presenting severity conflicts in the human-readable output. The `findings.json` records `severity_conflict`, but `summary.md` only mentions conflicts: "7. Conflicts (if any severity disagreements)" — a single section that appears at the end, after all the action items are already listed. A finding where Claude says P1 and DeepSeek says P3 appears in the "Issues to Address" section as P1, with the DeepSeek dissent buried in the conflicts section. The community (user) sees the verdict without the dissent clearly attributed.

**Why this matters specifically for cross-model integration:** When Claude and DeepSeek disagree, the disagreement is high-signal (cross-family kotekan, see JGC-4). A Claude P1 that DeepSeek rates P3 is not "Claude was right and DeepSeek was wrong" — it may mean Claude's training biases toward that pattern being a problem, while DeepSeek's training (different data distribution) does not. The user needs to see this disagreement prominently, not buried.

**Smallest viable fix:** Modify the findings presentation in `synthesis.md` §Step 7 to inline cross-family severity conflicts:
```markdown
- [ ] **P1** | Session tokens stored in localStorage (Authentication)
  ⚠️ Cross-model disagreement: Claude (fd-architecture): P1 | DeepSeek: P3 — verify independently
```

The `⚠️ Cross-model disagreement` annotation surfaced inline (not in a separate Conflicts section) gives the dissenting voice standing in the verdict, not footnote status.

---

### P1 | TKC-3 | Graduated speaking order not enforced — fast models read first, biasing synthesis

**Location:** `input.md` § "Question / Model diversity as a signal" and `synthesis.md` §Step 2

**Kgotla diagnosis:** In kgotla deliberations, junior members speak first precisely to prevent the seniority halo from shaping their testimony. If the senior members (elders, the dikgosi's advisors) speak first, junior members adjust their positions toward agreement even if their independent assessment differs. The synthesis equivalent is reading order: in what order are agent findings read and processed by the orchestrator?

**The graduation problem:** In a multi-model review, "junior" corresponds to cheap/fast models (DeepSeek, Haiku) and "senior" corresponds to Claude Opus. The kgotla principle requires reading junior findings first — before Opus has shaped the synthesis frame. But in practice, if the orchestrator reads agent outputs in the order: "1. collected as they completed → 2. processed in collection order," then Opus findings (arriving last, being slow) are read last. The synthesis frame is already established by the faster models before the senior architectural judgment arrives. This is the inverted graduation: seniors effectively speak first by arriving last into an already-established frame.

**Does this matter?** The synthesis algorithm claims to be deterministic (verdict from severity levels, not interpretation). But the "Key Findings" section in `summary.md` is not strictly deterministic — the orchestrator writes prose summaries. If fd-architecture arrives after the findings map is already assembled, the orchestrator's prose framing of the P0 structural finding will be influenced by the 5 P2 findings from faster models it already processed. This is the sycophancy pressure from the junior side: the frame is set by the fast, cheap, junior voices; the senior voice is integrated into an existing frame rather than establishing the frame independently.

**Smallest viable fix:** Explicit reading order policy in `synthesis.md` §Step 2:
```
SHOULD: Read agent outputs in reverse cost order (cheapest/fastest last, most expensive first).
Rationale: Preserves independence of high-judgment findings by establishing the synthesis frame
from structural analysis before coverage analysis.
```

This is a behavioral change to the orchestrator's loop order, not a structural change.

---

### P2 | TKC-4 | Verdict computation uses unanimity not consensus

**Location:** `interverse/interflux/docs/spec/core/synthesis.md` §Step 5 "Verdict Computation"

**Kgotla diagnosis:** Kgotla seeks consensus, not unanimity. Consensus means: everyone can live with the outcome, even if they don't agree. Unanimity means: everyone agrees. The synthesis verdict computation uses a unanimity-adjacent rule: "If any P0 finding → risky." This means a single agent's P0 finding produces a "risky" verdict regardless of what the other 5 agents said about the same content. In a single-family review, this is acceptable because trust multipliers and interspect feedback calibrate agent quality over time.

**Cross-family impact:** When a DeepSeek gambang-layer agent produces a P0 finding that no Claude agent reported (cross-family singleton), the verdict becomes "risky" based on a single low-confidence finding. The dissenting majority (5 Claude agents found no P0) cannot overcome the unanimity rule. The kgotla would recognize this as illegitimate: the dissenting majority's position is ignored, and the single voice produces the verdict.

**The fix is not to change the unanimity rule for all cases** — the P0 unanimity rule is correct when the P0 comes from fd-safety or fd-architecture (high-trust structural agents). The fix is to weight the unanimity rule by trust and family provenance:

```
verdict:
  risky if:
    - any P0 from a gong-layer (structural) agent, OR
    - any P0 with cross_family_convergence >= 2 (at least 2 families agree), OR
    - any P0 with within_family_convergence >= 3
  needs-changes if:
    - any P0 from single gambang-layer agent only (flag as "unverified P0 — verify independently")
```

This preserves the legitimate authority of the structural agents while requiring a higher legitimacy bar for coverage-layer P0 claims.

---

### P3 | TKC-5 | Reaction round creates sycophancy pressure on cheaper models

**Location:** `input.md` § "Reaction round: Inter-agent critique with discourse topology, sycophancy detection, hearsay filtering"

**Kgotla diagnosis:** The reaction round is a significant kgotla governance mechanism — inter-agent critique that allows agents to respond to each other's findings. The "sycophancy detection" already addresses the core concern (detecting when agents uncritically agree). But when multi-model integration arrives, the sycophancy pressure becomes asymmetric: cheaper/faster models (DeepSeek, Haiku) will see Claude Opus's findings during the reaction round and will systematically adjust toward agreement. This is the inverted graduation problem from TKC-3 applied to the reaction round.

**The structural concern:** DeepSeek agents in the reaction round receive Claude Opus's preliminary findings as context. DeepSeek's training (RLHF, preference data) may include patterns that favor deferring to authoritative-sounding prior art — a form of learned sycophancy toward high-confidence, well-structured outputs. Claude Opus produces high-confidence, well-structured outputs. The reaction round creates exactly the conditions where DeepSeek's sycophancy tendencies are most likely to activate.

**Suggested fix:** The reaction round should be stratified by density layer. Intra-layer reactions (gambang reviewing gambang, saron reviewing saron) preserve independence. Cross-layer reactions (gambang reviewing gong) are a legitimacy risk and should be optional/flagged. The `cross-ai.md` phase already handles cross-model comparison — the reaction round should focus on within-layer critique to preserve the independence that makes the kgotla legitimate.

---

## Decision Lens Assessment

Does the synthesis phase structurally protect minority findings and attribute dissent, or does it privilege majority convergence and discard outliers?

**Current state:** The synthesis phase privileges convergence (higher confidence for multi-agent agreement) and applies a formal severity-conflict record (`severity_conflict` in findings.json) but does not surface dissent prominently in the human-readable output. Cross-family disagreements are not distinguished from within-family disagreements in confidence scoring.

**Critical gap for OpenRouter integration:** The kgotla governance structures needed for legitimate multi-family synthesis are not in place. Adding Claude + DeepSeek to the same review without fixing TKC-1 (barrier semantics), TKC-2 (inline dissent attribution), and TKC-3 (reading order) means the synthesis will appear to have processed all voices while structurally privileging fast-model framing and burying cross-model dissent.

**Required additions before multi-model synthesis is production-ready:**
1. Explicit barrier requirement in synthesis (TKC-1) — all voices heard before verdict
2. Inline cross-family dissent attribution in summary.md (TKC-2) — dissent gets standing, not footnotes
3. Reading order policy that preserves senior voice independence (TKC-3) — graduated speaking order

These are documentation/behavioral additions to the synthesis spec and orchestrator implementation. No structural changes to agent files needed.
