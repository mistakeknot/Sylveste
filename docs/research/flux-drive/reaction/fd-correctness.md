---
reviewed: 2026-04-02
reviewer: fd-correctness (Julik)
subject: interverse/interflux/skills/flux-drive/phases/reaction.md
---

# Phase 2.5 Reaction Round — Correctness Review

## Invariants

These must hold for Phase 2.5 to be correct. If any breaks, the review pipeline produces corrupted, duplicated, or silently dropped signal.

1. **Convergence gate determinism.** Given the same output directory contents, `findings-helper.sh convergence` must produce the same result every time. The gate decision (skip / proceed) must not depend on wall-clock order of reads.
2. **Peer-priming discount idempotency.** Discounting the same peer-primed finding twice must not lower `overlap_ratio` below zero or count it as negative.
3. **Scaled threshold monotonicity.** `effective_threshold` must be monotonically non-decreasing as `agent_count` increases, and must never exceed `config.skip_if_convergence_above`.
4. **Agent isolation.** Each parallel reaction subagent reads only its own input files plus the shared peer-findings block. No agent writes to another agent's output path.
5. **Fixative sequencing.** The fixative context block must be fully computed before any reaction prompt is dispatched. Partial fixative injection (some agents receive it, others do not) degrades the protocol.
6. **Event emission completeness.** The `interspect-reaction` event must fire on both the skip path and the dispatch path, with no fields omitted.
7. **Empty-findings safety.** When `total_findings == 0`, `overlap_ratio` must be 0.0, not NaN or undefined. The gate must not divide by zero.
8. **N=1 agent safety.** With a single agent, there are no peers to react to. The round must either skip cleanly or dispatch zero agents, not hang.
9. **Title normalization stability.** Two findings that differ only in punctuation, capitalisation, or ID prefix must normalise to the same key, never to two distinct keys.
10. **Hearsay weight correctness.** A finding counted as hearsay (weight 0.0) must not contribute to `overlapping_findings` in the convergence denominator; an independent confirmation (weight 1.0) must.

---

## Findings Index

- P0 | RXN-01 | "Step 2.5.0 / convergence formula" | N=0 agent_count produces divide-by-zero in effective_threshold scaling
- P0 | RXN-02 | "Step 2.5.0 / peer-priming discount" | Peer-priming discount is applied to overlap_ratio after the ratio is computed, not before — spec is ambiguous enough to admit double-discounting
- P1 | RXN-03 | "Step 2.5.0 / convergence gate" | N=1 sends zero agents to react but still emits `agents_dispatched: 0` without a clear spec for the skip vs proceed branch
- P1 | RXN-04 | "findings-helper.sh convergence / title normalisation" | awk regex strips all non-alphanumeric chars including hyphens in IDs, causing unrelated findings to collide on normalised titles
- P1 | RXN-05 | "Step 2.5.2b / fixative sequencing" | Spec says 2.5.2b MUST complete before 2.5.3, but provides no enforcement mechanism for an LLM orchestrator; race is latent
- P1 | RXN-06 | "Step 2.5.3-4 / parallel dispatch timeout" | 60-second timeout on subagents is agent-wall-clock, not pipeline-wall-clock; no outer bound is defined, so all agents timing out serially takes 60×N seconds
- P2 | RXN-07 | "Step 2.5.0 / peer-priming timestamp comparison" | peer-findings.jsonl timestamp comparison relies on LLM to parse and compare ISO-8601 strings from two separate files with no defined format contract
- P2 | RXN-08 | "Step 2.5.0 / scaled threshold cap semantics" | Cap behaviour is defined only for N≥5; for N between 5 and ∞ the formula outputs values below cap, but the prose says cap fires at N=8 which is incorrect
- P2 | RXN-09 | "Step 2.5.5 / event field convergence_before" | convergence_before is recorded after peer-priming discount is applied; field name implies pre-discount value
- P2 | RXN-10 | "Step 2.5.2a / isolation fallback SCT-02" | Isolation fallback fires when zero peers are visible, but the fallback uses summary from ALL peers — this partially defeats topology isolation for genuinely isolated roles
- P3 | RXN-11 | "Step 2.5.3-4 / agents skipped on empty peer findings" | Agents with empty peer findings are silently skipped with no accounting in the reaction round report

Verdict: needs-changes

---

## Summary

