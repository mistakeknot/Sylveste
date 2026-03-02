---
name: clavain
description: "Self-improving agent rig: codifies product and engineering discipline into composable workflows from brainstorm to ship. Compounds knowledge, generates domain agents, and monitors its own docs. Orchestrates Claude, Codex, and GPT-5.2 Pro through 4 agents, 47 commands, 16 skills, 1 MCP server. Companions: interspect, interphase, interline, interflux, interpath, interwatch, interslack, interform, intercraft, interdev, interpeer, intertest."
---
# Gemini Skill: clavain

You have activated the clavain capability.

## Base Instructions
# Clavain — Development Guide

## Canonical References
1. [`PHILOSOPHY.md`](../../PHILOSOPHY.md) — direction for ideation and planning decisions.
2. `CLAUDE.md` — implementation details, architecture, testing, and release workflow.

## Philosophy Alignment Protocol
Review [`PHILOSOPHY.md`](../../PHILOSOPHY.md) during:
- Intake/scoping
- Brainstorming
- Planning
- Execution kickoff
- Review/gates
- Handoff/retrospective

For brainstorming/planning outputs, add two short lines:
- **Alignment:** one sentence on how the proposal supports the module's purpose within Demarch's philosophy.
- **Conflict/Risk:** one sentence on any tension with philosophy (or 'none').

If a high-value change conflicts with philosophy, either:
- adjust the plan to align, or
- create follow-up work to update `PHILOSOPHY.md` explicitly.


