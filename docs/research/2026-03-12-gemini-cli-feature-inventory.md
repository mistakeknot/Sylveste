# Gemini CLI Feature Inventory (v0.33.0, March 2026)

> Research date: 2026-03-12
> Repository: [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli)
> License: Apache 2.0 | Language: TypeScript | Stars: 97.4k
> Install: `npm i -g @google/gemini-cli` or `brew install gemini-cli`

---

## 1. Slash Commands (33 total)

| Command | Description |
|---------|-------------|
| `/about` | Show version info |
| `/auth` | Change authentication method via dialog |
| `/bug` | File a GitHub issue directly |
| `/chat` | Alias for `/resume`; opens session browser |
| `/clear` (`Ctrl+L`) | Clear terminal screen and visible session history |
| `/commands` | Manage custom slash commands from `.toml` files |
| `/commands reload` | Reload custom command definitions without restarting |
| `/compress` | Replace entire chat context with a structured summary to save tokens |
| `/copy` | Copy the last Gemini output to clipboard |
| `/directory` / `/dir` | Manage multi-directory workspace (`add`, `show`) |
| `/docs` | Open Gemini CLI documentation in browser |
| `/editor` | Dialog for selecting supported external editors |
| `/extensions` | Full extension lifecycle: `config`, `disable`, `enable`, `explore`, `install`, `link`, `list`, `restart`, `uninstall`, `update` |
| `/help` / `/?` | Display help information |
| `/hooks` | Manage hooks: `disable-all`, `disable`, `enable-all`, `enable`, `list` |
| `/ide` | Manage IDE integration: `disable`, `enable`, `install`, `status` |
| `/init` | Analyze directory and generate tailored `GEMINI.md` context file |
| `/mcp` | Manage MCP servers: `auth`, `desc`, `disable`, `enable`, `list`, `refresh`, `schema` |
| `/memory` | Manage GEMINI.md context: `add`, `list`, `refresh`, `show` |
| `/model` | Manage model configuration: `manage`, `set` |
| `/permissions` | Manage folder trust settings |
| `/plan` | Switch to Plan Mode (read-only research); `copy` subcommand |
| `/policies` | List active policies |
| `/privacy` | Display privacy notice and consent options |
| `/quit` / `/exit` | Exit Gemini CLI |
| `/restore` | Restore project files to pre-tool-execution state |
| `/resume` | Browse/resume sessions; subcommands: `list`, `save`, `resume`, `delete`, `share`, `debug` |
| `/rewind` | Navigate backward through conversation |
| `/settings` | Open settings editor |
| `/shells` / `/bashes` | Toggle background shells view |
| `/setup-github` | Configure GitHub Actions for issue triage and PR review |
| `/skills` | Manage Agent Skills: `disable`, `enable`, `list`, `reload` |
| `/stats` | Session statistics: `session`, `model`, `tools` |
| `/terminal-setup` | Configure terminal keybindings for multiline input |
| `/theme` | Change visual theme via dialog |
| `/tools` | Display available tools: `desc` (detailed), `nodesc` (names only) |
| `/upgrade` | Open upgrade page for higher usage limits |
| `/vim` | Toggle vim mode (NORMAL/INSERT modes) |

### Custom Slash Commands

- **User-scoped:** `~/.gemini/commands/*.toml`
- **Project-scoped:** `<project>/.gemini/commands/*.toml`
- **Namespacing:** Subdirectories create colon-separated names (e.g., `git/commit.toml` becomes `/git:commit`)
- **Variable interpolation:** `{{args}}` for user arguments, `!{...}` for shell command output, `@{...}` for file content
- **Shell safety:** Arguments inside `!{...}` blocks are automatically shell-escaped
- **MCP prompts as commands:** MCP server prompts automatically surfaced as slash commands

---

## 2. Hooks System (11 events, v0.26.0+)