Phase 2.5 is structurally coherent and the convergence gate formula works correctly for the common 2-to-8 agent range. However there are two P0/P1 issues involving undefined behaviour at degenerate inputs (N=0), an ambiguously specified peer-priming discount that can be applied at the wrong stage, and a title-normalisation regex in `findings-helper.sh` that will silently merge unrelated findings under adversarial or long-title conditions. The fixative sequencing constraint is stated but not enforced, and the parallel timeout model has no outer bound. None of these require a redesign; each has a small targeted fix. The hearsay detection and Lorenzen move validation config layers are well-specified and do not introduce correctness hazards at this phase.

---

## Issues Found

### 1. P0 — RXN-01 — N=0 agent_count produces effective_threshold divide-like fault and formula undefined

**Location:** `reaction.md` Step 2.5.0, `findings-helper.sh` lines 95-98 (the zero-raw output branch)

**Invariant broken:** Empty-findings safety (invariant 7), convergence gate determinism (invariant 1).

`findings-helper.sh convergence` emits `0.0\t0\t0\t0` when `$raw` is empty (line 96). The spec then instructs the orchestrating agent to compute:

```
effective_threshold = config.skip_if_convergence_above * (agent_count / 5)
```

With `agent_count = 0`, this yields `0.6 * (0 / 5) = 0.0`. The cap then clamps this to `min(0.0, 0.6) = 0.0`. The gate condition `overlap_ratio > effective_threshold` becomes `0.0 > 0.0`, which is **false** — so the reaction round proceeds with zero agents to dispatch. This is arguably the correct behaviour (skip a round with no data), but the mechanism is fragile: it depends on the `>` being strict, not `>=`. If an implementer uses `>=` (equally plausible from the prose "above the threshold"), N=0 falls through to dispatch with zero agents and still produces the event.

More importantly, the spec never acknowledges N=0 as a possible input. An output directory with no valid `.md` files (all outputs errored or the directory was freshly created) silently reaches `agent_count = 0`, `total_findings = 0`, and the effective_threshold = 0.0. If the Phase 2 dispatch itself failed completely, Phase 2.5 should short-circuit with an explicit error, not silently "fire" with a zero-agent population.

**Concrete failure interleaving:**
1. Phase 2 dispatches 5 agents. All 5 time out and write `.error.md` files.
2. `findings-helper.sh read-indexes` skips `*.reactions.error` patterns — but the primary agent outputs also failed. The directory contains only error files.
3. `raw` is empty. Script emits `0.0 0 0 0`.
4. `agent_count = 0`. `effective_threshold = 0.0`. `overlap_ratio (0.0) > 0.0` is false.
5. Spec says "continue to Step 2.5.1." The round proceeds, dispatches zero reaction agents, and emits a `reaction-dispatched` event with `agents_dispatched: 0` — indistinguishable from a successful round with full convergence.
6. Synthesis receives an empty reaction directory and no signal that the entire Phase 2 failed. The review completes with corrupted signal.

**Minimum correct fix:** Add an explicit guard at the top of Step 2.5.0: "If `agent_count == 0`, skip the reaction round and emit the skip event with `{"type":"error","reason":"no_phase2_agents"}`. Do not proceed to Step 2.5.1." In `findings-helper.sh`, the existing `0 0 0 0` output is correct; the consuming logic must treat `agent_count == 0` as an error case distinct from convergence skip.

---

### 2. P0 — RXN-02 — Peer-priming discount is applied after overlap_ratio is computed, creating double-discount risk

**Location:** `reaction.md` Step 2.5.0, paragraph beginning "Peer-priming discount"

**Invariant broken:** Peer-priming discount idempotency (invariant 2), convergence gate determinism (invariant 1).

The spec reads:

> "For each finding title in the overlap set, check if the first report timestamp in peer-findings.jsonl precedes a second agent's Findings Index entry. Discount peer-primed findings from the overlap count before computing `overlap_ratio`."

The phrase "before computing `overlap_ratio`" implies the discount adjusts `overlapping_findings` before the ratio is calculated. But `findings-helper.sh convergence` already computes and outputs a ratio. The spec then says to run the script first (`Run scripts/findings-helper.sh convergence {OUTPUT_DIR}`), then parse its output, then apply the discount. There is no mechanism to pass the discounted count back into the script.

This creates two possible interpretations:

- **Interpretation A:** Run the script, get `(ratio, total, overlapping, agents)`, then compute `discounted_overlapping = overlapping - peer_primed_count`, then compute `adjusted_ratio = discounted_overlapping / total_findings`, then apply gate. This is the intent but is not what the spec text prescribes (it says run the script, then discount "from the overlap count before computing overlap_ratio" — but the ratio is already computed).
- **Interpretation B:** Run the script to get the ratio, then discount the ratio by some fraction. This is arithmetically different from A and harder to reason about.

