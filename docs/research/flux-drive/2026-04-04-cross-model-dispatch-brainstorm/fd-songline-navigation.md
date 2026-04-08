# fd-songline-navigation Review: Cross-Model Dispatch Brainstorm

**Source:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`
**Reviewed:** 2026-04-04
**Agent:** fd-songline-navigation (Songline keeper — sequential knowledge-path encoding)
**Track:** D (Esoteric)
**Bead:** sylveste-9lp.9

---

## Findings Index

- P1 | SNG-01 | Design Space / Recommended Hybrid | Initiation ceiling: expansion score discards finding richness; some finding classes unreachable at haiku
- P1 | SNG-02 | Current Architecture / Step 2.2b | Single-custodian risk: no check that critical domain paths have ≥1 sonnet-tier agent
- P2 | SNG-03 | Current Architecture / Model Resolution Flow | Knowledge compression: tier assignment uses only score (severity), not the Stage 1 finding *type*
- P2 | SNG-04 | Scope / Out of Scope | Return journey absent: no re-dispatch path for agents whose findings reveal new expansion candidates
- P3 | SNG-05 | Design Space / Option A | Verse-position ignored: agents earlier in dispatch sequence get no sequential investment discount

---

## SNG-01 — Initiation Ceiling: Some Finding Classes Unreachable at Haiku Tier (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Design Space / Recommended: Option A + C Hybrid", step 2 (map score → model adjustment).

**Severity:** P1 — Required to exit quality gate. The downgrade logic has no model of which finding types require minimum capability, creating permanent blind spots for certain finding classes.

**The Songline parallel:**
In Aboriginal Australian songline tradition, certain verses are restricted to initiates who have undergone specific ceremony — not because the information is arbitrary, but because the earlier verses equip the listener with conceptual tools needed to understand the later verses. A non-initiate cannot simply read the restricted verse; the knowledge requires the prior accumulation. You cannot access the fourth verse's meaning with only the first verse's preparation.

Model tiers are analogous to initiation levels. Certain finding types — cross-component race conditions, transactional boundary violations, emergent failure modes in distributed systems, security implications of API surface design — require a level of reasoning that haiku-tier models cannot reliably produce. It is not that haiku *never* produces these findings; it is that haiku cannot reliably follow the reasoning chain that *validates* such findings. A haiku agent may output the correct conclusion while the supporting reasoning chain is incomplete or incorrect. Synthesis cannot distinguish.

**Concrete failure scenario:** `fd-architecture` is downgraded to haiku (expansion_score=1, budget_pressure=high). The document under review contains a subtle dependency inversion violation: service A calls service B's internal scheduler directly, bypassing B's public interface, because of a performance shortcut. At sonnet, `fd-architecture` would trace: (1) identify the direct call, (2) recognize it bypasses the interface contract, (3) model the failure mode (A now depends on B's internal schedule, coupling them on B's implementation changes), (4) assess severity (P1 — violates the service contract and creates hidden deployment ordering dependency). At haiku, the agent identifies step 1 (the direct call is visible) but cannot reliably complete steps 2-4. It either misses the finding or produces a finding with incorrect severity and reasoning. Both outcomes are worse than no finding — a missing finding prompts follow-up; a confidently wrong finding misleads synthesis.

**Evidence:** The brainstorm's Success Criteria: "No regression in P0/P1 finding recall (measured via intertrust)." This implies the expectation that P0/P1 findings can be produced at any tier with sufficient coverage. That assumption is false for finding classes requiring multi-step abstract reasoning chains. Intertrust precision scores could confirm this, but the brainstorm does not query them.

**Smallest fix:** Define `minimum_capability_tier` per agent in `agent-roles.yaml` — the minimum tier at which the agent can be expected to produce trustworthy P1+ findings. Do not confuse this with `min_model` (current minimum, based on role); this is a finding-quality threshold:

```yaml
- name: fd-architecture
  model_tier: opus
  min_model: sonnet            # existing: don't run below sonnet in normal mode
  finding_floor_tier: sonnet   # NEW: below sonnet, P1+ findings are unreliable