| Event | Trigger | Can Block? | Primary Use |
|-------|---------|-----------|-------------|
| `SessionStart` | Session begins, resume, or `/clear` | No | Initialize resources, load context |
| `SessionEnd` | Session terminates | No | Cleanup, state persistence |
| `BeforeAgent` | After prompt submission, pre-planning | Yes | Validate prompts, add context |
| `AfterAgent` | Agent loop completion | Retry/Halt | Review output, force retry |
| `BeforeModel` | Before LLM request | Yes/Mock | Modify prompts, inject synthetic responses |
| `AfterModel` | After LLM response | Yes/Redact | Filter responses, log interactions |
| `BeforeToolSelection` | Before tool selection | Filter | Optimize/restrict available tools |
| `BeforeTool` | Pre-tool execution | Yes | Validate arguments, block dangerous ops |
| `AfterTool` | Post-tool execution | Yes/Inject | Process results, run tests, add context |
| `PreCompress` | Before context compression | Advisory | Save state, notify user |
| `Notification` | System notification fires | Advisory | Forward to external systems |

**Configuration:** `settings.json` under `hooks` key. Supports `matcher` (regex for tools), `sequential`, `timeout` (ms, default 60000).

**Environment variables:** `GEMINI_PROJECT_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD`

**Exit codes:** 0 = success, 2 = system block (abort), other = warning (continue)

**Hook locations (merge order):** Project > User > System > Extension-defined

**Security:** Project-level hooks get fingerprinted; changes trigger new-hook warnings.

### Extensions System

- Extensions package: prompts, MCP servers, custom commands, themes, hooks, sub-agents, agent skills
- Install: `gemini extensions install <github-repo-url>`
- Management: `/extensions list`, `enable`, `disable`, `explore`, `install`, `link`, `restart`, `uninstall`, `update`
- Extension gallery for browsing community extensions
- Parallel loading (v0.30.0+)

### Agent Skills

- Modular capability packages (distinct from custom commands)
- Structure: self-contained directory with `SKILL.md` plus bundled assets
- Lazy loading: only name/description at startup; full content on activation
- Location: `.gemini/skills/` (project) or `~/.gemini/skills/` (user)
- Management: `/skills list`, `enable`, `disable`, `reload`

---

## 3. UI/UX

### Terminal Layout
- Two-zone: scrollable history + interactive input (Composer)
- Background shells view: `/shells` or `Ctrl+B`; concurrent shell processes
- Tab focus switching between Gemini input and active shell
- Minimal/Full toggle: `Tab+Tab` (remembered across sessions)

### Themes (16 built-in)
- Dark: ANSI, Atom One, Ayu, Default, Dracula, GitHub, Holiday, Shades Of Purple, Solarized Dark
- Light: ANSI Light, Ayu Light, Default Light, GitHub Light, Google Code, Solarized Light, Xcode
- Custom themes via `settings.json` `customThemes` or external JSON files
- Extension themes auto-appear in `/theme` dialog
- Auto light/dark switching: `autoThemeSwitching` setting

### Rendering
- Markdown output with syntax highlighting
- `Alt+M` toggles markdown rendering
- Line numbers toggle: `showLineNumbers`
- In-terminal diff display (added/removed highlighting)
- IDE companion for native diff viewing
- Streaming output with real-time token display
- `hideFooter` option, `dynamicWindowTitle` for terminal title

### Accessibility
- `--screen-reader` mode
- `NO_COLOR` environment variable

---

## 4. Keyboard Shortcuts

