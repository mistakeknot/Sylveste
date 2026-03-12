# Claude Code Feature Inventory (Deep Research 2026-03-12)

> Sources:
> - https://code.claude.com/docs/en/interactive-mode
> - https://code.claude.com/docs/en/hooks
> - https://code.claude.com/docs/en/cli-reference
> - https://code.claude.com/docs/en/permissions
> - https://code.claude.com/docs/en/settings
> - https://code.claude.com/docs/en/sub-agents
> - https://code.claude.com/docs/en/memory
> - https://code.claude.com/docs/en/sandboxing
> - https://code.claude.com/docs/en/model-config
> - https://code.claude.com/docs/en/skills
> - https://code.claude.com/docs/en/plugins
> - https://code.claude.com/docs/en/mcp
> - https://code.claude.com/docs/en/checkpointing
> - https://code.claude.com/docs/en/github-actions
> - https://code.claude.com/docs/en/vs-code
> - https://code.claude.com/docs/en/scheduled-tasks
> - https://code.claude.com/docs/en/claude-code-on-the-web
> - https://code.claude.com/docs/en/output-styles
> - https://code.claude.com/docs/en/monitoring-usage
> - https://code.claude.com/docs/en/costs

---

## 1. Slash Commands (50+ total)

Claude Code has 50+ built-in slash commands plus bundled skills and user-defined commands/skills. Type `/` to see all, or type letters after `/` to filter.

### Built-in Commands (46 listed)

| Command | Purpose |
|---|---|
| `/add-dir <path>` | Add additional working directory to the session |
| `/agents` | Manage subagent configurations |
| `/btw <question>` | Ask a side question without adding to conversation history |
| `/chrome` | Configure Chrome browser integration settings |
| `/clear` | Clear conversation history (aliases: `/reset`, `/new`) |
| `/compact [instructions]` | Compact conversation with optional focus instructions |
| `/config` | Open settings interface (alias: `/settings`) |
| `/context` | Visualize current context usage as colored grid with optimization suggestions |
| `/copy` | Copy last assistant response to clipboard; interactive picker for code blocks |
| `/cost` | Show token usage statistics |
| `/desktop` | Continue session in Claude Code Desktop app (macOS/Windows; alias: `/app`) |
| `/diff` | Interactive diff viewer: uncommitted changes + per-turn diffs |
| `/doctor` | Diagnose and verify installation and settings |
| `/exit` | Exit the CLI (alias: `/quit`) |
| `/export [filename]` | Export conversation as plain text (to file or clipboard) |
| `/extra-usage` | Configure extra usage for rate limit overflow |
| `/fast [on\|off]` | Toggle fast mode |
| `/feedback [report]` | Submit feedback (alias: `/bug`) |
| `/fork [name]` | Fork current conversation at this point |
| `/help` | Show help and available commands |
| `/hooks` | Manage hook configurations |
| `/ide` | Manage IDE integrations and show status |
| `/init` | Initialize project with CLAUDE.md guide |
| `/insights` | Generate report analyzing session history, patterns, friction |
| `/install-github-app` | Set up Claude GitHub Actions for a repo |
| `/install-slack-app` | Install Claude Slack app via OAuth |
| `/keybindings` | Open/create keybindings configuration file |
| `/login` | Sign in to Anthropic account |
| `/logout` | Sign out |
| `/mcp` | Manage MCP server connections and OAuth |
| `/memory` | Edit CLAUDE.md files, toggle auto-memory, view entries |
| `/mobile` | Show QR to download Claude mobile app (aliases: `/ios`, `/android`) |
| `/model [model]` | Select/change AI model; adjust effort with arrow keys |
| `/passes` | Share free Claude Code week with friends (if eligible) |
| `/permissions` | View/update permissions (alias: `/allowed-tools`) |
| `/plan` | Enter plan mode directly |
| `/plugin` | Manage plugins |
| `/pr-comments [PR]` | Fetch/display GitHub PR comments |
| `/privacy-settings` | View/update privacy settings (Pro/Max only) |
| `/release-notes` | View full changelog |
| `/reload-plugins` | Reload all active plugins without restart |
| `/remote-control` | Make session available for remote control from claude.ai (alias: `/rc`) |
| `/remote-env` | Configure default remote environment for teleport sessions |
| `/rename [name]` | Rename session; auto-generates from history if no name given |
| `/resume [session]` | Resume conversation by ID/name or open picker (alias: `/continue`) |
| `/review` | Deprecated; install `code-review` plugin instead |
| `/rewind` | Rewind conversation/code to previous point (alias: `/checkpoint`) |
| `/sandbox` | Toggle sandbox mode |
| `/security-review` | Analyze pending branch changes for security vulnerabilities |
| `/skills` | List available skills |
| `/stats` | Visualize daily usage, session history, streaks, model preferences |
| `/status` | Show version, model, account, connectivity |
| `/statusline` | Configure status line (describe desired content or auto-configure) |
| `/stickers` | Order Claude Code stickers |
| `/tasks` | List and manage background tasks |
| `/terminal-setup` | Configure terminal keybindings (Shift+Enter, etc.) |
| `/theme` | Change color theme (light/dark, daltonized, ANSI) |
| `/upgrade` | Open upgrade page for higher plan tier |
| `/usage` | Show plan usage limits and rate limit status |
| `/vim` | Toggle between Vim and Normal editing modes |

