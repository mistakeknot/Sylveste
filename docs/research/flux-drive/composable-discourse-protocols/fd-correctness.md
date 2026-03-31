---
reviewed: 2026-03-31
reviewer: fd-correctness (Julik)
bead: sylveste-rsj.7
plan: docs/plans/2026-03-31-composable-discourse-protocols.md
---

# Composable Discourse Protocols — Correctness Review

## Invariants

Before detailing findings, the invariants that must hold for this system to be correct:

1. **Synthesis input completeness.** Every field the synthesis agent reads from a reaction file must either exist or have a documented nil-safe fallback. Missing fields must not cause silent mis-scoring.
2. **findings.json single-writer.** Only one writer populates each top-level key in findings.json. Concurrent writers to the same key produce undefined JSON.
3. **discourse-health.sh precondition.** The script reads findings.json; findings.json is written by the synthesis subagent. Execution order must guarantee findings.json exists and is fully flushed before discourse-health.sh reads it.
4. **convergence gate coherence.** When `subsume_convergence_gate: true`, the existing `skip_if_convergence_above` check in reaction.yaml must either be disabled or explicitly delegated to sawyer. A reaction round that skips itself based on stale/absent health data corrupts convergence semantics.
5. **Config path resolution.** lorenzen.yaml and sawyer.yaml are referenced by the synthesis agent and by discourse-health.sh. Both must resolve the path from their own working context, which may differ from the orchestrator's cwd.
6. **Model capability contract.** haiku (the synthesis model) must be able to reliably execute the validation logic described in Step 3.7c. If the model cannot reliably distinguish "evidence different from original finding" vs. "evidence restating original finding," the legality scores are noise not signal.

---

## Findings Index

- P0 | CDP-01 | "Task 6 / findings.json write ordering" | Orchestrator merge of `discourse_health` is a race: synthesis subagent may not have flushed findings.json before the orchestrator reads it
- P1 | CDP-02 | "Task 2 / reaction output contract" | Existing reaction outputs lack `Move Type`; synthesis Step 3.7c has no nil-safe path for missing field
- P1 | CDP-03 | "Task 1 / sawyer subsumption" | `subsume_convergence_gate: true` makes the reaction round depend on a health score that does not exist on the first invocation
- P2 | CDP-04 | "Task 5 / haiku model capability" | Move legality validation requires cross-referencing evidence strings that haiku reliably hallucinates at fine-grained equality checks
- P2 | CDP-05 | "Task 3 / novelty_rate definition" | discourse-health.sh defines novelty via `convergence == 1` in findings.json, but findings.json uses `convergence_corrected` for stemma-corrected counts; the two values diverge silently
- P2 | CDP-06 | "Task 6 / two-writer schema conflict" | findings.json is written by intersynth:synthesize-review and then mutated by the orchestrator; no atomic merge strategy is defined
- P3 | CDP-07 | "Task 1 / lorenzen move-type naming" | Canonical move names in lorenzen.yaml (`new_assertion`) differ from reaction-prompt.md (`new-assertion` / `missed-this`); synthesis Step 3.7c pattern-matches on agent text

---

## Finding Detail

### CDP-01 — P0 — Orchestrator merge of `discourse_health` is a race

**Location:** Task 6 (`synthesize-review.md`), Task 4 (`synthesize.md` Step 3.9)

**The invariant broken:** findings.json single-writer (invariant 2) and discourse-health.sh precondition (invariant 3).

**Interleaving that causes corruption:**

1. The orchestrator launches `intersynth:synthesize-review` as a subagent Task (synthesize.md Step 3.2).
2. The subagent writes `{OUTPUT_DIR}/findings.json` and returns its compact summary to the orchestrator.
3. The orchestrator executes Step 3.9 (Task 4): `bash discourse-health.sh "{OUTPUT_DIR}"`.
   - This is well-ordered so far.
4. discourse-health.sh writes `{OUTPUT_DIR}/discourse-health.json`.
5. Per Task 6, the synthesis agent's `discourse_health` block is described as "populated by the orchestrator after running discourse-health.sh." This means the orchestrator must **write back into findings.json** — merging a new top-level key.

The plan says "The orchestrator merges them when reading findings.json" (Task 6, final paragraph). But findings.json was already written by the synthesis subagent (Step 8 of synthesize-review.md). A second write by the orchestrator is a clobber risk:

- If the orchestrator reads the full JSON, injects `discourse_health`, and rewrites the file atomically (write-to-temp + rename), this is safe but unspecified.
- If it uses a naive append or in-place edit, it corrupts JSON.
- If a downstream consumer (e.g., beads creation in Step 3.6, compounding agent) reads findings.json between the synthesis subagent's write and the orchestrator's merge write, it reads a stale schema that lacks `discourse_health`.

There is no atomic merge protocol defined anywhere in the plan. The phrase "merges them" is implementation-unspecified.

**Minimum correct fix:** findings.json must have a single complete write. Either (a) the synthesis subagent waits for discourse-health.json, reads it, and writes a unified findings.json in one pass, or (b) the orchestrator re-writes findings.json atomically (parse → inject → write-to-temp → rename) and no step reads findings.json between the synthesis write and the orchestrator merge. Option (a) is cleaner because it keeps synthesize-review.md as the sole writer of findings.json. The plan's current split-writer design violates the single-writer invariant with no compensating mechanism.

---

### CDP-02 — P1 — Missing `Move Type` field breaks synthesis on existing reaction outputs

**Location:** Task 2 (reaction-prompt.md modification), Task 5 (synthesize-review.md Step 3.7c)

**The invariant broken:** Synthesis input completeness (invariant 1).

The plan modifies reaction-prompt.md to add the `Move Type` field to the output contract (Task 2). Step 3.7c in synthesize-review.md then parses this field:

> "validate each reaction's move legality... attack (disagree): Must have non-empty Evidence field..."

The synthesis agent classifies each reaction by `Move Type`. If `Move Type` is absent — which it will be for any reaction output produced before this plan ships — the synthesis agent receives no guidance on how to proceed.

The plan defines no fallback. There is no instruction in Step 3.7c saying "if Move Type is missing, skip legality validation" or "infer Move Type from Stance." The synthesis agent (haiku) will either:

(a) Silently assign `move_legality: invalid` to all old-format reactions (because the evidence check fails against an absent type), or
(b) Attempt to infer the move type from Stance, but `disagree` maps to `attack` while `agree` maps to either `defense` or `concession` depending on whether the agent withdrew its claim — a distinction that is not present in the old format.

In practice haiku will choose (b) with inconsistent results, producing garbage legality scores for any rollout where old agents produce reactions before the new prompt template is deployed.

**Rollout window:** Because multiple agents may run the reaction round in parallel, and because reaction.yaml controls the prompt template while agents are stateless, there is a window where some agents use the old template (no Move Type) and some use the new one. The plan does not address this.

**Minimum correct fix:** Add to Step 3.7c: "If `Move Type` field is absent, skip legality validation for that reaction entirely. Set `move_legality: null, legality_score: null`. Do not attempt to infer Move Type from Stance alone." This makes old-format reactions transparent nulls rather than corrupted scores.

---

### CDP-03 — P1 — `subsume_convergence_gate: true` creates a bootstrap deadlock

**Location:** Task 1 (sawyer.yaml), reaction.yaml `skip_if_convergence_above: 0.6`

**The invariant broken:** Convergence gate coherence (invariant 4).

sawyer.yaml declares:
```yaml
subsume_convergence_gate: true
```

The prose comment says: "when sawyer is enabled, the convergence check in reaction.yaml becomes one of sawyer's health checks."

The existing convergence gate in reaction.yaml (`skip_if_convergence_above: 0.6`) fires BEFORE the reaction round executes — it is a pre-check that can skip the round entirely. The plan never specifies how the orchestrator should interpret `subsume_convergence_gate: true` during execution. Specifically:

**Problem A — Bootstrap:** On the very first run with sawyer enabled, no prior `discourse-health.json` exists. The plan specifies that discourse-health.sh runs AFTER synthesis (Task 3: "It runs AFTER synthesis, not before"). This means at reaction-round decision time, sawyer health state is undefined. If the orchestrator tries to apply sawyer's `healthy/degraded/unhealthy` logic to decide whether to skip the reaction round, it has no data. The plan gives no instruction for this case.

**Problem B — Semantic mismatch:** The existing gate is a binary skip (above threshold → skip entirely). Sawyer's health states are `healthy / degraded / unhealthy` — a three-way classification. The plan says sawyer "subsumes" the convergence check, but the convergence check uses a float threshold (0.6) while sawyer uses Gini + novelty + relevance thresholds. These are different metrics measuring different things. "Subsume" is a one-word claim with no implementation contract.

**Problem C — Who reads sawyer.yaml?** The plan says reaction.yaml references sawyer.yaml (Task 8). But the reaction round is orchestrated by the host agent reading `phases/react.md` (or equivalent), not by the synthesis agent. discourse-health.sh has not run yet at that point. Nothing in the plan shows the orchestrator loading sawyer.yaml to make a skip decision.

