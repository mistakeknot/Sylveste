---
artifact_type: brainstorm
stage: discover
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
| Feature parity | Mature (v0.57, 14K stars) | v0.1.8, 89/89 feature parity claimed | Trade-off |

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

**Decision: Own repo at `github.com/mistakeknot/skaffen`, monorepo anchor at `os/skaffen/`.**

Skaffen is the sixth pillar — a sibling L2 OS alongside Clavain, not an app under Autarch. It has its own GitHub repo and Cargo workspace (same pattern as cass). The monorepo anchor at `os/skaffen/` holds CLAUDE.md, AGENTS.md, and cross-repo references.

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

**Current lean: Extract to shared docs.** The discipline is the value, not the plugin format. Both runtimes should read from the same source of truth.

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

**Current lean: Hard gate.** Structural enforcement is the Demarch way (PHILOSOPHY.md: "structural, not moral"). If the model can't call `write` during review, it won't accidentally modify code when it should be reading.

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
- What's the bootstrap sequence? (Clavain-rigged Claude Code builds Skaffen v0.1, then Skaffen builds Skaffen v0.2+)

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

1. **Skaffen v0.1:** Fork built, Intercore bridge working, phase-aware tool gating implemented. Can run a simple "read file, edit file, run tests" workflow with phase transitions.
2. **Skaffen v0.2:** OODARC loop native, evidence emission to Interspect, model routing from routing overrides.
3. **Skaffen v0.3:** Self-building (Skaffen develops Skaffen). Discipline content shared with Clavain.
4. **Skaffen v1.0:** Production parity with Clavain-rigged Claude Code for Demarch development. Measurable improvement in autonomy level (PHILOSOPHY.md trust ladder).
