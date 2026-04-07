---
track: D
track_name: Esoteric
agent_count: 3
date: 2026-04-06
target: docs/brainstorms/2026-04-06-hassease-multi-model-forge-agent.md
---

# Track D — Esoteric Review: Hassease Multi-Model Forge Agent

## Agent 1: fd-polynesian-wayfinding-star-compass-routing

**Source domain:** Tongan kaveinga star compass navigation — specifically the *kaveinga* practice of switching between celestial reference signals as they rotate out of useful arc, combined with dead-reckoning legs between verifiable waypoints.

---

### Finding 1

**Severity:** P0

**Title:** The costrouter is a launch heading, not a continuous bearing — it will navigate by a star that has set

**Description:**
The brainstorm's routing table (`internal/costrouter/`) classifies tasks at intake: Read → GLM, single-file edit → GLM/Qwen, refactor → Sonnet, planning → Opus. This is the kaveinga equivalent of picking a star at the start of a voyage and sailing by it regardless of whether it remains above the horizon. The structural problem is that tasks reveal their true complexity mid-execution: a "simple single-file edit" of `src/auth.py` becomes a multi-module dependency graph as the model reads connected files. The brainstorm acknowledges escalation triggers ("Model confidence low, or edit touches >50 lines") but frames them as an exception path rather than a continuous per-turn signal. There is no indication that the costrouter re-evaluates model selection after each OODARC phase completes — meaning the router can commit GLM to a task leg for which GLM is structurally inadequate and keep it there until the edit fails, not before.

**Recommendation:**
Design `internal/costrouter/` with a per-turn `SelectModel(ctx TurnContext) (ProviderID, confidence float64)` interface rather than a per-task `ClassifyTask(task Task) ProviderID`. The OODARC phase FSM (`internal/agent/`) already has natural re-evaluation points at each phase boundary — wire the costrouter's signal-adequacy check to fire at each Orient and Decide phase entry, not just at task intake.

---

### Finding 2

**Severity:** P1

**Title:** Dead-reckoning gap: no course memory survives a mid-task model switch

**Description:**
Polynesian navigators crossing a dead-reckoning leg — no visible stars, no landmark — maintain course confidence through accumulated positional history: last known bearing, estimated current speed, elapsed time since last fix. When Hassease escalates from Qwen to Claude Sonnet mid-refactor, the brainstorm specifies that shared packages from Skaffen include `internal/session/` (JSONL session persistence) but does not specify what the escalation handoff message contains. If the new model receives only the current file state and the pending tool call, it lacks the navigational record: which edits were already applied, which were rejected by the human, and what reasoning chain led to the current position. Claude will re-derive context from artifact state alone, making decisions inconsistent with the decisions already committed to the working tree — the equivalent of a relief navigator who knows the destination but not the course sailed.

**Recommendation:**
Define an explicit `CourseMemory` struct that travels with every model escalation: applied edits (with human approval status), rejected proposals, per-turn reasoning summaries from prior models, and the original task framing. This struct should be the first content in the escalation prompt, not an optional attachment. The OODARC `internal/agent/` phase log is a natural source — serialize it as the handoff payload.

---

### Finding 3

**Severity:** P2

**Title:** No complementary signal integration — GLM's uncertain outputs are accepted or rejected in isolation without cross-model spot-check

**Description:**
The kaveinga navigator cross-references star bearing against swell direction against phosphorescence — not because any one signal is wrong, but because each has an orthogonal failure mode and agreement between independent signals raises confidence without requiring an expensive celestial observation. Hassease's architecture treats models as a sequential chain: GLM produces output, the trust evaluator gates it for human approval, the human approves or rejects. There is no mechanism for routing an uncertain GLM output to Qwen for a confidence cross-check before surfacing to the human — the two cheap models are purely competitive (the router picks one) rather than cooperative (one can verify the other). For edits in the "low confidence" escalation band — where GLM's confidence is below threshold but not low enough to auto-escalate to Sonnet — a Qwen cross-check would catch systematic GLM errors without incurring Sonnet cost.

**Recommendation:**
Add an optional `VerifyWith(secondaryProvider ProviderID)` field to the costrouter's turn context. For turns where `confidence < threshold && cost(verify) < cost(escalate)`, run the proposed edit through a second cheap model's read-only review before surfacing to the human or committing. This is additive — it does not change the approval flow, only adds a filter before the trust evaluator sees the output.

---

## Agent 2: fd-cham-po-nagar-temple-intermediary-petition

