# Codex CLI Feature Inventory (Deep Research 2026-03-12)

> **Product**: Codex CLI by OpenAI
> **Repository**: github.com/openai/codex (64.9K stars, Apache 2.0)
> **Language**: Rust (95.7% of codebase) with Ratatui TUI framework
> **Latest stable**: v0.98.0 (2026-02-05); pre-release v0.115.0-alpha (2026-03-11)
> **Installation**: `npm i -g @openai/codex` | `brew install --cask codex` | GitHub release binaries
> **Platforms**: macOS (native), Linux (native), Windows (experimental, native sandbox added March 2026), WSL
>
> Sources:
> - [Codex CLI Features](https://developers.openai.com/codex/cli/features/)
> - [Codex CLI Slash Commands](https://developers.openai.com/codex/cli/slash-commands/)
> - [Codex CLI Reference](https://developers.openai.com/codex/cli/reference)
> - [Codex Config Reference](https://developers.openai.com/codex/config-reference/)
> - [Codex Advanced Config](https://developers.openai.com/codex/config-advanced/)
> - [Codex Agent Approvals & Security](https://developers.openai.com/codex/agent-approvals-security/)
> - [Codex Sandboxing](https://developers.openai.com/codex/concepts/sandboxing/)
> - [Codex MCP](https://developers.openai.com/codex/mcp/)
> - [Codex Multi-Agent](https://developers.openai.com/codex/multi-agent/)
> - [Codex Skills](https://developers.openai.com/codex/skills/)
> - [Codex Models](https://developers.openai.com/codex/models/)
> - [Codex Changelog](https://developers.openai.com/codex/changelog/)
> - [Codex Execution Policy](https://developers.openai.com/codex/exec-policy)
> - [Codex Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
> - [Codex GitHub Action](https://developers.openai.com/codex/github-action/)
> - [Codex Agents SDK Guide](https://developers.openai.com/codex/guides/agents-sdk/)
> - [Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
> - [Codex Security](https://developers.openai.com/codex/security/)
> - [Codex Windows](https://developers.openai.com/codex/windows)
> - [GitHub: openai/codex](https://github.com/openai/codex)
> - [How Codex is built (Pragmatic Engineer)](https://newsletter.pragmaticengineer.com/p/how-codex-is-built)
> - [How OpenAI Codex Works (PromptLayer)](https://blog.promptlayer.com/how-openai-codex-works-behind-the-scenes-and-how-it-compares-to-claude-code/)
> - [DeepWiki: TUI Implementation](https://deepwiki.com/oaiagicorp/codex/3.2-tui-implementation)
> - [DeepWiki: Memory System](https://deepwiki.com/openai/codex/3.7-memory-system)

---

## 1. Slash Commands (28+ built-in)

Slash commands are invoked by typing `/` in the composer to open a popup picker. Codex ships with a curated set of built-ins.

### Built-in Commands

| Command | Description |
|---------|-------------|
| `/agent` | Switch between active agent threads; inspect ongoing thread |
| `/apps` | Browse apps (connectors) and insert into prompt |
| `/clear` | Clear the terminal and start a fresh chat |
| `/compact` | Summarize visible conversation to free tokens |
| `/copy` | Copy the latest completed Codex output to clipboard |
| `/debug-config` | Print configuration layer and policy diagnostics |
| `/diff` | Display Git changes including untracked files |
| `/exit` | Exit the CLI session |
| `/experimental` | Toggle experimental features on/off |
| `/fast` | Toggle fast mode (service tier) |
| `/feedback` | Submit logs and diagnostics to maintainers |
| `/fork` | Clone current conversation into a new thread |
| `/init` | Generate an AGENTS.md scaffold for the current repo |
| `/logout` | Clear local user credentials |
| `/mcp` | List available Model Context Protocol tools |
| `/mention` | Attach a file to the conversation |
| `/model` | Choose the active model and reasoning effort |
| `/new` | Start a fresh conversation within the same session |
| `/permissions` | Set what Codex can do without asking first |
| `/personality` | Choose a communication style (friendly, pragmatic, none) |
| `/plan` | Switch to plan mode; optionally send a prompt |
| `/ps` | Show background terminals and recent output |
| `/quit` | Exit the CLI |
| `/resume` | Resume a saved conversation from session list |
| `/review` | Request Codex to analyze your working tree (dedicated reviewer) |
| `/sandbox-add-read-dir` | Grant read access to directories (Windows only) |
| `/skills` | Browse and invoke installed skills |
| `/status` | Display session configuration and token usage |
| `/statusline` | Configure interactive status-line footer items |
| `/theme` | Preview and save a color theme |

**Note**: `/approvals` remains functional but hidden from the slash popup. Custom prompts (previously supported) are deprecated in favor of skills.

### Custom Commands

No user-defined slash command creation system exists natively. Extensibility is achieved through the **skills system** (see Section 12) where skills can be invoked via `$skill-name` syntax or implicitly matched by description.

---

## 2. Hook System (2 event types, experimental)

Hooks are **experimental** as of v0.114.0 (2026-03-11). The hook engine allows user-defined handlers (command/prompt/agent) to fire on specific lifecycle events.

### Supported Hook Events

| Event | Matchers | Description |
|-------|----------|-------------|
| `SessionStart` | `""` | Fires when a session begins |
| `Stop` | `""`, `done`, `ask` | Fires when a session stops (completion, user prompt, abort) |
| `TurnAborted` | `""`, `aborted` | Fires when a turn is aborted (via codex-hooks compat) |
| `TaskStarted` | `""` | Fires when a task starts (via codex-hooks compat) |
| `TaskComplete` | `""`, `done`, `ask` | Fires when a task completes (via codex-hooks compat) |

### Configuration

Hooks are configured in `config.toml` under the `[hooks]` table. Hook commands receive Claude-style JSON on stdin with stable fields:
- `hook_event_name`
- `transcript_path`
- `cwd`
- `session_id`
- `raw_event`

### Additional Hook: Commit Attribution

Commit co-author attribution uses a Codex-managed `prepare-commit-msg` Git hook. Configurable via `commit_attribution` in config.toml (default label, custom label, or disable with empty string).

### Comparison Note

The hook system is far less mature than Claude Code's (which has 5+ event types with pre/post variants, user-configurable in `settings.json`). Community project [codex-hooks](https://github.com/hatayama/codex-hooks) bridges the gap by reusing Claude Code hooks settings format.

---

## 3. Keyboard Shortcuts & Input (14+ keybindings)

### Keybindings

| Key | Context | Action |
|-----|---------|--------|
| `Enter` | Composer empty | Send prompt |
| `Enter` | While agent running | Inject new instructions into current turn |
| `Tab` | While agent running | Queue a follow-up prompt for next turn |
| `Esc` (1x) | Composer empty | Prime "backtrack" mode |
| `Esc` (2x) | Backtrack mode | Open transcript preview, highlight last user message |
| `Esc` (repeated) | Backtrack mode | Walk backward through user messages |
| `Enter` | Backtrack mode | Confirm; fork conversation from selected point, pre-fill composer |
| `Ctrl+C` | Any | Interrupt / close session |
| `Ctrl+D` | Any | Exit application |
| `Ctrl+L` | Any | Clear screen without starting new conversation |
| `Ctrl+G` | Composer | Open external editor ($VISUAL or $EDITOR) for drafting prompt |
| `Up/Down` | Composer | Navigate draft history |
| `@` | Composer | Open fuzzy file search to mention/attach files |
| `$` | Composer | Open skill picker to mention/invoke a skill |
| `!` | Composer (prefix) | Run a local shell command inline (e.g., `!ls`, `!git status`) |
| `/` | Composer (prefix) | Open slash command popup |
| `o` | Approval prompt (subagent) | Open subagent thread before approving/rejecting |

### Input Modes

- **No vim mode** -- Codex does not support vim-style keybindings in the composer
- **External editor support** via `Ctrl+G` (opens $VISUAL/$EDITOR) as alternative
- **Multi-line input** via external editor only
- **No Ctrl+R history search** -- history navigation via Up/Down arrows and Esc-based transcript walking
- **Shell escape** via `!` prefix for inline shell command execution

---

## 4. Tool System (3-4 core tools + MCP extensibility)

### Built-in Tools

Codex uses a **shell-first philosophy** with a minimal tool surface:

| Tool | Description |
|------|-------------|
| **Shell executor** (`shell` / `container.exec`) | Primary tool: executes shell commands. All file reading (cat, grep, find, ls), test running, git operations, etc. go through this single tool |
| **apply_patch** | File editing via unified diff format. Model generates patches; CLI intercepts and applies internally via Rust `process_patch`. Displays colorized diffs for approval |
| **Web search** | First-party web search tool (cached by default, live optional). Returns pre-indexed results to reduce prompt injection exposure |
| **js_repl** | JavaScript REPL for code execution. Supports dynamic `.js`/`.mjs` file imports from workspace. State persists across cells |
| **request_permissions** | Runtime permission escalation tool (v0.113.0+). Allows agent to request additional permissions mid-session |
| **Image generation** | Generates images and saves to CWD (model-dependent capability) |

### MCP Server Support

Codex supports the Model Context Protocol for tool extensibility:

- **STDIO servers**: Local processes started by command with env vars
- **Streamable HTTP servers**: Remote servers accessed via URL with bearer token or OAuth auth
- **Configuration**: `~/.codex/config.toml` or `.codex/config.toml` (project-scoped)
- **Management CLI**: `codex mcp add|list|get|login|logout|remove`
- **In-session**: `/mcp` slash command lists available MCP tools
- **Tool filtering**: `enabled_tools` (allowlist) and `disabled_tools` (denylist) per server
- **Timeouts**: `startup_timeout_sec` (default 10s), `tool_timeout_sec` (default 60s)
- **OAuth**: `codex mcp login <name>` with configurable callback ports and redirect URIs
- **Codex as MCP server**: `codex mcp-server` runs Codex as an MCP server over stdio for consumption by other agents. Exposes `codex()` and `codex-reply()` tools

### Tool Approval Model

- Destructive MCP/app tool calls **always require approval** when the tool advertises a destructive annotation
- Read operations may auto-approve depending on approval policy
- Smart approvals may propose new execpolicy rules during escalation

---

## 5. Context Management

### Context Window

- Model-dependent context windows (gpt-5.4 uses up to 272K tokens)
- Configurable via `model_context_window` in config.toml
- `/status` displays current token usage (input, output, cached breakdown)

### Compaction / Compression

- **Manual compaction**: `/compact` summarizes conversation to free tokens
- **Auto-compaction**: Triggers at configurable threshold (`model_auto_compact_token_limit`, approximately 95% capacity)
- Auto-compaction cannot currently be fully disabled (community feature request open)
- Compaction replaces earlier turns with a concise summary while preserving critical details

### File Mentions

- **`@` syntax**: Type `@` in composer to open fuzzy file search (respects `.gitignore`, including parent directories)
- **`/mention` command**: Explicitly attach a file to conversation context
- **`@plugin` mentions**: Reference installed plugins directly in chat (v0.112.0+)
- **Lazy loading**: Codex only reads files the model explicitly requests (keeps token usage low)

### Image Support

- `-i` / `--image` flags with PNG/JPEG support
- Comma-separated filenames for multiple images
- Screenshots and design specs can be attached
- Image generation output saved to CWD

### Codebase Indexing

- No built-in codebase indexing/embedding system
- Relies on lazy file reading via shell commands (cat, grep, find)
- AGENTS.md files provide project-specific context at each directory level
- Web search provides supplementary context (cached or live)

---

## 6. Session Management

### Session Storage

- Transcripts stored as JSONL files at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
- Contains full conversation history, tool calls, and token usage
- Configurable via `history.persistence` (save-all | none) and `history.max_bytes`

### Session Resume

| Command | Description |
|---------|-------------|
| `codex resume` | Interactive picker of recent sessions |
| `codex resume --all` | Sessions from any directory |
| `codex resume --last` | Most recent session, no picker |
| `codex resume <SESSION_ID>` | Specific session by UUID |
| `codex exec resume` | Resume non-interactive sessions |
| `codex exec resume --last` | Resume most recent non-interactive session |

### Session Forking

- `/fork` clones current conversation into a new thread with fresh ID
- `codex fork` CLI command opens session picker for forking saved sessions
- Original transcript remains untouched

### Context Carry-over

- Resumed sessions retain original transcript, plan history, and approvals
- Prior context available while supplying new instructions
- `/new` starts fresh conversation within same session (no carry-over)

---

## 7. Configuration

### Config File Format

- **Format**: TOML (`config.toml`)
- **User-level**: `~/.codex/config.toml` (or `$CODEX_HOME/config.toml`)
- **Project-level**: `.codex/config.toml` (trusted projects only)
- **CLI overrides**: `-c key=value` or `--config key=value` (TOML syntax, dot notation for nesting)

### Settings Hierarchy (precedence order, highest first)

1. CLI flags (`--model`, `--sandbox`, etc.)
2. CLI `-c key=value` overrides
3. Project `.codex/config.toml` (closest directory wins; trusted projects only)
4. User `~/.codex/config.toml`
5. Built-in defaults

### Instruction Files

- **AGENTS.md**: Primary instruction file. Discovered per-directory from project root to CWD
- **AGENTS.override.md**: Takes precedence over AGENTS.md when present at same directory level
- **Merge strategy**: At most one file per directory; concatenated root-down (later = higher priority)
- **Fallback filenames**: Configurable via `project_doc_fallback_filenames`
- **Size limit**: `project_doc_max_bytes` per file
- **Global**: `~/.codex/AGENTS.md` for personal cross-project instructions
- **`/init`**: Scaffolds a new AGENTS.md for current repo

### Profiles

- Named configuration sets: `[profiles.<name>]` in config.toml
- Activate via `--profile <name>` or `profile = "<name>"` default
- Can override any top-level key including model, sandbox, approval policy

### Key Configuration Sections

| Section | Notable Keys |
|---------|-------------|
| Core | `model`, `model_provider`, `model_context_window`, `model_reasoning_effort`, `model_verbosity` |
| Agents | `agents.max_threads` (default 6), `agents.max_depth` (default 1), `agents.<name>.description`, `agents.<name>.config_file` |
| Sandbox | `approval_policy`, `sandbox_mode`, `sandbox_workspace_write.writable_roots`, `sandbox_workspace_write.network_access` |
| Shell | `shell_environment_policy.inherit`, `shell_environment_policy.set`, `shell_environment_policy.exclude` |
| Features | `features.shell_tool`, `features.unified_exec`, `features.multi_agent`, `features.undo`, `features.fast_mode`, `features.personality`, `features.sqlite` |
| Web search | `web_search` (disabled | cached | live) |
| MCP | `mcp_servers.<id>.command`, `mcp_servers.<id>.url`, `mcp_servers.<id>.enabled_tools`, `mcp_servers.<id>.disabled_tools` |
| TUI | `tui.theme`, `tui.notifications`, `tui.animations`, `tui.alternate_screen` |
| History | `history.persistence`, `history.max_bytes` |
| OTel | `otel.exporter`, `otel.log_user_prompt` |
| Providers | `model_providers.<id>.base_url`, `model_providers.<id>.env_key`, `model_providers.<id>.wire_api` |

### Environment Variables

- `CODEX_HOME`: Override config directory (default `~/.codex`)
- `OPENAI_API_KEY`: API key for authentication
- `OPENAI_BASE_URL`: Redirect OpenAI provider without config edit
- `VISUAL` / `EDITOR`: External editor for Ctrl+G prompt editing

---

## 8. Git Integration

### Built-in Git Features

- **Protected paths**: `.git`, `.agents`, `.codex` directories are read-only even in workspace-write sandbox
- **Git repo detection**: Warns when running outside a git repository; `project_root_markers` defaults to `.git`
- **`/diff` command**: Shows git changes including untracked files
- **`/review` command**: Dedicated reviewer with three modes:
  - Review against base branch (finds merge base, diffs your work)
  - Review uncommitted changes (staged, unstaged, untracked)
  - Review specific commits (lists recent, reads exact changeset)
- **Custom review model**: `review_model` config override for code review
- **Commit attribution**: Automatic co-author trailer via `prepare-commit-msg` hook. Configurable via `commit_attribution` (default label, custom, or disable)

### What It Does NOT Have Built-in

- No dedicated PR creation tool (uses shell `gh` commands via agent)
- No dedicated branch management tools (uses shell `git` commands via agent)
- No auto-commit feature (community feature requests exist)
- No structured diff viewing tool (uses shell-based git diff via agent)

---

## 9. Security & Sandboxing

### Two-Layer Security Model

**Layer 1: Sandbox Mode** (what is technically possible)

| Mode | File Read | File Write | Commands | Network |
|------|-----------|------------|----------|---------|
| `read-only` | Anywhere | Blocked | Blocked | Blocked |
| `workspace-write` (default) | Anywhere | CWD + /tmp only | In workspace | Blocked (unless enabled) |
| `danger-full-access` | Anywhere | Anywhere | Anywhere | Allowed |

**Layer 2: Approval Policy** (when to pause for user consent)

| Policy | Behavior |
|--------|----------|
| `on-request` | Prompts for workspace escalation, network, external edits |
| `untrusted` | Auto-approves reads; requires approval for state-mutating commands |
| `never` | Skips all approval prompts (respects sandbox constraints) |
| Granular reject | Auto-rejects specific categories while keeping others interactive |

### Preset Combinations

| Flag | Sandbox | Approval | Behavior |
|------|---------|----------|----------|
| (default) | workspace-write | on-request | Auto mode: read/edit workspace, ask for network/external |
| `--sandbox read-only` | read-only | on-request | Safe browsing, approve all changes |
| `--full-auto` | workspace-write | never | Low-friction local work |
| `--yolo` / `--dangerously-bypass-approvals-and-sandbox` | none | none | No sandbox, no approvals |

### OS-Level Sandbox Implementation

| Platform | Technology | Details |
|----------|-----------|---------|
| macOS | Apple Seatbelt | `sandbox-exec` with profile restricting filesystem to project dir; blocks network except OpenAI API |
| Linux (default) | Landlock + seccomp | Kernel-level filesystem and syscall restrictions |
| Linux (opt-in) | Bubblewrap (bwrap) | `features.use_linux_sandbox_bwrap = true`; uses managed proxy for egress; fails closed if proxy routes unavailable |
| Windows | Experimental native sandbox | Added March 2026; still considered experimental |

### Execution Policy (execpolicy)

- **Rule files**: `.rules` files in `.codex/rules/` directories, written in **Starlark** (Python-like)
- **Rule type**: `prefix_rule()` with `pattern`, `decision` (allow | prompt | forbidden), `justification`
- **Matching**: Most restrictive decision wins when multiple rules match
- **Shell splitting**: Simple `&&`/`||`/`;`/`|` chains are split and evaluated individually; complex scripts treated as single command
- **Testing**: `codex execpolicy check --pretty --rules <file> -- <command>`
- **Smart approvals**: May propose new rules during escalation requests
- **User layer**: `~/.codex/rules/default.rules` (written when you approve in TUI)
- **Admin layer**: Enforceable via `requirements.toml`

### Protected Paths

Even in workspace-write mode, these are recursively read-only:
- `<root>/.git` (including gitdir pointers)
- `<root>/.agents`
- `<root>/.codex`

### Network Controls

- Network disabled by default in workspace-write mode
- Enable: `[sandbox_workspace_write] network_access = true`
- Managed proxy mode (bwrap pipeline): allowlist/denylist of domains
- Hardened proxy policy parsing rejects global wildcard domains (v0.113.0)

---

## 10. Agent Features

### Plan Mode

- Toggle via `/plan` slash command or `Shift+Tab`
- **On by default** from v0.96+
- Gathers information, conducts research, presents step-by-step plan before execution
- User reviews and approves plan before any code changes
- ExecPlans maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective sections

### Multi-Agent / Subagent Support (Experimental)

- Enable via `/experimental` or `features.multi_agent = true` in config.toml
- **Thread management**: `/agent` to switch between active threads
- **Spawning**: Codex auto-decides when to spawn subagents or responds to explicit requests
- **Concurrent threads**: Configurable via `agents.max_threads` (default 6)
- **Nesting depth**: `agents.max_depth` (default 1)
- **Built-in roles**: default, worker, explorer, monitor
- **Custom roles**: `[agents.<name>]` with description, config_file, nickname_candidates
- **Batch processing**: `spawn_agents_on_csv` for many similar tasks; workers call `report_agent_job_result`
- **Approval flow**: Sub-agents inherit parent sandbox; approval requests surface from inactive threads
- **Wait tool**: Polling windows up to 1 hour per call
- **Handoffs**: Carry realtime transcript context (v0.114.0)

### Non-Interactive / Headless Mode

- `codex exec` (alias `codex e`) for scripted/CI workflows
- Prompt via positional arg or stdin
- `--json` for newline-delimited JSON output
- `--output-last-message <path>` writes final message to file
- `--output-schema <path>` for JSON Schema output validation
- `--ephemeral` runs without persisting session files
- `--skip-git-repo-check` allows running outside git repos
- Resume: `codex exec resume [--last | SESSION_ID]`

### Cloud Execution

- `codex cloud exec --env ENV_ID "<prompt>"` for remote task execution
- `--attempts 1-4` for best-of-N runs
- `codex cloud list` with filtering, pagination, JSON output
- `codex apply <TASK_ID>` applies latest cloud diff to local repo
- Cloud environments: custom setup scripts, dependency installation, cached container resume

### GitHub Action

- `openai/codex-action@v1` for CI/CD integration
- Installs Codex CLI, starts Responses API proxy
- Runs `codex exec` with specified permissions
- Use cases: auto-fix CI failures, code review, release prep

### Agents SDK Integration

- `codex mcp-server` exposes Codex as MCP server
- Two tools: `codex()` (start conversation) and `codex-reply()` (continue)
- Supports parallel task execution with multiple agents
- Auditable handoffs with full traces

---

## 11. UI/UX Features

### TUI Framework

- Built with **Ratatui** (Rust) + **Crossterm** for terminal event handling
- Event-driven architecture: KeyEvent, Scroll, CodexEvent, Redraw
- Two-pane layout: ConversationHistoryWidget (upper) + BottomPane (input/approval)
- Alternate screen mode: configurable (auto | always | never) via `tui.alternate_screen`
- `--no-alt-screen` flag to disable alternate screen

### Themes & Syntax Highlighting

- `/theme` command for live preview and persistence
- Custom `.tmTheme` file support for syntax highlighting
- `tui.theme` config key
- Syntax-highlighted code blocks and diffs (deletions in red, additions in green)
- Known issues: hardcoded diff background colors ignore .tmTheme settings; poor light-theme support

### Status Line

- `/statusline` command: picker to toggle and reorder items
- Available items: model, model+reasoning, context stats, rate limits, git branch, token counters, session ID, CWD/project root, Codex version
- Fast mode indicator in TUI header (v0.111.0+)
- Persists to `tui.status_line` in config.toml

### Markdown Rendering

- Full markdown rendering in conversation display
- Syntax-highlighted code blocks
- Colorized diffs for file edits
- Inline display of shell command output

### Notifications

- Desktop notifications for unfocused terminals
- Configurable: `tui.notifications` (boolean | array of event types)
- Custom notification program support

### Other UI Features

- Animations: `tui.animations` (default true)
- Mouse wheel scrolling
- File opener for citations: `file_opener` (vscode | cursor | windsurf | none)
- `codex app` launches macOS desktop app

---

## 12. Extensibility & Integration

### Skills System

Skills are the primary extensibility mechanism, packaging instructions, resources, and optional scripts.

**Skill Structure**:
```
skill-name/
  SKILL.md           # Required: name, description, instructions
  scripts/           # Optional: executable scripts
  references/        # Optional: supporting docs
  assets/            # Optional: templates and resources
  agents/openai.yaml # Optional: UI config, tool deps
```

**Discovery Locations** (scanned in order):
1. `.agents/skills` in working directory (folder-specific)
2. `.agents/skills` in parent directories (shared team)
3. `$REPO_ROOT/.agents/skills` (organization-wide)
4. `$HOME/.agents/skills` (personal cross-project)
5. `/etc/codex/skills` (system-level admin)
6. Bundled with Codex (built-in: skill-creator, skill-installer)

**Invocation**:
- Explicit: `$skill-name` in composer, or `/skills` picker
- Implicit: Codex auto-selects when task matches skill description
- Progressive disclosure: Only metadata loaded at startup; full SKILL.md loaded on invocation

**Built-in Skills**:
- `$skill-creator`: Guided skill creation
- `$skill-installer`: Install community/curated skills

**Configuration**: Disable skills via `[[skills.config]]` in config.toml without deletion. `allow_implicit_invocation` policy per skill.

### Plugin System (v0.110.0+)

- Plugins can package skills, MCP entries, and app connectors
- `/apps` command: Browse available/installed apps and connectors
- `@plugin` mentions: Reference plugins directly in chat (v0.112.0+)
- Plugin marketplace: Discovery, metadata, categories, install-time auth checks
- Management: `codex plugin list|install|uninstall`

### MCP Protocol Support

Full MCP support (see Section 4). Both consumer and server roles.

### SDK

- **Codex SDK**: Available for programmatic integration
- **Agents SDK**: Integration via MCP server mode
- **GitHub Action**: `openai/codex-action@v1`

### IDE Integrations

- **VS Code extension** (official, closed-source): Same agent as CLI, shared config
- **Cursor, Windsurf**: Compatible via VS Code extension
- **JetBrains**: Community bridge project (Codex-JetBrains)
- Modes: Agent, Chat, Agent (Full Access)

---

## 13. Model & Provider

### Supported OpenAI Models

| Model | Description | Access |
|-------|-------------|--------|
| `gpt-5.4` | Flagship frontier model (recommended) | CLI, App, IDE, Cloud, API |
| `gpt-5.3-codex` | Industry-leading coding model | All platforms |
| `gpt-5.3-codex-spark` | Real-time iteration (text-only, research preview) | ChatGPT Pro only |
| `gpt-5.2-codex` | Prior generation coding model | All platforms |
| `gpt-5.2` | Prior generation general model | All platforms |
| `gpt-5.1-codex-max` | Extended context variant | All platforms |
| `gpt-5.1-codex` | Prior generation coding model | All platforms |
| `gpt-5.1` | Prior generation general model | All platforms |
| `gpt-5-codex` | Original Codex-optimized model | All platforms |
| `gpt-5-codex-mini` | Smaller, faster variant | All platforms |
| `gpt-5` | Base GPT-5 | All platforms |

### Open-Source / Local Models

- **gpt-oss:20b** (21B params, 3.6B active, 128K context)
- **gpt-oss:120b** (117B params, 5.1B active, 128K context)
- **`--oss` flag**: Use local open-source model provider
- **Ollama integration**: Native since 2026-01-15
- **LM Studio**: Supported via custom provider config
- **MLX**: Supported via custom provider config

### Custom Providers

- `model_providers.<id>.base_url`: API endpoint
- `model_providers.<id>.env_key`: API key env var
- `model_providers.<id>.wire_api`: Chat Completions or Responses API
- `model_providers.<id>.http_headers`: Static headers
- `model_providers.<id>.supports_websockets`: WebSocket support
- Azure, Mistral, and any OpenAI-compatible API supported

### Model Switching

- `--model` / `-m` flag at launch
- `/model` command mid-session
- `model_reasoning_effort`: minimal | low | medium | high | xhigh
- `model_reasoning_summary`: auto | concise | detailed | none
- `model_verbosity`: low | medium | high
- Fast mode: `/fast` toggle with service tier support

### Token Usage Display

- `/status` shows total tokens, input tokens, cached tokens, output tokens
- Token counting events emitted since v0.98+
- Status line can display real-time token counters

---

## 14. Memory System (v0.100.0+)

### Architecture

Persistent cross-session knowledge base via two-phase async pipeline:

**Phase 1 (Rollout Extraction)**:
- Processes individual session rollouts
- Extracts structured `raw_memory`, `rollout_summary`, `rollout_slug`
- Runs in parallel (bounded by CONCURRENCY_LIMIT)
- Eligibility: non-ephemeral, non-sub-agent, memory-enabled sessions
- Redacts secrets before storage

**Phase 2 (Global Consolidation)**:
- Serialized singleton process
- Runs consolidation sub-agent (WorkspaceWrite sandbox, no network)
- Produces MEMORY.md, memory_summary.md, and optional skills
- Watermark logic prevents redundant runs

### Storage

```
~/.codex/memories/
  MEMORY.md                     # Task-grouped handbook
  memory_summary.md             # User profile + tips
  raw_memories.md               # Merged Phase 1 outputs
  rollout_summaries/            # Per-session summaries
  skills/<name>/SKILL.md        # Auto-generated reusable procedures
```

SQLite backing store: `codex_home/state_<version>.sqlite`

### Memory Pollution & Forgetting

- Threads using web search are marked `polluted` and excluded
- Consolidation applies targeted forgetting for removed/polluted threads
- Thread modes: enabled, disabled, polluted

### Configuration

- `max_rollouts_per_startup`: Phase 1 job limit per session
- `max_rollout_age_days`: Exclude old rollouts
- `min_rollout_idle_hours`: Require idle period
- `extract_model` / `consolidation_model`: Model overrides
- `no_memories_if_mcp_or_web_search`: Disable if external tools detected
- `codex debug clear-memories`: Full memory reset

---

## 15. Observability (OpenTelemetry)

### OTel Integration

- **Disabled by default** (opt-in via `[otel]` table in config.toml)
- Exporters: `otlp-http`, `otlp-grpc`, or `none`
- Separate trace and metrics exporter configuration
- `log_user_prompt = false` by default (prompts may contain source code/secrets)

### What Gets Exported

- Outbound API requests and streamed responses
- User input (when `log_user_prompt = true`)
- Tool-approval decisions
- Tool invocation results
- Token attributes: `input_token_count`, `output_token_count`, `cached_token_count`, `reasoning_token_count`, `tool_token_count`

### Analytics

- `[analytics] enabled = true` by default for metrics collection
- Disable feedback submission separately
- No telemetry in `codex exec` mode or `codex mcp-server` mode

---

## Feature Count Summary

| Category | Count |
|----------|-------|
| Slash commands | 28+ built-in |
| Hook event types | 2 native (SessionStart, Stop) + 3 compat (TaskStarted, TaskComplete, TurnAborted) |
| Keyboard shortcuts | 14+ distinct bindings |
| Built-in tools | 6 (shell, apply_patch, web_search, js_repl, request_permissions, image_gen) |
| MCP capabilities | Full consumer + server support |
| Sandbox modes | 3 (read-only, workspace-write, danger-full-access) |
| Approval policies | 3 + granular reject (on-request, untrusted, never) |
| OS sandbox implementations | 4 (Seatbelt, Landlock+seccomp, bwrap, Windows experimental) |
| Supported models | 11+ OpenAI models + 2 open-source + any compatible provider |
| Agent roles | 4 built-in + custom |
| Skill discovery paths | 6 locations |
| Config file format | TOML |
| Session management commands | 6+ (resume, fork, new, resume --last, resume --all, exec resume) |
| Platforms | macOS, Linux, Windows (experimental), WSL |
| Installation methods | npm, Homebrew, GitHub release binaries |
