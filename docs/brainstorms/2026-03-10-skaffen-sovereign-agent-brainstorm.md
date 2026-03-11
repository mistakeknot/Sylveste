---
artifact_type: brainstorm
stage: discover
status: superseded
superseded_by: docs/brainstorms/2026-03-11-skaffen-go-rewrite-brainstorm.md
---

# Skaffen — Demarch's Sovereign Agent Runtime

**Date:** 2026-03-10
**Status:** Brainstorming

## The Problem

Clavain is a rig — it enhances Claude Code, Codex, and Gemini with discipline (17 skills, 6 agents, 47 commands, 10 hooks). But it's fundamentally constrained by host runtime decisions:

1. **The agent loop is opaque.** Claude Code decides when to call tools, how to compact, when to steer. Clavain hooks *around* decisions but can't change *how* the loop works.
2. **Phase gates are bolted on.** Sprint phases (brainstorm → plan → build → review → ship) are enforced via skill injection and hook checks, not native loop structure.
3. **Mid-session model routing is host-dependent.** Demarch's routing philosophy (cheapest model that clears the bar) requires switching models mid-conversation. Host agents don't support this.
4. **Evidence collection is aftermarket.** Interspect scrapes evidence from hooks and logs. With our own loop, evidence emission is a first-class primitive.
5. **Steering is approximated.** Pi-mono's `steer()` (interrupt mid-tool) and `followUp()` (queue for after) are programmatic. Clavain can only approximate through hook injection.
6. **Extensions are config, not code.** Interverse plugins are config+hooks+skills. A sovereign agent could offer full programmatic control over tool execution, compaction, and context transformation.

The ceiling is real and blocking today. The answer isn't replacing Clavain — it's adding a second L2 OS that owns its own runtime.

## What Skaffen Is

**Skaffen** is Demarch's sovereign agent runtime — a standalone coding agent binary where OODARC, evidence pipelines, phase gates, and model routing are architectural primitives, not bolt-ons.

Named after Skaffen-Amtiskaw — the Culture drone that operates with full autonomy within its authority scope. Exactly the earned-authority model from PHILOSOPHY.md.

### Relationship to Existing Pillars

| Pillar | Role | Relationship to Skaffen |
|--------|------|------------------------|
| **Clavain** | Rig for existing agents (Claude Code, Codex, Gemini) | Sibling L2 OS. Clavain stays the rig; Skaffen is the sovereign runtime. Both share infrastructure. |
| **Intercore** | L1 kernel (dispatch, events, runs) | Skaffen integrates as a native Intercore consumer/producer |
| **Interverse** | Plugin ecosystem (53 plugins) | Skaffen can load Interverse plugins via bridge |
| **Autarch** | L3 apps (TUI dashboards, mission control) | Autarch can orchestrate Skaffen instances via RPC |
| **Interspect** | Evidence pipeline, routing | Skaffen emits evidence natively; Interspect routing overrides drive model selection |

### Non-Goals

- **Not replacing Clavain.** Clavain's 53-plugin ecosystem and host-agent integrations remain production-proven.
- **Not rebuilding the LLM abstraction.** Fork pi_agent_rust's provider layer (Anthropic, OpenAI, Gemini, Azure — covers 95%+ of use).
- **Not a general-purpose agent framework.** Skaffen is opinionated for software development, aligned with Demarch's OODARC philosophy.

## Fork Base: pi_agent_rust

