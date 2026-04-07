---
track: C
track_name: Distant
agent_count: 4
date: 2026-04-06
target: docs/brainstorms/2026-04-06-hassease-multi-model-forge-agent.md
---

# Track C — Distant Review: Hassease Multi-Model Forge Agent

## Agent 1: fd-majlis-petition-routing

**Source domain:** Arabian tribal petition court (majlis)
**Structural isomorphism:** The sheikh's wakil auto-grants water renewals and defers land disputes until the sheikh's seal is available. Petition classification by consequence severity, not topic, determines approval tier. Wakil authority expands under absence but only within established precedent (qiyas).

---

### Finding M-1

**Severity:** P0
**Title:** Auto-approve classifies by file path, not consequence — test-file delete bypasses all gates

**Description:** Hassease's auto-approve rules classify `test/**` edits as low-risk based on path pattern alone, without inspecting operation semantics. A GLM-routed task that deletes an entire test file — or strips security assertions from a test body — receives the same auto-approval as a task that adds a new test case. The wakil's discipline was to classify petitions by their maximum damage potential, not their stated topic: a "water renewal" petition that actually requested diversion of the sole water source was still a sealed-judgment matter. Consequence-blind path matching fails the same way — the file path names the topic, not the damage.

**Recommendation:** Extend auto-approve evaluation in `internal/trust/` to inspect operation type alongside file path: Write (new file) and Edit (append) pass auto-approve; Edit (delete lines > N) and any operation that removes test assertions should require explicit human approval regardless of path. Gate on `(path_pattern, operation_type, delta_semantics)`, not on `path_pattern` alone.

---

### Finding M-2

**Severity:** P1
**Title:** Human-unavailable scenario has no explicit mode — daemon behavior during Signal silence is unspecified

**Description:** The brainstorm defines approval flow when the human responds (y/n/show) but does not specify what Hassease does when no response arrives. The majlis system explicitly accepted that sealed-judgment petitions would wait weeks rather than be wrongly delegated — inaction was a documented strategy, not an oversight. Hassease's current design leaves the daemon's behavior during human silence as an implicit timeout (likely: block indefinitely or retry), with no documented choice between: block-and-wait, buffer-and-batch, downgrade-to-auto-approved-only (wakil-mode), or escalate-to-alternate-authority. Each strategy has distinct failure modes; none can be safely inferred from context.

**Recommendation:** Define a `HumanUnavailablePolicy` in the approval flow configuration with four explicit modes (`block`, `buffer`, `degrade`, `escalate`) and a timeout threshold. Document the rationale for the chosen default in the architecture section of `cmd/hassease/`. The majlis insight is that "block" is often the correct default — delayed action is safer than wrongly delegated action.

---

### Finding M-3

**Severity:** P1
**Title:** GLM-routed src edits produce thin approval messages — human reviews a diff without the reasoning needed to approve it

**Description:** When the router assigns a task to GLM but the target file is `src/`, Hassease routes execution through the cheap tier while the approval gate demands human judgment. GLM's tool-use responses are terser than Claude's — the approval message the human receives on Signal will carry a diff but minimal reasoning about why the change is safe. The majlis equivalent: a petition prepared by the wakil who summarized too aggressively reaches the sheikh lacking the supporting evidence the sheikh needs to rule. The mismatch between execution model (cheap, terse) and approval requirement (human confidence) is a structural coupling gap, not a UX complaint.

**Recommendation:** Decouple approval-message generation from execution-model selection. When a gated operation is routed to GLM or Qwen, generate the approval message using at least Sonnet-tier reasoning — the cost is one small-context call, and the human's review quality depends on it. Add an `ApprovalMessageProvider` interface in `internal/transport/signal/` that can be configured independently of the execution provider.

---

### Finding M-4

**Severity:** P2
**Title:** Precedent-based adaptive gating is absent — the system cannot safely expand auto-approve from approval history

