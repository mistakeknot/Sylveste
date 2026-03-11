---
artifact_type: brainstorm
bead: none
stage: discover
---
# Skaffen Standalone TUI + Masaq Shared Library

## What We're Building

Two things:

1. **Skaffen TUI** (`os/Skaffen/internal/tui/`) — A conversational REPL that ships as the default `skaffen` experience. Claude Code-like interactive mode with best-of-breed features from the 2025-2026 agent CLI landscape. Makes Skaffen usable standalone without Autarch.

2. **Masaq** (`github.com/mistakeknot/masaq`) — A shared Bubble Tea component library providing rendering primitives that both Skaffen and Autarch consume. Named after Masaq' Orbital from Banks' *Look to Windward* — where the Culture's most beautiful experiences are rendered.

This reverses the PRD's "No TUI" non-goal (F7, line 130). The PRD already anticipated this: *"If interactive mode is needed later, bubbletea (Go-native, MIT) is the path."*

## Why This Approach

**The standalone problem:** Without a TUI, running `skaffen` gives you print-mode streaming to stdout. That's fine for CI/scripts but unusable for a human at a terminal. Requiring Autarch for interactive use creates an adoption barrier — OSS developers who `go install` Skaffen expect a Claude Code-like experience out of the box.

**The duplication problem:** Autarch already has ~48 files of Bubble Tea TUI code in `pkg/tui/`. Building Skaffen's TUI from scratch would duplicate diff rendering, markdown streaming, theming, keyboard handling, and viewport management. A shared library prevents this.

**The permission problem:** Research across 12 agent CLIs revealed that power users universally bypass approval systems (`--yolo`, `--dangerously-skip-permissions`). The friction is wrong, not the concept. Skaffen's TUI has an opportunity to get this right with smart defaults + progressive learning.

## Key Decisions

### 1. Skaffen ships with a standalone TUI (reversing PRD non-goal)

**Rationale:** All three personas need it — OSS newcomers expect interactive mode, power users want a lighter-weight alternative to Autarch, and even CI users benefit from an interactive debug mode. The PRD's RPC mode (F7) remains the primary automation interface.

**CLI modes after this change:**
- `skaffen` (default) → TUI mode (conversational REPL)
- `skaffen run --mode print` → headless streaming to stdout
- `skaffen run --mode rpc` → JSON-line protocol for IDE/CI integration

### 2. Shared TUI library: Masaq

**Repo:** `github.com/mistakeknot/masaq` (separate repo, matching Skaffen/Autarch pattern)

**Architecture:** Masaq owns rendering primitives only. It never knows about agent concepts (phases, tools, sessions). Skaffen and Autarch compose Masaq components into their own layouts.

**API pattern:** Standard Bubble Tea sub-models (Init/Update/View). Each component is a `tea.Model` that consumers embed and delegate messages to. Idiomatic, composable, minimal API surface.

```
github.com/mistakeknot/masaq/
  theme/         # Tokyo Night palette + semantic colors
  diff/          # Unified diff renderer w/ syntax highlighting (Chroma)
  markdown/      # Glamour-based streaming markdown renderer
  question/      # Full-featured structured multi-choice widget with previews
  keys/          # Keybinding framework + vim mode
  viewport/      # Flicker-free scrollable viewport
  compact/       # Compact/verbose output formatter
  styles.go      # Shared lipgloss styles

os/Skaffen/internal/tui/
  app.go         # Skaffen REPL Bubble Tea model
  chat.go        # Conversation view (composes masaq/*)
  toolcall.go    # Smart trust approval UI
  phase.go       # OODARC phase indicator + transition events
  prompt.go      # Input composer + @-mentions + slash commands

apps/Autarch/pkg/tui/
  (existing 48 files, migrated to import masaq/ after v0.2)
```

**Migration timeline:** Skaffen is the sole consumer for Masaq v0.1. APIs settle through Skaffen's development. Autarch migrates incrementally after Masaq v0.2 stabilizes.

### 3. Smart Trust: hybrid pattern rules + progressive learning

**The insight:** People use `--yolo` because existing approval UX is a net negative. Skaffen inverts this: auto-allow the 95% case, only block genuinely dangerous operations. Evidence earns authority.

