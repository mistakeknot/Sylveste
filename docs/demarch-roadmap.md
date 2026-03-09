# Demarch Roadmap

**Modules:** 61 | **Open beads:** 647 | **In progress:** 2 | **Blocked:** 44 | **Closed:** 2,476 | **Last updated:** 2026-03-08
**Structure:** [`CLAUDE.md`](../CLAUDE.md)
**Machine output:** [`docs/roadmap.json`](roadmap.json) — auto-generated superset with all roadmap-placed items. This markdown is the curated view. Counts above are from `bd stats` (all beads); roadmap.json counts are roadmap-placed items only and may differ.

---

## Ecosystem Snapshot

| Module | Location | Version | Status | Roadmap | Open Beads (context) |
|--------|----------|---------|--------|---------|----------------------|
| agent-rig | core/agent-rig | 0.1.0 | early | no | n/a |
| autarch | apps/autarch | 0.1.0 | active | yes | n/a |
| clavain | os/clavain | 0.6.155 | active | yes | n/a |
| interband | core/interband | — | planned | no | n/a |
| interbench | core/interbench | — | planned | no | n/a |
| intercache | interverse/intercache | 0.2.0 | early | no | n/a |
| interchart | interverse/interchart | 0.1.8 | early | no | n/a |
| intercheck | interverse/intercheck | 0.2.0 | active | yes | 4 |
| intercom | apps/intercom | 1.1.0 | active | yes | n/a |
| intercore | core/intercore | — | active | yes | n/a |
| intercraft | interverse/intercraft | 0.1.2 | active | yes | 4 |
| interdeep | interverse/interdeep | 0.1.6 | early | no | n/a |
| interdev | interverse/interdev | 0.2.0 | active | yes | 4 |
| interdoc | interverse/interdoc | 5.1.2 | active | yes | 4 |
| interfluence | interverse/interfluence | 0.2.8 | active | yes | 4 |
| interflux | interverse/interflux | 0.2.36 | active | yes | n/a |
| interform | interverse/interform | 0.1.0 | active | yes | 4 |
| interject | interverse/interject | 0.1.9 | active | yes | 4 |
| interkasten | interverse/interkasten | 0.4.9 | early | no | n/a |
| interknow | interverse/interknow | 0.1.2 | early | no | n/a |
| interlearn | interverse/interlearn | 0.1.0 | active | yes | 8 |
| interleave | interverse/interleave | 0.1.1 | early | no | n/a |
| interlens | interverse/interlens | 2.2.4 | active | yes | 4 |
| interline | interverse/interline | 0.2.11 | active | yes | 4 |
| interlock | interverse/interlock | 0.2.7 | active | yes | n/a |
| intermap | interverse/intermap | 0.1.5 | active | yes | 7 |
| intermem | interverse/intermem | 0.2.3 | active | yes | n/a |
| intermonk | interverse/intermonk | 0.1.1 | early | no | n/a |
| intermute | core/intermute | — | active | yes | n/a |
| intermux | interverse/intermux | 0.1.2 | active | yes | 4 |
| intername | interverse/intername | 0.1.1 | early | no | n/a |
| internext | interverse/internext | 0.1.4 | active | yes | 4 |
| interpath | interverse/interpath | 0.3.0 | active | yes | 4 |
| interpeer | interverse/interpeer | 0.1.0 | early | no | n/a |
| interphase | interverse/interphase | 0.3.13 | active | yes | 4 |
| interplug | interverse/interplug | 0.1.0 | early | no | n/a |
| interpub | interverse/interpub | 0.1.7 | active | yes | 4 |
| interpulse | interverse/interpulse | 0.1.3 | early | no | n/a |
| interrank | interverse/interrank | 0.1.0 | early | no | n/a |
| interscribe | interverse/interscribe | 0.1.1 | early | no | n/a |
| intersearch | interverse/intersearch | 0.2.0 | active | yes | 4 |
| intersense | interverse/intersense | 0.1.0 | early | no | n/a |
| interserve | interverse/interserve | 0.1.5 | active | yes | 4 |
| intership | interverse/intership | 0.3.0 | early | no | n/a |
| intersight | interverse/intersight | 0.1.3 | early | no | n/a |
| interskill | interverse/interskill | 0.1.1 | early | no | n/a |
| interslack | interverse/interslack | 0.1.0 | active | yes | 4 |
| interspect | interverse/interspect | 0.1.6 | early | [vision](./interspect-vision.md) | n/a |
| interstat | interverse/interstat | 0.2.15 | active | yes | 4 |
| intersynth | interverse/intersynth | 0.1.6 | early | no | n/a |
| intertest | interverse/intertest | 0.1.2 | early | no | n/a |
| intertrace | interverse/intertrace | 0.1.2 | early | no | n/a |
| intertrack | interverse/intertrack | 0.1.0 | active | yes | n/a |
| intertree | interverse/intertree | 0.1.0 | early | no | n/a |
| intertrust | interverse/intertrust | 0.1.2 | early | no | n/a |
| interverse | root | — | active | yes | n/a |
| interwatch | interverse/interwatch | 0.2.0 | active | yes | 5 |
| marketplace | core/marketplace | — | active | yes | n/a |
| tldr-swinton | interverse/tldr-swinton | 0.7.17 | active | yes | n/a |
| tool-time | interverse/tool-time | 0.3.5 | active | yes | n/a |
| tuivision | interverse/tuivision | 0.1.6 | active | yes | 4 |

