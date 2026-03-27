# Coding Agent TUI Feature Matrix

> Continuously updated competitive comparison across major AI coding agent CLIs/TUIs.
> Last updated: 2026-03-12 (deep research refresh)
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
| **Developer** | Sylveste | Anthropic | OpenAI | Google | Anomaly | Sourcegraph |
| **Language** | Go | TypeScript | Rust | TypeScript | TS/Zig (OpenTUI) | TypeScript |
| **TUI Framework** | Bubble Tea | Ink (React) | Ratatui | Ink | OpenTUI (SolidJS) | Custom TUI |
| **License** | Proprietary | Proprietary | Apache 2.0 | Apache 2.0 | Open source | Closed source |
| **Default Model** | Sonnet 4.6 | Sonnet 4.6 | GPT-5.4 | Gemini 3 (auto-routed) | Configurable | Claude Opus 4.6 |
| **Stars (GitHub)** | — | — | 64.9K | — | 112K | — |

---

## 1. Slash Commands

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Slash command system** | Y (16 cmds) | Y (46 cmds + 5 skills) | Y (28 cmds) | Y (33+ cmds) | Y (17 cmds) | P (15 palette actions) |
| **`/help`** | Y | Y | N (no `/help`) | Y | Y | Y (palette) |
| **`/model` switching** | Y | Y (`/model` + arrow effort) | Y (`/model`) | Y (`/model`) | Y (`/models` dialog) | P (`Ctrl+S` mode switch) |
| **`/diff` git diff** | Y | Y (interactive viewer) | Y (`/diff`) | Y (`/diff`) | P (session timeline) | N |
| **`/commit`** | Y | N (agent does it) | N | N | N | N |
| **`/undo` last commit** | Y | Y (`/rewind` + checkpoint) | N | Y (`/restore`) | Y (`/undo` file revert) | N |
| **`/push` / `/ship`** | Y | N | N | N | N | N |
| **`/compact` / `/compress`** | Y | Y (`/compact` + auto) | Y (`/compact` + auto) | Y (`/compress` + auto) | Y (`/compact` + auto) | N (use handoff) |
| **`/settings` interactive** | Y (overlay) | Y (`/config`) | P (`/debug-config`) | Y (`/settings`) | N | N |
| **`/theme` switching** | Y | Y (`/theme`) | Y (`/theme` + .tmTheme) | Y (`/theme`) | Y (`/themes`) | Y (palette) |
| **`/phase` / `/advance`** | Y (OODARC) | N | N | N | N | N |
| **`/status` session info** | Y | Y (`/status` + `/cost` + `/usage` + `/stats`) | Y (`/status`) | Y (`/stats`) | P (`<leader>s`) | N |
| **`/sessions` list** | Y | Y (`/resume` picker) | Y (`/resume` picker) | Y (`/sessions`) | Y (`/sessions` dialog) | Y (cloud threads) |
| **`/clear` viewport** | Y | Y (`/clear` + `/reset` + `/new`) | Y (`/clear`) | Y | Y (`/new`) | N |
| **`/version`** | Y | Y (`/status`) | N | Y | N | N |
| **`/quit`** | Y | Y (`/exit` + `/quit`) | Y (`/exit` + `/quit`) | Y | Y (`/exit`) | N |
| **`/permissions` toggle** | N | Y (`/permissions`) | Y (`/permissions`) | Y (`/permissions`) | N | N |
| **`/init` project setup** | N | Y (`/init` CLAUDE.md) | Y (`/init` AGENTS.md) | Y (`/init`) | Y (`/init` AGENTS.md) | N |
| **`/plan` mode** | N | Y (`/plan`) | Y (`/plan`) | Y (read-only research) | N (Plan agent) | N |
| **`/review` code review** | N | P (`/security-review`) | Y (`/review` 3 modes) | N | N | Y (`amp review`) |
| **`/fork` session** | N | Y (`/fork`) | Y (`/fork`) | N | P (SDK only) | N (deprecated) |
| **`/export` conversation** | N | Y (`/export`) | N | N | Y (`/export` MD) | N |
| **`/copy` last response** | N | Y (`/copy`) | Y (`/copy`) | N | N | N |
| **`/context` visualization** | N | Y (colored grid) | N | N | N | N |
| **`/share` session URL** | N | N | N | N | Y (`/share`) | Y (thread visibility) |
| **`/extensions` management** | N | Y (`/plugin`) | P (`/apps`) | Y (install/enable/disable) | N | N |
| **`/skills` management** | N | Y (`/skills`) | Y (`/skills`) | Y (enable/disable/reload) | N | Y (palette) |
| **`/hooks` management** | N | Y (`/hooks`) | N | Y (enable/disable/list) | N | N |
| **Custom slash commands** | N | Y (skills + legacy commands) | P (skills, no slash) | Y (TOML files) | Y (MD files) | N (skills replace) |
| **MCP prompts as commands** | N | Y (auto-discovered) | N | Y | N | N |
| **Command completion popup** | Y (filtered list) | Y (fuzzy `/` filter) | Y (popup picker) | Y (Tab) | Y (dialog) | Y (Ctrl+O palette) |