**Source domain:** Po Nagar temple petition system, Champa kingdom (11th century CE) — the halau jia intermediary priest classified incoming petitions by ritual category, batched them by ceremony cycle, triaged by urgency, rewrote them into the goddess's accepted register, and maintained the queue when the temple was closed to worshippers.

---

### Finding 4

**Severity:** P0

**Title:** Translation infidelity: the Signal approval message is a model-generated summary, not a faithful diff — the human approves a description, not the action

**Description:**
The brainstorm's approval flow sends a Signal message: "I want to edit `src/auth.py` lines 45-60 — add token refresh check." This is a halau jia problem of the worst kind: the intermediary translates the petition into language the goddess understands, but the translation omits critical ritual obligations from the original request. If GLM proposes an edit that adds a token refresh check *and* removes an existing validation guard (a common LLM pattern: simplify while implementing), the Signal message summarizes only the additive intent. The human approves "add token refresh check," Hassease executes the full edit including the deletion, and the human has sanctioned something they did not evaluate. The brainstorm includes "show" / "diff" / "preview" as optional commands but does not make diff-first the default — the natural approval path is summary-only.

**Recommendation:**
Invert the default: the Signal approval message should lead with a compact diff block (unified diff, truncated to 30 lines with a "show full" option) and trail with the natural-language summary. The summary is the translation; the diff is the original text. If the diff exceeds the Signal message character limit, attach it as a file and include the line count and changed-symbol names in the message body. Never let a summary stand as the only artifact a human approves against.

---

### Finding 5

**Severity:** P1

**Title:** No approval batching — the intermediary delivers each petition individually, producing notification fatigue that defeats the approval purpose

**Description:**
The Po Nagar temple structured its petition calendar around ceremony cycles precisely because batching is the only way to maintain a functioning intermediary relationship at scale. A worshipper who must return to temple for each minor request stops coming; a builder who receives a Signal notification for each of 15 test-file edits in a single logical change either rubber-stamps everything or disables the approval flow. The brainstorm's auto-approve rules (test files auto-approved, src files require approval) partially address this but at the wrong granularity — the test-file auto-approve rule is a static configuration, not a batching mechanism. A change touching 8 `_test.go` files and 2 `src/` files should present as one approval event covering the full logical change, not 2 separate approval requests (the 8 test files vanish, the 2 src files interrupt separately).

**Recommendation:**
Introduce a `PetitionBatch` concept in `internal/transport/signal/`: group tool calls that share a common OODARC phase and logical parent task into a single approval event. The batch message shows: total actions, risk category of each, and a "approve all / approve-read-deny-writes / deny all" response vocabulary. The halau jia's parallel: the priest batches all petitions of the same ritual category for a single ceremony rather than scheduling individual audiences.

---

### Finding 6

**Severity:** P2

**Title:** Closed-temple problem: no queue or timeout when the human is unavailable, the pipeline stalls with no recovery path

**Description:**
The Po Nagar temple maintained a petition queue for when it was closed — worshippers could leave their requests with a lesser functionary, and the priest would process the backlog at the next opening. Hassease's approval flow has no equivalent: when the builder does not respond to Signal within some window, the brainstorm specifies no behavior. The daemon presumably blocks waiting for the "y" / "n" / "show" response. The OODARC engine (`internal/agent/`) has no concept of a deferred-approval state — it either proceeds (approved) or halts (denied). Long-running tasks initiated before the builder goes offline will freeze mid-execution, holding file locks and partial edits, with no way for the builder to see the queue of pending petitions when they return.

**Recommendation:**
Add a `pending_approvals` queue in `internal/transport/signal/` with configurable timeout behavior: after N minutes without response, park the pending action in the queue and continue with auto-approvable work. When the builder returns and issues a `bd list` or `status` command, surface the queued petitions as a batch. The builder can then bulk-approve, bulk-deny, or review individually. The critical invariant: the daemon must never hold uncommitted partial edits while waiting — either the edit is fully applied or fully rolled back before entering the wait state.

---

## Agent 3: fd-sogdian-caravan-relay-trust-delegation

**Source domain:** Sogdian Silk Road relay merchant network (6th century CE) — the sartpao (caravan master) operated through a chain of trusted intermediaries who shared common trade protocols but held strictly scoped authority: a relay merchant could warehouse and forward goods but could not renegotiate the terms under which they were consigned, even if they had full access to the goods themselves.

---

### Finding 7

**Severity:** P0