**Legend:** active = recent commits or active tracker items; early = manifest exists but roadmap maturity is limited. `n/a` means there is no module-local `.beads` database.

---

## Roadmap

### Now — Frontier Priorities

**P0: Intercom cutover** (iv-awny7, epic, 6 open subtasks). The only P0 epic. Rust/Postgres control-plane migration is partially complete; Node/SQLite remain authoritative for group state, task mutation, and command handling.

**P1: Infrastructure + bugs.**
- **iv-ho3** StrongDM Factory Substrate — validation-first infra for Clavain. In progress. Blocks iv-296 → iv-g36hy → iv-3ov (the measurement chain).
- **iv-v5ayb** go.mod replace directive breaks interlock/intermap in plugin cache. Quick fix: publish interbase/go as Go module.
- **iv-28vf9** Compaction recovery protocol for SessionStart hook.
- **iv-83du3** Intercom message delivery reliability (outbox + LISTEN/NOTIFY + UDS).
- **iv-6376** Kernel E9: Autarch Phase 2 — Pollard + Gurgeh migration.

**P1: Measurement hardening chain.** The path to making the north-star metric canonical:
- iv-ho3 (in progress) → iv-296 (CXDB integration) → iv-g36hy (sprint execution recording) → iv-3ov (evidence pipeline wiring)

**P2: Adaptive routing (the flywheel).**
- **iv-5ztam** Interspect adaptive routing epic — evidence-driven agent selection. 10+ subtasks including counterfactual shadow evaluation, rate limiter, meta-learning loop.
- **iv-jgdct** Apply complexity-aware routing across all subagents.

**Recently completed (since last update):**
- Track C (C1-C5) — ALL SHIPPED. Agency specs (iv-asfy), fleet registry (iv-lx00), composer (iv-240m), cross-phase handoff (iv-1vny), self-building loop (iv-6ixw).
- iv-wie5i / iv-zsio — Discovery OS integration / discovery pipeline (consolidated, closed)
- iv-w7bh — Intermap: Project-Level Code Mapping (shipped)
- iv-t712t — First-stranger experience (README, install, setup)
- iv-r6mf — Interspect routing overrides F1-F5
- iv-b46xi — North star baseline ($1.17/landable change)

### Detailed Now Inventory

Open P0-P1 items. Closed items moved to "Recently completed" above.