**Classification pipeline:**
1. Check **learned overrides** (exact match from trust.toml) → found? use that decision
2. Check **pattern rules** (glob match against built-in + custom rules) → auto_allow / always_block / prompt_once
3. **No rule matches?** Default = prompt_once (unknown = ask, but remember answer)

**Three tiers:**

| Tier | Behavior | Examples |
|------|----------|----------|
| **Auto-allow** (never prompt) | Safe operations within project tree | read, write, edit, glob, grep, `go test`, `git status` |
| **Prompt once, remember** | Gray-area operations; user choice persists | `npm install`, write outside project, `git push` |
| **Always prompt** | Genuinely dangerous; no learning | `rm -rf`, `sudo`, network access, `.env` modifications |

**Learning UX:** After approving a prompted action, inline choice appears: `[a]lways [p]roject [s]ession [Enter=session]`. Additionally, silent approval counting: after 3 approvals of the same pattern across sessions without explicit "always", auto-promote with notification.

**Trust scope:** Three-layer cascade (session > project > global > built-in):
- `~/.skaffen/trust.toml` — global personal defaults + learned overrides
- `.skaffen/trust.toml` — project-level rules (committed to git, team-shared)
- Session overrides — ephemeral, gone on exit

**Persistence format:** TOML in dedicated `trust.toml` files (separate from config.toml for audit clarity).

### 4. v0.1 Feature Set: 12 features (3 distinctive + 9 table-stakes)

**Distinctive (why choose Skaffen):**
1. **Smart trust** — Hybrid pattern rules + progressive learning with sane defaults
2. **Structured questions** — Full-featured multi-choice with preview pane, descriptions, keyboard navigation
3. **Phase-aware REPL** — OODARC phases in status bar + transition events in chat stream

**Table-stakes (expected by users in 2026):**
4. **Streaming markdown** — Glamour-based with streaming adapter for partial markdown
5. **Inline diffs** — Unified diff with Chroma syntax highlighting, [y]/[n]/[d]/[e] keys. Word-level diff (difftastic-style) deferred to v0.2
6. **Session persistence** — JSONL sessions with smart resume picker, semantic search (CASS-style)
7. **Compact/verbose toggle** — Tool calls as one-line summaries by default, expandable on demand
8. **Git-native** — Auto-commit per edit (Aider-style), /undo = git revert, /ship = squash
9. **Slash commands** — /compact, /verbose, /phase, /advance, /undo, /commit, /sessions, /help
10. **@-file mentions** — Fuzzy file search in input composer
11. **Keyboard shortcuts** — Vim-style, customizable via config
12. **Flicker-free rendering** — Bubble Tea alternate screen, proper resize handling

