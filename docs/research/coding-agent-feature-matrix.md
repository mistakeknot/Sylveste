# Coding Agent TUI Feature Matrix

> Continuously updated competitive comparison across major AI coding agent CLIs/TUIs.
> Last updated: 2026-03-12
>
> **How to update:** Add new agents as columns. Add new features as rows. Mark cells with the status key below. Keep per-agent deep-dive docs in `docs/research/` and link from the Sources section.

## Status Key

| Symbol | Meaning |
|--------|---------|
| **Y** | Fully supported |
| **P** | Partial / limited |
| **N** | Not supported |
| **?** | Unknown / unresearched |
| *planned* | On roadmap but not shipped |

## Agents Compared

| Property | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|----------|---------|-------------|-----------|------------|----------|-----|
| **Developer** | Demarch | Anthropic | OpenAI | Google | Anomaly | Sourcegraph |
| **Language** | Go | TypeScript | Rust | TypeScript | TypeScript | Go |
| **TUI Framework** | Bubble Tea | Ink (React) | Ratatui | Ink | OpenTUI (SolidJS) | Chat REPL |
| **License** | Proprietary | Proprietary | Apache 2.0 | Apache 2.0 | MIT | Source-available |
| **Default Model** | Sonnet 4.6 | Sonnet 4.6 | GPT-5.4 | Gemini 3 (auto-routed) | Configurable | Claude Sonnet |

---

## 1. Slash Commands

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Slash command system** | Y (16 cmds) | Y (20+ cmds) | Y (27 cmds) | Y (33+ cmds) | Y (dialog-based) | P (few cmds) |
| **`/help`** | Y | Y | Y | Y | Y | N |
| **`/model` switching** | Y | Y (`/model`) | P (`/model` read-only) | Y (`/model`) | Y (dialog) | N |
| **`/diff` git diff** | Y | Y | Y (`/diff`) | Y (`/diff`) | Y (overlay) | N |
| **`/commit`** | Y | N (agent does it) | N | N | N | N |
| **`/undo` last commit** | Y | N | N | N | N | N |
| **`/push` / `/ship`** | Y | N | N | N | N | N |
| **`/compact` / `/compress`** | Y | Y | Y | Y (`/compress`) | N | N |
| **`/settings` interactive** | Y (overlay) | Y (`/config`) | P (`/preferences`) | Y (`/settings`) | Y (dialog) | N |
| **`/theme` switching** | Y | Y | Y | Y (`/theme`) | Y (`<leader>t`) | P (config only) |
| **`/phase` / `/advance`** | Y (OODARC) | N | N | N | N | N |
| **`/status` session info** | Y | Y (`/status`) | Y (`/stats`) | Y (`/stats`) | N | N |
| **`/sessions` list** | Y | N | P (`/history`) | Y (`/sessions`) | Y (dialog) | Y (cloud threads) |
| **`/clear` viewport** | Y | Y | Y | Y | N | N |
| **`/version`** | Y | Y | Y | Y | N | N |
| **`/quit`** | Y | Y | Y | Y | N | N |
| **`/permissions` toggle** | N | N | Y | Y (`/permissions`) | N | N |
| **`/init` project setup** | N | Y | Y | Y (`/init`) | Y | N |
| **`/plan` mode** | N | N | N | Y (read-only research) | N | N |
| **`/restore` / `/rewind`** | N | N | N | Y (undo tool changes) | N | N |
| **`/extensions` management** | N | N | N | Y (install/enable/disable) | N | N |
| **`/skills` management** | N | Y (plugins) | N | Y (enable/disable/reload) | N | N |
| **`/hooks` management** | N | N | N | Y (enable/disable/list) | N | N |
| **`/review-pr`** | N | Y (skill) | N | N | N | Y (`amp review`) |
| **Custom slash commands** | N | Y (skills) | Y (disk-based) | Y (TOML files) | N | N |
| **MCP prompts as commands** | N | N | N | Y | N | N |
| **`/prompt-suggest`** | N | N | N | Y | N | N |
| **Command completion popup** | Y (filtered list) | Y (fuzzy) | Y (popup) | Y (Tab) | Y (dialog) | N |

