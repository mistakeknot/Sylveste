---
artifact_type: review-synthesis
method: flux-review
target: "docs/brainstorms/2026-04-06-hassease-multi-model-forge-agent.md"
target_description: "Hassease — multi-model code execution daemon (Go, Signal-native, cost-routed)"
tracks: 4
track_a_agents: [fd-go-daemon-lifecycle, fd-multi-model-cost-router, fd-signal-messaging-transport, fd-tool-execution-sandboxing, fd-agent-loop-orchestration]
track_b_agents: [fd-airline-yield-management-routing, fd-industrial-control-plc-approval, fd-satellite-ground-station-command, fd-pharmaceutical-cmo-outsourcing]
track_c_agents: [fd-majlis-petition-routing, fd-venetian-glassblower-heat-tiering, fd-kamal-celestial-navigation-waypoint, fd-tang-courier-relay-failover]
track_d_agents: [fd-polynesian-wayfinding-star-compass-routing, fd-cham-po-nagar-temple-intermediary-petition, fd-sogdian-caravan-relay-trust-delegation]
date: 2026-04-06
total_findings: 68
p0_count: 11
p1_count: 31
p2_count: 24
---

# Cross-Track Synthesis — Hassease Multi-Model Forge Agent

68 findings across 16 agents in 4 tracks. 11 P0, 31 P1, 24 P2.

## Cross-Track Convergence

### Convergence 1: Skaffen trust import inherits autonomous authority (4/4 tracks)

Every track independently identified that importing Skaffen's `internal/trust/` package leaks autonomous-approval defaults into a human-directed daemon.

- **Track A** (fd-tool-execution-sandboxing): Skaffen's `rules.go` auto-approves read, write, and edit — silently removes Hassease's human oversight gate
- **Track B** (fd-pharmaceutical-cmo-outsourcing): Auto-approve rules uniform across providers despite different quality track records
- **Track C** (fd-tang-courier-relay-failover): "Shared horse pools don't share trade agreements" — importing packages doesn't mean importing trust policy
- **Track D** (fd-sogdian-caravan-relay-trust-delegation): "Borrowing a warehouse does not mean borrowing trade agreements" — `NewEvaluator()` must take explicit policy with no defaults

**Convergence score: 4/4.** This is the #1 architectural decision. Hassease MUST NOT use Skaffen's trust evaluator with default configuration. Solution: `NewEvaluator(policy TrustPolicy)` requires explicit policy argument; Hassease's policy lives in `cmd/hassease/`, not inherited from Skaffen.

### Convergence 2: No mid-execution model escalation (4/4 tracks)

The brainstorm routes by task complexity at intake but provides no mechanism to escalate mid-execution when complexity reveals itself.

- **Track A** (fd-multi-model-cost-router): Compound failure cost — cheap model fails, retry fails, then escalate, but total cost exceeds routing to Claude upfront
- **Track B** (fd-airline-yield-management-routing): "Spoilage" — locking a booking class at reservation time ignores real-time demand shifts
- **Track C** (fd-venetian-glassblower-heat-tiering): Under-tiering produces shattering not degradation — a complex edit on GLM doesn't degrade gracefully, it breaks
- **Track D** (fd-polynesian-wayfinding-star-compass-routing): Star arc rotation — the star you navigate by at dusk has set by midnight; `SelectModel()` must be per-turn, not per-task

**Convergence score: 4/4.** The cost router must re-evaluate at OODARC phase boundaries, not just at task intake. Escalation triggers: tool call failure, low-confidence output, file count exceeding threshold, cross-module dependency detected.

### Convergence 3: Approval message fidelity — diff first, not summary (3/4 tracks)

The approval flow sends a model-generated description of intent. The executed action may differ.

- **Track A** (fd-signal-messaging-transport): Approval must bind to specific tool calls, not conversational turns
- **Track B** (fd-industrial-control-plc-approval): Proposed-action hash must be recorded alongside approval response — any divergence between approved and executed action is detectable
- **Track D** (fd-cham-po-nagar-temple-intermediary-petition): "The halau jia translates between vernacular and ritual register" — if the translation (summary) is unfaithful, the petitioner (human) approves something other than what executes. Lead with compact diff, trail with summary.

**Convergence score: 3/4.** Every approval request must include: (1) compact diff or tool call parameters, (2) action hash, (3) optional model-generated summary. Approval binds to the hash, not the summary. Post-execution, verify executed action matches approved hash.