**Description:** The brainstorm describes a static auto-approve ruleset. The majlis wakil had a well-defined mechanism for authority expansion: qiyas (analogy to established precedent), but only for cases where an identical prior ruling existed. Hassease has no analogous mechanism — there is no approval history that the system could use to widen a gate when the human has approved identical operations repeatedly, and no safeguard preventing naive adaptive gating from over-generalizing (the 11th edit to `src/auth.py` might introduce a qualitatively different change despite superficial similarity to the previous ten).

**Recommendation:** P2 — do not block on this. Consider adding an approval history store in `internal/trust/` as a later phase feature, paired with a conservative generalization rule: auto-approve only when the operation is structurally identical (same file, same line range, same operation type) to an immediately prior approved operation within the same session.

---

## Agent 2: fd-venetian-glassblower-heat-tiering

**Source domain:** Murano glassblowing, three-zone heat management
**Structural isomorphism:** Under-tiering (complex work to glory hole) produces shattering, not degradation. Over-tiering (simple work to founding furnace) is correct output at blocking cost. Routing errors are asymmetric. Different glass compositions require different temperature thresholds — soda-lime is forgiving, borosilicate requires precision.

---

### Finding V-1

**Severity:** P0
**Title:** No mid-execution escalation path — router commits to cheap tier at task-start without runtime complexity detection

**Description:** Hassease's router makes a tier decision at task classification time based on initial description signals (line count, file count, task type label). There is no mechanism to detect mid-execution complexity escalation — if a task described as "single-file edit" reveals cross-module type dependencies after the first three tool calls, the router has already committed to GLM and the session continues accumulating edits in the wrong tier. The glassblowing equivalent: the maestro sends a piece to the glory hole apprentice after a quick visual inspection, but the gather contained a borosilicate streak that the apprentice cannot work before it drops past plasticity — the result is not a rougher finish but a shattered piece. The brainstorm acknowledges this in the escalation trigger table ("model confidence low, or edit touches >50 lines") but these triggers are classification-time criteria, not runtime signals.

**Recommendation:** Add a mid-execution escalation hook in `internal/agent/` (the OODARC workflow engine) that fires on: consecutive tool-call failures, syntax errors in generated edits, cross-file dependency discovery (Edit touching a file not in the original scope), or human rejection of a generated diff. When any hook fires, the session should pause, serialize its current state, and restart with the next-tier provider rather than continuing on the original assignment. This is a one-function addition to the OODARC phase FSM — a `EscalationCheck` step after each `Act` phase.

---

### Finding V-2

**Severity:** P1
**Title:** GLM and Qwen treated as interchangeable within cheap tier — provider-specific turn-depth reliability ignored

**Description:** The routing table assigns tasks to "GLM 5.1 or Qwen 3.6" as if they were equivalent operators at the same thermal zone. The brainstorm does not distinguish their capability profiles. GLM's tool-call JSON is known to degrade after extended multi-turn conversations; Qwen's API latency is higher during Chinese business hours; they may have different multi-file edit reliability. The maestro knows that two apprentices assigned to the same glory hole task have different sustained tempo — one cannot maintain the fifth gather. A long-running routine task assigned to GLM that begins producing malformed tool calls at turn 8 will either fail silently or require restart, with no router awareness of provider-specific turn-depth limits.

**Recommendation:** Create a provider reliability profile in `internal/costrouter/` that encodes known per-provider constraints: max reliable turn depth, known failure modes (malformed tool JSON after N turns, latency spikes in specific time windows), and language/domain reliability (GLM stronger on Chinese codebases, Qwen stronger on structured data tasks). The router should consult the profile at assignment time and re-evaluate provider selection if a task's projected turn depth exceeds a provider's reliable threshold.

---

### Finding V-3

**Severity:** P2
**Title:** Self-reported model confidence is a poor escalation signal — cheap models are least reliable at self-assessment