---

## 2. Hooks & Extensions

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Hook system** | N | Y (17 events) | P (5 events, experimental) | Y (11 events) | Y (28 plugin events) | P (2 events) |
| **SessionStart hook** | N | Y | Y | Y | Y (`session.created`) | N |
| **PreToolUse hook** | N | Y (`PreToolUse`) | N | Y (pre-tool) | Y (`tool.execute.before`) | Y (`tool:pre-execute`) |
| **PostToolUse hook** | N | Y (`PostToolUse` + Failure) | N | Y (post-tool) | Y (`tool.execute.after`) | Y (`tool:post-execute`) |
| **UserPromptSubmit hook** | N | Y | N | N | N | N |
| **Stop / SessionEnd hook** | N | Y (both) | Y (`Stop`) | Y | Y (`session.idle`) | N |
| **Notification hook** | N | Y (4 types) | N | Y | Y (`tui.toast.show`) | N |
| **Permission hooks** | N | Y (`PermissionRequest`) | N | Y (policy engine) | Y (`permission.*`) | N |
| **SubagentStart/Stop hooks** | N | Y (both) | N | N | N | N |
| **PreCompact hook** | N | Y | N | N | Y (`session.compacting`) | N |
| **Config/Instructions hooks** | N | Y (`ConfigChange`, `InstructionsLoaded`) | N | N | N | N |
| **WorktreeCreate/Remove hooks** | N | Y (both) | N | N | N | N |
| **TeammateIdle hook** | N | Y | N | N | N | N |
| **BeforeModel / AfterModel** | N | N | N | Y (mock/redact) | N | N |
| **BeforeToolSelection** | N | N | N | Y (filter tools) | N | N |
| **File change hooks** | N | N | N | N | Y (`file.edited`, `file.watcher`) | N |
| **LSP event hooks** | N | N | N | N | Y (`lsp.*`) | N |
| **Hook handler types** | — | 4+ (cmd, HTTP, prompt, agent) | 1 (command) | 2 (command, JSON) | JS/TS functions | 2 (send-msg, redact) |
| **Plugin/extension system** | Y (MCP only) | Y (7 component types) | Y (skills + plugins) | Y (extensions gallery) | Y (JS/TS plugin API) | P (skills + MCP + toolbox) |
| **Custom tool registration** | Y (MCP) | Y (MCP + plugins + LSP) | Y (MCP + MCP-server mode) | Y (MCP + extensions) | Y (custom tools + MCP) | Y (MCP + toolbox scripts) |
| **Policy engine** | N | P (permission rules) | Y (Starlark execpolicy) | Y (TOML, 5-tier priority) | P (permission rules) | P (ordered rules) |
| **Extensions gallery** | N | Y (plugin marketplace, 7 sources) | Y (plugin marketplace) | Y (browse/install) | N | N |
| **Skills system** | N | Y (SKILL.md + frontmatter) | Y (SKILL.md, 6 discovery paths) | Y (SKILL.md) | Y (SKILL.md, 6 paths) | Y (SKILL.md + git install) |

---

