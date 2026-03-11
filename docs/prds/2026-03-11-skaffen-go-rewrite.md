---
artifact_type: prd
bead: Demarch-92j
stage: design
supersedes: docs/prds/2026-03-10-skaffen-v01-fork.md
flux_drive_review: 2026-03-11
---
# PRD: Skaffen Go Rewrite — Clean-Room Sovereign Agent Runtime

## Problem

The Rust fork of pi_agent_rust carries an OpenAI/Anthropic license rider on all 4 vendored dependencies (asupersync, charmed_rust, rich_rust, sqlmodel_rust). The rider explicitly names Anthropic as a Restricted Party and prohibits use by agents/contractors acting on their behalf. Developing rider-encumbered code with Claude Code is legally ambiguous. Additionally, Rust's 3-10 minute build cycles (measured: 3m06s clean with sccache on ethics-gradient) make iterating on orchestration logic unnecessarily slow.

## Solution

Clean-room Go implementation of Skaffen, studying pi-mono's (TypeScript, clean MIT, 22K stars) architecture for proven patterns. Go is already Demarch's systems language (14+ modules: intercore, intermute, autarch, intermap, etc.), compiles in 1-5 seconds, produces single binaries, and shares the L1 kernel's language for future native integration.

## Features

### F1: Provider Abstraction + Anthropic Implementation

**What:** Streaming LLM provider interface with Anthropic Claude as the first implementation, plus a Claude Code RPC proxy as an opt-in backend for Max subscriptions.

**Acceptance criteria:**
- [x] `Provider` interface defined: `Stream(ctx, messages, tools, config) → StreamResponse` with text chunks, tool calls, usage stats
- [x] Anthropic provider implements streaming via SSE (Messages API), supports tool_use, reports token usage
- [x] Anthropic provider is the default backend (works in CI/server environments with API key)
- [x] Claude Code proxy provider spawns `claude --print --output-format=stream-json` subprocess, delegates inference (opt-in via `--provider claude-code`)
- [x] Proxy provider: graceful error with actionable message when `claude` binary is missing, not logged in, or returns unexpected response format
- [x] Provider selection by name via config (e.g., `--provider anthropic` or `--provider claude-code`)
- [x] Unit tests with recorded HTTP responses (golden files)

### F2: Core Tool System

**What:** Tool registry with phase-aware gating and 7 built-in tools matching Claude Code's core capabilities.

**Acceptance criteria:**
- [ ] `Tool` interface: `Name(), Description(), Schema() → JSONSchema, Execute(ctx, params) → ToolResult`
- [ ] Tool registry accepts phase, returns only tools available for that phase (hard gate)
- [ ] Registry supports runtime tool registration (extension point for future MCP tools in v0.2)
- [ ] `read` tool: reads files with offset/limit, returns content with line numbers
- [ ] `write` tool: creates/overwrites files
- [ ] `edit` tool: exact string replacement with uniqueness validation
- [ ] `bash` tool: shell execution with configurable timeout (default 120s), output truncation (default 10K chars)
- [ ] `grep` tool: ripgrep wrapper with regex, glob filtering, output modes
- [ ] `glob` tool: file pattern matching, sorted by modification time
- [ ] `ls` tool: directory listing
- [ ] Phase gate matrix tested: brainstorm=read-only, build=full, review=read+test, ship=git-only

### F3: OODARC Agent Loop

**What:** Main agent loop implementing OODARC (Observe-Orient-Decide-Act-Reflect-Compound) with phase FSM and hard tool gating.

**Acceptance criteria:**
- [ ] Agent loop: `for { observe → orient → decide → act → reflect → compound }` with clean exit on completion or error
- [ ] Phase FSM: brainstorm → plan → build → review → ship, with explicit transitions
- [ ] Loop accepts Router (F4), Session (F5), and Emitter (F6) as constructor dependencies via interfaces — testable in isolation with mocks
- [ ] Orient step: assembles phase context, selects model (via Router), determines available tools (via Registry)
- [ ] Decide step: calls LLM with oriented context, streams response
- [ ] Act step: executes tool calls from LLM response, collects results via goroutine-per-tool
- [ ] Reflect step: emits lightweight structured evidence (JSON) per turn via Emitter
- [ ] Compound step: at phase boundaries, persists learnings (phase summary → session)
- [ ] Steering via RPC: `{"type": "steer", "direction": "...", "mode": "interrupt|queue"}` message on stdin interrupts current turn (interrupt) or queues for after current act (queue)
- [ ] Loop terminates cleanly on: task completion, budget exhaustion, phase gate violation, user interrupt (SIGINT)
- [ ] Tests: deterministic loop execution with mock provider/router/session/emitter, phase transitions verified

### F4: Model Routing

**What:** Per-turn model selection based on phase, Interspect overrides, cost optimization, and fallback chains.

**Acceptance criteria:**
- [ ] `Router` interface: `SelectModel(phase, budget) → (Model, Reason)`
- [ ] Default router: checks phase defaults → Interspect overrides → budget constraints → fallback chain
- [ ] Phase default map configurable (e.g., brainstorm=haiku, build=sonnet, review=haiku)
- [ ] Interspect routing overrides loaded from JSON file (static v2 format with phases array)
- [ ] Budget tracker: per-session token/cost tracking, configurable limits, graceful degradation on budget exhaustion
- [ ] Fallback chain: if primary model rate-limited or unavailable, try next in chain
- [ ] Tests: routing decisions verified for each phase, override precedence tested

### F5: Session Persistence

**What:** JSONL session format with basic context management. Hybrid compaction and priority prompt rendering deferred to v0.2.