- [intercom] **iv-awny7** Finish Rust/Postgres control-plane cutover (6 open subtasks) — **P0, epic**
  - iv-awny7.1: Make group registration state single-writer — **P0** (blocks .3, .5)
  - iv-awny7.2: Make scheduled task state single-writer — **P0** (blocks .5)
  - iv-awny7.3: Remove legacy SQLite from Rust Telegram bridge — **P0** (blocked by .1)
  - iv-awny7.4: Unify chat command handling on one command plane — **P0** (blocks .5)
  - iv-awny7.5: Remove Node orchestration scaffolding — **P0** (blocked by .1-.4)
  - iv-awny7.6: Canonicalize architecture docs — **P0**
- [clavain] **iv-ho3** StrongDM Factory Substrate — **P0, in progress** (blocks iv-296, iv-g36hy, iv-3ov, and 7 more)
- [clavain] **iv-296** F1: Integrate CXDB as required infrastructure — **P1** (blocked by iv-ho3)
- [clavain] **iv-g36hy** Sprint execution recording in CXDB — **P1** (blocked by iv-296, iv-ho3)
- [intercom] **iv-83du3** Message delivery reliability: outbox + LISTEN/NOTIFY + UDS — **P1, epic**
- [intercore] **iv-6376** E9: Autarch Phase 2 — Pollard + Gurgeh migration — **P1, epic**
- [interverse] **iv-v5ayb** go.mod replace directive breaks in plugin cache — **P1, bug**
- [clavain] **iv-28vf9** Compaction recovery protocol for SessionStart hook — **P1**

### Next — Strategic Themes (P2)

**4 themes defining the medium-term direction.** Track C (Agency Architecture) has shipped entirely (C1-C5). Full item inventory: [backlog.md](backlog.md).

1. **Adaptive Routing (Track B3)** — Evidence-driven agent selection, canary monitoring, counterfactual shadow evaluation. The learning loop that makes the system cheaper and better over time. The primary strategic frontier now that Tracks A and C are complete.
   - Key items: iv-5ztam (evidence-driven selection epic), iv-435u (counterfactual shadow eval), iv-003t (global rate limiter), iv-rafa (meta-learning loop)
   - Key item (fd routing): iv-jgdct (apply complexity-aware routing across all subagents)

2. **Measurement Hardening** — Make the north-star metric canonical. The measurement chain (iv-ho3 → iv-296 → iv-g36hy → iv-3ov) unblocks the evidence pipeline that adaptive routing needs. Without measurement, the flywheel thesis is aspirational.
   - Key items: iv-mi8e0 (metrics plugin), iv-3ov (evidence pipeline wiring)

3. **Multi-Runtime Dispatch** — Multi-agent coordination patterns, Hermes pattern adoption. Multiple runtimes working together reliably.
   - Key items: iv-fwwhl (WCM coordination epic), iv-a0q2r (Hermes compression chain)

4. **Developer Experience & Tooling** — Intermap code mapping, interlock coordination, Autarch TUI migration, plugin ecosystem maturity. What makes the platform usable for others.
   - Key items: iv-6376 (E9 Autarch Phase 2), iv-v5ayb (go.mod bug)

### Later — Horizon (P3)

Longer-term directions, not yet scoped into specific items. Full inventory: [backlog.md](backlog.md).

- **Kernel library bindings** — Native client bindings for intercore (blocked by intent router)
- **Continuous dispatch** — Daemon mode for always-on agent orchestration
- **Workspace isolation** — Git worktree per task for parallel safe execution
- **Runtime budget enforcement** — Real-time token budget checks mid-execution
- **Intercom maturity** — Dual-persistence retirement, memory layers, self-review loops
- **Evaluation infrastructure** — Model-capability sensitivity benchmarks, verifier context patterns

---

## Module Highlights

### intercheck (interverse/intercheck)
Intercheck is the quality and session-health layer for Claude Code and Codex operations, focused on preventing unsafe edits before damage occurs.

### intercraft (interverse/intercraft)
Intercraft captures architecture guidance and auditable agent-native design patterns for complex agent behavior.

### interdev (interverse/interdev)
Interdev provides MCP and CLI-oriented developer workflows for discoverability, command execution, and environment tooling.