The ambiguity means an LLM orchestrator following the spec literally will re-compute ratio by modifying the already-computed `overlapping_findings` value, which is correct only if it re-divides by `total_findings`. If instead it subtracts the discount fraction from `overlap_ratio` directly (equally natural), the result is wrong.

**Worse:** if `peer-findings.jsonl` exists but is empty (no peer data), the discount block still executes. If a bug causes all findings to be classified as peer-primed and the count goes negative (no underflow protection), `adjusted_ratio` could be negative, which is always below threshold — the round always proceeds regardless of true convergence.

**Minimum correct fix:** Rewrite the spec paragraph to read: "Compute `discounted_overlapping = overlapping_findings - (count of peer-primed findings in overlap set)`, clamped to `[0, overlapping_findings]`. Then compute `overlap_ratio = discounted_overlapping / max(1, total_findings)`." Make explicit that the script's output ratio is replaced, not adjusted.

---

### 3. P1 — RXN-03 — N=1 agent produces zero-peer situation with under-specified branch

**Location:** `reaction.md` Step 2.5.3-4

**Invariant broken:** N=1 agent safety (invariant 8).

With `agent_count = 1`, the script outputs something like `0.0\t3\t0\t1` (3 findings, 0 overlapping, 1 agent). The effective threshold with N=1 is `0.6 * (1/5) = 0.12`. The overlap ratio 0.0 is not above 0.12, so the round proceeds to Step 2.5.1.

In Step 2.5.2a (topology), agent A has no peers — the peer_findings block for A is empty regardless of topology mode, because there is only one agent. Step 2.5.3 then says: "Skip agents with empty peer findings." So agent A is skipped.

The round dispatches zero agents. But the spec reached this by a different path than the convergence gate skip — this is a "proceed but dispatch nobody" outcome, not a skip outcome. The report at Step 2.5.5 will read "0 dispatched" with no indication that N=1 was the cause. The `interspect-reaction` event for the dispatch case (not the skip case) fires with `agents_dispatched: 0`.

This is distinguishable from the N=0 failure in issue RXN-01 only by `agent_count` in the event payload. There is no explicit guard or messaging for the N=1 case. A review operator reading the event log sees `agents_dispatched: 0` with no obvious error, but no reaction signal was collected.

**Minimum correct fix:** Add a guard after the convergence gate: "If `agent_count < 2`, skip reaction round with `{"type":"skip","reason":"insufficient_agents","agent_count":N}`. Reaction round requires at least 2 agents to have meaningful peer comparisons." This makes the N=1 case explicit rather than silently collapsing to zero dispatches.

---

### 4. P1 — RXN-04 — awk title normalisation strips hyphens, causing finding ID collisions

**Location:** `findings-helper.sh` line 119

**Invariant broken:** Title normalisation stability (invariant 9).

The normalisation regex at line 119 is:

```awk
gsub(/[^a-zA-Z0-9 ]/, "", title)
```

This strips all non-alphanumeric characters including **hyphens from finding titles**. Consider two findings:

- `ARCH-01 | "Section" | Race condition in read-write path`
- `ARCH-02 | "Section" | Race condition in readwrite path`

After normalisation:
- First: `gsub` strips the hyphen in "read-write" → `race condition in readwrite path`
- Second: already `race condition in readwrite path`

Both normalise to the same key. They are counted as one overlapping finding across two agents even if they describe entirely different code locations. The overlap ratio is inflated, and the convergence gate can fire prematurely.

This is not a theoretical concern. Finding titles in practice often contain hyphenated terms: "off-by-one", "use-after-free", "double-free", "read-write lock", "N-dimensional", "null-safety". Any two findings whose titles differ only in a hyphen will merge under this normalisation.

**Concrete failure:** Agent A reports "Off-by-one in loop bound" and Agent B reports "Off by one in loop bound" (space instead of hyphen). Both normalise to `off by one in loop bound`. The finding registers as overlapping across A and B. If this is the only overlapping finding out of 3 total, `overlap_ratio = 0.33`. The gate may or may not fire depending on N. The overlap count is wrong.

**Minimum correct fix:** Replace the character-stripping regex with one that normalises whitespace and removes only punctuation that is not a word-internal separator. At minimum, change line 119 to:

```awk
gsub(/[^a-zA-Z0-9 \-]/, "", title)
gsub(/-/, " ", title)
```

This collapses hyphenated and unhyphenated variants consistently. Alternatively, use Jaccard similarity on word-bag rather than exact-string equality — but that requires more awk complexity. The hyphen-to-space normalisation is the smallest fix that removes the collision.

---

### 5. P1 — RXN-05 — Fixative sequencing constraint has no enforcement mechanism

**Location:** `reaction.md` Step 2.5.2b, sequencing constraint paragraph

**Invariant broken:** Fixative sequencing (invariant 5).

The spec states: "Step 2.5.2b MUST complete before Step 2.5.3 begins — do not parallelize." This is a correct constraint: fixative Gini computation needs all agents' findings, and the fixative context must be injected into every reaction prompt.

However, the sequencing constraint is stated as a prose instruction to the LLM orchestrator. The reaction round dispatches agents as parallel Agent calls (Step 2.5.3). If the orchestrating LLM begins building reaction prompts (Step 2.5.3) while still executing Step 2.5.2b — which is entirely plausible if it interprets "compute fixative" and "build prompts" as logically independent since the fixative is just a string it will concatenate later — some reaction prompts will be constructed and dispatched before `fixative_context` is resolved.

The failure is silent: agents dispatched before fixative completion receive `{fixative_context}` as a literal template placeholder, or receive an empty string if the orchestrator substitutes eagerly. Neither corrupts the file system, but some agents react without the fixative injection, defeating the anti-echo-chamber mechanism on the runs where it matters most (high Gini or low novelty).

**Minimum correct fix:** Restructure the step ordering to make the dependency explicit: rename Step 2.5.2b to "Step 2.5.2b: Compute fixative context string `FC`" and add to Step 2.5.3: "Use `FC` from Step 2.5.2b in each prompt. If `FC` is empty (fixative disabled or no triggers fired), substitute empty string." This makes the dependency visible as a data dependency, which LLM orchestrators are more reliable at respecting than an abstract "do not parallelize" constraint.

---

### 6. P1 — RXN-06 — No outer timeout bound for parallel agent dispatch

**Location:** `reaction.md` Step 2.5.3-4

**Invariant broken:** Concurrency liveness — no guarantee the round terminates in bounded time.

The spec says: "Timeout: `timeout_seconds` from config (default: 60s)." This is a per-agent timeout. With N parallel agents, the maximum elapsed time is 60 seconds because they run in parallel. However, the spec says `run_in_background: true` and then collects results in Step 2.5.5, which implies a barrier after all agents complete.

The problem is that `run_in_background: true` in the Claude Code agent model does not guarantee N agents run truly concurrently. If the runtime queues agents sequentially, timeout_seconds=60 for N=12 agents yields a wall-clock wait of up to 720 seconds (12 minutes), with no progress signalling to the operator and no outer circuit-breaker.

Even in a truly parallel model, there is no spec for what happens if some agents stall beyond their timeout. The per-agent timeout is presumably enforced by the subagent launcher, but the spec does not define what happens to the outer barrier if the timeout enforcement itself fails (the subagent hangs rather than returning an error). An outer timeout of `N * timeout_seconds` with a hard kill would bound worst-case latency.

**Minimum correct fix:** Add to Step 2.5.5: "If the total elapsed time for all dispatched agents exceeds `2 * timeout_seconds`, treat remaining in-flight agents as timed out and proceed to report. Do not block indefinitely waiting for a hung subagent." This does not change the per-agent timeout but adds an outer circuit-breaker.

---

### 7. P2 — RXN-07 — Peer-priming timestamp comparison has no defined format contract

**Location:** `reaction.md` Step 2.5.0, peer-priming discount paragraph

**Invariant broken:** Convergence gate determinism (invariant 1).

The peer-priming discount requires comparing timestamps: "check if the first report timestamp in peer-findings.jsonl precedes a second agent's Findings Index entry." The Findings Index format (`- SEVERITY | ID | "Section" | Title`) contains no timestamp field. The `findings-helper.sh write` command does record a timestamp in the JSONL format (`{..., "timestamp": "...Z"}`), but that is for the intermediate `findings.json` JSONL file, not for the Markdown Findings Index.

The spec thus requires a comparison between:
- A timestamp from `peer-findings.jsonl` (format: depends on who writes it — undefined in reaction.md)
- A "Findings Index entry" timestamp (not present in the index format)

