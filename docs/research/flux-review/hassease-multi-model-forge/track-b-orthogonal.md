---
track: B
track_name: Orthogonal
agent_count: 4
date: 2026-04-06
target: docs/brainstorms/2026-04-06-hassease-multi-model-forge-agent.md
---

# Track B — Orthogonal Review: Hassease Multi-Model Forge Agent

## Agent 1: fd-airline-yield-management-routing

**Source discipline:** Airline revenue management — O&D inventory control, EMSR-b bid-price calibration, continuous nesting, spoilage vs. dilution threshold design

---

### Finding B1-1

**Severity:** P1
**Title:** Mid-task escalation has no provider-boundary context normalization — escalation failures are silent

**Description:** Airline continuous nesting requires that closing a lower fare class never creates a committed state that blocks the seat from higher-class rebooking. Hassease's escalation path (GLM/Qwen → Sonnet → Opus) has no equivalent guarantee. When a task starts on GLM 5.1 and a mid-task escalation fires — triggered by a failed edit, low confidence, or multi-file discovery via Glob — the handoff to Claude Sonnet must carry the conversation history accumulated on GLM. GLM's conversation history uses a provider-specific wire format. If `internal/costrouter/` passes raw GLM history to the Anthropic adapter without normalization, Claude's API will reject it. The brainstorm does not specify what happens on escalation failure: does the task halt and notify the builder, or does GLM continue past its competence boundary? If GLM continues, the cheap-tier model handles a task it already signaled it could not handle correctly.

**Recommendation:** Define a provider-agnostic intermediate representation (normalized message list: role, content blocks, tool calls) in `internal/costrouter/` or a new `internal/agent/handoff/` package. Every provider adapter must produce and consume this format. On escalation, the handoff normalizes GLM history to the intermediate format before passing to the Anthropic adapter. If normalization fails, the task halts with a Signal notification to the builder rather than allowing GLM to continue.

---

### Finding B1-2

**Severity:** P1
**Title:** The "80% cheap routing" target is stated as a ratio, not a threshold — this functions as a quota that can override task complexity signals

**Description:** In airline RM, spoilage and dilution are calibrated against measured demand distributions — the bid price threshold is a continuous function of demand signals, not a fixed percentage counter. Hassease's brainstorm states "routes ~80% of tasks to subsidized Chinese models" as a design goal. If `internal/costrouter/` implements this as a per-session counter (route to GLM until 80% of session tasks are GLM-routed, then switch), the counter overrides task complexity signals once the ratio is reached. A session with many simple tasks fills the GLM quota early; later complex tasks that should escalate are blocked by the counter. Conversely, an outage that forces early Claude routing can trigger post-recovery GLM over-routing to rebalance — routing complex tasks cheaply to compensate for the ratio drift.

**Recommendation:** Express the 80% figure as a calibration target for the complexity-signal threshold, not as a runtime counter. The `costrouter` evaluates each task's complexity independently and the aggregate ratio is a measurement of threshold correctness, not a hard cap. Remove any per-session quota enforcement; if a ratio metric is needed for observability, log it as a gauge rather than enforcing it as a limit.

---

### Finding B1-3

**Severity:** P2
**Title:** No quality baseline — routing is evaluated against task completion rate, not quality-adjusted counterfactual

**Description:** RM systems cannot calibrate bid prices without unconstrained demand estimates — the true quality of what a higher-tier model would have produced on the same task. Hassease's cost router, as described, has no mechanism to sample Claude on a subset of GLM-routed tasks to measure the quality delta. Without this signal, dilution events (GLM producing plausible-wrong output on tasks Claude would have handled correctly) accumulate silently. The JSONL evidence trail records completion and cost but not output quality relative to the Claude counterfactual. Over time, the routing threshold drifts toward over-routing to cheap models because the calibration signal (quality degradation) is never observed.

**Recommendation:** Designate a configurable sampling rate (e.g., 5% of GLM-routed tasks) where the same task is also sent to Claude Sonnet for comparison. Log both outputs to JSONL with a `quality_sample: true` flag. This is not a runtime quality gate — it is a calibration dataset. Surface the comparison in cost reports to detect threshold drift before it becomes a systemic quality problem.