### Bundled Skills (5)

| Skill | Purpose |
|---|---|
| `/simplify` | Reviews recently changed files for reuse/quality/efficiency; spawns 3 parallel review agents |
| `/batch <instruction>` | Orchestrate large-scale parallel changes across codebase; spawns agents in isolated worktrees |
| `/debug [description]` | Troubleshoot current session by reading debug log |
| `/loop [interval] <prompt>` | Run prompt repeatedly on interval (cron-style scheduling) |
| `/claude-api` | Load Claude API reference material for your project's language; auto-triggers on anthropic imports |

### Custom Commands & Skills

- **Legacy commands**: `.claude/commands/` (project) and `~/.claude/commands/` (user)
- **Skills (recommended)**: `.claude/skills/<name>/SKILL.md` (project), `~/.claude/skills/<name>/SKILL.md` (user)
- **Plugin skills**: namespaced as `/plugin-name:skill-name`
- **MCP prompts**: `/mcp__<server>__<prompt>` (dynamically discovered from connected servers)
- Skills support YAML frontmatter for configuration: `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `context`, `agent`, `hooks`
- Skills support `$ARGUMENTS`, `$ARGUMENTS[N]`, `$N`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` substitutions
- Skills support `context: fork` to run in isolated subagent
- Skills support `!`backtick` syntax for dynamic shell command injection before sending to Claude
- Skills can include supporting files (templates, examples, scripts) alongside SKILL.md

---

## 2. Hook System (17 event types)

Hooks are user-defined shell commands, HTTP endpoints, LLM prompts, or agent invocations that execute at specific lifecycle points.

### Hook Event Types (17)

| Event | When it fires | Matcher input | Can block/modify? |
|---|---|---|---|
| `SessionStart` | Session begins or resumes | How started: `startup`, `resume`, `clear`, `compact` | Async only |
| `UserPromptSubmit` | User submits prompt, before Claude processes | No matcher support | Can modify prompt |
| `PreToolUse` | Before tool call executes | Tool name (e.g. `Bash`, `Edit\|Write`) | Can block (deny), approve, modify input |
| `PermissionRequest` | When permission dialog appears | Tool name | Can approve/deny |
| `PostToolUse` | After tool call succeeds | Tool name | Can inject context |
| `PostToolUseFailure` | After tool call fails | Tool name | Can inject context |
| `Notification` | When Claude Code sends notification | Type: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog` | Async only |
| `SubagentStart` | When subagent is spawned | Agent type name | Async only |
| `SubagentStop` | When subagent finishes | Agent type name | Can inject context |
| `Stop` | When Claude finishes responding | No matcher support | Can force continue or inject context |
| `TeammateIdle` | Agent team teammate going idle | No matcher support | Can inject work |
| `TaskCompleted` | Task being marked complete | No matcher support | Can block completion |
| `InstructionsLoaded` | CLAUDE.md or rules file loaded into context | No matcher support | Async only |
| `ConfigChange` | Configuration file changes during session | Source: `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills` | Async only |
| `WorktreeCreate` | Worktree being created | No matcher support | Replaces default git behavior |
| `WorktreeRemove` | Worktree being removed | No matcher support | Replaces default cleanup |
| `PreCompact` | Before context compaction | Trigger: `manual`, `auto` | Can inject context |
| `SessionEnd` | Session terminates | Reason: `clear`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other` | Async only |

### Hook Handler Types (4+)

1. **Command hooks**: Run shell scripts; receive JSON on stdin, return JSON on stdout
2. **HTTP hooks**: POST to endpoint; receive JSON body, return JSON response
3. **Prompt hooks**: LLM-powered hooks that evaluate context
4. **Agent hooks**: Invoke subagent-style handlers
5. **MCP tool hooks**: Invoke MCP server tools

### Hook Configuration

- Defined in settings.json files (user, project, local, managed, plugin, skill/agent frontmatter)
- Matcher is a regex string filtering when hooks fire
- Exit codes: 0 = allow, 1 = error (non-fatal), 2 = block/deny
- Hooks can be async (non-blocking) or synchronous
- JSON output can include `hookSpecificOutput` with event-specific decisions
- `PreToolUse` hooks can return `permissionDecision`: `"allow"`, `"deny"`, `"ask"`
- Hooks can modify tool input and inject additional context for Claude

---

## 3. Keyboard Shortcuts & Input (30+ keybindings)

### General Controls (13)

| Shortcut | Description |
|---|---|
| `Ctrl+C` | Cancel current input or generation |
| `Ctrl+F` | Kill all background agents (press twice within 3s to confirm) |
| `Ctrl+D` | Exit session (EOF signal) |
| `Ctrl+G` | Open prompt in default text editor |
| `Ctrl+L` | Clear terminal screen (keeps history) |
| `Ctrl+O` | Toggle verbose output |
| `Ctrl+R` | Reverse search command history |
| `Ctrl+V` / `Cmd+V` / `Alt+V` | Paste image from clipboard |
| `Ctrl+B` | Background running tasks (tmux users: press twice) |
| `Ctrl+T` | Toggle task list |
| `Esc + Esc` | Rewind or summarize |
| `Shift+Tab` / `Alt+M` | Toggle permission modes (Auto-Accept, Plan, Normal) |
| `Alt+P` / `Option+P` | Switch model |
| `Alt+T` / `Option+T` | Toggle extended thinking |

### Text Editing (6)

| Shortcut | Description |
|---|---|
| `Ctrl+K` | Delete to end of line |
| `Ctrl+U` | Delete entire line |
| `Ctrl+Y` | Paste deleted text |
| `Alt+Y` (after Ctrl+Y) | Cycle paste history |
| `Alt+B` | Move cursor back one word |
| `Alt+F` | Move cursor forward one word |

### Multiline Input (5 methods)

| Method | Shortcut |
|---|---|
| Quick escape | `\` + `Enter` |
| macOS default | `Option+Enter` |
| Shift+Enter | `Shift+Enter` (native in iTerm2, WezTerm, Ghostty, Kitty) |
| Control sequence | `Ctrl+J` |
| Paste mode | Paste directly |

### Quick Commands (3)

| Prefix | Description |
|---|---|
| `/` at start | Slash command or skill |
| `!` at start | Bash mode (run commands directly, output added to context) |
| `@` | File path mention with autocomplete |

### Vim Mode

Full vim-style editing with `/vim` command or permanently via `/config`:

- **Mode switching**: `Esc`, `i`, `I`, `a`, `A`, `o`, `O`
- **Navigation**: `h`/`j`/`k`/`l`, `w`/`e`/`b`, `0`/`$`/`^`, `gg`/`G`, `f`/`F`/`t`/`T`/`;`/`,`
- **Editing**: `x`, `dd`, `D`, `dw`/`de`/`db`, `cc`, `C`, `cw`/`ce`/`cb`, `yy`/`Y`, `yw`/`ye`/`yb`, `p`/`P`, `>>`/`<<`, `J`, `.`
- **Text objects**: `iw`/`aw`, `iW`/`aW`, `i"`/`a"`, `i'`/`a'`, `i(`/`a(`, `i[`/`a[`, `i{`/`a{`

### Customizable Keybindings

- Fully customizable via JSON file (`/keybindings` to open)
- Organized by context with chord sequences and modifier combinations
- Can unbind any default binding

### Command History

- Per working directory input history
- Up/Down arrows to navigate
- `Ctrl+R` for reverse incremental search with highlighting
- History-based autocomplete for `!` bash mode (Tab to complete)
- History resets on `/clear`

---

## 4. Tool System (15+ built-in tools)

### Built-in Tools (15)

| Tool | Description |
|---|---|
| `Read` | Read files (text, images, PDFs, Jupyter notebooks); supports line offset/limit |
| `Write` | Create new files or complete rewrites |
| `Edit` | Exact string replacements in files (requires Read first); `replace_all` option |
| `MultiEdit` | Multiple edits in a single tool call |
| `Bash` | Execute shell commands; persistent working directory; configurable timeout |
| `Glob` | Fast file pattern matching (e.g., `**/*.js`) |
| `Grep` | Content search built on ripgrep; regex, multiline, context lines, file type filters |
| `WebSearch` | Search the web for up-to-date information |
| `WebFetch` | Fetch and process URL content |
| `Agent` | Spawn subagents for delegated tasks (formerly `Task`) |
| `AskUserQuestion` | Ask the user a clarifying question |
| `TodoRead` / `TodoWrite` | Read/write task list items |
| `NotebookEdit` | Edit Jupyter notebook cells |
| `TaskOutput` | Retrieve output from background tasks |
| `Skill` | Invoke a skill programmatically |

### MCP Server Support (3 transports)

| Transport | Description |
|---|---|
| `stdio` | Default; server runs as child process |
| `sse` | Server-Sent Events for remote servers (being deprecated) |
| `http` | Streamable HTTP; modern recommended transport for remote servers |

MCP configuration:
- `claude mcp add <name>` CLI command
- `.mcp.json` for project-scoped servers
- `~/.claude.json` for user-scoped servers
- `--mcp-config` flag for session-scoped servers
- `--strict-mcp-config` to ignore all other MCP configurations
- MCP servers expose tools, prompts (as slash commands), and resources
- Managed MCP settings: `allowedMcpServers`, `deniedMcpServers`, `allowManagedMcpServersOnly`
- MCP servers can be scoped to specific subagents via `mcpServers` frontmatter

### Tool Permission Model

- **Three-tier system**: Read-only (no approval), Bash (approval required, permanent per project), File modification (approval until session end)
- **Permission rules**: `allow`, `ask`, `deny` arrays in settings
- **Rule syntax**: `Tool`, `Tool(specifier)`, wildcard patterns with `*`
- **Evaluation order**: deny > ask > allow (first match wins)
- **Tool-specific rules**: Bash (glob patterns), Read/Edit (gitignore spec), WebFetch (`domain:` prefix), MCP (`mcp__server__tool`), Agent (`Agent(name)`)

---

## 5. Context Management

### Context Window

- **Standard**: 200K tokens
- **Extended**: 1M tokens (beta) for Opus 4.6 and Sonnet 4.6; requires extra usage enabled for subscribers
- `/context` command: visualize usage as colored grid with optimization suggestions
- Auto-compaction at ~95% capacity (configurable via `CLAUDE_CODE_AUTOCOMPACT_PCT_OVERRIDE`)
- Manual compaction via `/compact [focus instructions]`
- Session Memory writes continuous background summaries; `/compact` loads pre-written summary (instant)

### @-file Mentions

- Type `@` to trigger file path autocomplete
- Reference files to add them to context before Claude responds
- Custom file suggestion via `fileSuggestion` setting (external script)
- `respectGitignore` setting to exclude gitignored files from picker

### Image Support

- Paste images from clipboard: `Ctrl+V` / `Cmd+V` / `Alt+V`
- Copy/paste or drag-and-drop images into prompt
- Read tool can view image files (PNG, JPG, etc.) — multimodal

### PDF Support

- Read tool can read PDF files
- Large PDFs (10+ pages): must specify `pages` parameter (e.g., `"1-5"`)
- Maximum 20 pages per request

### Jupyter Notebook Support

- Read tool reads `.ipynb` files with all cells and outputs
- NotebookEdit tool for editing cells

### Prompt Suggestions

- Auto-generated suggestions based on git history and conversation
- Tab to accept, Enter to accept and submit
- Background request reusing prompt cache (minimal cost)
- Skipped when cache is cold, in non-interactive mode, and in plan mode
- Configurable via `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION`

---

## 6. Session Management

### Session Persistence

- Sessions stored as JSONL at `~/.claude/projects/<encoded-cwd>/*.jsonl`
- `<encoded-cwd>` replaces non-alphanumeric chars with `-`
- Each line is a JSON object with `type` field
- Configurable cleanup: `cleanupPeriodDays` setting (default: 30 days)
- `--no-session-persistence` flag to disable saving

### Session Resume

- `/resume [session]` or `claude -r <session>` — by ID or name, or interactive picker
- `claude -c` — continue most recent conversation in current directory
- `--fork-session` — create new session ID when resuming
- `--from-pr <number>` — resume sessions linked to a GitHub PR
- Sessions auto-linked when created via `gh pr create`

### Session Naming

- `/rename [name]` — rename session; auto-generates from history if no name given
- Sessions can be resumed by name

### Session Forking

- `/fork [name]` — create fork of current conversation
- `claude --continue --fork-session` — fork on resume

### Session Export

- `/export [filename]` — export as plain text to file or clipboard
- `--output-format json` — structured JSON output in print mode
- `--output-format stream-json` — streaming JSON output

### Session Teleportation

- Move sessions between local terminal and claude.ai/code web interface
- `--teleport` flag to resume a web session locally
- `--remote` flag to create a web session from CLI
- Full conversation history and code state preserved

---

## 7. Configuration

### Settings File Hierarchy (5 levels, highest precedence first)

1. **Managed settings** (MDM/registry/file) — cannot be overridden
   - macOS: `/Library/Application Support/ClaudeCode/managed-settings.json`
   - Linux/WSL: `/etc/claude-code/managed-settings.json`
   - Windows: `C:\Program Files\ClaudeCode\managed-settings.json`
2. **Command-line arguments** — temporary session overrides
3. **Local project settings** — `.claude/settings.local.json` (gitignored)
4. **Shared project settings** — `.claude/settings.json` (committed)
5. **User settings** — `~/.claude/settings.json`

Array-valued settings **merge** across scopes (not replace).

### CLAUDE.md Instruction Files

| Scope | Location |
|---|---|
| Managed policy | `/Library/Application Support/ClaudeCode/CLAUDE.md` (macOS), `/etc/claude-code/CLAUDE.md` (Linux) |
| Project | `./CLAUDE.md` or `./.claude/CLAUDE.md` |
| User | `~/.claude/CLAUDE.md` |

- `.claude/rules/*.md` — modular per-topic rules files
- Path-specific rules via `paths` YAML frontmatter (glob patterns)
- `@path/to/import` syntax for importing additional files (max depth 5)
- `claudeMdExcludes` setting to skip irrelevant CLAUDE.md files in monorepos
- Subdirectory CLAUDE.md files load lazily when Claude reads files in those directories
- Symlinks supported in `.claude/rules/`

### Auto Memory

- Claude automatically saves notes across sessions
- Storage: `~/.claude/projects/<project>/memory/MEMORY.md` + topic files
- First 200 lines of MEMORY.md loaded at session start
- Toggle via `/memory` or `autoMemoryEnabled` setting
- `autoMemoryDirectory` setting for custom location
- `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` to disable

### Environment Variables (60+)

Key categories:
- **Authentication**: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_CUSTOM_HEADERS`, `ANTHROPIC_FOUNDRY_API_KEY`, `AWS_BEARER_TOKEN_BEDROCK`
- **Model**: `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`, `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `CLAUDE_CODE_SUBAGENT_MODEL`
- **Feature toggles**: `CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_DISABLE_FAST_MODE`, `CLAUDE_CODE_DISABLE_CRON`, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`, `CLAUDE_CODE_DISABLE_1M_CONTEXT`, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`, `CLAUDE_CODE_SIMPLE`
- **Bash**: `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS`, `BASH_MAX_OUTPUT_LENGTH`, `CLAUDE_CODE_SHELL`, `CLAUDE_CODE_SHELL_PREFIX`, `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR`
- **Config/storage**: `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`
- **Telemetry**: `CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`
- **Agent teams**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_TEAM_NAME`
- **TLS**: `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`, `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE`
- **Prompt caching**: `DISABLE_PROMPT_CACHING`, `DISABLE_PROMPT_CACHING_HAIKU/SONNET/OPUS`
- **Account**: `CLAUDE_CODE_ACCOUNT_UUID`, `CLAUDE_CODE_USER_EMAIL`, `CLAUDE_CODE_ORGANIZATION_UUID`

### Key Settings Fields (40+)

`apiKeyHelper`, `autoMemoryDirectory`, `cleanupPeriodDays`, `companyAnnouncements`, `env`, `attribution`, `permissions`, `hooks`, `model`, `availableModels`, `modelOverrides`, `statusLine`, `fileSuggestion`, `outputStyle`, `language`, `autoUpdatesChannel`, `spinnerVerbs`, `spinnerTipsEnabled`, `spinnerTipsOverride`, `terminalProgressBarEnabled`, `prefersReducedMotion`, `alwaysThinkingEnabled`, `plansDirectory`, `showTurnDuration`, `teammateMode`, `fastModePerSessionOptIn`, `respectGitignore`, `forceLoginMethod`, `forceLoginOrgUUID`, `enableAllProjectMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `allowedMcpServers`, `deniedMcpServers`, `sandbox` (nested), `awsAuthRefresh`, `awsCredentialExport`, `effortLevel`, `otelHeadersHelper`, `claudeMdExcludes`

---

## 8. Git Integration

### Built-in Git Features

- **Auto-commit**: Claude creates git commits with configurable attribution
- **Diff viewing**: `/diff` — interactive diff viewer showing uncommitted changes and per-turn diffs
- **PR creation**: Via `gh pr create` through Bash tool; sessions auto-link to PRs
- **PR comments**: `/pr-comments [PR]` — fetch and display GitHub PR comments
- **PR review status**: Clickable PR link in footer with colored underline (green=approved, yellow=pending, red=changes requested, gray=draft, purple=merged); auto-updates every 60s
- **Branch management**: Full git operations through Bash tool
- **Security review**: `/security-review` — analyze pending branch changes for vulnerabilities

### Git Worktrees

- `claude -w <name>` or `--worktree` — start in isolated git worktree
- Auto-generated worktree names if not specified
- Worktrees stored at `<repo>/.claude/worktrees/<name>`
- Subagents can use `isolation: worktree` for isolated repository copies
- Auto-cleanup when subagent makes no changes
- `/batch` skill uses worktrees for parallel agent work

### Attribution Configuration

```json
{
  "attribution": {
    "commit": "Co-Authored-By: Claude <noreply@anthropic.com>",
    "pr": "Generated with Claude Code"
  }
}
```

Empty strings hide attribution.

### GitHub Actions Integration

- `claude-code-action` — official GitHub Action
- `/install-github-app` — set up Claude GitHub Actions for a repo
- Supports PR review, issue triage, code generation in CI/CD

---

## 9. Security & Sandboxing

### Permission Modes (5)

| Mode | Description |
|---|---|
| `default` | Standard: prompts for permission on first use |
| `acceptEdits` | Auto-accept file edits for the session |
| `plan` | Plan Mode: read-only analysis, no modifications |
| `dontAsk` | Auto-deny unless pre-approved via rules |
| `bypassPermissions` | Skip all checks (containers/VMs only) |

### Sandbox System

- **Filesystem isolation**: OS-level enforcement via Seatbelt (macOS) and bubblewrap (Linux/WSL2)
- **Network isolation**: Proxy-based domain restrictions; all child processes inherit boundaries
- **Two sandbox modes**: Auto-allow (sandboxed commands auto-approved) and Regular (standard permission flow)
- **Configurable paths**: `sandbox.filesystem.allowWrite`, `denyWrite`, `denyRead`
- **Network config**: `sandbox.network.allowedDomains`, `allowUnixSockets`, `allowLocalBinding`
- **Excluded commands**: `sandbox.excludedCommands` for incompatible tools (e.g., `docker`)
- **Custom proxy**: `sandbox.network.httpProxyPort`, `socksProxyPort`
- **Escape hatch**: Commands can retry outside sandbox via normal permission flow; disable with `allowUnsandboxedCommands: false`
- **Open source runtime**: `@anthropic-ai/sandbox-runtime` npm package

### Managed Security Settings

- `disableBypassPermissionsMode` — prevent bypass mode
- `allowManagedPermissionRulesOnly` — only managed permission rules apply
- `allowManagedHooksOnly` — only managed and SDK hooks allowed
- `allowManagedMcpServersOnly` — only managed MCP servers
- `sandbox.network.allowManagedDomainsOnly` — only managed domains
- `blockedMarketplaces` — block specific plugin sources
- `strictKnownMarketplaces` — allowlist plugin marketplaces
- `allow_remote_sessions` — control remote session access

### Network Security

- mTLS support: `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`, `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE`
- Proxy DNS resolution: `CLAUDE_CODE_PROXY_RESOLVES_HOSTS`
- HTTP hook URL allowlisting: `allowedHttpHookUrls`
- Environment variable allowlisting for HTTP hooks: `httpHookAllowedEnvVars`

---

## 10. Agent Features

### Subagent System

**Built-in subagents (5+):**

| Agent | Model | Tools | Purpose |
|---|---|---|---|
| `Explore` | Haiku (fast) | Read-only | File discovery, code search, codebase exploration |
| `Plan` | Inherits | Read-only | Codebase research for planning |
| `general-purpose` | Inherits | All | Complex multi-step tasks |
| `Bash` | Inherits | Bash | Terminal commands in separate context |
| `statusline-setup` | Sonnet | Config | Configure status line |
| `Claude Code Guide` | Haiku | Info | Answer questions about Claude Code |

**Custom subagents:**
- Defined as Markdown files with YAML frontmatter
- Scopes: CLI `--agents` flag (session), `.claude/agents/` (project), `~/.claude/agents/` (user), plugin `agents/` directory
- Configurable: `name`, `description`, `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `isolation`
- `/agents` command for interactive management
- `claude agents` CLI command for listing

**Subagent capabilities:**
- Persistent memory: `user`, `project`, `local` scopes
- Custom hooks scoped to subagent lifecycle
- Scoped MCP servers (inline or referenced)
- Background execution (concurrent with main conversation)
- Resume capability (retain full conversation history)
- Worktree isolation (`isolation: worktree`)
- Auto-compaction support
- Permission mode override
- Skill preloading

### Agent Teams

- Multiple Claude instances working in parallel
- Git-based coordination: agents claim tasks, merge changes, resolve conflicts
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` to enable
- `--teammate-mode`: `auto`, `in-process`, `tmux`
- `TeammateIdle` hook for coordination

### Plan Mode

- `/plan` to enter directly
- `Shift+Tab` or `Alt+M` to toggle
- `--permission-mode plan` CLI flag
- `opusplan` model alias: Opus for planning, Sonnet for execution
- Plan mode restricts to read-only tools

### Headless/Non-Interactive Mode

- `claude -p "query"` — print mode, process and exit
- `--output-format text|json|stream-json` — output format selection
- `--input-format text|stream-json` — input format
- `--max-turns N` — limit agentic turns
- `--max-budget-usd N` — spending cap
- `--json-schema` — validated structured output
- `--fallback-model` — automatic model fallback when overloaded
- Multi-turn sessions via `--session-id` or `-c`
- `--permission-prompt-tool` — MCP tool for permission handling in CI

### Task Management

- Task list visible via `Ctrl+T`
- Up to 10 tasks displayed at a time
- Tasks persist across context compactions
- `CLAUDE_CODE_TASK_LIST_ID` — share task list across sessions
- `/tasks` — list and manage background tasks
- `TodoRead` / `TodoWrite` tools for programmatic access
- Background tasks with unique IDs
- `CLAUDE_CODE_ENABLE_TASKS=true` for non-interactive mode

### Scheduled Tasks / Cron

- `/loop [interval] <prompt>` — run prompt on schedule
- Standard 5-field cron expressions
- Up to 50 scheduled tasks per session
- Recurring tasks auto-delete after 3 days
- Desktop scheduled tasks for persistent automation

### Checkpointing & Rewind

- Automatic checkpoints before each user prompt
- `Esc + Esc` or `/rewind` to open rewind menu
- Actions: Restore code+conversation, Restore conversation only, Restore code only, Summarize from here
- Persists across sessions (accessible in resumed conversations)
- Tracks file editing tools only (not Bash command changes)

---

## 11. UI/UX Features

### Themes

- `/theme` — color theme picker
- Light and dark variants
- Colorblind-accessible (daltonized) themes
- ANSI themes using terminal's color palette
- Syntax highlighting toggle (`Ctrl+T` in theme picker; native build only)

### Output Styles

- `outputStyle` setting — adjust system prompt output style
- Custom output styles as Markdown files with frontmatter
- Configurable response personality and formatting
- `/config` to select output style

### Status Line

- `/statusline` — configure custom status line
- `statusLine` setting: `type: "command"` with custom script
- Shows model, effort level, active status
- PR review status with colored underline

### Progress Indicators

- Spinner with customizable verbs (`spinnerVerbs` setting)
- Spinner tips (`spinnerTipsEnabled`, `spinnerTipsOverride`)
- Terminal progress bar (`terminalProgressBarEnabled`)
- Turn duration display (`showTurnDuration`)
- Current effort level displayed next to spinner

### Accessibility

- `prefersReducedMotion` — reduce UI animations
- Daltonized (colorblind-accessible) themes
- `language` setting for preferred response language
- Verbose mode (`Ctrl+O` or `--verbose`)

### Side Questions

- `/btw <question>` — ephemeral overlay, no tool access, no history impact
- Available while Claude is working (runs independently)
- Low cost (reuses prompt cache)

### Context Visualization

- `/context` — colored grid showing context usage
- Optimization suggestions for heavy tools, memory bloat, capacity warnings

### Diff Viewer

- `/diff` — interactive viewer
- Left/right arrows: switch between git diff and individual Claude turns
- Up/down arrows: browse files

---

## 12. Extensibility & Integration

### Plugin System

- Plugins bundle skills, agents, hooks, MCP servers, LSP servers, and settings
- Plugin manifest: `.claude-plugin/plugin.json` (name, description, version, author)
- Plugin components: `skills/`, `agents/`, `hooks/hooks.json`, `.mcp.json`, `.lsp.json`, `settings.json`, `commands/`
- Namespaced skills: `/plugin-name:skill-name`
- Install: `/plugin install <name>@<marketplace>`
- Manage: `/plugin`, `/reload-plugins`
- Test locally: `--plugin-dir ./my-plugin`
- Official marketplace submission via claude.ai or platform.claude.com

### Plugin Marketplaces (7 source types)

1. **GitHub repositories**: `{ "source": "github", "repo": "org/repo" }`
2. **Git repositories**: `{ "source": "git", "url": "https://..." }`
3. **URL-based**: `{ "source": "url", "url": "https://..." }`
4. **NPM packages**: `{ "source": "npm", "package": "@org/plugins" }`
5. **File paths**: `{ "source": "file", "path": "/path/to/marketplace.json" }`
6. **Directories**: `{ "source": "directory", "path": "/path/to/plugins" }`
7. **Host patterns**: `{ "source": "hostPattern", "hostPattern": "^github\\.example\\.com$" }`

### MCP Protocol

- Full Model Context Protocol support
- 3 transports: stdio, SSE (deprecated), Streamable HTTP
- Tools, prompts (as slash commands), resources
- OAuth authentication support
- Per-subagent MCP server scoping
- Managed MCP configuration for enterprises

### LSP Integration

- `.lsp.json` configuration in plugins
- Real-time code intelligence from language servers
- Pre-built LSP plugins for common languages (TypeScript, Python, Rust)

### IDE Integrations

| IDE | Type | Key Features |
|---|---|---|
| **VS Code** | Native extension | Graphical chat panel, checkpoint undo, @-mention file references, parallel conversations, diff viewer |
| **JetBrains** | Plugin (Beta) | CLI integration in terminal, IDE diff viewer, file references, conversation history |

### SDK & Programmatic Access

- **Claude Agent SDK**: Python and TypeScript SDKs
- `claude -p` print mode for programmatic usage
- `--output-format json|stream-json` for parsing
- `--json-schema` for validated structured output
- Session management API via SDK
- Cost tracking: `cost_usd` field in JSON output

### CI/CD Integration

- `claude-code-action` — official GitHub Action
- Headless mode via `-p` flag
- `--allowedTools` for restricting tools in CI
- `--max-turns`, `--max-budget-usd` for safety limits
- `--permission-prompt-tool` for automated permission handling
- Multi-turn sessions via `--session-id`

### Remote Control

- `/remote-control` or `claude remote-control` — control from claude.ai, iOS, Android
- QR code handoff for mobile
- Session runs locally, controlled remotely
- `allow_remote_sessions` managed setting

### Web Sessions

- claude.ai/code — web-based Claude Code linked to GitHub
- `--remote "task"` — create web session from CLI
- `--teleport` — resume web session in local terminal
- `/remote-env` — configure default remote environment

### Chrome Integration

- `--chrome` / `--no-chrome` flags
- `/chrome` command for configuration
- Web automation and testing capabilities
- Claude in Chrome extension for browser control

### OpenTelemetry

- Native OTel support: `CLAUDE_CODE_ENABLE_TELEMETRY=1`
- Metrics via standard metrics protocol
- Events via logs/events protocol
- `OTEL_METRICS_EXPORTER`, `OTEL_LOGS_EXPORTER`, `OTEL_EXPORTER_OTLP_ENDPOINT`
- Default intervals: 60s metrics, 5s logs
- `prompt.id` attributes for event correlation
- `otelHeadersHelper` setting for dynamic headers

---

## 13. Model & Provider

### Supported Models

| Alias | Model | Notes |
|---|---|---|
| `default` | Tier-dependent | Max/Team Premium: Opus 4.6; Pro/Team Standard: Sonnet 4.6 |
| `opus` | Claude Opus 4.6 | Complex reasoning; latest as of March 2026 |
| `sonnet` | Claude Sonnet 4.6 | Daily coding tasks |
| `haiku` | Claude Haiku 4.5 | Fast, simple tasks; used by Explore subagent |
| `sonnet[1m]` | Sonnet + 1M context | Extended context window |
| `opusplan` | Opus (plan) + Sonnet (execute) | Hybrid: Opus reasoning for planning, Sonnet efficiency for implementation |

### Effort Levels (3)

| Level | Description |
|---|---|
| `low` | Faster, cheaper for straightforward tasks |
| `medium` | Default for Opus on Max/Team |
| `high` | Deeper reasoning for complex problems |

Configurable via `/model` (arrow keys), `CLAUDE_CODE_EFFORT_LEVEL`, or `effortLevel` setting. Supported on Opus 4.6 and Sonnet 4.6.

### Extended Thinking

- Enabled by default with 31,999 token budget
- Toggle via `Alt+T` or `/config`
- `alwaysThinkingEnabled` setting
- `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` to revert to fixed budget
- "ultrathink" keyword in skills for forced extended thinking

### Fast Mode

- `/fast [on|off]` to toggle
- `CLAUDE_CODE_DISABLE_FAST_MODE=1` to disable
- `fastModePerSessionOptIn` — require opt-in per session

### Custom Providers (3)

| Provider | Setup | Auth |
|---|---|---|
| **Amazon Bedrock** | `CLAUDE_CODE_USE_BEDROCK=1` | AWS credentials, `AWS_BEARER_TOKEN_BEDROCK`, inference profile ARNs |
| **Google Vertex AI** | `CLAUDE_CODE_USE_VERTEX=1` | Google Cloud credentials |
| **Microsoft Foundry** | `CLAUDE_CODE_USE_FOUNDRY=1` | `ANTHROPIC_FOUNDRY_API_KEY`, `ANTHROPIC_FOUNDRY_BASE_URL` |

### Model Configuration

- `model` setting or `ANTHROPIC_MODEL` env var
- `availableModels` — restrict selectable models (managed setting)
- `modelOverrides` — map Anthropic model IDs to provider-specific IDs (ARNs, deployment names)
- `ANTHROPIC_DEFAULT_*_MODEL` env vars for pinning versions per provider
- Prompt caching: automatic; per-model disable via `DISABLE_PROMPT_CACHING_*`

### Token/Cost Display

- `/cost` — detailed token usage and cost for current session
- `/usage` — plan usage limits and rate limit status
- `/stats` — daily usage visualization, session history, streaks
- `--max-budget-usd` — spending cap in headless mode
- JSON output includes `cost_usd` field
- Background token usage tracked separately

---

## Summary Counts

| Category | Count |
|---|---|
| Built-in slash commands | 46 |
| Bundled skills | 5 |
| Hook event types | 17 |
| Hook handler types | 4+ |
| Keyboard shortcuts (general) | 13 |
| Keyboard shortcuts (text editing) | 6 |
| Multiline input methods | 5 |
| Vim mode commands | 30+ |
| Built-in tools | 15 |
| MCP transport types | 3 |
| Permission modes | 5 |
| Settings hierarchy levels | 5 |
| Environment variables | 60+ |
| Configurable settings fields | 40+ |
| Model aliases | 6 |
| Effort levels | 3 |
| Custom providers | 3 |
| IDE integrations | 2 |
| Plugin marketplace source types | 7 |
| Plugin component types | 7 (skills, agents, hooks, MCP, LSP, commands, settings) |
| Subagent built-in types | 5+ |
| CLAUDE.md file scopes | 3+ (managed, project, user, rules) |
