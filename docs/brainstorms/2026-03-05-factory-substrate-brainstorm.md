# Factory Substrate Brainstorm

**Bead:** iv-ho3
**Date:** 2026-03-05
**Status:** Brainstorm
**Source:** Oracle GPT-5.2 Pro gap analysis of StrongDM Software Factory (factory.strongdm.ai)

---

## Problem Statement

The Oracle gap analysis (Feb 2026) identified 15 StrongDM techniques. Three were already adopted at design-doc stage (Pyramid Summaries, Gene Transfusion, Shift Work). Several more have since been partially addressed by shipped features (token budget controls, model routing, sprint checkpoints, cost estimation). The remaining gaps cluster around one theme: **Clavain has no validation architecture.**

Clavain can brainstorm, plan, build, review, and ship. But it cannot:
- Define what "correct" means as an externalized, replayable artifact (scenario bank)
- Score satisfaction over trajectories rather than pass/fail tests
- Record execution history as a structured DAG with content-addressed artifacts
- Convert obstacles into model-consumable evidence packs
- Enforce capability boundaries on agents during execution

Without these, the autonomy ladder stalls at L2 (React). L3 (Auto-remediate) requires the system to know when something went wrong — which requires validation infrastructure that doesn't exist yet.

## Key Decisions Made During Brainstorm

### 1. Clavain-native, not Autarch-backed

**Decision:** All factory substrate intelligence lives in Clavain (L2) and Interverse plugins. Autarch (L3) is a pure UI consumer.

**Rationale:** The Autarch vision doc already states this as the target: "Autarch apps are pure rendering surfaces. They read kernel state, submit intents to the OS, and display results. All agency logic lives in the OS layer." The philosophy's "independently valuable" principle means factory capabilities must work without a Go TUI binary. The "composition over capability" principle means capabilities belong in the plugin ecosystem, not the app layer.

The original epic description ("Autarch becomes the runtime backend for Clavain's StrongDM-inspired factory techniques") is superseded by this decision. The child beads that assumed Autarch ownership need re-scoping.

### 2. Adopt CXDB, don't build CXDB-lite

**Decision:** Adopt StrongDM's open-source CXDB (github.com/strongdm/cxdb) as required infrastructure, same tier as Dolt for beads.

**What CXDB provides:**
- **Turn DAG:** Immutable directed acyclic graph of conversation turns with parent references
- **Blob CAS:** Content-addressed storage using BLAKE3 hashing with Zstd compression
- **Type Registry:** Typed JSON envelopes enabling forward-compatible schema evolution
- **O(1) Forking:** `ForkContext(baseTurnID)` branches execution without copying data
- **Go client SDK:** 3 dependencies (uuid, msgpack, blake3), clean API, Go 1.22

**Architecture:**
- Rust server binary (`cxdb-server`) on ports 9009 (binary protocol) + 9010 (HTTP API)
- Go client SDK (`github.com/strongdm/ai-cxdb/clients/go`) integrates into clavain-cli
- Data dir at `.clavain/cxdb/`
- Service lifecycle: PID file + auto-start, same pattern as Dolt in `.beads/`
- Pre-built binary distribution (not compiled from source by users)

**Why required, not optional:**
- Philosophy says "durable over ephemeral" — execution history is not optional
- Graceful degradation doubles code paths and the fallback path rots
- Beads (Dolt) is already required infrastructure and the pattern works
- Interspect needs complete execution data — gaps break the learning loop
- "Independently valuable" applies to plugins, not infrastructure

**Why adopt, not build:**
- Philosophy says "adopt mature external tools as dependencies rather than rebuilding them — the same way bd (beads) works today"
- CXDB is Apache 2.0, actively maintained by StrongDM, 356 stars
- The Go SDK is minimal and maps directly to Clavain concepts
- Building CXDB-lite would reimplement Turn DAG + Blob CAS + Type Registry — exactly what the philosophy warns against

### 3. "No daemon" reframed

**Decision:** "No daemon, no server, no background process" is a kernel (Intercore) design property, not a system-wide principle.

**Evidence:** The constraint appears only in the Intercore vision doc and the Demarch vision's kernel paragraph. It is not in PHILOSOPHY.md. The system already runs servers: Dolt (port 3307), intermute (port 7338), intercomd (Rust daemon), Autarch APIs (ports 8090-8092), and every MCP server.

The actual principles are "durable over ephemeral" and "independently valuable" — which constrain *how* servers integrate (must be manageable, must degrade for plugins) but don't prohibit them for infrastructure.

### 4. Scenario bank is the keystone

**Decision:** Scenario bank + satisfaction scoring is the primary deliverable. Everything else enables or follows from it.