There is no defined relationship between `peer-findings.jsonl` and the Findings Index blocks extracted by `read-indexes`. The peer-findings.jsonl format is referenced only by name; no schema is given. An orchestrating agent implementing this logic will either invent a format or silently skip the discount because it cannot find matching timestamps.

**Minimum correct fix:** Either (a) define the `peer-findings.jsonl` schema in the spec (at minimum: `{"title": "...", "agent": "...", "timestamp": "..."}`), and specify that the Findings Index block in each agent output must include a timestamp comment, or (b) remove the timestamp comparison entirely and substitute a simpler rule: "A finding is peer-primed if it appears in peer-findings.jsonl AND the agent's own Findings Index. Apply discount without timestamp check." The timestamp check is over-specified relative to the available data.

---

### 8. P2 — RXN-08 — Scaled threshold cap formula prose is incorrect for N between 5 and 8

**Location:** `reaction.md` Step 2.5.0

The spec states: "For N=2: threshold ~0.24. For N=5: threshold stays at 0.6. For N=8: threshold caps at 0.6."

Tracing the formula `effective_threshold = min(0.6 * (N / 5), 0.6)`:
- N=2: `0.6 * 0.4 = 0.24` — correct
- N=5: `0.6 * 1.0 = 0.6`, capped at 0.6 — correct
- N=8: `0.6 * 1.6 = 0.96`, capped at 0.6 — correct but the statement "for N=8: threshold caps at 0.6" implies the cap only starts at N=8, which is wrong. The cap fires for any N≥5. The prose misleads an implementer into thinking N=6 and N=7 have uncapped (sub-0.6) thresholds when in fact they all cap at 0.6.

This is a documentation error rather than an implementation error, but it will cause an implementer to write `if N >= 8: cap` instead of `if N >= 5: cap`, resulting in effective thresholds of 0.72 (N=6) and 0.84 (N=7) before capping — inflated thresholds that suppress the reaction round more aggressively than intended for 6- and 7-agent reviews.

**Minimum correct fix:** Change the prose to read: "Cap at `config.skip_if_convergence_above` for all N≥5. For N=6: 0.72→0.6 (capped). For N=7: 0.84→0.6 (capped). For N=8: 0.96→0.6 (capped)." This makes the cap boundary exact.

---

### 9. P2 — RXN-09 — convergence_before event field records post-discount value, not pre-discount

**Location:** `reaction.md` Step 2.5.5

**Invariant broken:** Event emission completeness (invariant 6).

The `reaction-dispatched` interspect event records `convergence_before` described as "overlap_ratio from Step 2.5.0." If the peer-priming discount was applied in Step 2.5.0, the stored value is the discounted ratio, not the raw ratio from `findings-helper.sh`. A downstream consumer (e.g., interstat trend analysis) that reads `convergence_before` expecting the raw structural overlap will see the peer-priming-adjusted number and underestimate natural convergence trends over time.

This is a labelling issue, not a data corruption issue. But because the field name says "before" (implying before the reaction round altered anything), the natural expectation is the pre-discount value.

**Minimum correct fix:** Record both in the event: `convergence_raw` (script output) and `convergence_discounted` (after peer-priming adjustment). Keep `convergence_before` as an alias for `convergence_discounted` for backward compatibility, but document both fields.

---

### 10. P2 — RXN-10 — SCT-02 isolation fallback partially defeats topology isolation

**Location:** `reaction.md` Step 2.5.2a, `discourse-topology.yaml` fallback_on_isolation

**Invariant broken:** Agent isolation intent (invariant 4 — soft violation).

The isolation fallback rule is: "zero visible peers → use `fallback_on_isolation` level from all peers." `fallback_on_isolation` is set to `summary` in `discourse-topology.yaml`.

Consider a scenario where only `checker`-role agents are dispatched (e.g., a quality-gates-only run with fd-perception and fd-resilience). Per the adjacency map, `checker` is adjacent to `editor` and `planner`, but if neither editor nor planner agents are in this run, each checker agent sees zero visible peers via topology. The fallback fires and each checker receives summary visibility from all other checkers.

The intent of topology isolation is to prevent fast convergence toward a single viewpoint. But the fallback restores full peer visibility for any run where only same-tier agents are dispatched. This creates an incentive structure where a malicious or misconfigured run with a homogeneous agent set silently bypasses topology isolation.

This is not a data integrity issue; it is a protocol correctness issue. The fallback is the right safeguard against the degenerate case of truly isolated agents (SCT-02), but it should document that homogeneous-role runs are expected to always trigger the fallback.

