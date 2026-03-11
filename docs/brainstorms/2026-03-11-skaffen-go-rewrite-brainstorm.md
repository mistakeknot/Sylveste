---
artifact_type: brainstorm
stage: discover
supersedes: docs/brainstorms/2026-03-10-skaffen-sovereign-agent-brainstorm.md
---

# Skaffen Rewrite: Go Clean-Room from pi-mono Patterns

**Date:** 2026-03-11
**Status:** Brainstorming
**Trigger:** License contamination discovery — all 4 vendored crates in the Rust fork carry the OpenAI/Anthropic rider. The rider explicitly names Anthropic as a Restricted Party and prohibits use by agents/contractors acting on their behalf. Using Claude Code to develop rider-encumbered code is legally ambiguous at best.

## The Pivot

**From:** Hard fork of pi_agent_rust (Rust, MIT + OpenAI/Anthropic rider)
**To:** Clean-room Go implementation, studying pi-mono's (TypeScript, clean MIT) architecture for proven patterns

### Why This Is Better

1. **Zero license contamination.** pi-mono is clean MIT (copyright Mario Zechner). No rider. No vendored deps with riders. No ambiguity about Claude Code developing on rider-encumbered code.

2. **Go is already Demarch's systems language.** 14+ Go modules across the stack:
   - L1: intercore, intermute, interband, interbench
   - L2: clavain-cli
   - L3: autarch
   - Interverse: intermap, intermux, interlock, interserve
   - SDK: interbase/go
   - Shared tooling, shared patterns, shared deployment model

3. **Iteration speed.** Go compiles in 1-5 seconds. The Rust fork took 3-10 minutes per build even with sccache. Agent loop development is orchestration logic — you need fast iteration, not fast execution.

4. **Single binary deployment.** Same as Rust. `go build` → static binary → drop on server. No node_modules, no runtime dependency.

5. **Goroutines map perfectly to agent parallelism.** Parallel tool execution (bash + grep + read simultaneously), concurrent MCP server communication, background evidence emission — all natural with goroutines + channels. No async/await ceremony, no borrow checker fights.

6. **The OODARC loop is ~2K lines of orchestration.** The differentiators (phase gates, model routing, evidence emission, context management) are pure logic. In Go, that's 2-3 weeks of focused work. In Rust, we spent 2 weeks just getting the fork to compile, rebrand, and pass CI — before writing any Skaffen-specific code.

### Why Not TypeScript

pi-mono is TypeScript, and TypeScript has the richest agent ecosystem. But:

- **Demarch has zero TypeScript infrastructure.** No TS modules, no TS build pipeline, no TS testing conventions. Adding a TS pillar would be a foreign body.
- **node_modules on ethics-gradient.** With 30GB RAM and bidirectional mutagen sync, a node_modules directory is a liability.
- **Deployment friction.** Every other Demarch binary is `go build` → scp → run. A Node.js agent would need npm install, node runtime, potentially pkg/nexe bundling.
- **Go already has the intercore/intermute integration points.** Skaffen calling intercore is Go→Go, not TS→Go subprocess.

TypeScript is the right choice for the ecosystem. Go is the right choice for Demarch.

## What Changes from the Original Brainstorm

The original brainstorm (2026-03-10) made 14 architectural decisions (D1-D14). Most are language-agnostic and carry forward. Here's what changes:

### Decisions That Carry Forward Unchanged

| Decision | Summary | Why It Transfers |
|----------|---------|-----------------|
| D2 | OODARC loop structure (Observe→Orient→Decide→Act→Reflect→Compound) | Pure logic |
| D4 | Shared discipline docs in docs/discipline/ | Format-agnostic |
| D5 | Phase-aware tool gating (hard gates) | Pure logic |
| D6 | Model routing at the loop level | Pure logic |
| D7 | Inference backend strategy (Claude Code proxy → direct API → OAuth) | Provider interface, not language |
| D8 | Hybrid compaction (structured at phase boundaries, reactive mid-phase) | Pure logic |
| D9 | Priompt-style priority prompt rendering | Pure logic |
| D10 | Context window as budget — git-context architecture | Pure logic |
| D13 | Testing strategy (block pyramid, VCR, proptest-stateful) | Adapted to Go testing |

### Decisions That Change