## 3. UI/UX & Layout

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **TUI type** | Full-screen | Full-screen | Full-screen (alt-screen) | REPL-style | Full-screen | Full-screen TUI |
| **Split panes** | N | N | N | N | Y (sidebar) | N |
| **Scrollable viewport** | Y | Y | Y | Y (scroll history) | Y | Y |
| **Status bar** | Y (phase, model, cost, ctx%, turns) | Y (model, cost, context, PR status) | Y (mode, context, configurable items) | Y (model, tokens) | Y (agent, model, ctx%) | P (minimal) |
| **Markdown rendering** | Y (headers, code, lists) | Y (Shiki syntax) | Y (syntax-highlighted) | Y (markdown) | Y (rich markdown) | Y |
| **Diff display** | Y (inline preview) | Y (interactive per-turn diff viewer) | Y (colorized, syntax-highlighted) | Y | Y (session timeline) | Y |
| **Progress indicators** | Y (streaming text) | Y (spinner + streaming + progress bar) | Y (spinner + animations) | Y (spinner) | Y (spinner) | Y (streaming + audio notify) |
| **Themes** | Y (Masaq: Tokyo Night, Catppuccin, etc.) | Y (light/dark/daltonized/ANSI) | Y (built-in + `.tmTheme`) | Y (built-in themes) | Y (11 built-in, JSON custom) | Y (8 built-in, TOML custom) |
| **Runtime theme switching** | Y (`/theme`) | Y (`/theme`) | Y (`/theme`) | Y (`/theme`) | Y (`/themes`) | Y (palette) |
| **Dark/Light mode** | Y (auto-detect) | Y (auto-detect + daltonized) | Y | Y | Y | Y |
| **Logo/splash animation** | Y (particle swarm) | N | N | N | N | N |
| **Overlay dialogs** | Y (settings, tool approval) | Y (permission, context viz) | Y (approval, slash picker) | Y (tool approval) | Y (11+ overlays) | N |
| **Vim mode** | N | Y (full vim: modes, motions, text objects) | N | Y (`/vim`) | N | N |
| **External editor** | N | Y (`Ctrl+G`) | Y (`Ctrl+G`) | Y (`Ctrl+X`) | Y (`/editor`) | Y (`Ctrl+G`) |
| **Image support** | N | Y (paste `Ctrl+V` + @ref + PDF) | Y (`-i` flag, PNG/JPEG) | Y (inline images) | P (drag-drop, evolving) | Y (paste + @ref + `look_at`) |
| **Desktop app** | N | Y (macOS/Windows via `/desktop`) | Y (`codex app` macOS) | N | Y (Tauri + Electron) | N |
| **Web client** | N | Y (claude.ai/code) | Y (cloud exec) | N | Y (`opencode web`) | Y (ampcode.com/threads) |
| **VS Code extension** | N | Y (native, graphical panel) | Y (official + Cursor/Windsurf) | Y (IDE companion) | Y (+ Cursor/Windsurf/VSCodium) | P (discontinued, CLI-only) |
| **JetBrains plugin** | N | Y (beta) | P (community bridge) | N | Y (via ACP) | Y (`--jetbrains` flag) |
| **Neovim plugin** | N | N | N | N | Y (community `opencode.nvim`) | Y (`amp.nvim`) |
| **Background shells** | N | N | Y (`/ps`) | Y (`Ctrl+B`, Tab focus) | N | N |
| **Subagents** | N | Y (5+ built-in, custom, background) | Y (experimental, 6 threads) | Y (4 built-in + custom) | Y (4 built-in + custom) | Y (6 subagent types) |
| **Agent teams** | N | Y (experimental, multi-instance) | N | N | N | N |
| **Screen reader mode** | N | N | N | Y (`--screen-reader`) | N | N |
| **Color depth** | True color (24-bit) | True color (24-bit) | True color | True color | True color | True color |
| **Mermaid diagrams** | N | N | N | N | N | Y (interactive, clickable) |
| **Output styles** | N | Y (configurable system prompt style) | Y (`/personality` 3 modes) | N | N | N |
| **Side questions** | N | Y (`/btw` — ephemeral) | N | N | N | N |

---

## 4. Keyboard Shortcuts

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Total keybindings** | ~10 | 30+ | 14+ | 20+ | 70+ | 12+ |
| **Enter to submit** | Y | Y | Y | Y | Y | Y |
| **Shift+Enter newline** | Y | Y (+ `\Enter`, `Ctrl+J`, `Option+Enter`) | P (external editor only) | Y (+ Ctrl+Enter, Alt+Enter, Ctrl+J) | Y (+ Ctrl+Return, Alt+Return) | Y |
| **External editor** | N | Y (`Ctrl+G`) | Y (`Ctrl+G`) | Y (`Ctrl+X`) | Y (`/editor`) | Y (`Ctrl+G`) |
| **History search** | N | Y (`Ctrl+R`) | N (Up/Down + Esc backtrack) | Y (`Ctrl+R`, `Ctrl+P/N`) | N (Up/Down) | Y (`Ctrl+R`) |
| **Shell escape (`!`)** | N | Y (`!` prefix) | Y (`!` prefix) | Y (`!` prefix) | Y (`!` prefix) | Y (`$` / `$$` prefix) |
| **Scroll: PageUp/Down** | Y | Y | Y | Y | Y | N |
| **Scroll: Ctrl+U/D** | Y | Y | N | N | Y | N |
| **Scroll: mouse wheel** | Y | Y | Y | Y | Y | N |
| **Approval mode toggle** | N | Y (`Shift+Tab` / `Alt+M`) | N | Y (`Shift+Tab`) | N | N |
| **Kill agents** | N | Y (`Ctrl+F` ×2) | N | N | N | N |
| **Toggle task list** | N | Y (`Ctrl+T`) | N | N | N | N |
| **Verbose output toggle** | N | Y (`Ctrl+O`) | N | N | N | N |
| **Model switch shortcut** | N | Y (`Alt+P`) | N | N | Y (F2 cycle) | Y (`Ctrl+S`) |
| **Thinking toggle** | N | Y (`Alt+T`) | N | N | Y (`Ctrl+T` variant) | Y (`Alt+D`) |
| **Shortcuts help panel** | N | N | Y (dynamic hints) | Y (`?` toggle) | Y (`?`) | Y (`amp: help`) |
| **Custom keybindings** | N | Y (`keybindings.json`) | N | Y (`keybindings.json`) | Y (`tui.json`) | N |
| **Leader key system** | N | N | N | N | Y (`Ctrl+X` default) | N |
| **File picker trigger** | Y (`@`) | Y (`@` + Tab) | Y (`@`) | Y (`@`) | Y (`@`) | Y (`@`) |
| **Thread mention** | N | N | N | N | N | Y (`@@`) |
| **Command picker trigger** | Y (`/`) | Y (`/`) | Y (`/`) | Y (`/`) | Y (`/`) | Y (`Ctrl+O`) |
| **Skill picker** | N | N | Y (`$` prefix) | N | N | N |

