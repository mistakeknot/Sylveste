# Intent Contract Architecture

**Status:** Phase 1-2 implemented (shared types + OS router). Phase 3 (Autarch migration) has client methods ready. Phase 4 (Intercom) deferred — no current clavain integration exists.

## Layer Boundaries

```
┌─────────────┐   ┌─────────────┐
│   Autarch   │   │  Intercom   │   L3: App surfaces
│  (Go CLI)   │   │ (TS/Rust)   │   Submit typed intents
└──────┬──────┘   └──────┬──────┘
       │                 │
       │   Intent{type, bead_id, idempotency_key, ...}
       │                 │
┌──────▼─────────────────▼──────┐
│          Clavain (OS)          │   L2: Policy enforcement
│  clavain-cli intent submit     │   Validates, routes, audits
└──────────────┬─────────────────┘
               │
               │   Go library call (AddIntentEvent)
               │
┌──────────────▼─────────────────┐
│        Intercore (Kernel)       │   L1: Durable state
│    SQLite WAL, events, gates    │   Persists, queries
└────────────────────────────────┘
```

## Shared Types

Package: `core/intercore/pkg/contract/`

- `Intent` — typed mutation request with idempotency key
- `IntentResult` — structured response with machine-readable error codes
- `IntentError` — code + detail + remediation
- 11 intent types across sprint lifecycle, gates, budget, agent dispatch

## Error Codes

| Code | Meaning |
|------|---------|
| `GATE_BLOCKED` | Gate precondition not met |
| `CLAIM_CONFLICT` | Bead already claimed by another session |
| `BUDGET_EXCEEDED` | Token budget exhausted |
| `INVALID_INTENT` | Malformed or unknown intent type |
| `PHASE_CONFLICT` | Phase transition not allowed |
| `NOT_FOUND` | Bead or resource not found |
| `INTERNAL` | Unexpected error |

## Known Limitations

- **TOCTOU race:** Gate check and phase advance are not atomic — a concurrent session could modify state between the check and the write. This is a kernel-level limitation requiring CAS (compare-and-swap) support in Intercore. Documented in `docs/solutions/database-issues/toctou-gate-check-cas-dispatch-intercore-20260221.md`.

## Future Work

- **F4: Intercom migration** — Intercom currently has zero clavain integration. When it adds one, it should use typed intents from the start.
- **F5: Kernel library bindings** — Replace `ic` CLI shelling with `core/intercore/pkg/client/` Go library for ~50ms latency reduction per intent.
- **Idempotency dedup** — Cache intent results by idempotency key (in-memory or SQLite).
- **MCP transport** — Expose intents as MCP tool calls via Clavain's existing MCP server.
- **Atomic gate+advance** — Requires Intercore kernel CAS support (F5 prerequisite).