### interdoc (interverse/interdoc)
Interdoc synchronizes AGENTS.md/CLAUDE.md governance and enables recursive documentation maintenance with review tooling.

### interfluence (interverse/interfluence)
Interfluence provides voice and style adaptation by profile, giving outputs that fit project conventions.

### interform (interverse/interform)
Interform raises visual and interaction quality for user-facing artifacts and interface workflows.

### interject (interverse/interject)
Interject provides ambient discovery and research execution services for agent workflows.

### interlearn (interverse/interlearn)
Interlearn indexes cross-repo solution documents and provides search and audit capabilities for institutional knowledge reuse.

### interlens (interverse/interlens)
Interlens is the cognitive-lens platform for structured reasoning and belief synthesis.

### interline (interverse/interline)
Interline provides session state visibility with statusline signals for multi-agent and phase-aware workflows.

### intermap (interverse/intermap)
Project-level code mapping via 9 MCP tools: registry, call graphs, impact analysis, cross-project deps, architecture detection, live changes, and agent overlay.

### intermux (interverse/intermux)
Intermux surfaces active agent sessions and task progress to support coordination and observability.

### internext (interverse/internext)
Internext prioritizes work proposals and tradeoffs with explicit value-risk scoring.

### interpath (interverse/interpath)
Interpath generates artifacts across roadmap, PRD, vision, changelog, and status from repository intelligence.

### interphase (interverse/interphase)
Interphase manages phase tracking, gate enforcement, and work discovery within Clavain and bead-based workflows.

### interpub (interverse/interpub)
Interpub provides safe version bumping, publishing, and release workflows for plugins and companion modules.

### intersearch (interverse/intersearch)
Intersearch underpins semantic search and Exa-backed discovery shared across Interverse modules.

### interserve (interverse/interserve)
Interserve supports Codex-side classification and context compression for dispatch efficiency.

### interslack (interverse/interslack)
InterSlack connects workflow events to team communication channels with actionable context.

### interstat (interverse/interstat)
Interstat measures token consumption, workflow efficiency, and decision cost across agent sessions.

### interwatch (interverse/interwatch)
Interwatch monitors documentation freshness — auto-discovers watchable docs by convention, detects drift via 14 signal types, scores confidence, and dispatches to generators for refresh.

### tuivision (interverse/tuivision)
Tuivision automates TUI and terminal UI testing through scriptable sessions and screenshot workflows.

---

## Research Agenda

- **Sprint resilience and agent coordination** — Multi-phase work on sprint handover, agent claiming protocols, shift-work boundary formalization, and cross-phase handoff to make long-running autonomous work survive session boundaries.
- **Token and cost optimization** — Token-efficient skill loading, budget controls, cost-aware agent scheduling, cost reconciliation, and accuracy gap measurement to reduce per-change cost and improve output quality.
- **Clavain kernel evolution** — Go migration of clavain-cli, kernel schema validation, native kernel coordination, hierarchical dispatch meta-agent, adaptive routing (b3), composer (c3), self-building loop (c5), and unified routing engine.
- **Intercore event pipeline** — Hook cutover (e3), discovery pipeline (e5), portfolio orchestration (e8), rollback recovery, fair spawn scheduler, sandbox specs, and Go wrapper for Autarch integration.
- **Observability and tracing** — Unified structured logging, MCP instrumentation middleware, intertrace cross-module integration tracer, tool selection failure instrumentation, and fleet registry enrichment for operational visibility.
- **Review and safety systems** — Interspect approve/propose flows, pattern detection, routing overrides, disagreement pipeline, agent trust scoring, safety floors, and Go redaction library for secure multi-agent review.
- **Plugin ecosystem maturity** — Dual-mode plugin architecture, publishing validation pipeline overhaul, plugin synergy catalog, data-driven plugin boundaries, modpack auto-install, and interverse plugin decomposition.
- **Code intelligence and mapping** — Intermap project-level code mapping, Python sidecar, live changes hardening, TLDRs import graph compression (dedup, longcodezip, precomputed context bundles, symbol popularity index), and intercache.
- **Knowledge and learning loops** — Reflect-phase learning loop, knowledge distillation pipeline, review quality feedback loop, intermonk dialectic reasoning, interdeep deep research, and role-aware latent memory experiments.
- **Multi-agent collaboration** — Interlock window identity, intermute contact policies and broadcast/topic messages, adopt mcp-agent-mail patterns, heterogeneous collaboration routing, and "when Claudes meet" interaction patterns.
- **SDK and cross-language support** — Interbase multi-language SDK, Go module path alignment, interbump transactional safety, and gemini CLI integration adapter for broader agent and language coverage.
- **Developer experience and onboarding** — First-stranger experience, project onboard skill, Autarch status tool, bigend migration (dirty row tracking, inline log pane), session start drift summary injection, and search surface documentation.
- **Document and artifact pipelines** — Flux-drive document slicing and intermediate findings, interscribe doc quality and extraction, CUJs as first-class artifacts, intent contracts, blueprint distillation sprint intake, and factory substrate for reproducible builds.
- **Application layer (Intercom and Intersight)** — Intercom H2 last-mile delivery, outbox listen-notify, interfin design, intersight UI design analysis, and interchart ecosystem diagrams.
- **Operational workflows** — Backlog hygiene gate, thematic work lanes, oodarc shared observation loops, Pollard hunter progressive reveal, catalog reminder escalation, and intent submission mechanism for structured planning.