---

## 5. Model Routing

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Phase-based routing** | Y (OODARC: brainstorm→ship) | N | N | N | N | N |
| **Automatic model routing** | N | N | N | Y (lite model decides) | N | Y (per-task model selection) |
| **Mid-session model switch** | Y (`/model`) | Y (`/model` + arrow effort) | Y (`/model`) | Y (`/model`) | Y (dialog + F2) | P (mode switch only) |
| **Multi-model ensemble** | N | P (`opusplan` hybrid) | N | Y (auto: flash+pro) | N | Y (7+ models, 4 providers) |
| **Effort levels** | N | Y (low/medium/high) | Y (minimal→xhigh, 5 levels) | N | Y (per-provider variants) | Y (low→max, 4 levels) |
| **Budget tracking** | Y (cost + context %) | Y (cost + context + `/usage`) | Y (context + token counters) | Y (token stats) | Y (context % + `opencode stats`) | Y (per-thread cost) |
| **Budget degradation** | Y (configurable threshold) | N | N | N | N | N |
| **Complexity routing** | Y (shadow/enforce modes) | N | N | Y (lite model triage) | N | N |
| **Model aliases** | Y (opus/sonnet/haiku) | Y (6 aliases + `opusplan`) | Y (11+ models) | Y | Y (provider/model format) | P (6 modes, not configurable) |
| **Per-phase env override** | Y (`SKAFFEN_MODEL_<PHASE>`) | Y (`ANTHROPIC_MODEL` + overrides) | Y (profiles) | N | N | N |
| **Context window config** | Y (per-model in routing.json) | Y (200K standard, 1M beta) | Y (`model_context_window`) | Y (validation on switch) | N (auto) | P (200K / 1M in large mode) |
| **Extended thinking** | N | Y (default on, 31K budget) | Y (5 effort levels) | N | Y (per-provider variants) | Y (configurable effort) |
| **Fast mode** | N | Y (`/fast` toggle) | Y (`/fast` toggle) | N | N | Y (rush mode) |
| **Custom providers** | N | Y (Bedrock, Vertex, Foundry) | Y (any OpenAI-compatible) | P (Vertex only) | Y (41 named + any compatible) | N (Amp controls models) |

---

## 6. Session Management

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Session persistence** | Y (JSONL) | Y (JSONL) | Y (JSONL) | Y (JSON) | Y (local DB) | Y (cloud) |
| **Resume last session** | Y (`-c` flag) | Y (`claude -c`) | Y (`codex resume --last`) | Y (`--resume`) | Y | Y (`amp threads continue`) |
| **Resume by ID** | Y (`-r <id>`) | Y (`claude -r <id>`) | Y (`codex resume <id>`) | Y (interactive browser) | Y | Y (`amp threads continue <id>`) |
| **Session browser** | Y (`/sessions`) | Y (`/resume` picker) | Y (`codex resume` picker) | Y (interactive) | Y (`/sessions` dialog) | Y (ampcode.com web UI) |
| **Context compaction** | N | Y (`/compact` + auto 95%) | Y (`/compact` + auto 95%) | Y (`/compress` + auto 50%) | Y (`/compact` + auto 75%) | N (handoff instead) |
| **Manual compaction** | N | Y | Y | Y (`/compress`) | Y | N |
| **Session forking** | N | Y (`/fork`) | Y (`/fork` + `codex fork`) | N | Y (SDK + `--fork`) | N (deprecated, use handoff) |
| **Session naming/rename** | Y (`-session <id>`) | Y (`/rename`) | N | Y | Y | Y (threads) |
| **Session export** | N | Y (`/export` text + JSON) | N | N | Y (`/export` MD/JSON + import) | N |
| **Session sharing** | N | N | N | N | Y (`/share` URL) | Y (thread visibility controls) |
| **Session teleportation** | N | Y (CLI ↔ web ↔ mobile) | Y (cloud exec + apply) | N | N | Y (cross-device threads) |
| **Cloud sync** | N | P (web sessions) | Y (cloud exec) | N | N | Y (all threads) |
| **Session retention policy** | N | Y (`cleanupPeriodDays`) | Y (`history.max_bytes`) | Y (30d default, configurable) | N | N |
| **Max turns config** | Y (`-max-turns`) | Y (`--max-turns`) | N | N | N | N |
| **Max budget config** | N | Y (`--max-budget-usd`) | N | N | N | N |

---

