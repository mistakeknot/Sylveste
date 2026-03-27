# Intent Contract: Apps -> OS -> Kernel

**Bead:** iv-ojik9
**Date:** 2026-03-05
**Complexity:** 5/5 (research)

## Problem

Autarch and Intercom submit policy-governing mutations to Clavain (L2 OS), which delegates durable state to Intercore (L1 kernel). But the boundaries are blurry: some agency logic lives in apps, some kernel calls bypass the OS layer, and there's no typed intent protocol. This makes app surfaces hard to swap and policy hard to enforce consistently.

## Current Reality

### L3: Autarch (Go CLI agent)
- **Pattern:** OS-first, kernel-fallback. Calls `clavain.SprintCreate()`, `clavain.SprintAdvance()`, `clavain.EnforceGate()` via `pkg/clavain/`. Falls back to direct Intercore calls when Clavain unavailable.
- **State reads:** Directly from Intercore (`ic state get`, `ic run show`).
- **Packages:** `pkg/clavain/` (OS client), `pkg/intercore/` (kernel client), `pkg/contract/types.go` (proto-contract types).
- **Issues:** Fallback path means policy can be bypassed when Clavain is down. No idempotency on sprint mutations. `types.go` is a local definition, not shared.

### L3: Intercom (Telegram/web agent)
- **Three intent pathways:**
  1. **File-based IPC** from containers via `/workspace/ipc/queries/` — polling-based, no typed schema.
  2. **SylvesteAdapter** wrapping `clavain-cli` for read/write operations — shell exec, string parsing.
  3. **Telegram callback** flow for approvals — inline keyboard → handler → shell exec.
- **Issues:** Query handler has agency logic that belongs in OS (deciding what to execute). No typed intent protocol — everything is string commands. Group management split between Node SQLite and Rust Postgres.

### L2: Clavain (OS)
- **80+ clavain-cli commands** across 12 groups. Slash commands as primary API surface (`/route`, `/sprint`, `/work`).
- **8 active hooks** mediating app-to-OS boundary.
- **Policy lives here:** model routing, agent selection, budget enforcement, quality gates.
- **Delegates state** to Intercore via `ic state set/get`.
- **Issue:** CLI-only API surface. Apps must shell out and parse stdout. No structured request/response protocol.

### L1: Intercore (Kernel)
- **CLI-only interface** (no Go library API). 15+ command families.
- **Owns durable state:** runs, phases, dispatches, gates, events, budgets, sentinels, coordination locks. SQLite WAL database.
- **Gate system** is the only kernel-level policy mechanism.
- **Separate from beads** (linked via one-way label `ic_run_id`).
- **Issue:** No library bindings — every caller pays shell-exec overhead and string-parsing tax.

## Canonical Intents

Based on current usage patterns, these are the policy-governing mutations that apps submit:

### Sprint Lifecycle
| Intent | Current Path | Owner Should Be |
|--------|-------------|-----------------|
| `sprint.create` | Autarch → `clavain-cli sprint-create` | OS (Clavain) |
| `sprint.advance` | Autarch → `clavain-cli sprint-advance` | OS (Clavain) |
| `sprint.claim` | Autarch → `bd update --claim` + `bd set-state` | OS (Clavain) |
| `sprint.release` | Autarch → `bd set-state claimed_by=released` | OS (Clavain) |

### Gate & Policy
| Intent | Current Path | Owner Should Be |
|--------|-------------|-----------------|
| `gate.enforce` | Autarch → `clavain-cli enforce-gate` | OS → Kernel |
| `gate.skip` | Direct `CLAVAIN_SKIP_GATE` env var | OS (Clavain, with audit) |
| `budget.check` | Autarch → `clavain-cli sprint-budget-remaining` | OS → Kernel |
| `model.route` | Hook → `lib-routing.sh` | OS (Clavain) |