---

## 2. Hooks & Extensions

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Hook system** | N | Y (6 events) | P (2 events) | Y (11 events) | Y (plugin events) | N |
| **SessionStart hook** | N | Y | Y | Y | Y | N |
| **PreToolUse hook** | N | Y | N | Y (pre-tool) | N | N |
| **PostToolUse hook** | N | Y | N | Y (post-tool) | N | N |
| **Notification hook** | N | Y | N | Y | N | N |
| **Permission hooks** | N | Y (allow/deny) | N | Y (policy engine) | N | N |
| **Plugin/extension system** | Y (MCP only) | Y (plugins) | N | Y (extensions) | Y (plugin API) | P (MCP only) |
| **Custom tool registration** | Y (MCP) | Y (MCP + plugins) | N | Y (MCP + extensions) | Y (plugin tools) | Y (MCP) |
| **Hook config format** | — | JSON (hooks.json) | JSON | JSON (settings.json) | JS/TS API | — |
| **Policy engine** | N | N | P (sandbox profiles) | Y (TOML, 5-tier priority) | N | N |
| **BeforeModel / AfterModel hooks** | N | N | N | Y (mock/redact responses) | N | N |
| **BeforeToolSelection hook** | N | N | N | Y (filter tools) | N | N |
| **Extensions gallery** | N | N | N | Y (browse/install) | N | N |
| **Agent Skills (lazy-loaded)** | N | Y (skills) | N | Y (SKILL.md) | N | N |

---

## 3. UI/UX & Layout

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **TUI type** | Full-screen | Full-screen | Full-screen | REPL-style | Full-screen | Chat REPL |
| **Split panes** | N | N | N | N | Y (sidebar) | N |
| **Scrollable viewport** | Y | Y | Y | Y (scroll history) | Y | Y |
| **Status bar** | Y (phase, model, cost, ctx%, turns) | Y (model, cost, context) | Y (mode, context, hints) | Y (model, tokens) | Y (agent state, model, ctx%) | P (minimal) |
| **Markdown rendering** | Y (headers, code, lists) | Y (Shiki syntax) | Y (syntax-highlighted) | Y (markdown) | Y (rich markdown) | Y |
| **Diff display** | Y (inline preview) | Y (inline diff) | Y (syntax-highlighted) | Y | Y (full-screen overlay) | Y |
| **Progress indicators** | Y (streaming text) | Y (spinner + streaming) | Y (spinner) | Y (spinner) | Y (spinner) | Y |
| **Themes** | Y (Masaq: Tokyo Night, Catppuccin, etc.) | Y (customizable) | Y (built-in + `.tmTheme`) | Y (built-in themes) | Y (11+ built-in, JSON custom) | Y (7+ built-in, TOML custom) |
| **Runtime theme switching** | Y (`/theme`) | Y (`/config`) | Y (`/theme`) | Y (`/theme`) | Y (`<leader>t`) | P (config restart) |
| **Dark/Light mode** | Y (auto-detect) | Y (auto-detect) | Y | Y | Y | Y |
| **Logo/splash animation** | Y (particle swarm) | N | N | N | N | N |
| **Overlay dialogs** | Y (settings, tool approval) | Y (permission) | Y (approval, slash picker) | Y (tool approval) | Y (11 overlays) | N |
| **Vim mode** | N | Y | N | Y (`/vim`) | Y (vim editor) | N |
| **External editor** | N | Y (`Ctrl+G`) | N | Y (`Ctrl+X`) | Y (vim-style) | N |
| **Image support** | N | Y (paste + @ref) | N | Y (inline images) | N | N |
| **Desktop app** | N | N (terminal only) | N | N | Y (Tauri/Electron) | N |
| **Web client** | N | N | N | N | Y (browser) | Y (web app) |
| **VS Code extension** | N | Y | Y | Y (IDE companion) | Y | Y (Zed panel) |
| **Background shells** | N | N | N | Y (`Ctrl+B`, Tab focus) | N | N |
| **Subagents** | N | Y (background) | N | Y (4 built-in + custom) | N | N |
| **Screen reader mode** | N | N | N | Y (`--screen-reader`) | N | N |
| **Color depth** | True color (24-bit) | True color (24-bit) | True color | True color | True color | True color |

