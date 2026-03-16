# SHIELDA Root Cause Tracing Assessment

**Assessed:** 2026-03-16
**Source:** arxiv.org/abs/2508.07935 (Zhou, Chen, Lu, Zhao, Zhu — Aug 2025)
**Venue:** ICLR 2026
**Category:** cs.SE — exception handling for LLM-driven agentic workflows
**Referenced from:** docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md (D13)

---

## What It Is

SHIELDA (Structured Handling of Exceptions in LLM-Driven Agentic Workflows) is a modular runtime framework for classifying, tracing, and recovering from agent failures. Its core insight: execution-phase failures (tool crashes, malformed outputs) often originate in reasoning-phase errors (bad plans, ambiguous goals) — but existing agent frameworks treat them as independent problems. SHIELDA provides backward-chaining root cause analysis that links execution symptoms to reasoning origins.

The framework has three contributions:

1. **Taxonomy:** 36 exception types across 12 agent artifacts, systematically derived from 55 studies
2. **Triadic handler model:** Each exception gets a handler composed of three orthogonal dimensions (local handling, flow control, state recovery) — 48 distinct handler patterns
3. **Escalation controller:** Two-level escalation when handlers fail — first within the framework, then to human/peer/backup

---

## Taxonomy: 36 Exceptions Across 12 Artifacts

| Artifact | Phase | Exception Types |
|----------|-------|-----------------|
| Goal | RP | Ambiguous Goal, Conflicting Goal |
| Context | RP | Context Corruption, Context Ambiguity |
| Reasoning | RP | Contradictory Reasoning, Circular/Invalid Reasoning |
| Planning | RP | Faulty Task Structuring, Overextended Planning |
| Memory | RP/E | Memory Poisoning, Outdated Memory, Misaligned Memory Recall |
| Knowledge Base | RP/E | Hallucinated Facts, Knowledge Base Poisoning, Knowledge Conflict |
| Model | RP/E | Token Limit Exceeded, Output Validation Failure, Output Handling Exception |
| Tool | E | Tool Invocation Exception, Tool Output Exception, Unavailable Tool |
| Interface | RP/E | API Invocation Exception, API Response Malformation, API Semantic Mismatch, UI Element Misclick, Text Recognition Error, UI Not Ready, Environmental Noise |
| Task Flow | E | Task Dependency Exception, Error Propagation, Stopping Too Early |
| Other Agent | E | Missing Information, Communication Exception, Agent Conflict, Role Violation |
| External System | E | Protocol Mismatch, External Attack |

Phase key: RP = Reasoning/Planning, E = Execution. RP/E means the exception can originate in either phase.

---

## How Cross-Phase Tracing Works

The backward-chaining mechanism:

1. **Exception classifier** identifies the exception type, affected artifact, and current phase
2. **Escalation controller** starts at the execution failure point and traces the artifact backward through the workflow history
3. When the trace reaches a reasoning-phase artifact, it re-classifies the root cause (e.g., ProtocolMismatchException in execution traced back to FaultyTaskStructuring in planning)
4. The handler selected matches the root cause, not the symptom — enabling plan repair rather than blind retry

Their AutoPR case study demonstrates this: an execution failure (wrong API protocol) was traced to a planning error (the plan included a prohibited workflow file modification). Recovery: abort execution, repair the plan with constraint prompts, re-execute with a corrected plan.

---

## Evaluation

SHIELDA's evaluation is qualitative, not quantitative. The paper validates the framework through a single case study on AutoPR (an open-source GitHub PR automation agent). There are no benchmark scores, no controlled experiments, no comparison against baselines. This is a taxonomy and framework paper, not an empirical one.

**Strengths:** The taxonomy is well-grounded (55 papers), the triadic handler model is composable, and the cross-phase tracing concept is sound.

**Limitations acknowledged:** Single case study, no runtime overhead measurements, no automated exception classifier implementation (the paper describes what the classifier should do, not how to build one with high accuracy).

---

## Skaffen Applicability Analysis

### What Skaffen Has Today

Skaffen's evidence system (`internal/evidence/emitter.go`) records per-turn JSONL events with: phase, tool calls, token counts, outcomes, model info. The `mutations` package aggregates these into `QualitySignal` structs with hard/soft/human signal dimensions and Pareto-front comparison. The Reflect phase has read-only tool access (read, grep, glob, bash) — it can inspect results but not modify code.

Current failure detection is flat: `outcome == "error"` increments `ToolErrorRate` in soft signals. There is no causal linkage between phases — an Act-phase tool failure is counted but never traced to a Decide-phase planning error.

### Which SHIELDA Exception Types Apply to Coding Agents?

**Directly applicable (14/36):**

| Exception | Coding Agent Manifestation |
|-----------|---------------------------|
| Ambiguous Goal | Vague user prompt leads to wrong file edits |
| Faulty Task Structuring | Plan edits files in wrong order, breaking intermediate builds |
| Overextended Planning | Agent plans 30 steps for a 3-line fix |
| Hallucinated Facts | Agent references nonexistent API, function, or import |
| Token Limit Exceeded | Long file + conversation exceeds context window |
| Output Validation Failure | Generated code has syntax errors |
| Tool Invocation Exception | Wrong arguments to bash/edit/write tools |
| Tool Output Exception | Tool succeeds but output is misinterpreted |
| Task Dependency Exception | Edits file B before creating file A that B imports |
| Error Propagation | Early typo cascades through multiple files |
| Stopping Too Early | Agent declares success before running tests |
| Context Corruption | Stale file content in prompt after edits |
| Contradictory Reasoning | Agent says "I'll use approach X" then implements approach Y |
| Circular Reasoning | Agent loops: read file, plan change, re-read, re-plan |

