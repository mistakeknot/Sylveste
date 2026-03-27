# fd-dependency-risk: Factory Substrate PRD Review

**PRD:** `docs/prds/2026-03-05-factory-substrate.md`
**Brainstorm:** `docs/brainstorms/2026-03-05-factory-substrate-brainstorm.md`
**Reviewer:** fd-dependency-risk
**Date:** 2026-03-05

---

## Finding 1: CXDB Has No Release Artifacts — Binary Distribution Is Unresolved

**Priority:** P0

**Finding:** The PRD lists CXDB as "same tier as Dolt for beads" required infrastructure, but CXDB has no GitHub releases, no pre-built binaries, and no version pinning mechanism. The PRD acknowledges this in Open Question #1 ("StrongDM doesn't publish release binaries yet") and the Dependencies section ("Need to build from source (Rust toolchain) and cache the binary, or request releases from StrongDM"), but ships the feature with this unresolved.

Dolt, by contrast, has 600+ releases, a Homebrew formula, deb/rpm packages, and a documented install path. Putting CXDB at the same infrastructure tier with zero distribution infrastructure is not a maturity parity — it is a tier mismatch.

**Failure scenario:** Every developer and agent environment must compile Rust from source to get `cxdb-server`. Rust compilation requires 2-4 GB of toolchain, takes 5-15 minutes on a cold build, and fails unpredictably on CI runners with constrained memory. A contributor who wants to run Clavain sprints must first install `rustup`, `cargo`, and successfully compile a Rust binary they have no expertise in debugging. Agent environments (which are ephemeral) face this on every fresh provision.

**Evidence:**
- PRD F1 acceptance criteria: "Pre-built `cxdb-server` binary distributed via Clavain setup flow" (line 23)
- PRD Dependencies: "StrongDM doesn't publish GitHub releases yet" (line 106)
- PRD Open Question #1 (line 113)
- Brainstorm architecture section: "Pre-built binary distribution (not compiled from source by users)" (line 49)

The brainstorm states the intent is pre-built binaries but the PRD does not include a concrete plan for producing, hosting, versioning, or updating them.

**Recommendation:** Before shipping, resolve binary distribution concretely. Options ranked by effort:
1. **Minimum viable:** Pin a specific CXDB commit hash. Add a `scripts/build-cxdb.sh` that builds from source and caches the binary at `.clavain/cxdb/cxdb-server`. Document the Rust toolchain requirement. This is honest about the cost.
2. **Better:** Contribute a GitHub Actions release workflow to `strongdm/cxdb`. Get pre-built binaries for linux-amd64/arm64 and darwin-amd64/arm64. Pin the release tag in `clavain setup`.
3. **Best:** Negotiate with StrongDM to publish releases. Consume their artifacts.

Do not merge the PRD with "pre-built binary" as an acceptance criterion while the actual plan is "build from source and cache" — that hides the Rust toolchain requirement from the acceptance criteria reader.

---

## Finding 2: No Graceful Degradation Is a Blast Radius Decision, Not an Architecture One

**Priority:** P1

**Finding:** The brainstorm explicitly rejects graceful degradation: "Graceful degradation doubles code paths and the fallback path rots" (line 53). The argument cites the Dolt precedent. However, the analogy is imprecise.

When Dolt is unavailable, `bd` commands fail but the sprint itself can proceed — agents can still write code, run tests, and produce artifacts. Beads track work items; they are not in the critical path of code execution. CXDB as designed sits in the critical path of sprint phase transitions (`sprint-advance` writes a phase turn to CXDB, per F2 line 39) and agent dispatch recording (`sprint-track-agent` / `sprint-complete-agent` write dispatch turns, per F2 lines 40-41).

If CXDB is unavailable and there is no degradation, then:
- `sprint-advance` fails, blocking all phase transitions
- Agent dispatch tracking fails, breaking sprint orchestration
- The entire sprint pipeline halts on an infrastructure dependency

This is a categorically different blast radius than "bead tracking is unavailable."

**Failure scenario:** CXDB process crashes (OOM, disk full, bug). No sprint can advance. All agents in all concurrent sprints are blocked. Recovery requires manual `cxdb-start` and potentially data directory repair. During the outage window, developer/agent work is completely blocked rather than just untracked.

**Evidence:**
- PRD F2 acceptance criteria: "sprint-advance writes a phase turn to CXDB context" (line 39)
- PRD F2: "sprint-track-agent / sprint-complete-agent write dispatch turns" (lines 40-41)
- Brainstorm: "Graceful degradation doubles code paths and the fallback path rots" (line 53)
- Brainstorm: "Beads (Dolt) is already required infrastructure and the pattern works" (line 54)