### Input & Editing
| Key | Action |
|-----|--------|
| `Enter` | Submit prompt |
| `Ctrl+Enter` / `Shift+Enter` / `Alt+Enter` / `Ctrl+J` | Insert newline |
| `Ctrl+X` | Open prompt in external editor |
| `Ctrl+V` | Paste from clipboard |
| `Ctrl+K` | Delete to end of line |
| `Ctrl+U` | Delete to start of line |
| `Ctrl+W` / `Alt+Backspace` | Delete previous word |
| `Alt+D` | Delete next word |
| `Cmd+Z` / `Alt+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |

### Navigation
| Key | Action |
|-----|--------|
| `Ctrl+A` / `Home` | Start of line |
| `Ctrl+E` / `End` | End of line |
| `Ctrl+Left` / `Alt+B` | Word left |
| `Ctrl+Right` / `Alt+F` | Word right |
| `Shift+Up/Down` | Scroll content |
| `Ctrl+Home` | Scroll to top |
| `Page Up/Down` | Page scroll |

### History
| Key | Action |
|-----|--------|
| `Ctrl+P` | Previous history entry |
| `Ctrl+N` | Next history entry |
| `Ctrl+R` | Reverse search through history |

### App Controls
| Key | Action |
|-----|--------|
| `Ctrl+C` | Cancel / quit |
| `Ctrl+Y` | Toggle YOLO (auto-approval) mode |
| `Shift+Tab` | Cycle approval modes |
| `Alt+M` | Toggle markdown rendering |
| `Ctrl+T` | Toggle TODO list |
| `Ctrl+S` | Toggle copy mode |
| `Ctrl+O` | Expand/collapse content blocks |
| `F12` | Toggle detailed error info |
| `?` (empty prompt) | Toggle shortcuts panel |
| `!` (empty prompt) | Enter shell mode |
| `Tab+Tab` | Toggle minimal/full UI |
| `Esc+Esc` | Clear prompt or browse/rewind |

### Custom Keybindings
- File: `~/.gemini/keybindings.json` (VS Code-like schema)
- Defaults cannot be removed; only additional bindings
- Vim mode: `/vim` command or `vimMode` setting

---

## 5. Model Routing

### Selection Precedence
1. `--model <name>` CLI flag
2. `GEMINI_MODEL` environment variable
3. `model.name` in `settings.json`
4. Default: `auto` (automatic routing)

### Auto-Routing
- Router model: `gemini-2.5-flash-lite` (extremely cheap, one increment per turn)
- Resolved models: Flash and Pro handle actual processing
- Three services: `ModelConfigService`, `ModelAvailabilityService`, `ModelRouterService`
- Plan Mode routing: Pro for planning, Flash for implementation

### Model Switching
- `/model set <name>` mid-session
- Context window validation on switch
- Fallback chain on failure: flash-lite → flash → pro

### Current Models
- Default: Gemini 3 (v0.29.0+)
- Gemini 3.1 Pro Preview (v0.31.0)
- Gemini 2.5 Pro (1M token context)
- Experimental: `gemini-2.5-computer-use-preview`

---

## 6. Session Management

### Persistence
- Complete conversation + tool executions + token usage
- Location: `~/.gemini/tmp/<project_hash>/chats/`
- Project-scoped

### Resume
- `gemini --resume` (most recent), `--resume <index>`, `--resume <UUID>`
- `/resume` interactive browser with search, preview, delete
- `/resume save <name>` for named checkpoints

### Checkpointing (disabled by default)
- Shadow Git repo at `~/.gemini/history/<project_hash>/`
- Automatic snapshots before file-modifying tool calls
- `/restore` lists and restores checkpoints

### Rewind
- `/rewind` or `Esc+Esc`: rewind conversation + revert code, or just one

### Context Compression
- Manual: `/compress` replaces history with structured summary
- Automatic: triggers at `contextPercentageThreshold` (default 50%)
- `/memory add` entries survive compression (stored in GEMINI.md)

### Retention
- `maxAge`: "30d" default, `maxCount`: 50, `minRetention`: "1d"
- `maxSessionTurns`: 100 default

---

## 7. Tool System (14 built-in)

| Tool | Category | Approval |
|------|----------|----------|
| `read_file` | File (text, images, audio, PDF) | Auto-allow |
| `write_file` | File | Ask user |
| `replace` (Edit) | File | Ask user |
| `list_directory` | File | Auto-allow |
| `glob` (FindFiles) | File | Auto-allow |
| `grep_search` | File (uses git grep when available) | Auto-allow |
| `read_many_files` | File | Auto-allow |
| `run_shell_command` | System (supports background, interactive pty) | Ask user |
| `google_web_search` | Web | Ask user |
| `web_fetch` | Web | Ask user |
| `save_memory` | Planning | Auto-allow |
| `write_todos` | Planning | Auto-allow |
| `ask_user` | Interaction | N/A |
| `codebase_investigator` | Subagent | Auto-allow |

### MCP Support
- Transports: Stdio, SSE, HTTP Streaming
- Tool filtering: `includeTools` / `excludeTools` per server
- OAuth support with token storage
- Environment variable redaction for security
- 10-minute default timeout

### Policy Engine
- Decisions: `allow`, `deny`, `ask_user`
- Conditions: tool name wildcards, argument regex, command patterns
- Priority tiers: Default (1) < Extension (2) < Workspace (3) < User (4) < Admin (5)
- Approval modes: `default`, `autoEdit`, `plan`, `yolo`
- Policy files: `~/.gemini/policies/*.toml`, `.gemini/policies/*.toml`, `/etc/gemini-cli/policies/`

### Sandboxing
- macOS Seatbelt (default)
- Docker/Podman (cross-platform)
- gVisor/runsc (Linux, strongest)
- LXC/LXD (Linux, experimental)
- Activation: `-s` flag or `GEMINI_SANDBOX` env var

---

## 8. Git Integration

- `.gitignore` respect for file filtering
- `.geminiignore` support
- `grep_search` uses `git grep` when available
- Shadow Git for checkpointing (separate from project repo)
- `/setup-github` for GitHub Actions integration
- No built-in auto-commit (done via custom commands or extensions)

---

## 9. File Mentions & Context

### @ Syntax
- `@path/to/file.txt` — injects file content
- `@path/to/dir` — traverses directory (respects .gitignore)
- Tab completion for paths
- Multimodal: images, PDFs, audio, video

### GEMINI.md
- Hierarchical: `~/.gemini/GEMINI.md` > parent dirs > project root > subdirs (max 200 dirs)
- Import syntax: `@path/to/file.md` within GEMINI.md
- `/init` auto-generates, `/memory add` appends (survives compression)

### MCP Resources
- `@server://resource/path` for MCP resource references

---

## 10. Configuration

### Files (precedence, highest wins)
1. CLI arguments
2. Environment variables
3. System overrides (`/etc/gemini-cli/settings.json`)
4. Project (`.gemini/settings.json`)
5. User (`~/.gemini/settings.json`)
6. System defaults
7. Built-in defaults

### Per-Project
- `.gemini/settings.json`, `.gemini/GEMINI.md`, `.gemini/commands/*.toml`
- `.gemini/agents/*.md`, `.gemini/skills/`, `.gemini/policies/*.toml`

---

## 11. Auth/Pricing

### Free Tier
| Method | Requests/Day | Requests/Min |
|--------|-------------|--------------|
| Google Account (Code Assist) | 1,000 | 60 |
| Gemini API Key (unpaid) | 250 | 10 (Flash only) |

### Paid Tiers
- Code Assist Standard: 1,500/day, 120/min
- Code Assist Enterprise: 2,000/day, 120/min
- Vertex AI: pay-as-you-go per-token
- Gemini API Key (paid): significantly higher limits

---

## 12. Unique Features

- **Subagents:** `codebase_investigator`, `cli_help`, `generalist_agent`, `browser_agent`
- **Browser Agent:** Chrome automation (v144+, computer-use model)
- **Plan Mode:** Read-only research with auto Pro/Flash routing
- **Interactive Shell:** PTY-based bidirectional shell with Tab focus
- **Agent Skills:** Lazy-loaded modular capability packages
- **A2A Protocol:** Remote agent delegation over HTTP
- **Rewind:** Undo conversation + code changes (or independently)
- **`/restore`:** File-level restore to pre-tool state
- **Multi-directory workspaces:** Up to 5 concurrent directories
- **Environment variable redaction:** Auto-strips secrets from MCP environments
- **SDK:** Programmatic access (v0.30.0+)
- **GitHub Actions:** `/setup-github` for automated PR review and issue triage

---

## Sources

- [GitHub Repository](https://github.com/google-gemini/gemini-cli)
- [Documentation](https://geminicli.com/docs/)
- [Keyboard Shortcuts](https://geminicli.com/docs/reference/keyboard-shortcuts/)
- [Policy Engine](https://geminicli.com/docs/reference/policy-engine/)
- [Model Routing](https://geminicli.com/docs/cli/model-routing/)
- [Session Management](https://geminicli.com/docs/cli/session-management/)
- [Hooks Reference](https://geminicli.com/docs/hooks/reference/)
- [Custom Commands](https://geminicli.com/docs/cli/custom-commands/)
- [Sandbox](https://geminicli.com/docs/cli/sandbox/)
- [Subagents](https://geminicli.com/docs/core/subagents/)
- [Plan Mode](https://geminicli.com/docs/cli/plan-mode/)
- [Configuration](https://geminicli.com/docs/reference/configuration/)
- [Quotas and Pricing](https://geminicli.com/docs/resources/quota-and-pricing/)
- [Enterprise](https://geminicli.com/docs/cli/enterprise/)
- [Extensions](https://geminicli.com/docs/extensions/)
- [Release Notes](https://geminicli.com/docs/changelogs/)
