# Sylveste Backlog — Detailed Inventory

**Companion to:** [sylveste-roadmap.md](sylveste-roadmap.md) (strategic roadmap)
**Last synced:** 2026-03-13

This file contains the full P2/P3 item inventory. The root roadmap shows strategic themes; this file has every tracked item. Generated from beads state — regenerate with `scripts/sync-roadmap-json.sh`.

---

## P2 — Next

### Intent Architecture & OS Routing
- [intercore] **iv-mlca1** F1: Shared intent types (core/intercore/pkg/contract/)
- [clavain] **iv-6ocmi** F2: OS intent router (clavain-cli intent submit)
- [autarch] **iv-4ggh8** F3: Autarch intent migration
- [intercom] **iv-g6wtc** F4: Intercom intent migration
- [clavain] **iv-lx00** C2: Agent fleet registry — capability + cost profiles per agent×model
- [clavain] **iv-14g9** TOCTOU prevention: phased dispatch coordination

### Interspect Adaptive Routing
- [interspect] **iv-5ztam** Epic: Evidence-driven agent selection
- [interspect] **iv-8fgu** F2: Routing-eligible pattern detection + propose flow
- [interspect] **iv-gkj9** F3: Apply override + canary + git commit
- [interspect] **iv-2o6c** F4: Status display + revert for routing overrides
- [interspect] **iv-6liz** F5: Manual routing override support
- [interspect] **iv-drgo** Privilege separation (proposer/applier)
- [interspect] **iv-435u** Counterfactual shadow evaluation
- [interspect] **iv-003t** Global modification rate limiter
- [interspect] **iv-0fi2** Circuit breaker
- [interspect] **iv-rafa** Meta-learning loop
- [interspect] **iv-t1m4** Prompt tuning (Type 3) overlay-based
- [interspect] **iv-izth** Eval corpus construction
- [interspect] **iv-x6by** Research: Adaptive profiling and dynamic rule evolution

### Intercom Features & Messaging
- [intercom] **iv-romro/iv-0ewaq** Image/document understanding (multimodal input pipeline)
- [intercom] **iv-o6z3i/iv-sgrz8** Voice message support via Whisper transcription
- [intercom] **iv-7iy1i/iv-vorsr** Warm container pool for faster response latency
- [intercom] **iv-jw6nh/iv-kmn6b** Message delivery confirmation feedback
- [intercom] **iv-r3am8/iv-tpjhx** Conversation memory search (FTS5/semantic)
- [intercom] **iv-hkrlc/iv-3no5z** Typing indicator persists after send_message
- [intercom] **iv-elbnh** Session continuity across model switches
- [intercom] **iv-niu3a** Discovery triage via messaging
- [intercom] **iv-wjbex** Sprint status push notifications
- [intercom] **iv-902u6** Gate approval via Telegram
- [intercom] **iv-0am8w** SessionResetPolicy: idle timeout and daily reset per group
- [intercom] **iv-p3h62** Hermes-style pairing system to replace static allowlists
- [intercom] **iv-q0ddx** Decouple user identity from session: add user_peers table

### Multi-Agent Coordination & Hermes Patterns
- [wcm] **iv-fwwhl** Epic: WCM multi-agent coordination patterns
- [wcm] **iv-goiyq** Convergence-divergence detection with per-domain calibration
- [wcm] **iv-2n0ew** Idle-time micro-task dispatch with budget gate
- [wcm] **iv-ofgtl** Verifiable work commitment lifecycle with Goodhart resistance
- [wcm] **iv-6bwm7** Research: Measure agent idle time and coordination overhead
- [wcm] **iv-zfvdf** Define interface contract convention using run_artifacts
- [wcm] **iv-hvoyx** Wire intra-sprint bug reporting via review_events
- [hermes] **iv-a0q2r** Adapt parent_session_id compression chain
- [hermes] **iv-7h6tp** Adapt check_fn tool gating pattern
- [hermes] **iv-w1dcl** Adopt 40/60 head/tail output truncation
- [hermes] **iv-qyx8z** Adopt memory-flush-before-compress pattern
- [hermes] **iv-f8s9q** Port Anthropic prompt caching strategy