**Recommendation:** Distinguish between "required for correctness" and "required for liveness." CXDB writes should be fire-and-forget with local buffering:
- Phase transitions and dispatch recording should attempt CXDB writes but not block on them.
- Buffer failed writes to a local append-only log (`.clavain/cxdb/pending.jsonl`).
- On CXDB recovery, replay the buffer.
- Scenario scoring and gate enforcement (F4) can legitimately hard-require CXDB — those are correctness checks, not liveness.

This is not "graceful degradation with two code paths." It is write-ahead logging — a single code path with a buffer. The CXDB write is always attempted; the buffer is the recovery mechanism.

---

## Finding 3: No Version Pinning Strategy Creates Silent Breakage Risk

**Priority:** P1

**Finding:** The PRD specifies the CXDB Go SDK (`github.com/strongdm/ai-cxdb/clients/go`) as a dependency but does not specify a version pin, compatibility contract, or upgrade policy. With 72 commits and no releases, CXDB's API surface may change without semantic versioning guarantees.

The Go SDK adds 3 new dependencies (uuid, msgpack, blake3) per PRD line 107, but there is no plan for what happens when CXDB makes a breaking change to its binary protocol (port 9009) or HTTP API (port 9010).

**Failure scenario:** A `go get -u` or transitive dependency update pulls a CXDB SDK version that speaks protocol v2 against a cached `cxdb-server` binary that speaks protocol v1. Sprint recording silently fails or panics. Diagnosing the version mismatch requires understanding CXDB internals that no Sylveste contributor has.

**Evidence:**
- PRD F2: "Go SDK (`github.com/strongdm/ai-cxdb/clients/go`) added to clavain-cli `go.mod`" (line 36)
- PRD Dependencies: "CXDB Go SDK adds 3 new dependencies" (line 107)
- No mention of version pinning, compatibility testing, or upgrade procedures anywhere in the PRD or brainstorm.

**Recommendation:**
- Pin the Go SDK to a specific commit hash in `go.mod` (since there are no releases to pin to).
- Pin the `cxdb-server` binary to the same commit hash.
- Add a version compatibility check: `cxdb-status` should verify client SDK version matches server version and fail loudly on mismatch.
- Document the upgrade procedure: build new binary, update SDK pin, test, deploy together.

---

## Finding 4: The "Why Not Existing Tools" Argument Has Gaps

**Priority:** P2

**Finding:** The brainstorm's argument for CXDB over existing tools (section "Why adopt, not build," line 58-62) makes the case against *building* a CXDB-lite. It does not make the case against *using existing infrastructure* (Dolt + filesystem).

The PRD's core CXDB primitives map to existing tools:

| CXDB Primitive | Existing Tool Equivalent |
|---|---|
| Turn DAG | Dolt table with parent_id column (Dolt already provides branching, diffing, versioning) |
| Blob CAS | Filesystem with BLAKE3 naming (or Dolt blob columns) |
| Type Registry | JSON schema validation (already used for scenario YAML) |
| O(1) Forking | `dolt branch` (already O(1) via structural sharing) |

The brainstorm states "Building CXDB-lite would reimplement Turn DAG + Blob CAS + Type Registry" (line 62), but the question is not whether to reimplement — it is whether Dolt (which already provides DAG, CAS-like content addressing, branching, and SQL queries) plus filesystem conventions are sufficient at current scale.

The PRD does not cite a specific limitation of Dolt that CXDB resolves. It does not estimate data volumes or query patterns that would exceed what Dolt + SQLite can handle.

**Evidence:**
- Brainstorm lines 58-62: argument is against building, not against using existing tools
- Brainstorm line 54: "Beads (Dolt) is already required infrastructure" — yet no analysis of extending Dolt
- Dolt already runs on port 3307 (`.beads/metadata.json`), already provides branching/forking, already stores structured data
- No performance benchmarks, data volume estimates, or query pattern analysis in either document

**Recommendation:** Add a "Why not extend Dolt?" section to the PRD that addresses:
1. Specific Dolt limitations that make it unsuitable for turn-level recording (latency? schema rigidity? query patterns?)
2. Expected data volumes (turns per sprint, sprints per day, retention period)
3. Whether the CXDB binary protocol offers meaningful performance advantages over Dolt SQL for the actual query patterns needed

If the answer is "CXDB's Turn DAG is a better conceptual fit," that is a valid argument but should be stated honestly as a modeling preference, not an infrastructure necessity.

---

## Finding 5: Resource Overhead Is Unquantified

**Priority:** P2

**Finding:** The PRD adds a Rust server process (`cxdb-server`) to an environment that already runs:
- Dolt SQL server (port 3307)
- intermute (port 7338)
- intercomd (Rust daemon)
- Multiple MCP servers (one per active plugin)
- Claude Code itself

The brainstorm specifies two ports: 9009 (binary protocol) and 9010 (HTTP API). Neither document estimates memory footprint, CPU usage, or disk growth rate for CXDB.

