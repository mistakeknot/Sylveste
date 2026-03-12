# Amp Feature Inventory (Deep Research 2026-03-12)

> **Product**: Amp (by Sourcegraph, formerly Cody CLI)
> **Version analyzed**: v0.0.1770366910 (CLI build from ~Feb 2026)
> **Status**: Closed-source CLI + cloud backend. Editor extensions (VS Code/Cursor) discontinued March 5, 2026. CLI is now the sole interface.
> **Install**: `curl -fsSL https://ampcode.com/install.sh | bash` or `npm install @sourcegraph/amp`
> **Pricing**: Free ($10/day ad-supported, admissions paused Feb 2026), Teams (at-cost), Enterprise (50% premium, 1k min credit spend)
> **SOC 2 Type II certified**, ISO 27001 (via Sourcegraph parent)

## Sources

- [Amp Official Site](https://ampcode.com/)
- [Amp Owner's Manual](https://ampcode.com/manual)
- [Amp Manual Appendix](https://ampcode.com/manual/appendix)
- [Amp Models Page](https://ampcode.com/models)
- [Amp Chronicle (Full Changelog)](https://ampcode.com/chronicle)
- [Amp Security Reference](https://ampcode.com/security)
- [Amp SDK Documentation](https://ampcode.com/manual/sdk)
- [Amp Hooks Announcement](https://ampcode.com/news/hooks)
- [Amp Code Review Announcement](https://ampcode.com/news/liberating-code-review)
- [Amp Agent Skills Announcement](https://ampcode.com/news/agent-skills)
- [Amp Custom Commands to Skills Migration](https://ampcode.com/news/slashing-custom-commands)
- [Amp "Coding Agent Is Dead" Post](https://ampcode.com/news/the-coding-agent-is-dead)
- [Amp Toolbox Announcement](https://ampcode.com/news/toolboxes)
- [Amp CLI Image Support](https://ampcode.com/news/cli-image-support)
- [Amp Command Palette Announcement](https://ampcode.com/news/command-palette)
- [Amp Globs in AGENTS.md](https://ampcode.com/news/globs-in-AGENTS.md)
- [Amp GitHub Org](https://github.com/ampcode)
- [amp-contrib Repository](https://github.com/ampcode/amp-contrib)
- [amp-examples-and-guides Repository](https://github.com/sourcegraph/amp-examples-and-guides)
- [amp.nvim Plugin](https://github.com/sourcegraph/amp.nvim)
- [Amp Prompts & Tools Extraction (johndamask)](https://johndamask.com/blog/2025/11/24/amp-all-prompts.html)
- [Amp CLI Internals (ben-vargas)](https://github.com/ben-vargas/ai-amp-cli)
- [Amp Tab Announcement](https://dev.to/jshorwitz/amp-tab-by-sourcegraph-intent-aware-tab-that-edits-across-files-now-on-by-default-4bo8)
- [Amp TypeScript SDK](https://ampcode.com/news/typescript-sdk)
- [Amp Python SDK](https://ampcode.com/news/python-sdk)
- [Amp Patterns: GitHub CLI](https://ampcode.com/patterns/github-cli)
- [Amp Code Review GitHub App](https://github.com/sourcegraph/cra-github)
- [npm: @sourcegraph/amp](https://www.npmjs.com/package/@sourcegraph/amp)

---

## 1. Command Palette / Slash Commands (~12 known actions)

Amp replaced traditional slash commands with a **Command Palette** (Oct 28, 2025). Custom commands were later replaced entirely by **Skills** (Jan 29, 2026).

### Command Palette Actions (opened via Ctrl+O in CLI)

| Action | Description |
|--------|-------------|
| `mode` | Switch between agent modes (smart/rush/deep) |
| `thread: set visibility` | Set thread sharing level (private/public/workspace/group) |
| `thread: archive and exit` | Archive current thread |
| `thread: share with support` | Share thread with Sourcegraph staff |
| `thread: map` | Visual graph of connected threads |
| `agents-md list` | View loaded AGENTS.md files |
| `skill: add` | Install skill from git source |
| `skill: list` | View installed skills |
| `skill: remove` | Remove skill |
| `skill: invoke` | User-invokable skill loading (Jan 7, 2026) |
| `ide connect` | Connect to IDE |
| `paste image from clipboard` | Attach images (Windows fallback) |
| `queue` | Queue message for later delivery |
| `theme: switch` | Change CLI theme |
| `amp: help` | View extended keybindings |

### CLI Subcommands

```
amp                              # Interactive mode
amp -x "prompt"                  # Execute mode (non-interactive)
amp --execute --stream-json      # Streaming JSON output
amp --stream-json-thinking       # Include thinking in JSON
amp --stream-json-input          # Accept JSON on stdin
amp --dangerously-allow-all      # Skip all permission checks
amp --jetbrains                  # JetBrains IDE detection
amp --mcp-config '{...}'         # Inline MCP config
amp --ide                        # Connect to IDE
amp permissions list             # Show permission rules
amp permissions list --builtin   # Show built-in rules only
amp permissions edit             # Edit rules in $EDITOR
amp permissions add <action> <tool>  # Add permission rule
amp permissions test <tool> <args>   # Test without execution
amp tools list                   # List all available tools
amp tools make [--bash|--zsh]    # Create new toolbox tool
amp tools show <tool-name>       # View tool schema
amp tools use <tool> [--arg val] # Invoke tool directly
amp tools use --only output <tool>  # Output only
amp skill add [path/url]         # Install skill
amp mcp add [name] [config]     # Add MCP server
amp mcp approve [name]          # Approve workspace MCP
amp mcp doctor                  # MCP server diagnostics
amp mcp oauth login [name]      # Manual OAuth registration
amp mcp oauth logout [name]     # Clear OAuth credentials
amp usage                        # Check credits balance
amp review                       # Trigger code review
amp threads continue [id]        # Resume thread
amp threads share <id> --support # Share with support
amp --help                       # Help
```

**Custom command support**: Deprecated. Replaced by Skills system (Jan 2026).

---

## 2. Hook System (2 event types, 2 action types)

Hooks let you deterministically override Amp's behavior. Configured in `amp.hooks` array in settings (e.g., `.vscode/settings.json` or equivalent).

### Event Types

| Event | Description |
|-------|-------------|
| `tool:pre-execute` | Fires before a tool call executes |
| `tool:post-execute` | Fires after a tool call completes |

### Action Types

| Action | Allowed Events | Description |
|--------|---------------|-------------|
| `send-user-message` | `tool:pre-execute` | Interrupts agent, cancels tool call, sends user message |
| `redact-tool-input` | `tool:post-execute` | Redacts tool input after execution (for side-effect-only or sensitive tools) |

### Hook Configuration Properties

- `event`: The event type (required)
- `tools`: Array of tool names to match (e.g., `["edit_file", "create_file"]`)
- `input.contains`: Exact string match on tool input (no regex support)
- `action.type`: The action to take
- `action.message`: Message content (for send-user-message)
- `compatibilityDate`: Version compatibility date

### Example

```json
{
  "amp.hooks": [{
    "compatibilityDate": "2025-05-13",
    "event": "tool:pre-execute",
    "tools": ["edit_file", "create_file"],
    "input": { "contains": "export let" },
    "action": { "type": "send-user-message", "message": "Use export const instead of export let" }
  }]
}
```

---

## 3. Keyboard Shortcuts & Input (12+ keybindings)

### CLI Keybindings

| Shortcut | Function |
|----------|----------|
| `Ctrl+O` | Open command palette |
| `Ctrl+G` | Open current prompt in `$EDITOR` |
| `Ctrl+S` | Switch agent modes |
| `Ctrl+R` | Prompt history search |
| `Ctrl+V` | Paste image from clipboard |
| `Ctrl+B` | Background a running task |
| `Alt+T` | Expand/collapse thinking/tool blocks |
| `Alt+D` | Toggle deep reasoning effort |
| `Up/Down` | Navigate and edit prior messages |
| `Tab` | Navigate to prior messages |
| `e` | Edit message (after Tab navigation) |
| `Shift+Enter` | Insert newline (requires modern terminal; tmux needs `extended-keys`) |
| `@` | File mention with fuzzy search |
| `@@` | Search threads to mention |
| `$` | Shell command execution (output in context) |
| `$$` | Incognito shell execution (output not in context) |

### Input Modes

- **Single-line**: Enter submits
- **Multi-line**: Shift+Enter for newlines (configurable via `amp.submitOnEnter`)
- **Shell prefix**: `$` and `$$` for inline shell execution
- **File mentions**: `@filename`, `@~/path`, `@path/**/*.ext` (glob patterns)
- **Thread mentions**: `@@` to reference other threads
- **External editor**: Ctrl+G opens `$EDITOR` for longer prompts

---

## 4. Tool System (45-50 built-in tools)

### Core Tools (Local Filesystem) -- 5

| Tool | Description |
|------|-------------|
| `Read` | Read files or list directories; supports images, PDFs; 1000-line default limit |
| `create_file` | Create or overwrite a file in the workspace |
| `edit_file` | Replace specific text strings using git-style diffs |
| `delete_file` | Remove files |
| `undo_edit` | Revert most recent file edit with diff visualization |

### Search & Navigation -- 4

| Tool | Description |
|------|-------------|
| `Grep` | Search for exact text patterns via ripgrep (100-match limit) |
| `glob` | Fast file pattern matching |
| `finder` | Intelligent AI-powered codebase search (subagent, uses Claude Haiku 4.5) |
| `search_documents` | Document search capability |

### File Modification -- 2

| Tool | Description |
|------|-------------|
| `format_file` | Format file using VS Code formatter |
| `apply_patch` | Apply patch to files using Codex format |

### Shell & Execution -- 2

| Tool | Description |
|------|-------------|
| `Bash` | Execute shell commands; output truncated at 50K chars |
| `repl` | Interactive subprocess evaluation loop |

### Web Tools -- 2

| Tool | Description |
|------|-------------|
| `web_search` | Search the web for information |
| `read_web_page` | Read and convert web pages to markdown |

### AI Sub-Agent Tools -- 6

| Tool | Description | Model |
|------|-------------|-------|
| `Task` | Spawn subagents for parallel independent work | Inherited from parent |
| `oracle` | Expert reasoning advisor (planning, review, debugging) | GPT-5.4 |
| `librarian` | Cross-repository code research (GitHub + Bitbucket) | Claude Sonnet 4.6 |
| `look_at` | Analyze images/PDFs without context bloat | Gemini 3 Flash |
| `code_review` | Composable code review with custom checks | Gemini 3 Pro |
| `skill` | Load domain-specific instruction sets | N/A |

### Thread & Memory Tools -- 5

| Tool | Description |
|------|-------------|
| `read_thread` | Extract content from other Amp threads |
| `find_thread` | Find threads using query DSL |
| `handoff` | Hand off work to a new background thread |
| `save_memory` | Save facts/preferences to long-term memory |
| `ask` | Ask user questions during execution |

### Visualization Tools -- 3

| Tool | Description |
|------|-------------|
| `mermaid` | Render interactive Mermaid diagrams |
| `walkthrough` | Interactive annotated walkthrough |
| `walkthrough_diagram` | Clickable Mermaid diagrams linking to code |

### Image Generation -- 1

| Tool | Description | Model |
|------|-------------|-------|
| `painter` | Generate and edit images (mockups, icons, redaction) | Gemini 3 Pro Image |

### GitHub Repository Tools -- 7

| Tool | Description |
|------|-------------|
| `read_github` | Read files from GitHub repos |
| `search_github` | Search code patterns in repositories |
| `commit_search` | Search commits with metadata |
| `list_directory_github` | List directory contents in GitHub repo |
| `list_repositories` | List and search repositories |
| `glob_github` | Find files matching glob pattern in repo |
| `diff` | Get diff between commits/branches/tags |

### Bitbucket Enterprise Tools -- 7

| Tool | Description |
|------|-------------|
| `read_bitbucket_enterprise` | Read files from Bitbucket repos |
| `search_bitbucket_enterprise` | Search code in Bitbucket |
| `commit_search_bitbucket_enterprise` | Search Bitbucket commits |
| `list_directory_bitbucket_enterprise` | List Bitbucket directory |
| `list_repositories_bitbucket_enterprise` | List Bitbucket repositories |
| `glob_bitbucket_enterprise` | Glob pattern matching in Bitbucket |
| `diff_bitbucket_enterprise` | Get Bitbucket diffs |

### Other Tools -- 5

| Tool | Description |
|------|-------------|
| `get_diagnostics` | Get IDE diagnostic information |
| `get_document` | Document retrieval |
| `Check` | Code quality verification |
| `task_list` | Plan and track tasks (formerly todo_read/todo_write) |
| `restore_snapshot` | Restore file/directory to previous state |
| `read_mcp_resource` | Read resources from MCP servers |

### MCP Server Support

Full MCP protocol support with:
- Local command-based servers (`command` + `args`)
- Remote HTTP endpoints (`url`)
- OAuth support (automatic or manual)
- Tool filtering via `includeTools` glob patterns
- Workspace MCP servers require explicit approval
- MCP Registry allowlist (Enterprise)
- Loading precedence: CLI flags > user config > skills
- `amp mcp doctor` for diagnostics

### Toolbox System (Custom Tools)

Executable scripts discovered from `AMP_TOOLBOX` environment variable (colon-separated paths, default `~/.config/amp/tools`). Tools use a simple stdin/stdout protocol:

- `TOOLBOX_ACTION=describe` returns tool schema (JSON or text format)
- `TOOLBOX_ACTION=execute` runs the tool
- Tools get `tb__` prefix when registered
- JSON or key-value I/O formats supported
- `amp tools make` scaffolds new tools

### Tool Approval Model

Ordered permission rules checked before every tool invocation:
- **allow**: Run silently
- **reject**: Block with optional message
- **ask**: Prompt operator
- **delegate**: External program decides (exit 0=allow, 1=ask, >=2=reject)

Built-in allowlist covers common dev commands (git status, npm test, cargo build, ls, etc.).

---

## 5. Context Management

### Context Window

- Up to **200,000 tokens** standard context
- **1M token context** available in `large` mode (Claude Sonnet 4.5)
- No compaction support -- use **handoff** instead to start fresh threads with relevant context

### File Mentions

- `@filename` -- specific file reference with fuzzy search
- `@~/path` -- home-relative paths
- `@path/**/*.ext` -- glob patterns
- `@@` -- search threads to mention
- Drag-and-drop files into CLI terminal
- `Ctrl+V` paste images from clipboard

### Image Support

- Paste images via Ctrl+V (CLI)
- Drag image files into terminal
- `@` mention image files by path
- `look_at` tool for image/PDF analysis without context bloat (uses Gemini 3 Flash)
- PDF analysis supported

### Codebase Search / Indexing

- `finder` subagent (Claude Haiku 4.5) for intelligent codebase search
- `Grep` (ripgrep-based) for exact pattern matching
- `glob` for file pattern matching
- `librarian` subagent for cross-repository GitHub/Bitbucket code search
- `search_github` / `search_bitbucket_enterprise` for remote code search
- `fuzzy.alwaysIncludePaths` setting to force-include gitignored files
- No local codebase indexing (partial code sent to LLM, never full clone)

### AGENTS.md (Instruction Files)

Amp automatically includes:
- `AGENTS.md` in current directory and parent directories (up to `$HOME`)
- Subtree `AGENTS.md` files when agent reads files in those directories
- `~/.config/amp/AGENTS.md` and `~/.config/AGENTS.md` if present

Features:
- **Globs frontmatter**: YAML `globs` field restricts instructions to matching files
  ```yaml
  ---
  globs:
    - '**/*.ts'
    - '**/*.tsx'
  ---
  Follow these TypeScript conventions...
  ```
- Globs implicitly prefixed with `**/` unless they start with `../` or `./`
- Hierarchical: nearest file in directory tree takes precedence
- Also reads `.claude/` paths for compatibility

---

## 6. Session Management (Cloud Threads)

### Thread Persistence

- All threads sync to `ampcode.com` cloud backend
- Accessible via `ampcode.com/threads` web UI
- Resume any thread: `amp threads continue [threadId]`
- Cross-device continuation
- Thread data encrypted at rest (AES-256) and in transit (TLS 1.2+)

### Thread Features

| Feature | Description |
|---------|-------------|
| **Handoff** | Transfer work to new thread preserving context (replaces compaction) |
| **Referencing** | Link to prior threads via URL or `@@thread-id` |
| **Finding** | Search threads by keyword, file, author, date (`find_thread` tool) |
| **Archiving** | Remove from active list while preserving access |
| **Labels** | Custom tags with autocomplete; filter by single/multiple labels |
| **Thread Map** | Visual graph of connected threads (handoff/mention relationships) |
| **Forking** | Deprecated (Jan 2026), replaced by handoff + thread mentions |

### Visibility Controls

| Level | Description |
|-------|-------------|
| `workspace` | Shared with workspace (default) |
| `private` | Only creator can see |
| `public` | Discoverable by anyone |
| `unlisted` | Accessible via link only |
| `group` | Shared with specific user groups (Enterprise) |

Enterprise can disable public/private threads, force private-by-default, etc.

### Thread Metadata in Git

- `amp.git.commit.ampThread.enabled`: Add `Amp-Thread` trailer to commits
- `amp.git.commit.coauthor.enabled`: Add `Co-authored-by: Amp` trailer

---

## 7. Configuration

### Config File Locations

| Location | Scope |
|----------|-------|
| `.vscode/settings.json` | Project (VS Code era, still works) |
| `.amp/settings.json` | Project (workspace) |
| `~/.config/amp/settings.json` | User global |
| Managed settings (OS-specific paths) | Enterprise admin |

Enterprise managed settings paths:
- macOS: `/Library/Application Support/ampcode/managed-settings.json`
- Linux: `/etc/ampcode/managed-settings.json`
- Windows: `C:\ProgramData\ampcode\managed-settings.json`

### Settings (40 CLI keys, 36 VS Code keys)

Key settings include:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `amp.anthropic.effort` | string | `"high"` | Effort level (low/medium/high/max) |
| `amp.anthropic.interleavedThinking.enabled` | boolean | `false` | Enable interleaved thinking for Claude 4 |
| `amp.anthropic.thinking.enabled` | boolean | `false` | Extended thinking output |
| `amp.anthropic.temperature` | number | `1` | Temperature for Anthropic models |
| `amp.dangerouslyAllowAll` | boolean | `false` | Skip all confirmations |
| `amp.debugLogs` | boolean | `false` | Debug logging |
| `amp.fuzzy.alwaysIncludePaths` | array | `[]` | Force-include gitignored files |
| `amp.git.commit.ampThread.enabled` | boolean | `true` | Thread trailer in commits |
| `amp.git.commit.coauthor.enabled` | boolean | `true` | Co-author trailer |
| `amp.guardedFiles.allowlist` | array | `[]` | Files bypassing guarded protection |
| `amp.hooks` | array | `[]` | Hook definitions |
| `amp.internal.deepReasoningEffort` | string | `"medium"` | GPT-5.3 Codex reasoning level |
| `amp.mcpServers` | object | `{}` | MCP server definitions |
| `amp.mcpPermissions` | array | `[]` | MCP server access control |
| `amp.network.timeout` | number | `30` | Network request timeout (seconds) |
| `amp.notifications.enabled` | boolean | `true` | Audio notification on completion |
| `amp.notifications.system.enabled` | boolean | `true` | System notifications when unfocused |
| `amp.permissions` | array | (defaults) | Tool permission rules |
| `amp.showCosts` | boolean | `true` | Display usage costs |
| `amp.skills.path` | string | undefined | Additional skill directories (colon-separated) |
| `amp.submitOnEnter` | boolean | `true` | Enter submits (vs Ctrl+Enter) |
| `amp.terminal.animation` | boolean | `true` | Terminal animations |
| `amp.terminal.theme` | string | `"terminal"` | CLI color theme |
| `amp.toolbox.path` | string | undefined | Toolbox script directory |
| `amp.tools.disable` | array | `[]` | Disable specific tools |
| `amp.tools.enable` | array | undefined | Enable tool name patterns (glob) |
| `amp.tools.inactivityTimeout` | number | `300` | Cancel bash after N seconds idle |
| `amp.tools.stopTimeout` | number | `300` | Tool stop timeout |
| `amp.updates.mode` | string | `"auto"` | Update checking (auto/warn/disabled) |

### Environment Variables (23 total)

| Variable | Purpose |
|----------|---------|
| `AMP_API_KEY` | Authentication for non-interactive/CI usage |
| `AMP_HOME` | Custom home directory |
| `AMP_TOOLBOX` | Colon-separated toolbox paths (empty disables) |
| `AMP_LOG_FILE` | Log file path |
| `AMP_LOG_LEVEL` | Log verbosity |
| `AMP_DEBUG` | Debug mode |
| `AMP_URL` | Custom server URL |
| `AMP_WORKER_URL` | Cloudflare Worker URL |
| `AMP_SETTINGS_FILE` | Custom settings file path |
| `AMP_RIPGREP_PATH` | Custom ripgrep binary |
| `AMP_PWD` | Override working directory |
| `AMP_SDK_VERSION` | SDK version identifier |
| `AMP_VERSION` | CLI version |
| `AMP_ENABLE_TRACING` | Enable tracing |
| `AMP_INSPECTOR_ENABLED` | Inspector mode |
| `AMP_HEADLESS_OAUTH` | Headless OAuth flow |
| `AMP_SKIP_UPDATE_CHECK` | Skip update check |
| `AMP_RESUME_OTHER_USER_THREADS_INSECURE` | Allow resuming others' threads |
| `AMP_CLI_STDOUT_DEBUG` | CLI stdout debug |
| `AMP_TEST_UPDATE_STATUS` | Test update status |
| `NO_ANIMATION` | Disable animations |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `TOOLBOX_ACTION` | Toolbox protocol action (describe/execute) |

---

## 8. Git Integration

### Built-in Capabilities

- **Commit tool**: Create commits with optional `Amp-Thread` trailer and `Co-authored-by` trailer
- **Git blame**: Inspect file history
- **Diff viewing**: `git diff --staged`, `diff` tool for comparing commits/branches/tags
- **Commit search**: `commit_search` tool for searching commit history with metadata
- **GitHub integration**: Full GitHub tools (read, search, list repos, glob, diff -- 7 tools)
- **Bitbucket Enterprise**: Mirror set of 7 tools for Bitbucket

### PR Creation

- Not built-in directly, but patterns documented for using `gh` CLI
- Amp patterns automate PR creation with intelligent titles/descriptions
- `amp review` for pre-commit code review

### Code Review (Feb 4, 2026)

- `amp review` CLI command triggers composable code review
- Custom checks in `.agents/checks/` directories
- Checks are YAML-frontmatter markdown files with name, description, severity-default
- Hierarchical: root `.agents/checks/` for whole codebase, nested dirs for scoped review
- Separate subagent per check (stronger guarantees)
- GitHub App available (`sourcegraph/cra-github`) for automated PR reviews

### Branch Management

- Git operations via Bash tool (no dedicated branch management tool)
- Thread-aware commit messages

---

## 9. Security & Sandboxing

### Permission Model

- Ordered rule list checked before **every** tool invocation
- 4 actions: `allow`, `reject`, `ask`, `delegate`
- Pattern matching: string globs (`*`), regex (`/pattern/`), arrays (OR), nested objects
- Context restriction: `"context": "thread"` (main only) or `"context": "subagent"` (sub only)
- Delegation to external programs (exit code protocol)
- Text format alternative: `allow Bash --cmd 'git *'`
- Commands: `amp permissions list`, `edit`, `test`, `add`

### Default Permission Rules

Built-in allowlist covers: `git status`, `git diff`, `git log`, `npm test`, `cargo build`, `ls`, and many other common read-only/safe commands.

Default ask rules for: `git push`, `git commit`, `git branch -D`, `git checkout HEAD`.

### Sandboxing

- No OS-level sandbox (no bwrap/container isolation)
- Relies on permission rules for tool access control
- `--dangerously-allow-all` flag to bypass all checks
- Previous vulnerability: could write files outside project folder (fixed)
- Guarded files system: `amp.guardedFiles.allowlist` for sensitive file protection

### Data Security

- **Secret redaction**: Auto-detects AWS, GCP, Azure, GitHub, GitLab, OpenAI, Anthropic, HuggingFace tokens; replaces with `[REDACTED:amp]`
- **Zero data retention (ZDR)**: Enterprise plans only; text inputs not retained by LLM providers
- **Encryption**: AES-256 at rest, TLS 1.2+ in transit
- **No codebase cloning**: Only partial code snippets sent to LLM
- Credentials stored locally at `~/.local/share/amp/secrets.json`
- Client avoids reading `.env` and credential files
- Bug bounty program (prompt injection out of scope for rewards)

---

## 10. Agent Features

### Agent Modes (6 total, 3 primary + 3 secondary)

| Mode | Model | Tools | Description |
|------|-------|-------|-------------|
| **smart** | Claude Opus 4.6 | 29 + 3 deferred | State-of-the-art, unconstrained |
| **rush** | Claude Haiku 4.5 | 25 | Fast, cheap, well-defined tasks |
| **deep** | GPT-5.3 Codex | 6 + 3 deferred | Extended reasoning, autonomous 5-15 min |
| **large** | Claude Sonnet 4.5 (1M tokens) | 29 + 3 deferred | Maximum context window |
| **free** | Claude Haiku 4.5 | 16 | Ad-supported tier |
| **bombadil** | Fireworks Kimi K2.5 | 29 + 3 deferred | Experimental open model |

### Subagent Modes (6 total)

| Subagent | Model | Tools | MCP |
|----------|-------|-------|-----|
| `task-subagent` | Inherited | 13 | Enabled |
| `code-review` | Claude Sonnet 4.5 | 6 | Disabled |
| `codereview-check` | Claude Haiku 4.5 | 4 | Disabled |
| `finder` | Claude Haiku 4.5 | 3 | Disabled |
| `librarian` | Claude Haiku 4.5 | 7 | Disabled |
| `oracle` | GPT-5.2 | 7 | Disabled |

### Subagent Architecture

- Spawned via `Task` tool for parallel independent work
- Each subagent has own context window and tool access
- Limitations: no inter-subagent communication, no mid-task user guidance, main agent receives only final summary
- Ctrl+B to background a running task

### Think/Plan Mode

- `deep` mode uses extended reasoning (GPT-5.3 Codex)
- `oracle` tool provides secondary reasoning (GPT-5.4)
- Natural language "plan but don't write code yet" instructions
- `amp.internal.deepReasoningEffort`: medium/high/xhigh
- `amp.anthropic.effort`: low/medium/high/max

### Headless / Non-Interactive Mode

- `amp -x "prompt"` for execute mode
- `echo "text" | amp -x` for piped input
- `--stream-json` for structured JSON output
- `--stream-json-input` for programmatic multi-turn conversations
- `AMP_API_KEY` environment variable for CI/CD
- SDK (TypeScript + Python) for programmatic execution

### Background Tasks

- Ctrl+B backgrounds a running task
- `handoff` tool hands work to new background thread
- Message queuing via command palette `queue`

---

## 11. UI/UX Features

### CLI vs TUI

Amp is a proper **TUI** (Terminal User Interface, since Sep 2, 2025) -- not a simple CLI REPL. Eliminated flicker, true terminal application.

### Themes (8 built-in + custom)

Built-in: `terminal` (transparent, default), `dark`, `light`, `catppuccin-mocha`, `solarized-dark`, `solarized-light`, `gruvbox-dark-hard`, `nord`

Custom themes: `~/.config/amp/themes/<name>/colors.toml` with YAML metadata. Minimal themes require 6 colors (background, foreground, primary, success, warning, destructive). Full themes support syntax highlighting.

### Markdown / Syntax Rendering

- Markdown rendering in terminal output
- Mermaid diagram rendering (interactive, clickable)
- Walkthrough diagrams with annotated code links
- Code blocks with syntax highlighting

### Progress / Streaming

- Real-time streaming of model responses
- Thinking/tool block expand/collapse (Alt+T)
- Cost display per thread (`amp.showCosts`)
- Audio notifications on task completion
- System notifications when terminal unfocused
- Terminal animations (configurable, `amp.terminal.animation`)

### Amp Tab (In-Editor Completions)

- Intent-aware code completion (not just next-token)
- Multi-line and multi-file edit suggestions
- Uses recent edits, language server diagnostics, semantic context
- 30% faster since Jul 2025 optimization
- On by default since Sep 23, 2025 (for VS Code/Cursor/Windsurf)
- Diagnostic-driven: suggests file-wide fixes based on IDE errors

---

## 12. Extensibility & Integration

### Skills System

Reusable instruction packages replacing custom commands:

- Project skills: `.agents/skills/<name>/SKILL.md`
- User skills: `~/.config/agents/skills/<name>/SKILL.md`
- Compatibility: `.claude/skills/`, `~/.claude/skills/`
- Skills can bundle MCP servers via `mcp.json`
- `includeTools` filtering to keep tool lists clean
- User-invokable via command palette `skill: invoke`
- `amp skill add <git-url>` to install from remote

Community skills repository: [ampcode/amp-contrib](https://github.com/ampcode/amp-contrib)

Featured skills: Agent Sandbox, Agent Skill Creator, BigQuery, Tmux, Web Browser, UI Preview

### MCP Protocol Support

- Full MCP protocol support (local + remote)
- Streamable HTTP transport (since Jul 8, 2025)
- OAuth support (automatic + manual)
- `amp.mcpServers` configuration in settings
- `amp.mcpPermissions` for server access control
- `amp mcp add`, `amp mcp approve`, `amp mcp doctor` commands
- Workspace MCP servers require explicit approval
- Enterprise: MCP Registry allowlist

### IDE Integrations

| Editor | Method | Status |
|--------|--------|--------|
| VS Code | Extension (discontinued Mar 5, 2026) | CLI via `amp --ide` |
| Cursor | Extension (discontinued Mar 5, 2026) | CLI via `amp --ide` |
| Neovim | `amp.nvim` plugin + CLI | Active |
| JetBrains | `amp --jetbrains` CLI flag | Active |
| Zed | CLI via `amp --ide` | Active |
| Emacs | Community `amp-emacs` plugin | Community |

IDE integration provides: diagnostics reading, current file/selection context, undo-compatible file editing.

### SDKs

| SDK | Install | Key Function |
|-----|---------|-------------|
| TypeScript | `npm install @sourcegraph/amp-sdk` | `execute()` async generator |
| Python | `pip install amp-sdk` | `execute()` async function |

SDK features: prompt input, mode selection, permission rules, MCP configuration, thread continuity, labels, visibility control, abort signals, streaming messages.

### Sourcegraph Integration

- `librarian` tool accesses Sourcegraph code intelligence
- GitHub and Bitbucket Enterprise repository tools (14 total)
- Sourcegraph MCP server available for direct integration

### API Access

- `AMP_API_KEY` for non-interactive usage
- `--stream-json` / `--stream-json-input` for structured I/O
- Enterprise API access included

---

## 13. Model & Provider Support

### Models in Use (as of March 2026)

| Role | Model | Provider |
|------|-------|----------|
| Smart mode (primary) | Claude Opus 4.6 | Anthropic |
| Rush mode | Claude Haiku 4.5 | Anthropic |
| Deep mode | GPT-5.3 Codex | OpenAI |
| Large mode | Claude Sonnet 4.5 (1M ctx) | Anthropic |
| Free mode | Claude Haiku 4.5 | Anthropic |
| Bombadil mode | Kimi K2.5 | Fireworks |
| Oracle subagent | GPT-5.4 (medium reasoning) | OpenAI |
| Librarian subagent | Claude Sonnet 4.6 | Anthropic |
| Code review | Gemini 3 Pro | Google |
| Search subagent | Gemini 3 Flash | Google |
| Look At (image/PDF) | Gemini 3 Flash | Google |
| Painter (image gen) | Gemini 3 Pro Image | Google |
| Handoff analysis | Gemini 3 Flash | Google |
| Thread titling | Claude Haiku 4.5 | Anthropic |
| Finder subagent | Claude Haiku 4.5 | Anthropic |
| Code review checks | Claude Haiku 4.5 | Anthropic |

### LLM Providers Used

- **Anthropic** (Claude Opus 4.6, Sonnet 4.6, Sonnet 4.5, Haiku 4.5)
- **OpenAI** (GPT-5.4, GPT-5.3 Codex)
- **Google Vertex AI** (Gemini 3 Pro, Gemini 3 Flash, Gemini 3 Pro Image)
- **Fireworks** (Kimi K2.5)
- **Amazon Bedrock** (mentioned in security docs)
- **Baseten** (mentioned in security docs)
- **xAI** (mentioned in earlier docs, Grok)

### Model Switching

- `Ctrl+S` or command palette `mode` to switch modes
- No bring-your-own-key (BYOK) -- BYOK/Isolated Mode was removed May 8, 2025
- No custom model selection; Amp selects best model per task
- `OPENROUTER_API_KEY` environment variable exists (unclear if active)
- Anthropic temperature configurable (`amp.anthropic.temperature`)
- Deep reasoning effort configurable (`amp.internal.deepReasoningEffort`)

### Token Usage Display

- `amp.showCosts` setting (default: `true`)
- `amp usage` command to check credit balance
- Per-thread cost tracking
- Streaming JSON includes usage stats: `input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`

---

## Notable Differentiators vs. Other CLI Agents

1. **Cloud thread persistence**: All conversations sync to ampcode.com, searchable/shareable
2. **Multi-model ensemble**: 7+ models from 4+ providers, each optimized per task
3. **Librarian subagent**: Cross-repository code intelligence via Sourcegraph backend
4. **Painter tool**: AI image generation (Gemini 3 Pro Image) -- unique among CLI agents
5. **Code review system**: Composable checks with dedicated subagents per check
6. **Thread Map**: Visual graph of conversation relationships
7. **Amp Tab**: Intent-aware in-editor completion (separate from agent)
8. **SDKs (TypeScript + Python)**: Programmatic access for automation
9. **6 agent modes**: smart/rush/deep/large/free/bombadil -- most flexible mode system
10. **Editor extension sunset**: Bold bet on CLI-only future (March 2026)
11. **Walkthrough diagrams**: Interactive annotated codebase exploration
12. **50 built-in tools**: Largest built-in tool set among major CLI agents
13. **Toolbox system**: Simple executable-based custom tools (no MCP server needed)
14. **Enterprise features**: SSO, SCIM, MCP registry allowlist, managed settings, per-user entitlements