## 7. Tool System

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Built-in tools** | 7 | 15 | 6 | 14 | 15 | 45-50 |
| **Phase gating** | Y (5-phase matrix) | N | N | N | N | N |
| **MCP support** | Y (stdio) | Y (stdio + SSE + HTTP) | Y (stdio + HTTP) | Y (stdio + SSE + HTTP) | Y (local + remote + OAuth) | Y (local + remote + OAuth) |
| **MCP server mode** | N | N | Y (`codex mcp-server`) | N | P (community package) | N |
| **Tool approval** | Y (Yes/No/Always) | Y (3-tier: read/bash/write) | Y (sandbox + approval layers) | Y (per-tool policies) | Y (14 permission types) | Y (4 actions: allow/reject/ask/delegate) |
| **Diff preview on approval** | Y (configurable) | Y | Y (colorized) | N | Y | N |
| **Sandbox/isolation** | N | Y (Seatbelt/bwrap + network proxy) | Y (Seatbelt/Landlock/bwrap/Windows) | Y (Seatbelt/Docker/gVisor/LXC) | N (UX-only permissions) | N (permission rules only) |
| **Tool include/exclude** | N | Y (permission rules) | Y (`enabled_tools`/`disabled_tools`) | Y (per MCP server) | Y (per-agent tool enable) | Y (`amp.tools.enable/disable`) |
| **LSP integration** | N | Y (plugin LSP servers) | P (diagnostics) | N | Y (24 built-in LSP servers) | P (`get_diagnostics`) |
| **Web search tool** | N | Y (`WebSearch` + `WebFetch`) | Y (cached or live) | Y (Google grounding) | P (Exa, requires flag) | Y (`web_search` + `read_web_page`) |
| **JS REPL** | N | N | Y (`js_repl`) | N | N | Y (`repl`) |
| **Image generation** | N | N | Y | N | N | Y (`painter` via Gemini) |
| **Code search (remote)** | N | N | N | N | N | Y (GitHub + Bitbucket, 14 tools) |
| **Auto-formatting** | N | N | N | N | Y (26 built-in formatters) | N |

---

## 8. Git Integration

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Auto-commit** | Y (`/commit`) | Y (agent-driven + attribution) | P (co-author trailer only) | N | N | P (co-author trailer) |
| **Undo last commit** | Y (`/undo`) | Y (`/rewind` checkpoint) | N | Y (`/restore`) | Y (`/undo` file revert) | Y (`undo_edit` tool) |
| **Push** | Y (`/ship`) | Y (agent-driven) | N | N | N | N |
| **Diff viewing** | Y (`/diff`) | Y (interactive per-turn viewer) | Y (`/diff` + `/review`) | Y | P (session timeline) | Y (`diff` tool) |
| **Branch awareness** | Y (status bar) | Y (status bar + worktree) | Y (protected `.git`) | Y | Y | N |
| **Git worktrees** | N | Y (`-w` flag, subagent isolation) | N | N | P (community plugins) | N |
| **PR creation** | N | Y (agent + auto-link sessions) | N (uses `gh` via shell) | N | N | N (uses `gh` via patterns) |
| **PR review** | N | Y (`/pr-comments` + `/security-review`) | Y (`/review` 3 modes) | N | N | Y (`amp review` + checks) |
| **PR status display** | N | Y (colored underline, auto-refresh) | N | N | N | N |
| **Commit search** | N | N | N | N | N | Y (`commit_search` tool) |
| **Code review checks** | N | N | N | N | N | Y (`.agents/checks/` composable) |
| **Commit attribution config** | N | Y (`attribution` setting) | Y (`commit_attribution` TOML) | N | N | Y (`amp.git.commit.*`) |

---

## 9. File Mentions & Context

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **`@file` references** | Y (picker + expansion) | Y (tab-complete + `fileSuggestion`) | Y (fuzzy search) | Y | Y (fuzzy search) | Y (fuzzy + glob patterns) |
| **`@directory` references** | N | Y | N | Y | N | N |
| **File picker UI** | Y (filtered, 10 items) | Y (tab-complete) | Y (popup) | Y | Y (fuzzy search) | Y |
| **Max file size** | 50KB | No hard limit (paginated PDFs) | Lazy loading | ? | ? | 1000-line default |
| **Image references** | N | Y (clipboard + file) | Y (`-i` flag) | Y (inline) | P (drag-drop) | Y (clipboard + file + `look_at`) |
| **PDF support** | N | Y (up to 20 pages/request) | N | Y | N | Y (via `look_at`) |
| **Jupyter notebook support** | N | Y (`NotebookEdit` tool) | N | N | N | N |
| **Stdin piping** | Y (`-p` flag) | Y (`-p` flag) | Y (positional/stdin) | Y (pipe) | Y (`opencode run`) | Y (`echo | amp -x`) |
| **Instruction files** | N | Y (CLAUDE.md, 3+ scopes + rules/) | Y (AGENTS.md, per-dir + override) | Y (GEMINI.md) | Y (AGENTS.md + CLAUDE.md compat) | Y (AGENTS.md + globs frontmatter) |
| **Instruction file imports** | N | Y (`@path/to/import`, max depth 5) | N | N | Y (globs, remote URLs) | N |
| **Managed/admin instructions** | N | Y (`/etc/claude-code/CLAUDE.md`) | N | N | N | Y (managed-settings paths) |