**Acceptance criteria:**
- [ ] Session state: ordered list of messages (system, user, assistant, tool_result) with metadata (timestamp, phase, turn number)
- [ ] JSONL persistence: append-only write, full-state read, crash-safe (fsync after write)
- [ ] Basic truncation: when context exceeds token threshold, keep system prompt + last N turns (configurable, default 20)
- [ ] Phase boundary summary: on phase transition, generate structured summary (goal, decisions, artifacts, file list) and prepend to next phase's context
- [ ] Session resume: load from JSONL, reconstruct state, continue from last turn
- [ ] Tests: session roundtrips through JSONL, truncation preserves system prompt, phase summaries generated

**Deferred to v0.2:**
- Priompt-style priority prompt rendering with phase-boost
- Anchor system (pinned signals surviving compaction)
- Reactive mid-phase compaction
- Token-accurate budget tracking for context packing

### F6: Evidence Emission

**What:** Structured event emission per tool call and phase transition, with local persistence and intercore CLI bridge.

**Acceptance criteria:**
- [ ] Evidence struct: `{timestamp, session_id, phase, turn, tool_name, tool_args_hash, outcome, duration_ms, tokens_used}`
- [ ] Emitter interface: `Emit(event Evidence)` — injectable into agent loop
- [ ] Evidence emitted per tool call (Reflect step) and per phase transition (Compound step)
- [ ] Outcome signals: terminal state (success/failure/timeout), retry count, test pass rate (for bash tool running tests)
- [ ] Local JSONL emitter: writes evidence to `~/.skaffen/evidence/<session_id>.jsonl`
- [ ] Intercore CLI bridge: shells out to `ic events record --source=skaffen` when `ic` binary is available
- [ ] Standalone mode: detect `ic` availability at startup, fall back to local-only emission silently
- [ ] Tests: evidence emission verified per tool call, emitter mocked for agent loop tests

**Note:** intercore does not export a Go client library in v1 (CLI only). Native Go integration deferred to v0.2+ pending intercore `pkg/client` API. The CLI bridge provides the same functionality with subprocess overhead (~5ms per event).

### F7: CLI Entry Point

**What:** Command-line interface with print mode (stdin/stdout) and headless RPC mode. No TUI.

**Acceptance criteria:**
- [ ] `skaffen` binary with subcommands: `run` (default), `version`, `config`
- [ ] Print mode (`--mode print`): reads prompt from stdin or `-p` flag, streams response to stdout, exits
- [ ] RPC mode (`--mode rpc`): JSON-line protocol on stdin/stdout for IDE/CI/orchestrator integration
- [ ] RPC protocol supports: `prompt`, `steer` (interrupt/queue), `cancel`, `status` message types
- [ ] Config: `--provider`, `--model`, `--phase`, `--budget`, `--config-file` flags
- [ ] Config file: TOML at `~/.skaffen/config.toml` or `$SKAFFEN_CONFIG_PATH`
- [ ] Version: `skaffen version` prints version, Go version, build info
- [ ] Clean shutdown: SIGINT/SIGTERM handled, session persisted, evidence flushed

## Non-goals

- **TUI.** Skaffen starts headless. Clavain handles the human interface. If interactive mode is needed later, bubbletea (Go-native, MIT) is the path.
- **MCP client.** Deferred to v0.2. F2's registry supports runtime tool registration as the extension point. The tool registry design accounts for MCP but v0.1 ships with built-in tools only.
- **Extension sandbox (QuickJS/WASM).** Interverse MCP plugins replace this. WASM via wazero is a future option.
- **Full pi-mono test suite porting.** New test suite from scratch, informed by pi-mono's patterns.
- **Multi-agent orchestration.** Skaffen is single-agent. Autarch handles fleet orchestration.
- **OpenAI/Gemini providers.** Anthropic + Claude Code proxy for v0.1. Other providers in v0.2.
- **Native intercore Go client.** intercore is CLI-only in v1. F6 uses `ic` CLI bridge. Native integration when intercore ships `pkg/client`.

## Dependencies

- **Anthropic Messages API**: SSE streaming endpoint. No official Go SDK — implement directly (~300 lines).
- **Claude Code binary** (optional): For proxy provider (F1). Must be installed and logged in. Not required — direct Anthropic API is the default.
- **ripgrep binary**: For grep tool (F2). Standard dev tool, assumed available.
- **intercore `ic` binary** (optional): For evidence bridge (F6). Skaffen runs standalone without it.
- **pi-mono source** (read-only reference): Architecture patterns for provider interface, tool execution, context management. MIT license, no code copied.

## Architecture Notes (from flux-drive review)

- **No `bridge/` god-module.** Intercore bridge is a thin interface in `internal/intercore/`. Evidence emission lives in `internal/agent/evidence.go`. Beads reads (if needed) are standalone utility functions.
- **Dependency injection for testability.** F3's loop accepts Router, Session, and Emitter as interfaces. Each can be mocked independently.
- **Registry extension point.** F2's tool registry supports `Register(tool Tool)` at runtime, designed for v0.2 MCP tool registration without refactoring.

## Open Questions

1. **Repo location:** Separate repo (`github.com/mistakeknot/Skaffen`) or Go module within monorepo (`os/Skaffen/go.mod`)? Lean: separate repo, matching existing pattern.
2. **Rust repo disposition:** Archive the existing `mistakeknot/Skaffen` GitHub repo (preserve as reference, clearly mark superseded). Do not delete until Go version is proven.
3. **MCP library for v0.2:** Use mark3labs/mcp-go or implement minimal stdio client (~500 lines)? Evaluate maturity at v0.2 planning time.