**Description:** One of the routing table's escalation triggers is "model confidence low." This requires GLM or Qwen to accurately self-assess that they are about to fail — the same models least likely to have reliable confidence calibration. An apprentice who does not recognize that the glass has cooled past working temperature because they lack experience reading the color shift cannot reliably report "I am struggling." Objective escalation signals (tool-call success rate, syntax check pass/fail, test run outcomes) do not depend on the executing model's self-awareness and are available without additional API cost.

**Recommendation:** Replace or supplement "model confidence low" in the escalation triggers with objective runtime signals: Edit tool calls that produce syntax errors on the first validation pass, Bash tool calls that exit non-zero, or consecutive tool calls to the same file without progress. These signals are generated by the execution environment, not the model, and are reliable regardless of provider.

---

### Finding V-4

**Severity:** P2
**Title:** No validation of mandatory post-execution checks — annealing step can be skipped under time pressure

**Description:** The brainstorm mentions that GLM handles "Read, Grep, Glob, simple Edit" and escalates on "model confidence low or edit touches >50 lines," but does not specify whether edits are validated after execution (syntax check, type check, minimal test run). Skipping post-edit validation is the equivalent of skipping the annealing oven — the glass looks complete but contains internal stress that manifests as breakage hours later. The auto-approve path for test file edits has no validation step, meaning a GLM-generated edit that breaks compilation passes through the pipeline without any confirming signal.

**Recommendation:** Add a mandatory `PostEditValidation` step to the tool execution pipeline in `internal/tool/` that runs at minimum a syntax check (language-appropriate: `go vet` for Go, `python -m py_compile` for Python) after every Edit operation, auto-approved or not. Validation failure should trigger the mid-execution escalation hook from V-1.

---

## Agent 3: fd-kamal-celestial-navigation-waypoint

**Source domain:** Indian Ocean kamal navigation, multi-signal consensus
**Structural isomorphism:** No single signal source trusted alone — kamal gives latitude but not longitude, wave swells give heading, birds indicate land proximity. When two or more signals conflict, the navigator heaves-to rather than proceeding on degraded information. Systematic bias in specific conditions (kamal unreliable near equator, wave reading unreliable in monsoon transition).

---

### Finding K-1

**Severity:** P0
**Title:** Semantically wrong edits from cheap providers pass all format-level validation and land unchecked on auto-approved paths

**Description:** Hassease's auto-approve path for test files means that a GLM-generated edit which is structurally valid (well-formed JSON tool call, valid file path, valid Edit parameters) but semantically wrong (logically inverts a condition, deletes a security assertion, introduces an off-by-one in a loop bound) passes every format-level check and lands in the codebase with no confirming signal. The navigator's kamal equivalent: the string knot has slipped — the measurement reads precisely but the reference is displaced, and no other signal was checked. The kamal string cannot detect its own slip; only a second independent signal (star altitude, wave bearing) can catch it. For auto-approved operations, the human review is bypassed — the only remaining signals are format validators, which cannot detect semantic drift.

**Recommendation:** Every auto-approved Edit operation should emit a post-apply validation signal from a source independent of the generating model: at minimum, a syntax check; preferably, a targeted test run scoped to the modified file. This is the navigator's rule of never sailing on a single signal. Wire the validation step into `internal/tool/` such that auto-approve grants execution permission but not bypass of the validation signal — auto-approve means "no human required," not "no confirmation required."

---

### Finding K-2

**Severity:** P1
**Title:** Provider failover silently switches active provider without adjusting response-parsing pipeline — format conventions cross provider boundary

**Description:** If GLM returns API errors and Hassease silently switches to Qwen, the response parsing pipeline may not account for Qwen's different tool-call format (reasoning in content field vs. separate field, different stop-reason strings, different streaming protocol). The navigator's equivalent: switching from wave-reading to bird-watching when waves become unreliable, but interpreting bird behavior using wave-reading conventions — the signal switch happens but the interpretation framework does not. The brainstorm specifies `internal/provider/` as a provider interface layer, but does not specify whether failover is an explicit state transition with format normalization or a silent swap within the provider abstraction.