### Agent Dispatch
| Intent | Current Path | Owner Should Be |
|--------|-------------|-----------------|
| `agent.dispatch` | Clavain hooks → Task tool / Codex | OS (Clavain) |
| `agent.approve` | Intercom Telegram callback → shell exec | OS (Clavain, with app as UI) |
| `agent.cancel` | Direct `ic run cancel` | OS → Kernel |

### State Queries (reads, not intents — but contract-relevant)
| Query | Current Path | Should Be |
|-------|-------------|-----------|
| `sprint.status` | Direct `ic state get` / `bd show` | OS (Clavain) |
| `run.show` | Direct `ic run show` | Kernel (Intercore) |
| `bead.show` | Direct `bd show` | Separate (Beads) |

## Design Principles

### 1. OS Mediates All Policy Writes
Apps MUST submit policy-governing mutations through Clavain. Direct kernel calls for state changes bypass policy enforcement (budget limits, gate checks, model routing). Reads can go direct to kernel for performance.

**Rule:** If it changes behavior (creates a sprint, advances a phase, dispatches an agent, enforces a gate), it goes through OS. If it reads state, apps can call kernel directly.

### 2. Intents Are Typed, Not String Commands
Current: `clavain-cli sprint-advance "$bead_id" "$phase"` → stdout string parsing.
Target: Typed intent structs with defined fields, validation, and error codes.

### 3. Idempotency Keys
Sprint mutations are not idempotent today. `sprint-advance` called twice with the same phase silently succeeds. Intent contract should require idempotency keys so retries are safe and duplicate submissions are detected.

**Shape:** `{intent: "sprint.advance", bead_id: "iv-xxx", phase: "executing", idempotency_key: "session-abc-step-5", timestamp: 1772749697}`

### 4. Sync for Policy, Async for Dispatch
- **Synchronous:** Gate enforcement, budget checks, phase advances (caller needs immediate yes/no).
- **Asynchronous:** Agent dispatch, quality-gate reviews, Codex delegation (fire-and-observe).

### 5. Error Handling: Structured Codes, Not Exit Codes
Current: exit code 0/1 + stderr string matching ("already claimed", "gate blocked").
Target: Structured error responses with typed error codes that apps can switch on.

```
{error: "GATE_BLOCKED", detail: "plan must be reviewed first", gate: "executing", remediation: "Run /interflux:flux-drive on the plan"}
{error: "CLAIM_CONFLICT", detail: "bead held by session abc123", holder: "abc123", claimed_at: 1772749697}
{error: "BUDGET_EXCEEDED", detail: "150k of 100k budget used", spent: 150000, budget: 100000}
```

### 6. App Surfaces Are Swappable
The intent contract is the stable interface. Autarch (Go CLI), Intercom (Telegram), a future web UI, or a direct MCP client should all submit the same typed intents through the same OS entry point.

## Payload Shape (Draft)

```typescript
interface Intent {
  type: string;           // "sprint.create", "gate.enforce", etc.
  bead_id?: string;       // Target bead (most intents need this)
  idempotency_key: string; // Caller-generated, unique per logical operation
  session_id: string;     // Calling session for audit trail
  timestamp: number;      // Unix epoch seconds
  params: Record<string, unknown>; // Intent-specific parameters
}

interface IntentResult {
  ok: boolean;
  intent_type: string;
  bead_id?: string;
  data?: Record<string, unknown>;  // Intent-specific return data
  error?: {
    code: string;          // Machine-readable: GATE_BLOCKED, CLAIM_CONFLICT, etc.
    detail: string;        // Human-readable explanation
    remediation?: string;  // Suggested fix
  };
}
```

## Approval Semantics

Some intents require human approval before execution:

| Intent | Approval Required | Current Mechanism |
|--------|------------------|-------------------|
| `sprint.create` | No (agent-initiated) | None |
| `gate.skip` | Yes | `CLAVAIN_SKIP_GATE` env var with reason |
| `agent.approve` | Yes | Telegram inline keyboard callback |
| `budget.override` | Yes | Manual override in sprint prompt |