### Convergence 4: Human unavailability has no defined behavior (3/4 tracks)

What happens when the builder doesn't respond to an approval request?

- **Track B** (fd-industrial-control-plc-approval): No response timeout — daemon blocks indefinitely
- **Track C** (fd-majlis-petition-routing): No explicit "closed court" mode — silence produces undefined behavior
- **Track D** (fd-cham-po-nagar-temple-intermediary-petition): "Closed-temple queue" — park pending approvals, surface as batch when builder returns

**Convergence score: 3/4.** Define three modes: (1) **block** — wait indefinitely (safe default), (2) **queue** — park approvals, resume when builder returns, (3) **timeout** — abort after N minutes, revert partial work. Silence MUST NOT default to approval (Track A P0).

### Convergence 5: Provider identity missing from evidence records (3/4 tracks)

Which model produced which output? Without this, cost analysis, quality attribution, and regression investigation are impossible.

- **Track B** (fd-pharmaceutical-cmo-outsourcing): Provider identity not guaranteed in every JSONL evidence record
- **Track C** (fd-tang-courier-relay-failover): JSONL from Hassease and Skaffen indistinguishable without `daemon_id` discriminator
- **Track D** (fd-polynesian-wayfinding-star-compass-routing): No course memory on model escalation — Claude doesn't know what GLM already tried

**Convergence score: 3/4.** Every JSONL evidence record must include: `provider_id` (glm-5.1, qwen-3.6, claude-sonnet-4.6, etc.), `daemon_id` (hassease vs skaffen), `turn_number`, `escalated_from` (if this turn was an escalation). This is the PHILOSOPHY.md "every action produces evidence" principle applied to multi-model routing.

### Convergence 6: Path traversal in auto-approve rules (2/4 tracks)

- **Track A** (fd-tool-execution-sandboxing): `tests/../.env` bypasses test-file auto-approve rule
- **Track C** (fd-majlis-petition-routing): Consequence-based classification needed, not path-based — a test-file delete is higher-consequence than a test-file addition

**Convergence score: 2/4.** Auto-approve rules must: (1) canonicalize paths before matching, (2) classify by consequence (read/add/modify/delete) not just path, (3) never auto-approve deletions regardless of path.

## Critical Findings (P0)

| # | Finding | Tracks | Fix |
|---|---------|--------|-----|
| 1 | Skaffen trust import inherits autonomous authority | A,B,C,D | `NewEvaluator(policy)` with explicit policy, no defaults |
| 2 | No mid-execution model escalation | A,B,C,D | Per-turn `SelectModel()` at OODARC phase boundaries |
| 3 | Approval timeout undefined (silence ≠ approval) | A,C,D | Default to block; configurable timeout with revert |
| 4 | Path traversal in auto-approve (`tests/../.env`) | A,C | Canonicalize paths, classify by consequence |
| 5 | No graceful shutdown (SIGTERM kills mid-approval) | A | SIGTERM handler: checkpoint JSONL, notify builder, clean exit |
| 6 | Approval binds to summary not diff | B,D | Lead with diff + action hash; verify post-execution |
| 7 | Semantically wrong edits pass format-level validation | C | Post-edit validation (compile/test check) on auto-approved paths |

## Synthesis Assessment

**Overall quality:** The brainstorm makes the right architectural call (new pillar, Go, imports Skaffen packages, Signal-native). The model routing strategy and tool approval concept are sound. But the brainstorm treats the trust boundary, approval protocol, and mid-execution escalation as implementation details when they are actually **architectural decisions** that must be resolved before the first line of code.

**Highest-leverage improvement:** Define the trust boundary between Skaffen and Hassease as a `pkg/trust/` extracted package with no defaults. This single decision resolves the #1 convergent finding (4/4 tracks) and forces explicit policy at every call site.

**Surprising finding:** The Cham temple "translation fidelity" insight — that a model-generated approval summary may accurately describe intent while the executed action silently removes an existing guard. This is not a theoretical risk; it's a known LLM pattern (add requested feature + silently refactor surrounding code). Leading with diff instead of summary is the structural fix.

**Semantic distance value:** The outer tracks (C/D) contributed the most actionable design patterns. The "closed-temple queue" (unavailability handling), "star compass per-turn routing" (not per-task), "Sogdian warehouse ≠ trade agreement" (trust import boundary), and "halau jia translation fidelity" (diff-first approval) are all specific mechanisms that became concrete architectural requirements. The adjacent track (A) caught the most findings by volume, but the outer tracks shaped the design.