**Minimum correct fix:** Add a note to Step 2.5.2a: "When the fallback fires due to homogeneous-role dispatch (all dispatched agents share the same role), log this condition — it indicates topology isolation is not operative for this run. The fixative may be particularly important in this case."

---

### 11. P3 — RXN-11 — Silently skipped agents not counted in report

**Location:** `reaction.md` Step 2.5.5 report line

**Invariant broken:** Event emission completeness (invariant 6 — minor).

Step 2.5.3 says: "Skip agents with empty peer findings." These skipped agents are not dispatched. The Step 2.5.5 report format only counts dispatched, produced, empty, and error agents. There is no bucket for "skipped due to empty peer findings." An operator cannot distinguish "3 dispatched, 0 errors" from "3 dispatched (5 skipped), 0 errors."

**Minimum correct fix:** Add `{S} skipped (empty peers)` to the Step 2.5.5 report string and include `reactions_skipped_empty_peers` in the `reaction-dispatched` event payload.

---

## Improvements

### 1. Define peer-findings.jsonl schema formally

The file is referenced in Step 2.5.0 but has no formal schema anywhere in the reviewed files. Defining it — even as a three-field JSONL (`title`, `agent`, `timestamp`) — would make the peer-priming discount implementable rather than speculative.

**Rationale:** Without a schema, two implementers of the discount logic will produce different results. One will use finding IDs, another will use normalised titles. These produce different discount counts, breaking convergence gate determinism.

---

### 2. Extract convergence computation into a structured output, not tab-separated text

`findings-helper.sh convergence` emits tab-separated text that the orchestrating agent must parse. This is error-prone: field order is load-bearing, a `printf` format change silently breaks all consumers. A JSON output (`{"overlap_ratio":0.24,"total_findings":5,"overlapping_findings":1,"agent_count":2}`) would be self-documenting and resilient to field additions.

**Rationale:** The spec already requires the orchestrator to parse the output and branch on multiple fields. JSON eliminates the parsing fragility without increasing script complexity (`jq -n ...`).

---

### 3. Add a dry-run / gate-only mode to findings-helper.sh

The convergence gate is the most consequential decision in Phase 2.5. A dry-run option (`findings-helper.sh convergence --gate`) that also prints the effective threshold and decision (skip/proceed) for a given config would make the gate observable and testable without running the full reaction round.

**Rationale:** Currently there is no way to validate gate behaviour against a known output directory without wiring up the full Phase 2.5 orchestration. A dry-run supports regression testing and debugging of edge cases (N=1, all-overlapping, no-findings).

---

### 4. Make the hearsay weight of 0.5 for reactive additions explicit in the spec

`reaction.yaml` defines `convergence_weight_reactive: 0.5` for reactive additions. The reaction-prompt.md tells agents to emit reactive additions in the "Reactive Additions Index." However, Phase 2.5 spec never explains how reactive additions flow into the next convergence computation or into synthesis. They are produced during Phase 2.5 but consumed in Phase 3. The spec should state where reactive additions land (are they added to findings.json? do they affect Phase 3 synthesis convergence?) and confirm their weight.

**Rationale:** If reactive additions are silently ignored in synthesis, the `convergence_weight_reactive` config value is a dead letter. If they do feed synthesis, the spec needs to say so to prevent implementation drift.

---

### 5. Clarify whether max_reactions_per_agent is enforced by the reaction prompt or by the orchestrator

`reaction.yaml` sets `max_reactions_per_agent: 3`. The reaction-prompt.md says "React to at most 3 peer findings." This aligns, but the enforcement is purely in the prompt (relying on LLM compliance). If an agent produces 5 reactions, the spec gives no instruction on whether to truncate to 3, accept all 5, or mark the output as malformed.

**Rationale:** An explicit truncation rule ("if more than 3 reactions appear, use the first 3") makes synthesis behaviour deterministic regardless of agent compliance.

---

--- VERDICT ---
STATUS: fail
FILES: 0 changed
FINDINGS: 11 (P0: 2, P1: 4, P2: 4, P3: 1)
SUMMARY: Two P0 issues require correction before deployment: N=0 agent_count produces a silent false-proceed through the convergence gate, and the peer-priming discount is specified ambiguously enough that an LLM orchestrator will apply it at the wrong stage. Four P1 issues (title normalisation collision, fixative sequencing race, N=1 under-specification, unbounded parallel timeout) are blocking for production reliability. The spec is not safe to implement as written.
---