### Intermap, Interlock & Tool Infrastructure
- [intermap] **iv-dl72x** F1: Audit existing Intermap MCP tools
- [intermap] **iv-728k** F1: Go MCP scaffold + Python subprocess bridge
- [intermap] **iv-vwj3** F2: Extract Python modules from tldr-swinton
- [intermap] **iv-mif9** F3: Remove moved tools from tldr-swinton
- [intermap] **iv-h3jl** F4: Project registry + path resolver
- [intermap] **iv-3kz0v** F5: Write real Intermap vision and roadmap docs
- [intermap] **iv-80s4e** F6: Cross-project dependency graph MCP tool
- [intermap] **iv-dta9w** F7: Architecture pattern detection MCP tool
- [intermap] **iv-54iqe** F8: Live change awareness MCP tool
- [interlock] **iv-6u3s** F4: Sprint scan release visibility
- [interlock] **iv-gg8v** F2: Auto-release on clean files
- [tool-composition] **iv-w41fn** Expand sequencing hints from real failure data
- [tool-composition] **iv-qi80j** Audit real sessions for unhinted sequencing pipelines

### Metrics, Instrumentation & Flux-Drive
- [intertrack] **iv-mi8e0** Metrics instrumentation plugin
- [intertrack] **iv-hqdvn** Establish metrics artifact convention
- [intertrack] **iv-z90qq** F1: Interknow failure-signal metrics
- [intertrack] **iv-yhjy4** F2: Verify-fix token savings metrics
- [intertrack] **iv-74moz** F3: Findings-identity overlap metrics
- [intertrack] **iv-f462h** F4: Baseline rescaling discrimination metrics
- [interstat] **iv-v81k** Repository-aware benchmark expansion
- [interstat] **iv-0lt** Extract cache_hints metrics in score_tokens.py
- [interstat] **iv-1gb** Add cache-friendly format queries to regression_suite.json
- [flux-drive] **iv-ia66** Phase 2: Extract domain detection library
- [flux-drive] **iv-0etu** Phase 3: Extract scoring/synthesis Python library
- [flux-drive] **iv-e8dg** Phase 4: Migrate Clavain to consume the library
- [flux-drive] **iv-jgdct** Apply complexity-aware routing across all subagents
- [flux-drive] **iv-qjwz** AgentDropout: dynamic redundancy elimination
- [flux-drive] **iv-quk4** Hierarchical dispatch: meta-agent for N-agent fan-out

### Research & Assessments
- **iv-1d3v2** Research: Portfolio orchestration economics and dependent-project fan-out
- **iv-i76wv** Research: Autonomy safety policy for auto-remediate and auto-ship
- **iv-dtxkn** Research: Human attention budgets and review UX for multi-agent output
- **iv-lpfin** Research: Standalone degradation matrix for Interverse plugins
- **iv-sym01** Research: Symphony spec analysis — what to adopt
- **iv-sym02** External issue tracker adapter for beads (blocked by iv-sym01)
- **iv-sym03** Dispatch-level retry with exponential backoff (blocked by iv-sym01)
- **iv-zyw5** Research: Token efficiency and context hygiene
- **iv-1b3n** Research: Advanced multi-agent coordination
- **iv-wqk6** Research: The Discovery Pipeline (Level -1)
- **iv-q21d** Research: Fleet orchestration and portfolio management
- **iv-jk7q** Research: Cognitive load budgets and progressive disclosure review UX
- **iv-3kee** Research: Product-native agent orchestration (whitespace opportunity)
- **iv-exos** Research: Bias-aware product decision framework
- **iv-fzrn** Research: Multi-agent hallucination cascades and failure taxonomy
- [research] **iv-iry5n** gemini-api-updater-doc | **iv-m5zw2** cass_memory_system | **iv-vogko** franken_agent_detection | **iv-7v5ow** frankensearch | **iv-9erqx** llm_docs | **iv-ewjom** post_compact_reminder | **iv-ngiet** ultimate_bug_scanner | **iv-qi6k0** automated_plan_reviser_pro | **iv-9dxkz** llm_multi_round_coding_tournament | **iv-w14e1** ntm — integration/inspiration assessments

### Autarch, Bigend & Standalone Features
- [autarch] **iv-16z** Wire Coldwine and Pollard signal emitters
- [autarch] **iv-l8p** TUI Pollard scan integration
- [autarch] **iv-6iu** Integrate Epic/Task generation into unified onboarding flow
- [autarch] **iv-1pkt** Phase-based confirmation flow for broadcast actions
- [bigend] **iv-8nly** Virtualized lists with Fenwick tree
- [bigend] **iv-m33r** Budget degradation with PID controller
- [intermem] **iv-f7po** F3: Multi-file tiered promotion
- [intermem] **iv-bn4j** F4: One-shot tiered migration
- [intersight] **iv-rjgi9** Optimize Playwright MCP token efficiency
- [interflux] **iv-wz3j** Role-aware latent memory architecture experiments
- **iv-ho3** Epic: StrongDM Factory Substrate
- **iv-zyym** Evaluate Claude Hub for event-driven GitHub agent dispatch
- **iv-sdqv** Plan interscribe extraction (knowledge compounding)
- **iv-6ikc** Plan intershift extraction (cross-AI dispatch engine)
- **iv-fv1f** Implement multi-strategy context estimation

