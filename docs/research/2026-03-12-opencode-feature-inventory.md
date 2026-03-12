# OpenCode Feature Inventory (Deep Research 2026-03-12)

> **Project:** OpenCode (formerly sst/opencode, now anomalyco/opencode)
> **Current Version:** v1.2.24 (March 9, 2026)
> **GitHub Stars:** ~112K+ | **Contributors:** ~800 | **Monthly Active Developers:** 2.5M+
> **License:** Open source
> **Written in:** TypeScript (TUI/SDK), Zig (OpenTUI core), Go (legacy pre-v1.0)
> **Organization:** Anomaly (formerly SST)

> Sources:
> - [OpenCode Docs](https://opencode.ai/docs/)
> - [GitHub: anomalyco/opencode](https://github.com/anomalyco/opencode)
> - [OpenCode Tools](https://opencode.ai/docs/tools/)
> - [OpenCode Commands](https://opencode.ai/docs/commands/)
> - [OpenCode Keybinds](https://opencode.ai/docs/keybinds/)
> - [OpenCode TUI](https://opencode.ai/docs/tui/)
> - [OpenCode Agents](https://opencode.ai/docs/agents/)
> - [OpenCode Custom Tools](https://opencode.ai/docs/custom-tools/)
> - [OpenCode Plugins](https://opencode.ai/docs/plugins/)
> - [OpenCode Providers](https://opencode.ai/docs/providers/)
> - [OpenCode Config](https://opencode.ai/docs/config/)
> - [OpenCode Permissions](https://opencode.ai/docs/permissions/)
> - [OpenCode MCP Servers](https://opencode.ai/docs/mcp-servers/)
> - [OpenCode Themes](https://opencode.ai/docs/themes/)
> - [OpenCode CLI](https://opencode.ai/docs/cli/)
> - [OpenCode SDK](https://opencode.ai/docs/sdk/)
> - [OpenCode Rules](https://opencode.ai/docs/rules/)
> - [OpenCode Skills](https://opencode.ai/docs/skills/)
> - [OpenCode Models](https://opencode.ai/docs/models/)
> - [OpenCode LSP](https://opencode.ai/docs/lsp/)
> - [OpenCode Formatters](https://opencode.ai/docs/formatters/)
> - [OpenCode GitHub Integration](https://opencode.ai/docs/github/)
> - [OpenCode IDE Integration](https://opencode.ai/docs/ide/)
> - [OpenCode Share](https://opencode.ai/docs/share/)
> - [OpenCode ACP](https://opencode.ai/docs/acp/)
> - [OpenCode Zen](https://opencode.ai/docs/zen/)
> - [OpenCode Go](https://opencode.ai/docs/go/)
> - [OpenCode Changelog](https://opencode.ai/changelog)
> - [OpenTUI GitHub](https://github.com/anomalyco/opentui)
> - [DeepWiki: sst/opencode](https://deepwiki.com/sst/opencode/)
> - [DeepWiki: anomalyco/opencode](https://deepwiki.com/anomalyco/opencode/)

---

## 1. Slash Commands / Dialog System (17 TUI commands + unlimited custom)

OpenCode uses a **slash command system** (`/command`) in the TUI, plus a **`!` prefix** for inline shell execution and **`@` prefix** for file fuzzy-search.

### Built-in TUI Commands

| # | Command | Keybind | Description |
|---|---------|---------|-------------|
| 1 | `/compact` | `ctrl+x c` | Reduce session size via compaction |
| 2 | `/connect` | -- | Add/configure a provider |
| 3 | `/details` | `ctrl+x d` | Toggle tool execution detail display |
| 4 | `/editor` | `ctrl+x e` | Open external editor for composing messages |
| 5 | `/exit` | `ctrl+x q` | Close application |
| 6 | `/export` | `ctrl+x x` | Export conversation to Markdown |
| 7 | `/help` | `ctrl+x h` | Display command reference |
| 8 | `/init` | `ctrl+x i` | Create/update AGENTS.md |
| 9 | `/models` | `ctrl+x m` | Show available models dialog |
| 10 | `/new` | `ctrl+x n` | Start fresh session |
| 11 | `/redo` | `ctrl+x r` | Restore undone changes |
| 12 | `/sessions` | `ctrl+x l` | List and resume past conversations |
| 13 | `/share` | `ctrl+x s` | Enable session sharing (generates URL) |
| 14 | `/themes` | `ctrl+x t` | View/switch theme |
| 15 | `/thinking` | -- | Toggle reasoning block visibility |
| 16 | `/undo` | `ctrl+x u` | Revert last message and file changes |
| 17 | `/unshare` | -- | Disable session sharing |

### Custom Commands

- Defined as **markdown files** in `.opencode/commands/` (project) or `~/.config/opencode/commands/` (global)
- Can also be configured in `opencode.json` under the `command` key
- Invoked with `/` prefix followed by the command name
- No limit on custom commands

### Inline Shortcuts

- **`@`** -- fuzzy file search and auto-inclusion in prompt
- **`!`** -- execute shell commands directly from the prompt input
- **`@agent_name`** -- invoke a subagent manually (e.g., `@general help me search`)

---

## 2. Hook System (20+ event types via plugin system)

OpenCode does **not** have a standalone hooks.json like Claude Code. Instead, hooks are implemented through the **plugin system** -- plugins are JS/TS modules that export hook functions.

### Event Types (from plugin docs)

| # | Event | Description |
|---|-------|-------------|
| 1 | `command.executed` | A TUI command was executed |
| 2 | `file.edited` | A file was modified |
| 3 | `file.watcher.updated` | File watcher detected changes |
| 4 | `installation.updated` | Plugin installation updated |
| 5 | `lsp.client.diagnostics` | LSP diagnostics received |
| 6 | `lsp.updated` | LSP state changed |
| 7 | `message.part.removed` | Part of a message removed |
| 8 | `message.part.updated` | Part of a message updated |
| 9 | `message.removed` | Message deleted |
| 10 | `message.updated` | Message content changed |
| 11 | `permission.asked` | Permission prompt shown |
| 12 | `permission.replied` | User responded to permission prompt |
| 13 | `server.connected` | Server connection established |
| 14 | `session.created` | New session started |
| 15 | `session.compacted` | Session underwent compaction |
| 16 | `session.deleted` | Session removed |
| 17 | `session.diff` | File changes in session |
| 18 | `session.error` | Session error occurred |
| 19 | `session.idle` | Session became idle |
| 20 | `session.status` | Session status changed |
| 21 | `session.updated` | Session content updated |
| 22 | `shell.env` | Shell environment hook (inject env vars) |
| 23 | `todo.updated` | Todo list changed |
| 24 | `tool.execute.after` | After tool execution |
| 25 | `tool.execute.before` | Before tool execution |
| 26 | `tui.prompt.append` | Append to TUI prompt |
| 27 | `tui.command.execute` | TUI command executed |
| 28 | `tui.toast.show` | Toast notification shown |

### Experimental Hook

- `experimental.session.compacting` -- fires before compaction summary, allows injecting domain-specific context

### Plugin Configuration

- Plugins defined as JS/TS files in `.opencode/plugins/` or `~/.config/opencode/plugins/`
- Also installable as npm packages via `"plugin"` array in config
- Load order: global config -> project config -> global dir -> project dir
- Context object provides: `project`, `directory`, `worktree`, `client`, `$` (Bun shell API)
- Plugins can define custom tools that override built-in tools

---

## 3. Keyboard Shortcuts & Input (70+ keybindings)

### Leader Key System

- **Default leader:** `ctrl+x`
- All leader-prefixed shortcuts require pressing leader first, then the action key
- Leader key is fully customizable in `tui.json`

### Complete Keybindings (70+ total)

**App & Navigation (6):**
- `app_exit`: ctrl+c, ctrl+d, \<leader\>q
- `sidebar_toggle`: \<leader\>b
- `scrollbar_toggle`: none (configurable)
- `username_toggle`: none (configurable)
- `terminal_title_toggle`: none (configurable)
- `terminal_suspend`: ctrl+z

**Editor & Display (4):**
- `editor_open`: \<leader\>e
- `theme_list`: \<leader\>t
- `status_view`: \<leader\>s
- `tips_toggle` / `display_thinking`: \<leader\>h / none

**Session Management (12):**
- `session_new`: \<leader\>n
- `session_list`: \<leader\>l
- `session_timeline`: \<leader\>g
- `session_export`: \<leader\>x
- `session_fork`: none
- `session_rename`: none
- `session_share` / `session_unshare`: none / none
- `session_interrupt`: escape
- `session_compact`: \<leader\>c
- `session_child_first`: \<leader\>down
- `session_child_cycle` / `reverse`: right / left
- `session_parent`: up

**Message Navigation (14):**
- `messages_page_up`: pageup, ctrl+alt+b
- `messages_page_down`: pagedown, ctrl+alt+f
- `messages_line_up` / `down`: ctrl+alt+y / ctrl+alt+e
- `messages_half_page_up` / `down`: ctrl+alt+u / ctrl+alt+d
- `messages_first`: ctrl+g, home
- `messages_last`: ctrl+alt+g, end
- `messages_copy`: \<leader\>y
- `messages_undo` / `redo`: \<leader\>u / \<leader\>r
- `messages_toggle_conceal`: \<leader\>h

**Model & Agent (7):**
- `model_list`: \<leader\>m
- `model_cycle_recent`: f2
- `model_cycle_recent_reverse`: shift+f2
- `variant_cycle`: ctrl+t
- `agent_list`: \<leader\>a
- `agent_cycle` / `reverse`: tab / shift+tab
- `command_list`: ctrl+p

**Input Editing (30+):**
- Full cursor movement: arrows, ctrl+a/e (line home/end), home/end (buffer)
- Selection: shift+arrows, shift+home/end
- Word navigation: alt+f/b, alt+arrows, ctrl+arrows
- Deletion: backspace, ctrl+d, ctrl+k, ctrl+u, ctrl+w, alt+d
- Undo/redo: ctrl+- / ctrl+.
- Multi-line: shift+return, ctrl+return, alt+return, ctrl+j
- Paste: ctrl+v
- Clear: ctrl+c
- Submit: return
- History: up/down

### Custom Keybindings

- Configured in `tui.json` or `tui.jsonc`
- Any keybind can be disabled by setting to `"none"`
- Supports: ctrl+, alt+, shift+ combinations
- Does **not** support cmd+ on macOS (known limitation)

### Input Modes

- No built-in vim mode for the prompt editor (feature requested, not implemented as of March 2026)
- Emacs-style keybindings are the default
- External editor support via `EDITOR` env var (vim, nano, VS Code, Cursor, etc.)

---

## 4. Tool System (15 built-in + unlimited custom + MCP)

### Built-in Tools (15)

| # | Tool | Description |
|---|------|-------------|
| 1 | `bash` | Execute shell commands in project environment |
| 2 | `edit` | Modify existing files using exact string replacements |
| 3 | `write` | Create new files or overwrite existing ones |
| 4 | `read` | Read file contents (supports line ranges) |
| 5 | `grep` | Search file contents using regular expressions |
| 6 | `glob` | Find files by pattern matching |
| 7 | `list` | List files/directories with glob filtering |
| 8 | `patch` | Apply patches/diffs to files |
| 9 | `skill` | Load a SKILL.md file into conversation context |
| 10 | `todowrite` | Create/update task lists (disabled for subagents) |
| 11 | `todoread` | Read existing todo lists |
| 12 | `webfetch` | Fetch and read web pages |
| 13 | `websearch` | Search web via Exa AI (requires `OPENCODE_ENABLE_EXA=1`) |
| 14 | `question` | Ask user for input during execution |
| 15 | `lsp` | LSP code intelligence (experimental: `OPENCODE_EXPERIMENTAL_LSP_TOOL=true`) |

### Custom Tools

- Defined as TypeScript/JavaScript files in `.opencode/tools/` (project) or `~/.config/opencode/tools/`
- Uses `tool()` helper from `@opencode-ai/plugin` with Zod schema validation
- Multiple tools per file supported (exported as `<filename>_<exportname>`)
- Context provides: `agent`, `sessionID`, `messageID`, `directory`, `worktree`
- Custom tools **override** built-in tools with matching names
- Can invoke scripts in any language (Python, etc.) via Bun shell

### MCP Server Support

- Full MCP client support with both local and remote servers
- **Local servers:** launched via command, with env vars and timeout config
- **Remote servers:** HTTP/HTTPS with automatic OAuth support (RFC 7591)
- OAuth tokens stored in `~/.local/share/opencode/mcp-auth.json`
- CLI management: `opencode mcp add|list|auth|logout|debug`
- Per-agent MCP tool enable/disable with glob patterns
- Tool precedence: custom tools > MCP tools > built-in tools

### Tool Permission Model

See Section 9 (Security) for the full permission system.

---

## 5. Context Management

### Compaction System

- **Automatic compaction** when context exceeds ~75% of model's context window
- Configurable via `compaction` key in `opencode.json`:
  - `auto` (bool) -- enable/disable automatic compaction
  - `prune` (bool) -- prune old tool outputs before compaction
  - `reserved` (int) -- reserved output token buffer (default: 20,000 tokens)
- Manual compaction via `/compact` command or `ctrl+x c`
- Dedicated **Compaction agent** (hidden system agent) generates summaries
- Plugin hook `experimental.session.compacting` allows injecting custom context before compaction
- Known limitation: hardcoded 75% threshold, not configurable per-model (community requests ongoing)

### File Mentions

- **`@` prefix** for fuzzy file search and auto-inclusion
- `@File#L37-42` syntax for specific line ranges (IDE extension)
- Drag-and-drop image support in terminal (limited clipboard paste support -- still evolving)

### Image Support

- Drag-and-drop images into terminal prompt
- Image files can be referenced and included in conversations
- Clipboard paste support is still buggy/under development as of March 2026

### Codebase Navigation

- No built-in embedding/semantic indexing (unlike Cursor)
- Relies on: `grep` (regex search), `glob` (pattern matching), `list` (directory enumeration), LSP (code intelligence)
- Community plugin `opencode-codebase-index` provides semantic search via tree-sitter + embeddings

---

## 6. Session Management

### Session Persistence

- All sessions are persisted locally (full message history, tool executions, file modifications)
- Sessions survive restart and can be resumed
- Model only receives curated context slice, not full stored history

### Session Operations

| Feature | Command/Keybind |
|---------|----------------|
| New session | `/new` or `ctrl+x n` |
| List sessions | `/sessions` or `ctrl+x l` |
| Session timeline | `ctrl+x g` |
| Resume session | Select from `/sessions` dialog |
| Fork session | `--fork` flag or SDK method |
| Export session | `/export` or `ctrl+x x` (Markdown/JSON) |
| Import session | `opencode import <file-or-url>` CLI |
| Share session | `/share` or `ctrl+x s` |
| Unshare | `/unshare` |
| Compact | `/compact` or `ctrl+x c` |
| Rename | SDK or config |

### Session Sharing

- Three modes: `manual` (default), `auto`, `disabled`
- Creates public URL copied to clipboard
- Shared at `opncd.com` or similar
- Known issues: sharing may not include all messages (bug tracked)

### Session Forking

- Creates new session with cloned messages up to optional cutoff
- Title appends "(fork #N)"

### Subagent Session Navigation

- `session_child_first`: \<leader\>+down
- `session_child_cycle`: right/left arrows
- `session_parent`: up arrow

---

## 7. Configuration

### Config File Format

- **JSON** (`.json`) and **JSONC** (`.jsonc`) -- JSON with comments
- Schema validation available: `https://opencode.ai/config.json`, `https://opencode.ai/tui.json`

### Configuration Hierarchy (highest to lowest precedence)

1. Remote config (`.well-known/opencode`)
2. Global config (`~/.config/opencode/opencode.json`)
3. Custom config (`OPENCODE_CONFIG` env var)
4. Project config (`opencode.json` in project/git root)
5. `.opencode` directories
6. Inline config (`OPENCODE_CONFIG_CONTENT` env var)

Config files are **merged**, not replaced.

### TUI Configuration

- Separate `tui.json` / `tui.jsonc` for UI settings
- Settings: theme, keybinds (leader key), scroll_speed, scroll_acceleration, diff_style

### Instruction Files

- Primary: `AGENTS.md` (project root, traversing upward to git root)
- Global: `~/.config/opencode/AGENTS.md`
- **Claude Code compatibility:** falls back to `CLAUDE.md` and `~/.claude/CLAUDE.md`
- Disable Claude compat: `OPENCODE_DISABLE_CLAUDE_CODE=1`
- Additional instructions via `"instructions"` key in config (supports globs, remote URLs)
- All instruction sources are combined

### Variable Substitution

- `{env:VARIABLE_NAME}` -- environment variable substitution
- `{file:path/to/file}` -- file content substitution

### Key Environment Variables

- `OPENCODE_CONFIG` -- custom config file path
- `OPENCODE_CONFIG_DIR` -- custom config directory
- `OPENCODE_CONFIG_CONTENT` -- inline runtime config (JSON)
- `OPENCODE_TUI_CONFIG` -- custom TUI config file
- `OPENCODE_EXPERIMENTAL` -- enable all experimental features
- `OPENCODE_EXPERIMENTAL_LSP_TOOL` -- enable LSP tool
- `OPENCODE_ENABLE_EXA` -- enable web search
- `OPENCODE_DISABLE_LSP_DOWNLOAD` -- disable LSP auto-install
- `OPENCODE_DISABLE_CLAUDE_CODE` -- disable Claude Code compatibility

---

## 8. Git Integration

### Undo/Redo with File Revert

- `/undo` reverts the last message **and** associated file changes (uses git under the hood)
- `/redo` restores previously undone modifications
- Requires project to be in a git repository
- Can undo bash command effects
- Known issues: file revert sometimes fails; `/redo` may touch unmodified files (bugs being tracked)

### Diff Viewing

- `diff_style` config: `"auto"` or `"stacked"` layout
- `session.diff` plugin event fires on file changes
- No built-in side-by-side diff overlay in TUI (community requests exist)
- Session timeline (`ctrl+x g`) provides visual history of changes

### Git Worktree Support

- Not built-in, but robust community plugins:
  - `opencode-worktree`: auto-spawns terminals per worktree, syncs files, cleans up
  - `opencode-worktree-session`: auto-creates worktrees per session, auto-commits on exit

### Auto-Commit

- Not a native feature in core OpenCode
- Available via worktree plugins (auto-commit on session end)

---

## 9. Security & Sandboxing

### Permission Model (14 permission types)

| # | Permission | Scope/Matches |
|---|-----------|---------------|
| 1 | `read` | File path |
| 2 | `edit` | File path (covers edit, write, patch, multiedit) |
| 3 | `glob` | Glob pattern |
| 4 | `grep` | Regex pattern |
| 5 | `list` | Directory path |
| 6 | `bash` | Parsed command (supports wildcard patterns) |
| 7 | `task` | Subagent type |
| 8 | `skill` | Skill name |
| 9 | `lsp` | Non-granular (all or nothing) |
| 10 | `todoread` | Todo access |
| 11 | `todowrite` | Todo modification |
| 12 | `webfetch` | URL |
| 13 | `websearch` / `codesearch` | Query |
| 14 | `external_directory` | Out-of-workspace paths |
| 15 | `doom_loop` | Identical repeated tool calls (3+ times) |

### Permission Actions

- `"allow"` -- execute without approval
- `"ask"` -- prompt user for confirmation (offers: once / always / reject)
- `"deny"` -- block entirely

### Default Permissions

- Most tools default to `"allow"`
- `doom_loop` and `external_directory` default to `"ask"`
- `.env` / `.env.*` files: `"deny"` by default (`.env.example` exempted)

### Pattern Matching

- `*` matches zero or more characters
- `?` matches exactly one character
- Last matching rule wins (order matters)
- Supports `~` and `$HOME` expansion

### Approval Workflow

- When `"ask"` triggers, user gets: once / always / reject
- Tools suggest patterns for "always" (e.g., `git status*`)

### Sandboxing

- **OpenCode does NOT sandbox the agent natively.** The permission system is a UX feature for user awareness, not a security boundary.
- Community plugin `opencode-sandbox` provides sandboxing via `@anthropic-ai/sandbox-runtime` (seatbelt on macOS, bubblewrap on Linux) with filesystem and network restrictions.

---

## 10. Agent Features

### Built-in Agents (5 total: 2 primary + 2 subagents + 3 system)

**Primary Agents (user-facing):**

| # | Agent | Tools | Purpose |
|---|-------|-------|---------|
| 1 | **Build** (default) | All enabled | Standard development work |
| 2 | **Plan** | File edits/bash require approval | Analysis and planning without modifications |

**Subagents:**

| # | Agent | Tools | Purpose |
|---|-------|-------|---------|
| 3 | **General** | All except todo | Research, multi-step tasks in parallel |
| 4 | **Explore** | Read-only | Codebase exploration, file search |

**System Agents (hidden):**

| # | Agent | Purpose |
|---|-------|---------|
| 5 | **Compaction** | Summarizes long context |
| 6 | **Title** | Generates session titles |
| 7 | **Summary** | Creates session summaries |

### Custom Agents

- Configured in `opencode.json` (JSON) or as markdown files in `agents/` directories
- Properties: `description`, `mode` (primary/subagent/all), `model`, `prompt`, `temperature`, `top_p`, `steps` (max iterations), `tools`, `permission`, `color`, `disable`, `hidden`
- Interactive creation wizard: `opencode agent create`
- Agent switching: `Tab` key or `agent_cycle` keybind
- Subagent invocation: `@mention` in prompt

### Plan/Think Mode

- **Plan agent** is a restricted primary agent (file edits/bash require approval)
- **Model variants** provide thinking levels:
  - Anthropic: `high` (default), `max`
  - OpenAI: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`
  - Google: `low`, `high`
- Cycle variants with `ctrl+t`
- Configurable per-agent

### Headless/Non-Interactive Mode

- `opencode run` -- execute prompts non-interactively (scripting/automation)
- `opencode serve` -- headless HTTP server with OpenAPI spec at `/doc`
- `opencode web` -- headless server + web browser interface
- `opencode acp` -- Agent Client Protocol server (stdin/stdout, nd-JSON)
- `opencode attach` -- connect TUI to running backend server
- Flags: `--command`, `--continue`, `--session`, `--fork`, `--share`, `--model`, `--agent`, `--file`, `--format`, `--title`, `--attach`, `--port`

### Structured Output

- SDK supports JSON schema-based output validation via `format` parameter
- Validation retries and `StructuredOutputError` handling

---

## 11. UI/UX Features

### TUI Framework: OpenTUI

- **OpenTUI** is a custom TUI library created by Anomaly specifically for OpenCode
- **Core:** Written in Zig for performance, with TypeScript bindings
- **Reactivity:** Framework-agnostic, supports SolidJS, React, and Vue bindings
- **OpenCode uses SolidJS** (`@opentui/solid`) for reactive state management
- Replaced earlier Go/Bubble Tea implementation in v1.0
- Current version: ~v0.1.72 (January 2026)
- Communicates with OpenCode HTTP/SSE server via `@opencode-ai/sdk`

### Themes (11 built-in + custom)

| # | Theme | Description |
|---|-------|-------------|
| 1 | `system` | Adapts to terminal background |
| 2 | `tokyonight` | Tokyo Night |
| 3 | `everforest` | Everforest |
| 4 | `ayu` | Ayu dark |
| 5 | `catppuccin` | Catppuccin |
| 6 | `catppuccin-macchiato` | Catppuccin Macchiato |
| 7 | `gruvbox` | Gruvbox |
| 8 | `kanagawa` | Kanagawa |
| 9 | `nord` | Nord |
| 10 | `matrix` | Hacker-style green on black |
| 11 | `one-dark` | Atom One Dark |

- Custom themes via JSON in project or config directories
- Supports: hex values, ANSI colors (0-255), color references, dark/light variants, `"none"` for terminal default
- Theme selection: `/themes` command or \<leader\>t

### Diff Display

- `diff_style` config: `"auto"` or `"stacked"`
- No side-by-side diff overlay (feature requested)
- Session timeline provides visual change history

### Markdown Rendering

- Renders markdown in AI responses
- Known issues in v1.0+: syntax highlighting broken in some themes (single color), JSON quotes stripped, tables sometimes render as plain text

### Syntax Highlighting

- Present but reported broken/degraded in OpenTUI v1.0+ transition
- All code may appear in single color in some configurations (bug tracked)

### Scroll Features

- Configurable `scroll_speed` (decimal, min 0.001)
- `scroll_acceleration` with macOS-style momentum scrolling option

### Sidebar

- Toggleable sidebar: \<leader\>b
- Session list and navigation

### File Tree

- No dedicated file tree panel in TUI
- File discovery via `@` fuzzy search, `glob`, `list` tools

### Desktop App

- **Tauri 2.x** native desktop app for Windows, macOS, Linux
- Also an Electron variant available
- Shares same SolidJS UI layer as TUI
- Native OS integrations: file picker dialogs, URL opener
- Automatic updates via `@tauri-apps/plugin-updater`
- Published via GitHub Releases and AUR

### Web Interface

- `opencode web` launches headless server with browser UI
- Same SDK-driven interface as TUI and desktop

---

## 12. Extensibility & Integration

### Plugin System

- Plugins are JS/TS modules exporting hook functions
- Install methods: local files (`.opencode/plugins/`), npm packages (auto-installed via Bun)
- Can define custom tools, inject environment variables, customize compaction
- Load order: global config -> project config -> global dir -> project dir
- `package.json` in config directory for npm dependencies (Bun installs at startup)
- Logging via `client.app.log()` (debug, info, warn, error)

### SDK (`@opencode-ai/sdk`)

- TypeScript/JavaScript SDK for programmatic control
- Install: `npm install @opencode-ai/sdk`
- Full API surface:
  - `global.health()` -- server status
  - `app.log()`, `app.agents()` -- logging and agent listing
  - `project.list()`, `project.current()` -- project management
  - `session.*` -- create, delete, prompt, command, shell, share, revert, fork
  - `find.text()`, `find.files()`, `find.symbols()` -- search operations
  - `file.read()` -- file access
  - `tui.*` -- appendPrompt, submitPrompt, clearPrompt, openSessions, openModels, showToast
  - `auth.set()` -- credential management
  - `event.subscribe()` -- real-time SSE event stream
- Structured output with JSON schema validation

### MCP Protocol

- Full MCP client support (see Section 4)
- OpenCode also acts as an **MCP server** via community packages (`nosolosoft/opencode-mcp`)
- Allows external MCP clients to use OpenCode's capabilities

### Agent Client Protocol (ACP)

- `opencode acp` starts ACP server over stdin/stdout (nd-JSON transport)
- Compatible with editors like Zed, JetBrains IDEs
- Adapter bridges ACP clients to OpenCode engine

### IDE Integrations

| IDE | Support |
|-----|---------|
| VS Code | Extension (auto-installs), ctrl+esc quick launch |
| Cursor | Extension support |
| Windsurf | Extension support |
| VSCodium | Extension support |
| Zed | Via ACP adapter |
| JetBrains | Via ACP |
| Neovim | Community plugin (`opencode.nvim`) |

- Keyboard shortcuts: Cmd+Esc / Ctrl+Esc (quick launch), Cmd+Shift+Esc / Ctrl+Shift+Esc (new session), Cmd+Option+K / Alt+Ctrl+K (insert file references)
- Context awareness: auto-shares current selection/tab with OpenCode

### GitHub Actions Integration

- `opencode github install` for guided setup
- Mention `/opencode` or `/oc` in issue/PR comments
- Supported triggers: `issue_comment`, `pull_request_review_comment`, `issues`, `pull_request`, `schedule`, `workflow_dispatch`
- Actions: issue triage, code implementation (auto-branch + PR), code review on specific lines
- Runs inside GitHub Actions runners (secure)
- Configurable: model, agent, prompt, share, token

### Skills System

- SKILL.md files in skill directories
- Discovery paths (6 locations): `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` (project + global)
- YAML frontmatter: `name`, `description` (required), `license`, `compatibility`, `metadata` (optional)
- Loaded on-demand via native `skill` tool
- Permission control: `allow`, `deny`, `ask` with pattern matching
- Community skills marketplace exists

---

## 13. Model & Provider Support

### Supported Providers (41 named + any OpenAI-compatible)

| # | Provider | Notes |
|---|----------|-------|
| 1 | 302.AI | |
| 2 | Amazon Bedrock | AWS auth (access keys, profiles, bearer tokens) |
| 3 | Anthropic | Claude models, Pro/Max subscription or API |
| 4 | Azure OpenAI | Resource name + deployed models |
| 5 | Azure Cognitive Services | |
| 6 | Baseten | |
| 7 | Cerebras | |
| 8 | Cloudflare AI Gateway | Unified endpoint |
| 9 | Cortecs | |
| 10 | DeepSeek | |
| 11 | Deep Infra | |
| 12 | Firmware | |
| 13 | Fireworks AI | |
| 14 | GitLab Duo | Claude via GitLab's Anthropic proxy |
| 15 | GitHub Copilot | Pro+ for some models |
| 16 | Google Vertex AI | Cloud project + regional config |
| 17 | Groq | |
| 18 | Hugging Face | 17+ inference providers |
| 19 | Helicone | LLM observability gateway |
| 20 | IO.NET | 17 optimized models |
| 21 | llama.cpp | Local, OpenAI-compatible |
| 22 | LM Studio | Local models |
| 23 | Moonshot AI | Kimi K2 |
| 24 | MiniMax | |
| 25 | Nebius Token Factory | |
| 26 | Ollama | Local, OpenAI-compatible |
| 27 | Ollama Cloud | |
| 28 | OpenAI | ChatGPT Plus/Pro or API |
| 29 | OpenCode Zen | Curated tested models (pay-as-you-go) |
| 30 | OpenCode Go | Low-cost subscription ($5 first month, then $10/mo) |
| 31 | OpenRouter | |
| 32 | OVHcloud AI Endpoints | |
| 33 | SAP AI Core | 40+ models |
| 34 | Scaleway | Generative APIs |
| 35 | STACKIT | Sovereign European hosting |
| 36 | Together AI | |
| 37 | Venice AI | |
| 38 | Vercel AI Gateway | |
| 39 | xAI | Grok models |
| 40 | Z.AI | GLM models |
| 41 | ZenMux | |

Plus **any OpenAI-compatible provider** via manual configuration (base URL + API endpoint).

### Model Discovery

- Uses **Models.dev** catalog: 75+ providers, 1000+ models
- `opencode models` CLI lists all available models
- `/models` TUI command for interactive selection

### Model Switching

- `/models` dialog or \<leader\>m keybind
- `model_cycle_recent`: F2 / Shift+F2
- `variant_cycle`: Ctrl+T
- `--model` / `-m` CLI flag
- Priority: CLI flag > config > last used > default

### Model Variants

- **Anthropic:** `high` (default), `max` thinking budgets
- **OpenAI:** `none`, `minimal`, `low`, `medium`, `high`, `xhigh` reasoning efforts
- **Google:** `low`, `high` effort levels
- Custom variants configurable per-model
- Cycle with Ctrl+T

### Model Configuration

- `model` -- primary model (e.g., `anthropic/claude-sonnet-4-5`)
- `small_model` -- lightweight model for titles, summaries
- `enabled_providers` / `disabled_providers` -- allowlist/blocklist
- Per-model: `reasoningEffort`, `textVerbosity`, `thinking` budget
- Per-agent model overrides

### Token Usage

- Built-in `opencode stats` CLI command (flags: `--days`, `--tools`, `--models`, `--project`)
- Token usage displayed in TUI session
- Community tools: OpenCode Monitor, TokenScope, OpenCode Bar (macOS menu bar)

### Subscription Tiers

| Tier | Price | Description |
|------|-------|-------------|
| OpenCode (core) | Free | Open source, bring your own API keys |
| OpenCode Go | $5 first month, then $10/mo | Low-cost access to popular open coding models |
| OpenCode Zen | Pay-as-you-go (at cost + processing) | Curated, tested model set |
| OpenCode Black | $200/mo (sold out) | Premium access to OpenAI + Anthropic + open-weight models |

---

## 14. Code Formatting (26 built-in formatters)

OpenCode automatically formats files after edit/write operations.

| # | Formatter | Extensions | Detection |
|---|-----------|-----------|-----------|
| 1 | air | .R | `air` command |
| 2 | biome | .js, .jsx, .ts, .tsx, .html, .css, .md, .json, .yaml + more | `biome.json(c)` |
| 3 | cargofmt | .rs | `cargo fmt` command |
| 4 | clang-format | .c, .cpp, .h, .hpp, .ino + more | `.clang-format` file |
| 5 | cljfmt | .clj, .cljs, .cljc, .edn | `cljfmt` command |
| 6 | dart | .dart | `dart` command |
| 7 | dfmt | .d | `dfmt` command |
| 8 | gleam | .gleam | `gleam` command |
| 9 | gofmt | .go | `gofmt` command |
| 10 | htmlbeautifier | .erb, .html.erb | `htmlbeautifier` command |
| 11 | ktlint | .kt, .kts | `ktlint` command |
| 12 | mix | .ex, .exs, .eex, .heex, .leex, .neex, .sface | `mix` command |
| 13 | nixfmt | .nix | `nixfmt` command |
| 14 | ocamlformat | .ml, .mli | `ocamlformat` + `.ocamlformat` |
| 15 | ormolu | .hs | `ormolu` command |
| 16 | oxfmt | .js, .jsx, .ts, .tsx | Experimental, requires flag |
| 17 | pint | .php | `laravel/pint` in composer.json |
| 18 | prettier | .js, .jsx, .ts, .tsx, .html, .css, .md, .json, .yaml + more | `prettier` in package.json |
| 19 | rubocop | .rb, .rake, .gemspec, .ru | `rubocop` command |
| 20 | ruff | .py, .pyi | `ruff` command + config |
| 21 | rustfmt | .rs | `rustfmt` command |
| 22 | shfmt | .sh, .bash | `shfmt` command |
| 23 | standardrb | .rb, .rake, .gemspec, .ru | `standardrb` command |
| 24 | terraform | .tf, .tfvars | `terraform` command |
| 25 | uv | .py, .pyi | `uv` command |
| 26 | zig | .zig, .zon | `zig` command |

- Disable all: `formatter: false` in config
- Custom formatters: specify command, env, extensions in config
- Event-driven: runs after file write/edit, non-blocking

---

## 15. LSP Integration (30+ language servers, 24 built-in)

### Built-in LSP Servers (24)

| # | Server | Languages/Extensions |
|---|--------|---------------------|
| 1 | TypeScript | .ts, .tsx, .js, .jsx, .mjs, .cjs, .mts, .cts |
| 2 | Deno | .ts, .tsx, .js, .jsx, .mjs (requires deno) |
| 3 | ESLint | .ts, .tsx, .js, .jsx, .mjs, .cjs, .mts, .cts, .vue |
| 4 | Oxlint | .ts, .tsx, .js, .jsx, .mjs, .cjs, .mts, .cts, .vue, .astro, .svelte |
| 5 | Vue | .vue |
| 6 | Svelte | .svelte |
| 7 | Astro | .astro |
| 8 | Rust (rust-analyzer) | .rs |
| 9 | C/C++ (Clangd) | .c, .cpp, .cc, .cxx, .c++, .h, .hpp |
| 10 | Go (Gopls) | .go |
| 11 | Zig (Zls) | .zig, .zon |
| 12 | Haskell | .hs, .lhs |
| 13 | Elixir | .ex, .exs |
| 14 | Clojure | .clj, .cljs, .cljc, .edn |
| 15 | OCaml | .ml, .mli |
| 16 | Gleam | .gleam |
| 17 | Python (Pyright) | .py, .pyi |
| 18 | PHP (Intelephense) | .php |
| 19 | Kotlin | .kt, .kts |
| 20 | Java (JDTLS) | .java (requires JDK 21+) |
| 21 | Prisma | .prisma |
| 22 | Terraform | .tf, .tfvars |
| 23 | YAML | .yaml, .yml |
| 24 | Lua | .lua |

Additional servers mentioned in docs: Nix, Typst, Bash, Ruby, F#, C#, Swift/Objective-C, Julia.

### LSP Capabilities

- Auto-install when matching files are opened
- Lazy-loading: servers spawn only when needed
- Provides to LLM: diagnostics, hover info, go-to-definition, find references, call hierarchy, document symbols
- LSP tool (experimental) exposes these capabilities directly to the agent
- Configurable per-server: `disabled`, `command`, `extensions`, `env`, `initialization`
- Disable all: `lsp: false`
- Disable auto-download: `OPENCODE_DISABLE_LSP_DOWNLOAD=true`

---

## Summary Counts

| Category | Count |
|----------|-------|
| TUI slash commands | 17 built-in + unlimited custom |
| Plugin event types | 28 |
| Keybindings | 70+ |
| Built-in tools | 15 |
| Permission types | 15 |
| Built-in agents | 7 (2 primary + 2 sub + 3 system) |
| Themes | 11 built-in + custom |
| Providers | 41 named + any OpenAI-compatible |
| Built-in formatters | 26 |
| Built-in LSP servers | 24+ |
| CLI commands | 14 top-level |
| Deployment modes | 5 (TUI, desktop/Tauri, web, headless/serve, ACP) |
| IDE integrations | 7+ (VS Code, Cursor, Windsurf, VSCodium, Zed, JetBrains, Neovim) |