**Failure scenario:** On resource-constrained environments (CI runners, small dev VMs, agent ephemeral containers), CXDB competes with Dolt and Claude Code for memory. CXDB's Rust binary with Zstd compression may have a non-trivial baseline memory footprint. Combined with Dolt's typical 200-400 MB RSS, the environment may exceed available memory, causing OOM kills that are difficult to diagnose.

**Evidence:**
- Brainstorm architecture: ports 9009 + 9010 (line 45)
- No memory/CPU estimates in either document
- Existing server inventory: Dolt, intermute, intercomd, MCP servers, Autarch APIs (brainstorm line 68)

**Recommendation:**
- Benchmark CXDB server baseline RSS (idle) and under load (1000 turns/context).
- Document the expected total memory footprint of all required services.
- Define a minimum environment specification (RAM, disk) for Clavain with CXDB.
- Consider: can CXDB use an embedded mode or shared-process model instead of a separate server? This would eliminate one process and two ports.

---

## Finding 6: Lock-in Risk Is Moderate but Manageable

**Priority:** P2

**Finding:** The `pkg/cxdb/` Go package (brainstorm line 151-162) defines 7 functions that wrap CXDB operations. This is a thin abstraction layer, which is good — it means migration would require rewriting ~300 lines (per brainstorm estimate) rather than scattered CXDB calls throughout the codebase.

However, the PRD defines 7 CXDB-specific type bundles (`clavain.phase.v1`, `clavain.dispatch.v1`, `clavain.artifact.v1`, `clavain.scenario.v1`, `clavain.satisfaction.v1`, `clavain.evidence.v1`, `clavain.policy_violation.v1`) that encode CXDB's type registry semantics. If CXDB is abandoned, these types need re-homing.

The broader concern: at 72 commits and 356 stars, CXDB could plausibly be abandoned within 12-18 months. StrongDM may pivot, deprioritize open-source, or the project may not find sufficient community adoption.

**Evidence:**
- Brainstorm lines 151-162: `pkg/cxdb/` abstraction (~300 lines)
- PRD F2: 7 type bundles defined (lines 38, 39, 40, 41, 54, 76, 94)
- CXDB stats: 72 commits, 356 stars, no releases, last activity Feb 2026

**Recommendation:**
- The `pkg/cxdb/` abstraction is sufficient for migration — keep it.
- Define the type bundles as Clavain-owned schemas that happen to be stored in CXDB, not as CXDB-native types. This means the schemas are documented independently of CXDB.
- Add a "Migration Plan" section to the PRD: if CXDB is abandoned, the fallback is SQLite + filesystem CAS implementing the same `pkg/cxdb/` interface. Estimate the migration effort (likely 1-2 weeks given the thin abstraction).

---

## Finding 7: Cross-Platform Support Is Unaddressed

**Priority:** P2

**Finding:** The PRD's F1 acceptance criteria specify a pre-built `cxdb-server` binary but do not mention which platforms must be supported. Sylveste developers work on macOS (Apple Silicon and Intel) and Linux (amd64). CI runs on Linux. Agent environments may vary.

Rust cross-compilation is straightforward for linux targets but macOS requires either native compilation or `cross-rs` with SDK licensing considerations.

**Evidence:**
- PRD F1: "Pre-built `cxdb-server` binary distributed via Clavain setup flow" (line 23)
- No platform matrix specified in PRD or brainstorm
- Dolt precedent: supports darwin-amd64, darwin-arm64, linux-amd64 via official releases

**Recommendation:** Specify the platform matrix in F1 acceptance criteria: at minimum linux-amd64 and darwin-arm64. Add platform detection to `clavain setup` that downloads the correct binary.

---

## Summary Verdict: NEEDS_REWORK

The PRD makes a reasonable case for *why* execution history and scenario validation are needed (the "validation architecture gap" is real). The choice of CXDB as the implementation vehicle has significant unresolved risks:

1. **P0: No binary distribution path.** The PRD cannot ship "pre-built binary" as an acceptance criterion while the actual plan is "compile from Rust source." This blocks adoption for any contributor without a Rust toolchain.

2. **P1: Hard-fail on CXDB unavailability** puts a 72-commit dependency in the critical path of all sprint operations. This is a categorically different blast radius than the Dolt precedent cited to justify it.

3. **P1: No version pinning** for a pre-1.0 dependency with no releases creates silent breakage risk.

4. **P2: The "why not Dolt/SQLite" argument** is made against building a custom tool, not against extending existing infrastructure. The gap in reasoning should be filled.

**Minimum changes to reach SHIP_WITH_FIXES:**
- Resolve binary distribution concretely (Finding 1) — even if the answer is "Rust toolchain required," say so in the acceptance criteria.
- Add write-ahead buffering so CXDB unavailability does not block sprint liveness (Finding 2).
- Pin CXDB SDK and binary to a specific commit hash with a version compatibility check (Finding 3).
- Add a "Why not extend Dolt?" section with concrete limitations cited (Finding 4).