**Title:** Borrowing Skaffen's warehouse: importing `internal/trust/` risks inheriting Skaffen's sovereign auto-approve defaults with no explicit override mandate

**Description:**
The Sogdian principle is precise: "borrowing a warehouse does not mean borrowing trade agreements." Hassease imports Skaffen's `internal/trust/` package — Skaffen's trust evaluator was designed for a sovereign agent that acts autonomously without per-action human approval. Skaffen's defaults almost certainly auto-approve edits to source files (Skaffen is autonomous — that is its identity). When Hassease instantiates the trust evaluator, it must override these defaults to enforce human-directed approval. The brainstorm states this intent ("Hassease is human-directed") but does not specify the mechanism. The danger is that Go struct initialization with zero-value or copied defaults will silently inherit Skaffen's approval posture. There is no indication that `internal/trust/` exposes a constructor that requires an explicit trust policy argument, nor that Hassease defines its own policy struct that overrides Skaffen's defaults — the warehouse is borrowed, and the trade agreements may travel with it invisibly.

**Recommendation:**
Require that `internal/trust/` expose a `NewEvaluator(policy TrustPolicy) *Evaluator` constructor that takes an explicit policy argument with no defaults. Skaffen and Hassease each pass their own `TrustPolicy` at construction time. Hassease's policy should be defined in `cmd/hassease/` and treated as a configuration artifact — never derived from or defaulted to Skaffen's policy. A compile-time check (a `HumanDirectedPolicy` interface that Hassease's policy must satisfy) would make the boundary visible to future maintainers.

---

### Finding 8

**Severity:** P1

**Title:** Binary trust with no content-sensitivity: editing a `README.md` and editing a cryptographic key handler require the same approval ceremony

**Description:**
The Sogdian relay network differentiated cargo by material sensitivity: silk traveled under lighter inspection than imperial tribute items; the same merchant who could freely handle cotton bales needed countersigned documentation to touch gold ingots. Hassease's current trust model gates by tool type (Edit → requires approval) rather than by file-path sensitivity or content class. The brainstorm's auto-approve rules gesture toward a binary risk split (test files auto-approved, src files require approval) but this is still tool-type gating, not content-sensitivity. An edit to `src/http/client.go`'s retry logic and an edit to `src/auth/jwt_verify.go`'s signature validation are both "edit src files" — they both trigger the same Signal approval request with no differentiation. The builder learns to treat all src-file approval requests as equivalent, which means they apply equal scrutiny to every request, which means the high-risk requests receive insufficient scrutiny.

**Recommendation:**
Define a `SensitivityClass` enum in `internal/trust/` (Standard, Elevated, Critical) and a path-pattern config in Hassease's trust policy that maps file path globs to sensitivity classes (e.g., `**/auth/**` → Critical, `**/*_test.go` → Standard). The Signal approval message should include the sensitivity class and a brief rationale. Critical edits require an explicit acknowledgment ("approve-critical") rather than a simple "y" — the different vocabulary forces the builder to mentally re-engage rather than pattern-matching on the response they always send.

---

### Finding 9

**Severity:** P2

**Title:** Trust is stateless across sessions: 50 successful GLM test-file edits build no track record, and the 51st requires full approval

**Description:**
The Sogdian network maintained factoring records — a merchant's 20-year record of reliable delivery at every relay station was the basis for extending them greater autonomy at each subsequent crossing. The network's trust was not fixed at the start of a trading relationship; it accumulated through evidence. Hassease's trust evaluator (imported from Skaffen's `internal/trust/`) has no indicated mechanism for accumulating approval history across sessions. GLM 5.1 may prove reliably accurate for `_test.go` edits across 50 sessions — but each new session starts from the same static approval rules. The JSONL evidence log (`internal/evidence/`) is present, but there is no pipeline from evidence accumulation to trust-policy adjustment. The result is that trust can never grow: the cost of operating Hassease never decreases as the system proves itself, and the builder's attention is permanently allocated at the same rate regardless of demonstrated reliability.

**Recommendation:**
Add an `EvidenceAccumulator` in `internal/evidence/` that tracks per-model, per-file-class approval outcomes across sessions. Expose a `TrustRecommendation` output that the operator can review periodically and apply to the trust policy config — not automatic trust elevation (that would be a Skaffen capability, not a Hassease one), but a human-ratified ratchet. The distinction is important: the caravan master reviews the merchant's record and decides to extend more autonomy; the merchant does not self-promote. Hassease's trust ratchet should require explicit operator action to apply, making the evidence-to-trust pipeline transparent and auditable.