**Proposed model:** Intents that require approval get a `pending` status. The OS holds them until an approval signal arrives (from any app surface). This decouples the approval UI from the intent submission.

```
App submits: {type: "gate.skip", ..., requires_approval: true}
OS responds: {ok: true, status: "pending", approval_id: "apr-xxx"}
App (any surface) submits: {type: "approval.grant", approval_id: "apr-xxx", approver: "mk"}
OS executes the held intent
```

## Sync vs Async Behavior

| Category | Behavior | Reason |
|----------|----------|--------|
| **Policy checks** (gate.enforce, budget.check) | Sync | Caller blocks on result |
| **State mutations** (sprint.advance, sprint.claim) | Sync | Caller needs confirmation |
| **Agent dispatch** (agent.dispatch, quality-gates) | Async | Long-running, fire-and-observe |
| **Approvals** (gate.skip, agent.approve) | Async | Waits for human input |
| **Reads** (sprint.status, run.show) | Sync | Data retrieval |

## Migration Map

### Phase 1: Define Types (No Runtime Change)
1. Create `core/intercore/pkg/contract/` with shared Go types for intents and results.
2. Move Autarch's `pkg/contract/types.go` to the shared location.
3. Define intent type constants and error codes.
4. **No behavioral change** — just shared type definitions.

### Phase 2: OS Intent Router
1. Add `clavain-cli intent submit --type=<type> --params=<json>` command.
2. Intent router in Clavain validates, enforces policy, delegates to kernel.
3. Returns structured JSON instead of string output.
4. **Existing CLI commands continue to work** — intent submit is a new parallel path.

### Phase 3: Autarch Migration
1. Replace `pkg/clavain/` shell-exec calls with intent submissions.
2. Remove kernel-fallback path (if OS is down, fail explicitly).
3. Parse structured responses instead of stdout strings.
4. **Incremental** — one intent type at a time, starting with sprint.advance.

### Phase 4: Intercom Migration
1. Replace SylvesteAdapter shell-exec with intent submissions.
2. Move query-handler agency logic into Clavain (OS decides what to execute, not the app).
3. Telegram callbacks submit approval intents instead of direct shell commands.
4. **Biggest lift** — Intercom has the most scattered intent paths.

### Phase 5: Kernel Library Bindings
1. Create Go library API for Intercore (`core/intercore/pkg/client/`).
2. Clavain calls library directly instead of shelling out to `ic`.
3. Eliminates shell-exec overhead for the hottest path (OS → Kernel).
4. **Optional optimization** — the CLI path works, this just removes overhead.

## Open Questions

1. **Transport:** Is CLI + JSON sufficient, or do we need a proper RPC/socket protocol? CLI works for current scale but adds ~50ms per call from fork/exec overhead.
2. **Beads integration:** Beads (Dolt-backed) is separate from Intercore (SQLite-backed). Should intents that touch both (e.g., sprint.create creates a bead AND an ic run) be a single transaction or eventual consistency?
3. **Versioning:** How do we version the intent contract? Semver on the type definitions? Breaking changes require migration?
4. **Observability:** Should every intent be logged to Intercore events for audit trail? (Currently only some mutations are tracked.)
5. **MCP as transport:** Clavain already has an MCP server. Could intents be MCP tool calls, giving any MCP client (Claude, Codex, future agents) native access to the intent contract?

## Key Insight

The three-layer architecture is sound — the problem isn't the layers, it's the interfaces between them. Current interfaces are **stringly-typed CLI calls with exit-code error handling**. The intent contract formalizes what's already happening implicitly: apps submit policy-governing mutations, OS enforces policy and routes, kernel persists state. Making this explicit with typed intents, structured errors, and idempotency keys makes the boundaries enforceable rather than advisory.