---

## 10. Configuration

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Config format** | JSON (`routing.json`) | JSON (`settings.json`) | TOML (`config.toml`) | JSON (`settings.json`) | JSON/JSONC (`opencode.json`) | JSON (`settings.json`) |
| **Config hierarchy levels** | 1 | 5 (managed→CLI→local→project→user) | 5 (CLI→`-c`→project→user→defaults) | 3+ | 6 (remote→global→custom→project→dir→inline) | 4 (managed→user→project→workspace) |
| **Per-project config** | N | Y (`.claude/`) | Y (`.codex/`, trusted only) | Y (`.gemini/`) | Y (`.opencode/`) | Y (`.amp/`) |
| **Environment variables** | Y (`SKAFFEN_MODEL_*`) | Y (60+ vars) | Y (`CODEX_HOME`, `OPENAI_*`) | Y (`GEMINI_*`) | Y (`OPENCODE_*`) | Y (23 `AMP_*` vars) |
| **Plugin config** | Y (`plugins.toml`) | Y (7 plugin source types) | Y (plugin marketplace) | Y (MCP in settings) | Y (JS/TS plugin API + npm) | Y (MCP + toolbox + skills) |
| **Settings UI** | Y (interactive overlay) | Y (`/config`) | P (`/debug-config`) | Y (`/settings`) | N | N |
| **Profiles** | N | N | Y (named config profiles) | N | N | N |
| **Auto memory** | N | Y (MEMORY.md + topic files) | Y (MEMORY.md + skills, SQLite) | N | N | Y (`save_memory` tool) |

---

## 11. Approval & Autonomy

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Approval model** | Per-tool (Yes/No/Always) | 5 modes (default→bypass) | 2-layer (sandbox × approval) | Policy engine (YAML rules) | 14 permission types | Ordered rules (4 actions) |
| **Full-auto mode** | N | Y (`bypassPermissions`) | Y (`--yolo` / `--full-auto`) | Y (auto-edit mode) | N | Y (`--dangerously-allow-all`) |
| **Mid-session mode toggle** | N | Y (`Shift+Tab`) | Y (`/permissions`) | Y (`Shift+Tab`) | N | N |
| **Per-tool policies** | N | Y (permission rules) | Y (Starlark execpolicy) | Y (YAML per tool/server) | Y (per-permission-type rules) | Y (ordered rules + delegate) |
| **Trust escalation** | Y (Always for session) | Y (permanent per project) | Y (rules auto-proposed) | Y (Allow future sessions) | Y (always option) | Y (allow rule) |
| **Delegate to external** | N | N | N | N | N | Y (external program decides) |
| **Secret redaction** | N | N | N | Y (env var redaction) | N | Y (auto-detect 8+ formats) |
| **Protected paths** | N | N | Y (`.git`, `.agents`, `.codex`) | N | Y (`.env` deny by default) | Y (guarded files) |

---

## 12. Provider & Auth

| Feature | Skaffen | Claude Code | Codex CLI | Gemini CLI | OpenCode | Amp |
|---------|---------|-------------|-----------|------------|----------|-----|
| **Providers supported** | 2 (Anthropic, Claude Code proxy) | 4 (Anthropic + Bedrock + Vertex + Foundry) | Many (OpenAI + any compatible + Ollama/LM Studio) | 2 (Gemini + Vertex) | 41+ named (+ any OpenAI-compatible) | 7+ (Anthropic, OpenAI, Google, Fireworks, Bedrock, Baseten, xAI) |
| **Free tier** | N | N | Y (ChatGPT account) | Y (60 req/min, 1K/day) | N (BYOK) | P (admissions paused) |
| **API key auth** | Y | Y | Y | Y | Y | Y (`AMP_API_KEY`) |
| **OAuth / Google login** | N | Y (Anthropic OAuth) | Y (OAuth) | Y | N | Y |
| **Enterprise / managed** | N | Y (managed settings, MDM) | Y (Azure, profiles) | Y (Vertex AI) | N | Y (SSO, SCIM, managed settings) |
| **Rate limit display** | N | Y (`/usage`) | Y (`/status` + statusline) | Y (`/stats model`) | N | Y (`amp usage`) |
| **Local model support** | N | N | Y (Ollama, LM Studio, MLX, gpt-oss) | N | Y (Ollama, llama.cpp, LM Studio) | N |
| **BYOK (bring your own key)** | Y | Y | Y | Y | Y | N (removed May 2025) |
| **OpenTelemetry** | N | Y (metrics + logs) | Y (traces + metrics) | N | N | P (tracing via env) |

---

## 13. Unique / Differentiating Features