Autonomous software agency — orchestrates the full development lifecycle from problem discovery through shipped code using heterogeneous AI models. Layer 2 (OS) in the Demarch stack: sits between Intercore (L1 kernel) for state management and Autarch (L3 apps) for TUI rendering. Originated from [superpowers](https://github.com/obra/superpowers), [superpowers-lab](https://github.com/obra/superpowers-lab), [superpowers-developing-for-claude-code](https://github.com/obra/superpowers-developing-for-claude-code), and [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin).

## Quick Reference

| Item | Value |
|------|-------|
| Repo | `https://github.com/mistakeknot/Clavain` |
| Namespace | `clavain:` |
| Manifest | `.claude-plugin/plugin.json` |
| Components | 16 skills, 4 agents, 47 commands, 8 hooks, 1 MCP server |
| License | MIT |
| Layer | L2 (OS) — depends on Intercore (L1), consumed by Autarch (L3) |

### North Star for New Work

- Improve at least one frontier axis: orchestration, reasoning quality, or token efficiency.
- Avoid measurable regressions on the other two axes unless offset by a larger quantified gain.
- Prefer changes with observable signals in routing, review precision, or resource-to-outcome ratio.

### Release workflow

- Run `scripts/bump-version.sh <version>` (or `/interpub:release <version>` in Claude Code) for any released changes.
- The bump updates these files atomically:
  - `.claude-plugin/plugin.json`
  - `infra/marketplace/.claude-plugin/marketplace.json`
  - other discovered versioned artifacts
- The command commits and pushes both plugin and marketplace repos.
- For routine updates, use patch bumps (`0.6.x -> 0.6.x+1`).

## Runbooks

- Codex sync operations: `docs/runbooks/codex-sync.md`
- Optional automated Codex refresh job: `scripts/codex-auto-refresh.sh` (cron/systemd/launchd examples in `docs/runbooks/codex-sync.md`)
- GitHub web PR agent commands (`/clavain:claude-review`, `/clavain:codex-review`, `/clavain:dual-review`) are documented in `docs/runbooks/codex-sync.md`
- GitHub issue command `/clavain:upstream-sync` (for `upstream-sync` issues) is documented in `docs/runbooks/codex-sync.md`

## Architecture

```
Clavain/
├── .claude-plugin/plugin.json     # Plugin manifest (name, version, MCP servers)
├── skills/                        # 16 discipline skills (ls skills/*/SKILL.md)
├── agents/
│   ├── review/                    # 2: plan-reviewer, data-migration-expert
│   └── workflow/                  # 2: bug-reproduction-validator, pr-comment-resolver
├── commands/                      # 47 slash commands (ls commands/*.md)
│   └── interpeer.md              # Quick cross-AI peer review (+ 45 others)
├── hooks/                         # 7 active hooks + 8 lib-*.sh libraries
│   ├── hooks.json                 # Hook registration (4 event types, 6 bindings)
│   └── lib-*.sh                   # Shared: intercore, sprint, signals, spec, verdict, gates, discovery
├── cmd/clavain-cli/               # Go CLI binary (budget, checkpoint, claim, phase, sprint)
├── config/                        # Agency specs, fleet registry, routing config
├── scripts/                       # bump-version, orchestrate.py, dispatch, fleet management
├── tests/                         # structural (pytest), shell (bats-core), smoke (subagent)
└── .github/workflows/             # CI: eval, sync, test, secret-scan, upstream-check
```

## How It Works

### SessionStart Hook

On every session start, resume, clear, or compact, the `session-start.sh` hook:

1. Reads `skills/using-clavain/SKILL.md`
2. JSON-escapes the content
3. Outputs `hookSpecificOutput.additionalContext` JSON
4. Claude Code injects this as system context

This means every session starts with the 3-layer routing table, so the agent knows which skill/agent/command to invoke for any task.

### 3-Layer Routing

The `using-clavain` skill provides a routing system:

1. **Stage** — What phase? (explore / plan / execute / debug / review / ship / meta)
2. **Domain** — What kind of work? (code / data / deploy / docs / research / workflow / design / infra)
3. **Concern** — What review concern? (architecture / safety / correctness / quality / user-product / performance)

Each cell maps to specific skills, commands, and agents.

### Component Types

| Type | Location | Format | Triggered By |
|------|----------|--------|-------------|
| **Skill** | `skills/<name>/SKILL.md` | Markdown with YAML frontmatter (`name`, `description`) | `Skill` tool invocation |
| **Agent** | `agents/<category>/<name>.md` | Markdown with YAML frontmatter (`name`, `description`, `model`) | `Task` tool with `subagent_type` |
| **Command** | `commands/<name>.md` | Markdown with YAML frontmatter (`name`, `description`, `argument-hint`) | `/clavain:<name>` slash command |
| **Hook** | `hooks/hooks.json` + scripts | JSON registration + bash scripts | Automatic on registered events |
| **MCP Server** | `.claude-plugin/plugin.json` `mcpServers` | JSON config | Automatic on plugin load |

### Interspect Routing Overrides

Interspect (companion plugin) monitors flux-drive agent dispatches and user corrections. When evidence reaches a threshold, it proposes permanent routing overrides stored in `.claude/routing-overrides.json`. See the interspect plugin's own AGENTS.md for full details on commands (`/interspect:propose`, `/interspect:revert`, `/interspect:status`), library functions, and canary monitoring.

## Component Conventions

### Skills

- One directory per skill: `skills/<kebab-case-name>/SKILL.md`
- YAML frontmatter: `name` (must match directory name) and `description` (third-person, with trigger phrases)
- Body written in imperative form ("Do X", not "You should do X")
- Keep SKILL.md lean (1,500-2,000 words) — move detailed content to sub-files
- Sub-resources go in the skill directory: `examples/`, `references/`, helper `.md` files
- Description should contain specific trigger phrases so Claude matches the skill to user intent

Example frontmatter:
```yaml
---
name: refactor-safely
description: Use when performing significant refactoring — guides a disciplined process that leverages duplication detection, characterization tests, staged execution, and continuous simplicity review
---
```

### Agents

- Flat files in category directories: `agents/review/`, `agents/workflow/`
- YAML frontmatter: `name`, `description` (with `<example>` blocks showing when to trigger), `model` (usually `inherit`)
- Description must include concrete `<example>` blocks with `<commentary>` explaining WHY to trigger
- System prompt is the body of the markdown file
- Agents are dispatched via `Task` tool — they run as subagents with their own context

Categories:
- **review/** — Review specialists (2): plan-reviewer and data-migration-expert. The 7 core fd-* agents live in the **interflux** companion plugin. The agent-native-reviewer lives in **intercraft**.
- **workflow/** — Process automation (2): PR comments, bug reproduction

### Renaming/Deleting Agents

Grep sweep checklist (10 locations): `agents/*/`, `skills/*/SKILL.md`, `commands/*.md`, `hooks/*.sh`, `hooks/lib-*.sh`, `plugin.json`, `CLAUDE.md`, `AGENTS.md`, dispatch templates, test fixtures. Do NOT update historical records (solution docs, sprint logs).

### Commands

- Flat `.md` files in `commands/`
- YAML frontmatter: `name`, `description`, `argument-hint` (optional)
- Body contains instructions FOR Claude (not for the user)
- Commands can reference skills: "Use the `clavain:writing-plans` skill"
- Commands can dispatch agents: "Launch `Task(interflux:review:fd-architecture)`"
- Invoked as `/clavain:<name>` by users

### Hooks

- Registration in `hooks/hooks.json` — specifies event, matcher regex, and command
- Scripts in `hooks/` — use `${CLAUDE_PLUGIN_ROOT}` for portable paths
- **SessionStart** (matcher: `startup|resume|clear|compact`):
  - `session-start.sh` — injects `using-clavain` skill content, interserve behavioral contract (when active), upstream staleness warnings. Sources `sprint-scan.sh` for sprint awareness.
- **PostToolUse** (matcher: `Edit|Write|MultiEdit|NotebookEdit`):
  - `interserve-audit.sh` — logs source code writes when interserve mode is active (audit only, no denial)
- **PostToolUse** (matcher: `Edit|Write|MultiEdit`):
  - `catalog-reminder.sh` — reminds about catalog updates when components change
- **PostToolUse** (matcher: `Bash`):
  - `auto-publish.sh` — detects `git push` in plugin repos, auto-bumps patch version if needed, syncs marketplace (60s TTL sentinel prevents loops)
  - `bead-agent-bind.sh` — binds agent identity to beads claimed with bd update/claim (warns on overlap, notifies other agent)
- **Stop**:
  - `auto-stop-actions.sh` — unified post-turn actions: detects signals via lib-signals.sh, weight >= 4 triggers /clavain:compound, weight >= 3 triggers /interwatch:watch
- **SessionEnd**:
  - `dotfiles-sync.sh` — syncs dotfile changes at end of session
- Scripts must output valid JSON to stdout
- Use `set -euo pipefail` in all hook scripts

### Hook Libraries

Sourced by hook scripts, not registered as hooks themselves:

| Library | Purpose |
|---------|---------|
| `lib.sh` | Shared utilities (escape_for_json, plugin path discovery) |
| `lib-intercore.sh` | Intercore CLI wrappers (ic run/state/sprint/coordination) |
| `lib-sprint.sh` | Sprint state queries (phase, gate, budget, artifact) |
| `lib-signals.sh` | Signal detection engine for auto-stop-actions |
| `lib-spec.sh` | Agency spec loader — reads `config/agency-spec.yaml` at runtime |
| `lib-verdict.sh` | Verdict file write/read utilities for structured agent handoffs |
| `lib-gates.sh` | Phase gate shim — delegates to interphase when installed, no-op stub otherwise |
| `lib-discovery.sh` | Plugin discovery shim — delegates to interphase when installed, no-op stub otherwise |

## Adding Components

### Add a Skill

1. Create `skills/<name>/SKILL.md` with frontmatter
2. Add to the routing table in `skills/using-clavain/SKILL.md` (appropriate stage/domain row)
3. Add to `plugin.json` skills array
4. Update `README.md` skills table

### Add an Agent

1. Create `agents/<category>/<name>.md` with frontmatter including `<example>` blocks
2. Add to the routing table in `skills/using-clavain/SKILL.md`
3. Reference from relevant commands if applicable
4. Update `README.md` agents list

### Add a Command

1. Create `commands/<name>.md` with frontmatter
2. Add to `plugin.json` commands array
3. Reference relevant skills in the body
4. Update `README.md` commands table

### Add an MCP Server

1. Add to `mcpServers` in `.claude-plugin/plugin.json`
2. Document required environment variables in README

## Validation Checklist

When making changes, verify:

- [ ] Skill `name` in frontmatter matches directory name
- [ ] All `clavain:` references point to existing skills/commands (no phantom references)
- [ ] Agent `description` includes `<example>` blocks with `<commentary>`
- [ ] Command `name` in frontmatter matches filename (minus `.md`)
- [ ] `hooks/hooks.json` is valid JSON
- [ ] All hook scripts pass `bash -n` syntax check
- [ ] No references to dropped namespaces (`superpowers:`, `compound-engineering:`)
- [ ] No references to dropped components (Rails, Ruby, Every.to, Figma, Xcode)
- [ ] Routing table in `using-clavain/SKILL.md` is consistent with actual components

Quick validation:
```bash
# Count components
echo "Skills: $(ls skills/*/SKILL.md | wc -l)"      # Should be 16
echo "Agents: $(ls agents/{review,workflow}/*.md | wc -l)"  # Should be 4
echo "Commands: $(ls commands/*.md | wc -l)"        # Should be 47