**Partially applicable (6/36):** Memory Poisoning, Outdated Memory, Knowledge Conflict, API Invocation Exception, API Response Malformation, Protocol Mismatch — these map to MCP plugin interactions and external tool calls.

**Not applicable (16/36):** The UI interaction exceptions (Misclick, Text Recognition Error, UI Not Ready, Environmental Noise), multi-agent exceptions (Missing Information, Communication Exception, Agent Conflict, Role Violation), External Attack, and Knowledge Base Poisoning have no current analog in Skaffen's single-agent coding workflow.

### What SHIELDA Requires That Skaffen Lacks

1. **Exception classifier.** SHIELDA assumes a component that can classify failures into the 36 types. Skaffen currently has binary outcome tracking (success/error). Building even a reduced classifier for the 14 applicable types requires either an LLM judge call per failure or pattern-matching heuristics on tool error messages.

2. **Cross-phase artifact log.** SHIELDA traces backward through artifacts. Skaffen's evidence records phases and tools but not the reasoning artifacts (plans, decisions) that led to tool calls. The Decide phase output (the plan) would need to be captured as a traceable artifact.

3. **Handler registry.** SHIELDA's handler patterns assume the agent can: retry with modified prompts, rollback state, abort and re-plan, or escalate to a human. Skaffen's phase FSM is currently linear (Observe->Orient->Decide->Act->Reflect->Compound) with no backward transitions. Adding "Reflect identifies root cause in Decide, triggers re-plan" requires FSM changes.

4. **State recovery.** SHIELDA distinguishes local handling, flow control, and state recovery. Skaffen has git auto-commit but no structured rollback-to-checkpoint mechanism.

### Comparison: SHIELDA vs. Simple "Test Failed -> Trace to Plan" Heuristics

The simple heuristic (which Skaffen could implement today):
- Test failure or build failure in Act phase
- Reflect reads the error message + the plan from Decide
- LLM in Reflect phase says "the plan was wrong because X, next time do Y"
- Compound phase records this as a QualitySignal with failure attribution

This captures ~60% of SHIELDA's value with ~10% of the implementation cost. The main things lost:

1. **Typed classification** — the simple approach just has "something went wrong" without knowing if it was FaultyTaskStructuring vs. HallucinatedFacts vs. OverextendedPlanning. This matters for choosing the right recovery action.
2. **Automated recovery** — SHIELDA's handler registry enables automatic recovery (re-plan, rollback, retry with constraints). The simple approach produces lessons but doesn't act on them within the same session.
3. **Escalation paths** — SHIELDA can route to humans or backup systems. The simple approach just records the failure.

---

## Verdict: inspire-only

**Rationale:**

SHIELDA's taxonomy is valuable as a vocabulary for failure classification, but the framework itself is overengineered for Skaffen's current maturity. Key factors:

1. **No quantitative validation.** A single AutoPR case study provides no evidence that the full 36-type taxonomy and 48 handler patterns improve outcomes vs. simpler approaches. Adopting a framework without proven ROI is premature.

2. **Skaffen's phase FSM needs work first.** SHIELDA assumes backward phase transitions and plan repair. Skaffen's FSM is strictly linear. The prerequisite infrastructure (checkpointing, re-planning, artifact tracing) is a larger project than the SHIELDA integration itself.

3. **The taxonomy is broader than needed.** 16 of 36 exception types (UI, multi-agent, adversarial) are irrelevant to single-agent coding. A purpose-built coding-agent failure taxonomy would be tighter and more actionable.

4. **The simple heuristic covers the critical path.** "Test failed -> LLM attributes to plan error -> record lesson" addresses the most common and impactful failure mode (faulty plans) without framework overhead.

---

## Practical Next Steps

### Now (inspire from SHIELDA)

1. **Add failure classification to Evidence.** Extend `Evidence` struct with `FailureType string` field. Start with 5 coding-specific types: `plan_error`, `hallucinated_api`, `wrong_file_order`, `premature_stop`, `context_stale`. Classify in Reflect phase via LLM judgment on error context.

2. **Capture Decide-phase plan as artifact.** When the Decide phase produces a plan, serialize it into the evidence stream so Reflect can reference it when attributing failures. This is the minimal cross-phase tracing.

3. **Enrich QualitySignal with failure type.** Add `FailureType` to `SoftSignals` so the Compound phase can track which failure types recur, enabling the `Suggest()` mechanism to provide type-specific advice.

### Later (if failure classification proves valuable)

4. **Add FSM backward transitions.** Enable Reflect to trigger a re-plan by transitioning back to Decide with constraints derived from the failure. Requires checkpointing Act-phase state (git stash/branch).

5. **Build a handler registry.** Map failure types to recovery actions: `plan_error -> re-plan with constraints`, `hallucinated_api -> grep codebase for correct API`, `premature_stop -> re-enter Act with "run tests" directive`.

6. **Consider SHIELDA's full taxonomy** once Skaffen handles multi-agent coordination (Clavain fleet integration) — the Other Agent exceptions become relevant then.

---

## References

- [SHIELDA paper (arXiv)](https://arxiv.org/abs/2508.07935)
- [SHIELDA HTML version](https://arxiv.org/html/2508.07935v1)
- [Semantic Scholar entry](https://www.semanticscholar.org/paper/SHIELDA:-Structured-Handling-of-Exceptions-in-Zhou-Chen/693dbcc90c430621994577cc8f3f8b28426c0c33)
- Skaffen evidence emitter: `os/Skaffen/internal/evidence/emitter.go`
- Skaffen mutations/signals: `os/Skaffen/internal/mutations/signal.go`
- Skaffen evidence aggregation: `os/Skaffen/internal/mutations/aggregate.go`
- Brainstorm reference: `docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md` (D13, research agenda item 6)