---

## P3 — Later

- [interverse] **iv-aac9z** F5: Kernel library bindings (intercore/pkg/client/) (blocked by iv-6ocmi)
- [interverse] **iv-sym04** Continuous dispatch daemon mode for Clavain (blocked by iv-sym01)
- [interverse] **iv-sym05** Workspace isolation via git worktree per task (blocked by iv-sym01)
- [interverse] **iv-sym06** Real-time token budget enforcement mid-execution (blocked by iv-sym01)
- [interverse] **iv-sym07** Harness engineering audit: repo health pre-routing gate (blocked by iv-sym01)
- [interverse] **iv-lthzo** Document cross-hook marker-file coordination pattern
- [intercom] **iv-m4y43** Deprecate dualWriteToPostgres fallback
- [intercom] **iv-st0dv** DSN stored indefinitely in PgPool memory
- [intercom] **iv-del8c** Quick reply templates (skip container)
- [intercom] **iv-niap5** Token budget tracking in chat
- [intercom] **iv-azezf** Agent-to-agent shared memory layer
- [intercom] **iv-29les** Self-improvement loop (scheduled self-review)
- [interverse] **iv-7c810** Repeat accuracy benchmark with Sonnet to test model-capability sensitivity
- [interverse] **iv-eu7ge** Self-improvement loop: scheduled self-review of Intercom codebase
- [interverse] **iv-kvu1u** Quick reply templates for common queries (skip container spin-up)
- [interverse] **iv-m3mu5** Token budget tracking and cost awareness in chat
- [interverse] **iv-yww42** Agent-to-agent shared memory layer
- [interverse] **iv-gx405** bd ready --verify: cross-check each result is still open before printing
- [interverse] **iv-sjz6t** Phase 3: Retire SQLite dual-persistence (blocked by iv-83du3, iv-nt43u)
- [interverse] **iv-pkv4y** Study VerifierContext pattern: reuse agent sandbox for reward verification

---

## Research Agenda

Thematic research directions spanning multiple modules. Each bullet may decompose into multiple beads.

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

Major dependency chains spanning multiple modules. Query live state with `bd blocked`.

- **iv-5ztam** (interverse) blocked by 17 interspect subtasks (iv-003t, iv-0fi2, iv-2o6c, iv-435u, iv-5su3, iv-6liz, iv-88yg, iv-8fgu, iv-bj0w, iv-c2b4, iv-drgo, iv-g0to, iv-gkj9, iv-izth, iv-m6cd, iv-rafa, iv-t1m4)
- **iv-mi8e0** (interverse) blocked by 5 intertrack subtasks (iv-74moz, iv-f462h, iv-hqdvn, iv-yhjy4, iv-z90qq)
- **iv-5ubkh** (fd) blocked by **iv-5ztam** (interverse)
- **iv-3r6q** (interflux) blocked by **iv-r6mf** (interspect)

---

## Modules Without Roadmaps

26 modules lack dedicated roadmap files. Most are peripheral ("early" status).

**Flywheel-critical (have alternative coverage):**
- `interverse/interspect` — has [vision doc](interspect-vision.md) and [interspect product PRD](../core/intercore/docs/product/interspect-prd.md). Roadmap items tracked via beads.

**Peripheral (early status, no roadmap needed yet):**
- `core/agent-rig`, `core/interband`, `core/interbench`
- `interverse/intercache`, `interverse/interchart`, `interverse/interdeep`
- `interverse/interkasten`, `interverse/interknow`, `interverse/interleave`
- `interverse/intermonk`, `interverse/intername`, `interverse/interpeer`
- `interverse/interplug`, `interverse/interpulse`, `interverse/interrank`
- `interverse/interscribe`, `interverse/intership`
- `interverse/intersight`, `interverse/interskill`, `interverse/intersynth`
- `interverse/intertest`, `interverse/intertrace`, `interverse/intertree`
- `interverse/intertrust`