**Rationale:** The Oracle analysis rated this P0 and called it "arguably the missing keystone that makes non-interactive / no-human-review even remotely defensible." It's the only P0 gap that hasn't been partially addressed by shipped features. It directly enables:
- L3 autonomy (auto-remediate requires knowing what "correct" means)
- Interspect learning (satisfaction scores are the outcome data the profiler needs)
- CXDB value (scenario trajectories are the primary data stored in the Turn DAG)

## Architecture

### Clavain Concept to CXDB Mapping

| Clavain Concept | CXDB Primitive |
|---|---|
| Sprint run | Context |
| Phase transition | Turn (typed: `clavain.phase.v1`) |
| Agent dispatch + result | Turn (typed: `clavain.dispatch.v1`) |
| Artifact (plan, brainstorm, review) | Blob CAS (BLAKE3 deduped) |
| Sprint fork ("what if different plan?") | `ForkContext(baseTurnID)` — O(1) |
| Scenario run trajectory | Context with typed `clavain.scenario.v1` turns |
| Satisfaction score | Turn (typed: `clavain.satisfaction.v1`) |
| Interspect outcome query | Query turns by type, extract signals |

### Scenario Bank Design

**Filesystem layout:**
```
.clavain/scenarios/
  dev/                    # Visible to implementation agents
    login-happy-path.yaml
    payment-edge-cases.yaml
  holdout/                # Hidden from implementation, visible to validation
    regression-2026-03.yaml
    adversarial-inputs.yaml
  satisfaction/           # Scores, trajectory logs, judge rationales
    run-001.json
    run-002.json
```

**Scenario YAML schema:**
```yaml
id: scenario-001
intent: "User can complete checkout with a valid credit card"
setup:
  - "Application running with test database"
  - "User authenticated as test-buyer"
steps:
  - action: "Navigate to cart"
    expect: "Cart shows 2 items"
  - action: "Enter payment details"
    expect: "Payment form validates"
  - action: "Submit order"
    expect: "Confirmation page with order ID"
rubric:
  - criterion: "Order persisted in database"
    weight: 0.4
  - criterion: "Confirmation email queued"
    weight: 0.3
  - criterion: "Inventory decremented"
    weight: 0.3
risk_tags: [payment, data-integrity]
holdout: false
```

**Satisfaction scoring:**
- LLM-as-judge + deterministic rubric scoring
- Reuse existing flux-drive agents: `fd-user-product` (satisfaction judge), `fd-correctness` (technical oracle), `fd-safety` (risk gating)
- Output: `satisfaction.json` with per-criterion scores, overall score, trajectory reference, judge rationale
- Gate integration: sprint cannot advance to Ship unless holdout satisfaction >= threshold

**Holdout separation:**
- Implementation agents run in a context that does not include `.clavain/scenarios/holdout/`
- Validation agents run with full access
- Enforcement via clavain-cli policy (not filesystem permissions — agents can read anything)
- The policy is a clavain-cli `policy-check` command that gates tool dispatch

### CXDB Integration in clavain-cli

**New Go package:** `pkg/cxdb/` in clavain-cli (~300 lines estimated)

```go
// Core integration surface
func Connect() (*cxdb.Client, error)     // Dial localhost:9009
func SprintContext(beadID string) uint64  // Get or create context for sprint
func RecordPhase(ctx, phase, artifacts)   // Append clavain.phase.v1 turn
func RecordDispatch(ctx, agent, result)   // Append clavain.dispatch.v1 turn
func RecordScenario(ctx, scenario, score) // Append clavain.scenario.v1 turn
func ForkSprint(ctx, fromTurnID) uint64   // Fork execution trajectory
func QueryByType(ctx, typeID) []Turn      // Read turns for Interspect
```

**Service lifecycle** (in `.clavain/cxdb/`):
```
.clavain/cxdb/
  cxdb-server           # Pre-built binary
  cxdb.pid              # PID file
  cxdb.log              # Server log
  data/                 # CXDB data directory
```

Start/stop managed by `clavain-cli cxdb-start` / `clavain-cli cxdb-stop`, called from setup and session hooks.

### Evidence Pipeline

Wire existing plugins rather than build new:

| Source | Pipeline | Destination |
|---|---|---|
| Interspect profiler events | Tag + normalize | CXDB turns (`clavain.evidence.v1`) |
| Interject scan findings | Convert to scenario steps | `.clavain/scenarios/dev/` |
| Flux-drive review findings | Extract failing criteria | `.clavain/scenarios/holdout/` regression tests |
| Interstat token data | Attach to dispatch turns | CXDB blob CAS |
| Sprint failure trajectories | Auto-generate evidence pack | `.clavain/evidence/<case>/` |

### New clavain-cli Commands