```

`routing_adjust_expansion_tier` checks `finding_floor_tier`: if adjusted tier falls below it, mark the agent's findings as `capability-limited: true` in synthesis input. Synthesis treats capability-limited findings as P2-max unless corroborated by a non-limited agent.

---

## SNG-02 — Single-Custodian Risk: No Redundancy Check for Critical Domain Paths (P1)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Current Architecture / Step 2.2b", "Constraints / #4".

**Severity:** P1 — Required to exit quality gate. A domain coverage gap that persists undetected until synthesis discovers it — at which point remediation requires re-dispatch.

**The Songline parallel:**
In songline tradition, knowledge of the complete path is distributed across multiple custodians. No single elder holds all verses — the distribution is not incidental but structural. A path whose only custodian dies takes that knowledge with them. Critical segments have redundant custodians precisely because the cost of losing that segment is unacceptable.

In the expansion pool, each agent is the sole custodian of its domain. `fd-resilience` is the only agent who reviews resilience patterns. `fd-performance` is the only agent who reviews performance characteristics. If `fd-resilience` is downgraded to haiku *and* the artifact under review has critical distributed-systems resilience patterns, the pool has a single-custodian situation with a capability-insufficient custodian. There is no redundancy.

**Concrete failure scenario:** The review targets a new service mesh configuration. `fd-resilience` is the expansion pool's only coverage for service mesh resilience patterns. It is downgraded to haiku (score=1). At haiku, it flags missing timeout configurations (visible) but misses the retry budget interaction pattern (requires understanding that two separate retry chains can create retry amplification under partial failure). `fd-architecture` at sonnet is also in the pool but is not scoped to resilience patterns — it will note the missing timeouts only if they cross architectural concerns. The service mesh ships with the retry amplification bug. Synthesis received one finding (missing timeouts) and one non-finding on retry amplification.

**Evidence:** Constraint #4: "Budget enforcement remains a separate gate. Cross-model dispatch adjusts tiers *within* the budget envelope." The expansion pool makeup (which agents are in it) is determined by AgentDropout (Step 2.2a.5) and expansion scoring (Step 2.2b). Neither step checks whether a downgraded agent's domain has an alternative reviewer. The pool may have partial domain coverage without knowing it.

**Smallest fix:** After applying per-agent tier adjustments, run a coverage gap check before dispatch. For each agent with `capability-limited: true` (or adjusted to haiku), check whether any other agent in the pool covers the same domain at sonnet+ tier:

```bash
# expansion.md, before Stage 2 dispatch
for agent in "$capability_limited_agents"; do
  domain=$(get_agent_domain "$agent")
  redundant=$(find_pool_agent_for_domain "$pool" "$domain" --min-tier sonnet)
  if [[ -z "$redundant" ]]; then
    log_warning "SINGLE_CUSTODIAN: $agent (haiku) is sole reviewer for domain: $domain"
    # Option: upgrade agent to sonnet, or note in synthesis
    if [[ "$can_afford_upgrade" == "true" ]]; then
      upgrade_agent "$agent" sonnet
    fi
  fi
done
```

This is a single post-adjustment loop, not a redesign.

---

## SNG-03 — Knowledge Compression: Tier Assignment Uses Score (Severity) Not Finding Type (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Current Architecture / What We Have to Work With", "Design Space / Option B".

**Severity:** P2 — Systematic information loss in the expansion scoring → tier mapping path.

**The Songline parallel:**
In songlines, different types of geographic knowledge (water sources, dangerous terrain, ceremonial sites, navigable passes) have different transmission requirements. Knowledge of water sources is critical for survival and requires precise, high-fidelity transmission. Knowledge of decorative landmarks can be approximated. The investment in transmission (ceremonial preparation, repetition, ritual context) varies by *knowledge type*, not just by *knowledge importance rank*.

The brainstorm collapses the Stage 1 findings into a single `expansion_score (0–3)`. A P0 finding that triggered expansion because of a missing security boundary and a P0 finding that triggered expansion because of a missing null check both produce `expansion_score=3` but have radically different implications for the Stage 2 agent's tier requirement. The security boundary finding requires cross-system reasoning; the null check finding is syntax-level.

**Evidence:** Option B ("Finding-Driven Tier Selection") in the brainstorm explicitly identifies this:

> "Map the specific Stage 1 finding that triggered expansion to a model tier."
> "Cons: Finding severity already feeds expansion_score, so this may be redundant with Option A."

This "may be redundant" dismissal is the error. Finding severity and finding type are independent dimensions. A P0 null check and a P0 distributed locking failure have the same severity but radically different type-required reasoning depth.

The Recommended Hybrid excludes Option B entirely: "Use expansion score as the primary tier signal." The richness of Stage 1 findings is compressed to a single integer.

**Smallest fix:** Include `trigger_finding_type` (the type field of the finding that most recently raised the expansion score) as an input to tier adjustment. This does not require building Option B fully — it is one additional field in the expansion candidate metadata:

```bash
# In expansion.md Step 2.2b, when scoring candidates
expansion_candidates+=("agent=$agent score=$score trigger_type=$finding_type")