**Recommendation:** Make provider failover an explicit state transition in `internal/costrouter/`. When a failover occurs, log the switch, re-initialize the response parser for the new provider's format conventions, and — if mid-session — apply a conversation-history normalization pass before continuing. The provider interface contract should require that each adapter fully normalizes to a canonical internal format, so that the session layer above never sees provider-specific format artifacts.

---

### Finding K-3

**Severity:** P2
**Title:** No per-provider reliability telemetry — gradual degradation (slipping kamal string) is invisible until acute failure

**Description:** The brainstorm does not describe any mechanism for tracking per-provider success rates, latency trends, or tool-call format error rates over time. Without this telemetry, gradual provider degradation — GLM's API quality declining over weeks, Qwen's latency growing during traffic spikes, a Chinese API undergoing quiet deprecation — is invisible until it causes an acute session failure. The navigator who sailed the same route for years without noticing that the kamal string had slowly stretched was accumulating a growing latitude error that would eventually produce a missed port.

**Recommendation:** Add per-provider metrics collection to `internal/evidence/` (already planned for cost tracking): track `(provider_id, turn_count, tool_call_success, latency_ms, format_error_bool)` per session turn. Expose a rolling success-rate view that the router can consult for dynamic provider trust weighting. This is a write-once-in-evidence, read-in-router pattern that does not require a separate telemetry service.

---

### Finding K-4

**Severity:** P2
**Title:** Long-session confidence decay is unaddressed — routing assumptions at turn 1 may not hold at turn 50

**Description:** The brainstorm does not address session length limits or confidence recalibration over long conversations. A task that enters a cheap-tier provider with a clean context window at turn 1 may be at turn 50 with a full context, accumulated state, and attention distributed across a long history — the same provider at a materially different operating point. The kamal equivalent: a 30-day crossing where the navigator's initial position fix is not refreshed produces growing positional error regardless of the kamal's per-turn accuracy. The routing decision to stay in the cheap tier was made at session start, not re-evaluated as the session aged.

**Recommendation:** Add a session-turn counter to the OODARC loop in `internal/agent/` with a configurable escalation threshold (e.g., after N turns on a cheap provider, prompt the router to re-evaluate whether to continue in-tier or escalate). This does not require re-routing — the re-evaluation can confirm the current tier — but it forces the system to refresh the classification rather than holding it from session start.

---

## Agent 4: fd-tang-courier-relay-failover

**Source domain:** Tang dynasty yizhan postal relay system
**Structural isomorphism:** Relay stations share horse pools — a burst of feibao traffic depletes horses for changxing. Highest error rate at substrate transitions (horse relay to boat courier) where messages must be re-encoded. Imperial seal must survive every transition intact or the message loses authority. Shared infrastructure means one service class's demands affect another class's capacity.

---

### Finding T-1

**Severity:** P0
**Title:** Skaffen trust evaluator may include autonomous escalation logic — importing it without a wrapper creates a latent privilege escalation path in Hassease

**Description:** The brainstorm states that Hassease imports Skaffen's `internal/trust/` trust evaluator. Skaffen is a sovereign autonomous agent; its trust evaluator almost certainly supports or expects autonomous escalation (the agent grants itself broader tool access after successful operations — this is the standard OODARC trust model). Hassease is human-directed: trust escalation must come exclusively from human approval signals via Signal. If Hassease imports the raw Skaffen trust evaluator without a wrapper that intercepts and blocks autonomous escalation calls, a Skaffen update that activates a previously dormant auto-escalation feature could silently allow Hassease to self-approve bash operations. The relay equivalent: a military-express routing table update by the military administration silently changes regular-dispatch priorities without the civil-post administrator's knowledge.