```
Scenarios:
  scenario-create     <name> [--holdout]           Create scenario YAML scaffold
  scenario-run        <pattern> [--sprint=<id>]    Run matching scenarios
  scenario-score      <run-id>                     Score trajectories via LLM judges
  scenario-list       [--holdout] [--dev]           List scenarios

CXDB:
  cxdb-start                                       Start CXDB server
  cxdb-stop                                        Stop CXDB server
  cxdb-status                                      Health check
  cxdb-fork           <sprint-id> <turn-id>        Fork sprint execution

Policy:
  policy-check        <agent> <action>             Check agent capability policy
  policy-show                                      Display current policy
```

## Child Bead Re-scoping

The 9 existing child beads were created assuming Autarch ownership. Re-scope for Clavain-native:

| Bead | Original | Re-scoped | Action |
|---|---|---|---|
| **iv-c2r** Scenario bank + satisfaction scoring | Gurgeh/Coldwine | **Clavain-native** — filesystem + clavain-cli + flux-drive judges | Keep, re-scope |
| **iv-296** CXDB-lite: run DAG + blob CAS | Build in Autarch | **Adopt CXDB** — Go SDK integration in clavain-cli | Keep, re-title: "Integrate CXDB as required infrastructure" |
| **iv-wbh** Attractor-mode graph pipelines | Coldwine | **Defer** — linear sprint with CXDB forking is sufficient for now | Deprioritize to P4 |
| **iv-2li** DTU-lite behavioral mocks | Autarch | **Clavain skill** — `/dtu` workflow using existing test infrastructure | Keep, re-scope |
| **iv-3ov** Evidence pack pipeline | Pollard | **Wire existing plugins** — interspect + interject + interstat → CXDB | Keep, re-scope |
| **iv-b46** Agent provenance + capability policies | Bigend/Coldwine | **Clavain-native** — `.clavain/policy.yml` + clavain-cli policy-check | Keep, re-scope |
| **iv-1hu** Expand autarch-mcp with factory tools | Autarch MCP | **Defer** — Autarch consumes clavain-cli, doesn't own tools | Deprioritize to P4 |
| **iv-d32** Semantic porting (Coldwine) | Coldwine | **Defer** — entirely new domain, not needed for validation | Keep at P4 |
| **iv-txw** Cross-session token economics | Bigend | **Already shipped** — interstat + cost-query.sh + fleet-registry | Close |

## Implementation Priority

**Phase 1: CXDB adoption** (iv-296 re-scoped)
- Ship pre-built CXDB binary in setup flow
- Add Go SDK to clavain-cli
- Implement service lifecycle (start/stop/status)
- Wire phase transitions and dispatch recording
- This unblocks everything else — all other features write to CXDB

**Phase 2: Scenario bank** (iv-c2r re-scoped)
- Scenario YAML schema + filesystem conventions
- `scenario-create` / `scenario-list` commands
- Satisfaction scoring using flux-drive agents
- Holdout separation via policy-check
- Gate integration: satisfaction threshold for Ship

**Phase 3: Evidence pipeline** (iv-3ov re-scoped)
- Wire interspect + interject + interstat into CXDB turns
- Auto-generate scenarios from sprint failures
- Evidence pack standard (`.clavain/evidence/`)

**Phase 4: Agent policies** (iv-b46 re-scoped)
- `.clavain/policy.yml` schema
- `policy-check` command
- Holdout enforcement during implementation phases

## What This Enables

- **L3 autonomy:** System can auto-remediate because it has externalized correctness (scenario bank) and outcome data (CXDB)
- **Interspect learning:** Satisfaction scores + dispatch outcomes + forked trajectories provide the evidence the profiler needs
- **Sprint forking:** "What if we used a different plan?" becomes O(1) via CXDB ForkContext
- **Self-building validation:** Demarch's own scenarios become the holdout set for its own development
- **Replayability:** Any sprint is reconstructable from its CXDB context — the philosophy's "receipts, not narratives"

## Open Questions

1. **CXDB binary distribution:** Pre-built releases from StrongDM, or build our own from source and ship in setup? StrongDM doesn't publish release binaries yet (no GitHub releases). May need to build and cache.
2. **Type registry bootstrapping:** CXDB requires type bundles to be registered before turns can use typed projections. Ship a `clavain-types.json` bundle in setup? Or register lazily on first use?
3. **CXDB data lifecycle:** How long do we keep turn data? Per-sprint? Per-project? Interspect benefits from historical data, but storage grows. Add compaction/archival later.
4. **Scenario authoring UX:** Who writes scenarios — the human, the agent, or both? The brainstorm assumes agent-authored with human curation. May need a `/scenario:generate` that infers scenarios from existing tests + specs.