---

## 4. Keyboard Shortcuts

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Enter to submit** | Y | Y | Y | Y | Y | Y |
| **Shift+Enter newline** | Y | Y | Y | Y (+ Ctrl+Enter, Alt+Enter, Ctrl+J) | Y | Y |
| **External editor** | N | Y (`Ctrl+G`) | N | Y (`Ctrl+X`) | Y (vim) | N |
| **History search** | N | Y (`Ctrl+R`) | N | Y (`Ctrl+R`, `Ctrl+P/N`) | N | N |
| **Shell escape (`!`)** | N | Y | N | Y | N | N |
| **Scroll: PageUp/Down** | Y | Y | Y | Y | Y | N |
| **Scroll: Ctrl+U/D** | Y | Y | N | N | Y | N |
| **Scroll: mouse wheel** | Y | Y | Y | Y | Y | N |
| **Approval mode toggle** | N | N | N | Y (`Shift+Tab`) | N | N |
| **UI detail toggle** | N | N | N | Y (`Tab×2`) | N | N |
| **Shortcuts help panel** | N | N | Y (dynamic hints) | Y (`?` toggle) | Y (`?`) | N |
| **Custom keybindings** | N | Y (`keybindings.json`) | N | Y (`keybindings.json`) | N | N |
| **File picker trigger** | Y (`@`) | Y (`@` + Tab) | Y (`@`) | Y (`@`) | Y (`Ctrl+F`) | P |
| **Command picker trigger** | Y (`/`) | Y (`/`) | Y (`/`) | Y (`/`) | Y (dialog) | N |

---

## 5. Model Routing

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Phase-based routing** | Y (OODARC: brainstorm→ship) | N | N | N | N | N |
| **Automatic model routing** | N | N | N | Y (lite model decides) | N | N |
| **Mid-session model switch** | Y (`/model`) | Y (`/model`) | P (read-only) | Y (`/model`) | Y (dialog) | N |
| **Multi-model pipeline** | N | N | N | Y (auto: flash+pro) | N | N |
| **Architect/Editor split** | N | N | N | N | N | N |
| **Budget tracking** | Y (cost + context %) | Y (cost + context) | Y (context) | Y (token stats) | Y (context %) | P |
| **Budget degradation** | Y (configurable threshold) | N | N | N | N | N |
| **Complexity routing** | Y (shadow/enforce modes) | N | N | Y (lite model triage) | N | N |
| **Model aliases** | Y (opus/sonnet/haiku) | Y | Y | Y | Y | N |
| **Per-phase env override** | Y (`SKAFFEN_MODEL_<PHASE>`) | N | N | N | N | N |
| **Context window config** | Y (per-model in routing.json) | N (auto) | N (auto) | Y (validation on switch) | N | N |

---

## 6. Session Management

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Session persistence** | Y (JSONL) | Y | Y (Markdown) | Y (JSON) | Y (SQLite) | Y (cloud) |
| **Resume last session** | Y (`-c` flag) | Y (`--continue`) | Y (`/history`) | Y (`--resume`) | Y | Y |
| **Resume by ID** | Y (`-r <id>`) | Y (`--resume`) | P | Y (interactive browser) | Y | Y |
| **Session browser** | Y (`/sessions`) | N | P (`/history`) | Y (interactive) | Y (dialog) | Y (web) |
| **Context compaction** | N | Y (`/compact`) | Y (`/compact`) | Y (`/compress`, auto at 50%) | N | N |
| **Manual compaction** | N | Y | Y | Y (`/compress`) | N | N |
| **Session forking** | N | N | N | N | Y (fork) | N |
| **Cloud sync** | N | N | N | N | N | Y (cross-device) |
| **Session retention policy** | N | N | N | Y (30d default, configurable) | N | N |
| **Max turns config** | Y (`-max-turns`) | N | N | N | N | N |
| **Named sessions** | Y (`-session <id>`) | N | N | Y | Y | Y (threads) |