**Recommendation:** Wrap Skaffen's trust evaluator in a `HasseaseTrustAdapter` in `internal/trust/` that overrides the autonomous escalation interface — any call to self-escalate should panic or return `ErrHumanApprovalRequired`. The adapter should be the only trust evaluator Hassease code calls; direct imports of Skaffen's trust package should be disallowed via a `//nolint` rule or a Go workspace alias. This is the critical boundary: Hassease's safety model depends on trust gates that Skaffen's packages were not designed to enforce.

---

### Finding T-2

**Severity:** P1
**Title:** Mid-session provider failover injects previous provider's conversation history into new provider without format normalization — edits may be re-applied

**Description:** If a task starts on GLM and fails over to Qwen at turn 8, the new provider receives 8 turns of GLM-formatted conversation history. Qwen's interpretation of GLM's tool-call format (especially for Edit operations that have already been applied) may differ — Qwen may treat a completed edit as pending, or may misread the file-state implied by the historical tool calls, causing it to re-apply an edit that already landed. This is the relay's substrate transition problem: the boat courier reread the waypoint list using river-distance conventions instead of overland-distance conventions, repeating a segment already covered. The brainstorm's "Session handoff" open question acknowledges the problem at the coarse escalation level but does not address mid-session intra-provider failover.

**Recommendation:** When a provider failover occurs mid-session, the conversation history passed to the new provider should be normalized: completed tool calls should be summarized as state facts ("File X has been modified as follows: ...") rather than passed as raw tool-call turns, so the new provider receives an unambiguous current state rather than a format-dependent execution log. Implement this normalization in `internal/session/` as a `NormalizeForProvider(history []Turn, target ProviderID) []Turn` function called on every failover event.

---

### Finding T-3

**Severity:** P1
**Title:** Skaffen internal packages lack stable cross-module interfaces — Hassease imports implementation details that can change without notice

**Description:** The brainstorm proposes that Hassease import Skaffen's `internal/` packages directly (same Go workspace). Go's `internal/` convention explicitly means these packages are not part of Skaffen's public API and carry no stability guarantees — they are implementation details that Skaffen's maintainers can change, rename, or delete without a semver boundary. The relay equivalent: a district administrator who manages his station's resources using another province's internal accounting tables — when the other province reorganizes, the administrator's records become invalid without warning. The table of shared packages (8 packages from `internal/`) in the brainstorm describes exactly this coupling.

**Recommendation:** Before building Hassease, negotiate with the Skaffen module which packages can be promoted to `pkg/` (public, stable, semver-governed). Packages that Hassease genuinely needs — `agent/`, `tool/`, `trust/`, `provider/`, `session/` — should become shared library packages under a new import path (e.g., `os/Skaffen/pkg/` or a separate `core/libskaffen/` module). The brainstorm's "Skaffen module boundary" open question should be resolved as a P0 prerequisite to Hassease construction, not deferred.

---

### Finding T-4

**Severity:** P2
**Title:** Hassease and Skaffen JSONL session output will be interleaved and indistinguishable by downstream consumers

**Description:** The brainstorm calls for Hassease to emit JSONL evidence via the same `internal/evidence/` package as Skaffen. If both daemons operate on the same repository — which is the expected production scenario (Skaffen running autonomous tasks while Hassease runs human-directed tasks) — their session files will be written to the same directory structure without a source discriminator. Interstat, the evidence pipeline, and cost reporting will be unable to attribute session costs, tool calls, or edits to the correct daemon. The relay equivalent: two service classes sharing the same log book without class markers, making audit impossible.

**Recommendation:** Add a `daemon_id` field to the JSONL evidence schema in `internal/evidence/` with a string value set at daemon startup (e.g., `"hassease"` vs `"skaffen"`). This is a one-line schema addition that enables all downstream consumers to filter and attribute correctly without architectural changes.