| Decision | Was (Rust) | Now (Go) | Impact |
|----------|-----------|---------|--------|
| D1 | Own repo at github.com/mistakeknot/Skaffen (Rust cargo workspace) | Own repo at github.com/mistakeknot/Skaffen (Go module) | `os/Skaffen/` remains monorepo anchor |
| D3 | Intercore via `ic` CLI, evolve to native Rust SQLite | Intercore via Go SDK (`intercore/pkg/client`) — native from day one | Go→Go eliminates the subprocess hop. intercore already exports a Go client. |
| D11 | Hard fork of pi_agent_rust | Clean-room Go, pi-mono as reference architecture | No upstream tracking needed. No license entanglement. |
| D12 | Native Rust MCP client | Go MCP client (mark3labs/mcp-go or custom) | Smaller ecosystem but growing. Intermap already uses Go MCP. |
| D14 | MCP + agent defs + shared docs for plugin bridge | Same, but Go MCP client. Agent dispatch via goroutines. | Natural fit — fan-out to multiple agents is trivial with goroutines. |

### Decisions That Are New

| Decision | Summary |
|----------|---------|
| D15 | **Provider abstraction from pi-mono patterns.** Study pi-mono's provider interface (streaming, caching, OAuth) and implement in Go. Not a port — a clean-room implementation of the same interface contract. |
| D16 | **intercore native integration.** Import intercore's Go client directly. Events, runs, state, dispatch — all Go function calls, no subprocess overhead. This was "evolve to B" in the original plan; now it's the default. |
| D17 | **Goroutine-per-tool execution model.** Each tool invocation runs in its own goroutine. Results flow back via channels. Timeout and cancellation via context.Context. This replaces the Rust fork's asupersync structured concurrency. |
| D18 | **No vendored TUI framework.** Skaffen in Go starts headless (RPC/print mode). TUI is not a v0.1 concern — Clavain handles the human interface. If TUI is needed later, use bubbletea (Go-native, MIT, mature). |

## What Go Enables for Speculative Features

### Already on the roadmap — now easier

| Feature | Roadmap ref | Go advantage |
|---------|------------|-------------|
| **Intercore native bridge** | Demarch-j2f (v0.3) | Was "CLI bridge, evolve to native." Now native from v0.1 — Go imports intercore client directly. Saves an entire version of bridge scaffolding. |
| **Multi-agent orchestration** | Q1 in original brainstorm | Goroutines make spawning sub-Skaffens trivial. `go func() { runSkaffen(subTask) }()` with channel-based result collection. No RPC overhead for in-process sub-agents. |
| **Interverse plugin fan-out** | D14, F6: Marketplace | Start N MCP servers as goroutines, fan-out tool calls, merge results. The interflux 17-reviewer pattern becomes `for _, agent := range agents { go dispatch(agent, ctx) }`. |
| **Self-building loop** | Demarch-22q (v0.4) | Go builds in 1-5s. Skaffen modifying its own source and `go build`ing to verify takes seconds, not minutes. The self-building feedback loop is 10x tighter. |
| **Idle-time micro-task dispatch** | iv-2n0ew | Goroutine pool with budget-gated dispatch. A goroutine blocks on a channel until budget is available. Natural Go pattern. |
| **Conversation resumption** | Demarch-4wm brainstorm | Go's stdlib `encoding/json` + `os.Signal` handling make PreCompact hooks and crash recovery straightforward. No async runtime complexity. |

### Speculative features that Go uniquely enables

| Feature | Why Go specifically |
|---------|-------------------|
| **In-process intercore** | Skaffen could embed intercore as a Go library, not a separate service. Single binary that IS both the agent and the kernel. Eliminates the L1/L2 boundary for solo-developer deployment. |
| **Hot-reload agent logic** | Go plugins (`plugin.Build`) or Yaegi interpreter allow loading new OODARC phases/routing logic without recompiling. Skaffen could evolve its own agent loop at runtime. |
| **Shared-memory multi-agent** | Multiple Skaffen goroutines sharing a single context store (sync.Map or channel-mediated). No serialization overhead between agents. The WCM coordination patterns (iv-fwwhl) become in-process. |
| **interband native producer** | interband (event bus) is Go. Skaffen producing events directly to interband — no serialization, no IPC. Real-time evidence pipeline. |
| **intermute native participant** | intermute (coordination service) is Go. Skaffen participating in agent coordination natively — lock acquisition, message passing, conflict detection all in-process. |
| **interbench native harness** | interbench (benchmarking) is Go. Skaffen as both the subject and the harness. Self-benchmarking with zero overhead. |
| **CGo escape hatch for ML** | If Skaffen ever needs local inference (GGML, llama.cpp), CGo provides a clean FFI. Rust's FFI is harder to get right. Python subprocess is slower. |
| **WASM agent plugins** | wazero (Go-native WASM runtime, no CGo) for sandboxed plugin execution. Lighter than QuickJS, better sandboxing than Go plugins. Future path for untrusted extensions. |

### Speculative features that Rust was better for (and why it doesn't matter)