| Feature | Agent | Description |
|---------|-------|-------------|
| **OODARC phase workflow** | Skaffen | 5-phase FSM (brainstorm→plan→build→review→ship) with per-phase tool gating and model routing |
| **Particle logo animation** | Skaffen | 48-particle HSV→brand-color swarm on startup |
| **Game of Life easter egg** | Skaffen | *planned* — true-color background layer (Sylveste-oyi) |
| **Evidence pipeline** | Skaffen | JSONL event emission bridging to Interspect |
| **Budget degradation** | Skaffen | Configurable model downgrade when approaching cost/context thresholds |
| **46 slash commands** | Claude Code | Most extensive built-in command set + 5 bundled skills |
| **17 hook events** | Claude Code | Most comprehensive hook lifecycle (incl. SubagentStart/Stop, TeammateIdle, WorktreeCreate/Remove, PreCompact) |
| **Plugin ecosystem** | Claude Code | 7 component types (skills, agents, hooks, MCP, LSP, commands, settings), 7 marketplace sources |
| **Session teleportation** | Claude Code | Move sessions between CLI ↔ web ↔ mobile; remote control |
| **Agent teams** | Claude Code | Multi-instance parallel coordination with git-based merging |
| **Rewind/checkpoint** | Claude Code | Automatic checkpoints before each prompt; restore code/conversation independently |
| **Context visualization** | Claude Code | `/context` colored grid with optimization suggestions |
| **Full vim mode** | Claude Code | 30+ vim commands with modes, motions, text objects |
| **Side questions (`/btw`)** | Claude Code | Ephemeral overlay questions that don't affect conversation history |
| **Starlark execution policy** | Codex CLI | Declarative rule files for fine-grained command approval |
| **4-platform sandbox** | Codex CLI | Seatbelt (macOS), Landlock+seccomp (Linux), bwrap (opt-in), Windows (experimental) |
| **Memory system** | Codex CLI | Two-phase async pipeline: rollout extraction → global consolidation → auto-generated skills |
| **Cloud execution** | Codex CLI | `codex cloud exec` with best-of-N runs, `codex apply` for local diff |
| **MCP server mode** | Codex CLI | `codex mcp-server` exposes Codex as MCP server for other agents |
| **Transcript backtracking** | Codex CLI | Esc×2 walks backward through user messages; Enter to fork from any point |
| **Session forking** | Codex CLI | `/fork` + `codex fork` for cloning conversations |
| **Google Search grounding** | Gemini CLI | Real-time web verification during coding |
| **1M token context** | Gemini CLI | Largest context window of any CLI agent |
| **Automatic model routing** | Gemini CLI | Lite model triages to flash/pro per-request |
| **Policy engine (TOML)** | Gemini CLI | 5-tier priority YAML-based per-tool security policies |
| **MCP prompts as commands** | Gemini CLI | MCP server prompts exposed as slash commands |
| **BeforeModel/AfterModel hooks** | Gemini CLI | Mock or redact model responses; unique hook events |
| **Background shells** | Gemini CLI | Concurrent shell processes with Tab focus switching |
| **Browser agent** | Gemini CLI | Chrome automation via computer-use model |
| **Agent-to-Agent (A2A)** | Gemini CLI | Remote agent delegation over HTTP |
| **Extensions gallery** | Gemini CLI | Community extension discovery and install |
| **4-backend sandbox** | Gemini CLI | Seatbelt, Docker/Podman, gVisor, LXC |
| **OpenTUI framework** | OpenCode | Custom Zig core + SolidJS reactivity; replaced Bubble Tea |
| **28 plugin event types** | OpenCode | Most granular event system (file, LSP, message, session, TUI events) |
| **41+ providers** | OpenCode | Broadest provider support via Models.dev catalog |
| **24 built-in LSP servers** | OpenCode | Auto-install language servers for real-time diagnostics |
| **26 built-in formatters** | OpenCode | Auto-format after every file write/edit |
| **5 deployment modes** | OpenCode | TUI, Tauri desktop, web browser, headless HTTP, ACP protocol |
| **7+ IDE integrations** | OpenCode | VS Code, Cursor, Windsurf, VSCodium, Zed, JetBrains, Neovim |
| **Agent Client Protocol** | OpenCode | ACP server over stdin/stdout for IDE integration |
| **Session sharing URLs** | OpenCode | `/share` generates public URLs at opncd.com |
| **45-50 built-in tools** | Amp | Largest tool set (incl. 7 GitHub tools, 7 Bitbucket tools, painter, mermaid, oracle) |
| **Multi-model ensemble** | Amp | 7+ models from 4+ providers, each optimized per task type |
| **Cloud-synced threads** | Amp | Cross-device session sharing via ampcode.com |
| **Composable code review** | Amp | `.agents/checks/` with per-check subagents and severity levels |
| **Toolbox system** | Amp | Simple executable-based custom tools (stdin/stdout protocol) |
| **6 agent modes** | Amp | smart/rush/deep/large/free/bombadil — most flexible mode selection |
| **Mermaid + walkthrough** | Amp | Interactive diagrams and annotated code explorations |
| **Painter tool** | Amp | AI image generation (Gemini 3 Pro Image) — unique among CLI agents |
| **Thread Map** | Amp | Visual graph of conversation relationships |
| **Secret auto-redaction** | Amp | Detects 8+ credential formats and replaces with `[REDACTED:amp]` |

