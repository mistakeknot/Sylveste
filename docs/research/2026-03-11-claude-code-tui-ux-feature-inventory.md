# Claude Code TUI/UX Feature Inventory

> Exhaustive feature inventory of Claude Code (Anthropic's official CLI), covering input, output,
> tool system, permissions, sessions, MCP, hooks, plugins, and more. Research date: 2026-03-11.

---

## 1. Input: Prompt Composition

### Text Entry
- **Single-line**: `Enter` submits the prompt immediately
- **Multi-line**: `Shift+Enter` inserts a newline; backslash `\` at end of line also works as continuation. If Shift+Enter doesn't work in your terminal, run `/terminal-setup` to install the keybinding (auto-configures VS Code, Alacritty, Zed, Warp). iTerm2, WezTerm, Ghostty, and Kitty support Shift+Enter natively
- **External editor**: `Ctrl+G` opens the current prompt in `$EDITOR` for complex multi-line composition
- **Vim mode**: `/vim` or `/config` to enable; provides subset of standard vim keybindings (mode switching with Esc/i/I/a/A/o/O, navigation with h/j/k/l/w/e/b/0/$, editing with d/c/x motions, `.` repeat)
- **History search**: `Ctrl+R` searches and replays previous prompts (bash-style reverse-i-search)

### File & Image References
- **`@` file references**: `@path/to/file.js` injects full file content into context; supports tab-completion for paths
- **`@` directory references**: `@path/to/dir/` includes directory listing
- **Image paste**: `Ctrl+V` (not Cmd+V on macOS) pastes clipboard images; attached images display as clickable `[Image #N]` links
- **Drag and drop**: Drag files into terminal window to insert path; hold Shift to reference in VS Code extension
- **Image path reference**: `@screenshot.png` or any image path readable by the Read tool
- **Supported image formats**: PNG, JPG, GIF, WebP

### Shell Command Injection
- **`!` prefix**: `!git status` runs a shell command directly and adds output to conversation context without Claude interpreting or approving it; useful for injecting build output, test results, etc.

### Stdin Piping (Non-Interactive)
- **Pipe input**: `cat file.ts | claude -p "Add types"` — the `-p`/`--print` flag accepts context via stdin through Unix pipes
- **Git diff piping**: `git diff | claude -p "Review this change"` — common pattern for automated review

---

## 2. Output: Response Rendering

### Markdown Rendering
- Uses **markdown-it** for parsing and **Shiki** for syntax highlighting with theme-aware color schemes
- Code blocks include **copy-to-clipboard** button (positioned top-right)
- Supports incremental rendering for streaming responses; prevents race conditions when AI streams text faster than Shiki can highlight
- Fenced code blocks with language tags get full syntax highlighting

### Thinking Blocks / Extended Thinking
- **Trigger phrases**: "think about it" / "think deeply" / "think more" (megathink level); "think harder" / "think really hard" / "ultrathink" (maximum thinking)
- **Display**: Thinking blocks rendered in **gray italic text** above actual output; these are the model's actual chain of thought, not a summary
- **Verbose toggle**: `Ctrl+O` toggles verbose output showing tool call details, execution traces, and thinking blocks
- **Interleaved thinking** (Claude 4+): Claude can think between tool calls, not just at the start; reasons about intermediate results and adjusts approach mid-execution
- **Tab toggle**: `Tab` key toggles thinking mode on/off

### Streaming
- Responses stream token-by-token to terminal in real-time
- Tool results stream as they complete
- Parallel tool calls (independent operations) execute simultaneously and results interleave

### Output Modes (Headless)
- **text**: Human-readable plain text (default with `-p`)
- **json**: Structured object with response, session metadata, token statistics (parseable with `jq`)
- **stream-json**: Newline-delimited JSON for real-time streaming processing

---

## 3. Tool System

### Built-in Tools
| Tool | Purpose |
|------|---------|
| **Bash** | Execute shell commands in persistent bash session |
| **Read** | Read files (text, images, PDFs, Jupyter notebooks) with line numbers and pagination |
| **Edit** | Exact string replacement in files (requires prior Read) |
| **MultiEdit** | Multiple find-and-replace operations on a single file, atomic (all-or-nothing) |
| **Write** | Create or overwrite files |
| **Glob** | Fast file pattern matching (`**/*.ts`) |
| **Grep** | Regex content search (ripgrep-based) |
| **WebSearch** | Web search via Anthropic's server-side infrastructure; spawns secondary Opus conversation |
| **WebFetch** | Fetch URL content locally via Axios; summarizes with secondary LLM conversation |
| **TodoRead** | Read current task list |
| **TodoWrite** | Create/update task checklist with pending/in_progress/completed statuses and priority levels |
| **NotebookEdit** | Edit Jupyter notebook cells (.ipynb) |
| **AskUserQuestion** | Present structured questions with multiple-choice options |
| **Agent** | Spawn subagents for delegated tasks |
| **EnterWorktree** | Create and enter a git worktree for isolated work |
| **ExitWorktree** | Exit current worktree |
| **ToolSearch** | Lazily load deferred MCP tool schemas; reduces context waste for large toolsets |

### Tool Call Approval Flow
- **Permission prompt**: Each tool call shows tool name, arguments, and asks for approval
- **Keyboard responses at permission prompt**:
  - `y` — Accept and execute
  - `n` — Reject
  - `d` — Show full diff (for Edit/Write tools)
  - `e` — Edit the proposed change before accepting
- **Always-allow**: Accept once per tool type for the session; subsequent calls of that type auto-approve
- **Auto-accept mode** (`Shift+Tab`): All edits proceed without pausing; user can still see and intervene
- **Parallel tool calls**: Independent tools execute simultaneously (e.g., two Grep searches); dependent tools run sequentially (Glob -> Read)

### Tool Display During Execution
- Tool name and arguments shown when invoked
- Bash commands show the command being run
- Edit/Write show file path and proposed changes
- Progress indicators for long-running operations
- Read tool outputs are visible in verbose mode (`Ctrl+O`)

---

## 4. Diffs: File Edit Display

### Terminal (CLI)
- When Claude proposes a file edit, a diff is shown inline
- Press `d` to expand to full diff view before deciding
- Press `e` to edit the proposed change in-place before accepting
- Unified diff format showing added/removed lines with `+`/`-` prefixes
- Changes are **atomic per tool call** — all edits in a MultiEdit succeed or none apply

### VS Code Extension
- **Inline diffs**: Proposed changes shown in sidebar; drag wider for inline view
- **Full side-by-side diff**: Click any file to open VS Code's native diff viewer (old left, new right)
- **Per-file review**: Each modified file listed separately for review
- **Limitation**: No per-hunk accept/reject (all changes in a tool call are atomic); feature request open for inline per-change approval

### Checkpoints and Rewind
- **Automatic checkpoints**: Code state captured before each file edit
- **Rewind**: Press `Esc` twice or use `/rewind` to open rewind menu; select any checkpoint to restore
- **Session-level**: Checkpoints are per-session snapshots, not git commits
- Enables "aggressive experimentation" — try ambitious changes knowing you can always roll back

---

## 5. Permission System

### Permission Modes
| Mode | Behavior | Activation |
|------|----------|------------|
| **Normal** (default) | Prompts on first use of each tool type; file edits prompt individually; shell commands prompt individually | Default |
| **Auto-Accept** | Edits proceed without pausing; still interactive and visible | `Shift+Tab` (1st press) |
| **Plan Mode** | Claude creates detailed plan requiring approval before execution | `Shift+Tab` (2nd press) or `/plan` |
| **Sandbox** | OS-level filesystem+network isolation; auto-allows sandboxed commands | `/sandbox` |
| **bypassPermissions** | Disables all permission checks (containers/VMs only) | `--dangerously-skip-permissions` flag |

### Mode Cycling
- `Shift+Tab` cycles: Normal -> Auto-Accept -> Plan Mode -> Normal
- Known Windows issue: may skip Plan Mode, toggling only Normal <-> Auto-Accept

### Permission Rules (settings.json)
- **Allowlist/blocklist** for Bash commands, file read patterns, file edit patterns
- **Gitignore-style patterns**: `*` matches single directory, `**` matches recursively
- **Absolute paths**: Use `//path` for absolute (single `/` is relative to project root)
- **Tool-specific rules**: `allow`, `deny` per tool name or pattern
- **Regex validation**: `exclude_regex` for complex rules ("allow cargo, but not with shell injection chars")
- **Precedence**: More specific rules override general ones

### Trust Levels
- **Global settings** (`~/.claude/settings.json`): Apply everywhere
- **Project settings** (`.claude/settings.json`): Apply to this project; checked into VCS
- **Enterprise managed settings** (`managed-mcp.json`, `managed-settings.json`): Admin-deployed, takes exclusive control
- Project settings cannot override global deny rules

### Sandboxing
- **macOS**: Seatbelt (same framework as App Store apps)
- **Linux**: bubblewrap (bwrap), same tool used by Flatpak
- **WSL1**: Not supported (requires WSL2 kernel features)
- **Filesystem isolation**: Claude can only access project directory
- **Network isolation**: Only connects to approved servers
- **Effectiveness**: Reduces permission prompts by 84% in internal usage
- **Fallback**: Commands that can't be sandboxed (e.g., non-allowed network hosts) fall back to normal permission flow

---

## 6. Session Management

### Starting Sessions
- `claude` — Start new interactive session
- `claude -c` / `claude --continue` — Continue most recent conversation
- `claude -r <id>` / `claude --resume <id>` — Resume specific session by ID
- `claude -p "prompt"` — Non-interactive single-shot (headless mode)
- `claude --worktree` — Start in isolated git worktree; optionally name it

### Context Window
- **200K token window** (~150K words)
- **System overhead**: ~30K-45K tokens consumed by system prompts, tool definitions, MCP schemas, memory files before user types anything
- **Usable context buffer**: ~33K tokens (16.5%) reserved for compaction, reduced from previous higher values

### Auto-Compaction
- Triggers at **~75-92%** of window capacity
- Clears older tool outputs first, then summarizes conversation
- `/compact` invokes manual compaction; accepts focus instructions (e.g., `/compact focus on the auth refactoring`)
- **Session Memory** (v2.1.30+): Background system continuously writes structured summaries; makes `/compact` instant since it loads pre-written summary

### CLAUDE.md System
- **Auto-loaded** at session start and preserved through every compaction cycle
- **Hierarchy**: `~/.claude/CLAUDE.md` (global) -> project root `CLAUDE.md` -> subdirectory `CLAUDE.md`
- **Recommended size**: Under 200 lines / 2,000 tokens
- **HTML comments**: `<!-- ... -->` are hidden from Claude when auto-injected
- **Compact Instructions section**: Controls what survives compaction
- `/init` auto-generates initial `CLAUDE.md` from project analysis

### Memory System
- **CLAUDE.md** (manual): You write and maintain persistent project instructions
- **Auto-Memory** (`~/.claude/projects/<path>/memory/MEMORY.md`): Claude accumulates learnings across sessions automatically
  - 200-line hard limit
  - Saves build commands, debugging insights, architecture notes, code style preferences
  - Claude decides what's worth remembering based on future utility
  - `MEMORY.md` acts as index with optional topic files in same directory
- **Session Memory** (background): Watches conversation, extracts important parts, saves structured summaries to disk continuously
- `/memory` command opens MEMORY.md for editing

### Cross-Device Session Handoff
- **Remote Control**: `claude remote control` generates session URL + QR code
- Scan QR code with phone camera -> Claude mobile app opens with synchronized session view
- Session runs locally on user's machine; web/mobile are windows into local session
- Messages can be sent from terminal, browser, and phone interchangeably
- Available for Pro and Max subscribers (Max first)
- `/teleport` — Pull long-running remote tasks into terminal
- `/desktop` — Hand session to Desktop app for visual diff review

---

## 7. Structured Prompts: AskUserQuestion

### Capabilities
- Presents structured questions with multiple-choice options and keyboard navigation
- Each option includes explanation/tradeoff description
- Recommendations highlighted per option
- Claude analyzes codebase context to auto-generate sensible options

### Behavior
- **60-second timeout** per question
- **Main agent only**: Cannot be used from sub-agents
- **Question limit**: ~4-6 questions per session
- **Plan mode integration**: Especially common in plan mode where Claude explores codebase and asks questions before proposing plan

### Customization
- Cannot build custom version, but system prompt persona instructions can transform its behavior
- Enables spec-based development: Claude interviews you -> builds specification -> executes with precision

---

## 8. MCP (Model Context Protocol) Integration

### Server Configuration Scopes
| Scope | Storage | Visibility | Use Case |
|-------|---------|------------|----------|
| **Local** | `~/.claude.json` (per-project path) | Private, current project only | Personal servers, experiments |
| **Project** | `.mcp.json` at repo root | Checked into VCS, team-shared | Team-standard tooling (Sentry, DB) |
| **User** | `~/.claude.json` | Private, all projects | Personal utilities across projects |

### Precedence
Local > Project > User (same-name servers resolved by priority)

### Security
- Project-scoped servers (`.mcp.json`) require **user approval** before first use
- `claude mcp reset-project-choices` resets approval decisions
- Enterprise: `managed-mcp.json` takes **exclusive control** over all MCP servers; users cannot add/modify/use unauthorized servers

### Remote MCP
- Native OAuth support for remote MCP servers
- Secure connections to existing accounts (GitHub, Sentry, etc.)

### Tool Discovery
- **ToolSearch** lazily loads MCP tool schemas on demand
- Reduces context window waste for large tool collections
- MCP tool names usable in PreToolUse/PostToolUse hooks

### Management Commands
- `claude mcp add <name> <command>` — Add stdio server
- `claude mcp add --transport sse <name> <url>` — Add SSE server
- `claude mcp remove <name>` — Remove server
- `claude mcp list` — List configured servers

---

## 9. Hooks System

### Hook Events
| Event | Fires When | Key Input Fields |
|-------|-----------|------------------|
| **SessionStart** | Beginning of session | `source` (startup/resume/clear/compact), `agent_type`, `model` |
| **SessionEnd** | End of session | Session metadata |
| **UserPromptSubmit** | User submits prompt | Prompt text |
| **PreToolUse** | Before tool execution | `tool_name`, `tool_input` |
| **PostToolUse** | After successful tool execution | `tool_name`, `tool_input`, `tool_response` |
| **PostToolUseFailure** | After tool execution fails | Tool name, input, error |
| **PermissionRequest** | Permission dialog shown | Tool details |
| **Notification** | Claude sends notification | `message`, `title`, `notification_type` |
| **Stop** | Claude attempts to stop | — |
| **SubagentStart** | Subagent spawned | Agent details |
| **SubagentStop** | Subagent attempts to stop | — |

### PreToolUse Permission Decisions
- Hook can return `hookSpecificOutput.permissionDecision` ("allow"/"deny") and `hookSpecificOutput.permissionDecisionReason`
- Matches on tool names: Bash, Edit, Write, Read, Glob, Grep, Agent, WebFetch, WebSearch, and any MCP tool names

### Hook Configuration
- Defined in `settings.json` or `.claude/settings.json`
- Commands receive event data as JSON on stdin
- Commands return JSON on stdout
- Record format (not array): `{"hooks": {"SessionStart": [{"hooks": [{"type":"command","command":"..."}]}]}}`

### Common Hook Use Cases
- Auto-formatting after file edits (PostToolUse on Edit/Write)
- Notification sounds on task completion (Notification event)
- Auto-indexing on session start (SessionStart)
- Permission automation (PreToolUse with custom logic)
- Linting/testing after code changes

### Performance
- SessionStart hooks deferred to reduce time-to-interactive by ~500ms

---

## 10. Skills and Custom Commands

### Skills (`.claude/skills/<name>/SKILL.md`)
- **YAML frontmatter** controls behavior:
  - `name`, `description` — Discovery metadata
  - `disable-model-invocation: true` — Only user can invoke (e.g., `/commit`, `/deploy`)
  - `user-invocable: false` — Only Claude can invoke (background knowledge)
- **Support files**: Directory alongside SKILL.md for templates, schemas, examples
- **Invocation**: `/skill-name` in prompt or Claude auto-loads when relevant
- **Backward compatible**: `.claude/commands/*.md` files still work and support same frontmatter

### Built-in Slash Commands
| Command | Purpose |
|---------|---------|
| `/help` | List available commands |
| `/init` | Generate CLAUDE.md from project analysis |
| `/clear` | Erase conversation history (not files) |
| `/compact` | Compress conversation; accepts focus instructions |
| `/cost` | Show session cost (input tokens, output tokens, amount) |
| `/config` | Open configuration (theme, vim mode, etc.) |
| `/model` | Switch models (opus/sonnet/haiku) |
| `/login` | Authenticate |
| `/logout` | Sign out |
| `/memory` | Edit CLAUDE.md |
| `/rewind` | Open checkpoint rewind menu |
| `/context` | Visualize context usage |
| `/status` | Check system status |
| `/doctor` | Check installation health |
| `/bug` | Report bug (sends conversation to Anthropic) |
| `/vim` | Toggle vim mode |
| `/plan` | Enter plan mode |
| `/sandbox` | Enable OS-level sandboxing |
| `/terminal-setup` | Configure Shift+Enter for your terminal |
| `/keybindings` | Open keybindings config file |
| `/statusline` | Generate custom status bar script |
| `/plugin` | Plugin management |

### Plugins
- **Bundle**: Skills + hooks + MCP servers + agents in a single installable package
- **Installation**: `npm install` for npm packages; `/plugin marketplace add user-or-org/repo` for marketplace
- **Marketplace**: Any git repo with `.claude-plugin/marketplace.json`; browse via `/plugin menu`
- **Pinning**: Pin to specific git commit SHA for exact versions
- **Search**: Type to filter installed plugins by name/description

---

## 11. Keyboard Shortcuts

### Core Navigation & Control
| Shortcut | Action |
|----------|--------|
| `Enter` | Submit prompt |
| `Shift+Enter` | Insert newline |
| `Esc` | Interrupt Claude during generation |
| `Esc Esc` (double) | Open checkpoint rewind menu |
| `Ctrl+C` | Interrupt / cancel |
| `Ctrl+D` | Exit Claude Code |
| `Ctrl+O` | Toggle verbose/transcript mode |
| `Ctrl+R` | Search prompt history |
| `Ctrl+G` | Open prompt in external editor |
| `Tab` | Toggle thinking mode |
| `Shift+Tab` | Cycle modes: Normal -> Auto-Accept -> Plan |

### Permission Prompt Responses
| Key | Action |
|-----|--------|
| `y` | Accept tool call |
| `n` | Reject tool call |
| `d` | Show diff |
| `e` | Edit proposed change |

### Keybinding Customization
- Config file: `~/.claude/keybindings.json`
- Open with `/keybindings` command
- Organized by **context** (Global, Chat, etc.)
- Supports chord sequences, modifier combinations, unbinding defaults
- Key syntax: `ctrl+k`, `shift+tab`, `esc`, `enter`
- Uppercase letter implies Shift (e.g., `K` = `shift+k`)
- Vim mode and keybindings operate on different layers (vim = text input, keybindings = app actions)

---

## 12. Themes, Styling, and Layout

### Theme Configuration
- `/config` to set light/dark mode
- Force theme via environment variables: `CLAUDE_CODE_COLOR_PRIMARY`, `CLAUDE_CODE_COLOR_SECONDARY`, `CLAUDE_CODE_COLOR_ERROR`, `CLAUDE_CODE_COLOR_SUCCESS`
- `COLORTERM=truecolor` enables full 24-bit RGB palette (important for remote sessions)
- 37 settings and 84 environment variables total for configuration

### Status Line
- Bottom-of-screen status bar showing model, context window usage, cost, etc.
- `/statusline` accepts natural language instructions for customization
- Generates a `.sh` script saved to global settings
- Default data: model name, context %, tokens used/total, cwd, git branch
- Community tools: ccusage, ccstatusline, ClaudeCode_status_bar for enhanced displays

### Display Settings
- `codeBlockStyle` — Code block appearance
- `syntaxHighlighting` — Toggle syntax highlighting
- `lineNumbers` — Show/hide line numbers
- `diffStyle` — Diff display format
- Status line `style` (e.g., "detailed")

### Notifications
- **Terminal bell**: `claude config set --global preferredNotifChannel terminal_bell`
- **iTerm2 native**: Enable in `/config`
- **Hook-based**: Notification event for custom desktop alerts, sounds
- **Community solutions**: Native macOS/Linux/Windows notifications via hooks; sound packs (Glass, Blow, Sosumi, Basso, etc.); Rust CLI notification tools; MCP notification servers

---

## 13. Subagents and Background Agents

### Built-in Subagent Types
| Type | Purpose | Tools Available |
|------|---------|----------------|
| **Explore** | File discovery, code search, codebase exploration (read-only) | Read, Glob, Grep, LS |
| **Plan** | Research agent for plan mode; gathers context before presenting plan | Read, Glob, Grep, LS |
| **General-purpose (Task)** | Complex multi-step tasks requiring both exploration and action | Full tool access |
| **Doc-writer** | Creating and updating documentation | Read, Write, Edit |

### Explore Agent Thoroughness Levels
- **quick**: Targeted lookups
- **medium**: Balanced exploration
- **very thorough**: Comprehensive analysis

### Custom Subagents
- Defined in `.claude/agents/<name>.md` or via Skills
- Custom system prompt, specific tool access, independent permissions
- Can specify hooks, skills, permission modes per subagent
- Created via Agent tool or `claude agent create`

### Parallel Execution
- **Task tool**: Spawns up to 7 sub-agents simultaneously
- Independent subagents run concurrently (e.g., style-checker + security-scanner + test-coverage)
- Each subagent has its own context window

### Background Agents
- Subagents run in background while main session continues
- Async message system for waking main agent with updates
- Background agents can request input or report critical findings

### Agent Teams (Experimental)
- Enable: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable
- **Team lead** coordinates; **teammates** work independently with own context windows
- Teammates **message each other** directly (not just report to lead)
- Teammates **claim tasks** from shared list
- Token costs scale linearly (each teammate = own context window)
- Best for: research with competing hypotheses, cross-layer coordination, parallel module development
- Shipped alongside Opus 4.6 release (February 2026)

---

## 14. Task Management

### In-Memory Todos (TodoRead/TodoWrite)
- Checklist displayed in terminal UI, updates in real-time
- Three statuses: `pending`, `in_progress`, `completed`
- Three priority levels: `high`, `medium`, `low`
- Vanish when session closes

### Persistent Tasks (v2.1+, January 2026)
- Stored on filesystem: `~/.claude/tasks/`
- Survive terminal close, machine switch, system crash
- **DAG support**: Tasks can block other tasks (directed acyclic graph)
- **Cross-session coordination**: `CLAUDE_CODE_TASK_LIST_ID` env var points multiple instances at same task list
- Updates broadcast to all active sessions sharing same task list ID

### File-Based Todos (`/file-todos`)
- Persistent alternative to in-memory TodoWrite
- Recommended for work spanning multiple sessions

---

## 15. Git Integration

### Worktrees
- `claude --worktree` — Start in isolated git worktree
- `claude --worktree --tmux` — Launch in its own tmux session
- Auto-creates branch and directory at `.claude/worktrees/<name>/`
- On exit: Claude prompts to keep or remove worktree
- **Auto-cleanup**: Worktree auto-deleted if no uncommitted changes on exit
- Project configs and auto-memory shared across worktrees of same repository

### Checkpoints
- Automatic snapshots before each file edit
- `/rewind` or `Esc Esc` to access
- Session-scoped (not git commits)

### GitHub Actions Integration
- `anthropics/claude-code-action@v1` — Official GitHub Action
- **Triggers**: `@claude` mentions in PRs/issues, PR open/update, issue assignment
- **Capabilities**: Code review, implementation, bug fixes, architecture questions
- Supports Anthropic API, Amazon Bedrock, Google Vertex AI, Microsoft Foundry
- `anthropics/claude-code-security-review` — Specialized security analysis action

---

## 16. Model Configuration

### Available Models (March 2026)
- **Claude Opus 4.6** — Most powerful; complex reasoning and architecture
- **Claude Sonnet 4.6** — Balanced speed/intelligence; everyday coding
- **Claude Haiku 4.5** — Fastest/cheapest; quick questions at ~3x lower cost

### Model Switching
- `/model` — Open model picker
- `/model opus`, `/model sonnet`, `/model haiku` — Direct switch
- **opusplan** alias: Opus for plan mode (reasoning), Sonnet for execution (code generation)

### 1M Context
- If account supports 1M context, option appears in `/model` picker
- **Prompt caching** used automatically to optimize performance and reduce costs

### Provider Configuration
- `CLAUDE_CODE_USE_VERTEX=1` — Google Vertex AI
- `CLAUDE_CODE_USE_FOUNDRY=1` — Microsoft Azure/Foundry
- Amazon Bedrock also supported

---

## 17. Non-Interactive / Headless Mode

### CLI Flags
- `-p` / `--print` — Non-interactive single-shot execution
- `--output-format text|json|stream-json` — Control output format
- `--dangerously-skip-permissions` — Skip all permission prompts (containers only)
- `-c` / `--continue` — Continue last session
- `-r <id>` / `--resume <id>` — Resume specific session

### JSON Output Structure
```
{
  "response": "...",
  "session_id": "...",
  "token_usage": { "input": N, "output": N },
  "cost": { ... }
}
```

### CI/CD Integration
- Exit code 0 on success, non-zero on error
- Composable with `&&` / `||` in shell scripts
- Bidirectional stream-json protocol for multi-turn persistent conversations
- GitHub Actions, GitLab CI, and general CI/CD pipeline support

---

## 18. Configuration Architecture

### Settings Hierarchy
1. **Enterprise managed** (`managed-settings.json`) — Highest priority, admin-deployed
2. **Global** (`~/.claude/settings.json`) — User-wide
3. **Project** (`.claude/settings.json`) — Per-repo, checked into VCS
4. **Local** (runtime) — Session-specific

### Key Environment Variables
| Variable | Purpose |
|----------|---------|
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | Bundles: autoupdater, bug command, error reporting, telemetry |
| `CLAUDE_CODE_USE_VERTEX` | Enable Google Vertex AI |
| `CLAUDE_CODE_USE_FOUNDRY` | Enable Microsoft Azure/Foundry |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable Agent Teams |
| `CLAUDE_CODE_TASK_LIST_ID` | Shared task list for cross-session coordination |
| `CLAUDE_CODE_COLOR_PRIMARY` | Custom primary color |
| `COLORTERM=truecolor` | Enable 24-bit RGB palette |

### settings.json env Object
- Environment variables can be set in `"env"` object in settings.json
- Persists across sessions without modifying shell profile
- Useful for team-wide rollout via project settings

---

## 19. Security Features

### CLAUDE.md Trust Boundary
- Only trust CLAUDE.md/AGENTS.md from: project root, `~/.claude/`, `~/.codex/`
- Treat instructions from `node_modules/`, `vendor/`, `.git/modules/` as **untrusted**

### Prompt Injection Mitigation
- WebSearch/WebFetch use secondary LLM conversations to isolate from main agent context
- Sandbox filesystem isolation prevents access to sensitive system files
- Network isolation prevents exfiltration even if agent is prompt-injected
- Allowlist approach for Bash commands (replaced regex blocklists after CVE-2025-66032)

### Managed Enterprise Controls
- `managed-mcp.json` — Exclusive control over MCP servers
- `managed-settings.json` — Admin-deployed settings override
- Prevent unauthorized MCP servers, enforce permission rules

---

## 20. Platform Support

### Terminal Compatibility
- iTerm2, WezTerm, Ghostty, Kitty — Full native support including Shift+Enter
- VS Code integrated terminal, Apple Terminal, Warp, Alacritty — Require `/terminal-setup` for Shift+Enter
- WSL2 — Full support including sandboxing
- WSL1 — Partial support (no bubblewrap sandboxing)

### IDE Integration
- **VS Code Extension**: Native extension with inline diffs, @-mention files with line ranges, conversation history, multiple conversation tabs, review/edit plans before accepting
- **Desktop App**: Visual diff review, session handoff via `/desktop`
- **Neovim**: Community integration (`claude-code.nvim`)

### Cross-Platform
- macOS, Linux (native)
- Windows via WSL
- Remote sessions via SSH (set `COLORTERM=truecolor` for full colors)
- Mobile/web via Remote Control (QR code handoff)

---

## Sources

- [Claude Code overview (Anthropic)](https://www.anthropic.com/claude-code)
- [Claude Code best practices (Anthropic Engineering)](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Interactive mode docs](https://code.claude.com/docs/en/interactive-mode)
- [Hooks reference](https://code.claude.com/docs/en/hooks)
- [Hooks guide](https://code.claude.com/docs/en/hooks-guide)
- [Permissions docs](https://code.claude.com/docs/en/permissions)
- [MCP integration docs](https://code.claude.com/docs/en/mcp)
- [Skills docs](https://code.claude.com/docs/en/skills)
- [Keybindings docs](https://code.claude.com/docs/en/keybindings)
- [Settings docs](https://code.claude.com/docs/en/settings)
- [Status line docs](https://code.claude.com/docs/en/statusline)
- [Sandboxing docs](https://code.claude.com/docs/en/sandboxing)
- [Sandboxing engineering blog](https://www.anthropic.com/engineering/claude-code-sandboxing)
- [Checkpointing docs](https://code.claude.com/docs/en/checkpointing)
- [Memory docs](https://code.claude.com/docs/en/memory)
- [How Claude Code works](https://code.claude.com/docs/en/how-claude-code-works)
- [Model configuration docs](https://code.claude.com/docs/en/model-config)
- [Subagents docs](https://code.claude.com/docs/en/sub-agents)
- [Agent teams docs](https://code.claude.com/docs/en/agent-teams)
- [Headless mode docs](https://code.claude.com/docs/en/headless)
- [Terminal configuration docs](https://code.claude.com/docs/en/terminal-config)
- [Remote control docs](https://code.claude.com/docs/en/remote-control)
- [Slash commands docs](https://code.claude.com/docs/en/slash-commands)
- [Plugin marketplaces docs](https://code.claude.com/docs/en/plugin-marketplaces)
- [Plugins announcement](https://www.anthropic.com/news/claude-code-plugins)
- [VS Code integration docs](https://code.claude.com/docs/en/vs-code)
- [GitHub Actions docs](https://code.claude.com/docs/en/github-actions)
- [CLI reference docs](https://code.claude.com/docs/en/cli-reference)
- [Common workflows docs](https://code.claude.com/docs/en/common-workflows)
- [Agent SDK overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Claude Code changelog](https://code.claude.com/docs/en/changelog)
- [Enabling autonomous work (Anthropic)](https://www.anthropic.com/news/enabling-claude-code-to-work-more-autonomously)
- [Remote MCP support announcement](https://www.anthropic.com/news/claude-code-remote-mcp)
- [Agent Skills announcement](https://www.anthropic.com/news/skills)
- [Claude Code on the web](https://www.anthropic.com/news/claude-code-on-the-web)
- [Extended thinking (Anthropic)](https://www.anthropic.com/news/visible-extended-thinking)
- [Claude Code keybindings guide (claudefa.st)](https://claudefa.st/blog/tools/keybindings-guide)
- [Claude Code session management (Steve Kinney)](https://stevekinney.com/courses/ai-development/claude-code-session-management)
- [AskUserQuestion tool guide (ClaudeLog)](https://claudelog.com/faqs/what-is-ask-user-question-tool-in-claude-code/)
- [Claude Code system prompts (GitHub)](https://github.com/Piebald-AI/claude-code-system-prompts)
- [Claude Code built-in tools reference](https://www.vtrivedy.com/posts/claudecode-tools-reference)
- [Context window management (DeepWiki)](https://deepwiki.com/anthropics/claude-code/3.3-session-and-conversation-management)
- [Ultrathink extended thinking guide](https://findskill.ai/blog/claude-ultrathink-extended-thinking/)