**Concrete failure:** The reaction round runs on a document with convergence 0.65 (above the existing 0.6 gate). With `subsume_convergence_gate: true`, the old gate should be suppressed. But because the orchestrator has no implementation for "sawyer takes over," the old gate still fires and the round is skipped. Sawyer health is never computed because discourse-health.sh never runs (synthesis never happens). The subsumption claim produces a silent no-op that appears to work.

**Minimum correct fix:** Either (a) explicitly define `subsume_convergence_gate: false` and leave the existing gate intact until a concrete sawyer-gate implementation exists, or (b) define a specific agent instruction in phases/react.md that reads sawyer.yaml and specifies behavior when no prior health data exists (e.g., "if no discourse-health.json, proceed as if healthy"). The current plan ships a config flag with no consuming implementation.

---

### CDP-04 — P2 — haiku cannot reliably perform evidence-set equality for legality scoring

**Location:** Task 5 (synthesize-review.md Step 3.7c), Task 1 (lorenzen.yaml `defense_requires_new_evidence: true`)

**The invariant broken:** Model capability contract (invariant 6).

Step 3.7c requires haiku to perform this check for defense moves:

> "Must have Evidence field with references not already cited by the original finding. If it only re-cites the original → `move_legality: invalid`"

This requires exact string comparison of file:line references across two separate documents: the reaction's Evidence field and the original finding's Evidence field from the initial review. haiku is the synthesis model specifically because "synthesis is structuring, not reasoning" (intersynth CLAUDE.md design decision). But move legality at the defense level requires:

1. Locating the original finding's evidence in the synthesis context (which may be deeply nested in findings.json or agent output prose).
2. Extracting and normalizing both evidence strings.
3. Performing a set-difference check.

haiku's known failure modes at set-membership reasoning — particularly when evidence strings have minor formatting variations (`src/auth.ts:47` vs `auth.ts:47` vs `src/auth.ts:47-50`) — will produce unreliable legality scores. A false `invalid` tags a legitimate defense; a false `valid` passes a hearsay defense.

The scoring table in lorenzen.yaml assigns `invalid_move: 0.2`. These scores appear in the findings.json `discourse_analysis.lorenzen` block and influence the Discourse Quality section of synthesis.md. Users will read these scores as meaningful signal. If haiku produces them unreliably, the scores are misleading rather than neutral.

**Note on severity:** This is P2, not P1, because legality scoring is clearly labeled as analytical metadata rather than gating synthesis verdict. No finding is suppressed or promoted based solely on legality score. The damage is misleading reports, not corrupted findings.

**Minimum correct fix:** Either (a) restrict the legality check to structural presence only (does the Evidence field exist and is it non-empty? — haiku can answer this reliably), or (b) have lorenzen.yaml specify `defense_requires_new_evidence: false` initially, enabling the check only when a higher-capability model handles synthesis. Document the limitation explicitly in the Lorenzen config comment.

---

### CDP-05 — P2 — Novelty rate metric diverges from stemma-corrected convergence

**Location:** Task 3 (discourse-health.sh), findings.json schema

**The invariant broken:** Synthesis input completeness (invariant 1), specifically the consistency of the `convergence` field.

The plan defines novelty rate in Task 3 as:

> "novelty = findings where convergence == 1 / total findings"

But the synthesis agent (rsj.10 stemma analysis, Step 6.3 of synthesize-review.md) writes TWO convergence values per finding:
- `"convergence": M` — the raw agent-count convergence
- `"convergence_corrected": N` — the stemma-corrected count (N <= M)

discourse-health.sh reads `convergence == 1` from findings.json. This is ambiguous: it is the raw count, not the corrected count. If 3 agents all independently report the same finding from the same source file, `convergence == 3` but `convergence_corrected == 1`. Under the corrected semantics, this finding is NOT novel (multiple agents saw it). Under the raw semantics, `convergence != 1` so it is also not novel. These agree in this case.

But consider: 1 agent reports a finding, `convergence == 1`, `convergence_corrected == 1`. discourse-health.sh counts this as "novel." Now stemma analysis finds that this finding shares >0.5 Jaccard overlap with another finding from a different section. The system has two findings that share evidence, but because they are in different sections, they are not merged. Each has `convergence == 1`. novelty_rate counts them both as novel. But they are not independent — they share the same source evidence. The novelty signal is inflated.