---

## 7. Tool System

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Built-in tools** | 7 | 10+ | 6+ | 14 | 8+ | 5+ |
| **Phase gating** | Y (5-phase matrix) | N | N | N | N | N |
| **MCP support** | Y (stdio) | Y (stdio + SSE) | N | Y (stdio + SSE + HTTP) | Y | Y |
| **Tool approval** | Y (Yes/No/Always) | Y (Yes/No/Always for session) | Y (3 modes) | Y (per-tool policies) | Y (permission dialog) | P |
| **Diff preview on approval** | Y (configurable) | Y | Y | N | Y (full-screen) | N |
| **Sandbox/isolation** | N | N | Y (network + filesystem) | Y (Seatbelt/Docker/gVisor/LXC) | N | P |
| **Tool include/exclude** | N | N | N | Y (per MCP server) | N | N |
| **LSP integration** | N | N | P (diagnostics) | N | Y (30+ languages) | N |
| **Web search tool** | N | Y | Y | Y (Google grounding) | N | Y |
| **Google Search grounding** | N | N | N | Y (unique) | N | N |

---

## 8. Git Integration

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Auto-commit** | Y (`/commit`) | Y (agent-driven) | N | N | N | N |
| **Undo last commit** | Y (`/undo`) | N | N | N | N | N |
| **Push** | Y (`/ship`) | Y (agent-driven) | N | N | N | N |
| **Diff viewing** | Y (`/diff`) | Y (inline) | Y (syntax-highlighted) | Y | Y (full-screen overlay) | N |
| **Branch awareness** | Y (status bar) | Y | Y | Y | Y (sidebar) | N |
| **Pre-commit per edit** | N | N | N | N | N | N |
| **Git-first workflow** | N | N | N | N | N | N |

---

## 9. File Mentions & Context

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **`@file` references** | Y (picker + expansion) | Y (tab-complete) | Y | Y | Y (`Ctrl+F`) | P |
| **`@directory` references** | N | Y | N | Y | N | N |
| **File picker UI** | Y (filtered, 10 items) | Y (tab-complete) | Y (popup) | Y | Y (fuzzy search) | N |
| **Max file size** | 50KB | No hard limit | ? | ? | ? | ? |
| **Image references** | N | Y | N | Y | N | N |
| **Stdin piping** | Y (`-p` flag) | Y (`-p` flag) | Y (`-p` flag) | Y (pipe) | Y | Y |
| **Context files (CLAUDE.md)** | N | Y (CLAUDE.md) | Y (AGENTS.md) | Y (GEMINI.md) | Y (RULES.md) | Y (AGENT.md) |
| **Repo map / tree-sitter** | N | N | N | N | N | N |

---

## 10. Configuration

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Config file** | `~/.skaffen/routing.json` | `~/.claude/settings.json` | `~/.codex/config.toml` | `~/.gemini/settings.json` | `~/.config/opencode/config.json` | `~/.config/amp/settings.toml` |
| **Per-project config** | N | Y (`.claude/`) | Y (`.codex/`) | Y (`.gemini/`) | Y (`.opencode/`) | Y |
| **Environment variables** | Y (`SKAFFEN_MODEL_*`) | Y (`ANTHROPIC_*`) | Y (`OPENAI_*`) | Y (`GEMINI_*`) | Y | Y |
| **Plugin config** | Y (`plugins.toml`) | Y (plugins) | N | Y (MCP in settings) | Y (plugin API) | Y (MCP in settings) |
| **Settings UI** | Y (interactive overlay) | Y (`/config`) | Y (`/preferences`) | Y (`/settings`) | Y (dialogs) | N |

