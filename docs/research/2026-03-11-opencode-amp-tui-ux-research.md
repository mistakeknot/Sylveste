# OpenCode & Amp: TUI/UX Feature Research

> Research date: 2026-03-11
> Purpose: Exhaustive feature inventory for competitive analysis against Claude Code / Skaffen

---

## Table of Contents

1. [OpenCode](#opencode)
2. [Amp (Sourcegraph)](#amp-sourcegraph)
3. [Community Comparisons](#community-comparisons)
4. [Key Takeaways for Skaffen/Demarch](#key-takeaways)

---

## OpenCode

**Repo**: [github.com/anomalyco/opencode](https://github.com/anomalyco/opencode) (formerly `sst/opencode`, then `opencode-ai/opencode`)
**Language**: TypeScript (rewritten from original Go/Bubble Tea version)
**TUI Framework**: OpenTUI — native Zig core with TypeScript bindings, SolidJS reconciler (`@opentui/solid`)
**Stars**: ~112K (Feb 2026)
**License**: MIT
**Built by**: Anomaly (creators of terminal.shop, SST)

### Architecture

OpenCode is a multi-client system with a single core server:

- **Backend**: TypeScript, Hono HTTP framework, SQLite via Drizzle ORM, Server-Sent Events (SSE) for real-time updates
- **Server**: Binds to `localhost:4096` by default; clients discover via mDNS, env vars, or direct URL
- **Event bus**: `Bus.emit()` / `Bus.subscribe()` — events include `session.created`, `message.part`, `permission.asked`, `lsp.diagnostics`
- **Monorepo**: 19+ Bun workspace packages (core, SDK, TUI, desktop, web, Slack bot, enterprise)

Clients:
1. **TUI** — SolidJS rendered in terminal via OpenTUI (in-process with server)
2. **Desktop** — Tauri and Electron wrappers embedding the web app
3. **Web** — Browser-based session viewer
4. **VS Code extension** — keybind integration (`Cmd+Esc`), terminal embedding
5. **Slack bot** — Bolt-based integration

### Split Pane Layout

The TUI implements a **page-based navigation** system with overlay dialogs:

- **Chat page** (primary): Split into message display area (scrollable conversation history) + editor pane (multiline input) + status bar showing agent state, model, context window usage percentage
- **Sidebar**: Toggled via `<leader>b`. Shows file changes for the current session. In the desktop app, a "Review" panel on the right displays file diffs
- **Logs page**: System activity viewing
- **Diff overlay**: Full-screen overlay for patch review with scroll + syntax highlighting. Configurable via `diff_style`: `"auto"` (adapts to terminal width) or `"stacked"` (single-column). Hunk-based navigation for reviewing changes section by section
- **11 dialog overlays**: Permission, Session, Command, Model, Init, Theme, Filepicker, Multi-Arguments, Help, Quit — rendered centered via `layout.PlaceOverlay`

The layout is **not a fixed multi-pane split** like tmux. It's a single main view (chat or logs) with toggleable sidebar and modal overlays. Dialog blocking prevents keyboard propagation to underlying components.

### LSP Integration

One of OpenCode's strongest differentiators. Supports **30+ language servers** covering: Astro, Bash, C/C++, C#, Clojure, Dart, Deno, Elixir, F#, Gleam, Go, Haskell, Java, Julia, Kotlin, Lua, Nix, OCaml, PHP, Prisma, Python, Ruby, Rust, Swift, Svelte, Terraform, Typst, TypeScript/JavaScript, Vue, YAML, Zig.

**What it provides to the AI agent:**
- **Diagnostics**: Real-time errors/warnings fed to LLM. `waitForDiagnostics()` subscribes with 3-second timeout, 150ms debounce
- **Go-to-definition**: Navigate to symbol definitions
- **Find references**: Locate all usages of a symbol
- **Hover information**: Type info and documentation
- **Document symbols**: Outline of symbols in a file
- **Call hierarchy**: Trace call chains

LSP servers auto-discover based on file extensions, spawn on demand, and run concurrently. Three aggregation query functions collect results from all active servers. Configurable per-language in `opencode.json` with `disabled`, `command`, `extensions`, `env`, `initialization` fields. `OPENCODE_DISABLE_LSP_DOWNLOAD` prevents auto-download.

### File Browser / File Picker

- **Filepicker dialog** (`Ctrl+F`): Modal file selection with fuzzy search
- **`@` mentions**: Fuzzy file search in the editor — file content added to conversation automatically
- **`!` prefix**: Execute shell commands, output added as tool result
- **Sidebar file changes**: Shows modified files for current session (toggleable)
- **Desktop app**: Full file explorer with tree view, expand/collapse, file type icons, Monaco editor with syntax highlighting

### Session Management

- **SQLite persistence**: Sessions survive terminal closure. Reconnectable from desktop/mobile apps
- **Session tree**: Sessions form a tree via `parentID`. Children inherit directory but maintain independent message history
- **Timeline view** (`<leader>g`): Visual graph/tree of all sessions for current project, showing parent-child relationships. Navigate with arrow keys, `Enter` to switch, `Shift+Enter` to fork
- **Session switcher** (`<leader>l`): List with titles, timestamps, preview text
- **Auto-compact**: At ~95% context window usage, generates conversation summary and starts new context. Token-based thresholds vary by model. Strips media attachments on overflow. Preserves last 40K tokens of tool output, replacing older ones with placeholders
- **Undo/Redo** (`<leader>u` / `<leader>r`): Git-tracked filesystem state revert. `SessionRevert.revert()` hides messages after a point and restores files
- **Session sharing**: Share sessions via links for teammate handoff
- **Export** (`<leader>x`): Markdown export of conversation

### Keybindings and Navigation

**Leader key**: `ctrl+x` (customizable in `tui.json`)

| Category | Key | Action |
|----------|-----|--------|
| **App** | `ctrl+c`, `ctrl+d`, `<leader>q` | Exit |
| **Navigation** | `<leader>b` | Toggle sidebar |
| **Navigation** | `<leader>s` | Status view |
| **Sessions** | `<leader>n` | New session |
| **Sessions** | `<leader>l` | List sessions |
| **Sessions** | `<leader>g` | Timeline (session tree) |
| **Sessions** | `<leader>x` | Export |
| **Sessions** | `<leader>c` | Compact |
| **Sessions** | `<leader>u` / `<leader>r` | Undo / Redo |
| **Sessions** | `<leader>down/right/left/up` | Navigate child/parent sessions |
| **Models** | `<leader>m` | List models |
| **Models** | `f2` / `shift+f2` | Cycle recent models |
| **Models** | `ctrl+t` | Cycle model variant |
| **Agents** | `<leader>a` | Agent list |
| **Agents** | `tab` / `shift+tab` | Cycle agents |
| **Commands** | `ctrl+p` | Command palette |
| **Editor** | `<leader>e` | External editor |
| **Editor** | `<leader>t` | Theme list |
| **Editor** | `<leader>h` | Toggle conceal (hide tool details) |
| **Editor** | `<leader>y` | Copy |
| **Scroll** | `pageup/pagedown` | Page scroll |
| **Scroll** | `ctrl+alt+u/d` | Half page up/down |
| **Scroll** | `ctrl+g` / `ctrl+alt+g` | First / Last message |
| **Input** | `return` | Submit |
| **Input** | `shift+return`, `ctrl+return`, `alt+return` | Newline |
| **Input** | `ctrl+a` / `ctrl+e` | Line home / end |
| **Input** | `alt+f` / `alt+b` | Word forward / backward |
| **Input** | `ctrl+k` / `ctrl+u` | Delete to line end / start |
| **Input** | `ctrl+w` | Delete word backward |
| **Permissions** | `a` / `A` | Allow (once / always) |
| **Permissions** | `d` | Deny |

### Theme System

- **Built-in themes**: `system` (adapts to terminal), `opencode`, `tokyonight`, `everforest`, `ayu`, `catppuccin`, `catppuccin-macchiato`, `gruvbox`, `kanagawa`, `nord`, `matrix`, `one-dark`
- **Custom themes**: JSON files in `~/.config/opencode/themes/`, `.opencode/themes/`, or project root
- **Loading hierarchy**: Built-in < user config < project < cwd (later overrides earlier)
- **Color support**: Hex (`#ffffff`), ANSI 0-255, named references, `"none"` for terminal default
- **Dark/light variants**: `{"dark": "#000", "light": "#fff"}` per color slot
- **Color slots**: primary, secondary, accent, error, warning, success, info, text, textMuted, background, backgroundPanel, backgroundElement, border variants, diff colors, markdown colors, syntax highlighting
- **Requires**: Truecolor (24-bit) terminal support
- **Runtime switching**: `<leader>t` opens theme dialog, no restart needed

### Conversation Model

- **Messages**: Rendered with speaker ID, timestamp, syntax-highlighted code blocks, inline tool calls and results
- **Streaming**: Progressive response generation with indicators
- **Markdown**: GitHub-flavored markdown rendering with CommonMark spec
- **Extended thinking**: Toggle display of model reasoning (`/thinking` command)

### Tool Call Display

- **Tool calls shown inline** within messages with operation details
- **Known issue**: `renderToolTitle()` only shows the `description` parameter, not the actual command — e.g., bash tool calls show description text but hide the command being run
- **Toggle conceal** (`<leader>h`): Show/hide detailed tool information
- **`/details` command**: Control tool result visibility
- **Permission dialog**: Modal overlay when tools require approval (bash, file edit)
- **Bash streaming**: Output streamed to client while tool runs

### Diff Display

- **Inline diffs**: File modifications shown within conversation
- **Full-screen diff overlay**: Dedicated patch review with syntax colors + scroll
- **`diff_style` config**: `"auto"` (side-by-side when terminal wide enough) or `"stacked"` (always single-column)
- **Hunk navigation**: Section-by-section review
- **Context lines**: Surrounding code for understanding

### Agent System

- **Primary agents**: `Build` (default, all tools), `Plan` (restricted, analysis-only)
- **Subagents**: `General` (full tools, multi-step research), `Explore` (read-only codebase exploration)
- **Hidden system agents**: Compaction, Title, Summary
- **Custom agents**: Via `opencode.json` or markdown files in `.opencode/agents/`
- **Agent config fields**: mode, model, prompt, description, temperature, top_p, steps (max iterations), tools, permission, color, hidden
- **Per-agent model override**: Format `provider/model-id`
- **Per-agent tool restrictions**: Enable/disable specific tools, bash command glob patterns
- **Multi-agent coordination**: In-process message passing via inbox JSONL. Lead agent spawns teammates, each with own context window
- **Agent cycling**: `Tab` / `Shift+Tab` in TUI, `@mention` for inline invocation

### Unique Features

1. **75+ provider support** via Models.dev + direct integrations (Anthropic, OpenAI, Google, Bedrock, Groq, Azure, OpenRouter, Ollama, LM Studio, etc.)
2. **Multi-client architecture**: Same session accessible from TUI, desktop, web, mobile, Slack
3. **HTTP API + SDK**: RESTful API with OpenAPI 3.1 spec, TypeScript SDK for programmatic control
4. **Persistent server mode**: Eliminates MCP cold boot times on reconnection
5. **LSP integration** feeding real-time diagnostics to AI (unique among terminal coding agents)
6. **Session timeline tree** with visual branching and forking
7. **Parallel agents** running on same project simultaneously
8. **Plugin system**: Custom tools, lifecycle hooks, event subscriptions via `@opencode-ai/plugin`
9. **OpenTUI**: Custom Zig-based terminal rendering (faster than Bubble Tea or Ink)
10. **Desktop app** via Tauri with full file explorer and Monaco editor

---

## Amp (Sourcegraph)

**Website**: [ampcode.com](https://ampcode.com/)
**Company**: Sourcegraph
**Install**: `npm install -g @sourcegraph/amp`
**Interfaces**: CLI, VS Code extension, JetBrains IDEs, Neovim
**Pricing**: Free tier ($10/day ad-supported), pay-as-you-go, Enterprise (50% premium)

### Architecture

Amp is a **server-side-first** coding agent — threads and state live on Sourcegraph's servers (accessible at `ampcode.com/threads`). The CLI and IDE extensions are clients that communicate with the backend.

- **Agent modes**: `smart` (Claude Opus 4.6 + GPT-5.4 oracle), `rush` (faster/cheaper for defined tasks), `deep` (GPT-5.3-Codex + GPT-5.4 oracle)
- **Model routing**: Automatic model selection per task; users can request specific models
- **AGENTS.md compatibility**: Reads both `AGENTS.md` and `CLAUDE.md` for project instructions

### Compact Streaming / Tool Call Display

Amp's CLI is a **chat-based REPL** (not a TUI application with panes). Interaction is linear: user types, agent responds with interleaved text and tool calls.

- **`--stream-json` flag**: Outputs one JSON object per line for programmatic integration (Claude Code compatible format)
- **`--stream-json-thinking`**: Includes thinking blocks in stream
- **ANSI rendering**: Progress bars and escape codes render properly; only final output sent to model (not intermediate frames)
- **Tool calls**: Displayed inline during streaming. Built-in commands (git status, npm test, cargo build) run without prompting via built-in allow rules
- **No explicit collapse/expand UI**: Tool calls stream as they execute. There is no accordion-style collapse/expand mechanism in the CLI (this is a VS Code extension feature)

### Thread Model

Threads are the core organizing primitive — persistent conversations containing messages, context, file changes, and tool calls.

- **Server-side storage**: All threads uploaded to Sourcegraph servers automatically
- **Visibility controls**: private, workspace-shared, unlisted, public
- **Thread referencing**: `@thread-url` or `@thread-id` to reference other threads. A secondary model extracts relevant info from the referenced thread
- **Thread archiving**: Hide from active list but keep accessible
- **Thread forking**: Branch from any point in a conversation
- **Message editing**: Up arrow to edit prior messages; `e` to edit (resets thread to that point), `r` to restore (removes message)
- **Message queueing**: `Cmd-Shift-Enter` queues messages to execute after current agent turn completes

### Thread Map

Accessed via command palette (`threads: map`). CLI-only feature.

- Visualizes **all threads connected to current thread** via mentions, handoffs, or forks
- **Top-down hierarchical view** of thread relationships
- Navigate with arrow keys, `Enter` to open selected thread
- **Structural patterns**: Hub-and-spokes (central thread + branches for parallel work), Chain (sequential threads for dependent changes)

### Multi-File Context Management

- **`@` mentions**: Type `@` + filename parts, press return. Files truncated to max 500 lines and 2KB per line. Binary files ignored; images attached as images
- **Shell mode**: Prefix with `$` to execute commands; output enters context. `$$` for incognito (no context inclusion)
- **AGENTS.md files**: Project guidance files in roots, parents, subtrees. Support `@`-mentions of other files, glob-pattern scoped instructions via YAML frontmatter
- **Context composition**: System prompt + tool definitions + AGENTS.md + environment (OS, directory, open files) + conversation
- **Context window**: Up to 200K tokens (Claude Opus 4.6)
- **Quality principle**: "Everything in context affects output" — shorter, focused threads yield better results

### Handoff (Superior Compaction)

Instead of in-place compaction, Amp uses **handoff** — creating a new thread from an existing one:

- User provides guidance (e.g., "now implement for teams")
- Secondary model analyzes source thread, identifies relevant files and information
- Generates a new thread prompt that user can **edit before starting**
- Preserves essential context without compaction artifacts
- Results in cleaner, more focused follow-up threads

### Approval / Permission Model

Three-level matching system (highest priority wins):

1. **User rules** (highest): Custom allow/deny/ask/delegate rules
2. **Built-in rules**: Common commands pre-allowed (git, npm, cargo, etc.). View via `amp permissions list --builtin`
3. **Default**: Reject anything not matched

Rule configuration:
- `allow`: Execute without prompting
- `reject`: Block execution
- `ask`: Prompt user for approval
- `delegate`: Invoke external helper script (receives `AGENT_TOOL_NAME` env var, arguments on stdin)

Workspace settings (`.amp/settings.json`) require explicit approval before MCP servers can run. Global settings and `--mcp-config` servers do not.

### Plan Generation and Display

- Amp **plans multi-step tasks** automatically, breaking them into subtasks
- Shows **what it's doing and why** during execution
- No explicit "plan mode" like Claude Code's `/plan` — planning is integrated into the agent loop
- Subagents handle parallel execution of plan steps

### Subagent System

- **Task tool**: Main agent spawns independent mini-Amps with isolated context windows
- **Use cases**: Multi-step tasks broken into independent parts, parallel work across different code areas, keeping main thread clean
- **Limitations**: Subagents cannot communicate with each other; main agent receives only final summaries
- **Oracle** (GPT-5.4 with reasoning=high): "Second opinion" model for complex analysis, debugging, architecture decisions. Slower and costlier; must be explicitly requested
- **Librarian**: Searches public/private GitHub repos and Bitbucket Enterprise. Requires PATs for Bitbucket. Default branches only
- **Painter** (Gemini 3 Pro Image): Generates/edits images — mockups, icons, redactions. Up to 3 reference images
- **Course Correction Agent**: Parallel validation running on every inference (mentioned in some sources, details sparse)

### Skills System

Replaces custom commands. Packages of instructions + resources.

- **Location**: `.agents/skills/` (project) or `~/.config/agents/skills/` (user-wide)
- **Format**: Directory with `SKILL.md` containing YAML frontmatter (`name`, `description`)
- **Install**: Via command palette, GitHub URLs, git URLs, or local paths
- **MCP bundling**: Skills can include `mcp.json` files — MCP servers load only when skill activates (keeps tool count manageable)
- **Built-in skill**: `building-skills` creates new skills via natural language

### Code Review & Checks

- **`amp review`**: CLI command spawning separate subagents for each check
- **In-thread reviews**: Natural language requests ("review changes since diverging from main")
- **Parallel reviews**: Editor extension supports multiple concurrent reviews
- **Checks framework**: User-defined invariants in `.agents/checks/` directories
  - YAML frontmatter: `name`, `description`, `severity-default`, `tools`
  - Scoped to subtrees (root = global, subdirectory = local)
  - Each check runs in isolated subagent with limited tool access
  - Reports: Line numbers, significance explanations, fix recommendations
  - Use cases: Performance anti-patterns, security invariants, deprecated API migration, style conventions, compliance

### Keybindings (CLI)

| Key | Action |
|-----|--------|
| `Ctrl+O` | Command palette |
| `Ctrl+G` | Open prompt in `$EDITOR` |
| `Ctrl+S` | Switch mode (smart/rush/deep) |
| `Ctrl+R` | History |
| `Ctrl+V` | Paste image from clipboard |
| `Up/Down` | Navigate/edit prior messages |
| `Alt+T` | Expand thinking blocks |
| `@` | File mention |
| `$` | Shell mode |
| `$$` | Incognito shell mode |
| `Shift+Enter` | Newline (in supported terminals) |
| `Cmd/Ctrl+Enter` | Submit message |

### Theme System

- **Built-in themes**: `terminal`, `dark`, `light`, `catppuccin-mocha`, solarized variants, `gruvbox`, `nord`
- **Custom themes**: `~/.config/amp/themes/<name>/colors.toml`
- **Config**: `amp.terminal.theme` in settings

### Configuration

- **Settings files**: `~/.config/amp/settings.json` (global), `.amp/settings.json` (workspace)
- **Key settings**: `amp.anthropic.thinking.enabled`, `amp.permissions`, `amp.mcpServers`, `amp.defaultVisibility`, `amp.terminal.theme`, `amp.agent.deepReasoningEffort`
- **Managed settings** (Enterprise): System-level policy overrides at `/etc/ampcode/managed-settings.json` (Linux)

### Toolboxes (Custom Tools)

Simple executables exposed as tools:

- Scripts in `$AMP_TOOLBOX` directories
- Self-describe via `TOOLBOX_ACTION=describe` (key-value metadata output)
- Execute via `TOOLBOX_ACTION=execute` (parameters on stdin)
- Simpler than MCP — just executables

### Unique Features

1. **Thread Map**: Visual graph of connected threads (forks, handoffs, mentions)
2. **Handoff**: Context-preserving thread creation (superior to `/compact`)
3. **Message queueing**: Queue next message while agent is working
4. **Oracle subagent**: Dedicated reasoning model for complex analysis (GPT-5.4)
5. **Librarian**: Cross-repo code search via Sourcegraph infrastructure
6. **Painter**: Image generation/editing subagent
7. **Checks framework**: Scoped, user-defined review criteria with isolated subagent execution
8. **Toolboxes**: Simple executable-as-tool system
9. **`delegate` permission**: Route approval decisions to external scripts
10. **Server-side threads**: Cross-device, team-shared conversation state
11. **Thread referencing**: Pull context from other threads via secondary model extraction
12. **Public developer profiles**: Shareable coding sessions
13. **AGENTS.md glob scoping**: YAML frontmatter restricts instructions to matching files
14. **IDE diagnostic reading**: Reads diagnostics from VS Code/JetBrains for context

---

## Community Comparisons

### OpenCode vs Claude Code

| Dimension | OpenCode | Claude Code |
|-----------|----------|-------------|
| **Model lock-in** | 75+ providers, BYOK | Anthropic only |
| **Interface** | Native TUI + desktop + web + Slack | CLI REPL + VS Code extension |
| **LSP** | 30+ servers, diagnostics fed to AI | Limited LSP integration |
| **Session persistence** | SQLite, survives terminal closure | In-session only, checkpoint system |
| **Themes** | 11+ built-in, full JSON customization | None |
| **Context management** | Auto-compact at 95%, tool output pruning | Auto-compact, `/compact [instructions]` |
| **Multi-agent** | Parallel agents, in-process coordination | Task subagent, sequential |
| **Cost** | Free (MIT), bring own API keys | $20/mo Pro, $100/mo Max, or API |
| **GitHub stars** | ~112K | ~71K |
| **Daily commits** | — | 135K/day (4% of all public GitHub commits) |
| **SWE-bench** | Depends on model | 59% |

Community sentiment (Reddit, HN): "The most productive developers use both" — Claude Code for fast implementation, OpenCode for model flexibility and terminal-heavy workflows.

### Amp vs Claude Code

| Dimension | Amp | Claude Code |
|-----------|-----|-------------|
| **Thread model** | Server-side, persistent, shareable, forkable | Local, session-based |
| **Context strategy** | Handoff (new thread) > compact | In-place `/compact` |
| **Subagents** | Oracle, Librarian, Painter, Task | Task, Explore |
| **Code review** | Dedicated `amp review` + checks framework | `/review-pr` slash command |
| **Permission model** | 3-level with delegate-to-script | Allow/deny per tool |
| **Model flexibility** | Multi-model (Claude, GPT, Gemini) | Anthropic only |
| **Pricing** | Free tier ($10/day) + pay-as-you-go | Subscription or API |
| **Privacy** | Threads on Sourcegraph servers | Local only |
| **Team features** | Shared threads, workspace visibility | None native |

Quote from developer: "I pay for Claude Code MAX. Amp is better at coding. It understood the codebase better and hallucinated less."

### OpenCode vs Amp

| Dimension | OpenCode | Amp |
|-----------|----------|-----|
| **Architecture** | Local server, multi-client | Cloud-first, CLI client |
| **TUI** | Rich SolidJS/OpenTUI with sidebar, overlays | Chat REPL (no split panes) |
| **LSP** | 30+ servers integrated | None (reads IDE diagnostics) |
| **Threads** | Local sessions with tree structure | Server-side threads with thread map |
| **Privacy** | Fully local | Threads on Sourcegraph servers |
| **Subagents** | General, Explore, custom agents | Oracle, Librarian, Painter, Task |
| **License** | MIT open source | Proprietary |
| **Code review** | Community plugins | Built-in checks framework |

---

## Key Takeaways

### Features Worth Studying for Skaffen/Demarch

**From OpenCode:**
- **LSP integration feeding diagnostics to AI** — unique differentiator, reduces hallucinated type errors. The 30+ server auto-discovery is impressive
- **Session timeline tree with visual branching** — branching conversations let users explore alternatives without losing history
- **Multi-client architecture** — same session from TUI, desktop, web, mobile is powerful for workflow continuity
- **Theme system with JSON customization and dark/light variants** — high-polish developer experience
- **OpenTUI (Zig core + SolidJS reconciler)** — custom terminal renderer outperforming Bubble Tea. Worth investigating for Skaffen's Go TUI
- **Agent system with per-agent model/tool restrictions** — enables specialized agents without code changes
- **Persistent server mode eliminating MCP cold boot** — significant UX improvement for multi-server setups

**From Amp:**
- **Handoff > compact** — creating a new focused thread beats in-place summarization. User can edit the handoff prompt before starting
- **Thread Map visualization** — seeing the graph of connected threads (forks, handoffs, references) is a navigation breakthrough
- **Message queueing** — queue next message while agent works. Simple but high-value for power users
- **Checks framework** — user-defined review criteria with isolated subagent execution. Composable, scoped, versionable
- **Toolboxes** — dead-simple tool creation (just executables) vs MCP server complexity
- **`delegate` permission action** — routing approval to external scripts enables policy-as-code
- **Oracle subagent pattern** — dedicated expensive reasoning model for complex decisions
- **AGENTS.md glob scoping** — restricting instructions to matching file types via YAML frontmatter

### Design Tensions to Watch

1. **Local vs cloud state**: OpenCode is fully local (privacy); Amp is cloud-first (collaboration). Both have tradeoffs
2. **Rich TUI vs simple REPL**: OpenCode invests in split panes, overlays, themes; Amp keeps CLI minimal and invests in server-side features. Community divided on which matters more
3. **Model freedom vs model optimization**: OpenCode supports 75+ providers but can't optimize for any; Amp picks models per task but limits choice
4. **LSP integration cost**: OpenCode's 30+ server management is complex. Worth the accuracy gains but significant engineering surface area

### Gaps in Both

- Neither has **live terminal multiplexing** (watching agent run commands in a split pane, a la tuivision)
- Neither has **persistent cross-session memory** beyond conversation history (no learning/adaptation layer)
- Neither has **structured plan visualization** (Gantt, dependency graph) — plans are just text
- Neither has **cost-aware model routing** (choosing cheaper models for simple subtasks automatically)
- OpenCode's tool call display hides actual commands (known issue)
- Amp's server-side thread storage is a dealbreaker for security-conscious teams

---

## Sources

- [OpenCode GitHub (anomalyco/opencode)](https://github.com/anomalyco/opencode)
- [OpenCode Docs: TUI](https://opencode.ai/docs/tui/)
- [OpenCode Docs: Keybinds](https://opencode.ai/docs/keybinds/)
- [OpenCode Docs: LSP](https://opencode.ai/docs/lsp/)
- [OpenCode Docs: Themes](https://opencode.ai/docs/themes/)
- [OpenCode Docs: Tools](https://opencode.ai/docs/tools/)
- [OpenCode Docs: Agents](https://opencode.ai/docs/agents/)
- [DeepWiki: OpenCode TUI Architecture](https://deepwiki.com/opencode-ai/opencode/4-terminal-ui-system)
- [DeepWiki: OpenCode Overview (anomalyco)](https://deepwiki.com/anomalyco/opencode)
- [Amp Manual](https://ampcode.com/manual)
- [Amp: Context Management Guide](https://ampcode.com/guides/context-management)
- [Amp: Thread Map](https://ampcode.com/news/thread-map)
- [Amp: Liberating Code Review](https://ampcode.com/news/liberating-code-review)
- [Amp: Agents for the Agent](https://ampcode.com/notes/agents-for-the-agent)
- [Amp: Terminal Improvements](https://ampcode.com/news/terminal)
- [Amp: Towards a New CLI](https://ampcode.com/news/towards-a-new-cli)
- [Sourcegraph Amp](https://sourcegraph.com/amp)
- [Aider vs OpenCode (NxCode)](https://www.nxcode.io/resources/news/aider-vs-opencode-ai-coding-cli-2026)
- [OpenCode vs Claude Code (MorphLLM)](https://www.morphllm.com/comparisons/opencode-vs-claude-code)
- [I Switched From Claude Code to OpenCode (Thomas Wiegold)](https://thomas-wiegold.com/blog/i-switched-from-claude-code-to-opencode/)
- [Amp Code AI Review 2026 (Second Talent)](https://www.secondtalent.com/resources/amp-ai-review/)
- [Sourcegraph Amp in 5 Minutes (Zoltan Bourne)](https://zoltanbourne.substack.com/p/early-preview-of-amp-the-new-ai-coding)
- [Amp vs Claude Code for Infra (Isaac Flath)](https://elite-ai-assisted-coding.dev/p/amp-vs-claude-code-for-infra)
- [Amp Notes (Hamel Husain)](https://hamel.dev/notes/coding-agents/amp.html)
- [Context Compaction Research Gist](https://gist.github.com/badlogic/cd2ef65b0697c4dbe2d13fbecb0a0a5f)
- [OpenCode vs Claude Code vs Codex (ByteBridge/Medium)](https://bytebridge.medium.com/opencode-vs-claude-code-vs-openai-codex-a-comprehensive-comparison-of-ai-coding-assistants-bd5078437c01)
- [Tembo: 2026 Guide to Coding CLI Tools](https://www.tembo.io/blog/coding-cli-tools-comparison)