---

## Skaffen Gap Analysis

### Skaffen-unique strengths (no competitor has)
- OODARC phase workflow with per-phase tool gating and model routing
- Budget degradation thresholds
- Per-phase model routing via env vars
- Particle swarm logo animation
- `/commit`, `/undo`, `/ship` git commands (dedicated, not agent-driven)
- Evidence pipeline (structured event emission to Interspect)
- Max turns configuration at CLI level

### Critical gaps (4+ competitors have, Skaffen doesn't)
- **Hook system** — CC (17 events), Codex (5), Gemini (11), OpenCode (28), Amp (2)
- **Context compaction** — CC, Codex, Gemini, OpenCode all have manual + auto
- **Skills/instruction files** — CC (CLAUDE.md), Codex (AGENTS.md), Gemini (GEMINI.md), OpenCode (AGENTS.md), Amp (AGENTS.md)
- **Subagents** — CC (5+ built-in), Codex (6 threads), Gemini (4+), OpenCode (4+), Amp (6 types)
- **External editor** — CC, Codex, Gemini, OpenCode, Amp all support `Ctrl+G` or similar
- **Shell escape (`!` prefix)** — CC, Codex, Gemini, OpenCode, Amp
- **Sandbox/isolation** — CC (Seatbelt/bwrap), Codex (4 platforms), Gemini (4 backends)
- **Image support** — CC, Codex, Gemini, Amp all handle images; OpenCode partial
- **Web search tool** — CC, Codex, Gemini, Amp all have built-in web search
- **Skills system (SKILL.md)** — CC, Codex, Gemini, OpenCode, Amp all have skill discovery

### High-priority gaps (2-3 competitors have)
- **Custom slash commands** — CC (skills), Codex (skills), Gemini (TOML), OpenCode (MD files)
- **Vim mode** — CC (full), Gemini (`/vim`)
- **History search** — CC (`Ctrl+R`), Gemini (`Ctrl+R`), Amp (`Ctrl+R`)
- **Session forking** — CC, Codex, OpenCode
- **Per-project config** — CC, Codex, Gemini, OpenCode, Amp
- **VS Code extension** — CC, Codex, Gemini, OpenCode
- **Plan mode** — CC (`/plan`), Codex (`/plan`), Gemini (read-only), Amp (deep mode)
- **Session export** — CC, OpenCode
- **PR review tools** — CC (`/pr-comments`), Codex (`/review`), Amp (`amp review`)
- **Custom keybindings** — CC, Gemini, OpenCode

### Medium-priority gaps
- **Split panes / sidebar** — OpenCode only
- **Mermaid diagrams** — Amp only
- **Cloud sync** — Amp (threads), CC (web sessions), Codex (cloud exec)
- **Desktop app** — CC (`/desktop`), Codex (`codex app`), OpenCode (Tauri)
- **OpenTelemetry** — CC, Codex
- **Memory system** — CC (auto-memory), Codex (two-phase), Amp (`save_memory`)
- **Secret redaction** — Gemini (env vars), Amp (8+ formats)
- **Output styles / personality** — CC (output styles), Codex (personality)
- **Auto-formatting** — OpenCode (26 formatters)

### Low-priority / nice-to-have
- **Agent teams** — CC only (experimental)
- **Session teleportation** — CC only
- **Browser agent** — Gemini only
- **A2A protocol** — Gemini only
- **Thread Map** — Amp only
- **Image generation** — Codex, Amp

---

## Sources

| Agent | Deep-dive doc | Date |
|-------|---------------|------|
| Claude Code | [2026-03-12-claude-code-feature-inventory.md](2026-03-12-claude-code-feature-inventory.md) | 2026-03-12 |
| Codex CLI | [2026-03-12-codex-cli-feature-inventory.md](2026-03-12-codex-cli-feature-inventory.md) | 2026-03-12 |
| OpenCode | [2026-03-12-opencode-feature-inventory.md](2026-03-12-opencode-feature-inventory.md) | 2026-03-12 |
| Amp | [2026-03-12-amp-feature-inventory.md](2026-03-12-amp-feature-inventory.md) | 2026-03-12 |
| Gemini CLI | [2026-03-12-gemini-cli-feature-inventory.md](2026-03-12-gemini-cli-feature-inventory.md) | 2026-03-12 |
| Landscape (all) | [2026-03-11-ai-coding-cli-tui-landscape.md](2026-03-11-ai-coding-cli-tui-landscape.md) | 2026-03-11 |
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
