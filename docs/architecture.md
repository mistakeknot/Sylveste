# Sylveste Architecture

> **Version:** 1.3 | **Last updated:** 2026-04-26

## Six Pillars

Sylveste is built from six pillars — major components that together form the platform:

| Pillar | Role |
|--------|------|
| **Intercore** | Orchestration kernel — the durable system of record |
| **Clavain** | Agent OS — workflow policy and the reference agency |
| **Skaffen** | Sovereign agent runtime — provider/tool loop and standalone execution |
| **Interverse** | Companion plugins, each independently valuable. Count plugin manifests with `find interverse -maxdepth 3 -path '*/.claude-plugin/plugin.json' \| wc -l` |
| **Autarch** | Application layer — TUI surfaces for kernel state |
| **Interspect** | Adaptive profiler — the learning loop |

Pillars describe *what* makes up Sylveste. The three-layer model below describes *how* they relate.

## The Three-Layer Model

```
                        ┌──────────────────────────────┐
                        │         L3: Apps             │
                        │   Autarch (TUI dashboards)   │
                        │   Bigend, Pollard, future    │
                        │                              │
                        │   Reads kernel state (L1)    │
                        │   Sends intents to OS (L2)   │
                        └──────────┬───────────────────┘
                                   │ intents (start-run,
                                   │ advance-run, override-gate,
                                   │ submit-artifact)
                        ┌──────────▼───────────────────┐
                        │         L2: OS               │
                        │   Clavain (agent agency)     │
                        │   Skaffen (agent runtime)    │
                        │   + Drivers (plugins)        │
                        │                              │
                        │   Maps domain concepts to    │
                        │   kernel primitives          │
                        │   Dispatches + supervises    │
                        │   agent work                 │
                        └──────────┬───────────────────┘
                                   │ ic CLI calls
                                   │ (runs, gates, events,
                                   │  dispatches, state, locks)
                        ┌──────────▼───────────────────┐
                        │         L1: Kernel           │
                        │   Intercore (Go CLI+SQLite)  │
                        │                              │
                        │   Owns: runs, phases, gates, │
                        │   events, dispatches, state, │
                        │   locks, sentinels, artifacts │
                        │                              │
                        │   Single source of truth     │
                        └──────────────────────────────┘

              ╔══════════════════════════════════════════╗
              ║   Cross-cutting: Interspect (profiler)   ║
              ║   Today: OS-layer changes only.          ║
              ║   Kernel boundary softens with trust.    ║
              ╚══════════════════════════════════════════╝
```

## Layer Ownership

| Layer | Component | Owns | Communicates via |
|-------|-----------|------|------------------|
| L1 Kernel | Intercore | Runs, phases, gates, events, dispatches, state, locks, sentinels, artifacts | CLI (`ic`) commands, exit codes |
| L2 OS | Clavain + Skaffen + Drivers | Workflow semantics, sprint lifecycle, agent supervision, provider/tool runtime, brainstorm-to-ship pipeline | Calls L1 via `ic` CLI; consumes the generic bus plus typed evidence queries while the measurement read model is still converging |
| L3 Apps | Autarch (TUIs) | User-facing dashboards, visualizations | Reads L1 state via `ic` queries; sends intents to L2 |
| Cross-cutting | Interspect | Observability, profiling, pattern detection | Consumes L1 event surfaces; today this includes `ic events tail`, `ic events list-review`, and `ic interspect query` rather than one fully unified stream. Writes only to L2 (OS config). Kernel boundary softens as trust is earned. |

## Write-Path Contract

All durable state flows through the kernel (L1). Higher layers do not write to the kernel's database directly.

Current-state note: the generic event bus is not yet the full measurement-grade read model. Review payload fidelity, Interspect evidence, and the durable session/bead/run join still require additional surfaces beyond `ic events tail`. See [docs/research/interspect-event-validity-and-outcome-attribution.md](./research/interspect-event-validity-and-outcome-attribution.md).

```
  L3 ──intent──▶ L2 ──ic CLI──▶ L1 (SQLite)
                                    │
  Interspect ◀──events──────────────┘ (read-only)
```

**Enforcement roadmap:**
- **v1 (current):** Convention — callers use `ic` commands by agreement.
- **v1.5:** Namespace validation — `ic` validates key prefixes match declared namespaces.
- **v2:** `--caller` flag — audit trail records which component wrote each entry.
- **v3:** Capability tokens (Gridfire) — callers present unforgeable tokens scoped to specific operations, with effects allowlists and resource bounds. See PHILOSOPHY.md § Earned Authority, Security.

## Inter-Layer Communication

| Direction | Mechanism | Example |
|-----------|-----------|---------|
| L2 → L1 | `ic` CLI calls | `ic run advance <id>`, `ic gate check <id>` |
| L1 → L2 | Event bus + typed evidence queries (pull) | `ic events tail <run> --consumer=hook-name`, `ic events list-review`, `ic interspect query` |
| L3 → L2 | Intent protocol | `start-run`, `advance-run`, `override-gate`, `submit-artifact` |
| L3 → L1 | Read-only queries | `ic run status <id> --json`, `ic state get ...` |
| * → Interspect | Event consumption | Interspect consumes kernel event surfaces; today this is not one fully unified stream |

## Drivers (L2 Extensions)

Drivers are Claude Code plugins that extend the OS layer. They are not a separate architectural layer.

**Core drivers:** interflux (multi-agent review), interpath (artifact generation), interwatch (doc freshness), interlock (multi-agent coordination), interspect (profiling), intercore (kernel CLI).

See [CLAUDE.md](../CLAUDE.md) for the full module list.

## Sprint Lifecycle

The OS (L2) configures a 10-phase sprint lifecycle across 5 macro-stages:

```
Discover          Design              Build          Ship         Reflect
─────────── ──────────────────── ────────────── ──────────── ────────────
brainstorm → brainstorm-reviewed → planned      → executing → shipping → reflect → done
             strategized           plan-reviewed                          │
                                                                    gate: artifact
                                                                    required
```

The kernel (L1) walks the phase chain, evaluates gates, and records events. The OS defines which phases exist and what they mean. Custom chains are supported for non-sprint workflows.

## Key Invariants

1. **Single-machine through v2.** Local POSIX filesystem, single PID namespace, local SQLite.
2. **No secrets in the kernel.** State validation rejects API keys, tokens, JWTs, PEM keys.
3. **CLI is the contract.** No Go library API in v1. External consumers use `ic` commands.
4. **Events are additive-only.** New event types may be added; existing types never removed without a major version bump.
5. **Single operator.** The threat model assumes a single trusted operator through v2.

## References

- [Intercore Vision](core/intercore/docs/product/intercore-vision.md) — kernel design and roadmap
- [Clavain Vision](os/Clavain/docs/clavain-vision.md) — OS layer design and workflow
- [Autarch Vision](apps/Autarch/docs/autarch-vision.md) — apps layer and TUI strategy
- [Sylveste Vision](sylveste-vision.md) — project overview and adoption ladder
- [Compatibility Contract](core/intercore/COMPATIBILITY.md) — stability guarantees for external consumers