---

### Finding B1-4

**Severity:** P2
**Title:** Batch task routing treats concurrent Signal messages independently — aggregate complexity is not evaluated

**Description:** Airlines handle group bookings differently from individual bookings because committing a block of seats at once requires aggregate demand assessment. When the builder sends a burst of related Signal messages (multiple tasks targeting the same module), `internal/costrouter/` routes each task independently based on its individual complexity signals. The aggregate complexity of the batch — three individually "simple" edits to the same abstraction layer — may exceed the threshold for Claude routing. Routing each task cheaply and executing them concurrently also creates file-scope overlap that the costrouter will not detect if it evaluates tasks without checking concurrent working sets.

**Recommendation:** Add a batch-context window to `internal/costrouter/`: when multiple tasks arrive within a configurable time window (e.g., 10 seconds), evaluate their aggregate file scope before committing individual routing decisions. If the union of working sets spans more than N files or touches shared abstractions, escalate the entire batch to a single Claude session rather than routing tasks independently.

---

## Agent 2: fd-industrial-control-plc-approval

**Source discipline:** IEC 61511 functional safety — permit-to-work systems, DCS operator acknowledgment workflows, safe defaults on ambiguous responses, audit trail non-repudiation

---

### Finding B2-1

**Severity:** P1
**Title:** Approval scope is not bound to the specific tool call — a single "y" can authorize multiple subsequent edits in the same agent turn

**Description:** Industrial permit-to-work systems bind authorization to a specific work order on a specific equipment item; the permit cannot be reused for adjacent work without reauthorization. Hassease's approval flow, as described, responds to "y" / "approve" / "go" signals from the builder. If the approval context is scoped to the agent turn rather than the individual tool call, a single "y" sent in response to an edit proposal for `src/auth/token.go` can be parsed as blanket authorization for subsequent edits to `src/auth/refresh.go` proposed in the same turn. The audit trail would record both edits as approved, but the builder only evaluated the first. `internal/trust/` (imported from Skaffen) must enforce per-tool-call scope binding — this is not inherited automatically if Skaffen's trust evaluator was designed for a different approval granularity.

**Recommendation:** In `internal/transport/signal/`, generate a unique `approval_id` (short hash of proposed-action parameters) for each tool call that requires approval. Include the `approval_id` in the Signal approval request message. The approval parser only matches a response to the approval with the matching `approval_id`. Responses that do not reference or implicitly match the current pending `approval_id` are held, not attributed forward to the next pending approval.

---

### Finding B2-2

**Severity:** P1
**Title:** Unrecognized approval responses trigger immediate re-prompting while the agent continues — delayed response is attributed to the next pending approval

**Description:** DCS operator interfaces fail safe on ambiguous input — a partial acknowledgment causes the automation to hold, not proceed, and the operator must send a recognized response before anything executes. Hassease's approval parser recognizes "y", "n", "show", "diff", "preview". If the builder sends "yes please" or a thumbs-up emoji, the parser must decide: proceed, deny, or hold. If the unrecognized-response branch logs a warning, treats the response as denial, and immediately re-prompts while the agent continues advancing its task queue, a timing race opens: the builder's follow-up "y" lands in a Signal conversation where the agent has already moved to the next pending approval and now attributes the "y" to an edit the builder never evaluated.

**Recommendation:** Unrecognized responses must pause the approval queue, not trigger re-prompting while execution continues. `internal/transport/signal/` enters a waiting state: no further tool calls execute, no new approval requests are sent, until the builder sends a recognized response. The Signal message sent on unrecognized input should be: "Unrecognized response. Reply y / n / show to proceed." The approval ID for the original pending action remains active during the wait.

---

### Finding B2-3

**Severity:** P1
**Title:** Approval is not bound to a proposed-action hash — the approved action and the executed action can diverge without detection