---

## Cross-Module Dependencies

Major dependency chains spanning multiple modules:

- **iv-5ztam** (interverse) blocked by **iv-003t** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-0fi2** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-2o6c** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-435u** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-5su3** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-6liz** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-88yg** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-8fgu** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-bj0w** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-c2b4** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-drgo** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-g0to** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-gkj9** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-izth** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-m6cd** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-rafa** (interspect)
- **iv-5ztam** (interverse) blocked by **iv-t1m4** (interspect)
- **iv-mi8e0** (interverse) blocked by **iv-74moz** (intertrack)
- **iv-mi8e0** (interverse) blocked by **iv-f462h** (intertrack)
- **iv-mi8e0** (interverse) blocked by **iv-hqdvn** (intertrack)
- **iv-mi8e0** (interverse) blocked by **iv-yhjy4** (intertrack)
- **iv-mi8e0** (interverse) blocked by **iv-z90qq** (intertrack)
- **iv-5ubkh** (fd) blocked by **iv-5ztam** (interverse)
- **iv-3r6q** (interflux) blocked by **iv-r6mf** (interspect)

---

## Modules Without Roadmaps

26 modules lack dedicated roadmap files. Most are peripheral ("early" status). Flywheel-critical modules have alternative coverage noted.

**Flywheel-critical (have alternative coverage):**
- `interverse/interspect` — has [vision doc](interspect-vision.md) and [interspect product PRD](../core/intercore/docs/product/interspect-prd.md). Roadmap items tracked via beads (iv-sksfx chain, iv-f7gsz, iv-w3ee6).

**Peripheral (early status, no roadmap needed yet):**
- `core/agent-rig`, `core/interband`, `core/interbench`
- `interverse/intercache`, `interverse/interchart`, `interverse/interdeep`
- `interverse/interkasten`, `interverse/interknow`, `interverse/interleave`
- `interverse/intermonk`, `interverse/intername`, `interverse/interpeer`
- `interverse/interplug`, `interverse/interpulse`, `interverse/interrank`
- `interverse/interscribe`, `interverse/intersense`, `interverse/intership`
- `interverse/intersight`, `interverse/interskill`, `interverse/intersynth`
- `interverse/intertest`, `interverse/intertrace`, `interverse/intertree`
- `interverse/intertrust`

---

## Keeping Current

```
# Regenerate this roadmap JSON from current repo state
scripts/sync-roadmap-json.sh docs/roadmap.json

# Regenerate via interpath command flow (Claude Code)
/interpath:roadmap    (from Interverse root)

# Propagate items to subrepo roadmaps
/interpath:propagate  (from Interverse root)
```