---

## 11. Approval & Autonomy

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Approval model** | Per-tool (Yes/No/Always) | Per-tool (Yes/No/Always) | 3 modes (untrusted/on-request/never) | Policy engine (YAML rules) | Per-tool dialog | Per-tool |
| **Auto-approve mode** | N | Y (`--dangerously-skip-permissions`) | Y (`-a never`) | Y (auto-edit mode) | N | N |
| **Mid-session mode toggle** | N | N | Y (`/permissions`) | Y (`Shift+Tab`) | N | N |
| **Risk-rated tiers** | N | N | N | N | N | N |
| **Per-tool policies** | N | N | P (sandbox profiles) | Y (YAML per tool/server) | N | N |
| **Trust escalation** | Y (Always for session) | Y (Always for session) | N | Y (Allow future sessions) | N | N |

---

## 12. Provider & Auth

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Multi-provider** | Y (anthropic, claude-code) | N (Anthropic only) | N (OpenAI only) | P (Gemini + Vertex) | Y (many providers) | P (Anthropic primary) |
| **Free tier** | N | N | Y (ChatGPT account) | Y (60 req/min, 1K/day) | N (BYOK) | N |
| **API key auth** | Y | Y | Y (+ OAuth) | Y | Y | Y |
| **OAuth / Google login** | N | N | Y | Y | N | N |
| **Enterprise / Vertex** | N | N | Y (Azure) | Y (Vertex AI) | N | N |
| **Rate limit display** | N | N | N | Y (`/stats model`) | N | N |

---

## 13. Unique / Differentiating Features

| Feature | Agent | Description |
|---------|-------|-------------|
| **OODARC phase workflow** | Skaffen | 5-phase FSM (brainstorm→plan→build→review→ship) with per-phase tool gating and model routing |
| **Particle logo animation** | Skaffen | 48-particle HSV→brand-color swarm on startup |
| **Game of Life easter egg** | Skaffen | *planned* — true-color background layer (Demarch-oyi) |
| **Evidence pipeline** | Skaffen | JSONL event emission bridging to Interspect |
| **Vim mode** | Claude Code | Full vim keybinding subset for input |
| **Image paste** | Claude Code | `Ctrl+V` clipboard image injection |
| **Skills ecosystem** | Claude Code | Plugin bundles (skills + hooks + MCP + agents) |
| **Subagents** | Claude Code | Background agent spawning |
| **Rust sandbox** | Codex CLI | Network + filesystem isolation per command |
| **AGENTS.md scaffolding** | Codex CLI | `/init` generates project context file |
| **27 slash commands** | Codex CLI | Second-most extensive built-in command set |
| **Google Search grounding** | Gemini CLI | Real-time web verification during coding |
| **1M token context** | Gemini CLI | Largest context window of any CLI agent |
| **Automatic model routing** | Gemini CLI | Lite model triages to flash/pro per-request |
| **Policy engine** | Gemini CLI | YAML-based per-tool security policies |
| **MCP prompts as commands** | Gemini CLI | MCP server prompts exposed as slash commands |
| **Hooks lifecycle** | Gemini CLI | Pre/post tool hooks with middleware pattern |
| **33 slash commands** | Gemini CLI | Most extensive built-in command set of any agent |
| **11 hook events** | Gemini CLI | Most comprehensive hook lifecycle (BeforeModel, AfterModel, BeforeToolSelection unique) |
| **Session retention policies** | Gemini CLI | Configurable max age (30d default) with auto-cleanup |
| **Rewind / Restore** | Gemini CLI | Undo conversation + file changes independently or together |
| **Background shells** | Gemini CLI | Concurrent shell processes with Tab focus switching |
| **Browser agent** | Gemini CLI | Chrome automation via computer-use model |
| **Plan Mode** | Gemini CLI | Read-only research environment with Pro model, auto-routing |
| **Agent-to-Agent (A2A)** | Gemini CLI | Remote agent delegation over HTTP |
| **Extensions gallery** | Gemini CLI | Community extension discovery and install |
| **4-backend sandbox** | Gemini CLI | Seatbelt, Docker/Podman, gVisor, LXC |
| **Environment var redaction** | Gemini CLI | Auto-strips secrets from MCP server environments |
| **LSP integration (30+ langs)** | OpenCode | Real-time diagnostics fed to LLM |
| **11 overlay dialogs** | OpenCode | Most sophisticated TUI overlay system |
| **Desktop + Web + Slack** | OpenCode | Multi-client architecture (TUI, desktop, web, Slack, VS Code) |
| **Cloud-synced threads** | Amp | Cross-device session sharing |
| **`amp review` PR workflow** | Amp | Dedicated code review subcommand |
| **Checks framework** | Amp | Structured verification assertions |