**Description:** Permit-to-work systems include a work description in the permit; the authorizing operator approves the specific described work, and any deviation requires a new permit. Hassease's JSONL evidence trail records completions and costs, but the brainstorm does not specify whether the approval interaction records a deterministic hash of the exact tool call parameters (file path, line range, content hash) at the time of the approval request. If the agent re-plans between sending the approval request and executing the tool call — due to intermediate model output or a mid-turn Glob that updates the working set — the executed action can differ from the approved action with no detection mechanism. The JSONL record would show "approved: y, executed: success" for an action the builder never reviewed.

**Recommendation:** At the time an approval request is generated in `internal/transport/signal/`, compute a `proposed_action_hash` as a deterministic hash of all tool call parameters (tool name, file path, line range, content). Store this hash in the pending approval record. Before executing, recompute the hash from the actual tool call parameters and assert equality. If the hashes diverge, cancel execution, send a new approval request with the updated parameters, and log the divergence event to JSONL.

---

### Finding B2-4

**Severity:** P2
**Title:** No response timeout defined — an unresponsive builder causes the task to hang indefinitely with no escalation path

**Description:** DCS systems define explicit escalation paths when the operator does not acknowledge within a timeout: pause automation, alert a supervisor, log the timeout. Hassease's approval flow sends a Signal message and waits for a response before executing the tool. The brainstorm does not define a response timeout. If the builder's phone is offline, in airplane mode, or Signal is disrupted, the daemon blocks indefinitely on approval for an edit that may be part of a longer task chain. There is no fallback: no timeout-based denial, no escalation to a secondary contact, no session-suspension protocol. The daemon consumes no resources while blocked, but the human has no way to know the daemon is waiting rather than working.

**Recommendation:** Add a configurable `approval_timeout_seconds` per tool type to the trust evaluator configuration. On timeout: (1) deny the pending tool call, (2) send a Signal notification "Approval timed out for [action] — task paused. Reply 'resume' to retry or 'cancel' to abort.", (3) log a timeout event to JSONL with the proposed action hash. The timeout for Bash should be shorter than for Edit, reflecting their relative consequence levels.

---

## Agent 3: fd-satellite-ground-station-command

**Source discipline:** Spacecraft operations — command uplink sequencing, CLTU acknowledgment, command holdback for dependent tasks, session state reconciliation across contact windows

---

### Finding B3-1

**Severity:** P1
**Title:** Signal delivers messages without guaranteed ordering — dependent tasks can execute in wrong sequence with no gap detection

**Description:** Spacecraft command sequences use sequence counters so the ground station detects dropped or reordered commands before executing them. Signal is not a sequenced, reliable transport: messages sent in rapid succession can arrive out of order, especially across different network conditions. Hassease's `internal/transport/signal/` receives builder messages and (as designed) processes them as tasks. If the builder sends "create src/handler.go" followed immediately by "add tests for the handler", Signal may deliver the test instruction first. Hassease begins generating tests referencing a file that does not yet exist, then creates the file with a different interface than the tests assumed. Both tasks complete with success receipts; the codebase is broken. There is no sequence numbering mechanism described in the brainstorm to detect or prevent this.

**Recommendation:** Assign a monotonic sequence number to each Signal message received, logged in JSONL with each task record. If the daemon receives message N+2 before N+1, it holds N+2 and sends a Signal notification to the builder: "Message gap detected (received #8, expected #7) — please confirm intent or resend." The hold is released when the gap is filled or the builder explicitly sends a "skip gap" command.

---

### Finding B3-2

**Severity:** P1
**Title:** Daemon restart has no recovery phase — interrupted tasks leave partial edits as silent context for subsequent work

**Description:** When a satellite contact window closes mid-sequence, the ground system reconciles commanded state against telemetry before issuing new commands in the next window. Hassease runs as a persistent headless daemon. If it is OOM-killed or restarted by systemd mid-task, `internal/session/` (JSONL persistence from Skaffen) will have a task record with a start event but no completion event. On restart, the daemon does not currently have a defined startup-phase recovery check. The next builder message causes the daemon to begin a new task. Glob and tool discovery will find the partial edits from the interrupted task and treat them as valid project state, potentially building incorrectly on top of incomplete work. The builder has no signal that anything is wrong.

