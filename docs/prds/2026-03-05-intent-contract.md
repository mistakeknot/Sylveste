---
artifact_type: prd
bead: iv-ojik9
stage: design
---
# PRD: Apps-OS-Kernel Intent Contract

## Problem

Apps (Autarch, Intercom) submit policy-governing mutations to Clavain via stringly-typed CLI calls with exit-code error handling. No typed protocol, no idempotency, no structured errors. Policy can be bypassed via direct kernel calls. App surfaces can't be swapped without reimplementing string parsing.

## Solution

Define a typed intent contract between layers: shared Go types for intents and results, an OS-level intent router that enforces policy before delegating to the kernel, and incremental migration of app callers from shell-exec to typed submissions.

## Features

### F1: Shared Intent Types
**What:** Create `core/intercore/pkg/contract/` with Go types for Intent, IntentResult, error codes, and intent type constants.
**Acceptance criteria:**
- [ ] `Intent` struct with type, bead_id, idempotency_key, session_id, timestamp, params fields
- [ ] `IntentResult` struct with ok, intent_type, bead_id, data, error fields
- [ ] Typed error codes: GATE_BLOCKED, CLAIM_CONFLICT, BUDGET_EXCEEDED, INVALID_INTENT, PHASE_CONFLICT
- [ ] Intent type constants for all 11 canonical intents (sprint.*, gate.*, budget.*, model.*, agent.*)
- [ ] Autarch's `pkg/contract/types.go` migrated to shared location with backward-compatible re-export
- [ ] Unit tests for intent validation (required fields, type format)

### F2: OS Intent Router
**What:** Add `clavain-cli intent submit` command that validates intents, enforces policy, delegates to kernel, and returns structured JSON.
**Acceptance criteria:**
- [ ] `clavain-cli intent submit --type=<type> --params=<json>` accepts and validates intent JSON
- [ ] Router enforces gate policy before executing gate-protected intents
- [ ] Router checks budget before executing budget-consuming intents
- [ ] Returns `IntentResult` JSON on stdout (both success and error cases)
- [ ] Existing CLI commands continue to work unchanged (parallel path)
- [ ] Idempotency key deduplication: same key within 5 minutes returns cached result
- [ ] Audit log: every intent submission recorded in Intercore events

### F3: Autarch Intent Migration
**What:** Replace Autarch's `pkg/clavain/` shell-exec calls with typed intent submissions via the shared contract.
**Acceptance criteria:**
- [ ] `sprint.advance` migrated first as proof of concept
- [ ] `sprint.create`, `sprint.claim`, `sprint.release` migrated
- [ ] `gate.enforce` migrated
- [ ] Kernel-fallback path removed (fail explicitly if OS unavailable)
- [ ] Structured error responses parsed instead of stdout strings
- [ ] All existing Autarch tests pass with new intent path

### F4: Intercom Intent Migration
**What:** Replace Intercom's DemarchAdapter shell-exec and file-based IPC with intent submissions. Move query-handler agency logic into Clavain.
**Acceptance criteria:**
- [ ] DemarchAdapter rewritten to submit intents instead of shelling out to `clavain-cli`
- [ ] Query handler agency logic moved to Clavain (OS decides what to execute)
- [ ] Telegram approval callbacks submit `approval.grant` intents
- [ ] File-based IPC queries migrated to intent submissions
- [ ] Approval hold-and-release pattern working (pending → approved → executed)

### F5: Kernel Library Bindings
**What:** Create Go library API for Intercore so Clavain can call kernel directly without shell-exec overhead.
**Acceptance criteria:**
- [ ] `core/intercore/pkg/client/` with Go client wrapping Intercore's SQLite operations
- [ ] Clavain intent router uses library client instead of `ic` CLI
- [ ] ~50ms latency reduction per intent (eliminates fork/exec)
- [ ] CLI `ic` commands continue to work (library is additive)
- [ ] Integration tests covering all intent types through library path

## Non-goals

- **RPC/socket protocol:** CLI + JSON is sufficient for current scale. Socket transport is a future optimization if latency becomes a problem.
- **Beads transactionality:** Intents touching both beads (Dolt) and Intercore (SQLite) use eventual consistency, not distributed transactions.
- **MCP intent transport:** Interesting future direction (Clavain MCP server already exists) but not this iteration.
- **Intent versioning scheme:** Define types first, version later when we have real breaking-change pressure.

## Dependencies

- `core/intercore/` — shared contract types live here
- `apps/autarch/` — consumer of intent contract (F3)
- `apps/intercom/` — consumer of intent contract (F4)
- `os/clavain/` — intent router lives here (F2)
- Intercore SQLite schema — may need events table extension for audit log

## Open Questions

1. **Idempotency storage:** Where does the dedup cache live? In-memory (lost on restart) or SQLite (durable but heavier)?
2. **Approval hold queue:** How long do pending approvals live before expiring? 1 hour? 24 hours?
3. **Intercom transport:** Intercom runs in containers — does it call `clavain-cli` directly or via a thin HTTP bridge?