# Check for phantom namespace references
grep -r 'superpowers:' skills/ agents/ commands/ hooks/ || echo "Clean"
grep -r 'compound-engineering:' skills/ agents/ commands/ hooks/ || echo "Clean"

# Validate JSON
python3 -c "import json; json.load(open('.claude-plugin/plugin.json')); print('Manifest OK')"
python3 -c "import json; json.load(open('hooks/hooks.json')); print('Hooks OK')"

# Syntax check all hook scripts
for f in hooks/*.sh; do bash -n "$f" && echo "$(basename $f) OK"; done

# Run structural tests
uv run -m pytest tests/structural/ -v
```

## Modpack — Companion Plugins

Clavain is a modpack: an opinionated integration layer that configures companion plugins into a cohesive engineering rig. It doesn't duplicate their capabilities — it routes to them and wires them together.

### Required

These must be installed for Clavain to function fully.

| Plugin | Source | Why Required |
|--------|--------|-------------|
| **context7** | claude-plugins-official | Runtime doc fetching. Clavain's MCP server. Skills use it to pull upstream docs without bundling them. |
| **explanatory-output-style** | claude-plugins-official | Educational insights in output. Injected via SessionStart hook. |

### Companion Plugins

Extracted subsystems that Clavain delegates to via namespace routing.

| Plugin | Source | What It Provides |
|--------|--------|-----------------|
| **interflux** | interagency-marketplace | Multi-agent review + research engine. 7 fd-* review agents, 5 research agents, flux-drive/flux-research skills, qmd + exa MCP servers. |
| **interphase** | interagency-marketplace | Phase tracking, gates, and work discovery. lib-phase.sh, lib-gates.sh, lib-discovery.sh. Clavain shims delegate to interphase when installed. |
| **interspect** | interagency-marketplace | Agent profiler — evidence collection, classification, routing overrides, canary monitoring. |
| **interline** | interagency-marketplace | Statusline renderer. Shows dispatch state, bead context, workflow phase, interserve mode. |
| **interwatch** | interagency-marketplace | Doc freshness monitoring. Auto-discovers watchable docs, detects drift via 14 signals, dispatches to interpath/interdoc for refresh. Triggered by `auto-stop-actions.sh` when signal weight >= 3. |

### Recommended

These enhance the rig significantly but aren't hard dependencies.

| Plugin | Source | What It Adds |
|--------|--------|-------------|
| **agent-sdk-dev** | claude-plugins-official | Agent SDK scaffolding: `/new-sdk-app` command, Python + TS verifier agents. |
| **plugin-dev** | claude-plugins-official | Plugin development: 7 skills, 3 agents including agent-creator and skill-reviewer. |
| **interdoc** | interagency-marketplace | AGENTS.md generation for any repo. |
| **tool-time** | interagency-marketplace | Tool usage analytics across sessions. |
| **security-guidance** | claude-plugins-official | Security warning hooks on file edits. Complements fd-safety agent. |
| **serena** | claude-plugins-official | Semantic code analysis via LSP-like tools. |

### Infrastructure (language servers)

Enable based on which languages you work with.

| Plugin | Language |
|--------|----------|
| **gopls-lsp** | Go |
| **pyright-lsp** | Python |
| **typescript-lsp** | TypeScript |
| **rust-analyzer-lsp** | Rust |

### Conditional (domain-specific)

| Plugin | Enable When |
|--------|------------|
| **supabase** | Working with Supabase backends |
| **vercel** | Deploying to Vercel |
| **tldrs** + **tldr-swinton** | Hitting context limits, want token-efficient exploration |
| **tuivision** | Building or testing terminal UI apps |

### Conflicts — Disabled by Clavain

Plugins that overlap with Clavain's equivalents (duplicate agents cause confusing routing):

code-review, pr-review-toolkit, code-simplifier, commit-commands, feature-dev, claude-md-management, frontend-design, hookify. Full rationale: `docs/plugin-audit.md`

## Operational Notes

### Upstream Sync
- Sync state in `upstreams.json` (commit hashes per upstream + fileMap)
- **sprint.md is canonical pipeline command** (renamed from lfg.md). lfg.md is alias
- **Post-sync checklist**: grep `compound-engineering:|/workflows:|ralph-wiggum:|/deepen-plan` in agents/commands/skills

### Interserve Dispatch
- dispatch.sh does NOT support `--template` — use `--prompt-file`
- Codex CLI v0.101.0: `--approval-mode` replaced by `-s`/`--sandbox`. Prompt is positional, NOT `-p`

### Conventions
- Uses pnpm, not npm
- `docs-sp-reference/` is read-only historical archive
- Full routing tables in `skills/using-clavain/references/routing-tables.md`
- gen-catalog.py expects pattern `\d+ skills, \d+ agents, and \d+ commands`

### Bulk Audit → Bead Creation

When creating beads from review findings, **verify each finding before creating a bead**: check `git log` for recent fixes, `bd list` for duplicates, and read current code for staleness.

## Known Constraints

- **No build step** — pure markdown/JSON/bash plugin, nothing to compile (except optional `cmd/clavain-cli/` Go binary)
- **3-tier test suite** — structural (pytest), shell (bats-core), smoke (Claude Code subagents). Run via `tests/run-tests.sh`
- **General-purpose only** — no domain-specific components (Rails, Ruby gems, Every.to, Figma, Xcode, browser-automation)
- **Trunk-based** — no branch/worktree skills; commit directly to `main`

## Upstream Tracking

6 upstreams tracked: superpowers, superpowers-lab, superpowers-dev, compound-engineering, beads, oracle. Two systems keep them in sync:

- **Check:** `upstream-check.yml` (daily cron) + `scripts/upstream-check.sh` (local). State in `docs/upstream-versions.json`.
- **Sync:** `sync.yml` (weekly cron) + `upstreams.json` (file mappings). Work dir: `.upstream-work/` (gitignored).

```bash
bash scripts/upstream-check.sh        # Local check (no file changes)
gh workflow run sync.yml               # Trigger auto-merge (creates PR)
```

## Session Completion

See root `Demarch/AGENTS.md` → "Landing the Plane" for the mandatory push workflow.