This is an accuracy issue in the health metric, not a data corruption issue. But because `flow_state` is computed from novelty_rate, and `flow_state: unhealthy` triggers warnings that could eventually gate review rounds, the inflation degrades health assessment reliability.

**Minimum correct fix:** In discourse-health.sh, use `convergence_corrected` if present, falling back to `convergence` when `convergence_corrected` is null (stemma analysis was skipped). Add to Task 3 description: "Use `convergence_corrected` for novelty calculation when available."

---

### CDP-06 — P2 — Two-writer findings.json lacks an atomic merge protocol

**Location:** Task 6 (synthesize-review.md schema extension), Task 4 (synthesize.md Step 3.9)

This is the structural formulation of the same issue raised in CDP-01, examined as a schema concern rather than a race condition.

The plan assigns findings.json population to two separate writers with no merge protocol:

| Writer | Key(s) written |
|--------|---------------|
| `intersynth:synthesize-review` | All existing keys including `discourse_analysis.lorenzen` (Task 5) |
| Orchestrator (post-discourse-health.sh) | `discourse_health` |

There is no defined merge operation. "Merges them when reading findings.json" in Task 6 is reader-side logic, not a write specification. If the orchestrator reads the synthesis-written findings.json, inserts `discourse_health`, and writes it back:

- It must not overwrite any key written by synthesize-review.
- It must produce valid JSON (e.g., handle the case where findings.json already has a partial `discourse_health` key because an old run left stale data).
- It must handle the case where synthesis failed and findings.json does not exist.

None of these cases are specified. The plan's verification step (item 5) only checks that the schema field exists in synthesize-review.md — it does not verify that the orchestrator write-back is implemented or tested.

**Minimum correct fix:** Designate a single canonical write in the plan. The simplest path: the orchestrator runs discourse-health.sh, reads the resulting discourse-health.json, passes it as an additional parameter to the synthesis subagent invocation (or writes it to a well-known location before invoking synthesis), and the synthesis agent incorporates it into findings.json in its single write. This eliminates the write-back entirely.

---

### CDP-07 — P3 — Move type naming inconsistency between lorenzen.yaml and reaction-prompt.md

**Location:** Task 1 (lorenzen.yaml `move_types`), Task 2 (reaction-prompt.md)

lorenzen.yaml defines move types with underscore naming: `new_assertion`, `valid_attack`, `valid_defense`.

reaction-prompt.md (Task 2) instructs agents to write:

```
- **Move Type**: attack | defense | new-assertion | concession
```

Note `new-assertion` (hyphen) vs `new_assertion` (underscore).

Additionally, the mapping in Task 2 says:
- `missed-this` → `new-assertion`

But `missed-this` is a Stance value, not a Move Type. Agents that write `missed-this` as their Stance must also write `new-assertion` as their Move Type — these are two separate fields. The synthesis agent in Step 3.7c pattern-matches on the Move Type field. If an agent writes `missed-this` in the Move Type field instead of `new-assertion` (a natural confusion given the mapping instruction), the `count per agent` for new_assertion_max_per_agent cap is never triggered and the cap is never enforced.

**Minimum correct fix:** Change lorenzen.yaml to use hyphens consistently with reaction-prompt.md (`new-assertion`, not `new_assertion`), or add an explicit normalization step in Step 3.7c: "Normalize move types: replace underscores with hyphens and convert to lowercase before matching against lorenzen.yaml move_types."

---

## Summary Assessment

The plan adds meaningful discourse-analytic metadata to the review pipeline. The core feature (Lorenzen move labeling, Sawyer health state) is conceptually sound. However, three issues require correction before implementation:

CDP-01 (P0) is the most dangerous: the plan describes the orchestrator mutating findings.json after the synthesis subagent has written it, with no atomic merge protocol. This produces undefined JSON if any consumer reads between writes, and the plan's verification section does not catch this because it only checks field presence in agent prompts, not runtime write ordering.

CDP-02 (P1) is a rollout correctness issue: the new `Move Type` field is added to the prompt but the synthesis agent has no nil-safe path for reactions produced under the old prompt. Any staged rollout produces corrupted legality scores for mixed-format runs.

CDP-03 (P1) is a spec-without-implementation issue: `subsume_convergence_gate: true` ships as a config comment with no consuming code path. The existing convergence gate continues to fire unchanged, making the sawyer config a no-op that appears functional.

CDP-04 through CDP-07 are quality concerns that do not corrupt persisted data or break the pipeline but degrade the accuracy of the discourse analytics.

---

**Verdict: NOT READY — resolve CDP-01, CDP-02, CDP-03 before implementation**