| Feature | Rust advantage | Why it doesn't matter |
|---------|---------------|---------------------|
| Memory predictability | No GC pauses | Agent is I/O bound (waiting on LLM). GC pauses (<1ms in Go 1.22+) are invisible next to 200ms-2s API latency. |
| TUI frame rate | Deterministic rendering timing | Skaffen starts headless. If TUI needed, bubbletea (Go) already handles 60fps. |
| Binary size | Smaller (46MB Skaffen) | Go binaries are ~15-30MB with `CGO_ENABLED=0`. Comparable. |
| Unsafe code prohibition | `#![forbid(unsafe_code)]` | Go is memory-safe by default. No `unsafe` blocks possible. |
| WASM compilation target | Compile agent to WASM | wazero runs WASM plugins inside Go. TinyGo compiles Go to WASM. Both paths exist. |

## Architecture

```
skaffen (Go module)
├── cmd/skaffen/           # CLI entry point (cobra or just flag)
├── internal/
│   ├── agent/             # OODARC loop: observe→orient→decide→act→reflect→compound
│   │   ├── loop.go        # Main agent loop
│   │   ├── phase.go       # Phase FSM (brainstorm→plan→build→review→ship)
│   │   ├── router.go      # Model routing (cheapest qualifying model per phase)
│   │   └── evidence.go    # Structured evidence emission
│   ├── provider/          # LLM provider abstraction
│   │   ├── provider.go    # Interface: Stream(messages, tools) → StreamResponse
│   │   ├── anthropic.go   # Anthropic Claude (streaming, caching, prompt cache)
│   │   ├── openai.go      # OpenAI (streaming, responses API)
│   │   ├── gemini.go      # Google Gemini
│   │   └── proxy.go       # Claude Code RPC proxy (zero-cost with Max)
│   ├── tool/              # Tool registry and execution
│   │   ├── registry.go    # Tool registration, phase gating
│   │   ├── read.go        # File read
│   │   ├── write.go       # File write
│   │   ├── edit.go        # String replacement edit
│   │   ├── bash.go        # Shell execution (timeout, output limits)
│   │   ├── grep.go        # Ripgrep wrapper
│   │   └── glob.go        # File pattern matching
│   ├── session/           # Context management and persistence
│   │   ├── session.go     # Session state (messages, tool results, anchors)
│   │   ├── compaction.go  # Hybrid compaction (phase boundary + reactive)
│   │   ├── priority.go    # Priompt-style priority prompt rendering (D9)
│   │   └── store.go       # JSONL persistence
│   ├── mcp/               # MCP client for Interverse plugins
│   │   ├── client.go      # MCP stdio client protocol
│   │   ├── discovery.go   # Plugin discovery from plugin.json
│   │   └── dispatch.go    # Tool dispatch to MCP servers
│   └── bridge/            # Demarch integrations
│       ├── intercore.go   # Native intercore client (events, runs, state)
│       ├── interspect.go  # Evidence emission to interspect
│       └── beads.go       # Bead state reads (for sprint context)
├── pkg/                   # Exported packages (for interband, interbench)
│   └── skaffen/           # Public API for embedding
├── testdata/              # VCR cassettes, golden files
└── go.mod
```