**Recommendation:** Add a startup recovery phase to `cmd/hassease/` before the Signal listener begins accepting new messages. Scan JSONL for tasks with start records and no completion records. Reconstruct the file scope from each interrupted task's tool execution log. Send a Signal summary to the builder: "Daemon restarted. Interrupted task: [task description], partial edits in: [file list]. Reply 'rollback' to revert, 'resume' to continue, or 'ignore' to proceed without action." Only begin accepting new instructions after the builder responds.

---

### Finding B3-3

**Severity:** P2
**Title:** No send acknowledgment — the builder cannot distinguish "Hassease received and is working" from "Hassease never received the message"

**Description:** Spacecraft command uplink systems require CLTU acknowledgment confirming the command reached the on-board computer before ground controllers advance to the next command. Hassease processes builder messages and begins task execution, but the brainstorm does not describe a per-message receipt sent back to the builder via `internal/transport/signal/`. If Signal delivery fails or the daemon crashes after receiving a message but before beginning work, the builder's view is identical to successful receipt: the last outgoing message was their instruction, and they are waiting for a response. The builder has no way to distinguish the daemon working silently from the daemon having never received the message.

**Recommendation:** `internal/transport/signal/` should send a lightweight acknowledgment Signal message for every received builder instruction before task execution begins: "Received: [task summary, first 80 chars]. Starting now." This costs one Signal message per task and eliminates the ambiguity between silent work and silent failure. If the daemon crashes after receipt but before sending the ack, the builder sees no ack and knows to resend.

---

### Finding B3-4

**Severity:** P2
**Title:** Multi-step tasks have no atomicity — a failure in step 2 leaves the codebase in a partial-refactor state

**Description:** Spacecraft command macros support rollback: if a step in an expanded macro fails, the ground system can issue a rollback sequence to undo the macro's prior steps. Hassease's multi-step tasks — "refactor this module and update its tests" — are described as sequences of individual tool calls. Each tool call commits independently to the filesystem as it executes. If step 2 (test update) fails after step 1 (module refactor) has committed, the codebase is in a partial state: the module was refactored but the tests still reference the old interface. The JSONL log shows step 1 as completed and step 2 as failed. There is no rollback mechanism described, and the builder must manually determine what step 1 changed and either revert it or complete step 2 by hand.

**Recommendation:** For multi-step tasks, `internal/agent/` should support a task scope with a defined file working set. Before beginning the task, record a git stash or snapshot of the working set files. If any step in the task fails, offer the builder a "rollback" option in the failure Signal message that restores the snapshot. This does not require atomic filesystem transactions — a pre-task stash ID in JSONL is sufficient for the rollback case.

---

## Agent 4: fd-pharmaceutical-cmo-outsourcing

**Source discipline:** Pharmaceutical CMO governance — capability qualification matrices, per-CMO quality agreements, tech transfer completeness, principal accountability under regulatory delegation

---

### Finding B4-1

**Severity:** P1
**Title:** Auto-approve rules apply uniformly across providers — GLM/Qwen src-file edits auto-approve at the same rate as Claude edits despite lower project-context awareness

**Description:** Pharmaceutical quality agreements define oversight requirements proportional to the CMO's quality risk tier: a Tier 3 CMO with an unproven track record requires more lot-release review than a Tier 1 CMO with a decade of compliance data. Hassease's trust evaluator (from `internal/trust/`) applies auto-approve rules based on file type: test files auto-approve, src files require approval, Bash always requires approval. These rules do not differentiate by provider. A single-file src edit generated by GLM 5.1 — a model with no project-specific training and limited context about the codebase's conventions — goes through the same approval gate as the same edit generated by Claude Sonnet 4.6, which has the full session context. GLM is more likely to produce plausible-wrong outputs (wrong error handling convention, wrong abstraction pattern) that pass a casual "looks reasonable" review precisely because they are syntactically correct.

