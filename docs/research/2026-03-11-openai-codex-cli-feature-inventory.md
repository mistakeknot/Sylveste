# OpenAI Codex CLI: Comprehensive Feature Inventory

> Research date: 2026-03-11
> Codex CLI version: v0.114.0 (latest as of research date)
> Repository: [github.com/openai/codex](https://github.com/openai/codex)
> Docs: [developers.openai.com/codex/cli](https://developers.openai.com/codex/cli/)

## Overview

Codex CLI is OpenAI's open-source terminal coding agent, rewritten from TypeScript/Ink to **Rust/Ratatui** (the Rust TUI became the maintained default). It runs locally, reads/edits/executes within a selected directory, and connects to OpenAI models (default: GPT-5.4). Licensed Apache-2.0. Installable via `npm i -g @openai/codex` or `brew install codex`, with standalone binaries on GitHub Releases.

Authentication: ChatGPT account (Plus/Pro/Business/Edu/Enterprise) or OpenAI API key. First run triggers OAuth or key entry.

---

## 1. Approval Modes

Codex uses **`--ask-for-approval` / `-a`** with three values:

| Value | Behavior |
|-------|----------|
| `untrusted` | Every file edit and command requires explicit approval. Browse-only by default. |
| `on-request` | Codex reads, edits, and runs commands within the working directory freely. Pauses for approval on out-of-scope operations or network access. |
| `never` | No approval prompts at all. For non-interactive/CI use. |

The legacy `on-failure` mode is deprecated in favor of `on-request` (interactive) or `never` (non-interactive).

**Mid-session switching**: `/permissions` slash command opens a picker with presets:
- **Auto** (default) -- corresponds to `on-request` + `workspace-write` sandbox
- **Read Only** -- browse files, but changes/commands need approval
- **Full Access** -- unrestricted including network; use sparingly

**Granular rejection**: `approval_policy = { reject = { ... } }` in config.toml can auto-reject sandbox approvals, execpolicy prompts, or MCP input requests while leaving other prompts interactive.

**Convenience flag**: `--full-auto` sets `--ask-for-approval on-request` + `--sandbox workspace-write` in one shot.

**YOLO flag**: `--dangerously-bypass-approvals-and-sandbox` (alias `--yolo`) disables all approvals and sandboxing. Intended only for externally hardened environments (VMs, containers).

**Persistence**: Approval grants now persist across turns within a session (v0.114.0).

---

## 2. Sandbox

### 2.1 Sandbox Modes

Controlled by `--sandbox` / `-s`:

| Mode | Filesystem | Network |
|------|-----------|---------|
| `read-only` | No writes anywhere | Blocked |
| `workspace-write` | Writable within CWD (`.git/` and `.codex/` remain read-only); additional roots via `--add-dir` | Blocked by default; configurable via `sandbox_workspace_write.network_access` |
| `danger-full-access` | Unrestricted machine-wide writes | Unrestricted |

### 2.2 Platform Implementations

**Linux**: Landlock (filesystem restrictions) + seccomp (syscall filtering). Bubblewrap (bwrap) is vendored and compiled as part of the Linux build since v0.100.0. Bwrap creates a read-only filesystem view with selective writable mount points. Always unshares user namespace for consistent isolation, even under root. Applies `PR_SET_NO_NEW_PRIVS` and network seccomp filter in-process.

**macOS**: Apple Seatbelt via `sandbox-exec` with mode-specific profiles compiled at runtime, enforced by the kernel. Allows file-read globally (enumerating every possible dependency path is impractical) but isolates writes and network. Recent improvements to Seatbelt network and unix-socket handling (v0.112.0).

**Windows**: Two modes configured in `[windows]` section:
- **Elevated**: Restricted Token with filesystem ACLs, runs commands as a dedicated Windows Sandbox User, installs Windows Firewall rules to limit network.
- **Unelevated**: Lighter-weight fallback.
- `/sandbox-add-read-dir C:\path` grants session-scoped read access to additional directories.

### 2.3 Exec Policy

`codex execpolicy` subcommand evaluates execpolicy rule files to determine whether a command would be allowed, prompted, or blocked. This enables declarative command-level policy beyond the filesystem sandbox.

### 2.4 Split Sandbox Policies (v0.113.0)

New permission-profile config language splits filesystem and network sandbox policies for more precise control. Executable permission profiles merge into the per-turn sandbox (v0.112.0).

---

## 3. Diff Display

- **Syntax-highlighted diffs**: The TUI renders fenced markdown code blocks and file diffs with syntax highlighting using the built-in theme engine.
- **`/diff` slash command**: Shows Git changes (staged, unstaged, untracked) inline in the session.
- **`/review` presets**: Launches a dedicated reviewer that reads a selected diff and reports prioritized, actionable findings:
  - Base branch comparison (auto-detects merge-base)
  - Uncommitted changes inspection
  - Specific commit analysis
  - Custom instruction reviews
- **Inline comments**: Feedback can attach directly to specific diff lines, guiding Codex to fixes.
- Each review appears as a separate transcript turn for iteration tracking.
- **`/theme` command**: Live theme preview + custom `.tmTheme` support. Color theme persists to `~/.codex/config.toml`.

---

## 4. Streaming and Response Display

### 4.1 Interactive TUI Streaming

Built on **Ratatui** (Rust TUI framework) with **Crossterm** for cross-platform terminal abstraction. Uses alternate screen mode (disableable via `--no-alt-screen`).

**Markdown rendering**: `MarkdownStreamCollector` processes incremental markdown input via `pulldown-cmark`, maintaining state across deltas. Syntax-highlighted code blocks render in real time as tokens arrive.

**Event-driven architecture**: Core event system uses `tokio::sync::mpsc::unbounded_channel` to decouple UI interactions from business logic. `AppEventSender` logs all inbound events for session replay.

### 4.2 Non-Interactive Streaming

`codex exec` streams progress to stderr and prints only the final agent message to stdout. With `--json`, stdout becomes a JSON Lines stream with event types:
- `thread.started`
- `turn.started` / `turn.completed` / `turn.failed`
- `item.started` / `item.completed`
- `error`

### 4.3 In-Flight Interaction

- **Enter while running**: Injects new instructions into the active turn.
- **Tab while running**: Queues a follow-up prompt.
- **Esc**: Interrupts current task.
- **Ctrl+C**: Quits session.

---

## 5. Terminal UI Layout and Design

### 5.1 Architecture

The TUI is a full-screen application with two main regions:

- **ChatWidget** (`tui/src/chatwidget.rs`): Main conversation surface. Consumes protocol events, maintains transcript state, renders streamed markdown and diffs.
- **BottomPane** (`tui/src/bottom_pane/mod.rs`): Input layer containing `ChatComposer` for text editing and popup views for approvals, slash command picker, file mentions, etc. Routes keys to composer or active popup.

### 5.2 Footer and Status Line

The footer is a stacked, responsive component:

```
[Mode Indicator] [Context Window] [Status Line]     [Shortcut Hints]
```

Falls back to two-line layout when width is constrained; hint-only fallback at minimum widths.

**Configurable status line items** (via `/statusline`):
- model, approval, sandbox, session-id, directory, branch (async git lookup), personality, collaboration

**Mode indicators**: `[ Plan ]` yellow, `[ Code ]` green, `[ Agent ]` cyan.

**Context window display**: `85% . 34k tokens` -- shows percentage used and token count.

**Dynamic shortcut hints** adapt to state:
- Empty composer: `Enter` submit, `?` shortcuts
- Non-empty draft: `Enter` submit, `Shift+Enter` newline, `Tab` queue
- Task running: `Esc` interrupt, `Ctrl+C` quit
- Quit armed: `Ctrl+C` again to quit (with timeout)

**Flash messages**: Temporary footer replacements for confirmations ("Copied to clipboard"), warnings, and one-shot hints.

### 5.3 Color Scheme

Consistent across terminal themes: cyan for user tips, green for success, red for errors, magenta for Codex-specific elements. Dim styling for separators and secondary info, gray italics for personality indicators.

---

## 6. Context: Project Instructions (AGENTS.md)

### 6.1 Discovery Chain

Codex builds an instruction chain once per session:

1. **Global scope**: `~/.codex/AGENTS.override.md` > `~/.codex/AGENTS.md` (first non-empty file wins)
2. **Project scope**: Walks from Git root down to CWD. At each directory: `AGENTS.override.md` > `AGENTS.md` > fallback names from `project_doc_fallback_filenames`

Files concatenate root-to-leaf; closer files override earlier ones. At most one file per directory enters the prompt.

### 6.2 Limits and Configuration

| Setting | Default | Purpose |
|---------|---------|---------|
| `project_doc_max_bytes` | 32 KiB | Combined size limit; stops adding files when reached |
| `project_doc_fallback_filenames` | None | Alternate filenames to scan per directory |
| `CODEX_HOME` | `~/.codex` | Custom home location |

### 6.3 Trust Model

Untrusted projects skip project-scoped `.codex/` config layers entirely. Organizations can enforce constraints via `requirements.toml` on managed machines.

### 6.4 Helper

`/init` slash command scaffolds an `AGENTS.md` file for the current repo.

---

## 7. Session Management

### 7.1 Transcript Storage

Sessions persist as JSONL rollout files under `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. Each file contains the full conversation history, tool calls, and token usage.

Controlled by:
- `history.persistence`: `save-all` (default) or `none`
- `history.max_bytes`: Cap on history file size

### 7.2 Resume

`codex resume` continues a previous session:
- `--last`: Immediately resumes most recent session
- `--all`: Shows sessions from any directory (not just CWD)
- `SESSION_ID`: Targets a specific session UUID
- Accepts optional follow-up prompt as string or stdin

Resumed sessions preserve the original transcript, plan history, and approvals. Git context and app enablement are also restored (v0.111.0).

### 7.3 Fork

`codex fork` clones the current conversation into a new thread with a fresh ID, leaving the original untouched. Also available via:
- **Esc x2**: Edits previous user message; repeated presses walk back through transcript. Hit Enter to fork from that point.
- Enables exploring alternative approaches in parallel.

### 7.4 Draft Navigation

Up/Down arrows restore prior prompt text and image placeholders within a session.

### 7.5 Non-Interactive Resume

`codex exec resume --last "next task"` or `codex exec resume <SESSION_ID>` continues work across CI pipeline stages.

---

## 8. Multi-Turn Conversation

### 8.1 Interactive Flow

The TUI is inherently multi-turn. Each prompt → response cycle appears as a transcript turn. The model maintains full conversation context within the session.

### 8.2 Context Window Management

**Automatic compaction**: When token count exceeds a threshold (`model_auto_compact_token_limit`), Codex automatically compacts the conversation. The compaction:
1. Queries the Responses API with the existing conversation + summarization instructions
2. Produces a summary including a special `type=compaction` item with `encrypted_content` that preserves the model's latent understanding
3. Replaces the conversation with the compacted version

**Manual compaction**: `/compact` slash command triggers compaction on demand. "Summarize conversation history to free context tokens while preserving key points."

**Model context window**: Configurable via `model_context_window`. GPT-5.4 supports up to 1M tokens experimentally.

### 8.3 Keyboard Shortcuts

- **Ctrl+G**: Opens `$VISUAL`/`$EDITOR` for longer drafts
- **`@`**: Fuzzy file search with Tab/Enter insertion
- **`!` prefix**: Executes local shell command, result treated as user-provided context
- **`$`**: Mention picker for apps/plugins

---

## 9. Configuration

### 9.1 File Locations and Precedence (highest to lowest)

1. CLI flags and `--config key=value` overrides
2. Profile values (`--profile <name>`)
3. Project config `.codex/config.toml` (closest to CWD wins; trusted projects only)
4. User config `~/.codex/config.toml`
5. System config `/etc/codex/config.toml`
6. Built-in defaults

### 9.2 Key Config Categories

**Model & Provider**:
- `model` (default: `gpt-5.4`)
- `model_provider` (default: `openai`)
- `model_context_window`
- `model_reasoning_effort`: `minimal` | `low` | `medium` | `high` | `xhigh`
- `model_reasoning_summary`: `auto` | `concise` | `detailed` | `none`

**Approval & Sandbox**:
- `approval_policy`: `untrusted` | `on-request` | `never` | `{ reject = { ... } }`
- `sandbox_mode`: `read-only` | `workspace-write` | `danger-full-access`
- `sandbox_workspace_write.writable_roots` and `.network_access`

**Shell Environment**:
```toml
[shell_environment_policy]
inherit = "none"  # or "core"
set = { PATH = "/usr/bin", MY_FLAG = "1" }
ignore_default_excludes = false
exclude = ["AWS_*", "AZURE_*"]
include_only = ["PATH", "HOME"]
```
Automatic KEY/SECRET/TOKEN filtering before include/exclude rules. Patterns are case-insensitive globs.

**Web Search**: `web_search = "cached"` (default) | `"live"` | `"disabled"`

**Personality**: `personality = "friendly"` | `"pragmatic"` | `"none"`

**MCP Servers**:
```toml
[mcp_servers.my_server]
command = "npx my-mcp-server"
enabled_tools = ["tool1", "tool2"]
disabled_tools = ["tool3"]
startup_timeout_sec = 30
```

**Feature Flags**: `[features]` table with toggles: `multi_agent`, `unified_exec`, `undo`, `shell_tool`, `fast_mode`, `shell_snapshot`, etc. Managed via `codex features list|enable|disable`.

**Profiles**:
```toml
[profiles.fast]
model = "gpt-4.1-mini"
model_reasoning_effort = "low"
web_search = "disabled"
```
Loaded via `--profile fast`. Any top-level setting can be overridden per profile.

### 9.3 CLI Flags

| Flag | Purpose |
|------|---------|
| `--model, -m` | Override model |
| `--sandbox, -s` | Sandbox policy |
| `--ask-for-approval, -a` | Approval mode |
| `--full-auto` | Convenience: on-request + workspace-write |
| `--yolo` | Bypass all approvals and sandbox |
| `--cd, -C` | Set working directory |
| `--add-dir` | Grant additional writable directories |
| `--image, -i` | Attach images to initial prompt |
| `--search` | Enable live web search |
| `--profile, -p` | Load config profile |
| `--config, -c` | Override config values |
| `--no-alt-screen` | Disable alternate screen TUI |
| `--oss` | Use local open-source model provider |
| `--enable / --disable` | Toggle feature flags |

---

## 10. Memory System

### 10.1 Architecture

SQLite-backed persistence at `codex_home/state_<version>.sqlite`. Two-phase pipeline:

**Phase 1 (Rollout Extraction)**: Processes completed rollouts asynchronously at startup. Claims up to `max_rollouts_per_startup` jobs from eligible threads. Calls model with structured output schema for `raw_memory`, `rollout_summary`, and `rollout_slug`. Stores in SQLite, auto-redacts secrets.

**Phase 2 (Global Consolidation)**: Serialized singleton job. Reads top-N stage-1 outputs filtered by `memory_mode = 'enabled'` and recency. Spawns a restricted sub-agent (no approvals, workspace-write-only sandbox) to produce consolidated files:
- `memories/MEMORY.md` -- consolidated handbook
- `memories/memory_summary.md` -- user profile (injected into system prompt)
- `memories/raw_memories.md` -- merged Phase 1 outputs
- `rollout_summaries/` -- per-session summaries
- Optional `skills/<name>/SKILL.md` -- reusable procedures

### 10.2 Workspace Scoping

Memories are workspace-scoped with guardrails against stale data (v0.110.0). Sessions using disqualifying tools (e.g., web search) are marked `polluted` and trigger a forgetting pass.

### 10.3 Configuration

- `max_raw_memories_for_consolidation`: Top-N outputs fed to Phase 2
- `max_unused_days`: Exclude memories not referenced within window
- `min_rollout_idle_hours`: Skip recently-updated rollouts
- `consolidation_model`: Model for Phase 2 agent
- `codex debug clear-memories`: Full reset command

---

## 11. Multi-Agent System

### 11.1 Enabling

Feature flag: `multi_agent = true` in `[features]`. Or `/experimental` > enable Multi-agents > restart.

### 11.2 Orchestration

Codex handles complete orchestration:
- Spawns sub-agents and routes instructions
- Awaits results from all agents
- Closes completed threads
- Automatic decisions about when to spawn (or accepts explicit requests)
- Returns consolidated response when all agents complete

### 11.3 Agent Management

- `/agent`: Switch between active threads, steer/stop/close sub-agents
- Ordinal nicknames and role labels for clarity
- Approval requests surface with source thread labels; press `o` to open that thread before approving
- Sub-agents inherit parent sandbox policy; parent overrides (including `/approvals` changes or `--yolo`) reapply to children

### 11.4 Built-in Roles

| Role | Purpose |
|------|---------|
| `default` | General-purpose fallback |
| `worker` | Execution-focused implementation |
| `explorer` | Read-heavy codebase analysis |
| `monitor` | Long-running task/command monitoring (up to 1hr polling) |

### 11.5 Configuration

```toml
[agents]
max_threads = 6          # concurrent thread cap
max_depth = 1            # nesting depth
job_max_runtime_seconds = 600

[agents.reviewer]
description = "Checks correctness and security"
config_file = "reviewer.toml"  # role-specific TOML
```

Each role can override: `model`, `model_reasoning_effort`, `sandbox_mode`, `developer_instructions`. Unspecified settings inherit from parent.

### 11.6 CSV Batch Processing

`spawn_agents_on_csv` distributes work across agents:
- One row = one work item
- Parameters: `csv_path`, `instruction`, `id_column`, `output_schema`, `output_csv_path`, `max_concurrency`, `max_runtime_seconds`
- Each worker calls `report_agent_job_result` exactly once

---

## 12. Slash Commands (27 documented)

### Session & Navigation
| Command | Behavior |
|---------|----------|
| `/model` | Switch model and reasoning effort level |
| `/personality` | Change style: `friendly`, `pragmatic`, `none` |
| `/plan` | Enter plan mode with optional inline prompt |
| `/new` | Fresh conversation in same CLI session |
| `/clear` | Reset terminal view and conversation |
| `/resume` | Continue previous session via picker |
| `/fork` | Clone conversation into new thread |
| `/compact` | Summarize history to free context tokens |

### Permissions & Config
| Command | Behavior |
|---------|----------|
| `/permissions` | Switch approval presets mid-session |
| `/experimental` | Toggle experimental features (requires restart) |
| `/statusline` | Pick and reorder footer items; persists to config.toml |
| `/debug-config` | Print config layer precedence, policy sources, MCP/rules diagnostics |

### Files & Review
| Command | Behavior |
|---------|----------|
| `/mention` | Attach specific files/folders to direct attention |
| `/diff` | Display Git changes inline |
| `/review` | Launch dedicated reviewer on selected diff |
| `/sandbox-add-read-dir` | Grant Windows sandbox read access to directory |

### Information
| Command | Behavior |
|---------|----------|
| `/status` | Show active model, approval policy, writable roots, token usage |
| `/mcp` | List configured MCP tools |
| `/ps` | Show background terminals and recent output |
| `/copy` | Copy latest output to clipboard |

### Tools & Integration
| Command | Behavior |
|---------|----------|
| `/apps` | Browse and insert app connectors |
| `/agent` | Switch active agent thread |
| `/init` | Generate AGENTS.md scaffold |

### Account & Exit
| Command | Behavior |
|---------|----------|
| `/logout` | Clear local credentials |
| `/quit` or `/exit` | Exit CLI |
| `/feedback` | Submit logs and diagnostics |

**Custom slash commands**: Stored on disk, team-specific. Type `/` to open the popup and filter.

---

## 13. Non-Interactive Mode (`codex exec`)

### 13.1 Core Behavior

```bash
codex exec "your task prompt here"
```

Progress streams to stderr; final agent message to stdout. Default: read-only sandbox.

### 13.2 Key Flags

| Flag | Purpose |
|------|---------|
| `--ephemeral` | No session files persisted |
| `--json` | JSONL event stream to stdout |
| `-o, --output-last-message` | Write final message to file |
| `--output-schema` | JSON Schema for validating response shape |
| `--skip-git-repo-check` | Run outside Git repos |
| `--color` | `always` / `never` / `auto` |
| `--full-auto` | Allow edits without approval gates |

### 13.3 Structured Output

```bash
codex exec "Extract project metadata" \
  --output-schema ./schema.json \
  -o ./output.json
```

Response conforms to the provided JSON Schema.

### 13.4 GitHub Action

`openai/codex-action@v1` installs CLI, starts Responses API proxy, runs `codex exec`. Drops sudo so Codex cannot access its own API key. Supports automated PR reviews, CI quality gates, and auto-fix workflows on CI failure.

---

## 14. Web Search

Built-in first-party web search tool:

| Mode | Behavior |
|------|----------|
| `cached` (default) | Results from OpenAI-maintained search index |
| `live` | Real-time web results (via `--search` flag or `web_search = "live"`) |
| `disabled` | No web search |

Web search supports full tool configuration including filters and location (v0.113.0).

---

## 15. Codex Cloud Integration

`codex cloud` subcommand manages cloud tasks from the terminal:
- Browse active/finished tasks
- Launch new tasks
- Apply diffs from cloud tasks to local project (`codex apply`)
- Tasks execute in isolated containers with internet disabled during agent phase
- Container caching up to 12 hours; auto-invalidates on setup/env changes
- Setup scripts run with internet; agent phase runs without
- Secrets available to setup scripts only (removed before agent phase)
- Business/Enterprise: caches shared across users with environment access

---

## 16. Unique and Notable Features

### 16.1 Shell Snapshots
`shell_snapshot` feature flag. Caches shell state to speed up repeated commands. Uses shell policy for isolation.

### 16.2 Undo
`undo` feature flag exists in config. Details limited in public docs.

### 16.3 Fast Mode
`/fast` toggle persists across sessions. TUI header indicator shows when active. App-server supports `fast`/`flex` tier.

### 16.4 JS REPL
Built-in JavaScript REPL supports dynamic local `.js`/`.mjs` file imports, image emission (data: URLs only), and cell-level binding persistence.

### 16.5 Image Input
`-i` / `--image` flag attaches PNG/JPEG screenshots or design specs alongside prompts. Comma-separated for multiple images.

### 16.6 `@` File Mentions
Type `@` in the composer to trigger fuzzy file search. Tab/Enter inserts the file path, directing Codex's attention to specific files.

### 16.7 `!` Shell Execution
`!` prefix executes a local shell command; the result is treated as user-provided context (not agent-executed).

### 16.8 Prompt Editor
Ctrl+G opens `$VISUAL`/`$EDITOR` for composing longer prompts externally.

### 16.9 Plugin System (v0.110.0+)
Plugins load skills, MCP entries, and app connectors. `@plugin` mentions in chat (v0.112.0). Plugin marketplace discovery with install-time auth checks (v0.113.0).

### 16.10 Hooks Engine (v0.114.0)
Experimental hooks with `SessionStart` and `Stop` events.

### 16.11 OpenTelemetry Observability
OTel export tracks API requests, SSE/events, prompts, tool approvals/results. Metrics include counters and histograms for API requests, WebSocket activity, and tool execution by name and success status.

### 16.12 Shell Completions
`codex completion` generates scripts for bash, zsh, and fish.

### 16.13 Desktop App
`codex app` launches a macOS desktop application. Also available for Windows. Enables working across multiple projects and parallel agent threads.

### 16.14 IDE Extension
Available for VS Code, Cursor, Windsurf, VS Code Insiders. Shares the same agent engine.

### 16.15 MCP Server Mode
Codex can run as an MCP server itself, allowing connection from other MCP clients (e.g., agents built with OpenAI Agents SDK).

---

## 17. Comparison Notes (vs. Claude Code)

| Dimension | Codex CLI | Claude Code |
|-----------|-----------|-------------|
| **Implementation** | Rust/Ratatui | TypeScript/Ink |
| **Default model** | GPT-5.4 | Claude Sonnet 4 |
| **Sandbox** | Landlock+seccomp+bwrap (Linux), Seatbelt (macOS), ACL+Firewall (Windows) | bwrap (Linux), Seatbelt (macOS) |
| **Approval modes** | 3 modes + granular rejection policy + exec policy | Permission-based with tool-level allow/deny |
| **Multi-agent** | Built-in with roles, CSV batch, thread management | Subagent spawning via tool |
| **Session resume** | `codex resume` with session picker, fork, exec resume | No built-in resume (context carries in conversation) |
| **Context compaction** | Automatic + manual `/compact` with encrypted compaction items | Automatic with summaries |
| **Memory** | Two-phase SQLite pipeline, workspace-scoped, pollution tracking | CLAUDE.md user memory file |
| **Code review** | Built-in `/review` with presets (base branch, uncommitted, commit) | No built-in review command |
| **Non-interactive** | `codex exec` with JSONL streaming, JSON Schema output | `claude --print` / `-p` flag |
| **Web search** | Built-in (cached or live) | Via MCP or tool |
| **Cloud execution** | `codex cloud` with container isolation | Not available |
| **GitHub Action** | First-party `codex-action@v1` | Third-party integrations |
| **Config profiles** | Named profiles in config.toml | Not available |
| **Plugin system** | Skills + MCP + app connectors + marketplace | MCP servers only |
| **SWE-bench** | 69.1% | 72.7% |
| **Terminal-Bench 2.0** | 77.3% (GPT-5.3-Codex) | 65.4% |

---

## Sources

- [GitHub: openai/codex](https://github.com/openai/codex)
- [Codex CLI Documentation](https://developers.openai.com/codex/cli/)
- [Codex CLI Features](https://developers.openai.com/codex/cli/features/)
- [Command Line Options Reference](https://developers.openai.com/codex/cli/reference)
- [Configuration Reference](https://developers.openai.com/codex/config-reference/)
- [Advanced Configuration](https://developers.openai.com/codex/config-advanced/)
- [Config Basics](https://developers.openai.com/codex/config-basic/)
- [Custom Instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md/)
- [Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Multi-Agents](https://developers.openai.com/codex/multi-agent/)
- [Slash Commands](https://developers.openai.com/codex/cli/slash-commands/)
- [Cloud Environments](https://developers.openai.com/codex/cloud/environments/)
- [Windows Support](https://developers.openai.com/codex/windows/)
- [Codex Changelog](https://developers.openai.com/codex/changelog/)
- [Codex GitHub Action](https://developers.openai.com/codex/github-action/)
- [Codex Quickstart](https://developers.openai.com/codex/quickstart/)
- [Codex CLI is Going Native (Discussion #1174)](https://github.com/openai/codex/discussions/1174)
- [Memory System (DeepWiki)](https://deepwiki.com/openai/codex/3.7-memory-system)
- [TUI Implementation (DeepWiki)](https://zread.ai/openai/codex/23-terminal-ui-tui-implementation)
- [Status Line and Footer (DeepWiki)](https://deepwiki.com/openai/codex/4.1.4-status-line-and-footer-rendering)
- [TechCrunch: OpenAI debuts Codex CLI](https://techcrunch.com/2025/04/16/openai-debuts-codex-cli-an-open-source-coding-tool-for-terminals/)
- [Codex vs Claude Code (builder.io)](https://www.builder.io/blog/codex-vs-claude-code)
- [Codex vs Claude Code (Composio)](https://composio.dev/content/claude-code-vs-openai-codex)
- [Codex vs Claude Code (Northflank)](https://northflank.com/blog/claude-code-vs-openai-codex)
- [Codex vs Claude Code (morphllm)](https://www.morphllm.com/comparisons/codex-vs-claude-code)