Fork [Dicklesworthstone/pi_agent_rust](https://github.com/Dicklesworthstone/pi_agent_rust) as the foundation. Prior research (docs/research/research-pi-agent-rust-repo.md, 2026-02-19) already identified this repo as the best-in-class single-agent runtime for Autarch inspiration.

### Why pi_agent_rust over pi-mono (TypeScript)

| Factor | pi-mono (TS) | pi_agent_rust | Winner |
|--------|-------------|---------------|--------|
| Startup | 500ms+ (Node) | <100ms (single binary) | Rust |
| Memory (1M-token session) | 820MB | 67MB | Rust (12x) |
| Session load (5M tokens) | 6s | 1.4s | Rust (4x) |
| Extension safety | Unrestricted Node.js | Capability-gated QuickJS, trust lifecycle | Rust |
| Deployment | Node 20+ required | Single static binary | Rust |
| Unsafe code | N/A | `#![forbid(unsafe_code)]` | Rust |
| Concurrency | Promise chains | Structured concurrency, cancellation | Rust |
| Provider count | 23+ | ~10 (Anthropic, OpenAI, Gemini, Azure) | TS has more, Rust has enough |
| Language fit | Only TS in Demarch | Joins Go (clavain-cli) + Rust (cass) | Rust |
| Feature parity | Mature (v0.57, 14K stars) | v0.1.8, author-claimed parity (unaudited; Skaffen validates via v0.1 AC) | Trade-off |

### What We Keep from the Fork

- **pi-ai provider layer** — Anthropic, OpenAI, Gemini, Azure streaming + caching + OAuth
- **Agent loop skeleton** — Turn-based execution, tool dispatch, steering/follow-up queues, abort handling
- **Tool implementations** — read, write, edit, bash, grep, find, ls (battle-tested)
- **Session persistence** — JSONL v3 tree format with branching
- **RPC mode** — Headless JSON protocol for IDE/CI/orchestrator integration
- **Extension runtime** — Capability-gated QuickJS with trust lifecycle

### What We Modify

The core modification is the agent loop (`src/agent.rs`). Today:

```
while has_tool_calls || has_pending:
    stream_response → execute_tools → check_steering
```

Skaffen's loop becomes:

```
while has_tool_calls || has_pending:
    check_phase_gate → select_model(routing) → stream_response →
    execute_tools → emit_evidence → check_steering →
    maybe_reflect → maybe_compound
```

## TUI Decision: FrankenTUI vs charmed_rust (bubbletea)

Pi_agent_rust currently uses `charmed_rust` (Rust ports of Go's bubbletea/lipgloss/bubbles/glamour), also by Dicklesworthstone. FrankenTUI is his newer, more ambitious TUI framework.

### FrankenTUI Assessment

[Dicklesworthstone/frankentui](https://github.com/Dicklesworthstone/frankentui) — 20-crate Rust TUI kernel, v0.2.1.

**Strengths:**
- **Inline mode with scrollback preservation** — novel in Rust TUI space. Renders UI in a fixed-height region at bottom while logs scroll above. Critical for agent harnesses where you need to see both streaming output and stable UI chrome.
- **Bayesian adaptive diff strategy** — Beta posterior over change rates; auto-selects full-diff vs dirty-row vs full-redraw. Not heuristic — principled statistical selection with conformal frame-time gating.
- **One-writer rule enforced by type system** — `TerminalWriter` owns all stdout. Prevents concurrent write bugs structurally.
- **RAII terminal cleanup** — Guaranteed restore even on panic via `TerminalSession` drop.
- **37+ widgets** including Markdown (GFM, streaming), syntax highlighting, charts, CommandPalette (Bayesian fuzzy scoring), LogViewer (incremental, searchable).
- **Snapshot test harness** (ftui-harness) — Deterministic rendering for regression testing.
- **WASM support** (ftui-web) — Future web dashboard path for Autarch.
- **`#![forbid(unsafe_code)]`** across all crates — matches pi_agent_rust safety stance.

**Concerns:**
- **Pre-1.0 (v0.2.1)** — APIs will break. Acceptable if we're forking and owning the code anyway.
- **Smaller widget ecosystem than Ratatui** (37 vs 50+) — but the 37 cover agent TUI needs.
- **Different architecture than charmed_rust** — migration from bubbletea Elm pattern to ftui's runtime model is non-trivial.
- **Same author as pi_agent_rust** — alignment is good, but both projects are moving fast.

### Decision Options

**Option A: Keep charmed_rust (bubbletea) from pi_agent_rust fork**
- Zero migration cost. The TUI already works.
- Proven with the pi agent's interactive mode.
- Bubbletea's Elm Architecture is simple and well-understood.
- No inline mode — classic alt-screen only.

**Option B: Migrate to FrankenTUI**
- Inline mode is a genuine capability gain for agent harnesses.
- Bayesian diff + deterministic rendering is better engineering.
- Richer widget set (LogViewer, CommandPalette, Markdown) built in.
- WASM path for future Autarch web dashboard.
- Migration cost: rewrite interactive mode (src/interactive/) against ftui APIs.

**Option C: Start with charmed_rust, plan FrankenTUI migration later**
- Ship Skaffen v0.1 with existing TUI.
- Once the core loop modifications (phases, evidence, OODARC) are stable, migrate TUI.
- Risk: double work on TUI code, but derisks the critical path (agent loop > TUI).

**Current lean: Option C.** The agent loop is the value. The TUI can evolve. FrankenTUI's inline mode becomes critical when Autarch orchestrates multiple Skaffen instances (logs from many agents need scrollback), but for Skaffen standalone interactive mode, charmed_rust is fine.

## Key Architectural Decisions

### D1: Where does Skaffen live?

**Decision: Own repo at `github.com/mistakeknot/Skaffen`, monorepo anchor at `os/Skaffen/`.**

Skaffen is the sixth pillar — a sibling L2 OS alongside Clavain, not an app under Autarch. It has its own GitHub repo and Cargo workspace (same pattern as cass). The monorepo anchor at `os/Skaffen/` holds CLAUDE.md, AGENTS.md, and cross-repo references.

### D2: OODARC loop structure

The agent loop should implement OODARC natively:

```
Observe  → Tool results, LLM response, evidence from prior turns
Orient   → Phase context, model selection, tool availability for current phase
Decide   → LLM call with oriented context
Act      → Tool execution
Reflect  → Emit evidence (what happened, what was expected, what differed)
Compound → Persist learnings (routing overrides, calibration, solution docs)
```

**Question:** Should Reflect and Compound run every turn, or only at phase boundaries?

- **Every turn:** Maximum learning velocity. Evidence emitted continuously.
- **Phase boundaries only:** Lower overhead. Reflect/Compound are heavier operations.
- **Hybrid:** Lightweight evidence emission every turn (structured event → interspect), heavier reflection at phase boundaries (LLM-generated summary → docs/solutions/).

**Current lean: Hybrid.** Structured evidence every turn is cheap (JSON append). LLM-based reflection is expensive and belongs at phase gates.

### D3: Intercore integration depth

**Option A: Thin bridge (CLI calls)**
- Skaffen calls `ic` binary for dispatch, events, state.
- Same pattern Clavain uses today.
- Loose coupling. Easy to test without Intercore running.

**Option B: Native Rust client for Intercore SQLite**
- Direct SQLite reads/writes from Skaffen binary.
- No subprocess overhead. Real-time event emission.
- Tight coupling. Skaffen must understand Intercore schema.

**Option C: Intercore gRPC/HTTP API (future)**
- When Intercore exposes a proper API, use it.
- Not available today.

**Current lean: Option A to start, evolve to B.** Start with CLI bridge for correctness, optimize to native SQLite when the schema stabilizes.

### D4: How does Skaffen relate to Clavain's skills/commands?

Clavain's 17 skills encode discipline (brainstorming protocol, plan format, review checklist, etc.). Skaffen should benefit from this discipline without depending on Clavain's plugin system.

**Options:**
- **Port skills to Skaffen-native format.** Skaffen has its own skill/prompt loading (inherited from pi_agent_rust). Port the discipline content.
- **Load Clavain skills via compatibility bridge.** Read SKILL.md files from Clavain's directory, inject into Skaffen's resource loader.
- **Extract discipline into shared docs.** The discipline content (brainstorm protocol, phase gates, review checklist) becomes shared documentation that both Clavain and Skaffen consume.

**Decision: Extract to shared markdown docs (`docs/discipline/`).** The discipline is the value, not the plugin format. Both runtimes consume shared source of truth. Plugin infrastructure (hooks, MCP servers, slash commands) stays Clavain-only. Drop "compatibility bridge" language.

### D5: Phase-aware tool gating

In Clavain, tool availability is hint-based (system prompt says "in review phase, prefer grep/read over write/edit"). In Skaffen, it can be structural:

```rust
fn tools_for_phase(phase: Phase) -> Vec<&dyn Tool> {
    match phase {
        Phase::Brainstorm => vec![&read, &grep, &find, &ls],  // Read-only
        Phase::Plan       => vec![&read, &grep, &find, &ls, &write],  // Can write plan
        Phase::Build      => vec![&read, &write, &edit, &bash, &grep, &find, &ls],  // Full access
        Phase::Review     => vec![&read, &grep, &find, &ls, &bash],  // Read + test
        Phase::Ship       => vec![&read, &bash, &grep],  // Commit/push only
    }
}
```

**Question:** Hard gate (tool unavailable) or soft gate (tool available but system prompt discourages)?

**Decision: Hard gate (runtime-enforced).** Structural enforcement is the Demarch way (PHILOSOPHY.md: "structural, not moral"). If the model can't call `write` during review, it won't accidentally modify code when it should be reading. Note: this is runtime enforcement via exclusive tool lists, not compile-time type-system enforcement. Ship phase uses `git_bash` (allowlisted git subcommands) instead of unrestricted `bash`.

### D6: Model routing at the loop level

Each turn, Skaffen selects the model based on:
1. Phase (brainstorm may use a different model than build)
2. Interspect routing overrides (evidence-based model selection)
3. Cost optimization (cheapest model that clears the quality bar)
4. Fallback chain (if primary model rate-limited, fall back)

Pi_agent_rust's `Agent.setModel()` supports mid-session model switching. Skaffen adds the routing decision layer.

```rust
fn select_model(phase: &Phase, routing: &RoutingOverrides, budget: &Budget) -> Model {
    // 1. Check interspect overrides for this phase
    // 2. Check budget constraints
    // 3. Select cheapest qualifying model
    // 4. Apply fallback chain if needed
}
```

### D7: Inference backend strategy

Skaffen needs LLM inference. The cost model determines whether this is viable as a hobby project or requires API budgets.

**The problem:** Pi_agent_rust's `Provider` trait assumes API-key auth (Anthropic, OpenAI, Gemini, Azure, etc.). Claude Max subscriptions provide unlimited Claude usage but only through Claude Code's proprietary OAuth flow — there's no general-purpose bearer token a third-party binary can use.

**Three backends, not one:**

```rust
trait InferenceBackend: Provider {
    fn auth_method(&self) -> AuthMethod;
    fn supports_mid_turn_model_switch(&self) -> bool;
    fn cost_per_turn(&self, model: &Model, tokens: &TokenEstimate) -> Cost;
}

enum AuthMethod {
    ApiKey,              // Anthropic/OpenAI API keys — pay per token
    ClaudeCodeProxy,     // Piggyback on Max subscription via `claude --mode rpc`
    OAuth,               // Future: Anthropic programmatic Max access
}
```

**Option A: Claude Code as inference proxy (works today, $0 extra)**

Skaffen spawns `claude --mode rpc` as a subprocess and sends prompts via JSON-line protocol. The Claude Code process authenticates via the user's Max subscription. This is the same pattern Clavain uses with `ic run`.

```
Skaffen binary
  └── ClaudeCodeProvider
        └── spawns `claude --mode rpc` subprocess
              └── authenticates via Max OAuth (handled by Claude Code)
```

- Pro: Free with Max subscription. Proven pattern (Clavain does this today).
- Pro: No API key management. Works anywhere Claude Code is logged in.
- Con: Extra process hop (~50ms latency per call). Claude Code manages compaction and context window.
- Con: No mid-turn model switching — Claude Code picks the model (unless `set_model` RPC command is supported).
- Con: Bound by Claude Code's rate limits (currently generous on Max).

**Option B: Direct API with aggressive routing ($)**

Use pi_agent_rust's native `Provider` trait with API keys. D6's model routing selects the cheapest model per phase:

| Phase | Default Model | Estimated Cost (100K context) |
|-------|--------------|-------------------------------|
| Brainstorm | Haiku | ~$0.03 |
| Plan | Haiku/Sonnet | ~$0.05 |
| Build | Sonnet/Opus | ~$0.15-0.50 |
| Review | Haiku | ~$0.03 |
| Ship | Haiku | ~$0.01 |

A full sprint: ~$0.10-0.60 depending on build complexity. Viable for hobby use at low volume.

- Pro: Full control. Mid-turn model switching. No Claude Code dependency.
- Pro: Can use any provider (OpenAI, Gemini, local models for cheap phases).
- Con: Requires API keys and a budget. Opus-heavy sprints add up.
- Con: No subscription leverage — you pay retail per token.

**Option C: Future Anthropic OAuth for programmatic Max access**

Anthropic is building toward OAuth for third-party integrations (MCP OAuth, Claude integrations). When this ships, Skaffen registers as an OAuth client and gets a token scoped to the user's Max subscription.

- Pro: Best of both worlds — Max pricing with full Provider control.
- Con: Doesn't exist yet. Timeline unknown.
- Con: May have rate limits or capability restrictions vs. API.

**Decision: Phased rollout with v0.3 decision gate.**

- **v0.1:** ClaudeCodeProvider only (zero cost, `ModelSelection::Deferred`)
- **v0.2:** DirectApiProvider as opt-in (API keys required, `ModelSelection::Selected(model)`, test mid-session switching)
- **v0.3 decision gate:** Can ClaudeCodeProvider honor Interspect routing overrides? If not, v0.4 requires DirectApiProvider or Anthropic OAuth.
- **v0.4:** Self-building uses whichever backend satisfies `select_model()`. Flywheel only validated on direct API.

**Important limitation:** ClaudeCodeProvider delegates model selection to Claude Code, short-circuiting the routing flywheel. This is acceptable for v0.1-v0.2 (bootstrap) but the core thesis cannot be validated without a backend that honors `select_model()`.

This also means Skaffen v0.1 doesn't need to solve auth at all — it delegates to Claude Code, which already handles it.

### D8: Compaction strategy

**Decision: Hybrid — structured at phase boundaries, reactive mid-phase.**

Phase boundaries produce structured summaries (goal, decisions, artifacts, file lists) that become the seed for the next phase. Mid-phase, reactive compaction fires when the context threshold is crossed, preserving recent tool results and the phase's goal/constraints. Cumulative file tracking across compactions (pi-mono pattern).

Phase summaries are persisted in two places:
- **Session tree:** Compaction entry with `first_kept_entry_id` (for context rebuild within session).
- **Beads:** `bd update <id> --notes "phase summary"` (for cross-session persistence and handoff).

The session entry is the ephemeral receipt; the bead update is the durable one. This is the Receipts principle applied to context management.

### D9: System prompt architecture

**Decision: Priompt-style priority rendering, phase-aware.**

Each prompt component (identity, phase instructions, tool docs, sprint context, evidence, file lists) has a priority number. At each turn, Skaffen renders components into the token budget, dropping lowest-priority items first. Phase transitions change the priority map — during brainstorm, research context is high-priority; during build, tool docs are high-priority.

```rust
struct PromptElement {
    content: String,
    priority: i32,        // higher = more important
    phase_boost: PhaseMap, // per-phase priority adjustments
    tokens: usize,
}

fn render_prompt(elements: &[PromptElement], phase: Phase, budget: usize) -> String {
    // Sort by effective priority (base + phase boost)
    // Greedily include until budget exhausted
    // Isolate stable prefixes for cache hits
}
```

Prompt construction is a knapsack problem, not a template problem. The optimal packing changes per phase. The closed-loop pattern applies: start with hardcoded priorities (stage 1), collect which elements the model actually uses (stage 2), calibrate priorities from usage data (stage 3), hardcoded becomes fallback (stage 4).

Plugins add elements with priorities; the renderer handles the budget. ~200 lines of Rust.

**Research bead:** SPEAR prompt algebra (CIDR 2026) — typed prompt fragments with algebraic composition. Natural Rust type-system fit. Long-term evolution path.

### D10: Context window as budget — git-context architecture

**Decision: Context management as agent tools over JSONL session tree, with priority rendering as default eviction policy.**

Skaffen's JSONL session tree already has COMMIT (session entries), BRANCH (tree branching), and MERGE (branch summarization from pi-mono). Add explicit context operations as tools the agent can call:

```rust
enum ContextTool {
    Commit { summary: String },            // Checkpoint working state
    Retrieve { query: String },            // Pull from L2/L3 into L1
    Anchor { key: String, value: String }, // Pin stable signal (survives compression)
    Fold { scope: FoldScope },             // Compress a completed sub-task
}
```

Three memory tiers:
- **L1** (context window) — current phase + active tool results. Managed by D9's priority rendering.
- **L2** (session index) — JSONL session tree + SQLite index. Recent summaries, file lists, evidence.
- **L3** (persistent store) — beads, docs/solutions, session archive.

Factory.ai's anchored summaries: stable signals (phase goals, file lists, test results) persist as anchors. Volatile content (tool outputs, intermediate reasoning) gets compressed. Delta encoding: only new content since last anchor is in full resolution.

The agent controls its own memory — aligned with Skaffen's sovereignty philosophy. Every context operation produces a receipt (PHILOSOPHY.md: "every action produces evidence").

**Research beads:**
- Entropy-aware telescoping (SimpleMem, Jan 2026) — 30x token reduction via entropy-scored compression.
- Learned folding (AgentFold, ICLR 2026) — agent learns granular vs. deep consolidation. 30B matches 671B.
- RLMs (Prime Intellect, Jan 2026) — model writes code to manage own context. Most radical.
- MAGMA (Jan 2026) — multi-graph retrieval (semantic/temporal/causal/entity). 95% token reduction.

### D11: Fork maintenance strategy

**Decision: Hard fork with per-release-tag upstream review.**

Fork pi_agent_rust once, rename to Skaffen, diverge. Agent loop, session format, and extension system diverge immediately. No upstream tracking for modified files.

Per-release-tag "upstream review": diff `agent.rs` + `Cargo.toml` against each pi_agent_rust release tag. Provider-layer patches are the high-value upstream content, but they are entangled with `asupersync` wiring that won't show up in a provider-file-only diff. Per-tag diffs are more targeted than monthly cadence and catch these entanglements.

PHILOSOPHY.md says "Fork, don't rewrite." Pi_agent_rust's agent loop (`src/agent.rs`) isn't designed for extension — there's no plugin point for OODARC, phase gates, or evidence emission. A wrapper would fight the architecture.

### D12: MCP server compatibility

**Decision: Native Rust MCP client.**

Implement the MCP stdio client protocol in Rust. Skaffen discovers MCP servers from plugin.json manifests, spawns them as subprocesses, and registers their tools alongside built-in tools. Same tool dispatch for MCP tools and native tools. The Rust `mcp` crate handles the protocol.

This gives 34 Interverse plugins tools immediately, plus full MCP ecosystem access (not just Interverse). MCP is becoming the standard — Anthropic, OpenAI, Google all support it. Skaffen's sovereignty requires independent tool discovery.

### D13: Testing strategy

**Decision: Phased Block pyramid with stateful properties and behavioral contracts.**

**V0.1 — Block pyramid base:**
- **L1 Deterministic:** `mockall` for provider traits, `proptest` for tool argument fuzzing, `#[test]` for phase FSM. Runs in CI.
- **L2 Record/Replay:** VCR pattern — record real agent sessions as cassettes, replay deterministically. `insta` for snapshot approval when behavior changes. Runs in CI.
- **L3 Performance:** Criterion benchmarks for startup time, context rebuild speed, compaction speed. CI gates.

**V0.2 — Stateful properties + contracts:**
- **proptest-stateful:** Define agent state machine (phase, context tokens, tool history, anchors). Generate random transition sequences. Check postconditions (context ≤ max after compaction, system prompt survives, evidence emitted per tool call). Auto-shrink to minimal failing sequence.
- **ABC (Agent Behavioral Contracts):** Formal contracts with pre/post conditions on the OODARC loop. Drift detection across extended sessions.
- **L4 Probabilistic:** LLM-as-judge evals. Nightly, not CI. Grade outputs not paths.

**V0.3+ — Self-testing:** Skaffen tests itself by building itself (PHILOSOPHY.md: "Demarch builds itself with its own tools").

**Research bead:** SHIELDA (ICLR 2026) — cross-phase root cause tracing. Tool failure ← reasoning error linkage.

### D14: Interverse plugin bridge

**Decision: MCP + agents + shared discipline docs for v0.1.**

Three capabilities bridged:
1. **MCP tools** (D12) — native Rust MCP client. 34 plugins work immediately.
2. **Agent definitions** — parse agents/*.md files, dispatch with Skaffen's routing. ~20 plugins with agent definitions (interflux's 17 reviewers, intersynth's 3 synthesizers).
3. **Shared discipline docs** (D4) — skill content extracted to shared documentation both runtimes consume. Not SKILL.md format, not Skaffen-native format — shared markdown.

What stays Clavain-only for v0.1: hooks (SessionStart, PreToolUse — Skaffen's OODARC phases have different boundaries), Claude-specific skills (depend on Claude Code's context model), slash commands (Skaffen has its own TUI command system).

This covers ~80% of plugin value with ~20% of bridge effort.

**Research bead:** Full compatibility layer — translate all plugin capabilities across runtimes. 200-400 hours estimated. Evaluate after v0.2 based on actual usage patterns.

## Open Questions for Brainstorming

### Q1: Should Skaffen support multi-agent orchestration natively?

Pi_agent_rust is a single-agent system. Should Skaffen's loop support spawning sub-agents (other Skaffen instances via RPC)?

- **Yes:** Skaffen becomes a full orchestrator. Clavain's `subagent-driven-development` pattern is native.
- **No:** Keep Skaffen single-agent. Autarch handles multi-agent orchestration.
- **Hybrid:** Skaffen can spawn sub-Skaffens via RPC for parallelizable sub-tasks (file-level parallelism), but the orchestration layer (what to work on, when to review, when to ship) stays in Autarch/Intercore.

### Q2: What's the deployment model?

- **Developer machine:** Interactive mode, replaces/complements Claude Code for Demarch development.
- **CI/CD:** RPC/print mode in GitHub Actions, running Skaffen headlessly.
- **Server:** Long-running Skaffen instances managed by Autarch.
- **All three?** The pi_agent_rust fork already supports all modes.

### Q3: How does the self-building loop work?

Demarch builds itself with its own tools (PHILOSOPHY.md). Skaffen should be the first consumer of its own runtime — building Skaffen features using Skaffen.

- At what point is Skaffen capable enough to build itself?
- What's the bootstrap sequence? (Clavain-rigged Claude Code builds Skaffen v0.1-v0.3, then Skaffen builds v0.4+ — superseded by PRD/Roadmap which set the handoff at v0.4)

### Q4: Extension compatibility with pi_agent_rust ecosystem

Pi_agent_rust has 224 vendored extensions. Should Skaffen maintain compatibility with the pi extension ecosystem?

- **Yes:** Larger tool surface. Community extensions work out of the box.
- **No:** Demarch has its own extension ecosystem (Interverse). Maintaining pi compat is overhead.
- **Best-effort:** Keep the QuickJS extension runtime, don't break existing extensions, but don't gate on pi compat.

### Q5: What's the FrankenTUI migration trigger?

When does the TUI migration from charmed_rust to FrankenTUI become worth the cost?

- When Autarch orchestrates multiple Skaffen instances (inline mode needed for log multiplexing).
- When we need WASM rendering for a web dashboard.
- When charmed_rust hits a capability ceiling (likely around rich markdown rendering or widget composition).

## Prior Art (Already in docs/research/)

- `research-pi-agent-rust-repo.md` (2026-02-19) — Deep architectural analysis, 10 Autarch-applicable patterns
- `research-pi-mono-repo.md` (2026-02-19) — TypeScript version analysis, TUI patterns, extension system
- `assess-dicklesworthstone-batch-2.md` (2026-03-01) — CASS (adopt), CASR (adopt-tentative), beads_rust (port-partially)
- `dicklesworthstone-repo-triage-2026-02-27.md` — Full repo survey with Demarch module mappings

## Success Criteria

1. **Skaffen v0.1:** Hard fork built. ClaudeCodeProvider as default inference backend. Native MCP client loading Interverse plugins. Phase-aware tool gating (D5). Priority-based prompt rendering (D9). Hybrid compaction with beads persistence (D8). Block pyramid tests (L1+L2) passing. Can run a simple "read file, edit file, run tests" workflow with phase transitions.
2. **Skaffen v0.2:** OODARC loop native with git-context tools (commit/retrieve/anchor/fold). Evidence emission to Interspect. Model routing from routing overrides (D6). Agent definitions from Interverse dispatched. proptest-stateful for loop invariants. ABC behavioral contracts for drift detection.
3. **Skaffen v0.3:** Self-building (Skaffen develops Skaffen). Shared discipline docs consumed by both runtimes (D4+D14). Learned context allocation via ACON pattern (D10). Self-testing capability.
4. **Skaffen v1.0:** Production parity with Clavain-rigged Claude Code for Demarch development. Measurable improvement in autonomy level (PHILOSOPHY.md trust ladder). Direct API backend with full model routing. Prompt priority calibration from outcomes.

## Research Beads (to create when beads server is healthy)

The following research beads should be created as children of the Skaffen epic (Demarch-6qb):

1. **SPEAR prompt algebra** — CIDR 2026 paper. Typed prompt fragments with algebraic composition (compose, refine, specialize). Natural Rust type-system fit. Long-term evolution path for D9. Source: arxiv.org/abs/2508.05012
2. **Entropy-aware context compression (SimpleMem)** — Jan 2026. 30x token reduction via entropy-scored filtering + recursive consolidation + adaptive query-aware retrieval. Source: huggingface.co/papers/2601.02553
3. **Learned context folding (AgentFold)** — ICLR 2026. Multi-scale folding: granular condensation vs. deep consolidation. AgentFold-30B matches DeepSeek-671B. Source: arxiv.org/abs/2510.24699
4. **Recursive Language Models (RLMs)** — Prime Intellect, Jan 2026. Model writes Python code to manage own context. Never summarizes — delegates to scripts. Most radical approach. Source: primeintellect.ai/blog/rlm
5. **Multi-graph retrieval (MAGMA)** — Jan 2026. 4 orthogonal graphs (semantic/temporal/causal/entity). Policy-guided traversal. 95% token reduction. Source: arxiv.org/abs/2601.03236
6. **Cross-phase root cause tracing (SHIELDA)** — ICLR 2026. 36 exception types across 12 agent artifacts. Phase-aware recovery links execution errors to reasoning failures. Source: arxiv.org/abs/2508.07935
7. **Full Interverse compatibility layer** — Translate all plugin capabilities (skills, hooks, commands) across Clavain and Skaffen runtimes. 200-400 hours estimated. Evaluate after v0.2 based on usage patterns.