---

## Skaffen Gap Analysis

### Skaffen-unique strengths (no competitor has)
- OODARC phase workflow with per-phase tool gating
- Budget degradation thresholds
- Per-phase model routing via env vars
- Particle swarm logo animation
- `/undo` and `/ship` git commands
- Evidence pipeline (structured event emission)
- Max turns configuration

### High-priority gaps (most competitors have, Skaffen doesn't)
- **Hook system** — Claude Code (6 events), Gemini CLI (lifecycle), OpenCode (plugin events)
- **Context compaction** — Claude Code and Codex CLI both support manual compaction
- **Custom slash commands** — Claude Code (skills), Codex CLI (disk), Gemini CLI (TOML)
- **Context files (CLAUDE.md equivalent)** — every competitor has project-level context injection
- **Vim mode / external editor** — Claude Code, Gemini CLI, OpenCode all support this
- **History search** — Claude Code has `Ctrl+R`
- **Shell escape (`!` prefix)** — Claude Code and Gemini CLI
- **Sandbox / isolation** — Codex CLI (Rust), Gemini CLI (Seatbelt/Docker)
- **Shortcuts help panel** — Codex CLI, Gemini CLI, OpenCode all show key hints

### Medium-priority gaps
- **Per-project config** — most competitors have `.agent/` directory support
- **Image support** — Claude Code and Gemini CLI handle images
- **Web search tool** — Claude Code, Codex CLI, Gemini CLI, Amp
- **Session forking** — OpenCode
- **VS Code extension** — Claude Code, Codex CLI, OpenCode, Amp
- **Split panes / sidebar** — OpenCode

### Low-priority / nice-to-have
- **Cloud sync** — Amp only
- **Desktop app** — OpenCode only
- **Architect/Editor split** — Aider only (not in this matrix)
- **Repo map / tree-sitter** — Aider only

---

## Sources

| Agent | Deep-dive doc | Date |
|-------|---------------|------|
| Claude Code | [claude-code-tui-ux-feature-inventory.md](2026-03-11-claude-code-tui-ux-feature-inventory.md) | 2026-03-11 |
| Codex CLI | [openai-codex-cli-feature-inventory.md](2026-03-11-openai-codex-cli-feature-inventory.md) | 2026-03-11 |
| OpenCode + Amp | [opencode-amp-tui-ux-research.md](2026-03-11-opencode-amp-tui-ux-research.md) | 2026-03-11 |
| Landscape (all) | [ai-coding-cli-tui-landscape.md](2026-03-11-ai-coding-cli-tui-landscape.md) | 2026-03-11 |
| Gemini CLI | [gemini-cli-feature-inventory.md](2026-03-12-gemini-cli-feature-inventory.md) | 2026-03-12 |
| Skaffen | Source code at `os/Skaffen/` | 2026-03-12 |

---

## Adding a New Agent

1. Create a deep-dive doc: `docs/research/YYYY-MM-DD-<agent>-feature-inventory.md`
2. Add a column to every table above
3. Fill cells using the status key (Y/P/N/?/planned)
4. Add any unique features to Section 13
5. Update the gap analysis in the final section
6. Add the source to the Sources table
7. Update the "Last updated" date at the top