# In routing_adjust_expansion_tier (extend signature)
routing_adjust_expansion_tier() {
  local agent="$1" model="$2" score="${3:-2}" pressure="${4:-low}" trigger_type="${5:-}"

  # Type-based tier floor (NEW)
  if [[ "$trigger_type" =~ ^(security|architectural|transactional) ]]; then
    # Complex-type finding: preserve one tier higher than score would suggest
    [[ "$score" == "1" ]] && score=2  # treat weak evidence for complex types as moderate
  fi
  # ...rest of existing logic
}
```

---

## SNG-04 — Return Journey Absent: No Re-Dispatch Path for Revelation-Triggered Expansions (P2)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Scope / Out of Scope".

**Severity:** P2 — Structural asymmetry; the staged dispatch model has no return path.

**The Songline parallel:**
A songline encodes both the outward journey (from home country to sacred site) and the return journey (from sacred site back home). The return journey is not simply the outward path reversed — it reveals different features of the landscape, uses different navigational cues, and accumulates different knowledge. A knowledge keeper who has traveled only one direction has an incomplete understanding of the path.

The brainstorm's dispatch is outward-only: Stage 1 → expansion scoring → Stage 2 → synthesis. Stage 2 agents may produce findings that, in a bidirectional model, would generate new expansion candidates. An `fd-architecture` Stage 2 finding that discovers a previously unknown service dependency would — in a return-journey model — trigger a new `fd-resilience` expansion for that dependency. The current architecture has no such path.

**Evidence:** Out of Scope: "Dynamic model switching mid-review (agent restart)." This rules out mid-flight expansion. But the out-of-scope constraint also forecloses the question of whether Stage 2 findings can trigger Stage 2 re-expansion. The brainstorm does not say this is architecturally impossible — it says it is out of scope for this feature. The concern is that this is classified as "out of scope" without analysis of whether it creates a systematic blind spot.

**Smallest fix:** Add to Open Questions: "Should Stage 2 findings that discover new expansion signals be eligible for a Stage 2b (secondary expansion) with a max depth of 1 additional round?" This is a design question, not an implementation task. The current brainstorm does not ask it. Raising it in scope acknowledges the return-journey gap without committing to implementing it.

---

## SNG-05 — Verse-Position Ignored: Sequential Position in Dispatch Not Used for Tier Calibration (P3)

**Location:** `docs/brainstorms/2026-04-04-cross-model-dispatch-brainstorm.md`, "Current Architecture / Model Resolution Flow".

**Severity:** P3 — Improvement for future iteration.

**The Songline parallel:**
In songlines, earlier verses in the sequence are shorter, simpler, and more broadly distributed — they are the navigational foundation that every traveler learns. Later verses are longer, more detailed, and restricted to higher-initiation custodians. The investment in transmission *increases* as you progress deeper into the path. An early orientation verse requires minimal ceremony; the verse describing the sacred site itself requires maximum ceremony.

The brainstorm's expansion pool treats all Stage 2 agents as equivalent in terms of their *position* in the dispatch sequence. But Stage 2 agents launched via speculative dispatch (2.2a.6) are earlier in the sequence (launched before Stage 1 complete) while Stage 2 agents in the main expansion (2.2c) are later. Later-stage agents have access to more accumulated knowledge and are therefore making higher-context investments.

**Evidence:** There is no `sequence_position` or `launch_phase` variable in the expansion candidate metadata. The spec does distinguish speculative (2.2a.6) from standard expansion (2.2c), but only in Constraint #5 ("same logic applies").

**Smallest fix:** Annotate expansion candidates with `launch_phase: speculative | standard`. For synthesis, use `launch_phase` to apply a confidence weighting: speculative findings carry lower base confidence (launched on partial evidence) than standard findings. This is a synthesis-level annotation, not a tier-adjustment change.

---

## Summary

| ID | Severity | Domain | Status |
|----|----------|--------|--------|
| SNG-01 | P1 | Finding-class capability ceiling | BLOCKING — no model of unreachable finding types at haiku |
| SNG-02 | P1 | Single-custodian domain coverage | BLOCKING — no redundancy check for capability-limited agents |
| SNG-03 | P2 | Finding type discarded in score compression | Important — trigger_type not passed to tier function |
| SNG-04 | P2 | No return journey / re-expansion path | Important — secondary expansion not in scope or open questions |
| SNG-05 | P3 | Sequential position not used for confidence | Improvement — launch_phase annotation for synthesis weighting |

**Verdict: needs-changes** — two P1 structural gaps: finding classes that cannot be reliably produced at haiku are not identified, and no redundancy check exists for domains where the only expansion agent has been downgraded.