Estimated: ~5-8K lines of Go for v0.1 (working agent with phase gates, model routing, evidence emission, MCP client). Compare to 300K lines inherited from the Rust fork (most of which was irrelevant to Skaffen's mission).

## What to Study from pi-mono

pi-mono (TypeScript, clean MIT, 22K stars) is the reference architecture. Not a port — study the design decisions:

1. **Provider streaming interface** — How pi-mono unifies streaming across Anthropic/OpenAI/Gemini. The `StreamResponse` shape (text chunks, tool calls, usage stats).
2. **Tool execution model** — Bash timeouts, file read size limits, edit validation (match uniqueness, whitespace preservation).
3. **Context window management** — When to compact (token threshold), what to keep (system prompt + recent N turns + tool results), cumulative file tracking across compactions.
4. **Session JSONL format** — Tree structure with COMMIT/BRANCH/MERGE nodes. Study for compatibility or learn from their format decisions.
5. **Steering and follow-up** — `steer()` (interrupt mid-tool-use with new direction) and `followUp()` (queue work for after current turn). These are the programmatic hooks Clavain can only approximate.

What to ignore from pi-mono:
- TUI implementation (Skaffen starts headless)
- Extension system (Interverse replaces this via MCP)
- VCR recording infrastructure (use Go's httptest + golden files)
- Browser/web UI layers
- Authentication flows (Claude Code proxy handles auth in v0.1)

## Skaffen Roadmap (Revised)

### v0.1: Working Agent (2-3 weeks)

- Provider interface + Anthropic implementation (streaming)
- Claude Code RPC proxy as default backend
- Core tools: read, write, edit, bash, grep, glob
- OODARC loop with phase FSM
- Phase-gated tool availability (hard gates)
- JSONL session persistence
- CLI: print mode (stdin/stdout) + headless RPC mode
- Tests: unit + VCR replay

### v0.2: Routing + Evidence (2 weeks)

- Model routing (cheapest qualifying model per phase)
- Interspect evidence emission (native Go, no subprocess)
- OpenAI + Gemini providers
- Direct API backend (API key auth)
- Priority prompt rendering (D9)
- Hybrid compaction (D8)
- MCP client for Interverse plugins

### v0.3: Native Integration (2 weeks)

- Intercore native client (Go→Go, no CLI bridge)
- interband event production
- Shared discipline docs consumption
- Agent definition dispatch from Interverse
- Context tools (commit, retrieve, anchor, fold)

### v0.4: Self-Building (ongoing)

- Skaffen develops Skaffen
- Self-testing, self-benchmarking
- Graduated autonomy (L1→L2→L3)

## Impact on Existing Beads

| Bead | Status | Action |
|------|--------|--------|
| Demarch-rp5 (v0.1 fork) | CLOSED | Already done. The Rust fork served its purpose as exploration. |
| Demarch-92j (v0.2 OODARC) | OPEN | **Redefine.** Same goal (OODARC loop), different implementation. Now v0.1 in Go, not v0.2 in Rust. |
| Demarch-j2f (v0.3 Intercore bridge) | OPEN | **Accelerated.** Native Go integration from v0.1, not v0.3. Scope narrows to evidence pipeline testing. |
| Demarch-22q (v0.4 self-building) | OPEN | Unchanged. Same goal, same criteria, faster path. |
| Demarch-6qb (epic) | OPEN | Update description to reflect Go rewrite. |
| Demarch-6qb.1-7 (research children) | OPEN | Unchanged. Research topics are language-agnostic. |

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| Go MCP ecosystem is immature | Medium | mark3labs/mcp-go exists. Intermap already uses Go MCP. Worst case: implement stdio MCP client (~500 lines). |
| No official Anthropic Go SDK | High | Implement streaming HTTP client directly. Anthropic's API is simple REST + SSE. ~300 lines. |
| Provider parity takes longer than expected | Medium | Start with Claude Code proxy (zero provider implementation needed). Add direct providers incrementally. |
| pi-mono patterns don't translate cleanly to Go | Low | The patterns are architectural (interface contracts, execution models), not language-specific. |
| Sunk cost fallacy on Rust fork | Zero | The Rust fork taught us what matters: the agent loop is ~2K lines of orchestration logic. The other 298K lines were baggage. The real value was understanding the architecture. |

## Open Questions

### Q1: Separate repo or monorepo module?

The Rust fork needed a separate repo because cargo workspaces don't nest well and `os/` is gitignored. Go modules are more flexible — `os/Skaffen/` could contain a `go.mod` and be a proper Go module within the monorepo. But a separate repo matches every other pillar.

**Lean:** Separate repo at `github.com/mistakeknot/Skaffen`, matching the existing pattern. `os/Skaffen/` remains a docs anchor.

### Q2: Should the Rust fork be archived or deleted?

The Rust fork at `github.com/mistakeknot/Skaffen` has 300K+ lines of rider-encumbered code. Options:
- **Archive:** Keep as reference, clearly mark as superseded.
- **Delete + recreate:** Same repo name, fresh Go module. Clean git history. No rider-encumbered code in history.
- **New repo name:** `Skaffen-go` or similar. Awkward but avoids any contamination questions.

**Lean:** Delete and recreate. The Rust code has no ongoing value, and keeping rider-encumbered code in git history is unnecessary risk.

### Q3: What about the Rust fork's test fixtures and VCR cassettes?

The test fixtures (API response recordings, golden files) are useful but were generated under the rider-encumbered codebase. They're likely factual data (API responses aren't copyrightable), but safest to regenerate from scratch.

### Q4: Timeline to first working agent?

With Go's iteration speed and the architecture already fully designed (14 decisions from the original brainstorm), a working agent (provider + tools + OODARC loop + CLI) is ~2-3 weeks of focused work. Compare to 2 weeks just rebasing the Rust fork.

### Q5: Should intercore client be imported or reimplemented?

Intercore exports a Go client package. Skaffen could import it directly (`github.com/mistakeknot/intercore/pkg/client`). But this creates a compile-time dependency on intercore's module graph. Alternative: thin HTTP/CLI bridge that's compatible but decoupled.

**Lean:** Import directly. Intercore is a Demarch module — the coupling is intentional, not accidental.