**Deferred to v0.2:**
- Hooks/extensibility system
- LSP integration (OpenCode's strongest differentiator — high priority for v0.2)
- Architect/editor model split (Aider's innovation, aligns with F4 model routing)
- Voice mode
- Thread sharing (Amp's collaboration feature)
- MCP tool registration (already planned in F2 registry extension point)
- Recipes/scheduling (Goose pattern)
- Plan-as-artifact (Factory Droid spec mode)
- Word-level diff rendering (difftastic-style)
- Toggleable sidebar
- Configurable status bar items

### 5. REPL Layout: chat-first with status bar

**Screen regions:**
- **Chat viewport** (top, scrollable) — conversation history with streaming responses, tool calls, diffs, phase transitions
- **Input composer** (bottom) — multi-line prompt input with Shift+Enter, @-mentions, slash commands
- **Status bar** (very bottom) — 5 essential items: phase | model | cost | context% | turn count
  - Color-coded: phase in accent color, cost green→yellow→red, context green→yellow→red

**Tool call display:** Compact by default (one-line summaries), expandable on Enter/d. Diffs always expanded (need review). Errors always expanded. /verbose shows everything expanded.

**Phase transitions:** Appear as system messages in the chat stream with brief summary (decisions made, artifacts produced). Phase name in status bar updates live.

### 6. PRD Integration: F8

TUI becomes F8 in the Skaffen PRD, after F7 (CLI Entry Point). Dependencies: F3 (agent loop), F5 (sessions), F7 (CLI modes). F7 updated to add `--mode tui` as the default.

### 7. Naming: Masaq

From Iain M. Banks' *Look to Windward*. Masaq' Orbital is where the Culture renders its most beautiful experiences — fitting for a library that renders the visual surface of Demarch's agent ecosystem. Two syllables, Culture-universe, evocative of display/presentation.

## Competitive Research

Deep feature inventories were produced for 12+ agent CLIs and written to `docs/research/`:

| Document | Coverage |
|----------|----------|
| `2026-03-11-ai-coding-cli-tui-landscape.md` | Aider, OpenCode, Goose, Cline, Continue, Factory Droid, Cursor, Warp, Zed, Amp, Gemini CLI, Mentat |
| `2026-03-11-claude-code-tui-ux-feature-inventory.md` | Claude Code deep dive (668 lines, 20 sections) |
| `2026-03-11-openai-codex-cli-feature-inventory.md` | Codex CLI deep dive (17 sections including Ratatui architecture) |
| `2026-03-11-opencode-amp-tui-ux-research.md` | OpenCode + Amp deep dive (~500 lines, 15 takeaways for Skaffen) |

**Top insights from competitive research:**

- **Tiered permission systems** are table-stakes — every serious CLI has them. But users bypass them universally. The UX is wrong.
- **OpenCode's LSP integration** is the strongest technical differentiator across all CLIs — feeding diagnostics to the AI reduces hallucinated types. Deferred to v0.2 but high priority.
- **Amp's handoff > compact** — creating a new focused thread beats in-place summarization. Worth studying for Skaffen's session model.
- **Aider's architect/editor split** achieved SOTA benchmarks (85%). Aligns with Skaffen's F4 model routing.
- **Codex's Ratatui architecture** is the closest reference for Go Bubble Tea TUI — same paradigm, different language.
- **OpenCode rebranded to Crush and rewrote from Go/Bubble Tea to TypeScript/Zig** — signals that the Go TUI ecosystem may need custom rendering. Worth watching but Bubble Tea is still viable for v0.1.
- **Factory Droid's risk-rated autonomy** (4 tiers with Shift+Tab cycling) is the most granular approval system. Our smart trust model is philosophically different (learn vs classify) but should support manual override.
- **Gemini CLI's pixel-perfect terminal rendering** (Nov 2025 overhaul) sets the bar for flicker-free output.

## Resolved Questions

1. **Masaq Go module path:** Separate repo at `github.com/mistakeknot/masaq`. Clean boundary, independent versioning. Use `replace` directives during development.

2. **Autarch migration timeline:** Skaffen-only consumer for Masaq v0.1. Autarch migrates after Masaq v0.2 APIs stabilize.

3. **Trust persistence format:** Separate `trust.toml` files (not merged into config.toml). TOML format. Three-layer cascade: session > project > global > built-in.

4. **Bubble Tea vs custom renderer:** Start with Bubble Tea for v0.1. Evaluate at v0.2 if split panes or advanced rendering needs arise.

5. **PRD numbering:** F8: TUI Mode (new feature, depends on F3/F5/F7).

6. **Risk classification:** Hybrid pattern rules + learned overrides. No LLM in the classification loop. Deterministic, auditable.

7. **Diff rendering:** Unified diff with Chroma syntax highlighting for v0.1. Word-level (difftastic-style) deferred to v0.2.

8. **Markdown rendering:** Glamour-based with streaming buffer adapter.

9. **Question widget:** Full-featured with preview pane, descriptions, multi-select, keyboard navigation.

10. **Git integration:** Auto-commit per edit (Aider-style). /undo = git revert. /ship = squash.

11. **Session resume:** Smart picker on startup (resume/new/list), `-c` for last, `-r <id>` for specific. Semantic search for session discovery.

12. **Phase visualization:** Status bar label + phase transition events in chat stream. Optional visual progress bar deferred.

## Follow-Up Items

- **Toggleable sidebar** — investigate OpenCode's sidebar pattern for files changed, tool history, phase progress
- **Configurable status bar** — check interline plugin for options and patterns
- **Word-level diff** — evaluate difftastic Go port or tree-sitter integration for v0.2
- **Session semantic search** — integrate with CASS or build lightweight embedding search