**Recommendation:** The trust evaluator in `internal/trust/` should read provider identity from the task context and apply per-provider auto-approve rules. For GLM/Qwen: reads auto-approve, no src-file edits auto-approve (all edits require Signal approval) until a per-provider track record is established. For Claude: current rules apply. Store per-provider auto-approve configuration in a qualification registry, not hardcoded in the trust evaluator, so the scope can expand as GLM/Qwen establish track records on the project.

---

### Finding B4-2

**Severity:** P1
**Title:** Provider identity is not guaranteed in every JSONL evidence record — GLM-sourced changes are not distinguishable post-session

**Description:** Pharmaceutical batch records must identify the manufacturing site for every production step; the sponsor cannot attribute a quality deviation to "one of our CMOs" without specifying which one. Hassease's JSONL evidence trail records completions and costs, but the brainstorm does not specify that provider identity is a mandatory field in every tool execution event. If `internal/evidence/` (from Skaffen) emits tool execution records without a required `provider` field, post-session analysis cannot attribute individual changes to their originating model. This prevents per-provider quality analysis, breaks the cost-per-task-type breakdown by provider, and makes it impossible to investigate a regression by asking "which model made this change."

**Recommendation:** Add `provider_id` (e.g., `"glm-5.1"`, `"claude-sonnet-4-6"`) and `provider_tier` (e.g., `"cheap"`, `"complex"`, `"planning"`) as mandatory fields in `internal/evidence/`'s tool execution event schema. The costrouter writes provider identity to the task context before dispatching to a provider adapter; the evidence emitter reads it from context rather than from the provider adapter directly, so the field is populated regardless of which code path emits the event.

---

### Finding B4-3

**Severity:** P2
**Title:** Tech transfer is incomplete — GLM/Qwen receive task instructions without the project-convention context needed to avoid plausible-wrong outputs

**Description:** Pharmaceutical tech transfer ensures the CMO has complete process knowledge — SOPs, critical quality attributes, in-process controls — before manufacturing begins. A CMO that fills gaps with assumptions produces batches that are superficially correct but fail quality release. GLM 5.1 and Qwen 3.6 are general-purpose models with no project-specific training. When routed a task, they receive the immediate task instruction and the file contents the tool registry surfaces — but not the project's conventions (error handling patterns, abstraction boundaries, naming rules, test structure). Claude sessions accumulate this context through the conversation. GLM/Qwen start cold every task. The costrouter's task classification may correctly identify a task as "simple single-file edit" (GLM-appropriate by complexity) while that task touches a convention-sensitive path where GLM's lack of context makes it likely to produce a plausible-wrong output.

**Recommendation:** Build a "context injection" step in `internal/costrouter/` that prepends project-convention summaries to tasks routed to GLM/Qwen. Source these from a `CONVENTIONS.md` or equivalent artifact that captures the project's critical patterns (error handling, abstraction contracts, test structure). Update the injected context as conventions evolve. This is the tech transfer equivalent: the CMO (GLM/Qwen) receives the minimum necessary process knowledge before it begins work.

---

### Finding B4-4

**Severity:** P2
**Title:** Provider fallback during outage can trigger post-recovery ratio rebalancing that under-routes complex tasks to GLM

**Description:** Pharmaceutical supply chain risk distribution plans for single-CMO outages, but the recovery protocol must not compromise product quality by rushing compensatory batches through an under-reviewed CMO. If GLM's API goes down for 45 seconds and the costrouter escalates pending cheap-tier tasks to Claude, the session's routing ratio will skew toward Claude for that window. If the ratio is tracked as a per-session counter (see B1-2), the rebalancing logic may subsequently route tasks aggressively to GLM to correct the drift — including tasks that individually would have triggered Claude escalation. The outage creates a quality deficit that the rebalancing logic fills by overloading GLM with work it is not qualified to handle.

**Recommendation:** The fallback escalation path in `internal/costrouter/` should flag tasks escalated due to provider unavailability (not due to complexity signals) with a `escalation_reason: "provider_unavailable"` JSONL field. Post-outage routing must not use the ratio counter to rebalance; it resumes normal threshold-based routing. If ratio observability is desired, report it as a post-session metric rather than enforcing it as a runtime constraint.
